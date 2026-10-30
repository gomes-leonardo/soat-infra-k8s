data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "fiap-software-architecture"
  }, var.extra_tags)

  azs = length(var.azs) > 0 ? var.azs : slice(data.aws_availability_zones.available.names, 0, 2)

  # Subnets derivadas do CIDR da VPC. Com 10.0.0.0/16 isso da /20 (4091 IPs
  # utilizaveis por subnet) — folga suficiente para o CNI da AWS, que consome
  # um IP da VPC por pod.
  public_subnet_cidrs  = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnet_cidrs = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, i + 8)]

  # ---------------------------------------------------------------------------
  # Perfis por ambiente. dev e barato e descartavel; prod tem redundancia.
  # Os defaults sao os conservadores: nada aqui apaga dado sem aviso em prod.
  # ---------------------------------------------------------------------------
  env_profiles = {
    dev = {
      single_nat_gateway  = true
      node_instance_types = ["t3.medium"]
      node_desired_size   = 2
      node_min_size       = 2
      node_max_size       = 4
      node_capacity_type  = "ON_DEMAND"
      node_disk_size      = 20


      log_retention_days = 7
    }

    prod = {
      single_nat_gateway  = false
      node_instance_types = ["t3.large"]
      node_desired_size   = 3
      node_min_size       = 3
      node_max_size       = 10
      node_capacity_type  = "ON_DEMAND"
      node_disk_size      = 50


      log_retention_days = 30
    }
  }

  profile = local.env_profiles[var.environment]

  # Override explicito vence o perfil; null cai no perfil.
  node_instance_types = coalesce(var.node_instance_types, local.profile.node_instance_types)
  node_desired_size   = coalesce(var.node_desired_size, local.profile.node_desired_size)
  node_min_size       = coalesce(var.node_min_size, local.profile.node_min_size)
  node_max_size       = coalesce(var.node_max_size, local.profile.node_max_size)
  node_capacity_type  = coalesce(var.node_capacity_type, local.profile.node_capacity_type)

  cluster_name = "${local.name_prefix}-eks"
}

module "network" {
  source = "../network"

  name_prefix          = local.name_prefix
  cluster_name         = local.cluster_name
  vpc_cidr             = var.vpc_cidr
  azs                  = local.azs
  public_subnet_cidrs  = local.public_subnet_cidrs
  private_subnet_cidrs = local.private_subnet_cidrs
  single_nat_gateway   = local.profile.single_nat_gateway

  tags = local.common_tags
}

module "k8s" {
  source = "../k8s"

  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  public_subnet_ids  = module.network.public_subnet_ids

  node_instance_types = local.node_instance_types
  node_capacity_type  = local.node_capacity_type
  node_desired_size   = local.node_desired_size
  node_min_size       = local.node_min_size
  node_max_size       = local.node_max_size
  node_disk_size      = local.profile.node_disk_size

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.eks_public_access_cidrs
  cluster_log_retention_days   = local.profile.log_retention_days

  tags = local.common_tags
}

# O banco desta referencia (RDS) fica em soat-infra-db/reference/aws-rds.
