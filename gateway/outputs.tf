output "gateway_url" {
  value = "http://localhost:${var.environment == "prd" ? 18080 : 18081}"
}

output "auth_mode" {
  value = var.auth_mode
}
