# Terraform — ToggleMaster Infraestrutura AWS

Pasta de Infraestrutura como Código (IaC) que provisiona **TODOS os recursos da conta AWS pessoal**
(menos o cluster EKS e seus add-ons, que será adicionado em um próximo passo).

---

## 🧩 O que este Terraform provisiona (Sprint 1)

| Categoria | Recursos | Módulo |
|---|---|---|
| **Rede** | 1 VPC dedicada `/16` + 3 sub-redes públicas + 3 privadas Multi-AZ, 1 IGW, 1 ou 3 NAT Gateways, Route Tables | `modules/networking/` |
| **Registro de Imagens** | 5 repositórios ECR privados (1 por serviço) | `modules/ecr/` |
| **Datastores relacionais** | 3 instâncias independentes RDS PostgreSQL 15 (auth-db, flags-db, targeting-db) com senhas geradas aleatórias | `modules/rds/` + `random_password` |
| **Cache hot-path** | 1 cluster ElastiCache Redis 7 | `modules/elasticache/` |
| **Fila de eventos** | 1 SQS Standard Queue + 1 DLQ (poison pill) | `modules/sqs/` |
| **Eventos analíticos** | 1 Tabela DynamoDB `ToggleMasterAnalytics` (PK event_id) + 3 GSIs | `modules/dynamodb/` |
| **Segurança** | Security Groups Zero Trust (cada serviço tem seu SG próprio; portas mínimas liberadas) | Dentro `modules/*/security_groups.tf` |
| **IAM (passo posterior)** | Roles IRSA p/ Ingress, KEDA, Evaluation, Analytics | **Módulo futuro (Sprint 2)** |
| **Container Orquestração** | Cluster EKS + Managed Node Group + OIDC Provider | **Módulo futuro (Sprint 2)** |

Todos os recursos são etiquetados com `common_tags` + `Project=ToggleMaster` + `ManagedBy=Terraform`
(ajuste em `terraform.tfvars`).

---

## 📋 Pré-requisitos (instalar localmente 1 vez)

1.  **Terraform >= 1.5.0, < 2.0** (alinhado com `versions.tf`)
    ```bash
    brew install terraform            # macOS homebrew
    terraform version                 # esperado >= 1.5
    ```
2.  **AWS CLI v2**
    ```bash
    brew install awscli               # macOS
    aws --version                     # esperado aws-cli/2.x
    ```
3.  **Credenciais base válidas** na sua conta AWS pessoal (IAM user credenciais LONG-TERM
    OU AWS SSO — tanto serve).

---

## ☁️ Estado Compartilhado OBRIGATÓRIO: Backend S3

**NUNCA DEIXE O ESTADO EM ARQUIVO LOCAL `terraform.tfstate`!**
Risco enorme de:
- Apagar o arquivo sem querer → perder RASTRO DE TODOS RECURSOS ($$$).
- Computador novo formatado → perder estado.

Nosso projeto armazena o estado em **1 bucket S3 da sua conta AWS pessoal** (versão + criptografia).

> 📝 **Estado Locking DynamoDB REMOVIDO por sua decisão** — item opcional para time. Para estudo 1 pessoa, desnecessário.

---

### Passo 1 (1 vez só): Crie o BUCKET S3 na sua conta

O nome de bucket S3 é **global único em TODO AWS**.
Padrão recomendado: `toggle-master-<SEU-NUMERO-DE-CONTA-AWS>-tfstate`

> 🚨 **OBSERVAÇÃO MUITO IMPORTANTE:** Buckets S3 **NÃO PODEM ser recriados com o mesmo nome globalmente por algumas horas após exclusão**. Por isso usamos o número da conta no nome.

