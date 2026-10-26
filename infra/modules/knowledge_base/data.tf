# Account id / region hiện tại để dựng ARN động (không hardcode)
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
