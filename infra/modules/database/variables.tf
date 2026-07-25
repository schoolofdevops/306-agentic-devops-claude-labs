variable "project" {
  description = "Project name used as a prefix for resource naming and tagging."
  type        = string
  default     = "northstar"
}

variable "environment" {
  description = "Deployment environment name (e.g. dev, staging, prod)."
  type        = string
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.r6g.large"
}

variable "allocated_storage" {
  description = "Initial allocated storage for the database, in GB."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Maximum storage RDS can autoscale to, in GB."
  type        = number
  default     = 100
}

variable "db_name" {
  description = "Name of the initial database created on the instance."
  type        = string
  default     = "orders"
}

variable "db_username" {
  description = "Master username for the database."
  type        = string
  default     = "orders"
}

variable "db_password" {
  description = "Master password for the database."
  type        = string
  sensitive   = true
}

variable "subnet_ids" {
  description = "Subnet IDs for the DB subnet group."
  type        = list(string)
}

variable "multi_az" {
  description = "Whether to deploy the database across multiple availability zones."
  type        = bool
  default     = false
}

variable "monitoring_interval" {
  description = "Enhanced monitoring interval in seconds (0 to disable)."
  type        = number
  default     = 0
}
