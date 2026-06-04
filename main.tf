module "cloudtrail" {
  source = "./modules/cloudtrail"

  project_name = var.project_name
  account_id   = var.account_id
}

module "lambda" {
  source = "./modules/lambda"

  project_name         = var.project_name
  log_group_arn        = module.cloudtrail.log_group_arn
  log_group_name       = module.cloudtrail.log_group_name
  teams_webhook_login  = var.teams_webhook_login
  teams_webhook_delete = var.teams_webhook_delete

  depends_on = [module.cloudtrail]
}

module "cloudwatch" {
  source = "./modules/cloudwatch"

  project_name   = var.project_name
  log_group_name = module.cloudtrail.log_group_name

  depends_on = [module.cloudtrail]
}