locals {
  namespace = "observability"

  # Destino de cada sinal. Antes da ativacao, equivalentes locais: Jaeger para
  # traces, endpoint Prometheus para metricas, stdout para logs.
  # jsonencode/jsondecode: os dois ramos tem formatos diferentes, e o
  # Terraform exige o mesmo tipo dos dois lados de um condicional.
  exporters = jsondecode(var.newrelic_enabled ? jsonencode({
    otlphttp = {
      endpoint    = var.newrelic_otlp_endpoint
      headers     = { "api-key" = "$${env:NEW_RELIC_LICENSE_KEY}" }
      compression = "gzip"
    }
    }) : jsonencode({
    "otlp/jaeger" = {
      endpoint = "jaeger.${local.namespace}.svc.cluster.local:4317"
      tls      = { insecure = true }
    }
    prometheus = { endpoint = "0.0.0.0:8889" }
    debug      = { verbosity = "basic" }
  }))

  traces_exporters  = var.newrelic_enabled ? ["otlphttp"] : ["otlp/jaeger"]
  metrics_exporters = var.newrelic_enabled ? ["otlphttp"] : ["prometheus"]
  logs_exporters    = var.newrelic_enabled ? ["otlphttp"] : ["debug"]

  # O New Relic prefere metricas em delta; o scrape Prometheus entrega cumulativo.
  metrics_processors = var.newrelic_enabled ? ["memory_limiter", "cumulativetodelta", "batch"] : ["memory_limiter", "batch"]

  license_env = jsondecode(var.newrelic_enabled ? jsonencode([{
    name = "NEW_RELIC_LICENSE_KEY"
    valueFrom = {
      secretKeyRef = { name = kubernetes_secret.newrelic[0].metadata[0].name, key = "license-key" }
    }
  }]) : "[]")
}

check "newrelic_has_key" {
  assert {
    condition     = !var.newrelic_enabled || length(var.newrelic_license_key) > 0
    error_message = "newrelic_enabled = true exige newrelic_license_key."
  }
}

resource "kubernetes_secret" "newrelic" {
  count = var.newrelic_enabled ? 1 : 0

  metadata {
    name      = "nr-license"
    namespace = local.namespace
  }
  data = {
    "license-key" = var.newrelic_license_key
  }
}

# ---------------------------------------------------------------------------
# Gateway: um pod que recebe OTLP da aplicacao, raspa o /metrics dos pods
# anotados, mede o uptime pelo Kong de cada ambiente e le o estado do cluster.
# Tudo sai por aqui.
# ---------------------------------------------------------------------------

resource "helm_release" "gateway" {
  name       = "otel-gateway"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  version    = var.collector_chart_version
  namespace  = local.namespace

  values = [yamlencode({
    mode             = "deployment"
    fullnameOverride = "otel-gateway"
    image            = { repository = var.collector_image }
    replicaCount     = 1
    presets = {
      clusterMetrics = { enabled = true }
    }
    clusterRole = {
      create = true
      rules = [{
        apiGroups = [""]
        resources = ["pods", "nodes", "endpoints", "services"]
        verbs     = ["get", "list", "watch"]
      }]
    }
    extraEnvs = local.license_env
    ports = {
      jaeger-compact = { enabled = false }
      jaeger-thrift  = { enabled = false }
      jaeger-grpc    = { enabled = false }
      zipkin         = { enabled = false }
      prom-export = {
        enabled       = !var.newrelic_enabled
        containerPort = 8889
        servicePort   = 8889
        protocol      = "TCP"
      }
    }
    resources = {
      requests = { cpu = "50m", memory = "128Mi" }
      limits   = { memory = "320Mi" }
    }
    config = {
      receivers = {
        otlp = {
          protocols = {
            grpc = { endpoint = "0.0.0.0:4317" }
            http = { endpoint = "0.0.0.0:4318" }
          }
        }
        # /metrics da aplicacao (porta 9464), descoberto pela anotacao do pod.
        prometheus = {
          config = {
            scrape_configs = [{
              job_name        = "soat-pods"
              scrape_interval = "30s"
              kubernetes_sd_configs = [{
                role       = "pod"
                namespaces = { names = ["soat-hml", "soat-prd"] }
              }]
              relabel_configs = [
                {
                  source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_scrape"]
                  action        = "keep"
                  regex         = "true"
                },
                {
                  source_labels = ["__address__", "__meta_kubernetes_pod_annotation_prometheus_io_port"]
                  action        = "replace"
                  regex         = "([^:]+)(?::\\d+)?;(\\d+)"
                  replacement   = "$1:$2"
                  target_label  = "__address__"
                },
                {
                  source_labels = ["__meta_kubernetes_namespace"]
                  target_label  = "k8s_namespace_name"
                },
                {
                  source_labels = ["__meta_kubernetes_pod_name"]
                  target_label  = "k8s_pod_name"
                },
              ]
            }]
          }
        }
        # Uptime medido pelo caminho do usuario: Kong -> app -> banco.
        httpcheck = {
          collection_interval = "30s"
          targets = [
            { endpoint = "http://kong-proxy.soat-prd.svc.cluster.local/health", method = "GET" },
            { endpoint = "http://kong-proxy.soat-hml.svc.cluster.local/health", method = "GET" },
          ]
        }
      }
      processors = {
        batch = {}
        memory_limiter = {
          check_interval  = "5s"
          limit_mib       = 256
          spike_limit_mib = 64
        }
        cumulativetodelta = {}
      }
      exporters = local.exporters
      service = {
        pipelines = {
          traces = {
            receivers  = ["otlp"]
            processors = ["memory_limiter", "batch"]
            exporters  = local.traces_exporters
          }
          metrics = {
            receivers  = ["otlp", "prometheus", "httpcheck", "k8s_cluster"]
            processors = local.metrics_processors
            exporters  = local.metrics_exporters
          }
          logs = {
            receivers  = ["otlp"]
            processors = ["memory_limiter", "batch"]
            exporters  = local.logs_exporters
          }
        }
      }
    }
  })]

  depends_on = [kubernetes_deployment.jaeger]
}

