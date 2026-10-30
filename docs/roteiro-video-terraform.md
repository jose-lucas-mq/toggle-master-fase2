# Roteiro Individual — Terraform + AWS + KEDA + E2E + Scripts

> **Para:** Integrante responsável pela Infraestrutura
> **Escopo:** Terraform/AWS, os 7 scripts do projeto, E2E geral e demo do KEDA
> **Duração alvo: 9:00 (limite rígido)**
> **Estilo:** você fala e opera a tela o tempo todo. Narração escrita pra leitura direta.

---

## Cronômetro

| Min       | Bloco                                              | Tela                                  |
| --------- | -------------------------------------------------- | ------------------------------------- |
| 0:00-0:20 | Abertura                                           | Slide/diagrama                        |
| 0:20-1:50 | Terraform + AWS (o que sobe + código + apply)     | Diagrama + VSCode + terminal          |
| 1:50-2:35 | Console AWS (evidência)                           | Console (8 abas pré-abertas)         |
| 2:35-4:05 | **Os 7 scripts do projeto**                  | VSCode: os`.sh`                     |
| 4:05-6:05 | **E2E geral** (funcionalidade ponta a ponta) | Terminal + Console (RDS/SQS/DynamoDB) |
| 6:05-8:30 | **KEDA** (autoscaling por fila SQS)          | 2 terminais + Console SQS             |
| 8:30-9:00 | Encerramento +`destroy.sh`                       | Terminal                              |

> **Aviso:** 9 minutos para esse escopo é apertado. Se estourar, corte primeiro o **Console AWS** (1:50-2:35) e depois a explicação dos scripts de carga.
> **Aviso 2:** o E2E e o KEDA já estavam nos blocos de outro integrante. **Combinem com o time** para não duplicar.

---

# BLOCO 1 (0:00 - 0:20) — ABERTURA

> "Oi, sou o [SEU NOME], do time [NOME]. Minha parte cobre **a infraestrutura AWS com Terraform**, os **scripts que automatizam o projeto**, o **E2E completo** e o **autoscaling com KEDA**.
>
> Ponto importante: **nada foi criado clicando no Console**. Tudo é código."

---

# BLOCO 2 (0:20 - 1:50) — TERRAFORM + AWS

### 2.1 — O que sobe (20s) — abra `docs/arquitetura-aws.png`

> "Provisionamos: **VPC** com sub-redes públicas e privadas em 3 AZs; **EKS** com 2 nós; **3 RDS PostgreSQL** (um por serviço); **Redis ElastiCache**; **SQS** com DLQ; **DynamoDB**; **5 repositórios ECR**; e **IAM com IRSA**.
>
> O fluxo quente é: evaluation consulta Redis e o banco, responde, e joga o evento no SQS; o analytics consome e grava no DynamoDB."

### 2.2 — Código: 3 pontos-chave (60s)

