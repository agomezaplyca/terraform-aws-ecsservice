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
      matcher = lookup(var.balancer, "matcher", null)      
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

data "aws_alb" "this" {
  count = var.balancer["name"] != "" ? 1 : 0
  name = var.balancer["name"]
}

data "aws_alb_listener" "this" {
  count = length(var.listener_rules)  
  load_balancer_arn = data.aws_alb.this.0.arn
  port = element(var.listener_rules, count.index).port
}