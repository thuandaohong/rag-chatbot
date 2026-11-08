"""
run_eval.py — Chạy bộ câu hỏi chuẩn (golden.jsonl) qua ĐÚNG pipeline của chatbot (Day 45 / E2).

Import thẳng `ask()` của backend/handler.py thay vì gọi API:
  - có NỘI DUNG các đoạn tài liệu đã retrieve (API chỉ trả tên file) -> E3 chấm groundedness
  - chạy được code trong PR trước khi deploy -> E5 eval gate
  - có sẵn token / guardrail / chi phí từng câu

Kết quả (chưa chấm điểm — E3 làm):
  eval/results/<run_id>.jsonl      mỗi câu 1 dòng
  eval/results/<run_id>.meta.json  cấu hình lần chạy + tóm tắt

Chạy:
  python eval/run_eval.py                       # đủ bộ đề, cấu hình mặc định (giống Lambda)
  python eval/run_eval.py --ids doc-01,out-02   # vài câu, đỡ tốn tiền khi thử
  python eval/run_eval.py --limit 5
  python eval/run_eval.py --env-from-lambda rag-chatbot-api   # lấy env y hệt Lambda đang chạy
"""

import argparse
import concurrent.futures as cf
import datetime as dt
import hashlib
import json
import os
import subprocess
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BACKEND = ROOT / "backend"

# Cấu hình mặc định = env của Lambda production (Terraform). Env thật của shell được ưu tiên.
DEFAULT_ENV = {
    "AWS_REGION": "us-east-1",
    "KB_ID": "PGKAMMKERL",
    "MODEL_ID": "amazon.nova-lite-v1:0",
    "TOP_K": "5",
    "GUARDRAIL_ID": "n8p73nudulzi",
    "GUARDRAIL_VERSION": "2",
}


def parse_args():
    p = argparse.ArgumentParser(description="Chạy golden dataset qua handler.ask()")
    p.add_argument("--golden", default=str(ROOT / "eval" / "golden.jsonl"))
    p.add_argument("--out", default=str(ROOT / "eval" / "results"))
    p.add_argument("--ids", help="chỉ chạy các id này, phân cách bằng dấu phẩy")
    p.add_argument("--limit", type=int, help="chỉ chạy N câu đầu")
    p.add_argument("--workers", type=int, default=3, help="số câu chạy song song (đừng để cao: throttle)")
    p.add_argument("--env-from-lambda", metavar="FUNCTION",
                   help="copy env (KB_ID, MODEL_ID, GUARDRAIL_*, PRICING_JSON...) từ Lambda đang chạy")
    return p.parse_args()


def setup_env(args) -> dict:
    """Đặt env TRƯỚC khi import handler — handler đọc env ngay lúc import.

    Quên bước này -> KeyError KB_ID, hoặc tệ hơn: chạy KHÔNG guardrail mà không báo gì
    (thiếu GUARDRAIL_ID = feature flag tắt).
    """
    env = dict(DEFAULT_ENV)
    if args.env_from_lambda:
        import boto3
        cfg = boto3.client("lambda", region_name=env["AWS_REGION"]).get_function_configuration(
            FunctionName=args.env_from_lambda)
        env.update(cfg.get("Environment", {}).get("Variables", {}))
    for k, v in env.items():
        os.environ.setdefault(k, v)  # env của shell thắng (để thử cấu hình khác: TOP_K=3 python ...)
    # Retry của boto3 qua env: tự chờ khi Bedrock trả ThrottlingException
    os.environ.setdefault("AWS_RETRY_MODE", "adaptive")
    os.environ.setdefault("AWS_MAX_ATTEMPTS", "8")
    return {k: os.environ[k] for k in env if k in os.environ}


def load_golden(args) -> list:
    rows = [json.loads(line) for line in open(args.golden, encoding="utf-8") if line.strip()]
    if args.ids:
        wanted = set(args.ids.split(","))
        rows = [r for r in rows if r["id"] in wanted]
        missing = wanted - {r["id"] for r in rows}
        if missing:
            sys.exit(f"Không có id trong golden: {sorted(missing)}")
    if args.limit:
        rows = rows[: args.limit]
    return rows


def git_info() -> dict:
    def run(*cmd):
        try:
            return subprocess.check_output(cmd, cwd=ROOT, text=True, stderr=subprocess.DEVNULL).strip()
        except (subprocess.CalledProcessError, FileNotFoundError):
            return ""
    return {"git_commit": run("git", "rev-parse", "--short", "HEAD"),
            "git_dirty": bool(run("git", "status", "--porcelain", "--", "backend", "eval"))}


def sha(text) -> str:
    data = text if isinstance(text, bytes) else text.encode("utf-8")
    return hashlib.sha256(data).hexdigest()[:12]


