module "cloudtrail" {
  source = "./modules/cloudtrail"

  project_name = var.project_name
  account_id   = var.account_id
}

module "lambda" {
  source = "./modules/lambda"

  project_name            = var.project_name
  log_group_arn           = module.cloudtrail.log_group_arn
  log_group_name          = module.cloudtrail.log_group_name
  teams_webhook_login     = var.teams_webhook_login
  teams_webhook_delete    = var.teams_webhook_delete
  teams_webhook_billing   = var.teams_webhook_billing
  azure_connection_string = var.azure_connection_string
  cloudtrail_bucket       = "aws-cloudtrail-logs-448768137813-05d6a32b"

  depends_on = [module.cloudtrail]
}

module "cloudwatch" {
  source = "./modules/cloudwatch"

  project_name   = var.project_name
  log_group_name = module.cloudtrail.log_group_name

  depends_on = [module.cloudtrail]
}

module "billing" {
  source = "./modules/billing"

  project_name       = var.project_name
  lambda_billing_arn = module.lambda.lambda_billing_arn

  depends_on = [module.lambda]
}

module "azure_monitor" {
  source = "./modules/azure_monitor"

  project_name             = var.project_name
  resource_group_name      = var.azure_resource_group
  location                 = var.azure_location
  azure_connection_string  = var.azure_connection_string
}