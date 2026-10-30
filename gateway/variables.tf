variable "environment" {
  description = "hml (branch develop) ou prd (branch main)."
  type        = string

  validation {
    condition     = contains(["hml", "prd"], var.environment)
    error_message = "environment deve ser hml ou prd."
  }
}

variable "auth_mode" {
  description = "local: /auth/cpf vai para o substituto no cluster. lambda: vai para a Function URL."
  type        = string
  default     = "local"

  validation {
    condition     = contains(["local", "lambda"], var.auth_mode)
    error_message = "auth_mode deve ser local ou lambda."
  }
}

variable "auth_function_url" {
  description = "Function URL da autenticacao por CPF (output do soat-auth-lambda). Obrigatoria com auth_mode = lambda."
  type        = string
  default     = ""
}

variable "kong_image" {
  type    = string
  default = "kong:3.9"
}

variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}

variable "kube_context" {
  type    = string
  default = "kind-soat"
}

variable "region" {
  type    = string
  default = "sa-east-1"
}
