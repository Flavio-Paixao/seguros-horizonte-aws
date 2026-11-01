# Decisões de arquitetura

Para cada decisão: **o que foi feito**, **por quê**, **por que não** as alternativas e **o trade-off**. O objetivo é poder explicar cada escolha numa entrevista, inclusive o que ficou fraco. O que cada camada cria está em [ARCHITECTURE.md](ARCHITECTURE.md).

## Sumário

1. [Rede](#1-rede)
2. [IAM](#2-iam)
3. [KMS](#3-kms)
4. [Aurora](#4-aurora)
5. [ALB e Auto Scaling](#5-alb-e-auto-scaling)
6. [S3](#6-s3)
7. [Terraform e processo](#7-terraform-e-processo)
8. [Pendências conhecidas](#pendências-conhecidas)

---

## 1. Rede

### 1.1 Duas AZs, com subnets públicas e privadas em cada uma
- **Por quê:** o ALB e o Aurora exigem subnets em pelo menos 2 AZs. Com 2 AZs, a perda de um datacenter não derruba o sistema.
- **Por que não 1 AZ:** era a versão antiga do projeto; é um ponto único de falha.
- **Por que não 3 AZs:** a sa-east-1 tem 3, mas 2 já provam o conceito, e cada AZ extra multiplica o custo de instâncias.
- **Trade-off:** o custo de computação dobra em relação a uma AZ.

### 1.2 Camadas em subnets distintas: ALB público, app e banco privados
- **Por quê:** só o ALB precisa ser alcançável pela internet. App e banco ficam sem IP público e sem rota de entrada.
- **Por que não EC2 em subnet pública:** expõe cada instância a varreduras e ataques diretos.
- **Trade-off:** as instâncias privadas precisam de NAT para sair, e acessar o banco do notebook exige SSM ou bastion.

### 1.3 Um único NAT Gateway, na 1a
- **Por quê:** um NAT custa cerca de US$ 45/mês parado, mais tráfego. Um só mantém o custo baixo; por isso a tabela de rotas privada também é uma só.
- **Por que não um NAT por AZ:** é a prática de produção, porém dobra o custo fixo.
- **Trade-off (ponto fraco assumido):** se a 1a cair, as instâncias da 1b continuam recebendo tráfego do ALB, mas perdem a saída para a internet. Ver [pendências](#pendências-conhecidas).

### 1.4 Security groups em cadeia, referenciando outros SGs
- **Por quê:** o `app-sg` só aceita 8000 vindo do `alb-sg`, e o `rds-sg` só aceita 5432 vindo do `app-sg`. Regras por SG acompanham as instâncias mesmo que o IP mude.
- **Por que não liberar por CIDR:** é mais amplo e quebra quando os IPs mudam.
- **Correção feita na Fase 3B:** o banco aceitava o SG do ALB, que nunca fala com o banco. Agora só a camada de aplicação entra.

### 1.5 `rds-sg` sem regra de saída
- **Por quê:** o banco não inicia conexões. SG é *stateful*, então as respostas às conexões da app continuam saindo.
- **Trade-off:** se um dia o banco precisar chamar algo externo (por exemplo, uma extensão), será preciso criar a regra.

### 1.6 Saída do ALB restrita à porta 8000 dentro da VPC
- **Por quê:** menor privilégio.
- **Por que não apontar para o `app-sg`:** os dois SGs se referenciariam e virariam um ciclo no Terraform; por isso usa o CIDR da VPC.

### 1.7 Porta 443 aberta no ALB sem listener HTTPS
- **Por quê:** deixa o SG pronto para quando houver domínio e certificado.
- **Trade-off:** hoje a porta 443 está liberada, mas ninguém escuta. É inofensivo, porém incoerente: ver pendências.

### 1.8 CIDRs `10.0.1x` para privadas e `10.0.x` para públicas
- **Por quê:** o IP diz o tipo e a AZ da subnet. Os blocos /24 (251 IPs úteis) sobram para o case.

---

## 2. IAM

### 2.1 Roles em vez de usuários com access keys
- **Por quê:** roles entregam credenciais temporárias e rotacionadas pela AWS. Não há chave para vazar no código, na AMI ou num `.env`.
- **Por que não usuário IAM:** chave de longa duração é a causa mais comum de incidentes.

### 2.2 Uma role por serviço, com trust policy restrita
- **Por quê:** a role da EC2 só pode ser assumida por `ec2.amazonaws.com`, a do monitoramento por `monitoring.rds.amazonaws.com` e a da Lambda por `lambda.amazonaws.com`. Uma Lambda não consegue usar a role da EC2.
- **Trade-off:** mais recursos para manter do que uma role única "faz tudo".

### 2.3 Policies inline para o que é do projeto; gerenciadas para o que é padrão
- **Por quê:** a inline morre junto com a role (não sobra permissão órfã) e é fácil de ler ao lado dela. Para SSM, Enhanced Monitoring e Lambda em VPC, a policy mantida pela AWS é mais segura do que reescrever a lista à mão.
- **Trade-off:** policies inline não são reutilizáveis entre roles. Aqui, as da EC2 e da Lambda repetem parte do conteúdo.

### 2.4 ARNs exatos dos buckets (Fase 7)
- **Por quê:** antes o acesso era `seguros-horizonte-*`, que pegaria qualquer bucket futuro com esse prefixo. Agora o módulo `storage` exporta os 3 ARNs e o IAM os recebe como entrada.
- **Trade-off:** cria a dependência `storage` → `iam`. Não gera ciclo porque `storage` só depende de `kms`.

### 2.5 Acesso à chave do S3 só via S3, sem acesso à chave do banco
- **Por quê:** ler um objeto criptografado exige permissão no S3 **e** na chave. A condição `kms:ViaService` impede usar a chave fora do S3. A chave do banco não foi dada à EC2 nem à Lambda, porque quem a usa é o próprio RDS, por grants.
- **Trade-off:** se alguém quiser, no futuro, descriptografar um snapshot do banco com uma role, precisará adicionar a permissão.

### 2.6 ARNs do RDS por padrão de nome, não por ARN exato
- **Por quê:** o ARN real do cluster só existe depois de criado, e o RDS depende do IAM (role de monitoramento). Usar o ARN exato criaria um ciclo.
- **Trade-off:** `cluster:seguros-horizonte-*` ainda é um curinga, mas limitado à conta, à região e ao prefixo do projeto, e só para `Describe*`.

### 2.7 Leitura do segredo por curinga `rds!cluster-*`
- **Por quê:** o nome do segredo é gerado pela AWS e só existe após o apply.
- **Trade-off:** permite ler o segredo de qualquer cluster RDS da conta e região. A alternativa é restringir ao output `master_user_secret_arn`, cuidando para não criar ciclo.

### 2.8 SSM Session Manager em vez de SSH
- **Por quê:** sem porta 22 aberta, sem par de chaves para guardar e com sessões registradas no CloudTrail.
- **Por que não bastion host:** mais uma máquina para pagar, atualizar e proteger.
- **Trade-off:** depende do agente SSM e de a instância alcançar os endpoints do SSM (hoje, via NAT).

### 2.9 Role da Lambda sem Lambda
- **Por quê:** estava no plano para processar arquivos do S3 no futuro, e criar a role agora deixa as permissões revisadas.
- **Trade-off:** é um recurso sem uso hoje. Uma função real exigiria validar de novo as permissões.

### 2.10 A EC2 tem `DeleteObject` também no bucket de logs
- **Por quê:** o código usa uma única lista de ARNs para os 3 buckets, o que simplificou o módulo.
- **Trade-off:** em princípio, a aplicação não deveria apagar logs. Ver pendências.

---

## 3. KMS

### 3.1 Chaves próprias (CMK) em vez das chaves `aws/rds` e `aws/s3`
- **Por quê:** com a CMK controlo a key policy, a rotação e posso desabilitar a chave. Cada uso fica registrado no CloudTrail.
- **Por que não a chave gerenciada pela AWS:** é grátis, mas não permite restringir quem a usa.
- **Trade-off:** cerca de US$ 1/mês por chave, mais as chamadas de API.

### 3.2 Duas chaves, uma para o banco e outra para o S3
- **Por quê:** raio de impacto menor: desabilitar ou comprometer uma não afeta a outra. A auditoria também fica separada.
- **Trade-off:** uma chave a mais para pagar e gerenciar.

### 3.3 Key policy separando administrar de usar
- **Por quê:** a conta administra a chave (rotação, policy, exclusão), mas `Encrypt`/`Decrypt` só valem via o serviço dono (`kms:ViaService`) e vindo da própria conta (`kms:CallerAccount`). Quem tem `kms:Decrypt` no IAM não abre os dados chamando o KMS direto.
- **Por que não a policy padrão** (`kms:*` para a conta): é mais simples, mas delega todo o controle ao IAM.
- **Trade-off:** policy mais longa e mais difícil de depurar. Um erro de condição pode impedir o próprio serviço de usar a chave.

### 3.4 `kms:CreateAlias` em vez de `kms:Create*`
- **Por quê:** `Create*` incluiria `CreateGrant` sem condições, e um grant permitiria usar a chave fora do RDS.

### 3.5 Grants só para recursos da AWS (`kms:GrantIsForAWSResource`)
- **Por quê:** o RDS precisa de grants para backups e réplicas; pessoas não.

### 3.6 Rotação anual e janela de exclusão de 30 dias
- **Por quê:** a rotação troca o material da chave sozinha, sem recriptografar os dados nem mudar o ARN. Apagar uma chave torna os dados ilegíveis para sempre, e 30 dias é a janela máxima para desfazer um erro.
- **Trade-off:** num ambiente de estudo, destruir demora 30 dias para valer de verdade.

---

## 4. Aurora

### 4.1 Aurora PostgreSQL em vez de RDS PostgreSQL
- **Por quê:** o armazenamento é replicado em 3 AZs, o failover é rápido e réplicas de leitura são baratas.
- **Trade-off:** mais caro que um RDS comum e preso ao Aurora.

### 4.2 Writer em 1a e reader em 1b (`availability_zone` fixa)
- **Por quê:** garante que as instâncias fiquem em AZs diferentes. Se o writer cair, o reader é promovido (`promotion_tier = 1`).
- **Trade-off:** duas instâncias são o dobro do custo de computação, e fixar a AZ reduz a flexibilidade da AWS para recolocá-las.

### 4.3 `db.t3.medium`
- **Por quê:** é a menor classe suportada pelo Aurora PostgreSQL e basta para o case.
- **Trade-off:** instâncias *burstable* usam créditos de CPU. Em produção, uma família de memória otimizada (r6g/r7g) seria mais adequada.

### 4.4 Senha gerenciada pelo Secrets Manager (`manage_master_user_password`)
- **Por quê:** a senha nunca aparece no código nem no state.
- **Por que não uma variável com a senha:** ela iria para o state e para o histórico do Git.
- **Trade-off:** o segredo usa a chave `aws/secretsmanager`, não a nossa CMK. Dá para mudar com `master_user_secret_kms_key_id`.

### 4.5 Banco privado, sem IP público, com SG fechado
- **Por quê:** três camadas independentes: sem IP público, sem rota para o IGW e SG que só aceita a camada de aplicação.
- **Trade-off:** acessar o banco do notebook exige SSM port forwarding ou bastion.

### 4.6 Backup de 7 dias, janela às 03:00 UTC
- **Por quê:** recuperação para qualquer ponto da última semana, fora do horário comercial de São Paulo.
- **Trade-off:** mais retenção custaria mais armazenamento de backup.

### 4.7 Performance Insights com a mesma CMK
- **Por quê:** ele guarda o texto das consultas, que pode ter dado sensível (checkov CKV_AWS_354).

### 4.8 `deletion_protection = false` e `skip_final_snapshot = true`
- **Por quê:** projeto de estudo que precisa poder ser destruído sem travar.
- **Trade-off (importante):** **em produção seria o contrário** (`true` e `false`). Hoje, um `terraform destroy` apaga o banco sem deixar cópia final.

### 4.9 Versão do motor obtida por data source, com `ignore_changes`
- **Por quê:** usa a versão padrão atual da família 15 e não briga com upgrades menores automáticos.
- **Trade-off:** a versão exata só aparece no plan, o que reduz a reprodutibilidade.

### 4.10 Autenticação IAM habilitada, mas sem uso
- **Por quê:** deixa a porta aberta para trocar a senha por tokens temporários no futuro.
- **Trade-off:** nenhuma role tem `rds-db:connect` hoje, então a opção não faz nada ainda.

---

## 5. ALB e Auto Scaling

### 5.1 ALB nas subnets públicas e EC2 nas privadas
- **Por quê:** só o ALB fica exposto.
- **Trade-off:** as instâncias dependem do NAT.

### 5.2 Mínimo de 2 instâncias (o guia original previa 1)
- **Por quê:** uma por AZ, sempre. Se uma AZ cair, a outra continua atendendo. O código bloqueia valores menores que 2.
- **Trade-off:** custo de 2 × `t3.small` o tempo todo.

### 5.3 Health check do ASG do tipo `ELB`
- **Por quê:** a instância que não responde `/health` é substituída, e não só a que falha no hardware.
- **Trade-off:** carência de 300 s para o `user_data` terminar; uma instância nova demora a contar.

### 5.4 IMDSv2 obrigatório, hop limit 1
- **Por quê:** bloqueia o roubo de credenciais por SSRF no endpoint de metadados.
- **Trade-off:** software antigo que só fala IMDSv1 deixa de funcionar. O hop limit 1 também impede containers de alcançar os metadados.

### 5.5 Disco criptografado com a chave `aws/ebs`
- **Por quê:** criptografia em repouso sem custo extra.
- **Por que não uma CMK:** exigiria mais permissões e mais um recurso. Perde-se o controle da key policy.

### 5.6 Listener só HTTP:80
- **Por quê:** não há domínio nem certificado ACM neste projeto de estudo.
- **Trade-off:** **o tráfego entre o usuário e o ALB não é criptografado.** É a maior lacuna de segurança do case. Ver pendências.

### 5.7 Escala por alarmes de CPU (70% / 30%)
- **Por quê:** simples de explicar e de acompanhar no CloudWatch.
- **Por que não *target tracking*:** seria mais preciso e evitaria oscilação, mas esconde a lógica dos alarmes.
- **Trade-off:** reage devagar (2 períodos de 5 min) e a CPU não é a métrica ideal para toda aplicação.

### 5.8 AMI "mais recente" por data source
- **Por quê:** sempre usa a imagem com os patches mais novos.
- **Trade-off:** um `plan` futuro pode trocar a AMI e recriar o launch template. Uma AMI fixa seria mais previsível.

### 5.9 `create_before_destroy` e `name_prefix`
- **Por quê:** o novo recurso sobe antes de o antigo sair, sem queda.
- **Trade-off:** exige nomes gerados (`name_prefix`) em vez de fixos.

### 5.10 Aplicação de teste com 15 linhas de Python
- **Por quê:** serve para o health check passar e provar a arquitetura.
- **Trade-off:** não é uma aplicação real e não usa o banco nem o S3. O fluxo EC2 → Aurora e EC2 → S3 está permitido nas regras, mas **não foi exercitado**.

---

## 6. S3

### 6.1 SSE-KMS com CMK em vez de SSE-S3
- **Por quê:** controle da key policy e trilha de quem descriptografou, importante para dados de clientes (LGPD).
- **Trade-off:** US$ 1/mês por chave, mais as chamadas ao KMS.

### 6.2 `bucket_key_enabled = true`
- **Por quê:** reduz muito as chamadas ao KMS e o custo.
- **Trade-off:** o CloudTrail passa a registrar o uso por bucket, não por objeto.

### 6.3 Block Public Access com as 4 travas
- **Por quê:** nenhum bucket deve ser público; impede vazamento por ACL ou policy errada.
- **Alternativa para conteúdo público:** CloudFront com OAC, nunca abrir o bucket.

### 6.4 Policy que nega acesso sem TLS
- **Por quê:** um `Deny` explícito vence qualquer `Allow`, inclusive o do IAM.
- **Trade-off:** clientes antigos sem HTTPS deixam de funcionar. Na prática, nenhum.

### 6.5 Versionamento em app-data e backups, mas não em logs
- **Por quê:** protege contra exclusão ou sobrescrita acidental e contra ransomware onde importa. Logs são só de escrita e já expiram.
- **Trade-off:** versões antigas custam armazenamento; o lifecycle as expira.

### 6.6 Lifecycle com Glacier e retenção de 7 anos
- **Por quê:** armazenamento frio é barato e 7 anos é uma retenção comum em exigências regulatórias.
- **Trade-off:** o Glacier cobra pela recuperação e demora. Os 7 anos são uma suposição minha, não uma exigência verificada para corretoras. Os 30 dias de backup são uma escolha de custo.

### 6.7 `bucket_prefix` em vez de nome fixo
- **Por quê:** nomes de bucket são únicos no mundo; o sufixo aleatório evita colisão.
- **Trade-off:** o nome fica imprevisível, e por isso os outputs o expõem.

### 6.8 Sem replicação entre regiões nem Object Lock
- **Por quê:** fora do escopo; adicionam custo e complexidade.
- **Trade-off:** os dados existem só em sa-east-1, e a imutabilidade dos backups não é garantida.

---

## 7. Terraform e processo

### 7.1 Um módulo por camada
- **Por quê:** cada módulo tem entradas e saídas claras, e a raiz só liga as peças.
- **Trade-off:** mais arquivos do que um `main.tf` único, e os módulos dependem uns dos outros pelos outputs.

### 7.2 Versões travadas (`~> 5.20` na raiz, `>= 5.20` nos módulos, lock em 5.100.0)
- **Por quê:** o lock garante o mesmo provider em qualquer máquina.

### 7.3 `default_tags` no provider
- **Por quê:** todo recurso recebe as tags de projeto, ambiente e dono sem repetição, o que ajuda em custo e auditoria.

### 7.4 Validar só até o `plan`, nunca `apply`
- **Por quê:** projeto de portfólio. Um `apply` geraria custo real (NAT, 2 Aurora, 2 EC2, ALB, chaves).
- **Trade-off (importante para a entrevista):** **o código nunca foi aplicado.** `validate` e `plan` não pegam erros que só aparecem na criação, como limites de conta, permissões da key policy ou o health check falhando. Os planos dos PRs foram conferidos offline, com valores fictícios para conta, região, AMI e versão do banco. Um `plan` real depende de credenciais AWS.

### 7.5 Um PR por fase, com a tabela de decisões na descrição
- **Por quê:** histórico revisável e rastreável pelos tickets do Jira (KAN-n).

---

## Pendências conhecidas

Esta lista é a parte honesta do projeto: o que **não** está resolvido, por quê, e o que seria feito em produção.

| # | Pendência | Risco | Correção em produção |
|---|---|---|---|
| 1 | **ALB só com HTTP:80** (sem HTTPS) | Tráfego entre usuário e ALB sem criptografia. Contradiz a ideia de proteger dados pessoais | Domínio no Route 53, certificado ACM, listener 443 e redirect 80 → 443 |
| 2 | **Um único NAT Gateway** (na 1a) | Se a 1a cair, as instâncias da 1b perdem a saída para a internet | Um NAT por AZ, com uma route table privada por AZ; ou VPC endpoints |
| 3 | **Nada foi aplicado** | Erros de runtime ficam sem detectar | `apply` numa conta de teste, seguido de `destroy`, com orçamento e alerta de custo |
| 4 | **Sem state remoto** | Não há bloqueio nem compartilhamento do state | Backend S3 com bloqueio e criptografia |
| 5 | **Aurora sem proteção de exclusão** e sem snapshot final | Um `destroy` apaga o banco sem cópia | `deletion_protection = true` e `skip_final_snapshot = false` |
| 6 | **Segredo do banco com chave `aws/secretsmanager`** | Menos controle que a CMK | `master_user_secret_kms_key_id` com a chave do banco, ajustando a key policy |
| 7 | **EC2 lê qualquer segredo `rds!cluster-*`** | Permissão mais ampla que o necessário | Restringir ao ARN do segredo do cluster |
| 8 | **EC2 pode apagar objetos do bucket de logs** | A aplicação poderia apagar a própria trilha | Listas separadas: app-data e backups com `DeleteObject`; logs só com escrita |
| 9 | **Porta 443 aberta sem listener** | Incoerência entre o SG e o ALB | Resolvida junto com o item 1 |
| 10 | **Sem WAF, CloudTrail, GuardDuty ou Config** | Pouca detecção e auditoria | Habilitar CloudTrail multi-região (para um bucket de logs dedicado) e GuardDuty; avaliar WAF no ALB |
| 11 | **Aplicação é só um health check** | O fluxo EC2 → Aurora e EC2 → S3 nunca foi exercitado | Aplicação real e testes de integração |
| 12 | **Escala por CPU com alarmes** | Reação lenta e possível oscilação | *Target tracking* ou métricas do ALB |
| 13 | **Instâncias burstable** (`t3`) e AMI "mais recente" | Desempenho variável e mudanças inesperadas no plan | Famílias dedicadas e AMI fixada por pipeline |
| 14 | **Sem CI** (fmt, validate, tflint, checkov) | Erros chegam à `main` sem checagem automática | GitHub Actions rodando as validações em cada PR |
| 15 | **Os buckets `backups` e `logs` ainda não são usados** | Recursos prontos sem produtor | Exportar logs do ALB e dumps do banco para eles |
