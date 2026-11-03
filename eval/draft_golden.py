"""
draft_golden.py — Soạn BẢN NHÁP câu hỏi in_doc / multi_hop từ chính tài liệu trong KB.

Cách chống "bịa": mỗi câu hỏi phải kèm 1 câu trích NGUYÊN VĂN (evidence) từ đoạn tài liệu
đã retrieve; script tự kiểm evidence có thật trong đoạn đó, không có -> loại.
Kết quả chỉ là nháp -> người duyệt lại rồi mới đưa vào golden.jsonl.

Chạy:  KB_ID=PGKAMMKERL python eval/draft_golden.py > eval/golden.draft.jsonl
"""

import json
import os
import re
import sys

import boto3

REGION = os.environ.get("AWS_REGION", "us-east-1")
KB_ID = os.environ["KB_ID"]
DRAFT_MODEL = os.environ.get("DRAFT_MODEL", "amazon.nova-pro-v1:0")  # mạnh hơn model trả lời

kb = boto3.client("bedrock-agent-runtime", region_name=REGION)
llm = boto3.client("bedrock-runtime", region_name=REGION)

# Chủ đề gợi ý cho từng tài liệu -> retrieve đoạn liên quan rồi soạn câu hỏi từ đoạn đó
TOPICS = {
    "ProcessGroupsPracticeGuide.pdf": [
        "five Process Groups", "Develop Project Charter purpose", "Initiating Process Group",
        "Monitoring and Controlling Process Group", "Close Project or Phase",
        "work package control account", "stakeholder engagement assessment matrix",
    ],
    "Agile-Practice-Guide.pdf": [
        "Agile Manifesto values", "servant leadership", "Kanban method",
        "retrospectives", "hybrid approach agile and predictive",
    ],
    # PS_WBS_ThirdEd.pdf: KHÔNG có trong KB — PDF mã hóa, ingestion lỗi
    # ("The document may be password-protected"), xem eval/README.md
    "2.PMP+Prep+Course+Summary+Notes+2025.pdf": [
        "Earned Value Analysis", "critical path", "Decomposition deliverables work packages",
        "conflict resolution techniques", "contract types fixed price cost reimbursable",
    ],
}

PROMPT = """Bạn soạn câu hỏi kiểm tra cho chatbot hỏi đáp tài liệu PMP.
Chỉ dựa vào ĐOẠN TÀI LIỆU dưới đây. Soạn đúng 1 câu hỏi mà đoạn này trả lời được rõ ràng.

Yêu cầu:
- Ngôn ngữ câu hỏi: {lang}.
- "expected": 1-5 ý chính ngắn mà câu trả lời đúng PHẢI có (lấy từ đoạn, có thể giữ thuật ngữ tiếng Anh).
- "evidence": 1 câu trích NGUYÊN VĂN, chép y hệt từ đoạn (không dịch, không sửa), chứng minh đáp án.
- Không hỏi về số trang, mục lục, hình ảnh, bản quyền.

Trả về DUY NHẤT JSON: {{"question": "...", "expected": ["..."], "evidence": "..."}}

ĐOẠN TÀI LIỆU:
{chunk}"""


# multi_hop: câu hỏi cần ĐỦ 2 đoạn từ 2 tài liệu khác nhau mới trả lời trọn
PMP_NOTES = "2.PMP+Prep+Course+Summary+Notes+2025.pdf"
PG = "ProcessGroupsPracticeGuide.pdf"
AG = "Agile-Practice-Guide.pdf"
MULTI_PAIRS = [
    (("servant leadership", AG), ("conflict resolution techniques", PMP_NOTES)),
    (("Decomposition deliverables work packages", PMP_NOTES), ("work package control account", PG)),
    (("retrospectives", AG), ("Close Project or Phase", PG)),
    (("critical path", PMP_NOTES), ("Monitoring and Controlling Process Group", PG)),
    (("Kanban method", AG), ("five Process Groups", PG)),
]

