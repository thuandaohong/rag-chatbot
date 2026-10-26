# ============================================================
# modules/backend/iam.tf — Execution role cho Lambda (least-privilege)
# ============================================================

# ---- Trust policy: ai được "mặc" role này? -> dịch vụ Lambda ----
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.project}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# ---- Quyền ghi log CloudWatch (managed policy sẵn của AWS) ----
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ---- Quyền gọi Bedrock (least-privilege, khóa theo KB) ----
data "aws_iam_policy_document" "bedrock" {
  statement {
    sid     = "AllowBedrockRAG"
    effect  = "Allow"
    actions = ["bedrock:RetrieveAndGenerate", "bedrock:Retrieve"]
    resources = [
      var.kb_arn
    ]
  }
  statement {
    sid       = "AllowInvokeModel"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel"]
    resources = ["arn:aws:bedrock:${data.aws_region.current.region}::foundation-model/*"]
  }
}

resource "aws_iam_role_policy" "bedrock" {
  name   = "${var.project}-bedrock-rag"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.bedrock.json
}
