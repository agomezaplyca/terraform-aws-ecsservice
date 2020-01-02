output "repositories" {
  value = zipmap(var.repositories.*.name, aws_ecr_repository.this.*.repository_url)
}

output "role" {
  value = aws_iam_role.this.*.name
}