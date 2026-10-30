# Infraestrutura AWS — ToggleMaster (Fase 2, Opção B Conta Pessoal)

> Este documento descreve **TODO o provisionamento em nuvem** que será construído com **Terraform** pela equipe. O objetivo é explicar o papel arquitetônico de cada recurso, as razões por trás das escolhas e como tudo se encaixa para suportar os 5 microsserviços do ToggleMaster em produção no EKS.
>
> Opção do projeto: **Opção B — Conta Pessoal AWS** (uso livre de IRSA, eksctl, KEDA. Sem restrições da LabRole do AWS Academy).

---

## 1. Visão arquitetônica geral (High Level)

```
                                 Usuários / Clientes
                                         │
                                         ▼
                              ┌────────────────────┐
                              │   Route 53 / DNS   │ (opcional, domínio)
                              └─────────┬──────────┘
                                        │
                                        ▼
                         ┌─────────────────────────────┐
                         │  AWS Load Balancer (ALB)    │ ◄─── Nginx Ingress Controller
                         │  (gerenciado pelo Nginx)    │      via IRSA (Service Account)
                         └─────────────┬───────────────┘
                                       │
                                       ▼
                          ┌────────────────────────┐
                          │   Amazon EKS Cluster    │
                          │   Managed K8s Control   │
                          └──────┬─────────────┬────┘
                                 │             │
                                 ▼             ▼
                      ┌──────────────────┐ ┌──────────────────────┐
                      │  Managed Node    │ │  Managed Node        │  Auto Scaling
                      │  Group (t3.small │ │  Group (t3.small     │  Min/Des/Max =
                      │  / t3.medium)    │ │  / t3.medium)        │  2 / 2 / 4
                      └────────┬─────────┘ └──────────┬───────────┘
                               │                      │
          ┌────────────────────┴──────────────────────┴─────────────────────────┐
          │   Pods K8s rodando nos Nós (5 Deployments):                         │
          │   auth-service   flag-service   targeting-service                   │
          │   evaluation-service (HPA CPU %)  analytics-service (KEDA SQS)      │
          │   (Todos com Service Accounts IRSA para acessar AWS com segurança)  │
          └───┬──────────┬────────────┬─────────────┬─────────────┬─────────────┘
              │          │            │             │             │
              │          │            │             │             │
  ┌───────────▼──┐  ┌───▼────────┐ ┌─▼────────┐ ┌──▼─────────┐ ┌▼──────────┐
  │  RDS         │  │  RDS       │ │ RDS      │ │ ElastiCache│ │  REDIS    │
  │  PostgreSQL  │  │  PostgreSQL│ │ Postgres │ │ Redis      │ │ Cache     │
  │  auth-db     │  │  flags-db  │ │ targeting│ │ t3.micro   │ └───────────┘
  │(db.t3.micro) │  │ (t3.micro) │ |(t3.micro)│ └─────┬──────┘
  └──────────────┘  └────────────┘ └──────────┘       │
                                                      │
                              evaluation-service usa Redis hot path cache.

                                                    ┌──────────────────────┐
                         ┌──────────────────┐       │  Amazon SQS Standard │
                         │  evaluation-svc  │──────►│ toggle-master-events │◄── (KEDA observa
                         └──────────┬───────┘       └──────────┬───────────┘    queueDepth p/
                                    │                          │                escalar analytics
                                    │                          ▼
                                    │                ┌────────────────────┐
                                    │                │ analytics-service  │ Consome SQS
                                    │                │ KEDA ScaledObject  │ → Put Dynamo
                                    │                └──────────┬─────────┘
                                    │                           │
                                    │                           ▼
                                    │              ┌──────────────────────────┐
                                    │              │  DynamoDB Table          │
                                    │              │  ToggleMasterAnalytics   │
                                    │              │  Partition Key event_id  │
                                    │              │  (autoscaling write/read │
                                    │              │   ou on-demand p/ dev)   │
                                    │              └──────────────────────────┘
                                    │
                  ┌─────────────────▼──────────────────────┐
                  │     5x Amazon ECR (Container Registry) │
                  │     auth / flag / targeting / evalu.   │
                  │     analytics (imagens multi-stage)    │
                  └────────────────────────────────────────┘
```

---

## 2. Mapa geral dos recursos AWS a criar com Terraform

