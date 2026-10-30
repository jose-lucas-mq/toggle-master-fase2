# Glossário de Kubernetes e DevOps Cloud - ToggleMaster FIAP

> **Público Alvo:** Time do ToggleMaster Tech Challenge. Nível: iniciante/intermediário.
> **Objetivo:** Explicar, em português e com exemplos do nosso projeto, os 6 pilares que vamos usar na Sprint 2: **EKS, Ingress, ClusterIP, IRSA, KEDA e Kyverno**.
> **Para quê serve?** Alinhar conhecimento do time: quem já sabe, confere exemplos; quem não sabe, entende o "porquê" de cada componente e como ele se encaixa no nosso desafio.

---

## 🧭 Como usar esse glossário

Cada seção segue a mesma estrutura para facilitar a leitura:

1.  **O QUE É (1 parágrafo simples):** Definição do conceito, sem jargões.
2.  **PAPEL NO TOGGLEMASTER:** Como esse componente se encaixa NO NOSSO PROJETO (não genérico).
3.  **ANALOGIA SIMPLES:** Para quem não sabe DevOps (ex: "é o porteiro do prédio").
4.  **EXEMPLO DE CÓDIGO / MANIFESTO KUBERNETES:** Trecho real (curto) que vamos usar.
5.  **CUSTO NA AWS (se aplicável):** Para o nosso ambiente de estudo (1 cluster EKS, 2 nós t3.small).

---

## 📖 Índice

