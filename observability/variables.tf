variable "newrelic_enabled" {
  description = "false: traces no Jaeger, metricas em /metrics (8889), logs no stdout. true: tudo para o New Relic por OTLP."
  type        = bool
  default     = false
}

variable "newrelic_license_key" {
  description = "Ingest License Key do New Relic. Obrigatoria com newrelic_enabled = true."
  type        = string
  default     = ""
  sensitive   = true

  # validation, nao check: check so avisa, e o apply seguiria com a chave vazia,
  # o exporter levaria 403 e toda a telemetria se perderia em silencio.
  validation {
    condition     = !var.newrelic_enabled || length(var.newrelic_license_key) > 0
    error_message = "newrelic_enabled = true exige newrelic_license_key."
  }
}

variable "newrelic_otlp_endpoint" {
  description = "https://otlp.nr-data.net para contas US, https://otlp.eu01.nr-data.net para EU."
  type        = string
  default     = "https://otlp.nr-data.net"
}

variable "collector_chart_version" {
  type    = string
  default = "0.178.1"
}

variable "collector_image" {
  type    = string
  default = "otel/opentelemetry-collector-contrib"
}

variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}

variable "kube_context" {
  type    = string
  default = "kind-soat"
}
