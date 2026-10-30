# Alertas de falha no processamento de OS (#64). A lista, com condicao, limiar
# e janela de cada um, esta em ALERTAS.md. Paineis e alertas filtram pelo
# namespace do ambiente; a contagem de erro vem da METRICA, nao de linha de log.

locals {
  ns = "soat-${var.environment}"
}

resource "newrelic_alert_policy" "soat" {
  name                = "SOAT ${var.environment} - processamento de OS"
  incident_preference = "PER_CONDITION_AND_TARGET"
}

# 1. API indisponivel: o health pelo Kong deixou de responder 2xx.
resource "newrelic_nrql_alert_condition" "api_down" {
  policy_id                    = newrelic_alert_policy.soat.id
  name                         = "API indisponivel (${var.environment})"
  description                  = "GET /health pelo Kong sem 2xx por 2 minutos. Banco fora ou app fora."
  type                         = "static"
  violation_time_limit_seconds = 86400

  nrql {
    query = "SELECT latest(httpcheck.status) FROM Metric WHERE http.url LIKE '%${local.ns}%' AND http.status_class = '2xx'"
  }

  critical {
    operator              = "below"
    threshold             = 1
    threshold_duration    = 120
    threshold_occurrences = "all"
  }

  aggregation_window             = 60
  aggregation_method             = "event_flow"
  aggregation_delay              = 120
  expiration_duration            = 300
  open_violation_on_expiration   = true
  close_violations_on_expiration = true
}

# 2. Erro interno em rota de OS ou de integracao. Faceta por trace_id para o
#    alerta apontar a requisicao que falhou.
resource "newrelic_nrql_alert_condition" "internal_error" {
  policy_id                    = newrelic_alert_policy.soat.id
  name                         = "Erro interno no processamento de OS (${var.environment})"
  description                  = "Qualquer 5xx em /service-orders, /budgets ou /webhooks em 5 minutos."
  type                         = "static"
  violation_time_limit_seconds = 86400

  nrql {
    query = "SELECT count(*) FROM Log WHERE k8s.namespace.name = '${local.ns}' AND msg = 'unhandled error' AND (route LIKE '/service-orders%' OR route LIKE '/budgets%' OR route LIKE '/webhooks%') FACET trace_id"
  }

  critical {
    operator              = "above_or_equals"
    threshold             = 1
    threshold_duration    = 300
    threshold_occurrences = "at_least_once"
  }

  aggregation_window             = 60
  aggregation_method             = "event_timer"
  aggregation_timer              = 60
  expiration_duration            = 600
  close_violations_on_expiration = true
}

# 3. Webhook recusado em volume: parceiro com segredo errado. Uma tentativa
#    isolada nao dispara.
resource "newrelic_nrql_alert_condition" "webhook_unauthorized" {
  policy_id                    = newrelic_alert_policy.soat.id
  name                         = "Webhook recusado por segredo invalido (${var.environment})"
  description                  = "5 ou mais 401 de webhook em 5 minutos."
  type                         = "static"
  violation_time_limit_seconds = 86400

  nrql {
    query = "SELECT sum(soat_integration_errors_total) FROM Metric WHERE k8s_namespace_name = '${local.ns}' AND kind = 'webhook_unauthorized'"
  }

  critical {
    operator              = "above_or_equals"
    threshold             = 5
    threshold_duration    = 300
    threshold_occurrences = "at_least_once"
  }

  aggregation_window             = 300
  aggregation_method             = "event_timer"
  aggregation_timer              = 60
  slide_by                       = 60
  expiration_duration            = 600
  close_violations_on_expiration = true
}

# 4. Transicao de status recusada pela regra de dominio, repetida na mesma OS.
resource "newrelic_nrql_alert_condition" "transition_rejected" {
  policy_id                    = newrelic_alert_policy.soat.id
  name                         = "Transicao de status recusada (${var.environment})"
  description                  = "3 ou mais recusas de dominio na mesma OS em 15 minutos."
  type                         = "static"
  violation_time_limit_seconds = 86400

  nrql {
    query = "SELECT count(*) FROM Log WHERE k8s.namespace.name = '${local.ns}' AND msg = 'domain exception' AND serviceOrderId IS NOT NULL FACET serviceOrderId"
  }

  critical {
    operator              = "above_or_equals"
    threshold             = 3
    threshold_duration    = 900
    threshold_occurrences = "at_least_once"
  }

  aggregation_window             = 900
  aggregation_method             = "event_timer"
  aggregation_timer              = 60
  slide_by                       = 60
  expiration_duration            = 1200
  close_violations_on_expiration = true
}

# 5. OS parada: aguardando aprovacao ou em diagnostico sem transicao ha mais
#    de 2h, por 30 minutos seguidos. So conta quando a leitura e valida (up=1).
resource "newrelic_nrql_alert_condition" "stalled" {
  policy_id                    = newrelic_alert_policy.soat.id
  name                         = "OS parada (${var.environment})"
  description                  = "OS em AGUARDANDO_APROVACAO ou EM_DIAGNOSTICO sem andar ha mais de 2h."
  type                         = "static"
  violation_time_limit_seconds = 86400

  nrql {
    query = "SELECT max(soat_service_orders_stalled) FROM Metric WHERE k8s_namespace_name = '${local.ns}' FACET status"
  }

  critical {
    operator              = "above"
    threshold             = 0
    threshold_duration    = 1800
    threshold_occurrences = "all"
  }

  aggregation_window = 60
  aggregation_method = "event_flow"
  aggregation_delay  = 120
}

# ---------------------------------------------------------------------------
# Entrega: workflow -> webhook -> Lambda notifier -> SNS -> e-mail.
# URL e segredo do notifier vem do SSM, escritos pelo soat-auth-lambda.
# ---------------------------------------------------------------------------

data "aws_ssm_parameter" "notifier_url" {
  name = "/soat/${var.environment}/notifier/url"
}

data "aws_ssm_parameter" "notifier_secret" {
  name = "/soat/${var.environment}/notifier/webhook-secret"
}

resource "newrelic_notification_destination" "notifier" {
  name = "SOAT notifier ${var.environment}"
  type = "WEBHOOK"

  property {
    key   = "url"
    value = data.aws_ssm_parameter.notifier_url.value
  }

  auth_token {
    prefix = "Bearer"
    token  = data.aws_ssm_parameter.notifier_secret.value
  }
}

resource "newrelic_notification_channel" "notifier" {
  name           = "SOAT e-mail ${var.environment}"
  type           = "WEBHOOK"
  product        = "IINT"
  destination_id = newrelic_notification_destination.notifier.id

  property {
    key   = "payload"
    label = "Payload do notifier"
    value = file("${path.module}/templates/webhook-payload.hbs")
  }
}

resource "newrelic_workflow" "notifier" {
  name                  = "SOAT ${var.environment} - avisar por e-mail"
  muting_rules_handling = "NOTIFY_ALL_ISSUES"

  issues_filter {
    name = "politica SOAT ${var.environment}"
    type = "FILTER"

    predicate {
      attribute = "labels.policyIds"
      operator  = "EXACTLY_MATCHES"
      values    = [newrelic_alert_policy.soat.id]
    }
  }

  destination {
    channel_id            = newrelic_notification_channel.notifier.id
    notification_triggers = ["ACTIVATED", "CLOSED"]
  }
}
