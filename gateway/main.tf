locals {
  namespace = "soat-${var.environment}"
  node_port = var.environment == "prd" ? 30080 : 30081
  labels = {
    "app.kubernetes.io/name"    = "kong"
    "app.kubernetes.io/part-of" = "soat"
  }
  auth_url = var.auth_mode == "lambda" ? var.auth_function_url : "http://soat-auth-local.${local.namespace}.svc.cluster.local:8080"
}

# ---------------------------------------------------------------------------
# Segredo dos JWTs do ambiente. Unica fonte: a aplicacao o recebe pelo Secret
# soat-jwt, o Kong pelos consumers, e a Lambda pelo SSM. Ninguem o digita.
# ---------------------------------------------------------------------------

resource "random_password" "jwt" {
  length  = 64
  special = false
}

resource "kubernetes_secret" "soat_jwt" {
  metadata {
    name      = "soat-jwt"
    namespace = local.namespace
    labels    = { "app.kubernetes.io/part-of" = "soat" }
  }
  data = {
    JWT_SECRET = random_password.jwt.result
  }
}

resource "aws_ssm_parameter" "jwt" {
  name        = "/soat/${var.environment}/jwt/secret"
  description = "Segredo HS256 dos JWTs do ambiente, lido pela Lambda de autenticacao"
  type        = "SecureString"
  value       = random_password.jwt.result
}

# Escrito pelo soat-auth-lambda. So existe depois do primeiro apply de la, e
# so e lido no modo lambda.
data "aws_ssm_parameter" "auth_origin" {
  count = var.auth_mode == "lambda" ? 1 : 0
  name  = "/soat/${var.environment}/auth/origin-secret"
}

# ---------------------------------------------------------------------------
# Kong DB-less: a configuracao inteira e um arquivo declarativo num Secret.
# Mudou o arquivo, muda o hash na anotacao e o Deployment faz rollout.
# ---------------------------------------------------------------------------

locals {
  kong_config = templatefile("${path.module}/templates/kong.yml.tftpl", {
    app_url         = "http://soat-app.${local.namespace}.svc.cluster.local:3000"
    auth_url        = local.auth_url
    swagger_enabled = var.environment == "hml"
    jwt_secret      = random_password.jwt.result
    origin_secret   = var.auth_mode == "lambda" ? data.aws_ssm_parameter.auth_origin[0].value : ""
  })
}

resource "kubernetes_secret" "kong_config" {
  metadata {
    name      = "kong-config"
    namespace = local.namespace
    labels    = local.labels
  }
  data = {
    "kong.yml" = local.kong_config
  }
}

resource "kubernetes_deployment" "kong" {
  metadata {
    name      = "kong"
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    replicas = 1

    selector {
      match_labels = { "app.kubernetes.io/name" = "kong" }
    }

    template {
      metadata {
        labels = local.labels
        annotations = {
          "soat/config-hash" = sha256(local.kong_config)
        }
      }

      spec {
        automount_service_account_token = false

        security_context {
          run_as_non_root = true
          run_as_user     = 1000
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "kong"
          image = var.kong_image

          env {
            name  = "KONG_DATABASE"
            value = "off"
          }
          env {
            name  = "KONG_DECLARATIVE_CONFIG"
            value = "/kong/kong.yml"
          }
          env {
            name  = "KONG_PROXY_LISTEN"
            value = "0.0.0.0:8000"
          }
          # Sem Admin API: a configuracao so muda pelo Terraform.
          env {
            name  = "KONG_ADMIN_LISTEN"
            value = "off"
          }
          env {
            name  = "KONG_STATUS_LISTEN"
            value = "0.0.0.0:8100"
          }
          env {
            name  = "KONG_PROXY_ACCESS_LOG"
            value = "/dev/stdout"
          }
          env {
            name  = "KONG_PROXY_ERROR_LOG"
            value = "/dev/stderr"
          }
          env {
            name  = "KONG_PREFIX"
            value = "/kong-prefix"
          }

          port {
            name           = "proxy"
            container_port = 8000
          }
          port {
            name           = "status"
            container_port = 8100
          }

          readiness_probe {
            http_get {
              path = "/status/ready"
              port = "status"
            }
            period_seconds = 5
          }
          liveness_probe {
            http_get {
              path = "/status"
              port = "status"
            }
            period_seconds    = 20
            failure_threshold = 3
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              memory = "256Mi"
            }
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/kong"
            read_only  = true
          }
          volume_mount {
            name       = "prefix"
            mount_path = "/kong-prefix"
          }
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }
        }

        volume {
          name = "config"
          secret {
            secret_name = kubernetes_secret.kong_config.metadata[0].name
          }
        }
        volume {
          name = "prefix"
          empty_dir {}
        }
        volume {
          name = "tmp"
          empty_dir {}
        }
      }
    }
  }

  wait_for_rollout = true
}

resource "kubernetes_service" "kong" {
  metadata {
    name      = "kong-proxy"
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    type     = "NodePort"
    selector = { "app.kubernetes.io/name" = "kong" }

    port {
      name        = "proxy"
      port        = 80
      target_port = "proxy"
      node_port   = local.node_port
    }
  }
}
