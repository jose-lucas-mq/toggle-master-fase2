locals {
  main_queue_name = "${var.name_prefix}-events"
  dlq_queue_name  = "${var.name_prefix}-events-dlq"
}

# ----- Dead Letter Queue (opcional) -----
resource "aws_sqs_queue" "dlq" {
  count = var.create_dlq ? 1 : 0

  name                      = local.dlq_queue_name
  message_retention_seconds = 1209600 # 14 dias máximo
  delay_seconds             = 0
  receive_wait_time_seconds = var.long_polling_wait_seconds
  tags = merge(var.tags, {
    Name      = local.dlq_queue_name
    Purpose   = "dead-letter"
    Component = "sqs"
  })
}

# ----- Fila principal -----
resource "aws_sqs_queue" "main" {
  name                       = local.main_queue_name
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  delay_seconds              = 0
  receive_wait_time_seconds  = var.long_polling_wait_seconds

  # Redrive policy para a DLQ (se habilitada)
  # Provider AWS 5.x: redrive_policy é ATRIBUTO STRING JSON, não bloco dinâmico.
  # Se create_dlq=false, seta null (sem policy).
  redrive_policy = var.create_dlq ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[0].arn
    maxReceiveCount     = var.dlq_max_receive_count
  }) : null

  tags = merge(var.tags, {
    Name      = local.main_queue_name
    Purpose   = "evaluation-events"
    Component = "sqs"
  })
}
