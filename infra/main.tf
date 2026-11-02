# ============================================================
# main.tf — gọi & nối các module (output module này -> input module kia)
#   storage ──> knowledge_base ──> backend <── guardrail
#      └──────> frontend
# ============================================================

module "storage" {
  source           = "./modules/storage"
  docs_bucket_name = "rag-chatbot-docs-thuan-20261012"
  web_bucket_name  = "rag-chatbot-web-thuan-20261012"
}

module "knowledge_base" {
  source           = "./modules/knowledge_base"
  project          = var.project
  docs_bucket_name = module.storage.docs_bucket_name
  docs_bucket_arn  = module.storage.docs_bucket_arn
}

module "backend" {
  source              = "./modules/backend"
  project             = var.project
  model_id            = var.model_id
  kb_id               = module.knowledge_base.kb_id
  kb_arn              = module.knowledge_base.kb_arn
  handler_source_file = "${path.root}/../backend/handler.py"
  build_dir           = "${path.root}/build"

  guardrail_id           = module.guardrail.guardrail_id
  guardrail_version      = module.guardrail.guardrail_version
  guardrail_arn          = module.guardrail.guardrail_arn
  guardrail_profile_arns = module.guardrail.guardrail_profile_arns
}

module "frontend" {
  source                          = "./modules/frontend"
  project                         = var.project
  web_bucket_id                   = module.storage.web_bucket_id
  web_bucket_arn                  = module.storage.web_bucket_arn
  web_bucket_regional_domain_name = module.storage.web_bucket_regional_domain_name
}

module "guardrail" {
  source  = "./modules/guardrail"
  project = var.project
}

module "monitoring" {
  source         = "./modules/monitoring"
  project        = var.project
  region         = var.region
  log_group_name = module.backend.log_group_name
  function_name  = module.backend.lambda_function_name
  api_id         = module.backend.api_id
  alert_email    = var.alert_email
}
