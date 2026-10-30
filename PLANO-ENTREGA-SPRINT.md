# 📋 Plano Ágil — ToggleMaster Tech Challenge

## Time: 4 generalistas • Prazo: 3 semanas • Infra as Code: Terraform

> **Opção escolhida:** Opção B — Conta Pessoal AWS (eksctl, IRSA, KEDA, sem restrições LabRole)
> **Cultura do time:** Todos colaboram em tudo, pair programming frequente, somos generalistas.

---

## 🎯 Meta Geral do Produto

Concluir implantação do ToggleMaster como microsserviços em **EKS**, com toda infra escrita em **Terraform**, autoescalando via HPA + KEDA, provado em vídeo + relatório de entrega.

---

---

## 🏃 SPRINT 1 — Semana 1: Docker local + Infra AWS como código (Terraform)

---

**Sprint Goal:**

1) `docker compose up` sobe **9 containers** e passa no teste E2E local.
2) Código Terraform provisiona, via `terraform apply`, **toda a infra AWS** e valida todos os recursos rodando saudáveis.

### Definition of Done (Sprint 1)

- [X] `docker compose up` sem erros → `docker ps` mostra **9 containers** (5 apps + 4 DBs locais)
- [X] Teste E2E local: criar chave → criar flag → criar regra → `/evaluate` → item no DynamoDB Local
- [X] Terraform state consistente — `terraform plan` mostra `0 changes` após apply
- [X] `terraform output` lista **todos os endpoints**:  3× RDS endpoint, ElastiCache Redis endpoint, SQS URL/ARN, DynamoDB table name, 5× URLs ECR
- [X] `kubectl get nodes --kubeconfig <output_tf>` → nodes EKS em **Ready**
- [X] Console AWS confirma visualmente os 10+ recursos (dupla checagem)

### Sprint Backlog

| Tarefa | Descrição                                                                                                                                                                                    |
| ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| T1.1   | Criar**5 Dockerfiles multi-stage** (2 Go + 3 Python) otimizados                                                                                                                          |
| T1.2   | Escrever**docker-compose.yml** raiz com 4 DBs locais (3× Postgres, Redis, DynamoDB Local) + 5 serviços, healthchecks, networks, init.sql automáticos                                  |
| T1.3   | Script**smoke-test local** automatizado: cria chave/flag/regra via curl, valida evaluate e item no DynamoDB Local                                                                        |
| T1.4   | **Bootstrap Terraform**: `provider "aws"` (Opção B, conta pessoal, us-east-1), backend (S3 + DynamoDB lock ou local), `versions.tf` com pinagem de versões                        |
| T1.5   | **Módulo Terraform Networking**: VPC dedicada (3 AZs, subnets públicas + privadas), IGW, NAT GWs, Route Tables                                                                         |
| T1.6   | **Módulo Terraform ECR**: 5 repositórios (`auth`, `flag`, `targeting`, `evaluation`, `analytics`) com lifecycle policy                                                       |
| T1.7   | **Módulo Terraform EKS**: Cluster EKS + Managed Node Group (t3.small/t3.medium, ASG Min=2, Des=2, Max=4), **OIDC Provider habilitado** (essencial p/ IRSA). Output `kubeconfig` |
| T1.8   | **Módulo Terraform RDS**: 3 instâncias PostgreSQL independentes (`auth-db`, `flag-db`, `targeting-db`), db.t3.micro, Security Groups aceitam tráfego VPC EKS                    |
| T1.9   | **Módulo Terraform ElastiCache**: Cluster Redis (cache.t3.micro), mesma VPC, SG privado. Output endpoint                                                                                |
| T1.10  | **Módulo Terraform SQS + DynamoDB**: SQS Standard Queue (`toggle-master-events`) + DynamoDB `ToggleMasterAnalytics` (PK `event_id:String`)                                        |
| T1.11  | `outputs.tf` consolidado + scripts `apply.sh` + `destroy.sh`                                                                                                                             |

**Dinâmica da semana:**

- Dia 1-2 → T1.1, T1.2 (2 duplas: 1 dupla Python + DBs, 1 dupla Go + services)
- Dia 2-3 → T1.3 + T1.4 bootstrap TF (1 pessoa smoke test, 3 iniciam VPC juntos — pair)
- Dia 3-4 → Duplas paralelas nos módulos TF:
  - Dupla 1 → T1.7 EKS + T1.5 VPC
  - Dupla 2 → T1.6 ECR + T1.8 RDS + T1.9 Redis + T1.10 SQS/Dynamo
- Dia 5 → Consolidação → `terraform plan` → `apply` → validação coletiva

---

---

## 🏃 SPRINT 2 — Semana 2: Imagens no ECR + App rodando público no EKS via Ingress

