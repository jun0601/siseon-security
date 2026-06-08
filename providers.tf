terraform {
  required_version = ">= 1.0"

  backend "s3" {
    bucket  = "siseon-terraform-state"
    key     = "security/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "siseon"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source = "hashicorp/archive"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = "siseon"
}

provider "aws" {
  alias   = "us_east_1"
  region  = "us-east-1"
  profile = "siseon"
}

provider "azurerm" {
  features {}
  tenant_id       = var.azure_tenant_id
  subscription_id = var.azure_subscription_id
}