# Referência: o mesmo desenho em AWS EKS

**Nunca aplicado.** O CI só roda `validate` aqui, e nenhum job de deploy aponta para este
diretório. EKS, NAT Gateway e nós EC2 têm custo mensal, e a entrega é custo zero. O cluster real é
o Kind de [`cluster/`](../cluster).

O código mostra como a mesma topologia ficaria na nuvem: VPC com subnets públicas e privadas, o
cluster EKS e os namespaces por ambiente. Os manifests da aplicação e do gateway não mudam.
