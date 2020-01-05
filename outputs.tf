output "repositories" {
  value = zipmap(local.create_repositories.*.name, aws_ecr_repository.this.*.repository_url)
}

output "role" {
  value = aws_iam_role.this.*.name
}