---

**Sprint Goal:**
Imagens buildadas e pushadas para ECR usando outputs TF. Todos os 5 serviços rodam como **Pods Running** em Namespace dedicado, com Secrets/ConfigMaps + Deployments + Services. **Nginx Ingress Controller com IRSA** expõe tudo publicamente. Fluxo E2E via DNS público do ALB/NLB funciona.

### Definition of Done (Sprint 2)

- [X] 5 imagens Docker `:latest` existem nos 5 repositórios ECR
- [X] `kubectl top nodes` funcionando → Metrics Server instalado
- [X] `kubectl get pods -n apps` → 5 pods Running + READY 1/1 + restart: 0
- [X] `kubectl get ingress -n ingress-nginx` → Address do ALB/NLB preenchido
- [X] `curl http://<INGRESS_URL>/auth/health` + `/flags/health` + `/rules/health` + `/evaluate/health` → todos `{"status":"ok"}`
- [X] Fluxo E2E **público via Ingress**: criar chave → criar flag → criar regra → `/evaluate` retorna JSON válido

### Sprint Backlog

| Tarefa | Descrição                                                                                                                                                                                                                      |
| ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| T2.1   | **Build + push pipeline local**: builda 5 imagens com tag ECR (`terraform output ecr_urls`) + `docker push`                                                                                                            |
| T2.2   | **IAM Roles / IRSA via Terraform**: Extender módulo EKS com roles para (a) Ingress Controller (criar ALB/NLB), (b) ServiceAccount KEDA (SQS metrics + DynamoDB). Políticas + Trust Relationships OIDC                    |
| T2.3   | Instalar**Metrics Server** via `kubectl apply`                                                                                                                                                                           |
| T2.4   | Instalar**Nginx Ingress Controller via Helm**: ServiceAccount anotada com IRSA criada em T2.2. Validar criação ALB/NLB DNS público                                                                                      |
| T2.5   | **Manifestos K8s: Namespaces + Secrets + ConfigMaps**: namespaces `apps`, `ingress-nginx`, `keda`. Secrets base64 com valores de `terraform output`. ConfigMaps: URLs internas, nomes, MASTER_KEY, SERVICE_API_KEY |
| T2.6   | **Manifestos K8s: Deployments × 5 + Services ClusterIP × 5**: imagem ECR, envFrom Secrets/ConfigMaps, readiness/livenessProbe (`/health`), resources requests/limits                                                   |
| T2.7   | **Manifesto Ingress Nginx**: path-based routing (`/auth*`→auth, `/flags*`→flag, `/rules*`→targeting, `/evaluate*`→evaluation)                                                                                  |
| T2.8   | **ServiceAccounts IRSA para evaluation e analytics**: anotadas com role criada em T2.2 (evaluation→SQS SendMessage, analytics→SQS Receive+Delete + DynamoDB PutItem). Referenciar nos Deployments                        |
| T2.9   | Bateria**testes E2E via Ingress público** + troubleshooting + script de teste automatizado                                                                                                                                |

**Dinâmica da semana:**

- Dia 1-2 → T2.1, T2.3, T2.4 + T2.2 IRSA no Terraform (Ingress + IRSA é complexo: 2-3 pairando)
- Dia 3 → Duplas paralelas: Dupla A → T2.5 (Secrets/ConfigMaps + valida base64), Dupla B → T2.6 (Deployments/Services)
- Dia 4 → T2.7 Ingress manifest + T2.8 IRSA Service Accounts apps
- Dia 5 → T2.9 testes públicos, ajustes, Review + Retrospectiva

---

---

## 🏃 SPRINT 3 — Semana 3: Autoscaling (HPA + KEDA), Vídeo e Relatório

---

**Sprint Goal:**
HPA do evaluation escale sob carga HTTP. **KEDA analytics escale de 0→N** observando profundidade da fila SQS. Vídeo ≤20min finalizado. Relatório entrega PDF pronto.

### Definition of Done (Sprint 3)

- [ ] Gera carga evaluation → `kubectl get hpa -w` mostra réplicas aumentando, CPU caindo
- [ ] Enche SQS → `kubectl get pods -n apps -w` mostra analytics escalando (evidência KEDA por queueDepth)
- [ ] Console DynamoDB confirma milhares de itens chegando (SQS→analytics→Dynamo end-to-end)
- [ ] Vídeo ≤20min hospedado (YouTube), **todos os itens do PDF entregáveis** foram abordados
- [ ] Relatório entrega PDF finalizado com nomes/RM/Discord/links

### Sprint Backlog

