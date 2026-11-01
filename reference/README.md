# Referência: o mesmo desenho em AWS EKS

**Nunca aplicado.** O CI só roda `validate` aqui, e nenhum job de deploy aponta para este
diretório. EKS, NAT Gateway e nós EC2 têm custo mensal, e a entrega é custo zero. O cluster real é
o Kind de [`cluster/`](../cluster).

O código mostra como a mesma topologia ficaria na nuvem: VPC com subnets públicas e privadas, o
cluster EKS e os namespaces por ambiente. Os manifests da aplicação e do gateway não mudam.

| Raiz | O que descreve |
| --- | --- |
| `aws-eks/network/` | VPC, subnets públicas e privadas, NAT |
| `aws-eks/k8s/` | Cluster EKS, node group, OIDC provider e addons |
| `aws-eks/env-aws/` | Composição das duas acima, com providers e backend de exemplo |

Para conferir que o código continua válido, sem criar nada:

```bash
for root in network k8s env-aws; do
  terraform -chdir=reference/aws-eks/$root init -backend=false && terraform -chdir=reference/aws-eks/$root validate
done
```
