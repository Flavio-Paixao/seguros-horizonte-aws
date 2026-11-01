# Análise de custos (sa-east-1)

Quanto custaria manter o Case 1 ligado na AWS, serviço por serviço, com base no que o código em `terraform/` realmente cria. O objetivo é poder responder numa entrevista: **quanto custa, onde está o dinheiro, e o que eu cortaria primeiro**.

> **Resumo:** cerca de **US$ 433 por mês** com o tráfego baixo de um projeto de estudo. Desse total, **US$ 411 são custo fixo por hora** (cobrado mesmo sem nenhum usuário) e só uns **US$ 22 dependem de uso**. O Aurora sozinho é **58%** da conta. Um teste de 4 horas, com `apply` seguido de `destroy`, sai por volta de **US$ 2,50**.

## Fonte, data e premissas

- **Fonte dos preços:** [AWS Price List API](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/price-changes.html), os arquivos oficiais de preço por região (`https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/<serviço>/current/sa-east-1/index.json`), baixados em **01/11/2026**. São os mesmos números das páginas de preço de cada serviço. Os arquivos tinham data de publicação entre 11/09/2026 e 29/10/2026.
- **Preços em dólar, sob demanda (on-demand), sem impostos.** Uma conta brasileira é faturada em reais pela AWS Brasil, com impostos locais por cima; isso não está incluído.
- **Mês de 730 horas** (a média que a própria AWS usa nas estimativas).
- **Sem free tier.** Contas novas têm créditos e cotas grátis, mas o objetivo aqui é saber o custo real da arquitetura. Onde o free tier zeraria um item, está anotado.
- **O que é estimativa:** tudo que depende de uso (GB trafegados, GB guardados, requisições, logs) é uma **suposição minha** para um ambiente de estudo com pouco tráfego. Esses valores estão marcados com **(est.)**. Os preços unitários são oficiais; as quantidades não.

## Custo por serviço

### Cobrado por hora (fixo: corre enquanto o recurso existe)

| Serviço | O que o código cria | Preço unitário | Conta | US$/mês |
|---|---|---|---|---:|
| **Aurora PostgreSQL** | writer + reader `db.t3.medium` | US$ 0,168/h por instância | 2 × 0,168 × 730 | **245,28** |
| **NAT Gateway** | 1 NAT na sa-east-1a | US$ 0,093/h | 0,093 × 730 | **67,89** |
| **EC2** | ASG com 2 × `t3.small` (mínimo 2) | US$ 0,0336/h por instância | 2 × 0,0336 × 730 | **49,06** |
| **Application Load Balancer** | 1 ALB em 2 AZs | US$ 0,034/h | 0,034 × 730 | **24,82** |
| **IPv4 público** | Elastic IP do NAT + 2 IPs do ALB (um por AZ) | US$ 0,005/h por IP | 3 × 0,005 × 730 | **10,95** |
| **EBS** | disco raiz gp3 de 20 GB por instância | US$ 0,152/GB-mês | 2 × 20 × 0,152 | **6,08** |
| **CloudWatch: monitoramento detalhado** | `monitoring { enabled = true }` no launch template | US$ 0,30 por métrica-mês, 7 métricas por instância | 2 × 7 × 0,30 | **4,20** |
| **KMS** | 2 chaves (banco e S3) | US$ 1 por chave-mês | 2 × 1 | **2,00** |
| **Secrets Manager** | 1 segredo (senha do Aurora, `manage_master_user_password`) | US$ 0,40 por segredo-mês | 1 × 0,40 | **0,40** |
| **CloudWatch: alarmes** | `cpu_high` e `cpu_low` do ASG | US$ 0,135 por alarme-mês | 2 × 0,135 | **0,27** |
| | | | **Subtotal fixo** | **410,95** |

### Cobrado por uso (variável)

| Serviço | Suposição de uso (est.) | Preço unitário | US$/mês |
|---|---|---|---:|
| **ALB: LCU** | 1 LCU em média o mês todo (mede conexões, requisições e bytes) | US$ 0,011 por LCU-hora | 8,03 |
| **Transferência de dados** | 20 GB saindo para a internet + 10 GB entre AZs (EC2 da 1b falando com o writer na 1a) | US$ 0,25/GB para a internet; US$ 0,01/GB em cada sentido entre AZs | 5,20 |
| **Aurora: I/O** | 10 milhões de operações de I/O | US$ 0,28 por milhão | 2,80 |
| **Aurora: armazenamento** | 10 GB | US$ 0,19/GB-mês | 1,90 |
| **CloudWatch Logs** | 2 GB ingeridos (log do PostgreSQL + Enhanced Monitoring) e 2 GB guardados | US$ 0,90/GB ingerido; US$ 0,0408/GB-mês | 1,88 |
| **S3** | 35 GB no total (app-data, backups e logs) + algumas requisições | US$ 0,0405/GB-mês (Standard) | 1,52 |
| **NAT: dados processados** | 10 GB (atualizações de pacote, SSM, Secrets Manager, S3) | US$ 0,093/GB | 0,93 |
| **Aurora: backup** | 7 dias de retenção | US$ 0,037/GB-mês acima do tamanho do banco | 0,00 |
| **KMS: requisições** | poucas, graças ao `bucket_key_enabled` nos buckets | US$ 0,03 por 10 mil (20 mil grátis por mês) | 0,00 |
| | | **Subtotal variável** | **22,26** |

