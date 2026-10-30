# ----- Parameter Group Redis -----
resource "aws_elasticache_parameter_group" "this" {
  name   = "${var.name_prefix}-redis-params"
  family = var.parameter_group_family
  tags   = merge(var.tags, { Name = "${var.name_prefix}-redis-params" })
}

# ----- Subnet Group -----
resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.name_prefix}-redis-subnet-grp"
  subnet_ids = var.private_subnet_ids
  tags       = merge(var.tags, { Name = "${var.name_prefix}-redis-subnet-grp" })
}

# ----- Security Group Redis (6379 interno à VPC) -----
resource "aws_security_group" "redis" {
  name        = "${var.name_prefix}-redis-sg"
  description = "Permite Redis 6379 dentro da VPC"
  vpc_id      = var.vpc_id
  ingress {
    description = "Redis TCP 6379 de CIDR VPC"
    from_port   = var.port
    to_port     = var.port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-redis-sg"
    Component = "elasticache"
  })
}

# ----- Replica Group (compatible com Multi-AZ / sharding) -----
resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.name_prefix}-redis"
  description          = "Redis cluster hot path evaluation-service"

  engine               = var.engine
  engine_version       = var.engine_version
  node_type            = var.node_type
  port                 = var.port
  num_cache_clusters   = var.num_cache_nodes
  parameter_group_name = aws_elasticache_parameter_group.this.name
  subnet_group_name    = aws_elasticache_subnet_group.this.name
  security_group_ids   = [aws_security_group.redis.id]

  automatic_failover_enabled = var.automatic_failover_enabled
  multi_az_enabled           = false
  apply_immediately          = var.apply_immediately
  at_rest_encryption_enabled = true
  transit_encryption_enabled = false

  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-redis"
    Component = "elasticache"
  })
}
