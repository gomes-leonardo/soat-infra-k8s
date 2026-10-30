variable "environment" {
  type = string

  validation {
    condition     = contains(["hml", "prd"], var.environment)
    error_message = "environment deve ser hml ou prd."
  }
}

variable "newrelic_region" {
  type    = string
  default = "US"
}

variable "newrelic_account_id" {
  type = number
}

variable "newrelic_api_key" {
  description = "User key (NRAK-...), nao a License key de ingestao."
  type        = string
  sensitive   = true
}
