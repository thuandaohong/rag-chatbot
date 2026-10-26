# ============================================================
# github_oidc.tf — Cho GitHub Actions deploy vào AWS qua OIDC
# (không dùng access key sống mãi)
# ============================================================

variable "github_repo" {
  description = "owner/repo trên GitHub, vd thuandaohong/rag-chatbot"
  type        = string
}

# ---- 1) OIDC provider: AWS tin GitHub làm nguồn danh tính ----
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # thumbprint: provider v6 tự xử; để danh sách này cho tương thích
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# ---- 2) Trust policy: CHỈ workflow của repo bạn mới assume được ----
data "aws_iam_policy_document" "gha_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    # điều kiện 1: token phải phát cho AWS STS
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # điều kiện 2: KHÓA đúng repo của bạn (chống confused deputy)
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${var.project}-gha-role"
  assume_role_policy = data.aws_iam_policy_document.gha_assume.json
}

# ---- 3) Permission policy: đúng những gì deploy cần (least-privilege) ----
data "aws_iam_policy_document" "gha_deploy" {
  # cập nhật code Lambda
  statement {
    sid       = "UpdateLambda"
    effect    = "Allow"
    actions   = ["lambda:UpdateFunctionCode", "lambda:GetFunction"]
    resources = [module.backend.lambda_function_arn]
  }
  # upload frontend lên bucket web
  statement {
    sid       = "SyncWebBucket"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
    resources = [module.storage.web_bucket_arn, "${module.storage.web_bucket_arn}/*"]
  }
  # invalidate cache CloudFront sau khi deploy frontend
  statement {
    sid       = "InvalidateCloudFront"
    effect    = "Allow"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [module.frontend.cloudfront_distribution_arn]
  }
}

resource "aws_iam_role_policy" "gha_deploy" {
  name   = "${var.project}-gha-deploy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.gha_deploy.json
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}
