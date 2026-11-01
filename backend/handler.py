"""
handler.py — Lambda cho RAG Chatbot.

Nhận câu hỏi qua API Gateway (POST /chat, body JSON {"question": "..."}),
gọi Bedrock Knowledge Base, trả về {"answer": ..., "sources": [...]}.

Cấu hình đọc từ biến môi trường của Lambda (KHÔNG hardcode):
    KB_ID       -> Knowledge Base ID
    MODEL_ID    -> model trả lời (vd amazon.nova-lite-v1:0)
    TOP_K       -> số đoạn tài liệu lấy về (mặc định 5)
    GUARDRAIL_ID / GUARDRAIL_VERSION -> Bedrock Guardrail (tùy chọn, feature flag:
                   thiếu 1 trong 2 -> bỏ qua guardrail, chatbot vẫn chạy)
    AWS_REGION  -> Lambda tự có sẵn biến này

Lưu ý: KB loại MANAGED không hỗ trợ retrieve_and_generate, nên RAG làm 2 bước:
    1. retrieve  (bedrock-agent-runtime) -> lấy các đoạn tài liệu liên quan
    2. converse  (bedrock-runtime)       -> model viết câu trả lời từ các đoạn đó
Guardrail kiểm 2 đầu bằng ApplyGuardrail (không gắn vào converse, vì prompt gửi
converse có cả tài liệu -> guardrail sẽ quét cả tài liệu, dễ chặn nhầm):
    câu hỏi  -> ApplyGuardrail(INPUT)  -> chặn thì trả luôn (không tốn retrieve/LLM)
    trả lời  -> ApplyGuardrail(OUTPUT) -> chặn hoặc che PII trước khi trả
Quyền IAM cần cho role Lambda: bedrock:Retrieve + bedrock:InvokeModel + bedrock:ApplyGuardrail.

Structured logging (Day 37): MỖI request ghi đúng 1 dòng JSON {"type": "rag_request", ...}
(status, latency từng bước, token, guardrail...) -> query bằng CloudWatch Logs Insights.
Token (Day 38) là số CHÍNH XÁC từ `usage` của Converse (không ước lượng); guardrail tính
tiền theo text unit (1 unit = tối đa 1000 ký tự, mỗi policy tính riêng) -> log riêng.
KHÔNG log nội dung câu hỏi/câu trả lời (có thể chứa PII), chỉ log độ dài.
"""

import base64
import json
import os
import time

import boto3
from botocore.exceptions import ClientError

REGION = os.environ.get("AWS_REGION", "us-east-1")
KB_ID = os.environ["KB_ID"]           # bắt buộc phải set ở Lambda env
MODEL_ID = os.environ.get("MODEL_ID", "amazon.nova-lite-v1:0")
TOP_K = int(os.environ.get("TOP_K", "5"))
GUARDRAIL_ID = os.environ.get("GUARDRAIL_ID", "")
GUARDRAIL_VERSION = os.environ.get("GUARDRAIL_VERSION", "")
GUARDRAIL_ENABLED = bool(GUARDRAIL_ID and GUARDRAIL_VERSION)

_cold_start = True  # True ở request đầu tiên của mỗi container Lambda mới

# Tạo client 1 lần ở ngoài handler -> tái dùng giữa các lần gọi (nhanh hơn)
kb_client = boto3.client("bedrock-agent-runtime", region_name=REGION)
llm_client = boto3.client("bedrock-runtime", region_name=REGION)

SYSTEM_PROMPT = (
    "Bạn là trợ lý trả lời câu hỏi dựa trên tài liệu được cung cấp. "
    "Chỉ dùng thông tin trong phần TÀI LIỆU. Nếu tài liệu không có thông tin, "
    "hãy nói rõ là không tìm thấy trong tài liệu. Trả lời cùng ngôn ngữ với câu hỏi."
)


def log_event(**fields) -> None:
    """Ghi 1 dòng JSON ra CloudWatch (stdout của Lambda) -> Logs Insights tự tách field."""
    print(json.dumps({"type": "rag_request", **fields}, ensure_ascii=False))


class Timer:
    """Đo thời gian từng bước: `with timer("retrieve"): ...` -> timer.ms["retrieve"]."""

    def __init__(self):
        self.ms = {}

    def __call__(self, name: str):
        timer = self

        class _Step:
            def __enter__(self):
                self.t0 = time.perf_counter()

            def __exit__(self, *exc):
                timer.ms[name] = int((time.perf_counter() - self.t0) * 1000)

        return _Step()


# Field `usage` của ApplyGuardrail -> tên ngắn trong log. Mỗi policy tính tiền riêng theo unit.
GUARDRAIL_UNIT_FIELDS = {
    "contentPolicyUnits": "content",
    "topicPolicyUnits": "topic",
    "sensitiveInformationPolicyUnits": "pii",
}