# ---------------------------------------------------------------------------
# Agente: um pod por node, para o que so o node enxerga. CPU e memoria de cada
# pod (kubelet) e os logs dos containers dos ambientes soat-*. Envia tudo ao
# gateway por OTLP.
# ---------------------------------------------------------------------------

resource "helm_release" "agent" {
  name       = "otel-agent"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  version    = var.collector_chart_version
  namespace  = local.namespace

  values = [yamlencode({
    mode             = "daemonset"
    fullnameOverride = "otel-agent"
    image            = { repository = var.collector_image }
    presets = {
      kubeletMetrics       = { enabled = true }
      kubernetesAttributes = { enabled = true }
      logsCollection       = { enabled = true }
    }
    ports = {
      otlp           = { enabled = false }
      otlp-http      = { enabled = false }
      jaeger-compact = { enabled = false }
      jaeger-thrift  = { enabled = false }
      jaeger-grpc    = { enabled = false }
      zipkin         = { enabled = false }
    }
    resources = {
      requests = { cpu = "25m", memory = "64Mi" }
      limits   = { memory = "200Mi" }
    }
    config = {
      receivers = {
        # So os ambientes da oficina; o log da aplicacao e JSON (pino) e vira
        # atributos, trace_id incluso, para a correlacao log-trace funcionar.
        filelog = {
          include = ["/var/log/pods/soat-*_*/*/*.log"]
          operators = [
            { type = "container", id = "container-parser" },
            {
              type       = "json_parser"
              id         = "app-json"
              parse_from = "body"
              parse_to   = "attributes"
              if         = "body matches \"^\\\\{\""
              on_error   = "send_quiet"
            },
          ]
        }
        kubeletstats = {
          collection_interval = "30s"
        }
      }
      processors = {
        batch = {}
        memory_limiter = {
          check_interval  = "5s"
          limit_mib       = 160
          spike_limit_mib = 40
        }
      }
      exporters = {
        "otlp/gateway" = {
          endpoint = "otel-gateway.${local.namespace}.svc.cluster.local:4317"
          tls      = { insecure = true }
        }
      }
      service = {
        pipelines = {
          traces = null
          metrics = {
            receivers  = ["kubeletstats"]
            processors = ["memory_limiter", "k8sattributes", "batch"]
            exporters  = ["otlp/gateway"]
          }
          logs = {
            receivers  = ["filelog"]
            processors = ["memory_limiter", "k8sattributes", "batch"]
            exporters  = ["otlp/gateway"]
          }
        }
      }
    }
  })]

  depends_on = [helm_release.gateway]
}

# ---------------------------------------------------------------------------
# Jaeger: destino local dos traces ate a ativacao do New Relic.
# ---------------------------------------------------------------------------

resource "kubernetes_deployment" "jaeger" {
  metadata {
    name      = "jaeger"
    namespace = local.namespace
    labels    = { "app.kubernetes.io/name" = "jaeger" }
  }

  spec {
    replicas = var.newrelic_enabled ? 0 : 1
    selector {
      match_labels = { "app.kubernetes.io/name" = "jaeger" }
    }
    template {
      metadata {
        labels = { "app.kubernetes.io/name" = "jaeger" }
      }
      spec {
        container {
          name  = "jaeger"
          image = "jaegertracing/all-in-one:1.62.0"
          port {
            name           = "otlp-grpc"
            container_port = 4317
          }
          port {
            name           = "ui"
            container_port = 16686
          }
          resources {
            requests = { cpu = "25m", memory = "64Mi" }
            limits   = { memory = "256Mi" }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "jaeger" {
  metadata {
    name      = "jaeger"
    namespace = local.namespace
  }
  spec {
    selector = { "app.kubernetes.io/name" = "jaeger" }
    port {
      name        = "otlp-grpc"
      port        = 4317
      target_port = "otlp-grpc"
    }
    port {
      name        = "ui"
      port        = 16686
      target_port = "ui"
    }
  }
}
