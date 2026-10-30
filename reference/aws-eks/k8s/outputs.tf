output "cluster_name" {
  description = "Nome do cluster EKS."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Endpoint HTTPS do servidor de API do Kubernetes."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "CA do cluster, em base64. Entra no kubeconfig."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_version" {
  description = "Versao do Kubernetes em execucao."
  value       = aws_eks_cluster.this.version
}

output "cluster_security_group_id" {
  description = "Security group gerenciado pelo EKS e anexado aos nodes. E a origem que o security group do RDS libera."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "cluster_oidc_issuer_url" {
  description = "URL do issuer OIDC do cluster."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "ARN do provedor OIDC no IAM. Usado nas trust policies de IRSA."
  value       = aws_iam_openid_connect_provider.this.arn
}

output "node_group_name" {
  description = "Nome do managed node group."
  value       = aws_eks_node_group.this.node_group_name
}

output "node_role_arn" {
  description = "ARN da role IAM dos nodes."
  value       = aws_iam_role.node.arn
}
