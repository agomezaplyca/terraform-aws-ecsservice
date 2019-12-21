# Terraform AWS ECS Service module

Deploy al necessary resources for ECS apps

# Example of service

```HCL
module "my_service" {
  source  = "Aplyca/ecsdeploy/aws"
  version = "0.1.0"

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

  repositories = {
    web-image = ""
  }

  task_file = "task.json.tpl"
  task_vars = {
    app-tag = "master"
    app = "MyApp"
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

  tags = {
    App = "MyApp"
    Environment = "Production"
    Service = "Web"
  }
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
    "image": "${web-image}:${web-tag}",
    "links": ["App:app"]
  },
  {
    "name": "App",
    "portMappings": [{
      "hostPort": 0,
      "protocol": "tcp",
      "containerPort": 9000
    }],
    "mountPoints": [{
      "containerPath": "/mnt/storage",
      "sourceVolume": "MyApp-Storage"
    }],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${log_group}",
        "awslogs-region": "${region}",
        "awslogs-stream-prefix": "MyApp"
      }
    },
    "image": "${app-image}:${app-version}",
    "secrets": [{
        "name": "DATABASE_PASSWORD",
        "valueFrom": "${DATABASE_PASSWORD}"
      }
    ],
    "environment": [{
        "name": "DATABASE_HOST",
        "value": "db.mydomian.com"
      },
      {
        "name": "DATABASE_USER",
        "value": "user"
      }
    ]
  }
]
```

## Sample to include Placement Constraints

```
   placement_constraints {
    type       = "memberOf"
    expression = "attribute:ecs.availability-zone in [us-east-1a]"
  }
```
