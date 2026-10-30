# Guia de Ambiente Local com Docker & Docker Compose

> **Foco desta página: resumir uso, funcionamento e o porquê de cada decisão tomada na etapa de conteinerização do ToggleMaster.
> Documenta Sprint 1, tarefas T1.1 (Dockerfiles), T1.2 (docker-compose) e ajustes de suporte local (LocalStack / DynamoDB Local).

---

## 1. Objetivo

Rodar **TODO o ToggleMaster localmente — 5 microsserviços + 4 bancos de dados locais + recursos AWS mockados **em um único comando, sem depender de conta AWS real.

- Provar que o código funciona ponta a ponta (criar chave → criar flag → criar regra → avaliar → evento → análise — tudo com recursos locais.
- Servir como base para a imagem Docker build → buildada no ECR e deploy EKS posteriormente.

---

## 2. O que existe hoje na pasta docs/

| Arquivo                                                                     | Propósito                                                              |
| --------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| [README.md](#)                                                              | Este arquivo — documentação de Docker e ambiente local (Sprint 1).     |
| [roteiro-video.md](./roteiro-video.md)                                      | **NOVO!** Roteiro completo do vídeo de entrega (20 min, 9 blocos com timestamps, comandos e checklist pré-gravação). |
| [arquitetura-aws.mmd](./arquitetura-aws.mmd)                                | Diagrama Mermaid da arquitetura AWS + fluxo de comunicação dos serviços (importável no draw.io). |
| [arquitetura-aws.png](./arquitetura-aws.png)                                | **NOVO!** Renderização PNG do diagrama acima (fundo branco).           |
| [arquitetura-aws.svg](./arquitetura-aws.svg)                                | **NOVO!** Renderização SVG do diagrama (vetorial, ideal para relatórios). |
| [arquitetura-comunicacao-servicos.md](./arquitetura-comunicacao-servicos.md) | Como os 5 microsserviços se comunicam (auth, flag, targeting, evaluation, analytics + SQS/Dynamo). |
| [infraestrutura-aws.md](./infraestrutura-aws.md)                            | Documentação de infraestrutura AWS por recurso (VPC, 3×RDS, Redis, EKS, ECR etc). |
| [glossario-kubernetes-devops.md](./glossario-kubernetes-devops.md)          | **NOVO!** Glossário Sprint 2 EKS/K8s — explica EKS, Ingress, ClusterIP, IRSA, KEDA e Kyverno (para todo o time, nível iniciante). |
| Referências:                                                               |                                                                         |
| - Plano de sprints do projeto em [../PLANO-ENTREGA-SPRINT.md](../PLANO-ENTREGA-SPRINT.md)
| - Cada serviço tem seu README.md próprio:
|   - [auth-service](../auth-service/README.md)
|   - [flag-service](../flag-service/README.md)
|   - [targeting-service](../targeting-service/README.md)
|   - [evaluation-service](../evaluation-service/README.md)
|   - [analytics-service](../analytics-service/README.md)

---

## 3. Estrutura entregue nesta etapa

```
fiap-toggle-master/
├── docker-compose.yml          # 11 serviços compose
├── .env.example          # modelo de variáveis
├── auth-service/Dockerfile      # Go (auth-service
├── flag-service/Dockerfile        # Python
├── targeting-service/Dockerfile   # Python
├── evaluation-service/Dockerfile    # Go
├── analytics-service/Dockerfile     # Python
└── docs/
    └── README.md
```

---

## 4. Como usar (Rápido

```bash
cd fiap-toggle-master

# 1) Copiar modelo de variáveis
cp .env.example .env

# 2) Build + subir tudo
docker compose up --build -d

# 3) Verificar containers (10 contêineres rodando + setup exited(0))
docker compose ps

# 4) Criar chave de serviço do evaluation
curl -X POST http://localhost:8001/admin/keys \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer SUA_MASTER_KEY" \
  -d '{"name": "evaluation-service-key"}'

# 5) Copiar "key": "tm_key_..." retornado, colar em .env
SERVICE_API_KEY=tm_key_xxx_...

# 6) Recriar evaluation:
docker compose up -d evaluation-service

# 7) Bateria E2E de teste
# 7.1) Criar flag (use a mesma key)
API_KEY=tm_key_xxx_...
curl -X POST http://localhost:8002/flags \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"name": "enable-new-dashboard", "description": "novo dashboard", "is_enabled": true}'

# 7.2) Criar regra targeting (50% dos usuários)
curl -X POST http://localhost:8003/rules \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"flag_name": "enable-new-dashboard", "is_enabled": true, "rules": {"type": "PERCENTAGE", "value": 50}}'

# 7.3) Avaliar flag (várias vezes com user_ids difs DIFERENTES)
curl "http://localhost:8004/evaluate?user_id=user-1&flag_name=enable-new-dashboard"
curl "http://localhost:8004/evaluate?user_id=user-2&flag_name=enable-new-dashboard"
curl "http://localhost:8004/evaluate?user_id=user-3&flag_name=enable-new-dashboard"

# 7.4) Ver eventos chegando no analytics → DynamoDB Local
docker compose logs -f analytics-service

# 8) Parar tudo (preservar dados)
docker compose stop

# 9) Parar e apagar volumes (limpar volumes)
docker compose down -v
```

---

## 4.1. Guia E2E — Todos os endpoints

Esta seção documenta **todos os endpoints** a serem testados nos dois ambientes: **local** (Docker Compose) e **nuvem** (EKS via Ingress público).

### 4.1.1. Pré-requisitos — Obter a SERVICE_API_KEY

Antes de testar os endpoints protegidos, gere uma chave de serviço no `auth-service`:

**Ambiente local:**
```bash
curl -X POST http://localhost:8001/admin/keys \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer SUA_MASTER_KEY" \
  -d '{"name": "e2e-test"}'
```

**Ambiente AWS (via Ingress):**
```bash
INGRESS=<DNS_DO_ELB>
MASTER_KEY=$(grep -E '^MASTER_KEY=' .env | cut -d'=' -f2- | tr -d '"' | tr -d "'")

curl -X POST http://$INGRESS/auth/admin/keys \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $MASTER_KEY" \
  -d '{"name": "e2e-test"}'
```

Guarde o valor retornado no campo `"key"` (formato `tm_key_...`). Daqui em diante, usaremos `KEY=<valor_da_key>`.

---

### 4.1.2. Lista de todos os endpoints

| # | Método | Endpoint (local) | Endpoint (AWS/Ingress) | Autenticação | Serviço alvo |
|---|--------|------------------|------------------------|--------------|--------------|
| 1 | GET  | `http://localhost:8001/health` | `http://$INGRESS/auth/health` | Nenhuma | auth-service |
| 2 | POST | `http://localhost:8001/admin/keys` | `http://$INGRESS/auth/admin/keys` | Bearer MASTER_KEY | auth-service |
| 3 | GET  | `http://localhost:8001/validate?key=...` | `http://$INGRESS/auth/validate?key=...` | Query param `key` | auth-service |
| 4 | GET  | `http://localhost:8002/health` | `http://$INGRESS/flags/health` | Nenhuma | flag-service |
| 5 | POST | `http://localhost:8002/flags` | `http://$INGRESS/flags` | Bearer SERVICE_API_KEY | flag-service |
| 6 | GET  | `http://localhost:8002/flags` | `http://$INGRESS/flags` | Bearer SERVICE_API_KEY | flag-service |
| 7 | GET  | `http://localhost:8002/flags/<name>` | `http://$INGRESS/flags/<name>` | Bearer SERVICE_API_KEY | flag-service |
| 8 | PUT  | `http://localhost:8002/flags/<name>` | `http://$INGRESS/flags/<name>` | Bearer SERVICE_API_KEY | flag-service |
| 9 | DELETE | `http://localhost:8002/flags/<name>` | `http://$INGRESS/flags/<name>` | Bearer SERVICE_API_KEY | flag-service |
| 10 | GET | `http://localhost:8003/health` | `http://$INGRESS/rules/health` | Nenhuma | targeting-service |
| 11 | POST | `http://localhost:8003/rules` | `http://$INGRESS/rules` | Bearer SERVICE_API_KEY | targeting-service |
| 12 | GET  | `http://localhost:8003/rules/<flag_name>` | `http://$INGRESS/rules/<flag_name>` | Bearer SERVICE_API_KEY | targeting-service |
| 13 | PUT  | `http://localhost:8003/rules/<flag_name>` | `http://$INGRESS/rules/<flag_name>` | Bearer SERVICE_API_KEY | targeting-service |
| 14 | DELETE | `http://localhost:8003/rules/<flag_name>` | `http://$INGRESS/rules/<flag_name>` | Bearer SERVICE_API_KEY | targeting-service |
| 15 | GET | `http://localhost:8004/health` | `http://$INGRESS/evaluate/health` | Nenhuma | evaluation-service |
| 16 | GET | `http://localhost:8004/evaluate?flag_name=...&user_id=...` | `http://$INGRESS/evaluate?flag_name=...&user_id=...` | Bearer SERVICE_API_KEY | evaluation-service |
| — | GET | `http://localhost:8005/health` | (não exposto no Ingress) | Nenhuma | analytics-service (worker interno) |

> **Nota:** O `analytics-service` (porta 8005) é um **worker interno** que consome a fila SQS e grava no DynamoDB. Ele **não é exposto publicamente** no Ingress. Seu `/health` pode ser testado via `port-forward` no EKS ou diretamente em `localhost:8005` no Docker Compose.

---

### 4.1.3. Fluxo E2E completo (AWS / Ingress)

Substitua `<DNS_DO_ELB>` pelo endereço do seu Ingress (`kubectl get ingress -n apps`) e `<SUA_KEY>` pela SERVICE_API_KEY gerada.

```bash
INGRESS=<DNS_DO_ELB>
KEY=<SUA_KEY>

# ---------------------------------------------------------------
# PASSO 1 — Health checks de TODOS os serviços de borda
# Todos devem retornar {"status":"ok"}
# ---------------------------------------------------------------
echo "auth:      $(curl -s http://$INGRESS/auth/health)"
echo "flags:     $(curl -s http://$INGRESS/flags/health)"
echo "targeting: $(curl -s http://$INGRESS/rules/health)"
echo "evaluate:  $(curl -s http://$INGRESS/evaluate/health)"

# ---------------------------------------------------------------
# PASSO 2 — Criar uma feature flag (POST /flags)
# ---------------------------------------------------------------
curl -s -X POST http://$INGRESS/flags \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $KEY" \
  -d '{"name":"feature-x","description":"Teste E2E","is_enabled":true}'

# Retorno esperado: {"id":1,"name":"feature-x","description":"Teste E2E","is_enabled":true,...}

# ---------------------------------------------------------------
# PASSO 3 — Listar todas as flags (GET /flags)
# ---------------------------------------------------------------
curl -s http://$INGRESS/flags \
  -H "Authorization: Bearer $KEY"

# Retorno esperado: [{"id":1,"name":"feature-x",...}]

# ---------------------------------------------------------------
# PASSO 4 — Buscar uma flag por nome (GET /flags/<name>)
# ---------------------------------------------------------------
curl -s http://$INGRESS/flags/feature-x \
  -H "Authorization: Bearer $KEY"

# ---------------------------------------------------------------
# PASSO 5 — Criar regra de segmentação (POST /rules)
# Neste exemplo: 100% dos usuários recebem a flag
# ---------------------------------------------------------------
curl -s -X POST http://$INGRESS/rules \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $KEY" \
  -d '{"flag_name":"feature-x","is_enabled":true,"rules":{"type":"PERCENTAGE","value":100}}'

# Retorno esperado: {"id":1,"flag_name":"feature-x","is_enabled":true,"rules":{"type":"PERCENTAGE","value":100},...}

# ---------------------------------------------------------------
# PASSO 6 — Buscar regra por flag (GET /rules/<flag_name>)
# ---------------------------------------------------------------
curl -s http://$INGRESS/rules/feature-x \
  -H "Authorization: Bearer $KEY"

# ---------------------------------------------------------------
# PASSO 7 — Avaliar a flag (GET /evaluate?flag_name=...&user_id=...)
# Este é o endpoint principal: consulta flag + regra, aplica a lógica,
# retorna true/false e envia um evento assíncrono para a fila SQS.
# ---------------------------------------------------------------
curl -s "http://$INGRESS/evaluate?flag_name=feature-x&user_id=user123" \
  -H "Authorization: Bearer $KEY"

# Retorno esperado: {"flag_name":"feature-x","user_id":"user123","result":true}

# ---------------------------------------------------------------
# PASSO 8 — Atualizar a regra para 0% (PUT /rules/<flag_name>)
# Agora nenhum usuário deve receber a flag
# ---------------------------------------------------------------
curl -s -X PUT http://$INGRESS/rules/feature-x \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $KEY" \
  -d '{"is_enabled":true,"rules":{"type":"PERCENTAGE","value":0}}'

# Avaliar novamente — agora result deve ser false
curl -s "http://$INGRESS/evaluate?flag_name=feature-x&user_id=user999" \
  -H "Authorization: Bearer $KEY"

# ---------------------------------------------------------------
# PASSO 9 — Atualizar a flag (PUT /flags/<name>)
# Desativa a flag globalmente (kill switch)
# ---------------------------------------------------------------
curl -s -X PUT http://$INGRESS/flags/feature-x \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $KEY" \
  -d '{"description":"Atualizada","is_enabled":false}'

# ---------------------------------------------------------------
# PASSO 10 — Verificar eventos no DynamoDB (analytics-service)
# O evaluation-service envia eventos para a fila SQS;
# o analytics-service consome e grava no DynamoDB.
# ---------------------------------------------------------------
sleep 5  # espera o processamento assíncrono

# AWS:
AWS_PROFILE=toggl aws dynamodb scan \
  --table-name ToggleMasterAnalytics \
  --region us-east-1 \
  --query "Items[?flag_name.S=='feature-x']" \
  --output table

# Local (Docker Compose):
aws --endpoint-url=http://localhost:8000 dynamodb scan \
  --table-name ToggleMasterAnalytics \
  --region us-east-1 \
  --query "Items[?flag_name.S=='feature-x']" \
  --output table

# ---------------------------------------------------------------
# PASSO 11 — Limpar (DELETE /rules e /flags)
# ---------------------------------------------------------------
curl -s -X DELETE http://$INGRESS/rules/feature-x \
  -H "Authorization: Bearer $KEY"

curl -s -X DELETE http://$INGRESS/flags/feature-x \
  -H "Authorization: Bearer $KEY"
```

---

### 4.1.4. Fluxo E2E — Ambiente local (Docker Compose)

O mesmo fluxo acima, mas com as portas locais. Substitua `http://$INGRESS/<path>` por `http://localhost:<porta>/<path>`:

| Serviço | Porta local | Exemplo |
|---|---|---|
| auth-service | 8001 | `http://localhost:8001/health` |
| flag-service | 8002 | `http://localhost:8002/flags` |
| targeting-service | 8003 | `http://localhost:8003/rules` |
| evaluation-service | 8004 | `http://localhost:8004/evaluate?flag_name=x&user_id=1` |
| analytics-service | 8005 | `http://localhost:8005/health` |

**Exemplo rápido local:**
```bash
KEY=tm_key_xxx

# Health
curl -s http://localhost:8001/health
curl -s http://localhost:8002/health
curl -s http://localhost:8003/health
curl -s http://localhost:8004/health

# Criar flag
curl -s -X POST http://localhost:8002/flags \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $KEY" \
  -d '{"name":"feature-x","description":"Teste","is_enabled":true}'

# Criar regra 100%
curl -s -X POST http://localhost:8003/rules \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $KEY" \
  -d '{"flag_name":"feature-x","is_enabled":true,"rules":{"type":"PERCENTAGE","value":100}}'

# Evaluate
curl -s "http://localhost:8004/evaluate?flag_name=feature-x&user_id=user1" \
  -H "Authorization: Bearer $KEY"

# Ver eventos no analytics (DynamoDB Local)
docker compose logs -f analytics-service
```

---

### 4.1.5. Tipos de regras de segmentação suportadas

O `targeting-service` suporta 3 tipos de regra no campo `rules`:

**1. PERCENTAGE** — porcentagem de usuários que recebem a flag:
```json
{"type":"PERCENTAGE","value":50}
```

**2. USER_LIST** — lista específica de user_ids:
```json
{"type":"USER_LIST","values":["user1","user2","user3"]}
```

**3. SEM REGRA** — se não houver regra, o resultado depende apenas do `is_enabled` da flag.

---

## 5. Funcionamento do compose: arquitetura de 11 serviços

### 5.1 Bancos de dados (6 containers persistidos)

```
postgres-auth:5432 (mapeada na porta host 5433
  └─ Tabela api_keys → iniciada via init.sql (auth-service/db/init.sql)

postgres-flag:5432 (host 5434)
  └─ Tabela flags → trigger updated_at iniciada via init.sql

postgres-targeting:5432 (host 5435)
  └─ Tabela targeting_rules + trigger iniciada via init.sql

redis:6379 (host 6379)
  └─ evaluation hot path cache (TTL curto)

dynamodb-local:8000 (host 8000)
  └─ Tabela ToggleMasterAnalytics
  └─ volume montado para dados salvam em /dados/dynamodb-data.

localstack-sqs:4566 (host 4566)
  └─ Só serviço SQS habilitado → fila SQS "toggle-master-events"
```

### 5.2 Container de Setup inicial (container `setup-aws-local`)

- **Imagem**:  Roda 1 vez e finaliza com exit code 0.
- **Missão**: Criar recursos locais:
  1. `aws --endpoint-url=localstack-sqs sqs create-queue toggle-master-events
  2. `aws --endpoint-url=dynamodb-local dynamodb create-table ToggleMasterAnalytics`
- **Por quê?** LocalStack e DynamoDB Local iniciam vazios. Sem a fila e tabela, o evaluation envia para URL não-existente e analytics quebra com SQS/Dynamo
- É **idempotente**: roda novamente ele pula criação caso recursos já existam** — usa `||` echo).
- **`condition: service_completed_successfully garante que apps SÓ DEPOIS que a fila/tabela existam de boa-fé** garante que evaluation-service e analytics-service não iniciam o startados

### 5.3 Aplicações (5 containers)

| Serviço           | Image  | Porta | Entra**Comando entrypoint                                  | Dependencies garante startup                             |  |
| ------------------ | ------ | ----- | ---------------------------------------------------------- | -------------------------------------------------------- | - |
| auth-service       | Go     | 8001  | ./auth-service                                             | postgres-auth healthy                                    |  |
| flag-service       | Python | 8002  | gunicorn --bind 0.0.0.0:8002 workers 2 --threads 4 app:app | postgres-flag healthy + auth started                     |  |
| targeting-service  | Python | 8003  | gunicorn idem acima                                        | postgres-targeting healthy + auth started                |  |
| evaluation-service | Go     | 8004  | ./evaluation-service                                       | redis healthy + setup completed + flag/targeting started |  |
| analytics-service  | Python | 8005  | gunicorn idem acima                                        | setup completed + evaluation started                     |  |

---

## 6. Pensamento e decisões de arquitetura & design

### 🔹 Por que **Multi-stage builds em TODOS Dockerfiles?

---

**Motivo**: a imagem final é enxuta, mais rápida e com reduz superficie de ataque.

**Serviços **Go**:

- `Stage 1 (builder: (multi-stage golang:1.21-alpine) → compila binário `CGO_ENABLED=0 + ldflags "-s -w" strip
- Stage 2 (runtime alpine3.19) **só copia o binário (~15MB. NÃO TEM compilador, NÃO TEM go.mod/sum

Serviços **Python**

- Stage 1 builder (python3.11-bookworm completo (gcc/libpq-dev/build-essential) → instala dependências de build: **apenas 1 vez no venv /opt/venv
- Stage 2: python3.11-slim-bookworm → copia só o venv populado → apenas runtime libpq5 (somente libpq runtime, sem headers)

**Bom prática padrão sem multi-stage reduz em todos os 5

### 🔹 Por que **bash e não scratch ou distroless?

Porque o requisito do time**: **bash disponível para `docker exec -it container bash

- scratch/ distroless não tem shell** shell
- Então: Go runtime usa **:

  - alpine3.19) adiciona pacote
    -Python slim já tem bash por padrão
- Além de bash, **também**curl** para healthcheck em Go e **em Python healthcheck nativo urllib sem instalar curl extra.

### 🔹 Usuário não-root (appuser:appgroup

---

Sempre rodar como usuário não privilegiado. Boa prática de segurança e para deploy e Kubernetes SecurityContext.runAsNonRoot.

### 🔹 Por que **3 instâncias Postgres separadas e não uma com 3 bancos?

---

Porque na **em produção** são **RDS independentes. O compose replica fielmente a topologia final. Cada serviço tem seu banco próprio banco de falha de propósito desacoplamento.

- Em production: 3× RDS
- localmente 3 containers postgres independentes auth não é um erro de custo alto
- Emular é muito facilidade de deploy, container, de forma simples de manter separado se precisar

### 🔹 Por que LocalStack + DynamoDB Local (2 containers) ao invés de 1 LocalStack completo

---

O PDF do desafio é **DynamoDB Local é o mais leve e estável para DynamoDB. Já LocalStack usa o time queria manter um SQS é muito menor

### 🔹 Por que `AWS_ENDPOINT_URL_* custom envs?

---

Problemática original**: os SDKs (boto3 Python e AWS SDK Go) apontam para AWS real por default. Para apontar pro local precisam **endpoint customizados

- Então inventamos a convenção de variáveis de ambiente:
  - `AWS_ENDPOINT_URL_SQS`
  - `AWS_ENDPOINT_URL_DYNAMODB`
- Ambos códigos lêem essas envs e injetam o endpoint no clientse não definidas, não configuram automaticamente para AWS real comportamento ideal dual:
  - ✅
  - Em produção não definir essas variáveis
  - SDKs usam DNS real automaticamente

### 🔹 `depends_on` com **`healthcheck + condition: service_healthy vs service_completed_successfully

---

- Para bancos de DADOS`: **mesmo se o container está rodando (started) o postgres ainda não está pronto para aceitar conexões, fica segundos minutos. Por isso **healthcheck + condition: service_healthy.
- Para setup**: rodou exit code 0,**setup garante apps** depois que terminou não continua rodando completed successfully

### 🔹 Volumes persistentes (docker não perder dados ao restartar compose.

- `auth-pgdata | flag-pgdata | targeting-pgdata | redis-data | dynamodb-data | localstack-data
- Limpar tudo: `docker compose down -v`
- Manter dados: `docker compose down` (sem -v)

### 🔹 Network bridge dedicada togglemaster-net

---

Isola os containers de redes padrão do host. DNS interno do Docker resolve nomes: `postgres-auth` é DNS interno, não precisa usar localhost. Apps conectam por nome de serviço.

---

## 7. Troubleshooting common

| Sintoma                                                                                                                                               | Causa comum                                                                                                                                                                       | Como ajustar?                             |
| ----------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------- |
| `Error do serviço `SERVICE_API_KEY auth service com chave de serviço evaluation não ainda não criou SERVICE_API_KEY no .env após o compose up. | Ver passo 4 e 5 da seção "Como usar". Atualizar .env + docker compose up -d evaluation-service.                                                                                 |                                           |
| `Erro não reconhecida, fila SQS " não-existe                                                                                                        | setup-aws-local não rodou ainda ou crashou                                                                                                                                       | docker compose logs setup-aws-local.      |
| `analytics` app.py erro de permissão / tabela `erro NoCredentialsError                                                                             | Local com credenciais fake: AWS_ACCESS_KEY_ID e AWS_SECRET_ACCESS_KEY não importa fake mas tem que bater exatamente o aws_access_key_id fake no compose todos usam fakeLocalKey. | Verificar AWS_* não batem.               |
| `redis: ping falha no evaluation                                                                                                                      | redis ainda subiu mais devagar, restart do evaluation                                                                                                                             | docker compose restart evaluation-service |
| Postgres`role não permissão `ERROR:  ... already exists`                                                                                          | Rodou init.sql 2x, data volume não está vazio                                                                                                                                   | docker compose down -v                    |

---

## 8. Referências internas → próximos passos

- Plano de entregas por sprint → [PLANO-ENTREGA-SPRINT.md](../PLANO-ENTREGA-SPRINT.md)
- Próximos passos do time:
  1) Terraform modules:  `terraform/`
  2) Build imagens → push ECR
  3) Kubernetes manifests
  4) Helm KEDA Ingress
