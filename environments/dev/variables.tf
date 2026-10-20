# ---------------------------------------------------------------
# General
# ---------------------------------------------------------------
variable "project" {
  type = string
}

variable "environment" {
  description = "dev or prod"
  type        = string
}

variable "region" {
  type = string
}

variable "azs" {
  type = list(string)
}

# ---------------------------------------------------------------
# Network
# ---------------------------------------------------------------
variable "vpc_cidr" {
  type = string
}

variable "frontend_subnet_cidrs" {
  type = list(string)
}

variable "compute_subnet_cidrs" {
  type = list(string)
}

variable "data_subnet_cidrs" {
  type = list(string)
}

variable "single_nat_gateway" {
  type = bool
}

variable "enable_interface_endpoints" {
  type = bool
}

# ---------------------------------------------------------------
# EKS
# ---------------------------------------------------------------
variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "eks_public_access_cidrs" {
  type = list(string)
}

variable "cluster_admin_arns" {
  type    = list(string)
  default = []
}

variable "node_instance_types" {
  type = list(string)
}

variable "node_min_size" {
  type = number
}

variable "node_max_size" {
  type = number
}

variable "node_desired_size" {
  type = number
}

# ---------------------------------------------------------------
# Database
# ---------------------------------------------------------------
variable "db_instance_class" {
  type = string
}

variable "db_allocated_storage" {
  type = number
}

variable "db_max_allocated_storage" {
  type = number
}

variable "db_multi_az" {
  type = bool
}

variable "db_backup_retention_days" {
  type = number
}

variable "db_deletion_protection" {
  type = bool
}

variable "db_skip_final_snapshot" {
  type = bool
}

variable "db_secret_recovery_window_days" {
  type = number
}

# ---------------------------------------------------------------
# Edge
# ---------------------------------------------------------------
variable "enable_waf" {
  type = bool
}
