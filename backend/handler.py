"""
handler.py — Lambda cho RAG Chatbot.

Nhận câu hỏi qua API Gateway (POST /chat, body JSON {"question": "..."}),
gọi Bedrock Knowledge Base, trả về {"answer": ..., "sources": [...]}.

Cấu hình đọc từ biến môi trường của Lambda (KHÔNG hardcode):
    KB_ID       -> Knowledge Base ID
    MODEL_ID    -> model trả lời (vd amazon.nova-lite-v1:0)
    TOP_K       -> số đoạn tài liệu lấy về (mặc định 5)
    AWS_REGION  -> Lambda tự có sẵn biến này

Lưu ý: KB loại MANAGED không hỗ trợ retrieve_and_generate, nên RAG làm 2 bước:
    1. retrieve  (bedrock-agent-runtime) -> lấy các đoạn tài liệu liên quan
    2. converse  (bedrock-runtime)       -> model viết câu trả lời từ các đoạn đó
Quyền IAM cần cho role Lambda: bedrock:Retrieve + bedrock:InvokeModel.
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

# Tạo client 1 lần ở ngoài handler -> tái dùng giữa các lần gọi (nhanh hơn)
kb_client = boto3.client("bedrock-agent-runtime", region_name=REGION)
llm_client = boto3.client("bedrock-runtime", region_name=REGION)

SYSTEM_PROMPT = (
    "Bạn là trợ lý trả lời câu hỏi dựa trên tài liệu được cung cấp. "
    "Chỉ dùng thông tin trong phần TÀI LIỆU. Nếu tài liệu không có thông tin, "
    "hãy nói rõ là không tìm thấy trong tài liệu. Trả lời cùng ngôn ngữ với câu hỏi."
)


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
    """Chạy đủ RAG: retrieve rồi generate. Trả về câu trả lời và các đoạn đã dùng."""
    chunks = retrieve(question)
    if not chunks:
        return {"answer": "(Không tìm thấy tài liệu liên quan.)", "chunks": []}
    return {"answer": generate(question, chunks), "chunks": chunks}


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

    # 3) Trả về câu trả lời + nguồn
    sources = extract_sources(result["chunks"])
    return _response(200, {"answer": result["answer"], "sources": sources})
