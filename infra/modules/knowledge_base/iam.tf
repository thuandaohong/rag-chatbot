# ============================================================
# modules/knowledge_base/iam.tf — Service role cho Knowledge Base (import từ role console tạo)
# Bedrock "mặc" role này để đọc PDF từ bucket docs + ghi metric CloudWatch.
# Tên có hậu tố _orwig do console sinh ra — giữ nguyên để import, không đổi tên.
# ============================================================

# ---- Trust policy: chỉ Bedrock, và chỉ KB trong đúng account/region này ----
data "aws_iam_policy_document" "kb_assume" {
  statement {
    sid     = "TrustPolicyStatement"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:bedrock:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:knowledge-base/*"]
    }
  }
}

resource "aws_iam_role" "kb" {
  name               = "AmazonBedrockExecutionRoleForKnowledgeBase_orwig"
  path               = "/service-role/"
  description        = "Bedrock Knowledge Base access"
  assume_role_policy = data.aws_iam_policy_document.kb_assume.json
}

# ---- Quyền đọc PDF trong bucket docs (least-privilege: đúng 1 bucket) ----
data "aws_iam_policy_document" "kb_s3" {
  statement {
    sid       = "S3ListBucketStatement"
    actions   = ["s3:ListBucket"]
    resources = [var.docs_bucket_arn]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
  statement {
    sid       = "S3GetObjectStatement"
    actions   = ["s3:GetObject"]
    resources = ["${var.docs_bucket_arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_policy" "kb_s3" {
  name   = "AmazonBedrockS3PolicyForKnowledgeBase_orwig"
  path   = "/service-role/"
  policy = data.aws_iam_policy_document.kb_s3.json
}

# ---- Quyền ghi metric CloudWatch (chỉ namespace của KB) ----
data "aws_iam_policy_document" "kb_logs" {
  statement {
    sid       = "CloudWatchWritePermissionStatement"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["AWS/Bedrock/KnowledgeBases"]
    }
  }
}

resource "aws_iam_policy" "kb_logs" {
  name   = "AmazonBedrockCloudWatchPolicyForKnowledgeBase_orwig"
  path   = "/service-role/"
  policy = data.aws_iam_policy_document.kb_logs.json
}

resource "aws_iam_role_policy_attachment" "kb_s3" {
  role       = aws_iam_role.kb.name
  policy_arn = aws_iam_policy.kb_s3.arn
}

resource "aws_iam_role_policy_attachment" "kb_logs" {
  role       = aws_iam_role.kb.name
  policy_arn = aws_iam_policy.kb_logs.arn
}
