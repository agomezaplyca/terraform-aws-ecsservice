output "repositories" {
  value = zipmap(local.create_repositories.*.name, aws_ecr_repository.this.*.repository_url)
}

output "role" {
  value = aws_iam_role.task.*.name
}

output "role_execution_id" {
  value       = aws_iam_role.execution.*.id
}

output "aws_alb_target_group_arn" {
  value = aws_alb_target_group.default.0.arn  
}
