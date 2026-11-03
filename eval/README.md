# Evaluation — bộ câu hỏi chuẩn (golden dataset)

"Thước đo cố định" cho chatbot: mỗi lần đổi model / prompt / TOP_K / guardrail, chạy lại
**cùng bộ câu hỏi này** và so điểm với lần trước. Giống bộ test case, nhưng cho AI.

| File | Nội dung |
|---|---|
| `golden.jsonl` | Bộ câu hỏi chuẩn — mỗi dòng 1 câu (JSON) |
| `draft_golden.py` | Script soạn **bản nháp** câu `in_doc` / `multi_hop` từ chính tài liệu trong KB |
| `run_eval.py` | Chạy bộ đề qua đúng pipeline `handler.ask()`, lưu kết quả để chấm (E2) |
| `results/` | Kết quả mỗi lần chạy (không commit) |

## Chạy eval (E2)

```bash
# đủ bộ đề, cấu hình mặc định = env của Lambda production
python eval/run_eval.py
# thử vài câu (đỡ tốn tiền)
python eval/run_eval.py --ids doc-01,out-02,guard-block-01
python eval/run_eval.py --limit 5
# lấy env y hệt Lambda đang chạy (KB, model, guardrail, bảng giá)
python eval/run_eval.py --env-from-lambda rag-chatbot-api
# thử cấu hình khác: env của shell được ưu tiên
TOP_K=3 python eval/run_eval.py
```

Import `ask()` thay vì gọi API: có **nội dung** đoạn tài liệu (để chấm groundedness), chạy được
code trong PR trước khi deploy, có sẵn token / guardrail / chi phí. Script đặt env **trước** khi
import handler (handler đọc env lúc import; thiếu `GUARDRAIL_ID` = chạy không guardrail mà không báo).

Mỗi lần chạy tạo 2 file trong `results/`:
- `<run_id>.jsonl`: mỗi câu 1 dòng — `answer`, `chunks` (source, score, **text**), `sources`,
  `guardrail_input/output`, token, `guardrail_units`, `stage_ms`, `latency_ms`, `cost_usd`, `error`.
- `<run_id>.meta.json`: commit (+ dirty), model, top_k, guardrail version, **hash system prompt**,
  **hash golden**, thời gian, tóm tắt. Đổi prompt/đề -> hash đổi -> không so nhầm 2 lần chạy.

Một lần chạy đủ 33 câu: ~65s (3 workers), **~$0.064**.

## Cấu trúc 1 dòng

| Trường | Bắt buộc | Ý nghĩa |
|---|---|---|
| `id` | ✅ | Mã duy nhất (`doc-`, `multi-`, `out-`, `guard-`) |
| `type` | ✅ | `in_doc` · `multi_hop` · `out_of_doc` · `guardrail` |
| `lang` | ✅ | `vi` / `en` — người dùng hỏi cả 2 thứ tiếng |
| `question` | ✅ | Câu hỏi gửi chatbot |
| `expected` | | Các ý chính câu trả lời đúng PHẢI có (dùng cho chấm correctness) |
| `expected_sources` | | File nguồn chấp nhận được. `in_doc`: khớp **1** là đạt; `multi_hop`: phải đủ **tất cả**; `out_of_doc`: `[]` |
| `evidence` | | Câu trích NGUYÊN VĂN từ tài liệu chứng minh đáp án (để người duyệt đối chiếu) |
| `should_block` | | (`guardrail`) `true` = phải chặn, `false` = **không được** chặn (đo chặn nhầm) |
| `expected_reason` | | (`guardrail`) lý do chặn mong đợi, vd `topic:investment-advice` |
| `expect_masked` | | (`guardrail`) loại PII phải bị che nhưng vẫn trả lời, vd `["EMAIL"]` |
| `review` | ✅ | `needs_review` (nháp do model soạn) · `approved` (đã duyệt) · `manual` (người viết) |
| `note` | | Ghi chú cho người đọc |

## 4 loại câu và thứ chúng đo

