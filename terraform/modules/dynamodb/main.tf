locals {
  # PAY_PER_REQUEST ignora RC/WC. PROVISIONED usa valores das vars.
  capacity = var.billing_mode == "PROVISIONED" ? {
    read_capacity  = var.provisioned_read_capacity
    write_capacity = var.provisioned_write_capacity
  } : { read_capacity = null, write_capacity = null }
}

# ===== Tabela Principal =====
resource "aws_dynamodb_table" "analytics" {
  name           = var.table_name
  billing_mode   = var.billing_mode
  read_capacity  = local.capacity.read_capacity
  write_capacity = local.capacity.write_capacity
  table_class    = "STANDARD"
  server_side_encryption {
    enabled = true
  }

  # PK event_id
  hash_key = "event_id"
  attribute {
    name = "event_id"
    type = "S"
  }
  # Para GSIs (é obrigatório declarar attributes referenciados em índices).
  # Declaramos só os que existem. Tipos: S=String, N=Number, B=Binary.
  attribute {
    name = "flag_name"
    type = "S"
  }
  attribute {
    name = "timestamp"
    type = "S"
  }
  attribute {
    name = "user_id"
    type = "S"
  }
  attribute {
    name = "result"
    type = "S"
  }

  # IMPORTANTE: Não declarar attributes que SÓ existem como item livres (não são
  # PK, SK, GSI hash_key ou GSI range_key). O DynamoDB é schema-less para
  # attributes não-indexados — você grava quando quiser sem declarar.
  # Exemplo: ttl_epoch (atributo livre para TTL), evaluation_id etc. NÃO declarar.

  # ===== GSIs recomendados (consultas analíticas) =====
  dynamic "global_secondary_index" {
    for_each = var.create_gsis ? [1] : []
    content {
      name            = "GSI_FlagName_Timestamp"
      hash_key        = "flag_name"
      range_key       = "timestamp"
      projection_type = "ALL"
      read_capacity   = local.capacity.read_capacity
      write_capacity  = local.capacity.write_capacity
    }
  }
  dynamic "global_secondary_index" {
    for_each = var.create_gsis ? [1] : []
    content {
      name            = "GSI_UserId_FlagName"
      hash_key        = "user_id"
      range_key       = "flag_name"
      projection_type = "ALL"
      read_capacity   = local.capacity.read_capacity
      write_capacity  = local.capacity.write_capacity
    }
  }
  dynamic "global_secondary_index" {
    for_each = var.create_gsis ? [1] : []
    content {
      name            = "GSI_Result_FlagName"
      hash_key        = "result"
      range_key       = "flag_name"
      projection_type = "ALL"
      read_capacity   = local.capacity.read_capacity
      write_capacity  = local.capacity.write_capacity
    }
  }

  # ===== TTL =====
  dynamic "ttl" {
    for_each = var.ttl_enabled ? [1] : []
    content {
      attribute_name = var.ttl_attribute_name
      enabled        = true
    }
  }

  tags = merge(var.tags, {
    Name      = var.table_name
    Component = "dynamodb"
    Purpose   = "events-analytics"
  })
}