| #  | Categoria AWS                        | Recurso                                                                              | Quantidade | Uso pelo serviço                                                                                        |
| -- | ------------------------------------ | ------------------------------------------------------------------------------------ | ---------- | -------------------------------------------------------------------------------------------------------- |
| 1  | **Rede**                       | **VPC dedicada**                                                               | 1          | Isola todo o ToggleMaster do resto da conta                                                              |
| 2  | Rede                                 | Sub-redes públicas (×3 AZ)                                                         | 3          | Bastion + ALB/NLB + NAT GWs                                                                              |
| 3  | Rede                                 | Sub-redes privadas (×3 AZ)                                                          | 6          | RDS, ElastiCache, Nós do EKS (workloads sensíveis)                                                     |
| 4  | Rede                                 | Internet Gateway                                                                     | 1          | Acesso internet pública (saída para pacotes atualizações ALB, entrada Ingress)                       |
| 5  | Rede                                 | NAT Gateway ×3 (uma por AZ) + Elastic IP ×3                                        | 3          | Nós privados → internet (baixar imagens, chamadas APIs AWS public endpoints)                           |
| 6  | Rede                                 | Route Tables públicas + privadas ×3                                                | 4          | Encaminhamento                                                                                           |
| 7  | Rede                                 | VPC Endpoints (opcional: S3, ECR-DKR, ECR-API, STS, Logs)                            | 5+         | Reduz custo NAT Gateway e aumenta segurança de tráfego AWS                                             |
| 8  | **IAM & Segurança**           | OIDC Provider do EKS (OIDC)                                                          | 1          | Habilita IRSA = autenticação de Service Accounts K8s → Roles IAM                                      |
| 9  | IAM                                  | IAM Role Ingress-Nginx-Controller (IRSA)                                             | 1          | Permissão de criar/gerenciar ALB/NLB                                                                    |
| 10 | IAM                                  | IAM Role KEDA-Operator (IRSA)                                                        | 1          | Permite ao KEDA ler SQS`ApproximateNumberOfMessagesVisible` + métricas CloudWatch                     |
| 11 | IAM                                  | IAM Role Evaluation-Service (IRSA)                                                   | 1          | `sqs:SendMessage` na fila toggle-master-events                                                         |
| 12 | IAM                                  | IAM Role Analytics-Service (IRSA)                                                    | 1          | `sqs:ReceiveMessage`, `sqs:DeleteMessage`, `dynamodb:PutItem`                                      |
| 13 | IAM                                  | IAM Role EKS-Cluster-Role (padrão eksctl / eks module)                              | 1          | Permissões do plano de controle EKS                                                                     |
| 14 | IAM                                  | IAM Role Node-Instance-Role (padrão eks worker nodes)                               | 1          | Permissões básicas (ECR pull, CNI, CloudWatch logs)                                                    |
| 15 | Segurança (SGs)                     | Security Groups dedicados ×7                                                        | 7          | Segregação de tráfego por componente (ver seção 4)                                                  |
| 16 | **Registro de Imagens**        | ECR repositórios (private) ×5                                                      | 5          | `auth-service`, `flag-service`, `targeting-service`, `evaluation-service`, `analytics-service` |
| 17 | **Orquestração**             | Cluster EKS (Kubernetes)                                                             | 1          | Control plane gerenciado pela AWS                                                                        |
| 18 | Orquestração                       | Managed Node Group (ASG + Launch Template)                                           | 1          | ASG Min 2 / Des 2 / Max 4, instâncias t3.small ou t3.medium                                             |
| 19 | **Bancos relacionais**         | RDS PostgreSQL (auth-db)                                                             | 1          | db.t3.micro, Multi-AZ opcional (dev single-AZ)                                                           |
| 20 | Bancos relacionais                   | RDS PostgreSQL (flags-db)                                                            | 1          | db.t3.micro                                                                                              |
| 21 | Bancos relacionais                   | RDS PostgreSQL (targeting-db)                                                        | 1          | db.t3.micro                                                                                              |
| 22 | **Cache**                      | ElastiCache for Redis (cluster mode disabled, 1 shard)                               | 1          | cache.t3.micro / cache.t4g.micro                                                                         |
| 23 | **Mensageria**                 | SQS Standard Queue`toggle-master-events`                                           | 1          | Comunicação assíncrona evaluation → analytics                                                        |
| 24 | **NoSQL**                      | DynamoDB Table`ToggleMasterAnalytics`                                              | 1          | event_id (Partition Key String)                                                                          |
| 25 | **Observabilidade (opcional)** | CloudWatch Log Groups para /aws/eks/toggle-master/cluster, + cada RDS, + ElastiCache | N          | Logs nativos                                                                                             |
| 26 | Observabilidade (opcional)           | KMS Customer Managed Key para RDS, EBS volumes nós                                  | 1          | Criptografia em repouso chave própria                                                                   |

---

## 3. Rede — Rede (Módulo Terraform `networking`)

### 3.1 Por que uma VPC DEDICADA ao projeto ToggleMaster?

Separar workloads de estudo / desafio da sua conta AWS pessoal padrão. Permite CIDR block limpo, fácil destruição (terraform destroy sem medo de apagar recurso de outro projeto), controle granular Security Groups e fluxo.

### 3.2 CIDR sugerido

