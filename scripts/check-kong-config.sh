#!/usr/bin/env bash
# Renderiza gateway/templates/kong.yml.tftpl nos dois modos (local e lambda)
# com valores ficticios e valida cada resultado com `kong config parse`, na
# mesma imagem que o cluster usa. Roda no CI e localmente.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
image="${KONG_IMAGE:-kong:3.9}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cp "$root/gateway/templates/kong.yml.tftpl" "$work/"
echo 'output "noop" { value = "" }' > "$work/main.tf"
terraform -chdir="$work" init -input=false >/dev/null

for mode in local lambda; do
  origin=""
  [ "$mode" = lambda ] && origin="origem-ficticia"
  expr="templatefile(\"kong.yml.tftpl\", {app_url=\"http://soat-app.soat-hml.svc.cluster.local:3000\", auth_url=\"https://exemplo.lambda-url.sa-east-1.on.aws/\", swagger_enabled=true, jwt_secret=\"segredo-ficticio\", origin_secret=\"$origin\"})"
  echo "$expr" | terraform -chdir="$work" console | sed -e '1{/^<<EOT$/d;}' -e '${/^EOT$/d;}' > "$work/kong-$mode.yml"
  echo "== $mode"
  docker run --rm -e KONG_DATABASE=off -v "$work/kong-$mode.yml:/kong.yml:ro" "$image" kong config parse /kong.yml
done
