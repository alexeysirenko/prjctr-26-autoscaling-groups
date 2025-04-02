variable "name_tag" {
  description = "prefix for the tags and names"
}

variable "region" {
  description = "AWS region for deployment"
  type        = string
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}

variable "ecr_image_uri" {
  description = "URI of the ECR image to deploy"
}

variable "min_tasks" {
  default     = 2
  description = "Minimum number of ECS tasks"
}

variable "max_tasks" {
  default     = 3
  description = "Maximum number of ECS tasks"
}

variable "task_cpu" {
  description = "CPU units for the ECS task"
}

variable "task_memory" {
  description = "Memory for the ECS task"
}

variable "alb_internal" {
  default     = false
  description = "Whether the ALB is internal"
}

variable "app_port" {
  description = "The port the application is running on."
  type        = number
  default     = 5000
}

variable "host_port" {
  description = "The port the ALB listener uses."
  type        = number
  default     = 80
}

variable "log_level" {
  default     = "INFO"
  description = "App log level"
}

variable "instance_type" {
  description = "EC2 instance type for ECS hosts"
  default     = "t3.medium"
}

variable "instance_type_alt1" {
  description = "Alternative EC2 instance type for better spot availability"
  default     = "t3a.medium"
}

variable "instance_type_alt2" {
  description = "Secondary alternative EC2 instance type for better spot availability"
  default     = "m5.large"
}

variable "target_requests_per_instance" {
  description = "Target number of requests per instance"
  type        = number
  default     = 500
}
