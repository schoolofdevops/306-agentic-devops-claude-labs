variable "project" {
  description = "Project name used as a prefix for resource naming and tagging."
  type        = string
  default     = "northstar"
}

variable "environment" {
  description = "Deployment environment name (e.g. dev, staging, prod)."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for application instances."
  type        = string
  default     = "t3.small"
}

variable "ami_id" {
  description = "AMI ID to use for the application launch template."
  type        = string
  default     = "ami-0c55b159cbfafe1f0"
}

variable "min_size" {
  description = "Minimum number of instances in the autoscaling group."
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of instances in the autoscaling group."
  type        = number
  default     = 3
}

variable "desired_capacity" {
  description = "Desired number of instances in the autoscaling group."
  type        = number
  default     = 1
}

variable "subnet_ids" {
  description = "Subnet IDs (private) for the autoscaling group instances."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Subnet IDs (public) for the application load balancer."
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC ID the target group belongs to."
  type        = string
}

variable "security_group_ids" {
  description = "Security group IDs to attach to app instances and the load balancer."
  type        = list(string)
}