| CIDR                                                                                                | Uso                                                     |
| --------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| VPC CIDR                                                                                            | `10.20.0.0/16` (65k IPs)                              |
| Sub-redes públicas ×3 AZs (us-east-1a, 1b, 1c)                                                    | `10.20.0.0/20`, `10.20.16.0/20`, `10.20.32.0/20`  |
| Sub-redes privadas ×3 AZs                                                                          | `10.20.48.0/20`, `10.20.64.0/20`, `10.20.80.0/20` |
| Multi-AZ é**obrigatório** para: RDS Multi-AZ failover, ElastiCache, nós em múltiplas AZs. |                                                         |

### 3.3 Internet Gateway (IGW)

Anexado à VPC. Usado para:

- Tráfego de entrada para o ALB (Ingress Controller) → acesso público.
- NAT Gateways na subnet pública usam o IGW para fazer saída p/ internet.

### 3.4 NAT Gateway ×3 (uma por AZ pública) + Elastic IP ×3

Nós do EKS, RDS, Redis (nas privadas) **não tem IP público**. Para:

- Baixar imagens Docker do ECR (ou Docker Hub).
- Chamadas públicas SDK AWS que não usam VPC Endpoint.
- Atualizações SO dos nós.

Cada NAT Gateway é criado em uma AZ → alta disponibilidade. Custo por hora ~$0.045/NAT-gateway/hr + $0.045/GB dados processados. Para o desafio de estudo, NAT único (1 AZ) reduz custo mas reduz HA. O time decide.

### 3.5 (Recomendado, opcional) VPC Endpoints tipo Gateway / Interface

Diminui custo de NAT Gateway pois tráfego AWS interno não passa pela internet:

- **Gateway Endpoint S3** (sem custo) → nós baixam imagens ECR layers do S3 gratuitamente sem NAT.
- **Interface Endpoint**: `com.amazonaws.us-east-1.ecr.dkr` + `ecr.api` (docker login + pull).
- **Interface Endpoint STS**: AssumeRoleWithWebIdentity IRSA dentro das pods.
- **Interface Endpoint Logs** (CloudWatch Logs).
- **Interface Endpoint SQS** (analytics e evaluation não usam internet para falar com SQS).
- **Interface Endpoint DynamoDB** (Gateway endpoint, sem custo, igual S3).

### 3.6 Route Tables

| Route Table   | Associada a          | Regra 0.0.0.0/0 para   |
| ------------- | -------------------- | ---------------------- |
| RT pública   | Sub-redes públicas  | Internet Gateway (IGW) |
| RT privada 1a | Subnet privada AZ 1a | NAT Gateway 1a         |
| RT privada 1b | Subnet privada AZ 1b | NAT Gateway 1b         |
| RT privada 1c | Subnet privada AZ 1c | NAT Gateway 1c         |

---

## 4. Segurança — IAM, IRSA & Security Groups

### 4.1 IRSA (IAM Roles para Service Accounts) — Pilar fundamental da Opção B

**Motivação**: Ao invés de colocar credenciais permanentes (ACCESS_KEY / SECRET_KEY hardcoded nas Secrets K8s) e ao invés de dar permissões IAM amplas para a Instance Role do nó (o que seria LabRole estilo Academy, inseguro pois QUALQUER pod do nó herda as permissões), nós usamos **IRSA**:

1. Criamos **OIDC Provider** (vinculado ao cluster EKS — fornece trust federado OpenID Connect entre AWS IAM e Service Accounts do Kubernetes).
2. Criamos **uma IAM Role por componente** que precisa acessar AWS.
3. A Role tem **Trust Policy** confia apenas no Service Account específico (`system:serviceaccount:<namespace>:<nome-sa>`).
4. Anotamos a Service Account K8s com a Role ARN: `eks.amazonaws.com/role-arn: arn:aws:iam::xxx:role/NomeRole`.
5. K8s monta o Web Identity Token automaticamente no pod → SDK AWS dentro do pod automaticamente faz `sts:AssumeRoleWithWebIdentity`.

**Roles IRSA a criar (Terraform)**:

