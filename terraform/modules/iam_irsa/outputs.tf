output "evaluation_pod_role_arn" {
  description = "ARN da role IRSA do pod evaluation-service (SQS SendMessage)."
  value       = aws_iam_role.evaluation_pod.arn
}

output "analytics_pod_role_arn" {
  description = "ARN da role IRSA do pod analytics-service (SQS consume + DynamoDB PutItem)."
  value       = aws_iam_role.analytics_pod.arn
}

output "keda_operator_role_arn" {
  description = "ARN da role IRSA do KEDA Operator (métricas SQS)."
  value       = aws_iam_role.keda_operator.arn
}

output "all_irsa_role_arns" {
  description = "Map com todas as ARNs das roles IRSA (útil para output raiz)."
  value = {
    evaluation = aws_iam_role.evaluation_pod.arn
    analytics  = aws_iam_role.analytics_pod.arn
    keda       = aws_iam_role.keda_operator.arn
  }
}
