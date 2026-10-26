# ============================================================
# modules/knowledge_base — Bedrock Knowledge Base (loại MANAGED) + data source S3
# KB tạo bằng console (Day 5-7) -> import vào state.
# Cần provider aws >= 6.56 (bản đầu tiên hỗ trợ type = "MANAGED").
# ============================================================

# ---- Knowledge Base: AWS tự quản vector store + embedding (MANAGED) ----
resource "aws_bedrockagent_knowledge_base" "main" {
  name        = "${var.project}-kb"
  description = "RAG demo over my PDFs"
  role_arn    = aws_iam_role.kb.arn # service role, xem iam.tf

  knowledge_base_configuration {
    type = "MANAGED"
    managed_knowledge_base_configuration {
      embedding_model_type = "MANAGED" # AWS tự chọn model embedding
    }
  }
}

# ---- Data source: đọc PDF từ bucket docs (storage.tf) ----
resource "aws_bedrockagent_data_source" "docs" {
  knowledge_base_id    = aws_bedrockagent_knowledge_base.main.id
  name                 = "rag-docs-s3"
  data_deletion_policy = "DELETE" # xóa data source -> xóa luôn vector đã ingest

  data_source_configuration {
    type = "MANAGED_KNOWLEDGE_BASE_CONNECTOR"
    managed_knowledge_base_connector_configuration {
      connector_parameters = jsonencode({
        aclEnabled = false
        connectionConfiguration = {
          bucketArn            = var.docs_bucket_arn
          bucketName           = var.docs_bucket_name
          bucketOwnerAccountId = data.aws_caller_identity.current.account_id
        }
        filterConfiguration = {
          maxFileSizeInMegaBytes = "10240"
        }
        type    = "S3"
        version = "1"
      })
      deletion_protection_configuration {
        deletion_protection_status    = "DISABLED"
        deletion_protection_threshold = 15
      }
      media_extraction_configuration {
        audio_extraction_configuration {
          audio_extraction_status = "ENABLED"
        }
        image_extraction_configuration {
          image_extraction_status = "ENABLED"
        }
        video_extraction_configuration {
          video_extraction_status = "ENABLED"
        }
      }
    }
  }

  vector_ingestion_configuration {
    parsing_configuration {
      parsing_strategy = "SMART_PARSING"
    }
  }
}