**Abra [backend.tf](file:///Users/joze_lucas/Desktop/codes/fiap-toggle-master/terraform/backend.tf):**

> "O estado fica no **S3**, não na minha máquina. E o acesso assume uma **role IAM** — meu usuário base não cria nada, ele só pode assumir a role de deploy. **Menor privilégio**."

**Abra [main.tf](file:///Users/joze_lucas/Desktop/codes/fiap-toggle-master/terraform/main.tf):**

> "Três detalhes que valem a pena:
>
> **Um** — a senha do RDS é gerada com `random_password`, mas com um conjunto de caracteres especiais restrito. O RDS proíbe barra, arroba e espaço; e eu removi `%` e chaves porque **quebravam o parser de URL**. Foi um bug real.
>
> **Dois** — os 3 RDS ficam em **sub-redes privadas**. Banco sem acesso à internet.
>
> **Três** — o módulo `iam_irsa` depende do **OIDC Provider do EKS**. É essa cadeia que permite ao pod assumir uma role IAM **sem nenhuma credencial dentro dele**."

**Abra [outputs.tf](file:///Users/joze_lucas/Desktop/codes/fiap-toggle-master/terraform/outputs.tf):**

> "Os outputs são a ponte com o resto: endpoints, URLs do ECR, Redis, ARNs das roles. Ninguém digita endpoint na mão."

### 2.3 — Apply (30s)

```bash
cd terraform
terraform plan          # mostra o que vai criar: 66 recursos
```

> "(Cortar o `apply` — leva ~25 min. Volte já com ele concluído.)"

```bash
terraform output        # senhas mascaradas (marcadas como sensitive)
```

---

# BLOCO 3 (1:50 - 2:35) — CONSOLE AWS (evidência)

**8 abas já carregadas. ~5s cada, narrando rápido:**

> "Confirmando na AWS: **VPC** com as 6 sub-redes · **EKS** `toggle-master-eks` 1.31 com 2 nós · **3 RDS** todos *not publicly accessible* · **ElastiCache Redis** · **SQS** + DLQ · **DynamoDB** com GSI · **5 repositórios ECR** com imagens · **3 roles IAM** do IRSA."

---

# BLOCO 4 (2:35 - 4:05) — OS 7 SCRIPTS DO PROJETO

**Abra a pasta raiz e mostre os `.sh`. Fale em 3 grupos.**

### 4.1 — Os 3 scripts de Terraform (30s)

**Abra [terraform/apply.sh](file:///Users/joze_lucas/Desktop/codes/fiap-toggle-master/terraform/apply.sh):**

> "O `apply.sh` roda `fmt`, `init`, `plan` e só então `apply` — com **confirmação explícita** e um alerta de custo, pra ninguém deixar a stack ligada por engano."

**Abra [terraform/push-all-images-to-ecr.sh](file:///Users/joze_lucas/Desktop/codes/fiap-toggle-master/terraform/push-all-images-to-ecr.sh):**

> "O `push-all-images-to-ecr.sh` pega as 5 URLs do ECR via `terraform output`, faz login, builda as imagens com **`--platform linux/amd64`** — porque os nós do EKS são x86 e minha máquina é ARM — e faz push das 5 de uma vez."

**Abra [terraform/destroy.sh](file:///Users/joze_lucas/Desktop/codes/fiap-toggle-master/terraform/destroy.sh):**

> "E o `destroy.sh`, que eu vou mostrar funcionando no final. Ele existe porque o **Load Balancer do Ingress é criado pelo Kubernetes, não pelo Terraform** — então ele precisa ser removido antes, senão dá `DependencyViolation` nas sub-redes. O script faz isso, depois roda o destroy."

### 4.2 — Os 2 scripts de Kubernetes (35s)

**Abra [kubernetes/apply.sh](file:///Users/joze_lucas/Desktop/codes/fiap-toggle-master/kubernetes/apply.sh):**

> "O `apply.sh` do Kubernetes é o mais interessante: ele **gera os manifests reais** substituindo os placeholders pelos valores do `terraform output`, e faz o deploy numa ordem específica —
>
> **primeiro sobe o auth**, faz *port-forward* nele, **chama o endpoint que gera a SERVICE_API_KEY**, atualiza o Secret, e **só então** sobe os outros 4 serviços. Porque os outros dependem dessa chave pra autenticar.
>
> No fim ele ainda aplica o Ingress e o HPA/ScaledObject."

**Abra [kubernetes/install-keda.sh](file:///Users/joze_lucas/Desktop/codes/fiap-toggle-master/kubernetes/install-keda.sh):**

> "E o `install-keda.sh` instala o **Metrics Server** (que o HPA usa pra medir CPU) e o **KEDA** — reaproveitando a ServiceAccount `keda-operator` **já anotada com a role IRSA**. Ou seja, o KEDA acessa a fila SQS sem nenhuma credencial hardcoded."

### 4.3 — Os 2 scripts de teste/carga (25s)

**Abra [scripts/load-test-evaluation.sh](file:///Users/joze_lucas/Desktop/codes/fiap-toggle-master/scripts/load-test-evaluation.sh) e [scripts/send-sqs-batch.sh](file:///Users/joze_lucas/Desktop/codes/fiap-toggle-master/scripts/send-sqs-batch.sh):**

> "Por último, os dois de teste: o `load-test-evaluation.sh` gera **carga HTTP no evaluate** — e como cada evaluate publica um evento no SQS, ele testa o HPA **e** o KEDA. E o `send-sqs-batch.sh` **enche a fila SQS em lotes de 10** — é o que eu vou usar daqui a pouco pra mostrar o KEDA."

---

# BLOCO 5 (4:05 - 6:05) — E2E GERAL (a funcionalidade ponta a ponta)

### 5.1 — Ponto de entrada + health (15s)

```bash
cd kubernetes
INGRESS=$(kubectl get ingress togglemaster-api-ingress -n apps -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
for p in auth flags rules evaluate; do echo "$p -> $(curl -s http://$INGRESS/$p/health)"; done
```

> "Tudo entra por **um único Load Balancer**. Os 4 serviços de borda respondem `ok`. O analytics não aparece porque é **worker interno** — ele não recebe HTTP, só consome fila."

### 5.2 — Autenticação + criação da flag (20s)

```bash
MASTER_KEY=$(grep -E '^MASTER_KEY=' ../.env | cut -d'=' -f2- | tr -d '"'"'"'')
KEY=$(curl -s -X POST http://$INGRESS/auth/admin/keys \
  -H "Content-Type: application/json" -H "Authorization: Bearer $MASTER_KEY" \
  -d '{"name":"demo"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["key"])')

curl -s -X POST http://$INGRESS/flags \
  -H "Content-Type: application/json" -H "Authorization: Bearer $KEY" \
  -d '{"name":"checkout-v2","description":"Checkout novo","is_enabled":true}'
```

> "O auth emite uma **chave de serviço** e guarda no **RDS de autenticação**. Com ela eu crio a flag `checkout-v2`."

### 5.3 — Provar que persistiu no RDS (20s) ⭐

```bash
FLAGS_HOST=$(terraform -chdir=../terraform output -raw flags_rds_endpoint | cut -d: -f1)
FLAGS_PW=$(terraform -chdir=../terraform output -raw flags_rds_password)

kubectl run psql-demo --rm -it --restart=Never -n apps --image=postgres:15-alpine -- \
  env PGPASSWORD="$FLAGS_PW" psql -h "$FLAGS_HOST" -U flag_user -d flags_db \
  -c "SELECT id, name, is_enabled FROM flags;"
```

> "A prova de que não é memória: a flag está **gravada no PostgreSQL**, num banco que **não é acessível pela internet** — só de dentro da VPC. Por isso rodei um pod temporário: é o mesmo caminho que os serviços usam."

### 5.4 — Regra + evaluate (20s)

```bash
curl -s -X POST http://$INGRESS/rules \
  -H "Content-Type: application/json" -H "Authorization: Bearer $KEY" \
  -d '{"flag_name":"checkout-v2","is_enabled":true,"rules":{"type":"PERCENTAGE","value":100}}'

curl -s "http://$INGRESS/evaluate?flag_name=checkout-v2&user_id=user-123" -H "Authorization: Bearer $KEY"
```

> "Criei a regra de segmentação — 100% dos usuários. E o **evaluate**: consulta flag e regra, verifica o **Redis**, responde `result: true` **na hora**, e publica um evento no **SQS** de forma assíncrona."

### 5.5 — Provar SQS → DynamoDB (25s) ⭐

```bash
aws dynamodb scan --table-name ToggleMasterAnalytics --select COUNT --region us-east-1
```

> "No **SQS** dá pra ver a mensagem que o evaluate publicou. E o **analytics**, rodando no EKS e assumindo a role IRSA, consumiu e **gravou no DynamoDB**. Olha os itens: flag, usuário, resultado e timestamp.
>
> **Fluxo fechado**: Ingress → evaluation → Redis + RDS → SQS → analytics → DynamoDB."

### 5.6 — CRUD (10s)

```bash
curl -s http://$INGRESS/flags -H "Authorization: Bearer $KEY"
```

> "E o `GET /flags` lista tudo que está no banco. A funcionalidade completa está de pé."

---

# BLOCO 6 (6:05 - 8:30) — KEDA (autoscaling por fila SQS)

### 6.1 — A justificativa (25s)

> "Agora o autoscaling. Temos **dois tipos de carga** e cada uma pede um sinal diferente.
>
> O **evaluation** é **síncrono** — responde HTTP, então a carga vira **CPU**, e quem escala é o **HPA** nativo do Kubernetes.
>
> O **analytics** é **assíncrono** — não recebe HTTP, só consome fila. CPU **não serve** como métrica, porque ele fica ocioso. O sinal correto é a **profundidade da fila**. E é pra isso que existe o **KEDA**: ele lê o tamanho da fila SQS e escala — inclusive **de zero a N**, e **de volta a zero** quando não há mensagem. Isso é economia real."

### 6.2 — O manifest (20s)

**Abra [keda-scaledobject.yaml](file:///Users/joze_lucas/Desktop/codes/fiap-toggle-master/kubernetes/keda-scaledobject.yaml):**

> "Dois objetos: o `TriggerAuthentication` diz **como** autenticar na AWS — via **IRSA**, sem credencial hardcoded. O `ScaledObject` diz **o que** escalar: o deployment `analytics-service`, trigger `aws-sqs-queue`, **uma réplica a cada 10 mensagens**, `min 0` e `max 10`."

### 6.3 — Estado inicial: ZERO (20s)

**Terminal A (deixe rodando):**

```bash
kubectl get pods -n apps -w
```

**Terminal B:**

```bash
kubectl get scaledobject -n apps
kubectl get hpa -n apps
```

> "Olha o estado inicial: o KEDA mostra `READY=True` e `ACTIVE=False`. E o analytics está com **zero pods** — fila vazia, não precisa de worker. Guarde essa imagem: **zero**."

### 6.4 — Encher a fila → escalar (40s) ⭐

**Terminal B:**

```bash
cd scripts
./send-sqs-batch.sh 1500
```

> "Enviando **1500 mensagens** em lote pro SQS. Olha o terminal da esquerda: o KEDA lê a profundidade da fila e **começa a criar réplicas** — 1, 5, 10, até o máximo. Os pods sobem e começam a consumir."

```bash
kubectl get scaledobject -n apps
```

> "E repare: o KEDA **cria um HPA por baixo** — o `keda-hpa-analytics-scaledobject`, lendo uma **métrica externa**, o tamanho da fila. É o Kubernetes com fonte de métrica customizada."

### 6.5 — Provar no DynamoDB (20s)

```bash
aws dynamodb scan --table-name ToggleMasterAnalytics --select COUNT --region us-east-1
```

> "E cada mensagem consumida virou um item no **DynamoDB**. O ciclo fechou: **SQS → analytics → DynamoDB**."

### 6.6 — Volta a ZERO (25s)

> "Com a fila drenada, o KEDA reduz de volta a **zero réplicas**.
>
> Essa é a diferença essencial: o **HPA** ajusta a capacidade de algo que está **sempre no ar**; o **KEDA** **liga e desliga** conforme o evento. Um custa o tempo todo pelo mínimo — o outro custa **zero** quando não há trabalho."

---

# BLOCO 7 (8:30 - 9:00) — ENCERRAMENTO + DESTROY

**Abra `terraform/destroy.sh` no VSCode, depois rode:**

```bash
cd ../terraform
./destroy.sh          # confirme digitando: DESTROY-TOGGLE-MASTER
```

> "E pra fechar: **toda essa infra é descartável**. O `destroy.sh` primeiro remove o que o Kubernetes criou fora do Terraform — o Load Balancer do Ingress — e depois roda o destroy. Os **66 recursos** são apagados e **não sobra nada**: sem cluster, sem banco, sem cobrança rodando.
>
> Resumindo: **infra AWS 100% declarativa em Terraform, com IRSA pra segurança, autoscaling por evento com KEDA, e uma demonstração ponta a ponta validada nos serviços reais.** Obrigado!"

> **Atenção:** se o time ainda precisa da infra pra outras partes do vídeo, **não delete de verdade** — só mostre o script e diga que ele apaga tudo.

---

# CHECKLIST PRÉ-GRAVAÇÃO

**Infra viva (rodar antes, fora do vídeo)**

- [ ] `cd terraform && ./apply.sh`
- [ ] `./push-all-images-to-ecr.sh`
- [ ] `cd ../kubernetes && ./apply.sh`
- [ ] `./install-keda.sh && ./apply.sh`
- [ ] **Fila SQS vazia** antes de gravar (a demo do KEDA precisa começar em 0)

**Console AWS — 8 abas pré-carregadas e com F5 dado**

- [ ] VPC · EKS (Node Group) · RDS · ElastiCache · SQS · DynamoDB · ECR · IAM Roles

**Terminal**

- [ ] `INGRESS` capturado e testado (`curl http://$INGRESS/auth/health` → ok)
- [ ] `MASTER_KEY` disponível no `.env`
- [ ] `kubectl get scaledobject -n apps` → `READY=True`, `ACTIVE=False`
- [ ] Comando do `psql-demo` já testado uma vez

**Vídeo**

- [ ] Zoom do terminal 125-150%
- [ ] Notificações do sistema desligadas
- [ ] Cronômetro visível (meta: **≤ 9:00**)

---

# DICAS DE GRAVAÇÃO

1. **O `terraform apply` leva ~25 min** — mostre o `plan`, corte, e volte com ele pronto.
2. **Console AWS carrega devagar** — abra tudo antes e dê F5. Nunca espere carregar ao vivo.
3. **Os 5 momentos ⭐** (RDS, SQS, DynamoDB, KEDA escalando, KEDA voltando a 0) são a prova de que funciona de verdade — **não corte esses**.
4. **Se estourar o tempo**, corte nesta ordem: (1) Console AWS, (2) CRUD do 5.6, (3) detalhes dos scripts de carga.
5. **Não leia código linha a linha** — cite o ponto-chave e siga. O `apply.sh` do K8s e o `destroy.sh` são os dois scripts que mais impressionam.
6. **Frases de impacto:** "nada foi clicado no console" · "menor privilégio" · "sem credencial dentro do pod" · "escala de zero a N" · "custo perto de zero".
