terraform {
  required_version = ">= 1.10"

  required_providers {
    newrelic = {
      source  = "newrelic/newrelic"
      version = "~> 3.101"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # key por -backend-config: soat-infra-k8s/newrelic/<env>/terraform.tfstate.
  backend "s3" {
    region       = "sa-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

# Conta e User key chegam do CI por TF_VAR_newrelic_account_id e
# TF_VAR_newrelic_api_key.
provider "newrelic" {
  account_id = var.newrelic_account_id
  api_key    = var.newrelic_api_key
  region     = var.newrelic_region
}

provider "aws" {
  region = "sa-east-1"
}
