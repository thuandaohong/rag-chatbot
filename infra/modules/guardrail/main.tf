# ============================================================
# modules/guardrail — Bedrock Guardrail: lọc cả câu hỏi (input) lẫn câu trả lời (output)
#
# Tier STANDARD (không phải Classic mặc định): người dùng hỏi tiếng Việt, mà Classic
# chỉ hỗ trợ EN/FR/ES cho content filter + denied topic -> câu tiếng Việt lọt qua.
# Standard bắt buộc cross-region profile (us.guardrail.v1:0, dữ liệu ở trong US, không thêm phí).
# ============================================================

locals {
  # Provider đòi ARN đầy đủ (không nhận ID ngắn "us.guardrail.v1:0")
  guardrail_profile_arn = "arn:aws:bedrock:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:guardrail-profile/${var.guardrail_profile_id}"
}

resource "aws_bedrock_guardrail" "main" {
  name        = "${var.project}-guardrail"
  description = "Lọc nội dung độc hại, chống prompt injection, chặn lạc đề tài chính, che/chặn PII"

  # Thông báo trả về khi bị chặn (thay cho câu trả lời của model)
  blocked_input_messaging   = "Xin lỗi, mình không thể hỗ trợ câu hỏi này. Mình chỉ trả lời về nội dung tài liệu PMP/Agile."
  blocked_outputs_messaging = "Xin lỗi, câu trả lời đã bị chặn vì vi phạm chính sách nội dung."

  cross_region_config {
    guardrail_profile_identifier = local.guardrail_profile_arn
  }

  # ---- 1) Content filters: nội dung độc hại + prompt attack ----
  content_policy_config {
    tier_config = [{ tier_name = "STANDARD" }]

    dynamic "filters_config" {
      for_each = toset(["HATE", "VIOLENCE", "SEXUAL", "INSULTS", "MISCONDUCT"])
      content {
        type            = filters_config.value
        input_strength  = "HIGH"
        output_strength = "HIGH"
      }
    }

    # Jailbreak / prompt injection đến từ phía người dùng -> chỉ kiểm input
    filters_config {
      type            = "PROMPT_ATTACK"
      input_strength  = "HIGH"
      output_strength = "NONE"
    }
  }

  # ---- 2) Denied topics: chặn lạc đề (definition + examples cả Việt lẫn Anh) ----
  topic_policy_config {
    tier_config = [{ tier_name = "STANDARD" }]

    topics_config {
      name       = "investment-advice"
      type       = "DENY"
      definition = "Tư vấn đầu tư tài chính: khuyên mua/bán cổ phiếu, crypto, quỹ, bất động sản hoặc dự đoán giá. Investment advice, stock or crypto recommendations, or price predictions."
      examples = [
        "Tôi nên mua cổ phiếu nào để giàu nhanh?",
        "Có nên đầu tư Bitcoin lúc này không?",
        "Giá vàng tuần sau tăng hay giảm?",
        "Which stocks should I buy this year?",
      ]
    }
  }

  # ---- 3) PII: mức nhạy cảm khác nhau -> xử lý khác nhau ----
  sensitive_information_policy_config {
    # Che (thay bằng {EMAIL}, {PHONE}) nhưng vẫn trả lời
    pii_entities_config {
      type   = "EMAIL"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "PHONE"
      action = "ANONYMIZE"
    }
    # Số thẻ: chặn hẳn cả câu
    pii_entities_config {
      type   = "CREDIT_DEBIT_CARD_NUMBER"
      action = "BLOCK"
    }
  }

  tags = {
    Project = var.project
  }
}

# ---- Version cố định để app gọi (DRAFT thay đổi mỗi lần sửa luật) ----
resource "aws_bedrock_guardrail_version" "main" {
  guardrail_arn = aws_bedrock_guardrail.main.guardrail_arn
  description   = "Managed by Terraform"
  skip_destroy  = true # giữ version cũ trên AWS để rollback được

  lifecycle {
    # Sửa luật -> guardrail được update -> tự tạo version MỚI (không thì app vẫn chạy luật cũ)
    replace_triggered_by = [aws_bedrock_guardrail.main]
  }
}
