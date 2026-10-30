output "vpc_id" {
  description = "Id da VPC criada."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "Bloco CIDR da VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Ids das subnets publicas."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Ids das subnets privadas."
  value       = aws_subnet.private[*].id
}

output "nat_gateway_public_ips" {
  description = "IPs publicos de saida dos NAT Gateways. Uteis para liberar em firewalls de terceiros."
  value       = aws_eip.nat[*].public_ip
}
