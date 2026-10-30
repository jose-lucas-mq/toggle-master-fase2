# Roteiro de Gravação do Vídeo — ToggleMaster Tech Challenge FIAP (Fase 2)

> **Duração alvo: 19-20 minutos** (máximo permitido pelo desafio)
> **Formato: 1 pessoa opera a tela, os 4 revezam falando**
> **Gravação: tela + webcam (ou só tela com narração)**
> **Cortar: silêncios, waits longos de `terraform apply` (acelerar ou cortar)**

---

## Cronograma Geral (timestamps)

| Min         | Bloco                                   | Quem fala               | O que mostrar na tela                                    |
| ----------- | --------------------------------------- | ----------------------- | -------------------------------------------------------- |
| 0:00-0:45   | Abertura + Apresentação do Projeto      | Integrante 1            | Slide/Readme do projeto + nome do time                   |
| 0:45-3:00   | Arquitetura da Solução (visão geral)    | Integrante 1            | Diagrama `docs/arquitetura-aws.png`                      |
| 3:00-5:30   | Demo Local (Docker Compose)             | Integrante 2            | Terminal: `docker compose up` + E2E                      |
| 5:30-8:00   | Infraestrutura AWS via Terraform        | Integrante 3            | VSCode: arquivos `.tf` + AWS Console                     |
| 8:00-9:45   | Build & Push das Imagens para o ECR     | Integrante 3            | Terminal: `push-all-images-to-ecr.sh` + Console ECR      |
| 9:45-12:15  | Kubernetes: Deploy dos Serviços         | Integrante 4            | Terminal: `kubectl` commands + manifests                 |
| 12:15-13:45 | E2E Público via Ingress                 | Integrante 4            | Terminal: `curl` no DNS do Ingress                       |
| 13:45-16:45 | **Autoscaling: HPA + KEDA**             | Integrante 4 → 2        | `kubectl get hpa -w` / `kubectl get pods -w` + SQS       |
| 16:45-18:30 | Diferenciais: IRSA, 3 Datastores, IaC   | Integrante 1            | Código dos manifests + Terraform                         |
| 18:30-20:00 | Encerramento + Links                    | Todos                   | Relatório + GitHub + YouTube                             |

---

# BLOCO 1 (0:00 - 0:45) — ABERTURA

**Integrante 1 fala:**

> "Olá! Nós somos o time [NOME DO TIME] e este é o nosso Tech Challenge da Fase 2 da Pós-Graduação em Arquitetura de Sistemas da FIAP. O projeto se chama **ToggleMaster** — uma plataforma de Feature Flags distribuída como microsserviços.

> Neste vídeo vamos mostrar:
>
> 1. A solução rodando localmente com Docker
> 2. Toda a infraestrutura AWS provisionada via Terraform
> 3. Os 5 microsserviços deployados no Kubernetes (EKS)
> 4. O fluxo E2E funcionando publicamente via Ingress
> 5. **Autoscaling: HPA por CPU e KEDA por profundidade de fila SQS**

> Vamos lá!"

**Tela:** README do repositório ou slide de abertura.

---

# BLOCO 2 (0:45 - 3:00) — ARQUITETURA DA SOLUÇÃO

**Integrante 1 fala, apontando para o diagrama `docs/arquitetura-aws.png`:**

> "A arquitetura é composta por **5 microsserviços**:
>
> - **auth-service** (Go) — autenticação, emissão de JWT
> - **flag-service** (Python) — CRUD de feature flags
> - **targeting-service** (Python) — regras de segmentação de usuários
> - **evaluation-service** (Go) — avalia se uma flag está ativa para um usuário (hot path)
> - **analytics-service** (Python) — processa eventos assíncronos e grava no DynamoDB

> A comunicação é assim:
>
> - O usuário acessa via **Ingress Nginx**, que faz path-based routing
> - `evaluation-service` consulta `flag-service` e `targeting-service`, usa **Redis** como cache e publica eventos no **SQS**
> - `analytics-service` consome a fila SQS e grava no **DynamoDB**
> - Cada serviço tem seu **RDS PostgreSQL** independente

> Repare que os dois serviços da ponta têm naturezas diferentes: o **evaluation é síncrono** (responde HTTP no hot path) e o **analytics é assíncrono** (só consome fila). Essa diferença vai ser o motivo de cada um escalar de um jeito — e vamos mostrar isso no bloco de autoscaling.

