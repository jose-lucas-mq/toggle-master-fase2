# =============================================================================
# LOCAL: Extrai o HOST do OIDC issuer (sem "https://") p/ usar nas Trust Policies
#        Ex: https://oidc.eks.us-east-1.amazonaws.com/id/XXXX → oidc.eks...
# =============================================================================
locals {
  oidc_host = replace(var.oidc_issuer_url, "https://", "")
}

# =============================================================================
# 1) ROLE evaluation-service: evaluation-pod
#    Permite que o pod do evaluation-service enviar eventos p/ SQS (SendMessage)
# =============================================================================
resource "aws_iam_role" "evaluation_pod" {
  name        = "${var.name_prefix}-evaluation-pod-role"
  description = "Role IRSA do pod evaluation-service (envia eventos para SQS)."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:sub" = "system:serviceaccount:apps:evaluation-sa"
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(var.tags, { Name = "${var.name_prefix}-evaluation-pod-role" })
}

resource "aws_iam_role_policy" "evaluation_pod_sqs_send" {
  name = "${var.name_prefix}-evaluation-pod-sqs-send"
  role = aws_iam_role.evaluation_pod.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:SendMessage",
        "sqs:GetQueueUrl"
      ]
      Resource = var.sqs_events_queue_arn
    }]
  })
}

# =============================================================================
# 2) ROLE analytics-pod: analytics-service
#    Permite consumir SQS (Receive/Delete) + gravar DynamoDB (PutItem)
# =============================================================================
resource "aws_iam_role" "analytics_pod" {
  name        = "${var.name_prefix}-analytics-pod-role"
  description = "Role IRSA do pod analytics-service (consome SQS e grava DynamoDB)."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:sub" = "system:serviceaccount:apps:analytics-sa"
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(var.tags, { Name = "${var.name_prefix}-analytics-pod-role" })
}

resource "aws_iam_role_policy" "analytics_pod_sqs_consume" {
  name = "${var.name_prefix}-analytics-pod-sqs-consume"
  role = aws_iam_role.analytics_pod.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = [
          var.sqs_events_queue_arn,
          var.sqs_dlq_arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = var.dynamodb_table_arn
      }
    ]
  })
}

# =============================================================================
# 3) ROLE keda-operator
#    Permite ao KEDA (auto-scaler consultar a profundidade da fila SQS (métricas)
# =============================================================================
resource "aws_iam_role" "keda_operator" {
  name        = "${var.name_prefix}-keda-operator-role"
  description = "Role IRSA do KEDA Operator (consulta métricas SQS para escalar analytics)."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:sub" = "system:serviceaccount:keda:keda-operator"
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(var.tags, { Name = "${var.name_prefix}-keda-operator-role" })
}

resource "aws_iam_role_policy" "keda_operator_sqs_metrics" {
  name = "${var.name_prefix}-keda-operator-sqs-metrics"
  role = aws_iam_role.keda_operator.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:GetQueueAttributes",
        "sqs:ListQueues"
      ]
      Resource = var.sqs_events_queue_arn
    }]
  })
}