Criação via AWS CLI:
```bash
# 1) Autenticado com a sua role/profile:
export AWS_PROFILE=fiap-toggle-master   # ou seu profile base
export SUA_CONTA_AWS=123456789012       # COLOQUE SEU NÚMERO DE CONTA AQUI
export NOME_BUCKET="toggle-master-${SUA_CONTA_AWS}-tfstate"
export REGION=us-east-1

# 2) Cria o bucket (se região us-east-1 não precisa LocationConstraint):
aws s3api create-bucket \
  --bucket "$NOME_BUCKET" \
  --region "$REGION" \
  --object-ownership BucketOwnerEnforced \
  --profile "$AWS_PROFILE"

# 3) BLOQUEIA ACESSO PÚBLICO (OBRIGATÓRIO - estado tem secrets sensíveis como senhas RDS!):
aws s3api put-public-access-block \
  --bucket "$NOME_BUCKET" \
  --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
  --profile "$AWS_PROFILE"

# 4) Habilita VERSIONAMENTO (rollback manual se precisar):
aws s3api put-bucket-versioning \
  --bucket "$NOME_BUCKET" \
  --versioning-configuration Status=Enabled \
  --profile "$AWS_PROFILE"

# 5) Habilita CRIPTOGRAFIA DEFAULT SSE-S3 (sem custo):
aws s3api put-bucket-encryption \
  --bucket "$NOME_BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
  --profile "$AWS_PROFILE"

echo "✅ Bucket criado: $NOME_BUCKET — SALVE esse nome!"
```

---

### Passo 2 (20 segundos): Cole o NOME DO SEU BUCKET diretamente no arquivo `backend.tf`

**SIMPLES! Não precisa de arquivo separado de vars.**

Edite agora o arquivo `terraform/backend.tf` (linha ~23) e substitua o placeholder:

```hcl
# ANTES (placeholder):
bucket = "toggle-master-COLOQUE-SEU-CONTA-ID-AQUI-tfstate"

# DEPOIS (seu bucket real):
bucket = "toggle-master-123456789012-tfstate"
```
💡 Os outros campos (`key`, `region = "us-east-1"`, `profile = "fiap-toggle-master"`, `encrypt = true`) são fixos e **NÃO PRECISA ALTERAR**.

---

### Passo 3 (1 vez só): Inicialize o backend e migre o estado

```bash
cd terraform/
terraform init
```

Saída esperada sucesso:
```
Successfully configured the backend "s3"! Terraform will automatically
use this backend unless the backend configuration changes.
```

Se você já tinha um estado LOCAL criado (arquivo `terraform.tfstate` na pasta antes de configurar backend), o Terraform pergunta:
```
Do you want to copy existing state to the new backend?
```
**Responda `yes`** → estado é copiado com segurança para o S3, e o arquivo local é apagado. 🎉

---

### Politica IAM MÍNIMA que sua ROLE de deploy precisa para acessar o backend S3

Cole na Managed Policy da sua `ToggleMasterDeployRole`:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketVersioning",
        "s3:GetBucketPublicAccessBlock"
      ],
      "Resource": "arn:aws:s3:::toggle-master-SEU-NUMERO-CONTA-tfstate"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:GetObjectVersion"
      ],
      "Resource": "arn:aws:s3:::toggle-master-SEU-NUMERO-CONTA-tfstate/*"
    }
  ]
}
```

---

## 🔐 2 Formas de Configurar a Sua Role Específica (Escolha 1)

Você pediu para o Terraform assumir uma **role específica da sua conta**.
Existem **2 estratégias recomendadas** — ambas funcionam, escolha **SÓ UMA**:

---

### ✅ ESTRATÉGIA 1 (RECOMENDADA PARA ESTUDO)
### Profile AWS CLI com `role_arn` no `~/.aws/config`
**Vantagem:** não precisa colocar ARN de role hardcoded nos arquivos; você troca de role
apenas com `export AWS_PROFILE` ou `terraform.tfvars`. Permite auditar comandos AWS CLI
e Terraform usando o MESMO profile.

#### Passo 1.1 — Crie o profile `fiap-toggle-master` no seu `~/.aws/config`
```ini
# ~/.aws/config (LINUX / MAC: ~/.aws/config   WIN: C:\Users\You\.aws\config)
[profile fiap-toggle-master]
region                      = us-east-1
output                      = json
role_arn                    = arn:aws:iam::123456789012:role/ToggleMasterDeployRole
source_profile              = minha-conta-pessoal-base      # <-- profile com suas credenciais LONG-TERM / SSO
role_session_name           = terraform-toggle-master-local
duration_seconds            = 3600                           # sessão STS 1h (máximo que a role permitir)
```

> **Pré-requisito da sua role:**  
> A role `ToggleMasterDeployRole` precisa ter uma **Trust Policy** que permita
> `sts:AssumeRole` pelo ARN da sua identidade IAM base (usuário/role SSO).
> Exemplo Trust Policy mínima:
> ```json
> {
>   "Version": "2012-10-17",
>   "Statement": [{
>     "Effect": "Allow",
>     "Principal": { "AWS": "arn:aws:iam::123456789012:root" },
>     "Action": "sts:AssumeRole",
>     "Condition": {}
>   }]
> }
> ```

#### Passo 1.2 — Valide que o profile funciona (fora do Terraform):
```bash
aws sts get-caller-identity --profile fiap-toggle-master
# Saída esperada:
# {
#   "UserId": "AROA...botocore-session...",
#   "Account": "123456789012",
#   "Arn": "arn:aws:sts::123456789012:assumed-role/ToggleMasterDeployRole/terraform-toggle-master-local"
# }
```

#### Passo 1.3 — Diga ao Terraform para usar ESTE profile:
Copie `terraform/terraform.tfvars.example → terraform/terraform.tfvars` e ajuste:
```hcl
# terraform.tfvars
aws_profile = "fiap-toggle-master"
# aws_assume_role_arn = ""  # DEIXE VAZIO — a role já vem do profile AWS CLI automaticamente
```

---

### ✅ ESTRATÉGIA 2 (DIRETO NO PROVIDER, SEM EDITAR `~/.aws/`)
### Assume-role direto no provider AWS (variável `aws_assume_role_arn`)
Use se você já tem credenciais base em variáveis de ambiente (`AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) ou no `[default]` profile, **e já tem
permissão `sts:AssumeRole`** para a role de deploy.

