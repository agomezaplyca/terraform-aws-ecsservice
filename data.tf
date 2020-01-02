data "template_file" "this" {
    count = local.task != "" ? 0 : 1  
    template = lookup(var.task_vars, "file", "task.json.tpl")
    vars = merge(var.task_vars, zipmap(var.repositories.*.name, aws_ecr_repository.this.*.repository_url), { "log_group" = module.logs.0.name, "region" = data.aws_region.current.name, "parameter-store-prefix" = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${local.id}-" })
}

data "aws_iam_policy_document" "ssm_parameter_store" {
  count = local.task != "" ? 0 : 1  
  statement {
    actions = ["ssm:DescribeParameters"]

    resources = ["*"]
  }

  statement {
    actions = [
      "ssm:GetParameters",
    ]

    resources = [
     "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${local.id}-*",
    ]
  }
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

    resources = aws_ecr_repository.this.*.arn
  }
}

#data "aws_iam_role" "service_ecs" {
#  name = "AWSServiceRoleForECS"
#}

data "aws_alb" "this" {
  count = var.balancer["name"] != "" ? 1 : 0
  name = var.balancer["name"]
}

data "aws_alb_listener" "this" {
  count = length(var.listener_rules)  
  load_balancer_arn = data.aws_alb.this.0.arn
  port = element(var.listener_rules, count.index).port
}

data "aws_subnet" "this" {
  count = length(var.subnets) > 0 ? 1 : 0
  id = sort(var.subnets)[0]
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