### Total

| | US$/mês |
|---|---:|
| Fixo (por hora) | 410,95 |
| Variável (por uso, est.) | 22,26 |
| **Total estimado** | **≈ 433** |

Onde está o dinheiro:

| Bloco | US$/mês | % |
|---|---:|---:|
| Banco (Aurora: instâncias, I/O, storage) | 249,98 | 58% |
| Rede (NAT, IPv4, transferência) | 84,97 | 20% |
| Computação (EC2, EBS, monitoramento) | 59,34 | 14% |
| Load balancer (hora + LCU) | 32,85 | 8% |
| Segurança, logs e S3 (KMS, Secrets, CloudWatch, S3) | 6,07 | 1% |

A leitura para a entrevista: **o banco e a rede são 78% da conta**, e quase tudo isso é custo fixo. Em tráfego baixo, a arquitetura custa praticamente o mesmo com zero ou com mil usuários.

## Por hora vs por uso: o que isso significa

- **Por hora** (Aurora, NAT, EC2, ALB, IPv4, EBS, chaves KMS, segredo): começa a cobrar no `apply` e só para no `destroy`. É a parte que pesa num ambiente esquecido ligado.
- **Por uso** (LCU, GB trafegados, I/O, logs, S3): cresce com a carga. Num site de verdade, a transferência para a internet (US$ 0,25/GB em São Paulo) e o processamento do NAT são os primeiros a crescer.
- **Granularidade da cobrança:**
  - EC2 Linux: por segundo, mínimo de 60 segundos.
  - Aurora: por segundo, mínimo de 10 minutos.
  - NAT e ALB: por hora **ou fração** (15 minutos ligado contam como 1 hora).
  - KMS e Secrets Manager: proporcional às horas no mês. Chave agendada para exclusão não é cobrada.

## Detalhes que pegam desprevenido