> Os serviços que acessam AWS (SQS, DynamoDB) usam **IRSA** — IAM Roles for Service Accounts — para autenticação segura sem secrets hardcoded.

> E toda essa infra é provisionada via **Terraform**, que vamos mostrar em seguida."

**Tela:** Mostrar o diagrama de arquitetura (arquitetura-aws.png).

---

# BLOCO 3 (3:00 - 5:30) — DEMO LOCAL (DOCKER COMPOSE)

**Integrante 2 opera o terminal:**

### Passo 3.1 — Subir o ambiente local

```bash
cd ~/codes/fiap-toggle-master
cp .env.example .env   # se não existir
docker compose up --build -d
```

> "Aqui temos o `docker-compose.yml` que sobe **11 containers**: 5 apps + 3 Postgres + Redis + DynamoDB Local + LocalStack (SQS). Cada serviço tem seu próprio banco, replicando a topologia de produção."

### Passo 3.2 — Verificar containers

```bash
docker compose ps
```

> "Vemos os 5 serviços rodando saudáveis (healthy). Os bancos foram inicializados via `init.sql`."

### Passo 3.3 — Criar chave de serviço

```bash
curl -X POST http://localhost:8001/admin/keys \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer SUA_MASTER_KEY" \
  -d '{"name": "evaluation-key"}'
```

> "O auth-service retorna uma `tm_key_...`. Essa chave identifica o evaluation-service."

### Passo 3.4 — Criar uma flag

```bash
API_KEY=tm_key_xxx_...
curl -X POST http://localhost:8002/flags \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"name": "enable-new-dashboard", "description": "novo dashboard", "is_enabled": true}'
```

### Passo 3.5 — Criar regra de targeting (50% dos usuários)

```bash
curl -X POST http://localhost:8003/rules \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"flag_name": "enable-new-dashboard", "is_enabled": true, "rules": {"type": "PERCENTAGE", "value": 50}}'
```

### Passo 3.6 — Avaliar a flag para diferentes usuários

```bash
curl "http://localhost:8004/evaluate?user_id=user-1&flag_name=enable-new-dashboard"
curl "http://localhost:8004/evaluate?user_id=user-2&flag_name=enable-new-dashboard"
curl "http://localhost:8004/evaluate?user_id=user-3&flag_name=enable-new-dashboard"
```

> "Veja que aproximadamente 50% dos usuários recebem `enabled: true`."

### Passo 3.7 — Verificar evento no DynamoDB Local

```bash
docker compose logs analytics-service
```

> "O analytics-service consumiu o evento do SQS e gravou no DynamoDB Local. O fluxo E2E local funciona."

**Tela:** Terminal com os comandos acima.

---

# BLOCO 4 (5:30 - 8:00) — INFRAESTRUTURA AWS VIA TERRAFORM

**Integrante 3 opera o VSCode + AWS Console:**

### Passo 4.1 — Estrutura do Terraform

> "A pasta `terraform/` está organizada em módulos. Vamos abrir o `main.tf`."

**Mostrar `terraform/main.tf`:**

> "Temos 9 módulos: networking, ecr, rds (3 instâncias), elasticache, sqs, dynamodb, eks_cluster e iam_irsa. Cada um encapsula um conjunto de recursos."

### Passo 4.2 — Backend S3

**Mostrar `terraform/backend.tf`:**

> "O estado do Terraform fica em um bucket S3 (`fiap-tf-state-5dclt`), nunca localmente. Isso evita perder o rastro dos recursos."

### Passo 4.3 — Módulo EKS

**Mostrar `terraform/modules/eks_cluster/main.tf`:**

> "O módulo `eks_cluster` cria o Control Plane do EKS, o Managed Node Group (2 nós t3.small, Min2/Max4), o OIDC Provider (essencial para IRSA) e os Security Groups."

### Passo 4.4 — Módulo IRSA

**Mostrar `terraform/modules/iam_irsa/main.tf`:**

> "O módulo `iam_irsa` cria 3 roles: `evaluation-pod` (SQS SendMessage), `analytics-pod` (SQS Receive/Delete + DynamoDB PutItem) e `keda-operator` (SQS GetQueueAttributes) — essa última vai ser usada pelo autoscaling que veremos no final. As trust policies condicionam o `sts:AssumeRoleWithWebIdentity` pelo OIDC do cluster."

