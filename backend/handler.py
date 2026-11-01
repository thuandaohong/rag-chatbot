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
"""

import base64
import json
import os

import boto3
from botocore.exceptions import ClientError

REGION = os.environ.get("AWS_REGION", "us-east-1")
KB_ID = os.environ["KB_ID"]           # bắt buộc phải set ở Lambda env
MODEL_ID = os.environ.get("MODEL_ID", "amazon.nova-lite-v1:0")
TOP_K = int(os.environ.get("TOP_K", "5"))
GUARDRAIL_ID = os.environ.get("GUARDRAIL_ID", "")
GUARDRAIL_VERSION = os.environ.get("GUARDRAIL_VERSION", "")
GUARDRAIL_ENABLED = bool(GUARDRAIL_ID and GUARDRAIL_VERSION)

# Tạo client 1 lần ở ngoài handler -> tái dùng giữa các lần gọi (nhanh hơn)
kb_client = boto3.client("bedrock-agent-runtime", region_name=REGION)
llm_client = boto3.client("bedrock-runtime", region_name=REGION)

SYSTEM_PROMPT = (
    "Bạn là trợ lý trả lời câu hỏi dựa trên tài liệu được cung cấp. "
    "Chỉ dùng thông tin trong phần TÀI LIỆU. Nếu tài liệu không có thông tin, "
    "hãy nói rõ là không tìm thấy trong tài liệu. Trả lời cùng ngôn ngữ với câu hỏi."
)


def check_guardrail(text: str, source: str) -> dict:
    """Chạy guardrail trên 1 đoạn text. source = "INPUT" (câu hỏi) | "OUTPUT" (trả lời).

    Trả về {"action": "NONE"|"MASKED"|"BLOCKED", "text": ..., "reasons": [...]}
      - NONE    : không vi phạm, text giữ nguyên
      - MASKED  : PII bị che ({EMAIL}, {PHONE}...), text là bản đã che
      - BLOCKED : vi phạm, text là thông báo chặn cấu hình trong guardrail
    """
    if not GUARDRAIL_ENABLED:
        return {"action": "NONE", "text": text, "reasons": []}

    resp = llm_client.apply_guardrail(
        guardrailIdentifier=GUARDRAIL_ID,
        guardrailVersion=GUARDRAIL_VERSION,
        source=source,
        content=[{"text": {"text": text}}],
    )
    if resp.get("action") != "GUARDRAIL_INTERVENED":
        return {"action": "NONE", "text": text, "reasons": []}

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
    return {"action": "BLOCKED" if blocked else "MASKED", "text": outputs[0]["text"], "reasons": reasons}


def retrieve(question: str) -> list:
    """Bước 1: tìm các đoạn tài liệu liên quan nhất trong KB."""
    resp = kb_client.retrieve(
        knowledgeBaseId=KB_ID,
        retrievalQuery={"text": question},
    )
    return resp.get("retrievalResults", [])[:TOP_K]


def generate(question: str, chunks: list) -> str:
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
    return resp["output"]["message"]["content"][0]["text"]


def ask(question: str) -> dict:
    """Chạy đủ RAG có guardrail 2 đầu. Trả về câu trả lời, các đoạn đã dùng, kết quả guardrail."""
    # 1) Guardrail chiều vào: chặn sớm -> không tốn tiền retrieve + LLM
    g_in = check_guardrail(question, "INPUT")
    if g_in["action"] == "BLOCKED":
        return {"answer": g_in["text"], "chunks": [], "guardrail": {"input": g_in, "output": None}}
    question = g_in["text"]  # bản đã che PII (nếu có) -> PII không đi tới KB/model

    # 2) RAG
    chunks = retrieve(question)
    if not chunks:
        return {"answer": "(Không tìm thấy tài liệu liên quan.)", "chunks": [],
                "guardrail": {"input": g_in, "output": None}}
    answer = generate(question, chunks)

    # 3) Guardrail chiều ra: chặn nội dung độc / che PII model lỡ sinh ra
    g_out = check_guardrail(answer, "OUTPUT")
    if g_out["action"] == "BLOCKED":
        return {"answer": g_out["text"], "chunks": [], "guardrail": {"input": g_in, "output": g_out}}
    return {"answer": g_out["text"], "chunks": chunks, "guardrail": {"input": g_in, "output": g_out}}


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
        return _response(400, {"error": "Body không phải JSON hợp lệ"})

    if not isinstance(data, dict):
        return _response(400, {"error": "Body phải là object JSON"})

    question = data.get("question")
    if not isinstance(question, str) or not question.strip():
        return _response(400, {"error": "Thiếu trường 'question' (chuỗi)"})
    question = question.strip()

    # 2) Gọi RAG
    try:
        result = ask(question)
    except ClientError as e:
        code = e.response.get("Error", {}).get("Code", "Unknown")
        msg = e.response.get("Error", {}).get("Message", str(e))
        # In ra log CloudWatch để debug
        print(f"Bedrock error: {code} - {msg}")
        return _response(502, {"error": f"{code}: {msg}"})

    # Log khi guardrail can thiệp (Day 37 sẽ chuyển thành structured log + metric).
    # Chỉ log action + lý do, KHÔNG log câu hỏi gốc (có thể chứa PII).
    for side, g in result["guardrail"].items():
        if g and g["action"] != "NONE":
            print(json.dumps({"event": "guardrail_intervened", "side": side,
                              "action": g["action"], "reasons": g["reasons"]}))

    # 3) Trả về câu trả lời + nguồn
    sources = extract_sources(result["chunks"])
    return _response(200, {"answer": result["answer"], "sources": sources})