1. **IPv4 público é cobrado** desde 2024: além do Elastic IP do NAT, o ALB usa um IP público por AZ. São US$ 11/mês que não aparecem no diagrama.
2. **São Paulo é mais cara que a Virgínia.** O NAT custa US$ 0,093/h aqui (US$ 68/mês parado). Valores de tutoriais, quase sempre em us-east-1, ficam abaixo do real.
3. **Rotação de chave KMS aumenta o preço com o tempo.** Cada rotação automática adiciona US$ 1/mês por chave, até o limite de 2 rotações. Com `enable_key_rotation = true`: US$ 2/mês no ano 1, US$ 4 no ano 2 e US$ 6 a partir do ano 3.
4. **Instâncias `t3` do Aurora funcionam no modo *unlimited*.** Se a CPU ficar alta por muito tempo, a AWS cobra créditos de CPU extras por hora. Com uso baixo não acontece, mas é um custo que não aparece na tabela.
5. **Os log groups do RDS não são gerenciados pelo Terraform.** O Aurora cria sozinho `/aws/rds/cluster/.../postgresql` e `RDSOSMetrics`, sem prazo de expiração. Eles **continuam existindo (e cobrando armazenamento) depois do `destroy`**. Em produção, eu criaria esses log groups no código com `retention_in_days`.
6. **Performance Insights** está ligado sem `performance_insights_retention_period`, ou seja, com a retenção padrão de 7 dias, que é gratuita. Aumentar a retenção passa a cobrar.
7. **Nada de CloudTrail, GuardDuty, WAF ou Config** (pendência 10 do [DECISIONS.md](DECISIONS.md#pendências-conhecidas)). Quando entrarem, entram também no custo.

## Opções de redução

Cada opção com quanto economiza e o que se perde. Os valores usam os preços acima.

### Banco (o maior item)

| Opção | Novo custo das instâncias | Economia/mês | O que se perde |
|---|---:|---:|---|
| `db.t4g.medium` (Graviton, ARM) no lugar de `db.t3.medium` | 223,38 | **21,90** | Nada relevante: o Aurora não depende da arquitetura do processador da aplicação |
| Reserva de 1 ano, sem entrada (No Upfront), `db.t3.medium` (US$ 0,116/h) | 169,36 | **75,92** (31%) | Compromisso de pagar 1 ano inteiro, ligado ou não |
| Aurora Serverless v2 (US$ 0,25 por ACU-hora), 2 instâncias no mínimo de 0,5 ACU | a partir de 182,50 | **≥ 62,78** | O custo sobe com a carga; com uso alto pode passar do provisionado |
| Remover o reader (só em dev) | 122,64 | **122,64** | Sem failover: se a AZ do writer cair, o banco para |

### Rede

| Opção | Efeito/mês | Comentário |
|---|---:|---|
| **Um NAT por AZ** (prática de produção, corrige a pendência 2) | **+ 71,54** (+ 67,89 do NAT, + 3,65 do IPv4) | É o preço de não perder a saída para a internet se a 1a cair |
| VPC endpoint de **gateway** para o S3 | **− o tráfego S3 no NAT** | Gratuito. O tráfego para o S3 deixa de passar pelo NAT (US$ 0,093/GB) |
| VPC endpoints de **interface** (SSM, Secrets Manager, KMS, logs) no lugar do NAT | US$ 0,021/h por endpoint por AZ: 4 endpoints × 2 AZs = **122,64** | Fica **mais caro** que o NAT único neste tamanho. Só compensa com muito tráfego, ou quando a exigência de segurança proíbe a saída para a internet |

### Computação

| Opção | Novo custo das 2 EC2 | Economia/mês | O que se perde |
|---|---:|---:|---|
| Compute Savings Plan, 1 ano, No Upfront (US$ 0,0222/h) | 32,41 | **16,65** (34%) | Compromisso de gasto por hora durante 1 ano; vale para qualquer família e região |
| Reserva padrão de 1 ano, No Upfront (US$ 0,0193/h) | 28,18 | **20,88** (43%) | Presa a `t3.small` em São Paulo |
| `t4g.small` (Graviton, US$ 0,0268/h) | 39,13 | **9,93** | Exige trocar o filtro da AMI de `x86_64` para `arm64` no módulo `ec2` |
| Desligar o monitoramento detalhado | — | **4,20** | Métricas de 5 em 5 minutos em vez de 1 em 1; o ASG reage mais devagar |

### Cenários completos

| Cenário | O que muda | US$/mês (est.) |
|---|---|---:|
| **Como está no código** | — | **≈ 433** |
| **Produção com alta disponibilidade real** | + 1 NAT na 1b | ≈ 505 |
| **Mesma arquitetura com compromisso de 1 ano** | Reserva do Aurora + Savings Plan nas EC2 | ≈ 341 |
| **Dev enxuto** | Aurora só com writer `db.t4g.medium`, ASG com 1 `t3.small`, sem monitoramento detalhado | ≈ 268 |

Savings Plans e reservas só fazem sentido para algo que vai ficar ligado o ano todo. Para um projeto de portfólio, o que economiza de verdade é **não deixar ligado**.

## Custo de um teste de poucas horas

Para validar o código com `apply` numa conta de teste (pendência 3 do [DECISIONS.md](DECISIONS.md#pendências-conhecidas)) e depois `destroy`:

- Custo fixo por hora: 410,95 ÷ 730 ≈ **US$ 0,56 por hora**.
- O tráfego de um teste é desprezível.

| Duração | US$ (est.) |
|---|---:|
| 1 hora | ≈ 0,60 |
| 4 horas | ≈ 2,50 |
| 8 horas | ≈ 4,80 |
| 24 horas (esquecido ligado um dia) | ≈ 13,50 |
| 1 mês esquecido ligado | ≈ 433 |

Cuidados para o teste não virar surpresa na fatura:

1. **Criar um AWS Budget antes do `apply`**, com alerta por e-mail em US$ 10, por exemplo.
2. **O Aurora demora** (de 10 a 20 minutos para criar e outro tanto para apagar). O teste deve durar no mínimo 1 hora.
3. **Rodar `terraform destroy` no mesmo dia** e conferir no console (EC2, RDS, VPC → NAT Gateways, Elastic IPs) que nada ficou para trás.
4. **Esvaziar os buckets antes do `destroy`:** os buckets não têm `force_destroy`, então o Terraform não apaga um bucket com objetos (e versões).
5. **Apagar à mão os log groups do RDS** no CloudWatch (item 5 dos detalhes acima).
6. As **chaves KMS ficam 30 dias "agendadas para exclusão"** depois do `destroy`. Nesse período elas não são cobradas.

## Como explicar numa entrevista

- **"Quanto custa?"** Cerca de US$ 430 por mês em São Paulo, e 95% disso é fixo. O maior item é o Aurora com 2 instâncias, seguido pelo NAT Gateway.
- **"O que você cortaria primeiro?"** Num ambiente de dev, o reader do Aurora (−US$ 123) e o tamanho das instâncias. Em produção eu não cortaria: compraria reserva do Aurora e Savings Plan das EC2 (−US$ 92 juntos), porque a carga é estável.
- **"Por que um NAT só, se a prática é um por AZ?"** Porque um NAT custa US$ 68/mês parado em São Paulo. Escolhi o custo menor e documentei o risco. Em produção, pagaria mais US$ 72/mês pelo segundo NAT.
- **"Por que não VPC endpoints no lugar do NAT?"** Os de interface custam por hora e por AZ: os 4 que eu precisaria custariam mais (US$ 123) do que o NAT único. O de gateway para o S3, sendo gratuito, eu adicionaria já.
- **"Como você controla custo?"** Tags em todos os recursos (`default_tags`), alerta de orçamento, `bucket_key_enabled` para reduzir as chamadas ao KMS, ciclo de vida para mandar dados antigos ao Glacier, e log do banco só com DDL (e não "all").
