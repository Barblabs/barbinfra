# An account can hold only one provider per URL, so every environment's deploy
# roles trust this one. AWS verifies GitHub's tokens against its own trusted
# CAs, so no thumbprints are needed.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# One repository for every environment, so the image tested in one is promoted
# unchanged to the next. Immutable tags keep a git SHA pointing at one image.
resource "aws_ecr_repository" "backend" {
  name                 = "barbackend"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}
