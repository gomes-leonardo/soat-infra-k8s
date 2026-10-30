data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Cluster.
# ---------------------------------------------------------------------------

output "region" {
  description = "Regiao da AWS onde a stack foi provisionada."
  value       = var.region
}

output "environment" {
  description = "Ambiente provisionado (dev ou prod)."
  value       = var.environment
}

output "cluster_name" {
  description = "Nome do cluster EKS."
  value       = module.k8s.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint do servidor de API do Kubernetes."
  value       = module.k8s.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "CA do cluster em base64."
  value       = module.k8s.cluster_certificate_authority_data
}

output "cluster_version" {
  description = "Versao do Kubernetes."
  value       = module.k8s.cluster_version
}

output "cluster_security_group_id" {
  description = "Security group dos nodes do EKS."
  value       = module.k8s.cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN do provedor OIDC do cluster (IRSA)."
  value       = module.k8s.oidc_provider_arn
}

# ---------------------------------------------------------------------------
# Banco.
# ---------------------------------------------------------------------------

output "db_endpoint" {
  description = "Endpoint do RDS no formato host:porta."
  value       = module.database.db_endpoint
}

output "db_address" {
  description = "Hostname do RDS. Valor de DB_HOST."
  value       = module.database.db_address
}

output "db_port" {
  description = "Porta do Postgres. Valor de DB_PORT."
  value       = module.database.db_port
}

output "db_name" {
  description = "Nome do banco. Valor de DB_NAME."
  value       = module.database.db_name
}

output "db_username" {
  description = "Usuario do banco. Valor de DB_USER."
  value       = module.database.db_username
}

output "db_secret_arn" {
  description = "ARN do segredo no Secrets Manager com DB_HOST, DB_PORT, DB_NAME, DB_USER e DB_PASS."
  value       = module.database.db_secret_arn
}

output "db_secret_name" {
  description = "Nome do segredo no Secrets Manager."
  value       = module.database.db_secret_name
}

output "db_password" {
  description = "Senha do banco. Marcada como sensivel: use `terraform output -raw db_password` ou, de preferencia, leia do Secrets Manager."
  value       = module.database.db_password
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Rede.
# ---------------------------------------------------------------------------

output "vpc_id" {
  description = "Id da VPC."
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "Ids das subnets publicas."
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Ids das subnets privadas."
  value       = module.network.private_subnet_ids
}

# ---------------------------------------------------------------------------
# Acesso.
# ---------------------------------------------------------------------------

output "kubeconfig_command" {
  description = "Comando que escreve o contexto do cluster no kubeconfig local."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.k8s.cluster_name}"
}

output "kubeconfig" {
  description = <<-EOT
    Kubeconfig completo do cluster, pronto para gravar em arquivo. A autenticacao
    e delegada ao `aws eks get-token`, entao quem usar este arquivo precisa de
    credenciais AWS validas com acesso ao cluster.

      terraform output -raw kubeconfig > ~/.kube/soat.yaml
      KUBECONFIG=~/.kube/soat.yaml kubectl get nodes
  EOT

  sensitive = true

  value = yamlencode({
    apiVersion = "v1"
    kind       = "Config"

    clusters = [{
      name = module.k8s.cluster_name
      cluster = {
        server                     = module.k8s.cluster_endpoint
        certificate-authority-data = module.k8s.cluster_certificate_authority_data
      }
    }]

    contexts = [{
      name = module.k8s.cluster_name
      context = {
        cluster = module.k8s.cluster_name
        user    = module.k8s.cluster_name
      }
    }]

    current-context = module.k8s.cluster_name

    users = [{
      name = module.k8s.cluster_name
      user = {
        exec = {
          apiVersion = "client.authentication.k8s.io/v1beta1"
          command    = "aws"
          args = [
            "--region", var.region,
            "eks", "get-token",
            "--cluster-name", module.k8s.cluster_name,
            "--output", "json",
          ]
        }
      }
    }]
  })
}

output "account_id" {
  description = "Conta AWS onde a stack vive. Util para montar ARNs no pipeline."
  value       = data.aws_caller_identity.current.account_id
}
