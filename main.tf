locals {
  app = replace(var.task_vars["app_name"], " ", "")
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
  cpu = lookup(var.task_vars, "cpu", null)
  memory = lookup(var.task_vars, "memory", null)
  container_definitions = templatefile(lookup(var.task_vars, "file", "task.json.tpl"), merge(var.task_vars, zipmap(var.repositories.*.name, concat(aws_ecr_repository.this.*.repository_url, data.aws_ecr_repository.this.*.repository_url)), { "log_group" = local.id, "region" = data.aws_region.current.name}, {"parameter-store-prefix" = local.parameters_prefix}))

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

      # To use it you have to use an aws provider version equal or or greater than 3.1.0    
      dynamic "efs_volume_configuration" {
        for_each = lookup(volume.value, "efs_volume_configuration", null) == null ? [] : list(volume.value.efs_volume_configuration)
        content {
          file_system_id = efs_volume_configuration.value.file_system_id
          root_directory = lookup(efs_volume_configuration.value, "root_directory", null)
          transit_encryption      = "ENABLED"
          dynamic "authorization_config" {
            for_each = lookup(efs_volume_configuration.value, "authorization_config", null) == null ? [] : list(efs_volume_configuration.value.authorization_config)
            content {
              access_point_id = authorization_config.value.access_point_id
              iam             = "ENABLED"
            }
          }
        }
      }

    }
  }

  task_role_arn = aws_iam_role.task.0.arn
  execution_role_arn = aws_iam_role.execution.0.arn
  requires_compatibilities = var.compatibilities
  dynamic "placement_constraints" {
    for_each = var.placement_constraints.type != "" ? list(var.placement_constraints) : []
    content {
       type       = var.placement_constraints.type
       expression = var.placement_constraints.expression
    }
  }
  network_mode = var.network_mode  
  #tags = local.tags    
}

resource "aws_ecs_service" "this" {
  name            = local.id
  cluster         = data.aws_ecs_cluster.this.arn
  task_definition = local.task != "" ? local.task : aws_ecs_task_definition.this.0.arn
  desired_count   = var.desired
  health_check_grace_period_seconds = 0
  launch_type = var.launch_type
  enable_ecs_managed_tags = false
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
    for_each = var.network_mode == "awsvpc" && var.discovery["namespace"] != "" ? ["awsvpc"] : [] 

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

  dynamic "ordered_placement_strategy" {
    for_each = var.launch_type != "FARGATE" ? ["ec2"] : [] 

    content {
      type  = "spread"
      field = "host"
    }  
  }

  # Allow external changes without Terraform plan difference
  lifecycle {
    ignore_changes = [ desired_count ]
  }

  deployment_controller {
    type = "ECS"
  }

  #tags = local.tags  
}

resource "aws_iam_role" "task" {
  count = local.task != "" ? 0 : 1
  name = "${local.id}-Task"
  description = "${local.name} ECS Task"
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

resource "aws_iam_role" "execution" {
  count = local.task != "" ? 0 : 1
  name = "${local.id}-TaskExecution"
  description = "${local.name} ECS Task execution"
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
  role = local.task == "" ? aws_iam_role.execution.0.name : "" 
  description = "${local.name} ECSTask CloudWatch Logs"
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "execution" {
  count = local.task != "" ? 0 : 1  
  role = aws_iam_role.execution.0.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}