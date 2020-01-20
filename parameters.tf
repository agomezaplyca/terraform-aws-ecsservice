locals {  
  parameters_prefix = concat([local.id], lookup(var.task_vars, "parameter_prefix", "") != "" ? [var.task_vars["parameter_prefix"]] : [])
}

resource "aws_ssm_parameter" "parameters" {
  count = length(var.parameters)
  description = element(var.parameters, count.index).description
  name  = "${local.id}-${element(var.parameters, count.index).name}"
  type  = "String"
  value = " "
  lifecycle {
    ignore_changes = [
      value
    ]
  }
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

    resources = formatlist("arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/%s-*", local.parameters_prefix)
  }
}

resource "aws_iam_policy" "ssm_parameter_store" {
  count = local.task != "" ? 0 : 1
  name   = "${local.id}-SSMParameterStore"
  description = "Access to SSM Parameter Store for ${local.id} parameters only"
  policy = data.aws_iam_policy_document.ssm_parameter_store.0.json
}

resource "aws_iam_role_policy_attachment" "ssm_parameter_store" {
  count = local.task != "" ? 0 : 1
  role = aws_iam_role.execution.0.name
  policy_arn = aws_iam_policy.ssm_parameter_store.0.arn
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}