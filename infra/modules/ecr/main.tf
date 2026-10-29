# ECR: Docker image registry for the .NET app
# ponytail: single repo. Add lifecycle policy when image count > 20.

variable "project" { type = string }

resource "aws_ecr_repository" "app" {
  name                 = "${var.project}-api"
  image_tag_mutability = "MUTABLE" # allows :latest tag overwrite
  force_delete         = true      # clean terraform destroy

  image_scanning_configuration {
    scan_on_push = true # free vulnerability scanning
  }

  tags = { Name = "${var.project}-api" }
}

output "repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "repository_name" {
  value = aws_ecr_repository.app.name
}

