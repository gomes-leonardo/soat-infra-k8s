terraform {
  required_version = ">= 1.10"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.13"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }

  # O state descreve um cluster que vive no Docker da maquina do runner: fica
  # nela, fora do S3. O caminho chega por -backend-config no init
  # (ver README): $HOME/.soat-tfstate/cluster.tfstate.
  backend "local" {}
}

provider "kind" {}

# Valores estaticos: o plan nao depende do cluster existir, e a conexao so
# abre quando um recurso Kubernetes e aplicado, com o cluster ja de pe.
provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig_path)
  config_context = "kind-${var.cluster_name}"
}

provider "helm" {
  kubernetes {
    config_path    = pathexpand(var.kubeconfig_path)
    config_context = "kind-${var.cluster_name}"
  }
}
