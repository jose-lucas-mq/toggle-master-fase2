resource "aws_ecr_repository" "this" {
  count                = length(var.repos)
  name                 = "${var.name_prefix}-${var.repos[count.index].name}"
  image_tag_mutability = var.repos[count.index].image_tag_mutability
  force_delete         = true
  image_scanning_configuration {
    scan_on_push = var.repos[count.index].scan_on_push
  }
  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-ecr-${var.repos[count.index].name}"
    Component = "ecr"
  })
  # Expose friendly name (stripping prefix) via for_each-friendly.
  provisioner "local-exec" {
    when    = destroy
    command = "echo 'Removendo imagens do ECR ${self.name} antes de delete...'"
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  count      = length(aws_ecr_repository.this)
  repository = aws_ecr_repository.this[count.index].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only the last N tagged images; expire untagged after 7 days."
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "main-", "sha-"]
          countType     = "imageCountMoreThan"
          countNumber   = var.repos[count.index].keep_last_n_images
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images after 7 days."
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      }
    ]
  })
}
