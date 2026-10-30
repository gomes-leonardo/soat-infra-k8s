# Paineis da direcao (#62) e da operacao (#60). Cada widget diz a janela no
# titulo. Metricas de negocio so valem com soat_business_metrics_up = 1, e o
# tempo medio por status so com status_samples > 0: os dois aparecem ao lado.

locals {
  where_metric = "k8s_namespace_name = '${local.ns}'"
  app_service  = "soat-app-${var.environment}"
}

resource "newrelic_one_dashboard" "soat" {
  name        = "SOAT ${var.environment} - oficina"
  permissions = "public_read_only"

  page {
    name = "Negocio"

    widget_bar {
      title  = "Volume diario de OS - ultimos 7 dias (0 = hoje, dia de Sao Paulo) - atualiza a cada 1 min"
      row    = 1
      column = 1
      width  = 8
      height = 4
      nrql_query {
        query = "SELECT latest(soat_service_orders_created_by_day) FROM Metric WHERE ${local.where_metric} FACET days_ago SINCE 10 minutes ago LIMIT 7"
      }
    }

    widget_billboard {
      title  = "Leitura das metricas de negocio (1 = valida)"
      row    = 1
      column = 9
      width  = 4
      height = 2
      nrql_query {
        query = "SELECT latest(soat_business_metrics_up) FROM Metric WHERE ${local.where_metric} SINCE 10 minutes ago"
      }
      critical = 0.5
    }

    widget_billboard {
      title  = "OS paradas ha mais de 2h"
      row    = 3
      column = 9
      width  = 4
      height = 2
      nrql_query {
        query = "SELECT latest(soat_service_orders_stalled) FROM Metric WHERE ${local.where_metric} FACET status SINCE 10 minutes ago"
      }
    }

    widget_bar {
      title  = "Tempo medio por status, em horas - passagens encerradas nos ultimos 7 dias"
      row    = 5
      column = 1
      width  = 8
      height = 4
      nrql_query {
        query = "SELECT latest(soat_service_orders_avg_status_duration_seconds) / 3600 AS 'horas' FROM Metric WHERE ${local.where_metric} AND status IN ('EM_DIAGNOSTICO', 'EM_EXECUCAO', 'FINALIZADA') FACET status SINCE 10 minutes ago"
      }
    }

    widget_table {
      title  = "Base da media: passagens encerradas por status (0 = sem dados)"
      row    = 5
      column = 9
      width  = 4
      height = 4
      nrql_query {
        query = "SELECT latest(soat_service_orders_status_samples) AS 'passagens' FROM Metric WHERE ${local.where_metric} FACET status SINCE 10 minutes ago"
      }
    }

    widget_line {
      title  = "Erros e falhas nas integracoes por tipo (401 webhook, 400 dominio, 5xx) - por minuto"
      row    = 9
      column = 1
      width  = 12
      height = 4
      nrql_query {
        query = "SELECT sum(soat_integration_errors_total) FROM Metric WHERE ${local.where_metric} AND route != '/health' FACET kind TIMESERIES 1 minute SINCE 3 hours ago"
      }
    }
  }

  page {
    name = "Operacao"

    widget_line {
      title  = "Latencia das APIs por rota - p50, p95, p99 (ms)"
      row    = 1
      column = 1
      width  = 12
      height = 4
      nrql_query {
        query = "SELECT percentile(duration.ms, 50, 95, 99) FROM Span WHERE service.name = '${local.app_service}' AND span.kind = 'server' FACET http.route TIMESERIES AUTO SINCE 1 hour ago"
      }
    }

    widget_line {
      title  = "CPU por pod (cores) - pedido de 250m"
      row    = 5
      column = 1
      width  = 6
      height = 4
      nrql_query {
        query = "SELECT average(k8s.pod.cpu.usage) FROM Metric WHERE k8s.namespace.name = '${local.ns}' FACET k8s.pod.name TIMESERIES AUTO SINCE 1 hour ago"
      }
    }

    widget_line {
      title  = "Memoria por pod (MiB) - limite de 512 MiB"
      row    = 5
      column = 7
      width  = 6
      height = 4
      nrql_query {
        query = "SELECT average(k8s.pod.memory.working_set) / 1048576 FROM Metric WHERE k8s.namespace.name = '${local.ns}' FACET k8s.pod.name TIMESERIES AUTO SINCE 1 hour ago"
      }
    }

    widget_billboard {
      title  = "Uptime pelo Kong (% de checagens 2xx) - 24h"
      row    = 9
      column = 1
      width  = 4
      height = 3
      nrql_query {
        query = "SELECT average(httpcheck.status) * 100 AS 'uptime %' FROM Metric WHERE http.url LIKE '%${local.ns}%' AND http.status_class = '2xx' SINCE 24 hours ago"
      }
      critical = 99
    }

    widget_line {
      title  = "Healthcheck pelo Kong (1 = 2xx)"
      row    = 9
      column = 5
      width  = 4
      height = 3
      nrql_query {
        query = "SELECT latest(httpcheck.status) FROM Metric WHERE http.url LIKE '%${local.ns}%' AND http.status_class = '2xx' TIMESERIES 1 minute SINCE 3 hours ago"
      }
    }

    widget_line {
      title  = "Replicas da aplicacao (HPA)"
      row    = 9
      column = 9
      width  = 4
      height = 3
      nrql_query {
        query = "SELECT latest(k8s.hpa.current_replicas) FROM Metric WHERE k8s.namespace.name = '${local.ns}' TIMESERIES 1 minute SINCE 3 hours ago"
      }
    }
  }
}

output "dashboard_url" {
  value = newrelic_one_dashboard.soat.permalink
}
