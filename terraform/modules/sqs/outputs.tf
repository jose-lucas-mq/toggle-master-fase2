output "queue_url" { value = aws_sqs_queue.main.id }
output "queue_arn" { value = aws_sqs_queue.main.arn }
output "dlq_url" { value = var.create_dlq ? aws_sqs_queue.dlq[0].id : "" }
output "dlq_arn" { value = var.create_dlq ? aws_sqs_queue.dlq[0].arn : "" }
output "queue_name" { value = aws_sqs_queue.main.name }
output "dlq_name" { value = var.create_dlq ? aws_sqs_queue.dlq[0].name : "" }