def run_one(handler, row: dict) -> dict:
    """1 câu hỏi -> 1 dòng kết quả. Lỗi được ghi lại, không làm hỏng cả lần chạy."""
    out = {"id": row["id"], "type": row["type"], "lang": row.get("lang"), "question": row["question"]}
    timer = handler.Timer()
    t0 = time.perf_counter()
    try:
        result = handler.ask(row["question"], timer)
    except Exception as e:  # ClientError, throttle hết lượt retry, bug...
        out.update(error=f"{type(e).__name__}: {e}", latency_ms=int((time.perf_counter() - t0) * 1000),
                   stage_ms=timer.ms)
        return out

    g_in, g_out = result["guardrail"]["input"], result["guardrail"]["output"]
    units = Counter()
    for g in (g_in, g_out):
        units.update((g or {}).get("units", {}))
    usage = result["usage"]

    out.update(
        answer=result["answer"],
        # Lưu NGUYÊN đoạn tài liệu: E3 đưa cho giám khảo hỏi "câu trả lời có nằm trong tài liệu?"
        chunks=[{
            "source": c.get("location", {}).get("s3Location", {}).get("uri", "").split("/")[-1].replace("%2B", "+"),
            "score": round(c.get("score", 0), 4),
            "text": c.get("content", {}).get("text", ""),
        } for c in result["chunks"]],
        sources=[s.split("/")[-1].replace("%2B", "+") for s in handler.extract_sources(result["chunks"])],
        guardrail_input={"action": g_in["action"], "reasons": g_in["reasons"]} if g_in else None,
        guardrail_output={"action": g_out["action"], "reasons": g_out["reasons"]} if g_out else None,
        input_tokens=usage.get("inputTokens", 0),
        output_tokens=usage.get("outputTokens", 0),
        guardrail_units=dict(units),
        stage_ms=timer.ms,
        latency_ms=int((time.perf_counter() - t0) * 1000),
        cost_usd=handler.compute_cost(usage, dict(units), 1 if "retrieve" in timer.ms else 0),
    )
    return out


def is_blocked(r: dict) -> bool:
    return any((r.get(k) or {}).get("action") == "BLOCKED" for k in ("guardrail_input", "guardrail_output"))


def summarize(results: list) -> dict:
    ok = [r for r in results if "error" not in r]
    by_type = defaultdict(lambda: {"total": 0, "answered": 0, "blocked": 0, "errors": 0, "latency_ms": []})
    for r in results:
        t = by_type[r["type"]]
        t["total"] += 1
        if "error" in r:
            t["errors"] += 1
            continue
        t["blocked" if is_blocked(r) else "answered"] += 1
        t["latency_ms"].append(r["latency_ms"])
    for t in by_type.values():
        lat = t.pop("latency_ms")
        t["avg_latency_ms"] = int(sum(lat) / len(lat)) if lat else None
    units = Counter()
    for r in ok:
        units.update(r["guardrail_units"])
    return {
        "questions": len(results),
        "errors": len(results) - len(ok),
        "by_type": dict(by_type),
        "input_tokens": sum(r["input_tokens"] for r in ok),
        "output_tokens": sum(r["output_tokens"] for r in ok),
        "guardrail_units": dict(units),
        "cost_usd": round(sum(r["cost_usd"]["total"] for r in ok), 6),
    }


def main():
    args = parse_args()
    config = setup_env(args)
    sys.path.insert(0, str(BACKEND))
    import handler  # noqa: E402 — phải import SAU setup_env

    if not handler.GUARDRAIL_ENABLED:
        print("⚠️  GUARDRAIL tắt (thiếu GUARDRAIL_ID/VERSION) — kết quả câu guardrail sẽ vô nghĩa", file=sys.stderr)

    rows = load_golden(args)
    run_id = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"Run {run_id}: {len(rows)} câu, {args.workers} workers ...", file=sys.stderr)
    t0 = time.perf_counter()
    with cf.ThreadPoolExecutor(max_workers=args.workers) as pool:  # boto3 client dùng chung giữa thread được
        results = list(pool.map(lambda r: run_one(handler, r), rows))  # map giữ đúng thứ tự đề
    elapsed = round(time.perf_counter() - t0, 1)

    with open(out_dir / f"{run_id}.jsonl", "w", encoding="utf-8") as f:
        for r in results:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    summary = summarize(results)
    meta = {
        "run_id": run_id,
        **git_info(),
        # Mọi thứ ảnh hưởng tới kết quả -> E4 so 2 lần chạy là so đúng cấu hình
        "kb_id": config.get("KB_ID"),
        "model_id": handler.MODEL_ID,
        "top_k": handler.TOP_K,
        "guardrail_id": handler.GUARDRAIL_ID or None,
        "guardrail_version": handler.GUARDRAIL_VERSION or None,
        "system_prompt_sha": sha(handler.SYSTEM_PROMPT),
        "golden_sha": sha(Path(args.golden).read_bytes()),
        "golden_filter": {"ids": args.ids, "limit": args.limit},
        "workers": args.workers,
        "elapsed_s": elapsed,
        "summary": summary,
    }
    with open(out_dir / f"{run_id}.meta.json", "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)

    # ---- Tóm tắt ra màn hình ----
    print(f"\nRun {run_id}  commit {meta['git_commit']}{' (dirty)' if meta['git_dirty'] else ''}  "
          f"model {meta['model_id']}  top_k={meta['top_k']}  guardrail v{meta['guardrail_version']}")
    print(f"{summary['questions']} câu | lỗi {summary['errors']} | {elapsed}s")
    for t, s in summary["by_type"].items():
        lat = f"{s['avg_latency_ms'] / 1000:.1f}s" if s["avg_latency_ms"] else "-"
        print(f"  {t:<11}{s['total']:>3} | trả lời {s['answered']:>2} | chặn {s['blocked']:>2} | "
              f"lỗi {s['errors']} | latency tb {lat}")
    u = summary["guardrail_units"]
    print(f"Chi phí: ${summary['cost_usd']:.4f}  (token {summary['input_tokens']:,} in / "
          f"{summary['output_tokens']:,} out, guardrail {sum(u.values())} unit)")
    print(f"→ {out_dir / (run_id + '.jsonl')}")
    for r in results:
        if "error" in r:
            print(f"  ❌ {r['id']}: {r['error'][:150]}")
    sys.exit(1 if summary["errors"] else 0)


if __name__ == "__main__":
    main()