def check_guardrail(text: str, source: str) -> dict:
    """Chạy guardrail trên 1 đoạn text. source = "INPUT" (câu hỏi) | "OUTPUT" (trả lời).

    Trả về {"action": "NONE"|"MASKED"|"BLOCKED", "text": ..., "reasons": [...], "units": {...}}
      - NONE    : không vi phạm, text giữ nguyên
      - MASKED  : PII bị che ({EMAIL}, {PHONE}...), text là bản đã che
      - BLOCKED : vi phạm, text là thông báo chặn cấu hình trong guardrail
    units = text unit đã tính tiền cho lần gọi này, vd {"content": 1, "topic": 1, "pii": 1}
    """
    if not GUARDRAIL_ENABLED:
        return {"action": "NONE", "text": text, "reasons": [], "units": {}}

    resp = llm_client.apply_guardrail(
        guardrailIdentifier=GUARDRAIL_ID,
        guardrailVersion=GUARDRAIL_VERSION,
        source=source,
        content=[{"text": {"text": text}}],
    )
    usage = resp.get("usage", {})
    units = {short: usage.get(field, 0) for field, short in GUARDRAIL_UNIT_FIELDS.items()}
    if resp.get("action") != "GUARDRAIL_INTERVENED":
        return {"action": "NONE", "text": text, "reasons": [], "units": units}

    # Cả "chặn" lẫn "che PII" đều trả GUARDRAIL_INTERVENED -> phân biệt qua assessments
    reasons, blocked = [], False
    for a in resp.get("assessments", []):
        for f in a.get("contentPolicy", {}).get("filters", []):
            if f.get("action") == "BLOCKED":
                reasons.append(f"content:{f.get('type')}")
                blocked = True
        for t in a.get("topicPolicy", {}).get("topics", []):
            if t.get("action") == "BLOCKED":
                reasons.append(f"topic:{t.get('name')}")
                blocked = True
        sip = a.get("sensitiveInformationPolicy", {})
        for p in sip.get("piiEntities", []) + sip.get("regexes", []):
            reasons.append(f"pii:{p.get('type') or p.get('name')}:{p.get('action')}")
            if p.get("action") == "BLOCKED":
                blocked = True

    outputs = resp.get("outputs") or [{"text": text}]
    return {"action": "BLOCKED" if blocked else "MASKED", "text": outputs[0]["text"],
            "reasons": reasons, "units": units}


def retrieve(question: str) -> list:
    """Bước 1: tìm các đoạn tài liệu liên quan nhất trong KB."""
    resp = kb_client.retrieve(
        knowledgeBaseId=KB_ID,
        retrievalQuery={"text": question},
    )
    return resp.get("retrievalResults", [])[:TOP_K]


def generate(question: str, chunks: list) -> tuple:
    """Bước 2: đưa câu hỏi + các đoạn tài liệu cho model viết câu trả lời."""
    context = "\n\n".join(
        f"[{i}] {c.get('content', {}).get('text', '')}"
        for i, c in enumerate(chunks, 1)
    )
    prompt = f"TÀI LIỆU:\n{context}\n\nCÂU HỎI: {question}"

    resp = llm_client.converse(
        modelId=MODEL_ID,
        system=[{"text": SYSTEM_PROMPT}],
        messages=[{"role": "user", "content": [{"text": prompt}]}],
        inferenceConfig={"maxTokens": 1024, "temperature": 0.2},
    )
    usage = resp.get("usage", {})  # Day 38 dùng token để tính tiền
    return resp["output"]["message"]["content"][0]["text"], usage


def ask(question: str, timer: Timer) -> dict:
    """Chạy đủ RAG có guardrail 2 đầu.

    Trả về {"answer", "chunks", "guardrail": {"input", "output"}, "usage"}; thời gian
    từng bước ghi vào `timer` (bước nào không chạy thì không có trong timer.ms).
    """
    result = {"answer": "", "chunks": [], "guardrail": {"input": None, "output": None}, "usage": {}}

    # 1) Guardrail chiều vào: chặn sớm -> không tốn tiền retrieve + LLM
    with timer("guardrail_in"):
        g_in = check_guardrail(question, "INPUT")
    result["guardrail"]["input"] = g_in
    if g_in["action"] == "BLOCKED":
        result["answer"] = g_in["text"]
        return result
    question = g_in["text"]  # bản đã che PII (nếu có) -> PII không đi tới KB/model

    # 2) RAG
    with timer("retrieve"):
        chunks = retrieve(question)
    if not chunks:
        result["answer"] = "(Không tìm thấy tài liệu liên quan.)"
        return result
    with timer("generate"):
        answer, result["usage"] = generate(question, chunks)

    # 3) Guardrail chiều ra: chặn nội dung độc / che PII model lỡ sinh ra
    with timer("guardrail_out"):
        g_out = check_guardrail(answer, "OUTPUT")
    result["guardrail"]["output"] = g_out
    result["answer"] = g_out["text"]
    if g_out["action"] != "BLOCKED":
        result["chunks"] = chunks
    return result


