# Alertas de falha no processamento de OS

Definidos como código em [`alerts.tf`](alerts.tf), uma política por ambiente
(`SOAT hml - processamento de OS`, `SOAT prd - processamento de OS`).

## O que conta como falha

| # | Alerta | Condição (NRQL) | Limiar e janela | Natureza |
|---|---|---|---|---|
| 1 | **API indisponível** | `httpcheck.status` 2xx do `GET /health` pelo Kong do ambiente | abaixo de 1 por **2 min**; sem sinal por 5 min também abre | incidente técnico: banco ou app fora |
| 2 | **Erro interno no processamento de OS** | logs `unhandled error` (5xx) em `/service-orders`, `/budgets` ou `/webhooks`, **por `trace_id`** | 1 ou mais em **5 min** | incidente técnico |
| 3 | **Webhook recusado por segredo inválido** | `soat_integration_errors_total{kind="webhook_unauthorized"}` | **5 ou mais em 5 min**; uma tentativa isolada não dispara | integração com parceiro quebrada |
| 4 | **Transição de status recusada** | logs `domain exception` com `serviceOrderId`, **por OS** | **3 ou mais na mesma OS em 15 min** | uso errado da API por parceiro; volume, não evento único |
| 5 | **OS parada** | `soat_service_orders_stalled` por status | acima de 0 por **30 min** seguidos (a métrica já exige 2h sem transição) | operacional: OS em `AGUARDANDO_APROVACAO` ou `EM_DIAGNOSTICO` sem andar |

Os 5xx dos alertas 1 e 2 são incidente e precisam avisar rápido. Os 400 de domínio (alerta 4)
quase sempre são uso errado da API, e por isso contam como volume acima do normal.

## Identificação da OS

- O alerta 2 é facetado por `trace_id`. O e-mail traz o id, e com ele se abre o trace e os logs da
  requisição que falhou.
- O alerta 4 é facetado por `serviceOrderId`, que a aplicação registra no log de toda recusa de
  domínio, inclusive no webhook do parceiro.

## Destino

Workflow `SOAT <env> - avisar por e-mail` → webhook (Bearer) → Lambda `soat-<env>-notifier` →
tópico SNS `soat-<env>-alerts` → **e-mail do responsável** (variável `ALERT_EMAIL` do
`soat-auth-lambda`).

O workflow notifica em `ACTIVATED` (e-mail `[ABERTO]`) e em `CLOSED` (e-mail `[RESOLVIDO]`).

## Fechamento automático

Todo alerta fecha sozinho quando a condição cessa: as condições são avaliadas a cada minuto, e as
de contagem fecham quando o sinal expira (`close_violations_on_expiration`). Ninguém precisa
fechar incidente à mão.

## Deploy sem alarme falso

Um rolling update troca um pod por vez, e a readiness só põe o pod novo no Service quando
`/health` responde. O Kong continua respondendo 2xx durante o deploy, então o alerta 1 não abre.
O alerta 2 só conta 5xx, que um deploy saudável não gera.

## Como provocar cada alerta (roteiro de verificação)

```bash
# 1 e 2: derrubar o banco do hml por 3 minutos e restaurar
#        (scripts/chaos/db-outage.sh no repositório da aplicação)
# 3: seis webhooks com segredo errado
for i in $(seq 6); do
  curl -s -o /dev/null -w '%{http_code}\n' -X POST localhost:18081/webhooks/service-orders/$OS/status \
    -H 'Authorization: Bearer errado' -H 'Content-Type: application/json' -d '{"status":"EM_DIAGNOSTICO"}'
done
# 4: tres transicoes ilegais na mesma OS, RECEBIDA -> FINALIZADA (token de admin em $ADMIN)
for i in 1 2 3; do
  curl -s -o /dev/null -w '%{http_code}\n' -X PATCH localhost:18081/service-orders/$OS/status \
    -H "Authorization: Bearer $ADMIN" -H 'Content-Type: application/json' -d '{"status":"FINALIZADA"}'
done
```

## Conferências na ativação

- **Nome da métrica no New Relic.** O app emite `soat_integration_errors`, o exporter Prometheus
  acrescenta `_total`, e o receiver do Collector pode removê-lo de novo. Antes de dar o alerta 3 por
  verificado, confira o nome real:
  `FROM Metric SELECT uniques(metricName) WHERE metricName LIKE 'soat_%' SINCE 1 hour ago`.
  Se vier sem `_total`, ajuste a query em `alerts.tf` e no painel.
- **Primeiro ponto de cada série.** O Collector converte cumulativo em delta com
  `initial_value = keep`, então o primeiro webhook recusado de um pod já conta. O efeito colateral:
  reiniciar o `otel-gateway` reemite o acumulado de cada pod como um delta só, e pode abrir o
  alerta 3 uma vez se algum pod já somava 5 ou mais recusas.
- **Rate limit do `/auth/cpf`.** O tráfego entra pelo mapeamento de porta do Docker, então todo
  cliente chega ao Kong com o mesmo IP: o limite de 10/min vale para todos juntos. Não rode o e2e
  e uma demonstração manual no mesmo minuto.

## Limiares

Não há histórico para calibrar: nada era medido antes desta fase. Os valores acima são
conservadores para a entrega. O plano é medir uma semana em produção e ajustar.
