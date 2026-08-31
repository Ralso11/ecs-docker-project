variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Name used to prefix and tag all resources in this project"
  type        = string
  default     = "ecs-docker-project"
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "IP address range for the VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "public_subnet_cidr" {
  description = "IP address range for the public subnet"
  type        = string
  default     = "10.1.1.0/24"
}

variable "container_port" {
  description = "Port the Flask app listens on inside the container"
  type        = number
  default     = 8080
}

variable "task_cpu" {
  description = "CPU units for the Fargate task (256 = 0.25 vCPU, the smallest option)"
  type        = string
  default     = "256"
}

variable "task_memory" {
  description = "Memory (in MB) for the Fargate task"
  type        = string
  default     = "512"
}