#### Passo 2.1 — Apenas preencha `terraform.tfvars`:
```hcl
# terraform.tfvars
aws_profile         = null            # Opcional: usar default profile ou env vars
aws_assume_role_arn = "arn:aws:iam::123456789012:role/ToggleMasterDeployRole"
aws_assume_role_session_name = "terraform-toggle-master-local"
```
É isso. O provider automaticamente faz `sts:AssumeRole` na sua role antes de qualquer chamada.

---

## 🚀 Fluxo de Uso Diário (4 comandos)

Tudo é feito **sempre dentro da pasta `terraform/`**.

```bash
cd terraform/

# (1 vez, ou após mudar providers/modules) Inicializa o diretório, baixa
# provider hashicorp/aws ~> 5.30 e baixa os módulos locais.
terraform init

# (Opcional, bom prática) Formata todos arquivos .tf de forma padronizada.
terraform fmt -recursive

# (Sempre antes de apply) Visualiza as alterações QUE SERÃO FEITAS (sem mudar nada!).
terraform plan

# Aplica as alterações (pergunta confirmação). Custa $$$ REAL na AWS.
terraform apply
```

### Atalhos automatizados (scripts do time):
- `./apply.sh` — executa `fmt → init → plan → apply` (pede confirmação antes de aplicar).
- `./destroy.sh` — executa `terraform destroy` (pede escrever `DESTROY-TOGGLE-MASTER` em maiúsculas para confirmar).

```bash
# Mais simples para iniciantes:
chmod +x apply.sh destroy.sh
./apply.sh          # sobe tudo
# .
# . 30-40 minutos depois (RDS + Elasticache demoram ~15min para create)
#
./destroy.sh        # NÃO ESQUEÇA DE RODAR NO FIM DO DIA (evita cobrança RDS/Elasticache!)
```

---

## ⚠️ Dicas Cruciais (Economia $ + Não Ficar Travado)

1.  **NÃO DEIXE RECURSOS RODANDO SEM USO!**
    -   3 RDS db.t3.micro single-AZ free tier → 12 meses grátis, mas se não for free tier
        custa ~$0.02/h ($14/mês) CADA.
    -   1 ElastiCache cache.t4g.micro → ~$0.016/h ($11/mês).
    -   NAT Gateway (1 única) → ~$0.045/h + ~$0.045/GB processado (~$32/mês fixo SÓ o NAT).
    -   **Sempre rodar `./destroy.sh` no FIM DO DIA DE ESTUDO.**

2.  **⚠️ COMPORTAMENTO IMPORTANTE DOS ECR (REPOSITÓRIOS DOCKER):**
    -   **Destroy:** quando você roda `./destroy.sh`, **os 5 repositórios ECR (`toggle-master-*-service`) são **APAGADOS COMPLETAMENTE**, **JUNTAMENTE COM TODAS AS IMAGENS DENTRO DELES.**
    -   **Apply (daqui a 3 dias / próxima sessão de estudo):** os 5 ECR são **CRIADOS DE NOVO, VAZIOS** (zero imagens).
    -   **O que fazer antes de Deployar no EKS (Sprint 2)?**
        1.  Build local das 5 imagens Docker (reaproveita cache build, rápido).
        2.  `aws ecr get-login-password` + `docker login` no seu registry `128432678106.dkr.ecr.us-east-1.amazonaws.com`.
        3.  `docker tag` 5 imagens com o prefixo do ECR + `docker push` de cada uma.
        4.  (Na Sprint 2 criaremos um `push-all-images-to-ecr.sh` automatizado que faz tudo em 3 minutos!)
    -   **Não se preocupe agora:** na Sprint 2, antes do EKS, rodamos esse script em 3 minutos. Nenhuma imagem é "preciosa" — todas vem do Dockerfile do código fonte local.

