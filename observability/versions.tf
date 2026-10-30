terraform {
  required_version = ">= 1.10"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }

  # key por -backend-config: soat-infra-k8s/observability/terraform.tfstate.
  # Um so para o cluster: o namespace observability atende hml e prd.
  backend "s3" {
    region       = "sa-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig_path)
  config_context = var.kube_context
}

provider "helm" {
  kubernetes {
    config_path    = pathexpand(var.kubeconfig_path)
    config_context = var.kube_context
  }
}
