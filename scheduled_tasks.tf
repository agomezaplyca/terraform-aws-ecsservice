resource "aws_cloudwatch_event_rule" "this" {
  count = length(var.scheduled_tasks)

  name        = "${local.id}-${element(var.scheduled_tasks, count.index).name}"
  description = element(var.scheduled_tasks, count.index).description
  schedule_expression = element(var.scheduled_tasks, count.index).schedule
}

resource "aws_cloudwatch_event_target" "this" {
  count = length(var.scheduled_tasks)

  target_id = "${local.id}-${element(var.scheduled_tasks, count.index).name}"
  arn       = data.aws_ecs_cluster.this.arn
  rule      = "${local.id}-${element(var.scheduled_tasks, count.index).name}"
  role_arn  = data.aws_iam_role.ecs_events.arn

  ecs_target {
    launch_type         = "EC2"
    task_count          = 1
    task_definition_arn = local.task != "" ? local.task : "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:task-definition/${aws_ecs_task_definition.this.0.family}"

    dynamic "network_configuration" {
      for_each = var.network_mode == "awsvpc" ? ["awsvpc"] : [] 

      content {
        subnets = var.subnets
        security_groups = concat(aws_security_group.this.*.id, var.outbound_security_groups)
      }  
    }
  }

  input = <<DOC
{
  "containerOverrides": [
    {
      "name": "${element(var.scheduled_tasks, count.index).container_name}",
      "command": ${element(var.scheduled_tasks, count.index).command}    
    }
  ]
}
DOC

  depends_on = [
    aws_cloudwatch_event_rule.this
  ]

}


data "aws_ecs_cluster" "this" {
  cluster_name = var.cluster
}

data "aws_iam_role" "ecs_events" {
  name = "ecsEventsRole"
}