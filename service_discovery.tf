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

data "aws_subnet" "this" {
  count = length(var.subnets) > 0 ? 1 : 0
  id = sort(var.subnets)[0]
}