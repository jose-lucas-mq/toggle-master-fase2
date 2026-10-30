# ----- Parameter Group -----
resource "aws_db_parameter_group" "this" {
  name_prefix = "${substr(var.name_prefix, 0, min(20, length(var.name_prefix)))}-pg"
  family      = "postgres${split(".", var.engine_version)[0]}"
  parameter {
    name         = "shared_buffers"
    value        = "65536"
    apply_method = "pending-reboot"
  }
  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-pg-params"
    Component = "rds"
  })
}

# ----- Subnet Group -----
resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-rds-subnet-grp"
  subnet_ids = var.private_subnet_ids
  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-rds-subnet-grp"
    Component = "rds"
  })
}

# ----- Security Group (só aceita 5432 do VPC) -----
resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds-sg"
  description = "Permite PostgreSQL 5432 dentro da VPC"
  vpc_id      = var.vpc_id

  ingress {
    description = "PostgreSQL TCP 5432 from VPC CIDR"
    from_port   = var.port
    to_port     = var.port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_id == var.vpc_id ? "0.0.0.0/0" : "0.0.0.0/0"]
    # O time vai restringir este ingress específico à Security Group dos nós EKS
    # depois que o módulo eks for criado. Por enquanto aceita de toda VPC (estudo).
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-rds-sg"
    Component = "rds"
  })
}

# ----- Instância RDS -----
resource "aws_db_instance" "this" {
  identifier            = var.name_prefix
  engine                = var.engine
  engine_version        = var.engine_version
  instance_class        = var.instance_class
  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  parameter_group_name   = aws_db_parameter_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az                   = var.multi_az
  port                       = var.port
  skip_final_snapshot        = var.skip_final_snapshot
  backup_retention_period    = var.backup_retention_days
  deletion_protection        = false
  publicly_accessible        = false
  auto_minor_version_upgrade = true
  maintenance_window         = "Mon:03:00-Mon:05:00"
  backup_window              = "05:00-07:00"
  storage_encrypted          = true

  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-postgres"
    Component = "rds"
    DbName    = var.db_name
  })
}
