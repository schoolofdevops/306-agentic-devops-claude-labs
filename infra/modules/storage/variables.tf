variable "project" {
  description = "Project name used as a prefix for resource naming and tagging."
  type        = string
  default     = "northstar"
}

variable "environment" {
  description = "Deployment environment name (e.g. dev, staging, prod)."
  type        = string
}

variable "account_id" {
  description = "AWS account ID, used to keep the S3 bucket name globally unique."
  type        = string
  default     = "123456789012"
}
