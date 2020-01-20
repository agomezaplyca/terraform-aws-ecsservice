locals {
  app = replace(upper(var.task_vars["app_name"]), " ", "")
  service = replace(title(var.task_vars["service"]), " ", "")
  env = replace(title(var.task_vars["env"]), " ", "")
  container = replace(title(var.task_vars["container"]), " ", "")
  name = "${local.app} ${local.service} ${local.env}"
  id = replace(local.name, " ", "-")
  tags = {
    App = local.app
    Environment = local.env
    Service = local.service
    Name = local.name
  }
  task = lookup(var.task_vars, "task", "")
}

# --------------------------------------------------------
# CREATE New Service
# --------------------------------------------------------
resource "aws_ecs_task_definition" "this" {
  count = local.task != "" ? 0 : 1
  family  = local.id

  container_definitions = templatefile(lookup(var.task_vars, "file", "task.json.tpl"), merge(var.task_vars, zipmap(var.repositories.*.name, concat(aws_ecr_repository.this.*.repository_url, data.aws_ecr_repository.this.*.repository_url)), { "log_group" = module.logs.name.0, "region" = data.aws_region.current.name}, {"parameter-store-prefix" = local.parameters_prefix}))

  dynamic "volume" {
    for_each = var.volumes
    content {
      name      = volume.value.name
      host_path = lookup(volume.value, "host_path", null)

      dynamic "docker_volume_configuration" {
        for_each = lookup(volume.value, "docker", "") == "" ? [] : list(volume.value.docker)
        content {
          scope         = docker_volume_configuration.value
          autoprovision = true
          labels = {
            name = volume.value.name
            taks = local.id
          }
        }
      }
    }
  }

  task_role_arn = aws_iam_role.this.0.arn
  execution_role_arn = aws_iam_role.this.0.arn
  requires_compatibilities = var.compatibilities
  dynamic "placement_constraints" {
    for_each = var.placement_constraints.type != "" ? list(var.placement_constraints) : []
    content {
       type       = var.placement_constraints.type
       expression = var.placement_constraints.expression
    }
  }
  network_mode = var.network_mode  
}

resource "aws_ecs_service" "this" {
  name            = local.id
  cluster         = var.cluster
  task_definition = local.task != "" ? local.task : aws_ecs_task_definition.this.0.arn
  desired_count   = var.desired
  health_check_grace_period_seconds = 0
  launch_type = var.launch_type
  #iam_role = var.network_mode != "awsvpc" ? data.aws_iam_role.service_ecs.arn : ""

  dynamic "load_balancer" {
    for_each = var.balancer["name"] != "" ? [var.balancer] : [] 

    content {
      target_group_arn = aws_alb_target_group.default.0.arn
      container_name = var.task_vars["container"]
      container_port = var.task_vars["container_port"]
    }  
  }

  dynamic "service_registries" {
    for_each = var.network_mode == "awsvpc" ? ["awsvpc"] : [] 

    content {
      registry_arn = aws_service_discovery_service.this.0.arn
    }  
  }

  dynamic "network_configuration" {
    for_each = var.network_mode == "awsvpc" ? ["awsvpc"] : [] 

    content {
      subnets = var.subnets
      security_groups = concat(aws_security_group.this.*.id, var.outbound_security_groups)
    }  
  }

  ordered_placement_strategy {
    type  = "spread"
    field = "host"
  }

  # Allow external changes without Terraform plan difference
  #lifecycle {
  #  ignore_changes = [ desired_count ]
  #}
}

resource "aws_iam_role" "this" {
  count = local.task != "" ? 0 : 1
  name = local.id
  description = "${local.name} ECSTask"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

module "logs" {
  source  = "Aplyca/cloudwatchlogs/aws"
  version = "0.3.1"

  name    = local.task == "" ? local.id : ""
  role = local.task == "" ? aws_iam_role.this.0.name : "" 
  description = "${local.name} ECSTask CloudWatch Logs"
  retention_in_days = var.log_retention
  tags = local.tags
}