3.  **NÃO COMMITE** `terraform.tfvars`, `*.tfplan*`, `*.tfstate*`, `.terraform/`
    no git. O `.gitignore` do repositório já deveria bloqueá-los.

4.  **Se quiser state compartilhado do time:** descomente o bloco `backend "s3"` em
    `versions.tf` e crie um bucket S3 + tabela DynamoDB `terraform-locks` com
    `LockID (String)` como PK.

5.  **Credenciais expirando?** (STSError 403 Expired)  
    Se usar AWS SSO: `aws sso login --sso-session ...`. Se usar assume_role 1h: basta re-executar
    o `terraform plan` (provider faz novo STS automaticamente).

---

## 📤 Outputs Disponíveis Depois do Apply

Depois do `terraform apply`, use `terraform output` para ver todos recursos criados,
suas URLs e connection strings — estas serão coladas depois nos Secrets Kubernetes da Sprint 2:

-   `vpc_id`, `public_subnet_ids`, `private_subnet_ids`, `nat_gateway_ids`
-   `ecr_repo_uris` — map com as 5 URLs dos repositórios ECR (fazer docker push).
-   `rds_auth_endpoint`, `rds_flags_endpoint`, `rds_targeting_endpoint`, cada um com
    senha gerada aleatória via `terraform output rds_auth_password -raw`.
-   `redis_primary_endpoint_address` + `redis_port`
-   `sqs_events_queue_url`, `sqs_events_queue_arn`, `sqs_dlq_url` / `_arn`
-   `dynamodb_analytics_table_name`, `dynamodb_analytics_table_arn`

---

## 🗂️ Estrutura de Pastas

```
terraform/
├── versions.tf              required_version, required_providers, backend S3 (comentado), provider AWS + random, assume_role
├── variables.tf             TODAS variáveis (tags, VPC, instâncias, autenticação)
├── main.tf                  6 módulos (networking / ecr / rds×3 / elasticache / sqs / dynamodb)
├── outputs.tf               TODOS outputs consumíveis Sprint 2
├── terraform.tfvars.example Modelo p/ copiar → terraform.tfvars
├── apply.sh / destroy.sh    Scripts padrão do time
├── README.md                ESTE arquivo
└── modules/
    ├── networking/          VPC, IGW, NAT, RTs, SGs base
    ├── ecr/                 5 repositórios privados
    ├── rds/                 1 instância RDS PostgreSQL reutilizável
    ├── elasticache/         1 cluster Redis + SG
    ├── sqs/                 Standard Queue + DLQ + Policy
    └── dynamodb/            Tabela eventos + 3 GSIs
```

---

## 🆘 Troubleshooting Rápido

| Sintoma | Como resolver |
|---|---|
| `Error: Failed to assume role... AccessDenied` | Trust Policy da role `ToggleMasterDeployRole` não permite `sts:AssumeRole` da sua identidade. Ajuste Trust Policy (exemplo acima). |
| `Error: NoCredentialProviders...` | Nenhuma credencial base encontrada. `aws sts get-caller-identity` (sem profile) deve funcionar OU `aws_profile` / `AWS_PROFILE` deve estar setado corretamente. |
| `Provider produced inconsistent result after apply (RDS)` | RDS demora 15-20 min para available; pode acontecer timeout. Rode `terraform apply` NOVAMENTE em 5 minutos (estado vai sincronizar). |
| `Error creating SecurityGroup: InvalidGroup.Duplicate` | Em casos de destroy falho, SGs ficam órfãos. Apague manualmente no Console VPC Security Groups com a tag `ManagedBy=Terraform` e re-apply. |
| `RDS password vazia?` | Rode `terraform output -raw rds_auth_password` (as senhas são marcadas `sensitive=true` no output). |
| `terraform init: modules not found` | Rode `terraform get` para atualizar cache de módulos locais. |