### Passo 4.5 — Aplicar na AWS

```bash
cd terraform
terraform apply --auto-approve
```

> "O `apply` cria todos os recursos. (Mostrar resumo: 'Plan: 66 to add, 0 to change, 0 to destroy'.)"

> "(Cortar o wait de ~30 min. Acelerar ou cortar.)"

### Passo 4.6 — AWS Console

> "Agora no AWS Console, vemos:
>
> - VPC `toggle-master-vpc` com sub-redes públicas e privadas em 3 AZs
> - 3 instâncias RDS PostgreSQL
> - Cluster Redis ElastiCache
> - Fila SQS `toggle-master-events`
> - Tabela DynamoDB `ToggleMasterAnalytics`
> - Cluster EKS `toggle-master-eks` com 2 nós
> - 5 repositórios ECR"

**Tela:** VSCode com arquivos `.tf` + AWS Console (várias abas).

---

# BLOCO 5 (8:00 - 9:45) — BUILD & PUSH DAS IMAGENS PARA O ECR

**Integrante 3 opera o terminal:**

### Passo 5.1 — Rodar o script de push

```bash
cd terraform
./push-all-images-to-ecr.sh
```

> "Este script coleta as 5 URLs do ECR via `terraform output`, faz login no ECR com `aws ecr get-login-password`, builda e pusha as 5 imagens com tag `:latest`. O build é forçado para `linux/amd64`, porque os nós do EKS são x86 e nossa máquina é ARM."

### Passo 5.2 — Verificar no Console ECR

> "No Console AWS → ECR, vemos as 5 imagens `:latest` em cada repositório."

**Tela:** Terminal rodando o script + Console ECR.

---

# BLOCO 6 (9:45 - 12:15) — KUBERNETES: DEPLOY DOS SERVIÇOS

**Integrante 4 opera o terminal:**

### Passo 6.1 — Conectar kubectl ao EKS

```bash
aws eks update-kubeconfig --region us-east-1 --name toggle-master-eks
kubectl get nodes
```

> "Vemos os 2 nós do EKS em estado Ready."

