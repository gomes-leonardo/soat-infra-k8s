output "kube_context" {
  value = "kind-${var.cluster_name}"
}

output "gateway_urls" {
  description = "Kong de cada ambiente, no host."
  value       = { for ns, p in local.gateway_ports : ns => "http://localhost:${p.host_port}" }
}
