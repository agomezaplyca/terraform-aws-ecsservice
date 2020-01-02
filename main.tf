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

resource "aws_ecr_repository" "this" {
  count = length(var.repositories)
  name  = trim(lower(join("/", [local.app, local.service, element(var.repositories, count.index).name])), "/")

  image_tag_mutability = element(var.repositories, count.index).mutability

  image_scanning_configuration {
    scan_on_push = element(var.repositories, count.index).scan
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  count = length(var.repositories)
  repository = element(aws_ecr_repository.this, count.index).name

  policy = <<EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Expire untagged images older than ${element(var.repositories, count.index).untagged_expiration} days",
            "selection": {
                "tagStatus": "untagged",
                "countType": "sinceImagePushed",
                "countUnit": "days",
                "countNumber": ${element(var.repositories, count.index).untagged_expiration}
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
EOF
}

resource "aws_ecs_task_definition" "this" {
  count = local.task != "" ? 0 : 1
  family  = local.id
  container_definitions = data.template_file.this.0.rendered

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
  #execution_role_arn = aws_iam_role.this.0.arn
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

resource "aws_service_discovery_service" "this" {
  count = var.network_mode == "awsvpc" && var.discovery["namespace"] != ""? 1 : 0
  name = lower(join(".", [local.env, local.service]))
  description = "Service discovery for ${local.name}"   

  dns_config {
    namespace_id = var.discovery["namespace"]

    dns_records {
      ttl  = var.discovery["dns_ttl"]
      type = var.discovery["dns_type"]
    }

    routing_policy = "MULTIVALUE"
  }

}

resource "aws_security_group" "this" {
  count = var.network_mode == "awsvpc"? 1 : 0
  name = local.id
  description = "Ports open for ${local.id} ECS service"
  vpc_id = data.aws_subnet.this.0.vpc_id

  ingress {
    from_port = var.task_vars["container_port"] 
    to_port = var.task_vars["container_port"] 
    protocol = "tcp"
    security_groups = var.inbound_security_groups
    description = "Open port from ECS Services"
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = local.tags
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
  #source  = "Aplyca/cloudwatchlogs/aws"
  #version = "0.3.0"

  source = "github.com/Aplyca/terraform-aws-cloudwatchlogs"

  name    = local.task == "" ? local.id : ""
  role = local.task == "" ? aws_iam_role.this.0.name : "" 
  description = "${local.name} ECSTask CloudWatch Logs"
  tags = local.tags
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

resource "aws_iam_policy" "ssm_parameter_store" {
  count = local.task != "" ? 0 : 1
  name   = "${local.id}-SSMParameterStore"
  description = "Access to SSM Parameter Store for ${local.id} parameters only"
  policy = data.aws_iam_policy_document.ssm_parameter_store.0.json
}

resource "aws_iam_role_policy_attachment" "ssm_parameter_store" {
  count = local.task != "" ? 0 : 1
  role = aws_iam_role.this.0.name
  policy_arn = aws_iam_policy.ssm_parameter_store.0.arn
}

resource "aws_iam_policy" "ecr" {
  count = local.task != "" ? 0 : 1  
  name   = "${local.id}-ECR"
  description = "Access to ECR for ${local.id}"
  policy = data.aws_iam_policy_document.ecr.0.json
}

resource "aws_iam_role_policy_attachment" "ecr" {
  count = local.task != "" ? 0 : 1  
  role = aws_iam_role.this.0.name
  policy_arn = aws_iam_policy.ecr.0.arn
}

resource "aws_alb_target_group" "default" {
  count = var.balancer["name"] != "" ? 1 : 0
  name     = local.id
  port     = 80
  protocol = var.balancer["protocol"]
  vpc_id = data.aws_alb.this.0.vpc_id
  deregistration_delay = 3
  target_type = var.network_mode != "awsvpc" ? var.target_type : "ip"

  dynamic "health_check" {
    for_each = list(var.balancer)
    
    content {
      port = "traffic-port"
      path = var.balancer["path"]
      healthy_threshold = var.balancer["healthy_threshold"]
      unhealthy_threshold = var.balancer["unhealthy_threshold"]
      interval = var.balancer["interval"]
      timeout = var.balancer["timeout"]      
      protocol = var.balancer["protocol"]
    }
  }

  stickiness {
    type = "lb_cookie"
    enabled = false
  }

  tags = local.tags
}

resource "aws_lb_listener_rule" "this" {
  count = length(var.listener_rules)  
  listener_arn =  element(data.aws_alb_listener.this, count.index).arn

  action {
    type = "forward"
    target_group_arn = aws_alb_target_group.default.0.arn
  }

  condition {
    host_header {
      values = split(",", element(var.listener_rules, count.index).values)
    }
  }
}


