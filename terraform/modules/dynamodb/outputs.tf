output "table_name" { value = aws_dynamodb_table.analytics.name }
output "table_arn" { value = aws_dynamodb_table.analytics.arn }
output "table_id" { value = aws_dynamodb_table.analytics.id }
output "gsi_names" {
  value = {
    gsi_flag_timestamp = var.create_gsis ? "GSI_FlagName_Timestamp" : ""
    gsi_user_flag      = var.create_gsis ? "GSI_UserId_FlagName" : ""
    gsi_result_flag    = var.create_gsis ? "GSI_Result_FlagName" : ""
  }
}