| Loại | Số câu | Đo gì |
|---|---|---|
| `in_doc` | 15 | Trả lời đúng ý, bám tài liệu, **lấy đúng file nguồn** |
| `multi_hop` | 3 | Tổng hợp từ **2 tài liệu** |
| `out_of_doc` | 6 | Nói "không có trong tài liệu" thay vì bịa — gồm cả câu *gần lĩnh vực* (lịch thi PMP, ITIL) dễ bịa nhất |
| `guardrail` | 9 | Chặn đúng (5) **và không chặn nhầm** câu nghe nhạy cảm nhưng hợp lệ (3) + che PII mà vẫn trả lời (1) |

## Cách soạn câu `in_doc` / `multi_hop` (chống bịa)

1. `retrieve` lấy đoạn thật của từng tài liệu theo chủ đề.
2. Nova Pro soạn câu hỏi + ý chính **chỉ từ đoạn đó**, kèm 1 câu trích nguyên văn (`evidence`).
3. Script kiểm `evidence` có **nguyên văn** trong đoạn đã retrieve — không có thì loại (lần soạn đầu loại 4 câu).
4. **Người duyệt** từng câu `needs_review` (bước bắt buộc — người hiểu tài liệu mới là chuẩn).

## Duyệt câu `needs_review`

Với mỗi dòng: đọc `question` + `expected` + `evidence`, rồi:
- Đúng và hữu ích → đổi `"review": "approved"`.
- Ý chính sai / thiếu → sửa `expected`, rồi `approved`.
- Câu mơ hồ / hỏi chi tiết vô nghĩa → xóa dòng.

## Kiểm tra nhãn đã chạy (2026-11-03)

- Guardrail (n8p73nudulzi v2): **9/9** đúng nhãn `should_block`, 3 câu "nhạy cảm nhưng hợp lệ" không bị chặn nhầm.
- Retrieval: 16/18 câu `in_doc`/`multi_hop` lấy được nguồn mong đợi trong top-5. `multi-01`, `multi-03`
  chỉ lấy được 1/2 tài liệu -> giữ lại làm case khó cho Module C (rerank / top-K).

## Lần chạy đầu tiên (2026-11-03, commit 0d38ac1, Nova Lite, top_k=5, guardrail v2)

33/33 câu chạy xong, 0 lỗi, $0.064. Chưa chấm điểm (E3), nhưng đọc kết quả thô đã thấy 3 vấn đề thật:

1. **Câu hỏi tiếng Anh -> trả lời tiếng Việt: 13/13 câu.** System prompt dặn "trả lời cùng ngôn
   ngữ với câu hỏi" nhưng prompt + nhãn `TÀI LIỆU:` / `CÂU HỎI:` đều tiếng Việt -> model nghiêng
   về tiếng Việt. E3 cần một tiêu chí "đúng ngôn ngữ".
2. **`out-02` lọt bẫy**: "Write a Python function..." -> bot viết code thay vì nói tài liệu không
   có. 5/6 câu bẫy còn lại trả lời đúng "Không tìm thấy thông tin... trong tài liệu".
3. **Score retrieve không tách được câu liên quan / không liên quan**: top score câu `in_doc`
   0.570–0.977 (tb 0.833), câu `out_of_doc` 0.518–0.972 (tb 0.733) -> lọc đoạn theo ngưỡng score
   (ý tưởng Module C) sẽ không hiệu quả.

## ⚠️ Vấn đề dữ liệu phát hiện khi làm E1

`PS_WBS_ThirdEd.pdf` **chưa từng vào Knowledge Base**: PDF bị mã hóa (`/Encrypt`), ingestion job
ngày 2026-10-12 ghi `numberOfDocumentsFailed: 1`, lý do *"The document may be password-protected"*,
trong khi trạng thái job vẫn là `COMPLETE`. Chatbot chỉ trả lời từ 3/4 tài liệu. Bộ câu hỏi hiện
không có câu nào cần tài liệu WBS.
