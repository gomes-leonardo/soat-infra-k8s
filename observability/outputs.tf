output "otlp_endpoint" {
  description = "Para OTEL_EXPORTER_OTLP_ENDPOINT da aplicacao."
  value       = "http://otel-gateway.observability.svc.cluster.local:4318"
}

output "destination" {
  value = var.newrelic_enabled ? "New Relic (${var.newrelic_otlp_endpoint})" : "local: Jaeger, /metrics na 8889, stdout"
}
