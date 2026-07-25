module "networking" {
  source      = "../../modules/networking"
  environment = var.environment
  project     = var.project
}

module "compute" {
  source             = "../../modules/compute"
  environment        = var.environment
  project            = var.project
  instance_type      = var.instance_type
  min_size           = var.min_size
  max_size           = var.max_size
  desired_capacity   = var.desired_capacity
  subnet_ids         = module.networking.private_subnet_ids
  public_subnet_ids  = module.networking.public_subnet_ids
  vpc_id             = module.networking.vpc_id
  security_group_ids = [module.networking.app_security_group_id]
}

module "database" {
  source         = "../../modules/database"
  environment    = var.environment
  project        = var.project
  instance_class = var.db_instance_class
  db_password    = var.db_password
  subnet_ids     = module.networking.private_subnet_ids
  multi_az       = var.multi_az
}

module "storage" {
  source      = "../../modules/storage"
  environment = var.environment
  project     = var.project
}

variable "environment" {
  type = string
}

variable "project" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "db_instance_class" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "min_size" {
  type = number
}

variable "max_size" {
  type = number
}

variable "desired_capacity" {
  type = number
}

variable "multi_az" {
  type = bool
}