1.  [EKS (Amazon Elastic Kubernetes Service)](#1-eks-amazon-elastic-kubernetes-service)
2.  [ClusterIP](#2-clusterip)
3.  [Ingress](#3-ingress)
4.  [IRSA (IAM Roles for Service Accounts)](#4-irsa-iam-roles-for-service-accounts)
5.  [KEDA (Kubernetes Event-Driven Autoscaling)](#5-keda-kubernetes-event-driven-autoscaling)
6.  [Kyverno](#6-kyverno)

---

## 1. EKS (Amazon Elastic Kubernetes Service)

### O QUE É
EKS é o **Kubernetes Gerenciado pela AWS**. Ou seja: a AWS cuida, instala, atualiza e monitora o **"cérebro do cluster" (Control Plane - API Server, etcd, scheduler)** 24/7 para nós. Nós só precisamos provisionar e gerenciar os **nós de trabalho (Worker Nodes / Node Groups)** — as VMs EC2 onde nossos 5 microsserviços rodam.

### PAPEL NO TOGGLEMASTER
É o **ambiente oficial de execução** da Sprint 2: substitui o `docker compose up` local por um **cluster de produção real na AWS**.
- O EKS vai hospedar nossos 5 pods (auth, flag, targeting, evaluation, analytics).
- Gerencia atualizações zero-downtime (Rolling Updates), restart automático se um pod cair, health checks etc.
- Conecta nossos pods ao RDS, Redis, SQS e DynamoDB (mesma VPC 10.20.0.0/16 que criamos na Sprint 1).

### ANALOGIA SIMPLES
> "Imagine o Kubernetes como um **SHOPPING CENTER**.
> - O **EKS (Control Plane)** é a **ADMINISTRAÇÃO DO SHOPPING**: controla qual loja (pod) vai em qual andar (nó), aluguel, segurança.
> - Os **Worker Nós** são os **ANDARES / SALAS** do shopping.
> - As **LOJAS** são os **PODS** (auth, flag, targeting, evaluation, analytics)."

### EXEMPLO PRÁTICO (Nosso cenário)
```yaml
# futuro: eks-cluster/main.tf (simplificado)
module "eks" {
  cluster_name    = "toggle-master-eks"
  cluster_version = "1.29"   # Versão Kubernetes
  vpc_id          = "vpc-0887e1259cea742ce"   # Nossa VPC já criada!

  # Sub-redes PRIVADAS para nós workers (Well Architected)
  subnet_ids      = [
    "subnet-097fd0e3c5ca9c074",
    "subnet-0be5074224ac3a7d9",
    "subnet-0aa80ddb53b4cc8ea"
  ]
}
```

### CUSTO AWS (estudo)
| Item | Custo 24/7 mês (caro) | Custo 3h/semana (ESTUDO) |
|---|---|---|
| EKS Control Plane (OBRIGATÓRIO) | **~US$ 146,00 / mês** | **~US$ 2,46** (12h) |
| 2 × Worker Nós `t3.small` (Managed Node Group) | US$ 45,50 / mês | ~US$ 0,75 |
| **TOTAL EKS (aproximado)** | **~US$ 190,00 / mês** 💸 | **~US$ 3,20 / mês** 🎉 |

> 💡 **LIÇÃO CASA:** No estudo, rodamos `terraform destroy` NO FIM da sessão. Em produção, o EKS fica 24/7.

---

## 2. ClusterIP

### O QUE É
ClusterIP é o **tipo MAIS SIMPLES e MAIS COMUM de Service Kubernetes**. Ele cria **um ENDEREÇO IP INTERNO (fixo, virtual) DENTRO DO CLUSTER** que aponta para um ou mais pods do mesmo tipo.

- O IP dele **só é acessível de DENTRO do cluster Kubernetes**.
- **NUNCA é acessível da internet ou da VPC externa ao cluster.**

### PAPEL NO TOGGLEMASTER
Todos os nossos 5 microsserviços **vão expor portas internamente via ClusterIP**, porque:
1.  Ninguém acessa o `auth-service:8001` (porta interna) da internet — **apenas os outros microsserviços dentro do cluster** precisam falar com ele.
2.  A única forma de chegar de FORA do cluster é através do **Ingress (item 3)**.
3.  Exemplo: quando o `evaluation-service` precisa consultar a flag no `flag-service`, ele usa **DNS interno** do ClusterIP (ex: `http://flag-service:80`).

### ANALOGIA SIMPLES
> "O ClusterIP é o **RAMAL INTERNO de uma empresa**.
> - Você disca *8001 para falar com o RH (auth-service), *8002 para Produto (flag-service).
> - Só quem está DENTRO da empresa (no cluster) pode usar esse ramal.
> - O telefone da rua (internet) NÃO consegue discar esse ramal direto (precisa passar pela recepção = Ingress / Load Balancer)."

### EXEMPLO DE CÓDIGO PRÁTICO (Nosso service flag-service)
```yaml
# futuro: k8s/flag-service/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: flag-service
  namespace: togglemaster
spec:
  type: ClusterIP   # 👈 Tipo padrão. Se você omitir type, default é ClusterIP!
  selector:
    app: flag-service
  ports:
    - port: 80              # Porta INTERNA que OUTROS serviços acessam
      targetPort: 8002       # Porta REAL do container Flask Python
      protocol: TCP
```
Como o evaluation acessa?
- URL interna no pod: `http://flag-service/flags` (porta 80 padrão, via service DNS). Não precisa porta 8002 externamente.

---

## 3. Ingress

### O QUE É
Ingress é o **"porteiro / gateway único" do cluster Kubernetes**. Ele gerencia **TODO O TRÁFEGO HTTP/HTTPS (Norte-Sul) QUE VEM DA INTERNET** e roteia para o serviço ClusterIP correto **baseado no caminho da URL (path)** ou **no domínio (hostname)**.

Para o Ingress funcionar, precisamos do **Ingress Controller** (nós vamos usar o **Nginx Ingress Controller** via Helm — software open-source que implementa as regras do Ingress). O Controller é o software que lê as regras do Ingress e executa o roteamento.

### PAPEL NO TOGGLEMASTER
É a **ÚNICA PORTA DE ENTRADA HTTP DE FORA DA AWS** (internet). Exemplos de rotas reais do nosso projeto:

| URL (externa) | Para onde o Ingress encaminha? | ClusterIP destino |
|---|---|---|
| `https://api.togglemaster.fiap.br/auth/*` | Login, criar chave API | `auth-service` porta 80 |
| `https://api.togglemaster.fiap.br/flags/*` | CRUD flags | `flag-service` porta 80 |
| `https://api.togglemaster.fiap.br/rules/*` | CRUD regras targeting | `targeting-service` porta 80 |
| `https://api.togglemaster.fiap.br/evaluate?user_id=123&flag_name=...` | Avaliação hot path | `evaluation-service` porta 80 |

> 💡 Obs: O `analytics-service` NÃO tem rota no Ingress! Ele só consome SQS em background (trabalhador interno, sem endpoint HTTP público).

### ANALOGIA SIMPLES
> "O Ingress é a **RECEPÇÃO / PORARIA DO PRÉDIO**.
> - Ele recebe TODOS os visitantes da internet (porta 80 / 443).
> - Se o visitante disser **"vim para o RH (rota /auth)"**, a recepção (Ingress) encaminha ele para o andar correto (ClusterIP auth-service).
> - Pessoal interno (outros pods) não precisa passar pela recepção.
> - O Ingress também impõe **HTTPS obrigatório**, terminando o certificado SSL publico antes de chegar nos pods (Terminação TLS)."

### EXEMPLO DE CÓDIGO PRÁTICO (Nosso Ingress)
```yaml
# futuro: k8s/ingress/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: togglemaster-api
  namespace: togglemaster
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"   # Força HTTPS
spec:
  ingressClassName: nginx   # Usa o Nginx Ingress Controller
  rules:
  - host: api.togglemaster.fiap.br
    http:
      paths:
      - path: /auth
        pathType: Prefix
        backend:
          service: { name: auth-service, port: { number: 80 } }
      - path: /flags
        pathType: Prefix
        backend:
          service: { name: flag-service, port: { number: 80 } }
      - path: /rules
        pathType: Prefix
        backend:
          service: { name: targeting-service, port: { number: 80 } }
      - path: /evaluate
        pathType: Prefix
        backend:
          service: { name: evaluation-service, port: { number: 80 } }
```

---

## 4. IRSA (IAM Roles for Service Accounts)

### O QUE É
IRSA é uma **FEATURE EXCLUSIVA DO EKS (AWS)** que permite **ligar uma ROLE IAM DA AWS diretamente a uma Service Account do Kubernetes**.

Resultado: **PODS que usam essa Service Account recebem automaticamente CREDENCIAIS AWS TEMPORÁRIAS (STS) com permissões da ROLE IAM anexada** — sem precisar gravar Access Key / Secret AKID hardcoded em Secrets do K8s (o que é perigoso e anti-padrão).

- Resolve **gerenciamento de credenciais AWS** para pods que falam com SQS, DynamoDB, S3, ECR etc.
- Usa **OpenID Connect (OIDC)** provider do cluster EKS para provar identidade do pod ao IAM.

### PAPEL NO TOGGLEMASTER
É OBRIGATÓRIO e **USAMOS 4 ROLES IRSA NO MINIMO**:

| Role IRSA (AWS IAM) | Kubernetes Service Account (KSA) | Quem usa? | Permissões MÍNIMAS |
|---|---|---|---|
| `Role-Evaluation-Pod` | `evaluation-sa` | `evaluation-service` pods | Apenas **`sqs:SendMessage`** na fila `toggle-master-events`. Ler `redis` não é AWS, é interno. |
| `Role-Analytics-Pod` | `analytics-sa` | `analytics-service` pods | Apenas **`sqs:ReceiveMessage`, `sqs:DeleteMessage`** + **`dynamodb:PutItem`** tabela `ToggleMasterAnalytics`. |
| `Role-KEDA-Operator` | `keda-operator` | KEDA | Permissão **`sqs:GetQueueAttributes`** (KEDA consulta o `ApproximateNumberOfMessagesVisible` para escalar o analytics). |
| `Role-Nginx-Ingress` | `ingress-nginx` | Nginx Ingress Controller | Permissão de **criar ALB/ELB e Route53 (se usar ExternalDNS)**. |

> Sem IRSA: nós teríamos que criar Access Key ID/Secret para cada app e colocar em Secrets K8s (FEIO, INSEGURO, auditável difícil).

### ANALOGIA SIMPLES
> "O IRSA é um **Crachá de Empresa (badge)**.
> - Sem crachá: para entrar no arquivo (AWS), você precisaria de uma **SENHA GENÉRICA ESCRITA NO POST-IT** (Access Key hardcoded — todo mundo vê, se perde é problema).
> - Com crachá (IRSA): cada funcionário (pod) tem um **crachá de acesso TEMPORÁRIO e PESSOAL**, expira em 1 hora, e o RH (IAM AWS) controla exatamente o que cada crachá (role) acessa (princípio do menor privilégio).
> - A porta do arquivo (STS da AWS) valida o crachá automaticamente."

### DIAGRAMA RÁPIDO (ToggleMaster)
```
POD evaluation → ServiceAccount: evaluation-sa (anotação eks.amazonaws.com/role-arn = Role-Evaluation-Pod)
                                    │
                                    └── OIDC Provider do EKS ── sts:AssumeRoleWithWebIdentity ──► Role IAM: Role-Evaluation-Pod
                                                                                                            │
                                                                                                            └── Policy: Apenas sqs:SendMessage no ARN da fila
                                                                                                            └── Credenciais temporárias (1h) injectadas no pod via AWS_WEB_IDENTITY_TOKEN_FILE
```

---

## 5. KEDA (Kubernetes Event-Driven Autoscaling)

### O QUE É
KEDA é um **operador (addon) Kubernetes open-source** criado pela Microsoft + Red Hat para **AUTO-ESCALAR HORIZONTALMENTE (HPA) SEUS PODS COM BASE EM EVENTOS / MÉTRICAS EXTERNAS (SQS, Kafka, Azure SB, Prometheus etc)**.

O HPA padrão do Kubernetes só escala baseado em CPU/RAM do pod. O KEDA **adiciona 50+ scalers**: no nosso caso, ele escala o **analytics-service** baseado no **NÚMERO DE MENSAGENS PENDENTES NA FILA SQS `toggle-master-events`**.

### PAPEL NO TOGGLEMASTER
É um dos **DESAFIOS DO TECH CHALLENGE!** (escalar analytics dinamicamente):
- **Horário de pico (ex: 10k eventos em 1 minuto):** KEDA vê 10000 mensagens no SQS e **sobe o deployment do analytics de 1 para 20 pods** consumindo em paralelo.
- **Horário ocioso (0 a 5 mensagens):** KEDA **diminui para 0 pods (Scale to Zero!)* para economizar recurso e custo.
- Responde rápido (escalagem em segundos).

> Obs: O `evaluation-service` vai usar **HPA PADRÃO (baseado em CPU/RAM + QPS custom Prometheus)** — não KEDA. KEDA é só para fila SQS → analytics.

### ANALOGIA SIMPLES
> "O KEDA é o **GERENTE DE CAIXA DE SUPERMERCADO**.
> - Ele **OLHA PARA O TAMANHO DA FILA DE CLIENTES** (mensagens SQS).
> - Se tem 30 pessoas na fila: ele **ABRE 6 CAIXAS NOVOS** (escala 6 pods analytics).
> - Se tem 1 pessoa ou nenhuma: ele **FECHA TODOS os caixas e o gerente cuida sozinho ou fecha** (scale to zero).
> - O gerente não olha para o quanto os caixas estão suando (CPU). Ele olha para o TAMANHO DA FILA.

### EXEMPLO PRÁTICO (Nosso ScaledObject KEDA para analytics)
```yaml
# futuro: k8s/analytics/keda-scaledobject.yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: analytics-sqs-scaler
  namespace: togglemaster
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: analytics-service    # 👈 O que ele escala: analytics deployment

  pollingInterval:  5          # Consulta SQS a cada 5s
  cooldownPeriod:   60         # Espera 1min sem msgs p/ escalar p/ baixo
  minReplicaCount:  0          # 👈 SCALE TO ZERO (NENHUM pod ocioso)
  maxReplicaCount:  20         # Teto máximo de 20 pods (economia)

  triggers:
    - type: aws-sqs-queue
      authenticationRef:
        name: keda-trigger-auth-aws-role   # Usa a IRSA do KEDA operator!
      metadata:
        queueURL: https://sqs.us-east-1.amazonaws.com/128432678106/toggle-master-events
        queueLength: "5"     # 👈 Cada pod analytics processa ~5 msgs. Total msgs /5 = pods.
        awsRegion: "us-east-1"
        identityOwner: operator
```

---

## 6. Kyverno

### O QUE É
Kyverno é **um POLICY ENGINE Kubernetes (admission controller + mutating webhook)** que funciona **igual uma "POLÍCIA DO CLUSTER"**. Kyverno permite criar REGRAS (policies) YAML que validam, mutam (alteram antes de criar) ou geram recursos automaticamente **ANTES que qualquer objeto (Pod, Deployment, Service, Ingress) seja aceito pelo API Server e gravado no etcd do Kubernetes**.

Diferentemente do Open Policy Agent (OPA/Gatekeeper), Kyverno é **NATIVO Kubernetes (CRDs customizados)** e as policies são 100% YAML (sem linguagem Rego nova para aprender).

### PAPEL NO TOGGLEMASTER
É também do desafio! Vamos usar no mínimo **5 POLÍTICAS DE GOVERNANÇA** para o cluster não virar bagunça:

| # | Policy Kyverno ToggleMaster | Tipo | O que faz? |
|---|---|---|---|
| 1 | `require-resources-limits` | Validate | **OBRIGA TODO Deployment declarar `resources.requests` e `resources.limits` (CPU/memória)**. Ninguém cria pod sem limites (evita consumo infinito que derruba nó). |
| 2 | `require-readiness-liveness-probe` | Validate | **OBRIGA TODO Deployment ter `readinessProbe` e `livenessProbe`**. Ninguém cria app que trava sem restart automático. |
| 3 | `block-default-namespace` | Validate | NINGUÉM cria pod/recurso no namespace `default`. Tudo tem que ir no namespace `togglemaster` ou `keda`/`ingress-nginx` (organização). |
| 4 | `block-latest-image-tag` | Validate | **PROÍBE usar imagem Docker com tag `:latest`** (anti padrão, não tem reprodutibilidade). Obriga versão semântica (ex: `:v1.2.3` ou `:sha-ab23cd`). |
| 5 | `add-safe-to-evict-annotation` | Mutate | **Adiciona automaticamente annotation `cluster-autoscaler.kubernetes.io/safe-to-evict: "true"` em todos os pods do namespace togglemaster.** Facilita o Cluster Autoscaler remover nós quando estão ociosos (economia). |

### ANALOGIA SIMPLES
> "Kyverno é o **FISCAL DE BOATE + PORTEIRO DO CLUSTER**.
> - Antes de deixar QUALQUER PESSOA (pod) entrar na festa (criar no cluster):
>   1.  VALIDA se ela tem RG (limits/requests) — se não tem, NÃO ENTRA.
>   2.  VALIDA se ela está com tag da festa (não pode entrar camisa do time rival / proíbe :latest).
>   3.  MUTA (adiciona automaticamente) um pulseira VIP (annotation safe-to-evict) em todos convidados.
> - Ninguém entra se a regra falha."

### EXEMPLO PRÁTICO (Nosso Policy `require-resources-limits`)
```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resources-limits
  annotations:
    policies.kyverno.io/title: Requer CPU/memória
    policies.kyverno.io/severity: high
spec:
  validationFailureAction: Enforce   # 👈 Ação: "Enforce" (BLOQUEIA se violar). Outra opção: "Audit" (só loga).
  background: true
  rules:
  - name: check-container-resources
    match:
      any:
      - resources:
          kinds:
          - Pod
    validate:
      message: "Todo container DEVE declarar resources.requests e resources.limits (CPU e memória)! Use Deployment.spec.template.spec.containers[*].resources."
      pattern:
        spec:
          containers:
          - name: "*"
            resources:
              requests:
                memory: "?*"
                cpu: "?*"
              limits:
                memory: "?*"
                cpu: "?*"
```
> Se alguém tentar `kubectl apply -f deployment-sem-limits.yaml`, a API Server do Kubernetes responde imediatamente **403 Forbidden** com a message acima (bloqueia o deploy).

---

## 📚 Resumo Visual do Todo o Fluxo (ToggleMaster Sprint 2)

```
INTERNET
    │ 443 HTTPS (DNS api.togglemaster.fiap.br)
    ▼
AWS ALB / NLB (criado automaticamente por Nginx Ingress Controller)
    │
    ▼
NGINX INGRESS CONTROLLER ──► Ingress (roteamento por path /flags /auth ...)
    │                     └── Kyverno: valida o Ingress antes de aceitar.
    ▼
CLUSTER IPs (só dentro do cluster)
  ├── auth-service (80 → 8001 Go)
  ├── flag-service (80 → 8002 Python Flask)
  ├── targeting-service (80 → 8003 Python Flask)
  ├── evaluation-service (80 → 8004 Go)
  │         │ (scaling: HPA CPU/RAM + IRSA Role-Evaluation-Pod → sqs:SendMessage)
  │         ▼
  │     📮 SQS toggle-master-events (AWS) ◄── KEDA Scaler (polling)
  │                                              │ (IRSA Role-KEDA → sqs:GetQueueAttributes)
  │                                              ▼ (se msgs > 5)
  └── analytics-service (escala: 0 a 20 pods) ── KEDA ScaledObject
            │ (IRSA Role-Analytics-Pod → sqs:ReceiveMessage + dynamodb:PutItem)
            ▼
        🗄️ DynamoDB ToggleMasterAnalytics

Bancos / Cache (VPC privada criada Sprint 1):
  3x RDS PostgreSQL (auth/flags/targeting) + ElastiCache Redis
```

---

## 🧩 Próximos passos depois de ler esse glossário

1.  **Para quem NÃO DOMINA K8s:**
    - Instalar `kubectx` + `kubens` no laptop.
    - Assistir 2 vídeos de 10min no YouTube: "O que é Kubernetes Deployment + Service ClusterIP".
2.  **Para o time todo:**
    - Quando criarmos o EKS, todos recebem `kubeconfig` e rodam `kubectl get pods -n togglemaster` para ver os 5 serviços.
3.  **Próximo trabalho de código:**
    - Criar módulo Terraform `eks_cluster` (Control Plane + MNG).
    - Criar módulo Terraform `iam_irsa` (4 roles IRSA + 4 KSAs + OIDC provider).
    - Buildar e pushar as 5 imagens Docker no ECR criado.

---
