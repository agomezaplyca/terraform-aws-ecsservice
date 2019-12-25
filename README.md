# Terraform AWS ECS Service module

Deploy al necessary resources for ECS apps

# Example of service

```HCL
module "my_service" {
  source  = "Aplyca/ecsdeploy/aws"
  version = "0.1.1"

  cluster = "MYCLUSTER"
  desired = 1

  balancer = {
    name = "MyALB"
    path = "/healthcheck"
    healthy_threshold = "2"
    unhealthy_threshold = "3"
    interval = "30"
    timeout = "5"
    protocol = "HTTP"
  }

  repositories = [{
    name = "App"
    mutability = "MUTABLE"
    scan = true
  }]

  task_file = "task.json.tpl"
  task_vars = {
    app_tag = "master"
    app_name = "MyApp"
    service = "MyService"
    env = "Production"
    container = "Web"
    container_port = "80"
  }

  # Parameter value is not supported here. You should set the value manually from the AWS console.
  parameters = [{
    name = "DATABASE_PASSWORD"
    description = "Description of this parameter"
  }]

  volumes = [{
    name      = "MyApp-Storage"
    host_path = "/mnt/myapp-storage"
  }]
}
```

Example of a Task definition

```JSON
[{
    "name": "${container}",
    "portMappings": [{
        "hostPort": ${container_port},
        "protocol": "tcp",
        "containerPort": ${container_port}
    }],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${log_group}",
        "awslogs-region": "${region}",
        "awslogs-stream-prefix": "${service}"
      }
    },
    "image": "${App}:${app_tag}"
  }
]
```
