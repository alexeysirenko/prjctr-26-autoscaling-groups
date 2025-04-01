name_tag                        = "test-dev"
region                          = "eu-central-1"
vpc_cidr_block                  = "10.0.0.0/16"
public_subnet_cidrs = [
  "10.0.1.0/24",
  "10.0.2.0/24",
  "10.0.3.0/24"
]
private_subnet_cidrs = [
  "10.0.4.0/24", 
  "10.0.5.0/24", 
  "10.0.6.0/24"
]
ecr_image_uri                   = "523717802721.dkr.ecr.eu-central-1.amazonaws.com/test-dev:latest"
min_tasks                       = 2
max_tasks                       = 3
task_cpu                        = 512
task_memory                     = 1024
alb_internal                    = false
app_port                        = 5000
host_port                       = 80
log_level                       = "INFO"
instance_type                   = "t3.medium"
instance_type_alt1              = "t3a.medium"
instance_type_alt2              = "m5.large"