| Tarefa                  | Descrição                                                                                                                                                                                                                                                                                                                                    |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| T3.1                    | Instalar**KEDA no cluster via Helm**: ServiceAccount anotada com IRSA criada em T2.2 (permissão SQS:GetQueueAttributes + CloudWatch:GetMetricStatistics)                                                                                                                                                                                |
| T3.2                    | Manifesto**HPA evaluation-service**: CPU target 70%, min=2, max=6~8. Behavior scaleUp/scaleDown suave                                                                                                                                                                                                                                    |
| T3.3                    | Manifesto**KEDA `ScaledObject` analytics**: trigger `aws-sqs-queue`, `queueURL` (output TF), `queueLength: 10`, `minReplicaCount: 0`, `maxReplicaCount: 10`                                                                                                                                                                  |
| T3.4                    | **Scripts de carga padronizados**: (a) `hey`/`ab` 500-1000 req/s evaluation Ingress URL (b) batch SQS SendMessage AWS CLI 500+ msgs                                                                                                                                                                                                  |
| T3.5                    | **Validação sob carga**: Rodar scripts + acompanhar `kubectl get hpa -w`, `kubectl get pods -w`, SQS queue depth, DynamoDB itens. Ajustar thresholds se necessário                                                                                                                                                                |
| T3.6                    | **Roteiro do vídeo** (checklist fiel ao PDF): docker compose up, eks nodes, kubectl get pods, Ingress curl demo, HPA evaluation com carga, KEDA analytics com SQS cheia, DynamoDB itens, explicação arquitetura, 3 datastores diferentes (RDS vs ElastiCache vs DynamoDB propósitos), justificativa HPA+KEDA, menção Terraform IaC |
| T3.7                    | **Gravar + editar vídeo ≤ 20 min**: 1 pessoa opera tela, 4 revezam falando. Cortar silêncios                                                                                                                                                                                                                                          |
| T3.8                    | **Relatório entrega PDF/.txt**: nomes completos, RM, username Discord, link repositório GitHub, link YouTube                                                                                                                                                                                                                           |
| T3.9 (OPCIONAL +10 pts) | Trilha Google Cloud Skills Boost concluída + badge pública no relatório                                                                                                                                                                                                                                                                     |

**Dinâmica da semana:**

- Dia 1-2 → T3.1, T3.2, T3.3, T3.4. KEDA mais crítico: 3 pairando nele, 1 prepara scripts de carga
- Dia 3 → T3.5 validação stress test
- Dia 4 → T3.6 roteiro → T3.7 gravação vídeo (dia reservado)
- Dia 5 → T3.8 relatório + T3.9 (opcional). Fechamento geral

---

---

## 🧑‍🤝‍🧑 Cerimônias Ágeis (TODOS participam)

| Cerimônia                        | Frequência               | Duração   | Objetivo                                                                           |
| --------------------------------- | ------------------------- | ----------- | ---------------------------------------------------------------------------------- |
| **Daily Standup**           | Diária 9h                | 15 min      | O que fiz ontem / hoje / bloqueios. Sincroniza 4 pessoas!                          |
| **Pair Programming Blocks** | 2×/dia (10-12h / 14-16h) | 1.5-2h cada | Ninguém trabalha solo em tarefa complexa (Terraform módulos, KEDA, Ingress IRSA) |
| **Sprint Review**           | Sexta 16h                 | 45 min      | Demo da meta do sprint + validar coletivamente o DoD                               |
| **Retrospectiva**           | Sexta 17h                 | 30 min      | O que deu certo/errado → ações melhoria p/ semana seguinte                      |

---

## 📐 Board Kanban (Notion / Trello / Jira)

```
📥 BACKLOG | 🚧 IN PROGRESS (máx 2 tasks por pessoa) | 👀 PEER REVIEW (outro membro valida) | ✅ DONE (atingiu DoD)
```

> Regra de ouro: **nenhuma tarefa vai direto de IN PROGRESS para DONE** — sempre passa por validação de outro par.

---

## 🧠 Artefatos Chave que o Time Produz ao Final

1. `Dockerfile` × 5 (um por serviço)
2. `docker-compose.yml` + `.env.example` na raiz
3. Pasta `terraform/` organizada:
   - `main.tf`, `versions.tf`, `variables.tf`, `outputs.tf`
   - `modules/` com subpastas (networking, eks, ecr, rds, elasticache, sqs-dynamodb, iam-irsa)
   - `apply.sh`, `destroy.sh`
4. Pasta `kubernetes/` organizada:
   - `namespaces/`, `secrets/`, `configmaps/`, `deployments/`, `services/`, `ingress/`, `autoscaling/` (HPA + KEDA)
5. Scripts utilitários: `smoke-test-local.sh`, `load-test-evaluation.sh`, `send-sqs-batch.sh`
6. Vídeo YouTube + Relatório entrega PDF