def extract_sources(chunks: list) -> list:
    """Bóc danh sách đường dẫn S3 (nguồn) từ các đoạn đã retrieve, bỏ trùng."""
    sources = []
    for chunk in chunks:
        uri = chunk.get("location", {}).get("s3Location", {}).get("uri", "")
        if uri and uri not in sources:
            sources.append(uri)
    return sources


def _response(status: int, body: dict) -> dict:
    """Đóng gói response đúng định dạng API Gateway."""
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "application/json",
        },
        "body": json.dumps(body, ensure_ascii=False),
    }


def _http_method(event: dict) -> str:
    """Lấy HTTP method cho cả REST API (v1) lẫn HTTP API (v2)."""
    return (
        event.get("httpMethod")
        or event.get("requestContext", {}).get("http", {}).get("method", "")
    ).upper()


def lambda_handler(event, context):
    global _cold_start
    t_start = time.perf_counter()
    base = {
        "request_id": getattr(context, "aws_request_id", None),
        "cold_start": _cold_start,
    }
    _cold_start = False

    def elapsed_ms() -> int:
        return int((time.perf_counter() - t_start) * 1000)

    # 0) Trình duyệt gửi OPTIONS (CORS preflight) trước khi POST JSON
    if _http_method(event) == "OPTIONS":
        return _response(200, {})

    # 1) Lấy câu hỏi từ body của request
    raw_body = event.get("body") or "{}"
    try:
        # API Gateway có thể gửi body dạng base64 (isBase64Encoded=true)
        if event.get("isBase64Encoded"):
            raw_body = base64.b64decode(raw_body).decode("utf-8")
        data = json.loads(raw_body)
    except (TypeError, ValueError):
        log_event(**base, status=400, error="bad_json", latency_ms=elapsed_ms())
        return _response(400, {"error": "Body không phải JSON hợp lệ"})

    if not isinstance(data, dict):
        log_event(**base, status=400, error="body_not_object", latency_ms=elapsed_ms())
        return _response(400, {"error": "Body phải là object JSON"})

    question = data.get("question")
    if not isinstance(question, str) or not question.strip():
        log_event(**base, status=400, error="missing_question", latency_ms=elapsed_ms())
        return _response(400, {"error": "Thiếu trường 'question' (chuỗi)"})
    question = question.strip()

    # 2) Gọi RAG
    timer = Timer()
    try:
        result = ask(question, timer)
    except ClientError as e:
        code = e.response.get("Error", {}).get("Code", "Unknown")
        msg = e.response.get("Error", {}).get("Message", str(e))
        log_event(**base, status=502, error=code, latency_ms=elapsed_ms(), stage_ms=timer.ms)
        print(f"Bedrock error: {code} - {msg}")  # chi tiết lỗi để debug (không chứa PII)
        return _response(502, {"error": f"{code}: {msg}"})
    except Exception as e:  # lỗi code bất ngờ: vẫn có 1 dòng log để đếm tỉ lệ lỗi
        log_event(**base, status=500, error=type(e).__name__, latency_ms=elapsed_ms(), stage_ms=timer.ms)
        raise

    # 3) Trả về câu trả lời + nguồn
    sources = extract_sources(result["chunks"])
    g_in, g_out = result["guardrail"]["input"], result["guardrail"]["output"]
    usage = result["usage"]

    # Cộng text unit của 2 lần gọi guardrail (input + output) -> Day 39 quy ra tiền
    guardrail_units = {short: 0 for short in GUARDRAIL_UNIT_FIELDS.values()}
    for g in (g_in, g_out):
        for k, v in (g["units"] if g else {}).items():
            guardrail_units[k] += v

    # 1 dòng JSON có cấu trúc / request. Chỉ log ĐỘ DÀI, không log nội dung (tránh lộ PII).
    log_event(
        **base,
        status=200,
        latency_ms=elapsed_ms(),
        stage_ms=timer.ms,                          # {guardrail_in, retrieve, generate, guardrail_out}
        model_id=MODEL_ID,
        question_len=len(question),
        answer_len=len(result["answer"]),
        num_chunks=len(result["chunks"]),
        num_sources=len(sources),
        input_tokens=usage.get("inputTokens", 0),   # 0 nếu không gọi model (bị chặn / không có tài liệu)
        output_tokens=usage.get("outputTokens", 0),
        guardrail_input=g_in["action"] if g_in else "SKIPPED",
        guardrail_output=g_out["action"] if g_out else "SKIPPED",
        guardrail_reasons=(g_in["reasons"] if g_in else []) + (g_out["reasons"] if g_out else []),
        guardrail_units=guardrail_units,            # {"content", "topic", "pii"} cộng cả 2 chiều
    )

    return _response(200, {"answer": result["answer"], "sources": sources})
