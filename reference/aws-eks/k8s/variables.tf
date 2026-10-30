variable "cluster_name" {
  description = "Nome do cluster EKS."
  type        = string
}

variable "kubernetes_version" {
  description = "Versao do control plane do EKS."
  type        = string
  default     = "1.31"
}

variable "vpc_id" {
  description = "VPC onde o cluster sobe."
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets privadas. Os nodes ficam aqui — nenhum node recebe IP publico."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Subnets publicas. Entram no vpc_config para que Services do tipo LoadBalancer consigam criar ELBs internet-facing."
  type        = list(string)
  default     = []
}

variable "node_instance_types" {
  description = "Tipos de instancia do managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND ou SPOT. SPOT corta ~70% do custo ao preco de interrupcoes."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type precisa ser ON_DEMAND ou SPOT."
  }
}

variable "node_desired_size" {
  description = "Quantidade desejada de nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimo de nodes do Auto Scaling Group."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximo de nodes. Precisa comportar o teto do HPA da aplicacao."
  type        = number
  default     = 4
}

variable "node_disk_size" {
  description = "Tamanho do disco EBS de cada node, em GiB."
  type        = number
  default     = 20
}

variable "endpoint_public_access" {
  description = "Expoe o endpoint da API do Kubernetes na internet. Necessario para kubectl e para o pipeline de CD rodarem de fora da VPC."
  type        = bool
  default     = true
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs autorizados a falar com o endpoint publico da API. Restrinja em prod."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_log_types" {
  description = "Tipos de log do control plane enviados ao CloudWatch."
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "cluster_log_retention_days" {
  description = "Retencao dos logs do control plane. Sem isso o log group nasce com retencao infinita."
  type        = number
  default     = 7
}

variable "addons" {
  description = "Add-ons gerenciados do EKS. metrics-server e pre-requisito do HPA — sem ele o HPA fica em <unknown>."
  type        = list(string)
  default     = ["vpc-cni", "coredns", "kube-proxy", "metrics-server"]
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos do modulo."
  type        = map(string)
  default     = {}
}
