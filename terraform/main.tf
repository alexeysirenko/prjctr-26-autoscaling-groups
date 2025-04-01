locals {
  cluster_name                    = "${var.name_tag}-ec2-cluster"
  application_load_balancer_name  = "${var.name_tag}-alb"
  aws_lb_target_group_name        = "${var.name_tag}-target-group"
  ecs_task_execution_role_name    = "${var.name_tag}-execution-role"
  ecs_task_role_name              = "${var.name_tag}-task-role"
  ecs_instance_role_name          = "${var.name_tag}-instance-role"
  ecs_instance_profile_name       = "${var.name_tag}-instance-profile"
  ecs_execution_policy_name       = "${var.name_tag}-policy"
  ecs_task_definition_family      = "${var.name_tag}-task-family"
  container_name                  = "${var.name_tag}-container"
  ecs_service_name                = "${var.name_tag}-service"
  capacity_provider_name          = "${var.name_tag}-capacity-provider"
  asg_name                        = "${var.name_tag}-asg"
  launch_template_name            = "${var.name_tag}-launch-template"
}

provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Get latest Amazon ECS-optimized AMI
data "aws_ami" "ecs_optimized" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name      = "${var.name_tag}-vpc"
    ManagedBy = "Terraform"
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

  vpc_id                  = aws_vpc.main.id
  cidr_block              = element(var.public_subnet_cidrs, count.index)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name_tag}-public-subnet-az-${element(data.aws_availability_zones.available.names, count.index)}"
  }
}

resource "aws_eip" "nat_gateway" {
  domain = "vpc"
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
    cidr_block     = "0.0.0.0/0"
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

resource "aws_security_group" "ecs_instance_sg" {
  name_prefix = "${var.name_tag}-ecs-instance-sg-"
  description = "Security group for ECS EC2 instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_tag}-ecs-instance-sg"
  }
}

resource "aws_security_group" "alb_sg" {
  name_prefix = "${var.name_tag}-alb-sg-"
  description = "Allow HTTP access for ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = var.host_port
    to_port     = var.host_port # var.host_port
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

# IAM Role for EC2 instances
resource "aws_iam_role" "ecs_instance_role" {
  name = local.ecs_instance_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_ec2_role" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = local.ecs_instance_profile_name
  role = aws_iam_role.ecs_instance_role.name
}

# ECS Task Role
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

# ECS Task Execution Role
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
    name = local.ecs_execution_policy_name
    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Effect = "Allow",
          Action = [
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

# CloudWatch Log Group for ECS
resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/${var.name_tag}/${local.container_name}"
  retention_in_days = 7

  tags = {
    Service = local.ecs_service_name
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = local.cluster_name
}

# Launch Template
resource "aws_launch_template" "ecs" {
  name          = local.launch_template_name
  image_id      = data.aws_ami.ecs_optimized.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }

  vpc_security_group_ids = [aws_security_group.ecs_instance_sg.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${aws_ecs_cluster.main.name} >> /etc/ecs/ecs.config
    echo ECS_ENABLE_SPOT_INSTANCE_DRAINING=true >> /etc/ecs/ecs.config
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.name_tag}-ecs-instance"
    }
  }

  monitoring {
    enabled = true
  }
}

# Auto Scaling Group with mixed instances
resource "aws_autoscaling_group" "ecs" {
  name                = local.asg_name
  vpc_zone_identifier = aws_subnet.private_subnets[*].id
  min_size            = var.min_tasks  # Minimum size is 1 for the on-demand instance
  max_size            = var.max_tasks
  desired_capacity    = var.min_tasks

  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = 1         # 1 on-demand instance as base
      on_demand_percentage_above_base_capacity = 0         # Rest are spot instances
      spot_allocation_strategy                 = "capacity-optimized"
      spot_instance_pools                      = 0         # Use with capacity-optimized strategy
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.ecs.id
        version            = "$Latest"
      }

      # Optional: add instance type overrides for better spot availability
      override {
        instance_type = var.instance_type
      }

      # Add additional similar instance types for better spot availability
      override {
        instance_type = var.instance_type_alt1
      }

      override {
        instance_type = var.instance_type_alt2
      }
    }
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = ""
    propagate_at_launch = true
  }

  protect_from_scale_in = true  # Let ECS manage instance termination

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_ecs_capacity_provider" "main" {
  name = local.capacity_provider_name

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs.arn
    managed_termination_protection = "ENABLED"

    managed_scaling {
      maximum_scaling_step_size = 2
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 80  # Target 80% cluster utilization
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "cluster_capacity_providers" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = [aws_ecs_capacity_provider.main.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.main.name
    weight            = 100
    base              = 1
  }
}

resource "aws_ecs_task_definition" "task" {
  family                   = local.ecs_task_definition_family
  network_mode             = "bridge"  # Use bridge for EC2 launch type
  requires_compatibilities = ["EC2"]
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
          hostPort      = 0 #0  # Dynamic port mapping for EC2 launch type
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
  name        = local.aws_lb_target_group_name
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"  # Change to instance for EC2 launch type

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200-399"  # Acceptable HTTP response codes
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

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.main.name
    weight            = 100
    base              = 1
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = local.container_name
    container_port   = var.app_port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  # We need to manage the autoscaling group separately
  lifecycle {
    ignore_changes = [desired_count]
  }
}

output "alb_dns_name" {
  description = "Public DNS name of the ALB"
  value       = aws_lb.application_load_balancer.dns_name
}