| Role IAM                             | Service Account K8s                        | Políticas anexadas (permissões mínimas least privilege)                                                                                                                             |
| ------------------------------------ | ------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `EKS-Ingress-Nginx-Role`           | `ingress-nginx:ingress-nginx-controller` | `ec2:Describe*`, `elasticloadbalancing:*`, `wafv2:Get*`, `acm:*` list/read e create tags                                                                                       |
| `EKS-KEDA-Operator-Role`           | `keda:keda-operator`                     | `cloudwatch:GetMetricStatistics`, `cloudwatch:GetMetricData`, `sqs:GetQueueAttributes`, `sqs:ListQueues` (para KEDA ler a profundidade da fila e escalar analytics)            |
| `Evaluation-Service-Role`          | `apps:evaluation-service-sa`             | `sqs:SendMessage` restrito ao ARN `toggle-master-events`                                                                                                                           |
| `Analytics-Service-Role`           | `apps:analytics-service-sa`              | `sqs:ReceiveMessage`, `sqs:DeleteMessage`, `sqs:GetQueueAttributes` (restrito à fila), `dynamodb:PutItem`, `dynamodb:DescribeTable` (restrito ao ARN ToggleMasterAnalytics) |
| (Padrão eks)`EKS-Cluster-Role`    | N/A plano controle                         | AmazonEKSClusterPolicy (AWS managed)                                                                                                                                                   |
| (Padrão eks)`EKS-WorkerNode-Role` | Instance Profile nós                      | AmazonEKSWorkerNodePolicy, AmazonEKS_CNI_Policy, AmazonEC2ContainerRegistryReadOnly (AWS managed)                                                                                      |

### 4.2 Security Groups (Zero Trust) — isolamento de camadas

| Nome SG                       | Anexado a                         | Regras Inbound (source) | Porta                                                                           |
| ----------------------------- | --------------------------------- | ----------------------- | ------------------------------------------------------------------------------- |
| SG-ALB-Publico                | Load Balancer Ingress Nginx       | 0.0.0.0/0               | 80, 443                                                                         |
| SG-Nodes-EKS                  | ENIs dos Nós EKS (todas as pods) | SG-ALB-Publico          | 30000-32767 (NodePort do Ingress) + 443 (K8s API já tratado por control plane) |
| SG-RDS-Auth                   | RDS auth-db                       | SG-Nodes-EKS            | 5432                                                                            |
| SG-RDS-Flags                  | RDS flags-db                      | SG-Nodes-EKS            | 5432                                                                            |
| SG-RDS-Targeting              | RDS targeting-db                  | SG-Nodes-EKS            | 5432                                                                            |
| SG-Redis-ElastiCache          | Redis                             | SG-Nodes-EKS            | 6379                                                                            |
| SG-VPC-Endpoints (se criados) | ENIs endpoints                    | SG-Nodes-EKS            | 443                                                                             |

Nenhuma regra 0.0.0.0/0 nas privadas.

---

## 5. Amazon EKS (Cluster K8s) — Módulo terraform-aws-modules/eks/aws

### 5.1 Configuração do cluster

- Nome cluster: `toggle-master-eks`
- Versão Kubernetes: 1.29 (ou mais nova estável AWS)
- Logs do plano de controle habilitados: `api, audit, authenticator, controllerManager, scheduler` → CloudWatch Logs
- Endpoint access: **private + public** (acesso público kubectl de dev; dentro da VPC usa endpoint privado)
- Secrets Encryption Configuration com KMS Key (opcional, CMK)

### 5.2 Managed Node Group (MNG)

Tipo do desafio: `Managed` (AWS patching, upgrades, ASG gerenciado). Opção B usa eksctl ou módulo Terraform MNG.

| Item                                                    | Valor sugerido                                                                                          |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Nome                                                    | `toggle-master-mng-general`                                                                           |
| AMI Type                                                | `AL2_x86_64` (Amazon Linux 2 x86)                                                                     |
| Tamanho                                                 | `t3.small` (2 vCPU / 2 GB RAM, ~$0.0208/h — free tier elegível primeiros 12 meses) ou `t3.medium` |
| Capacidade OnDemand (sem SPOT no desafio, simplicidade) | sim                                                                                                     |
| Desired Size                                            | **2 nós**                                                                                        |
| Min Size                                                | 2                                                                                                       |
| Max Size                                                | 4                                                                                                       |
| Subnets                                                 | Apenas sub-redes**privadas** (nós sem IP público — segurança)                                 |
| Tags                                                    | CostCenter = fiap-toggle-master, Project = toggle-master, Environment = dev                             |

### 5.3 Add-ons EKS instalados via Terraform/Helm

| Add-on                               | Método                                   | Motivo                                                                                                                                                                       |
| ------------------------------------ | ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| CoreDNS (padrão EKS)                | EKS add-on padrão                        | DNS interno cluster                                                                                                                                                          |
| kube-proxy (padrão EKS)             | padrão                                   | network policies de L3                                                                                                                                                       |
| VPC CNI (Amazon VPC CNI)             | EKS add-on                                | cada pod recebe IP privado da VPC                                                                                                                                            |
| Metrics Server                       | `kubectl apply` ou Helm oficial         | **OBRIGATÓRIO para HPA funcionar** (HPA lê CPU/Mem via metrics.k8s.io API)                                                                                           |
| Nginx Ingress Controller             | Helm chart`ingress-nginx/ingress-nginx` | Service Account IRSA`ingress-nginx-controller` → cria ALB público automaticamente. Ingress manifest path routing.                                                        |
| KEDA v2.x (Event-driven Autoscaling) | Helm chart`kedacore/keda`               | **Objetivo**: escalar analytics de 0→N pods baseado no SQS `ApproximateNumberOfMessagesVisible`. Opção B recomenda KEDA no lugar de HPA CPU simples p/ analytics. |

