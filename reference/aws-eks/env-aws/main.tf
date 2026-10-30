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

      db_instance_class      = "db.t3.micro"
      db_allocated_storage   = 20
      db_multi_az            = false
      db_backup_retention    = 1
      db_deletion_protection = false
      db_skip_final_snapshot = true

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

      db_instance_class      = "db.t3.small"
      db_allocated_storage   = 50
      db_multi_az            = true
      db_backup_retention    = 7
      db_deletion_protection = true
      db_skip_final_snapshot = false

      log_retention_days = 30
    }
  }

  profile = local.env_profiles[var.environment]

  # Override explicito vence o perfil; null cai no perfil.
  node_instance_types = coalesce(var.node_instance_types, local.profile.node_instance_types)
  node_desired_size   = coalesce(var.node_desired_size, local.profile.node_desired_size)
  node_min_size       = coalesce(var.node_min_size, local.profile.node_min_size)
  node_max_size       = coalesce(var.node_max_size, local.profile.node_max_size)
  db_instance_class   = coalesce(var.db_instance_class, local.profile.db_instance_class)
  node_capacity_type  = coalesce(var.node_capacity_type, local.profile.node_capacity_type)

  cluster_name = "${local.name_prefix}-eks"
}

module "network" {
  source = "../../modules/network"

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
  source = "../../modules/k8s"

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

module "database" {
  source = "../../modules/database"

  identifier         = "${local.name_prefix}-pg"
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids

  # O unico caminho aberto ate a porta 5432 e o security group dos nodes do
  # EKS. Nao ha CIDR liberado, nem endereco publico.
  allowed_security_group_ids = [module.k8s.cluster_security_group_id]

  engine_version    = var.postgres_version
  instance_class    = local.db_instance_class
  allocated_storage = local.profile.db_allocated_storage
  multi_az          = local.profile.db_multi_az

  db_name     = var.db_name
  db_username = var.db_username

  backup_retention_days = local.profile.db_backup_retention
  deletion_protection   = local.profile.db_deletion_protection
  skip_final_snapshot   = local.profile.db_skip_final_snapshot

  tags = local.common_tags
}
