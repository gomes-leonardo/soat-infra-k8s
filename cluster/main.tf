locals {
  # Cada ambiente expoe o proprio Kong numa porta do host, so em loopback.
  gateway_ports = {
    "soat-prd" = { node_port = 30080, host_port = 18080 }
    "soat-hml" = { node_port = 30081, host_port = 18081 }
  }
  namespaces = concat(keys(local.gateway_ports), ["observability"])
}

resource "kind_cluster" "this" {
  name            = var.cluster_name
  node_image      = var.node_image
  kubeconfig_path = pathexpand(var.kubeconfig_path)
  wait_for_ready  = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      dynamic "extra_port_mappings" {
        for_each = local.gateway_ports
        content {
          container_port = extra_port_mappings.value.node_port
          host_port      = extra_port_mappings.value.host_port
          listen_address = "127.0.0.1"
          protocol       = "TCP"
        }
      }
    }

    dynamic "node" {
      for_each = range(var.worker_count)
      content {
        role = "worker"
      }
    }
  }
}

# Homologacao e producao como namespaces do mesmo cluster: isolamento de
# nomes, Secrets e quotas, a custo zero. Registrado em ADR.
resource "kubernetes_namespace" "this" {
  for_each = toset(local.namespaces)

  metadata {
    name = each.value
    labels = {
      "app.kubernetes.io/part-of" = "soat"
      "soat/environment"          = each.value == "observability" ? "shared" : trimprefix(each.value, "soat-")
    }
  }

  depends_on = [kind_cluster.this]
}

# Teto por ambiente: um rollout descontrolado em hml nao derruba prd.
resource "kubernetes_resource_quota" "env" {
  for_each = local.gateway_ports

  metadata {
    name      = "env-quota"
    namespace = kubernetes_namespace.this[each.key].metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = each.key == "soat-prd" ? "4" : "2"
      "requests.memory" = each.key == "soat-prd" ? "4Gi" : "2Gi"
      pods              = each.key == "soat-prd" ? "30" : "15"
    }
  }
}

# Com ResourceQuota de CPU e memoria, todo pod sem requests e recusado. O
# LimitRange da um padrao para quem nao declarar (Jobs de migration, stand-ins).
resource "kubernetes_limit_range" "env" {
  for_each = local.gateway_ports

  metadata {
    name      = "env-defaults"
    namespace = kubernetes_namespace.this[each.key].metadata[0].name
  }

  spec {
    limit {
      type = "Container"
      default_request = {
        cpu    = "50m"
        memory = "64Mi"
      }
      default = {
        cpu    = "500m"
        memory = "512Mi"
      }
    }
  }
}

# O Kind nao traz metrics-server, e sem ele o HPA nao tem CPU para comparar.
# --kubelet-insecure-tls porque o kubelet do Kind usa certificado
# auto-assinado; aceitavel num cluster local e descartavel.
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_chart_version
  namespace  = "kube-system"

  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }

  set {
    name  = "args[1]"
    value = "--kubelet-preferred-address-types=InternalIP\\,Hostname"
  }

  depends_on = [kind_cluster.this]
}