---

## 6. Datastores (RDS, ElastiCache Redis, DynamoDB) + SQS

### 6.1 RDS PostgreSQL ×3 (auth / flags / targeting)

Motivo arquitetônico: **separação de bancos por serviço (desacoplamento)**. Cada microsserviço dono do seu schema, do seu lifecycle, pode migrar independentemente. Se um RDS fica lento ou precisa upgrade não afeta os outros dois.

Cada RDS tem estas configurações padrão:

| Item                      | Config                                                                                                                                                                          |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Engine                    | PostgreSQL 15.x (alinhado com o compose local`postgres:15-alpine`)                                                                                                            |
| Instância classe         | `db.t3.micro` (free tier elegível 12 meses, 1 vCPU/1 GB)                                                                                                                     |
| Multi-AZ deploy           | **estudo pode ser Single-AZ** (reduz custo); produção Multi-AZ para failover automático.                                                                               |
| Storage                   | gp3 20 GB                                                                                                                                                                       |
| Storage autoscaling       | Sim até 100 GB (evita surpresas)                                                                                                                                               |
| Master username + senha   | gerado aleatório via Terraform`random_password`, salvo em Secrets Manager (recomendado) ou simplesmente outputs + use `sensitive = true`. **Não commitado em Git.** |
| VPC                       | Sub-redes privadas (NÃO público)                                                                                                                                              |
| Security Group            | Somente SG-Nodes-EKS / SG-Bastion se criarmos                                                                                                                                   |
| Automated backups         | Retenção 7 dias (estudo ok; produção 30d)                                                                                                                                   |
| Enhanced Monitoring       | Sim granularidade 60s (CloudWatch Logs)                                                                                                                                         |
| Performance Insights      | db.t3.micro habilita.                                                                                                                                                           |
| Parameter Group           | shared_buffers ajustado para a classe.                                                                                                                                          |
| Final snapshot ao deletar | no final desafio.                                                                                                                                                               |

**Bancos criados:**

1. **auth-db** — tabela `api_keys` (ver auth-service/db/init.sql)
2. **flags-db** — tabela `flags` + trigger updated_at (flag-service/db/init.sql)
3. **targeting-db** — tabela `targeting_rules` JSONB + trigger (targeting-service/db/init.sql)

### 6.2 ElastiCache for Redis

Uso: hot path cache evaluation-service, reduz latência de `/evaluate`.

| Item               | Config                                                                            |
| ------------------ | --------------------------------------------------------------------------------- |
| Engine             | Redis 7.x (compatível com compose redis:7)                                       |
| Node type          | `cache.t4g.micro` (Graviton2, ~$0.016/h, free tier elegível) OU cache.t3.micro |
| Num cache clusters | 1 shard / 1 node (Single-AZ desafio; ReplicaMulti-AZ se orçamento permitir)      |
| Subnet group       | Sub-redes privadas                                                                |
| Security Group     | 6379 aberto apenas para SG-Nodes-EKS                                              |
| Transit encryption | Desabilitado para desafio dev (sem senha do Redis)                                |
| Auth token         | Desabilitado / opcional                                                           |

TTL das chaves no evaluation-service: alguns segundos/minutos (configurável por variável no helm ou configmap).

### 6.3 Amazon SQS Standard Queue — toggle-master-events

Comunicação assíncrona entre evaluation-service (publica `EvaluationEvent`) → analytics-service (consome).

