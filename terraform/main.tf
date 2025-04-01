locals {
  cluster_name                    = "${var.name_tag}-fargate-cluster"
  application_load_balancer_name  = "${var.name_tag}-alb"
  aws_lb_target_group_name        = "${var.name_tag}-target-group"
  ecs_task_execution_role_name    = "${var.name_tag}-execution-role"
  ecs_task_role_name              = "${var.name_tag}-task-role"
  ecs_execution_policy_name       = "${var.name_tag}-policy"
  ecs_task_definition_family      = "${var.name_tag}-task-family"
  container_name                  = "${var.name_tag}-container"
  ecs_service_name                = "${var.name_tag}-service"
}

provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.name_tag}-vpc"
    ManagedBy   = "Terraform"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_tag}-igw"
  }
}

resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.public_subnet_cidrs, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name_tag}-public-subnet-az-${element(data.aws_availability_zones.available.names, count.index)}"
  }
}

resource "aws_eip" "nat_gateway" {
  vpc = true
  tags = {
    Name = "${var.name_tag}-nat-gateway-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat_gateway.id
  subnet_id     = aws_subnet.public_subnets[0].id

  tags = {
    Name = "${var.name_tag}-nat-gateway"
  }
}

resource "aws_subnet" "private_subnets" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name = "${var.name_tag}-private-subnet-az-${element(data.aws_availability_zones.available.names, count.index)}"
  }
}

resource "aws_default_route_table" "default" {
  default_route_table_id = aws_vpc.main.default_route_table_id

  tags = {
    Name   = "default-route-table-unused"
    Status = "Not Associated"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.name_tag}-public-route-table"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.name_tag}-private-route-table"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "ecs_task_sg" {
  name_prefix = "${var.name_tag}-ecs-task-sg-"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = var.app_port 
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_tag}-ecs-task-sg"
  }
}

resource "aws_security_group" "alb_sg" {
  name_prefix = "${var.name_tag}-alb-sg-"
  description = "Allow HTTP access for ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = var.host_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_tag}-alb-sg"
  }
}

resource "aws_ecs_cluster" "main" {
  name = local.cluster_name
}

resource "aws_iam_role" "ecs_task_role" {
  name = local.ecs_task_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = local.ecs_task_execution_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  inline_policy {
    name   = local.ecs_execution_policy_name
    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Effect   = "Allow",
          Action   = [
            "ecr:GetAuthorizationToken",
            "ecr:BatchCheckLayerAvailability",
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage",
            "s3:GetObject",
            "ecs:UpdateService",
          ],
          Resource = "*"
        }
      ]
    })
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/${var.name_tag}/${local.container_name}"
  retention_in_days = 7

  tags = {
    Service     = local.ecs_service_name
  }
}

resource "aws_ecs_task_definition" "task" {
  family                   = local.ecs_task_definition_family
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  cpu                      = var.task_cpu
  memory                   = var.task_memory

  container_definitions = jsonencode([
    {
      name      = local.container_name,
      image     = var.ecr_image_uri,
      cpu       = var.task_cpu,
      memory    = var.task_memory,
      essential = true,
      environment = [
        { name = "LOG_LEVEL", value = var.log_level },
        { name = "PORT", value = tostring(var.app_port) },
      ],
      portMappings = [
        {
          containerPort = var.app_port
          hostPort      = var.app_port
          protocol      = "tcp"
        }
      ],
      mountPoints = [],
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_log_group.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }      
    }
  ])
}

resource "aws_lb" "application_load_balancer" {
  name               = local.application_load_balancer_name
  internal           = var.alb_internal
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public_subnets[*].id

  tags = {
    Name = "${var.name_tag}-alb"
  }
}

resource "aws_lb_target_group" "main" {
  name       = local.aws_lb_target_group_name
  port       = var.app_port
  protocol   = "HTTP"
  vpc_id     = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${var.name_tag}-target-group"
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.application_load_balancer.arn
  port              = var.host_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  tags = {
    Name = "${var.name_tag}-lb-listener"
  }
}

resource "aws_ecs_service" "service" {
  name            = local.ecs_service_name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.task.arn
  desired_count   = var.min_tasks

  launch_type = "FARGATE"

  network_configuration {
    subnets         = aws_subnet.private_subnets[*].id
    security_groups = [aws_security_group.ecs_task_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = local.container_name
    container_port   = var.app_port
  }
}

resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = var.max_tasks
  min_capacity       = var.min_tasks
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "scale_cpu" {
  name               = "scale-cpu"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = "ecs"

  policy_type = "TargetTrackingScaling"
  target_tracking_scaling_policy_configuration {
    target_value       = 70.0 # Adjust as needed
    scale_in_cooldown  = 300
    scale_out_cooldown = 300
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

output "alb_dns_name" {
  description = "Public DNS name of the ALB"
  value       = aws_lb.application_load_balancer.dns_name
}
