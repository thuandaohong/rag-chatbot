# ============================================================
# tf_roles.tf — 2 role cho pipeline Terraform (Day 34), xác thực qua OIDC
#
#   rag-chatbot-tf-plan  : job `plan` trên Pull Request  -> CHỈ ĐỌC
#   rag-chatbot-tf-apply : job `apply` trong environment production -> GHI
#
# Vì sao tách 2 role: role của job plan assume được từ MỌI PR. Nếu nó có quyền
# ghi, ai mở PR cũng sửa được workflow trong PR đó để chạy `apply` và bỏ qua bước
# duyệt. Tách ra -> quyền ghi chỉ lấy được khi job đã vào environment production
# (tức đã qua Required reviewers).
#
# BOOTSTRAP: pipeline cần 2 role này mới chạy được -> lần đầu phải apply ở máy.
# ============================================================

data "aws_caller_identity" "current" {}

locals {
  tf_state_bucket = "rag-chatbot-tfstate-thuan-20261024" # khớp backend "s3" trong providers.tf
  tf_state_key    = "rag-chatbot/terraform.tfstate"

  # Phần đầu claim `sub` (2 định dạng, xem github_oidc.tf); phần sau đổi theo ngữ cảnh job
  github_sub_prefixes = [
    "repo:${local.github_owner}@${var.github_owner_id}/${local.github_name}@${var.github_repo_id}",
    "repo:${var.github_repo}",
  ]
}

# ============================================================
# 1) PLAN role — chỉ đọc
# ============================================================

data "aws_iam_policy_document" "tf_plan_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Job chạy trên PR có sub = repo:...:pull_request (KHÔNG phải ref:refs/heads/main)
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for p in local.github_sub_prefixes : "${p}:pull_request"]
    }
  }
}

resource "aws_iam_role" "tf_plan" {
  name               = "${var.project}-tf-plan"
  assume_role_policy = data.aws_iam_policy_document.tf_plan_assume.json
}

# Đọc được mọi resource để refresh state + so sánh với code
resource "aws_iam_role_policy_attachment" "tf_plan_readonly" {
  role       = aws_iam_role.tf_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Ghi DUY NHẤT file khóa state (use_lockfile tạo/xóa <key>.tflock khi plan)
data "aws_iam_policy_document" "tf_plan_lock" {
  statement {
    sid       = "StateLockFile"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${local.tf_state_bucket}/${local.tf_state_key}.tflock"]
  }
}

resource "aws_iam_role_policy" "tf_plan_lock" {
  name   = "${var.project}-tf-plan-lock"
  role   = aws_iam_role.tf_plan.id
  policy = data.aws_iam_policy_document.tf_plan_lock.json
}

# ============================================================
# 2) APPLY role — ghi, chỉ khi job chạy trong environment production
# ============================================================

data "aws_iam_policy_document" "tf_apply_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Job có `environment: production` có sub = repo:...:environment:production
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for p in local.github_sub_prefixes : "${p}:environment:production"]
    }
  }
}

resource "aws_iam_role" "tf_apply" {
  name               = "${var.project}-tf-apply"
  assume_role_policy = data.aws_iam_policy_document.tf_apply_assume.json
}

# Mọi dịch vụ TRỪ IAM/Organizations/Account (S3, Lambda, API GW, Bedrock, CloudFront...)
resource "aws_iam_role_policy_attachment" "tf_apply_poweruser" {
  role       = aws_iam_role.tf_apply.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# IAM: chỉ trên role/policy của project này, không phải toàn account.
# Lưu ý: rag-chatbot-* gồm cả chính role này -> Terraform tự quản role của nó
# (bản chất của việc để Terraform quản quyền của chính pipeline).
data "aws_iam_policy_document" "tf_apply_iam" {
  statement {
    sid     = "ManageProjectIam"
    actions = ["iam:*"]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project}-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/service-role/AmazonBedrockExecutionRoleForKnowledgeBase_*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/service-role/AmazonBedrock*ForKnowledgeBase_*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com",
    ]
  }
  # Đọc managed policy của AWS (ReadOnlyAccess, PowerUserAccess, AWSLambdaBasicExecutionRole...)
  statement {
    sid       = "ReadAwsManagedPolicies"
    actions   = ["iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicyVersions"]
    resources = ["arn:aws:iam::aws:policy/*"]
  }
}

resource "aws_iam_role_policy" "tf_apply_iam" {
  name   = "${var.project}-tf-apply-iam"
  role   = aws_iam_role.tf_apply.id
  policy = data.aws_iam_policy_document.tf_apply_iam.json
}

output "tf_plan_role_arn" {
  value = aws_iam_role.tf_plan.arn # -> GitHub secret AWS_TF_PLAN_ROLE_ARN
}

output "tf_apply_role_arn" {
  value = aws_iam_role.tf_apply.arn # -> GitHub secret AWS_TF_APPLY_ROLE_ARN
}
