variable "name_prefix" {
  description = "Prefixo aplicado ao nome de todos os recursos de rede."
  type        = string
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC. Precisa comportar as subnets publicas e privadas."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr precisa ser um bloco CIDR IPv4 valido (ex.: 10.0.0.0/16)."
  }
}

variable "azs" {
  description = "Zonas de disponibilidade usadas. O EKS exige no minimo duas."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "O EKS exige subnets em pelo menos duas zonas de disponibilidade."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets publicas, na mesma ordem de azs."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas, na mesma ordem de azs."
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "true cria um unico NAT Gateway compartilhado (barato, ponto unico de falha). false cria um por AZ."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Nome do cluster EKS, usado nas tags de descoberta de subnet do Kubernetes."
  type        = string
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos do modulo."
  type        = map(string)
  default     = {}
}
