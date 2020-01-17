locals {
  create_repositories = [
    for repository in var.repositories :
    repository
    if lookup(repository, "repo", "") == ""
  ]

  add_repositories = [
    for repository in var.repositories :
    repository
    if lookup(repository, "repo", "") != ""
  ]
}

resource "aws_ecr_repository" "this" {
  count = length(local.create_repositories)
  name  = trim(lower(join("/", [local.app, local.service, element(local.create_repositories, count.index).name])), "/")

  image_tag_mutability = element(local.create_repositories, count.index).mutability

  image_scanning_configuration {
    scan_on_push = element(local.create_repositories, count.index).scan
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  count = length(local.create_repositories)
  repository = element(aws_ecr_repository.this, count.index).name

  policy = <<EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Expire untagged images older than ${element(local.create_repositories, count.index).untagged_expiration} days",
            "selection": {
                "tagStatus": "untagged",
                "countType": "sinceImagePushed",
                "countUnit": "days",
                "countNumber": ${element(local.create_repositories, count.index).untagged_expiration}
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
EOF
}

resource "aws_iam_policy" "ecr" {
  count = local.task != "" ? 0 : 1  
  name   = "${local.id}-ECR"
  description = "Access to ECR for ${local.id} service"
  policy = data.aws_iam_policy_document.ecr.0.json
}

resource "aws_iam_role_policy_attachment" "ecr" {
  count = local.task != "" ? 0 : 1  
  role = aws_iam_role.this.0.name
  policy_arn = aws_iam_policy.ecr.0.arn
}

data "aws_iam_policy_document" "ecr" {
  count = local.task != "" ? 0 : 1  
  statement {
    actions = [
      "ecr:GetAuthorizationToken"
    ]

    resources = ["*"]
  }  
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer"
    ]

    resources = concat(aws_ecr_repository.this.*.arn, data.aws_ecr_repository.this.*.arn)
  }
}

data "aws_ecr_repository" "this" {
  count = length(local.add_repositories) 
  name = lower(element(local.add_repositories, count.index).repo)
}