PROMPT_MULTI = """Bạn soạn câu hỏi kiểm tra cho chatbot hỏi đáp tài liệu PMP.
Soạn đúng 1 câu hỏi (ngôn ngữ: {lang}) mà muốn trả lời TRỌN phải dùng CẢ ĐOẠN A lẫn ĐOẠN B.

- "expected": 2-5 ý chính, có ý lấy từ A và có ý lấy từ B.
- "evidence_a": 1 câu trích NGUYÊN VĂN từ đoạn A. "evidence_b": 1 câu trích NGUYÊN VĂN từ đoạn B.

Trả về DUY NHẤT JSON: {{"question": "...", "expected": ["..."], "evidence_a": "...", "evidence_b": "..."}}

ĐOẠN A:
{a}

ĐOẠN B:
{b}"""


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip().lower()


def source_file(chunk: dict) -> str:
    uri = chunk.get("location", {}).get("s3Location", {}).get("uri", "")
    return uri.split("/")[-1].replace("%2B", "+")


def best_chunk(topic: str, doc: str):
    """Đoạn có score cao nhất thuộc ĐÚNG tài liệu doc (bỏ đoạn của file khác)."""
    res = kb.retrieve(knowledgeBaseId=KB_ID, retrievalQuery={"text": topic})["retrievalResults"]
    for c in sorted(res, key=lambda c: c.get("score", 0), reverse=True):
        text = c.get("content", {}).get("text", "")
        if source_file(c) == doc and len(text) > 300 and "<image_type>" not in text:
            return text
    return None


def draft(chunk: str, lang: str, prompt: str = None) -> dict:
    text = prompt or PROMPT.format(lang=lang, chunk=chunk[:6000])
    resp = llm.converse(
        modelId=DRAFT_MODEL,
        messages=[{"role": "user", "content": [{"text": text}]}],
        inferenceConfig={"maxTokens": 600, "temperature": 0},
    )
    out = resp["output"]["message"]["content"][0]["text"]
    return json.loads(out[out.index("{"): out.rindex("}") + 1])


def main():
    n = 0
    for doc, topics in TOPICS.items():
        for i, topic in enumerate(topics):
            chunk = best_chunk(topic, doc)
            if not chunk:
                print(f"skip (no chunk): {doc} / {topic}", file=sys.stderr)
                continue
            lang = "tiếng Việt" if i % 2 else "English"  # trộn VI/EN như người dùng thật
            try:
                q = draft(chunk, lang)
            except (ValueError, KeyError) as e:
                print(f"skip (bad JSON): {doc} / {topic}: {e}", file=sys.stderr)
                continue
            # Chống bịa: evidence phải có NGUYÊN VĂN trong đoạn đã retrieve
            if norm(q.get("evidence", "")) not in norm(chunk):
                print(f"skip (evidence not in chunk): {doc} / {topic}", file=sys.stderr)
                continue
            n += 1
            print(json.dumps({
                "id": f"draft-{n:02d}",
                "type": "in_doc",
                "lang": "vi" if lang == "tiếng Việt" else "en",
                "question": q["question"],
                "expected": q["expected"],
                "expected_sources": [doc],
                "evidence": q["evidence"],
                "topic": topic,
            }, ensure_ascii=False))
    m = 0
    for i, ((ta, da), (tb, db)) in enumerate(MULTI_PAIRS):
        a, b = best_chunk(ta, da), best_chunk(tb, db)
        if not (a and b):
            print(f"skip multi (no chunk): {ta} + {tb}", file=sys.stderr)
            continue
        lang = "tiếng Việt" if i % 2 == 0 else "English"
        try:
            q = draft(None, lang, PROMPT_MULTI.format(lang=lang, a=a[:4000], b=b[:4000]))
        except (ValueError, KeyError) as e:
            print(f"skip multi (bad JSON): {ta} + {tb}: {e}", file=sys.stderr)
            continue
        if norm(q.get("evidence_a", "")) not in norm(a) or norm(q.get("evidence_b", "")) not in norm(b):
            print(f"skip multi (evidence not in chunks): {ta} + {tb}", file=sys.stderr)
            continue
        m += 1
        print(json.dumps({
            "id": f"draft-m{m:02d}",
            "type": "multi_hop",
            "lang": "vi" if lang == "tiếng Việt" else "en",
            "question": q["question"],
            "expected": q["expected"],
            "expected_sources": sorted({da, db}),
            "evidence": [q["evidence_a"], q["evidence_b"]],
            "topic": f"{ta} + {tb}",
        }, ensure_ascii=False))
    print(f"drafted {n} in_doc + {m} multi_hop questions", file=sys.stderr)


if __name__ == "__main__":
    main()
