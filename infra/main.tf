# ============================================================
# main.tf — gọi & nối các module (output module này -> input module kia)
#   storage ──> knowledge_base ──> backend
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
}

module "frontend" {
  source                          = "./modules/frontend"
  project                         = var.project
  web_bucket_id                   = module.storage.web_bucket_id
  web_bucket_arn                  = module.storage.web_bucket_arn
  web_bucket_regional_domain_name = module.storage.web_bucket_regional_domain_name
}
