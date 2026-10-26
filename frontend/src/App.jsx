import { useState, useRef, useEffect } from "react";
import { askQuestion } from "./api";

// Lấy tên file dễ đọc từ URL S3: "2.PMP%2BPrep%2BCourse.pdf" -> "2.PMP Prep Course.pdf"
function sourceName(uri) {
  const name = uri.split("/").pop();
  try {
    return decodeURIComponent(name).replace(/\+/g, " ");
  } catch {
    return name;
  }
}

// Render markdown tối giản AN TOÀN: escape HTML trước, rồi chỉ cho phép **đậm**.
// Không dùng thư viện, không dangerouslySet với nội dung chưa escape.
function renderText(text) {
  const escaped = text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
  const withBold = escaped.replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>");
  return { __html: withBold };
}

export default function App() {
  // Mỗi tin: { role: "user" | "bot", text, sources?, error? }
  const [messages, setMessages] = useState([]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  const endRef = useRef(null);

  useEffect(() => {
    endRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, loading]);

  async function handleSend() {
    const q = input.trim();
    if (!q || loading) return;

    setMessages((prev) => [...prev, { role: "user", text: q }]);
    setInput("");
    setLoading(true);

    try {
      const data = await askQuestion(q);
      setMessages((prev) => [
        ...prev,
        {
          role: "bot",
          text: data.answer || "(không có câu trả lời)",
          sources: data.sources || [],
        },
      ]);
    } catch (e) {
      setMessages((prev) => [
        ...prev,
        { role: "bot", text: e.message || "Không gọi được API", error: true },
      ]);
    } finally {
      setLoading(false);
    }
  }

  function handleKeyDown(e) {
    // isComposing: đang gõ dở chữ bằng bộ gõ tiếng Việt (Telex/VNI) -> Enter để chốt chữ, không gửi
    if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) {
      e.preventDefault();
      handleSend();
    }
  }

  function clearChat() {
    setMessages([]);
  }

  return (
    <div className="app">
      <header className="header">
        <h1>RAG Chatbot</h1>
        <span className="tag">PMP Process Groups</span>
        {messages.length > 0 && !loading && (
          <button className="clear" onClick={clearChat}>
            Xóa
          </button>
        )}
      </header>

      <main className="chat">
        {messages.length === 0 && (
          <p className="empty">Hỏi một câu về tài liệu để bắt đầu…</p>
        )}
        {messages.map((m, i) => (
          <div key={i} className={`msg ${m.role}`}>
            {m.role === "bot" && !m.error ? (
              <div
                className="bubble"
                dangerouslySetInnerHTML={renderText(m.text)}
              />
            ) : (
              <div className={`bubble ${m.error ? "error" : ""}`}>{m.text}</div>
            )}
            {m.sources && m.sources.length > 0 && (
              <div className="sources">
                <span className="sources-label">
                  {m.sources.length} nguồn:
                </span>
                {m.sources.map((s, j) => (
                  <span key={j} className="source" title={s}>
                    {sourceName(s)}
                  </span>
                ))}
              </div>
            )}
          </div>
        ))}
        {loading && (
          <div className="msg bot">
            <div className="bubble typing">Đang trả lời…</div>
          </div>
        )}
        <div ref={endRef} />
      </main>

      <footer className="composer">
        {/* Không disable textarea khi loading: vẫn gõ trước được câu sau, không mất focus.
            Việc chặn gửi trùng đã do nút Gửi + check `loading` trong handleSend lo. */}
        <textarea
          rows={1}
          placeholder="Nhập câu hỏi…"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={handleKeyDown}
        />
        <button onClick={handleSend} disabled={!input.trim() || loading}>
          Gửi
        </button>
      </footer>
    </div>
  );
}
