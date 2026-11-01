# ============================================================
# imports.tf — import resource đã tồn tại trên AWS vào state (block import phải ở root module).
# Sau khi apply thành công có thể xóa block tương ứng.
# ============================================================

# Day 37: log group Lambda tự tạo (retention vĩnh viễn) -> TF quản để đặt retention
import {
  to = module.backend.aws_cloudwatch_log_group.api
  id = "/aws/lambda/rag-chatbot-api"
}
