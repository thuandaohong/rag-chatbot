"""
try_local.py — Gọi RAG (Bedrock Knowledge Base) từ máy local.

Chạy:
    python try_local.py
Rồi gõ câu hỏi. Gõ 'quit' hoặc Ctrl-C để thoát.

Cấu hình đọc từ biến môi trường (nguyên tắc 12-factor, không hardcode):
    KB_ID       -> Knowledge Base ID   (mặc định: PGKAMMKERL)
    MODEL_ID    -> model trả lời        (mặc định: amazon.nova-lite-v1:0)
    AWS_REGION  -> region               (mặc định: us-east-1)
    TOP_K       -> số đoạn tài liệu lấy về (mặc định: 5)

Lưu ý: KB loại MANAGED không hỗ trợ retrieve_and_generate, nên RAG làm 2 bước:
    1. retrieve  (bedrock-agent-runtime) -> lấy các đoạn tài liệu liên quan
    2. converse  (bedrock-runtime)       -> model viết câu trả lời từ các đoạn đó
"""

import os

import boto3
from botocore.exceptions import ClientError

# --- Cấu hình từ môi trường, có giá trị mặc định để chạy ngay ---
REGION = os.environ.get("AWS_REGION", "us-east-1")
KB_ID = os.environ.get("KB_ID", "PGKAMMKERL")
MODEL_ID = os.environ.get("MODEL_ID", "amazon.nova-lite-v1:0")
TOP_K = int(os.environ.get("TOP_K", "5"))

# "bedrock-agent-runtime" = truy vấn KB; "bedrock-runtime" = gọi model sinh văn bản
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


def main() -> None:
    print(f"RAG local — KB={KB_ID}  model={MODEL_ID}  region={REGION}")
    print("Gõ câu hỏi (hoặc 'quit' để thoát).\n")

    while True:
        try:
            question = input("Hỏi> ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\nTạm biệt.")
            return

        if not question:
            continue
        if question.lower() in {"quit", "exit", "q"}:
            print("Tạm biệt.")
            return

        try:
            result = ask(question)
        except ClientError as e:
            # Lỗi phía AWS (quyền, model chưa bật, sai region...) in gọn gàng
            code = e.response.get("Error", {}).get("Code", "Unknown")
            msg = e.response.get("Error", {}).get("Message", str(e))
            print(f"\n[Lỗi AWS: {code}] {msg}\n")
            continue

        sources = extract_sources(result["chunks"])

        print("\n--- Trả lời ---")
        print(result["answer"])
        if sources:
            print("\n--- Nguồn ---")
            for i, s in enumerate(sources, 1):
                print(f"  [{i}] {s}")
        else:
            print("\n(Không có nguồn — câu hỏi có thể nằm ngoài tài liệu.)")
        print()


if __name__ == "__main__":
    main()
