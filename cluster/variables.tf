variable "cluster_name" {
  type    = string
  default = "soat"
}

variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}

variable "node_image" {
  type    = string
  default = "kindest/node:v1.36.1"
}

variable "worker_count" {
  description = "Workers alem do control-plane. Um basta para o HPA e cabe em 8 GB de Docker."
  type        = number
  default     = 1
}

variable "metrics_server_chart_version" {
  type    = string
  default = "3.12.2"
}