| Item                          | Config                                                                                                                                                                        |
| ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Queue Name                    | `toggle-master-events` (nome definido no evaluation e analytics compose)                                                                                                    |
| Tipo                          | **Standard Queue** (at-least-once delivery, ordem best-effort, throughput ilimitado. Ideal para eventos de analytics.                                                   |
| DelaySeconds                  | 0s (entrega imediata após publish)                                                                                                                                           |
| MessageRetentionPeriod        | **345.600s (4 dias)** padrão.                                                                                                                                          |
| VisibilityTimeout             | **300s (5m)** (analytics processa batch 10 mensagens, tem tempo para PutItem Dynamo e delete)                                                                           |
| ReceiveMessageWaitTimeSeconds | **20s** (long polling — menos API calls e custo menor)                                                                                                                 |
| MaximumMessageSize            | 256KB (ok, EvaluationEvent tem só user_id + flag_name + result + timestamp)                                                                                                  |
| Dead Letter Queue (opcional)  | Criar outra SQS`toggle-master-events-dlq` + redrive policy = depois de 5 receives com erro, vai p/ DLQ p/ investigação pós. **Muito recomendado para produção.** |

**KEDA ScaledObject observa esta fila via `ApproximateNumberOfMessagesVisible`** → escalar analytics automaticamente.

### 6.4 Amazon DynamoDB Table ToggleMasterAnalytics

Destino final de todo evento de avaliação. Dados analíticos / consulta por flag e usuário.

| Item                          | Config                                                                                                                                                           |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Table Name                    | ToggleMasterAnalytics (igual README e app.py analytics-service)                                                                                                  |
| Partition Key                 | `event_id` tipo **String (S)**                                                                                                                           |
| Sort Key                      | Sem sort key (simples para desafio). Consultar por flag_name e user_id com**GSIs abaixo recomendadas**                                                     |
| Table Class                   | Standard (padrão)                                                                                                                                               |
| Billing mode                  | `PAY_PER_REQUEST` (on-demand — estudo perfeito, $0 por mês se zero reads/writes + até thresholds generosos. Evita pagar por capacidade provisionada ociosa. |
| Server-side encryption        | DynamoDB owned key (padrão sem custo extra)                                                                                                                     |
| Point-in-time Recovery (PITR) | desabilitado p/ desafio (custo extra)                                                                                                                            |
| TTL Attribute (opcional)      | `timestamp` → 90 dias auto-expira dados antigos. Ajustar analytics para atributo epoch.                                                                       |
| Tags                          | CostCenter fiap-toggle-master                                                                                                                                    |

**Índices Secundários Globais (GSIs) recomendados para consulta analítica pós implementação:**

| GSI Name                   | Partition Key (PK)     | Sort Key          | Uso analítico típico                               |
| -------------------------- | ---------------------- | ----------------- | ---------------------------------------------------- |
| `GSI_FlagName_Timestamp` | `flag_name` (S)      | `timestamp` (S) | Contagem de eventos por flag em uma janela de tempo. |
| `GSI_UserId_FlagName`    | `user_id` (S)        | `flag_name` (S) | Histórico de flags que um usuário viu.             |
| `GSI_Result_FlagName`    | `result` (BOOL ou S) | `flag_name` (S) | % true/false por flag.                               |

---

## 7. Amazon ECR ×5 repositórios privados

Registro de contêiner gerenciado pela AWS. Cada microsserviço tem seu próprio repositório:

| Repositório           | Porta do serviço | Source code         |
| ---------------------- | ----------------- | ------------------- |
| `auth-service`       | 8001              | auth-service/       |
| `flag-service`       | 8002              | flag-service/       |
| `targeting-service`  | 8003              | targeting-service/  |
| `evaluation-service` | 8004              | evaluation-service/ |
| `analytics-service`  | 8005              | analytics-service/  |

Configurações por repositório:

- **Immutability de tags** habilitado (tag `latest` pode ser mutable para estudo; ou `immutable` e usar hash commit de tag)
- **Lifecycle Policy**: manter apenas últimas 10 imagens de `*-main-*` e apagar imagens > 60 dias sem tag. Evita custo storage ($0.10/GB-mês).
- **Scan on push**: habilitado (detecta vulnerabilidades nas imagens automaticamente).
- Policy de acesso anônimo é **negado**. Acesso ao pull: via role de nós (AmazonEC2ContainerRegistryReadOnly anexado a NodeRole) **e** via IRSA roles específicas p/ apps push (CI/CD).

---

## 8. Custos estimados p/ ambiente de estudo (Opção B, conta pessoal, us-east-1, 1 mês, 730h)

> Ordem de magnitude. Free-tier cobre quase tudo no primeiro ano.

| Recurso                                                                                              | Estimativa mensal aproximada (USD)                                                                                                                  |
| ---------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| EKS Cluster (Control Plane hour)                                                                     | $73.00 (obrigaório EKS ~$0.10/hr, é item mais caro. AWS Free Tier**não cobre EKS control plane**.)                                         |
| 2 × EC2 t3.small worker nodes (On-demand)                                                           | 2 × 0.0208 × 730 ≈ $30.00. Cobre free tier elegível t3.micro p/ 1 ano.                                                                          |
| 3 × NAT Gateways ($0.045/hr) + GB trafego                                                           | $98.55 + ~$10 dados ≈ $108 (ou $36 para 1 NAT p/ reduzir custo estudo)                                                                             |
| 3 × RDS db.t3.micro PostgreSQL Single-AZ                                                            | 3 × $0.017/hr × 730 ≈ $37.23 → coberto por free tier 1 ano se elegível.                                                                        |
| 1 × ElastiCache cache.t4g.micro Redis                                                               | $0.016 × 730 ≈ $11.68 → free tier elegível                                                                                                      |
| 1 × DynamoDB On-Demand (ToggleMasterAnalytics)                                                      | $0.00 (baixa carga teste) → ~grátis.                                                                                                              |
| 1 × SQS Standard (1 milhão requests)                                                               | ~$0.40 (grátis para poucas chamadas).                                                                                                              |
| 5 × ECR + alguns GB + CloudWatch                                                                    | $2-10.                                                                                                                                              |
| VPC Endpoints (5× interface, $0.01/hr cada)                                                         | $29.20.                                                                                                                                             |
| Total Aproximado opção estudo econômica (1 NAT, sem endpoints, free tier elegível EC2/RDS/Redis) | EKS $73 + EC2 ~$0 free tier + NAT $36 + RDS/Redis $0 free tier + o resto ~$10 =**aproximadamente ~$120 USD / mês total ambiente de estudo**. |
| Total opção mais próxima produção (3 NAT, VPC Endpoints, Multi-AZ RDS)                          | ~$250+/mês.                                                                                                                                        |

**Sugestão econômica para o desafio de estudo:**

- EKS cluster rodar **apenas durante dias letivos / finais de semana** → destruir com terraform destroy quando não usando. Economiza ~$70/semana de control plane (é o mais caro). Subir de novo com terraform apply demora ~15 minutos.
- 1 NAT Gateway apenas (perde um pouco de HA).
- t3.small, Single-AZ RDS, Dynamo e SQS quase zero.

---

## 9. Módulos Terraform a criar (organização do código na pasta `terraform/`)

```
terraform/
├── main.tf                      # configura provider AWS, backend, módulos
├── versions.tf                  # required_providers pinagem de versões
├── variables.tf                 # inputs (região, vpc_cidr, tamanhos instâncias, tags, etc.)
├── outputs.tf                   # kubeconfig, RDS endpoints, Redis endpoint, SQS URL/ARN, DynamoDB table name, ECR URLs, ALB DNS, etc.
├── apply.sh                     # script terraform init + plan + apply (padroniza exec time)
├── destroy.sh                   # script destroy (padroniza)
└── modules/
    ├── networking/              # VPC, subnets públicas/privadas, IGW, NAT GWs, RTs, VPC endpoints opc.
    ├── iam_irsa/                # OIDC EKS + IRSA Roles (Ingress / KEDA / Evaluation / Analytics + Trust Policies)
    ├── eks_cluster/             # Cluster EKS + Managed Node Group + Security Groups nodes
    ├── ecr/                     # 5 repositórios + lifecycle policies
    ├── rds/                     # 3 instâncias RDS Postgres + parameter groups + SGs (ou sub-módulo por banco)
    ├── elasticache/             # Redis cluster, subnet grp + SG
    ├── sqs/                     # fila standard ( + DLQ opcional)
    └── dynamodb/                # tabela ToggleMasterAnalytics + GSIs opcionais
```

---

## 10. Saídas (outputs.tf) obrigatórias do Terraform (input p/ próxima etapa — manifestos K8s e Secrets)

Após `terraform apply`, estes valores serão usados para construir Secrets e ConfigMaps K8s:

- `eks_cluster_name`, `kubeconfig` (gera arquivo ~/.kube/config ou comando aws eks update-kubeconfig …)
- `alb_ingress_dns_name` (do Ingress Controller, ainda não criado pelo TF, mas sim pelo Helm; output pode ser vazio e pego após `kubectl get ingress`)
- Endpoints RDS: `auth_db_endpoint`, `flags_db_endpoint`, `targeting_db_endpoint` + portas (5432) + senhas master (marcadas sensitive=true)
- `redis_endpoint` + `redis_port`
- `sqs_url`, `sqs_arn`
- `dynamodb_table_name` (ToggleMasterAnalytics)
- URLs 5x ECR: `auth_ecr_repo_url`, `flags_ecr_repo_url`, `targeting_ecr_repo_url`, `evaluation_ecr_repo_url`, `analytics_ecr_repo_url`
- `aws_region` (us-east-1)
- ARNs das 4 roles IRSA: `ingress_role_arn`, `keda_role_arn`, `evaluation_service_role_arn`, `analytics_service_role_arn` (para anotar Service Accounts K8s)

---

## Apêndice A — 🔐 Como Configurar a Sua Role AWS Pessoal + Rodar o Terraform Localmente

> 📖 **Documentação operacional COMPLETA** (copiar/colar comandos) está no arquivo:
> [`../terraform/README.md`](../terraform/README.md)
>
> **Modelo de variáveis (copiar e preencher com sua role ARN / profile):**
> [`../terraform/terraform.tfvars.example`](../terraform/terraform.tfvars.example)

Este apêndice explica **a integração da sua Role específica da conta AWS pessoal** no provider.
O objetivo é **NÃO USAR ADMIN FULL** e **NÃO USAR credenciais LONG-TERM hardcoded**.

### A.1 Como funciona a autenticação no provider Terraform AWS (ajustado em `terraform/versions.tf`)

O bloco `provider "aws"` do nosso projeto (linha ~25 em `versions.tf`) aceita **3 camadas de credenciais, em ordem de precedência**:

1.  **(Opcional) Variáveis locais `aws_profile`** — lê o profile nomeado de `~/.aws/config`.
2.  **(Sua Requisição) Variável `aws_assume_role_arn`** — se setada, o provider automaticamente faz `sts:AssumeRole` na sua role **antes de qualquer chamada AWS**. Se vazia (default), ignora e usa credenciais padrão.
3.  **Padrão SDK Credential Provider Chain** — env vars `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`, profile `[default]`, EC2/ECS/EKS IRSA role.

### A.2 Duas formas de usar (ESCOLHA SÓ UMA)

#### 🥇 Forma 1 — Recomendada: Profile AWS CLI com role_arn
**Passo a passo em 3 minutos:**
1.  Abra `~/.aws/config` e crie um profile com a ARN da sua role:
    ```ini
    [profile minha-conta-pessoal-base]
    region = us-east-1
    aws_access_key_id = AKIA_SUA_CREDENCIAL_BASE
    aws_secret_access_key = SUA_CHAVE_LONGO_PRAZO

    [profile fiap-toggle-master]
    region           = us-east-1
    role_arn         = arn:aws:iam::SEU_NUMERO_CONTA:role/ToggleMasterDeployRole
    source_profile   = minha-conta-pessoal-base
    role_session_name= terraform-toggle-master-local
    ```
2.  Valide fora do Terraform que a role é assumida:
    ```bash
    aws sts get-caller-identity --profile fiap-toggle-master
    # Saída esperada mostra "Arn": "arn:aws:sts::...:assumed-role/ToggleMasterDeployRole/terraform-toggle-master-local"
    ```
3.  Copie `terraform/terraform.tfvars.example → terraform/terraform.tfvars` e coloque:
    ```hcl
    aws_profile = "fiap-toggle-master"
    # aws_assume_role_arn = ""  # DEIXE VAZIO — a role vem do profile automaticamente
    ```

#### 🥈 Forma 2 — Direto no Provider (sem ~/.aws/*):
Se você já tem credenciais base em env vars/default profile e permissão `sts:AssumeRole`:
1.  Copie `.tfvars.example` → `terraform.tfvars`:
    ```hcl
    aws_profile = null
    aws_assume_role_arn = "arn:aws:iam::SEU_NUMERO_CONTA:role/ToggleMasterDeployRole"
    ```
2.  Válido. Provider automaticamente faz STS AssumeRole antes de qualquer operação.

### A.3 Trust Policy MÍNIMA OBRIGATÓRIA na sua Role `ToggleMasterDeployRole`

Sem essa trust policy, o AssumeRole retorna `AccessDenied`. Cole no Console AWS IAM → Roles → Sua Role → Trust relationships:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::SEU_NUMERO_CONTA:root"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### A.4 Permissões IAM Mínimas (Managed Policy) para a Role de Deploy

Para não precisar de `AdministratorAccess`, crie uma política gerenciada com estes **grupos de ações**:
- `ec2:*` (VPC, Security Groups, Subnets, NAT, IGW, EBS)
- `rds:*` (3 bancos)
- `elasticache:*` (Redis)
- `dynamodb:*` (Tabela eventos)
- `sqs:*` (Fila + DLQ)
- `ecr:*` (5 repositórios, lifecycle)
- `cloudwatch:*` (métricas, logs)
- `iam:CreateRole / DeleteRole / AttachRolePolicy / PutRolePolicy` (futuras roles IRSA)
- `iam:PassRole` (para RDS monitoramento, se habilitado)
- `kms:*` (se usar CMK)
- `sts:GetCallerIdentity` (debug)

### A.5 Primeiro Teste (Não Custa Nada!)

```bash
cd terraform
terraform init       # (se ainda não rodou)
terraform plan       # 0 erros = autenticação + provider funcionando (NÃO cria nada na AWS!)
```

Saída esperada: `Plan: N to add, N to change, N to destroy.` (N ≠ 0 = OK, vai criar os módulos; N = 0 = vazia ou já aplicada).

---

## 11. Referências e links internos

| Documento                                                        | Link                                                                          |
| ---------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| Documento ambiente local Docker Compose                          | [./README.md](./README.md)                                                     |
| Documento arquitetura microsserviços (comunicação entre apps) | [./arquitetura-comunicacao-servicos.md](./arquitetura-comunicacao-servicos.md) |
| Plano sprint backlog do time                                     | [../PLANO-ENTREGA-SPRINT.md](../PLANO-ENTREGA-SPRINT.md)                       |
