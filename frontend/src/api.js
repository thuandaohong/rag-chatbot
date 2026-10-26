// Gọi backend RAG. URL đọc từ biến môi trường (không hardcode).
// Bỏ dấu "/" thừa ở cuối để ghép "/chat" không bị "//chat".
const API_URL = (import.meta.env.VITE_API_URL || "").replace(/\/+$/, "");

export async function askQuestion(question) {
  if (!API_URL) {
    throw new Error("Chưa cấu hình VITE_API_URL trong file .env");
  }

  const res = await fetch(`${API_URL}/chat`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ question }),
  });

  // Backend trả mã lỗi (400/502...) kèm {error: ...}
  if (!res.ok) {
    let detail = `Lỗi ${res.status}`;
    try {
      const err = await res.json();
      if (err.error) detail = err.error;
    } catch (_) {
      /* body không phải JSON — giữ detail mặc định */
    }
    throw new Error(detail);
  }

  // Thành công: { answer, sources }
  return res.json();
}
