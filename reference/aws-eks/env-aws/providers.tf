terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Backend parcial de proposito: bucket, tabela e chave mudam por ambiente e
  # nao podem ser interpolados aqui. Passe tudo em `-backend-config`:
  #
  #   terraform init -backend-config=backend.hcl
  #
  # Os recursos de backend sao criados por infra/bootstrap. Para rodar com
  # state local (avaliacao rapida), use `terraform init -backend=false` para
  # validar ou remova este bloco.
  backend "s3" {}
}

provider "aws" {
  region = var.region

  # Toda tag definida aqui e herdada por qualquer recurso que o provider crie,
  # inclusive os que os modulos nao taggeiam explicitamente.
  default_tags {
    tags = local.common_tags
  }
}