### Passo 6.2 — Instalar Ingress Nginx

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer
```

> "Isso cria um Load Balancer público que vai receber o tráfego da internet."

### Passo 6.3 — Mostrar manifests K8s

**Mostrar `kubernetes/` no VSCode:**

> "Temos manifests para: namespaces, serviceaccounts (IRSA), configmap, secrets template, 5 deployments+services, ingress, e os manifestos de autoscaling — o HPA e o KEDA ScaledObject, que veremos no próximo bloco."

**Abrir `kubernetes/evaluation-service.yaml`:**

> "Veja que o `evaluation-service` usa `serviceAccountName: evaluation-sa`, que está anotado com a role IRSA. As env vars vêm de configmap e secrets."

**Abrir `kubernetes/ingress.yaml`:**

> "O Ingress faz path-based routing: `/auth/*` → auth-service, `/flags/*` → flag-service, etc."

### Passo 6.4 — Deploy dos serviços

```bash
cd ../kubernetes
./apply.sh
```

> "O `apply.sh` coleta os valores do `terraform output` (endpoints RDS, URLs ECR, ARNs IRSA), gera os manifests reais com os placeholders substituídos, codifica os segredos em base64 e aplica tudo na ordem correta. Ele também aplica o HPA e o KEDA ScaledObject."

### Passo 6.5 — Verificar pods

```bash
kubectl get pods -n apps
kubectl get ingress -n apps
```

> "Todos os pods estão Running e Ready. Repare que o `evaluation-service` já está com **2 réplicas** — é o mínimo definido no HPA. E o `analytics` está com **zero**, porque a fila está vazia e o KEDA o mantém desligado."

**Tela:** Terminal com kubectl + VSCode com manifests.

---

# BLOCO 7 (12:15 - 13:45) — E2E PÚBLICO VIA INGRESS

**Integrante 4 opera o terminal:**

### Passo 7.1 — Pegar URL do Ingress

```bash
INGRESS=$(kubectl get ingress togglemaster-api-ingress -n apps -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo $INGRESS
```

### Passo 7.2 — Health checks públicos

```bash
curl http://$INGRESS/auth/health
curl http://$INGRESS/flags/health
curl http://$INGRESS/rules/health
curl http://$INGRESS/evaluate/health
```

> "Todos os serviços respondem `{"status":"ok"}` publicamente."

> "(Observação: o `analytics-service` é um worker interno e não é exposto no Ingress.)"

### Passo 7.3 — Fluxo E2E público (mesmo do local, mas via DNS público)

```bash
# Criar chave
curl -X POST http://$INGRESS/auth/admin/keys \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer SUA_MASTER_KEY" \
  -d '{"name": "prod-key"}'

# Criar flag
curl -X POST http://$INGRESS/flags \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"name": "enable-new-checkout", "is_enabled": true}'

# Criar regra (usuários específicos)
curl -X POST http://$INGRESS/rules \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"flag_name": "enable-new-checkout", "is_enabled": true, "rules": {"type": "USER_LIST", "users": ["user-premium-1"]}}'

# Avaliar
curl "http://$INGRESS/evaluate?user_id=user-premium-1&flag_name=enable-new-checkout"
curl "http://$INGRESS/evaluate?user_id=user-normal&flag_name=enable-new-checkout"
```

### Passo 7.4 — Verificar no DynamoDB

> "No Console DynamoDB, vemos o item do evento de avaliação gravado. O fluxo completo: Ingress → evaluation → SQS → analytics → DynamoDB funciona em produção."

**Tela:** Terminal com curl + Console DynamoDB.

---

# BLOCO 8 (13:45 - 16:45) — AUTOSCALING: HPA + KEDA

**Integrante 4 apresenta o HPA (CPU). Integrante 2 apresenta o KEDA (fila SQS).**

> Bloco mais importante da Sprint 3 — dedique calma e mostre os terminais com `-w` em paralelo.

### Passo 8.1 — A justificativa (por que cada serviço escala de um jeito)

**Integrante 4 fala:**

> "Antes de mostrar rodando, o **porquê**. Temos dois tipos de carga diferentes, e cada uma pede um sinal de escala diferente.
>
> O **evaluation-service** é **síncrono** — ele responde requisições HTTP no hot path. A carga dele se traduz em **CPU**. Então usamos o **HPA**, o Horizontal Pod Autoscaler nativo do Kubernetes, com alvo de **70% de CPU**, entre **2 e 8 réplicas**.
>
> O **analytics-service** é **assíncrono** — ele não recebe HTTP, só consome a fila SQS. CPU **não serve** como métrica pra ele, porque ele fica ocioso esperando mensagem. O sinal correto é a **profundidade da fila**. E é exatamente pra isso que existe o **KEDA**: ele lê o tamanho da fila SQS e ajusta o número de réplicas — inclusive **de zero a N**, e **de volta a zero** quando não há mensagens. Isso é economia real: sem fila, sem worker ligado."

### Passo 8.2 — Mostrar os manifests

**Abrir `kubernetes/hpa-evaluation.yaml`:**

> "No HPA: `autoscaling/v2`, CPU 70%, min 2 e max 8, com `behavior` para subir rápido e descer devagar — isso evita o efeito de 'flapping', ficar criando e destruindo pod toda hora."

**Abrir `kubernetes/keda-scaledobject.yaml`:**

> "No KEDA temos dois objetos. O `TriggerAuthentication` diz **como** autenticar na AWS — e aqui entra o **IRSA**: o KEDA usa a ServiceAccount `keda-operator`, anotada com a role IAM, **sem nenhuma credencial hardcoded**. E o `ScaledObject` diz **o que** escalar: o deployment `analytics-service`, com trigger `aws-sqs-queue`, `queueLength: 10` — ou seja, uma réplica para cada 10 mensagens na fila — `min 0`, `max 10`."

### Passo 8.3 — Instalar os componentes

```bash
cd kubernetes
./install-keda.sh
```

> "O script instala dois componentes: o **Metrics Server**, que o HPA usa pra ler o CPU dos pods, e o **KEDA**, reaproveitando a ServiceAccount já anotada com IRSA."

```bash
kubectl get pods -n keda
kubectl get crd scaledobjects.keda.sh
```

### Passo 8.4 — Estado inicial (em repouso)

```bash
kubectl get hpa -n apps
kubectl get scaledobject -n apps
kubectl get pods -n apps
```

> "Em repouso: o HPA do evaluation está no **mínimo, 2 réplicas**, com CPU quase zero. O ScaledObject mostra `READY=True` e `ACTIVE=False` — significa que o KEDA está conectado na fila e autenticando via IRSA, mas **não há mensagem**. Por isso o analytics está com **zero pods**. Guarde essa imagem: zero."

### Passo 8.5 — Demo 1: HPA sob carga HTTP

**Integrante 4 opera. Abra 2 terminais lado a lado.**

Terminal A — observar:
```bash
kubectl get hpa -n apps -w
```

Terminal B — gerar carga:
```bash
./scripts/load-test-evaluation.sh http://$INGRESS 120s 150
```

> "Vamos jogar carga HTTP no evaluation. Olha o HPA reagindo no terminal da esquerda: conforme a CPU passa dos 70%, ele **cria novas réplicas** — 3, 4, 5... chegou ao **máximo de 8**."

```bash
kubectl get pods -n apps -w
```

> "Agora eu paro a carga. Depois de 60 segundos de métrica estável, o HPA começa a **reduzir** de volta ao mínimo de 2. Ele escala pra baixo devagar pra não oscilar."

### Passo 8.6 — Demo 2: KEDA com a fila SQS cheia

**Integrante 2 assume. Terminal A continua observando pods.**

Terminal B — encher a fila:
```bash
./scripts/send-sqs-batch.sh 1500
```

> "Agora eu encho a fila SQS com **1500 mensagens**. Lembra que o analytics estava em **zero**? Olha o KEDA trabalhando: ele lê a profundidade da fila e **começa a criar réplicas** — 1, 5, 10, até o máximo. Os pods sobem, entram em Running e começam a consumir a fila."

```bash
kubectl get scaledobject -n apps
kubectl get hpa -n apps
```

> "Aqui está o detalhe legal: o KEDA **cria um HPA por baixo** — veja o `keda-hpa-analytics-scaledobject`, lendo uma **métrica externa**: o tamanho da fila SQS. É o padrão do Kubernetes com uma fonte de métrica customizada."

### Passo 8.7 — Confirmar os eventos no DynamoDB

```bash
aws dynamodb scan --table-name ToggleMasterAnalytics --select COUNT --region us-east-1
```

> "E no Console **DynamoDB**, confirmamos os **milhares de itens** chegando: cada mensagem da fila foi consumida pelo analytics e gravada aqui. O ciclo fechou de ponta a ponta — **SQS → analytics → DynamoDB**."

### Passo 8.8 — De volta a zero

```bash
kubectl get pods -n apps -w
kubectl get scaledobject -n apps
```

> "Com a fila drenada, o KEDA reduz de volta a **zero réplicas**. Essa é a diferença fundamental entre os dois: o **HPA** ajusta a capacidade de algo que está **sempre no ar**; o **KEDA** **liga e desliga** conforme o evento. Um custa o tempo todo pelo mínimo; o outro pode custar **zero** quando não há trabalho."

**Tela:** 2 terminais (HPA/pods com `-w`) + script de carga + Console DynamoDB + manifests no VSCode.

---

# BLOCO 9 (16:45 - 18:30) — DIFERENCIAIS TÉCNICOS

**Integrante 1 fala, mostrando código:**

### 9.1 — IRSA (sem secrets hardcoded)

> "Em vez de colocar `AWS_ACCESS_KEY_ID` nos manifests, usamos IRSA. Cada ServiceAccount tem uma anotação `eks.amazonaws.com/role-arn` com a role IAM. O OIDC Provider do EKS assina os tokens e o pod assume a role automaticamente. O mesmo mecanismo é usado pelos pods (analytics) **e pelo próprio KEDA** para ler a fila SQS. Mais seguro e auditável."

### 9.2 — 3 Datastores diferentes (justificativa)

> "Usamos 3 tipos de banco propositalmente:
>
> - **RDS PostgreSQL** (×3) — dados transacionais relacionais (usuários, flags, regras)
> - **Redis ElastiCache** — cache de baixa latência no hot path do evaluation
> - **DynamoDB** — eventos de analytics, alta volumetria, escrita assíncrona

Cada um no seu caso de uso ideal."

### 9.3 — Estratégia de autoscaling

> "E duas formas de escalar, cada uma no lugar certo: **HPA** para o serviço síncrono, orientado a CPU; **KEDA** para o serviço assíncrono, orientado a evento, com scale-to-zero. Não é 'usar a ferramenta da moda' — é escolher a métrica certa pra cada tipo de carga."

### 9.4 — Infraestrutura como Código

> "Toda a infraestrutura é declarativa em Terraform. Nenhum clique no Console. O `destroy.sh` apaga tudo quando terminamos — a stack é efêmera, custo próximo de zero quando não estamos usando."

### 9.5 — Multi-stage builds

> "Todos os Dockerfiles são multi-stage: compila em uma imagem cheia, copia só o binário/venv para uma imagem slim. Imagens menores, mais rápidas de pullar, menor superfície de ataque."

**Tela:** Código dos manifests e Terraform.

---

# BLOCO 10 (18:30 - 20:00) — ENCERRAMENTO

**Todos participam:**

> "Resumindo o que entregamos:
>
> - 5 microsserviços (2 Go + 3 Python)
> - Docker Compose local funcional
> - Infra AWS completa via Terraform (VPC, RDS, Redis, SQS, DynamoDB, ECR, EKS, IRSA)
> - Deploy Kubernetes com Ingress público
> - IRSA para autenticação segura aos serviços AWS
> - 3 tipos de datastore com propósitos definidos
> - **Autoscaling: HPA por CPU no evaluation e KEDA por fila SQS no analytics, com scale-to-zero**

> O código está no GitHub: [LINK DO REPO]
> O relatório de entrega: [LINK]
> Obrigado!"

**Tela:** Slide final com links + nomes/RM/Discord.

---

# CHECKLIST DE PRÉ-GRAVAÇÃO (fazer ANTES de gravar)

**Ambiente local**
- [ ] `docker compose up` rodando localmente e E2E validado

**Infra AWS**
- [ ] `terraform apply` rodado na AWS (stack viva)
- [ ] 5 imagens `:latest` no ECR

**Kubernetes**
- [ ] `kubectl get pods -n apps` → pods Running+Ready (evaluation com **2 réplicas** via HPA; analytics em **0**)
- [ ] `kubectl get ingress` → Address preenchido
- [ ] `curl http://$INGRESS/auth/health` → ok

**Autoscaling (Sprint 3)**
- [ ] `kubectl top pods -n apps` funciona → **Metrics Server** instalado
- [ ] `kubectl get crd scaledobjects.keda.sh` existe → **KEDA** instalado
- [ ] `kubectl get hpa -n apps` → `evaluation-hpa` ativo (CPU visível, ex. `1%/70%`)
- [ ] `kubectl get scaledobject -n apps` → `READY=True`, `ACTIVE=False`
- [ ] **Fila SQS vazia** antes de gravar (pra demo do KEDA começar em 0)
- [ ] `kubectl get pods -n apps` → nenhum pod `Pending`
- [ ] (Opcional) `brew install hey` → output de carga mais bonito que o `ab`

**Gravação**
- [ ] Console AWS aberto nas abas: VPC, RDS, ElastiCache, SQS, DynamoDB, EKS, ECR
- [ ] VSCode aberto em `terraform/` e `kubernetes/`
- [ ] Diagrama `docs/arquitetura-aws.png` pronto para mostrar
- [ ] 2 terminais pré-abertos para o bloco de autoscaling
- [ ] Áudio testado (microfone funcionando)
- [ ] Resolução de tela 1920×1080
- [ ] Fechar notificações do sistema

---

# DICAS DE EDIÇÃO

1. **Cortar waits longos**: `terraform apply` (~30 min), `helm install`, `kubectl rollout status`. Acelerar 8x ou cortar.
2. **Manter narração contínua**: quem não está falando, prepara o próximo comando.
3. **Zoom em comandos importantes**: use zoom 125-150% nos terminais.
4. **Bloco de autoscaling**: deixe os terminais com `kubectl get hpa -w` e `kubectl get pods -w` visíveis; acelere a parte da carga e destaque o momento em que as réplicas mudam de número.
5. **Legendas**: adicionar timestamps e títulos dos blocos.
6. **Áudio**: normalizar para -16 LUFS.
