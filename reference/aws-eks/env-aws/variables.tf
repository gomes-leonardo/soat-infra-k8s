variable "project" {
  description = "Nome do projeto. Vira prefixo dos recursos e a tag Project."
  type        = string
  default     = "soat-tech-challenge"
}

variable "environment" {
  description = "Ambiente. Escolhe o perfil de dimensionamento e vira a tag Environment."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment precisa ser dev ou prod."
  }
}

variable "region" {
  description = "Regiao da AWS."
  type        = string
  default     = "us-east-1"
}

variable "azs" {
  description = "Zonas de disponibilidade. Deixe vazio para usar as duas primeiras da regiao."
  type        = list(string)
  default     = []
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "kubernetes_version" {
  description = "Versao do control plane do EKS."
  type        = string
  default     = "1.31"
}

variable "postgres_version" {
  description = "Versao do PostgreSQL no RDS. Espelha o postgres:16-alpine do docker-compose."
  type        = string
  default     = "16.4"
}

variable "db_name" {
  description = "Nome do banco criado no RDS."
  type        = string
  default     = "soat_repair_shop"
}

variable "db_username" {
  description = "Usuario master do RDS. A senha nunca vem daqui — e gerada por random_password e guardada no Secrets Manager."
  type        = string
  default     = "soat_app"
}

variable "eks_public_access_cidrs" {
  description = "CIDRs autorizados a acessar o endpoint publico da API do Kubernetes. Restrinja para o IP do escritorio e o do runner de CI em prod."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ---------------------------------------------------------------------------
# Overrides opcionais. null = usa o default do perfil do ambiente definido em
# main.tf. Existem para ajustar um valor pontual sem editar o perfil inteiro.
# ---------------------------------------------------------------------------

variable "node_instance_types" {
  description = "Override dos tipos de instancia dos nodes."
  type        = list(string)
  default     = null
}

variable "node_desired_size" {
  description = "Override da quantidade desejada de nodes."
  type        = number
  default     = null
}

variable "node_min_size" {
  description = "Override do minimo de nodes."
  type        = number
  default     = null
}

variable "node_max_size" {
  description = "Override do maximo de nodes."
  type        = number
  default     = null
}

variable "node_capacity_type" {
  description = "Override do tipo de capacidade dos nodes. SPOT corta ~70% do custo de EC2 ao preco de interrupcoes — aceitavel em dev, discutivel em prod."
  type        = string
  default     = null
}

variable "db_instance_class" {
  description = "Override da classe da instancia RDS."
  type        = string
  default     = null
}

variable "extra_tags" {
  description = "Tags adicionais aplicadas a todos os recursos."
  type        = map(string)
  default     = {}
}
