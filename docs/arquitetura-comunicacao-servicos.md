# Arquitetura & Comunicação entre Microsserviços

> Documento derivado da análise dos 5 README.md + código fonte original do ToggleMaster.

---

## 1. Visão Geral

O ToggleMaster é um sistema de Feature Flags distribuídas, reescrito do MVP monolítico (Fase 1) para microsserviços (Fase 2).

| Serviço | Linguagem | Porta | Banco de Dados | Papel |
|---|---|---|---|---|
| auth-service | Go | 8001 | PostgreSQL | Central de **chaves de API + valida identidade de chamadas API protegidas |
| flag-service | Python/Flask | 8002 | PostgreSQL | CRUD de **definições das feature flags (nome, descrição, is_enabled (kill switch global) |
| targeting-service | Python/Flask | 8003 | PostgreSQL | Regras de segmentação / targeting (50% usuários, país X etc. |
| evaluation-service | Go | 8004 | Redis (cache TTL curto) | Hot path: avalia flag final true/false + publica eventos na fila |
| analytics-service | Python/Flask | 8005 | AWS DynamoDB | Worker: consome eventos de fila → ingestão DynamoDB p/ métricas |

---

## 2. Diagrama de comunicação

```
Cliente / Admin (App/Web)
        │
        │ ┌───────────────────────────────────────────────────────────────┐
        │ │ Ingress / ALB / Nginx                                      │
        │ │ Path routing: /auth* | /flags* | /rules* | /evaluate*
        └─┤
          │
          │ ┌─ auth-service (8001):
          │ │ ├── /validate (valida Bearer chave API — 200/401)
          │ │ └── POST /admin/keys (cria nova chave, requer MASTER_KEY
          │
          ├─► flag-service (8002) → antes de qualquer request protegida ────► GET /validate auth-service
          │    CRUD /flags [POST GET GET/{name} PUT/{name} DELETE/{name}
          │
          ├─► targeting-service (8003) → antes de qualquer request protegida ──► GET /validate auth-service
          │    CRUD /rules + GET /rules/{flag_name}
          │
          │ evaluation-service (8004) ← cliente final: GET /evaluate?user_id=U&flag_name=F
          │         │
          │         ├──► Redis ──► HIT → retorna rápido
          │         │     (MISS)
          │         │
          │         ├──► HTTP GET /flags/{flag_name} flag-service:8002 (Bearer token)
          │         │
          │         ├──► HTTP GET /rules/{flag_name} targeting-service:8003 (Bearer token)
          │         │
          │         ▼
          │     Executa lógica de avaliação (hash determinístico do user_id vs percentage)
          │         │
          │         ├──► true / false → retorna HTTP Response síncrona ao cliente (hot path)
          │         │
          │         └──► (assíncrono, fire-and-forget) ──────────►
          │
          │                                                        SQS Queue Standard
          │                                                           │
          │                                                           ▼ polling long 20s
          │
          │                                                  analytics-service (8005)
          │                                                         │ boto3 receive_message
          │                                                         │ 10 msgs em paralelo
          │                                                         │ parse json
          │                                                         │ dynamodb put_item ToggleMasterAnalytics
          │                                                         │ delete_message
          │                                                         ▼
          │                                                  AWS DynamoDB ToggleMasterAnalytics
```

---

## 3. Pontos chave de design do sistema

### 3.1 Autenticação centralizada (auth-service como validação em cada request protegida
- **Sempre HTTP síncrono GET `/validate`
- Flag-service e targeting-service chamam auth-service no require_auth em **toda requisição que não for /health
- Se o auth-service cai → Gateway 503/504 nos serviços de borda
- **Bearer token com MASTER_KEY Bearer tm_key_** criada no 401

### 3.2 Evaluation como Hot Path / cache Redis
- **TTL curto no Redis reduz latência de requests para mesma flag/regra repetida vezes em request
- Em cache MISS → vai à flag + targeting
- Cache HIT → resposta em ms

### 3.3 Comunicação assíncrona evaluation → analytics → DynamoDB via SQS
- **Evaluation não espera pelo DynamoDB: SQS garante ingestão e separa hot path de ingestão
- **Queue Standard SQS Standard: mensagens podem chegar mais de 1 vez (at-least-once delivery garantia, mas perfeitamente OK p/ analytics já que event_id uuid).
- Analytics é um loop SQS 20s polling recebe 10 delete

---

## 4. Referências ao código fonte

| Item | Link
|---|---|
| Middleware `require_auth` flag-service | [flag-service/app.py#L39-L65](../flag-service/app.py#L39-L65) |
| Middleware `require_auth` targeting-service | [targeting-service/app.py#L39-L63](../targeting-service/app.py#L39-L63) |
| Avaliação / evaluate redis cache miss / hit | [evaluation-service/handlers.go](../evaluation-service/handlers.go) |
| SQS send evento evaluation | [evaluation-service/sqs.go](../evaluation-service/sqs.go) |
| SQS worker loop analytics receive_message (batch 10, polling 20s, parse, Dynamo put | [analytics-service/app.py#L44-L116](../analytics-service/app.py#L44-L116) |

---

## 5. Explicação dos 3 diferentes datastores (RDS × Redis × DynamoDB

| Datastore | Uso no sistema | Propósito arquitetônico |
|---|---|---|
| **3× RDS PostgreSQL | auth / flags / targeting regras | Dados transacionais ACID: consistentes, relacionais. |
| **ElastiCache Redis | evaluation cache | Baixa latência microseconds. Salva TTL curto cache flag+regras. Evita bater RDS todo request. Hot path |
| **DynamoDB NoSQL | analytics eventos de milhões de avaliações/day | Alta ingestão escrita ilimitada Write scaling. Sem necessidade ACID para eventos. Pay por request |
