variable "name" {
  description = "DB instance identifier and name prefix, e.g. enterprise-hr-portal-dev"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Data (isolated) subnets"
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to connect on 5432 (the EKS cluster security group)"
  type        = list(string)
}

variable "engine_version" {
  description = "PostgreSQL major version"
  type        = string
  default     = "16"
}

variable "instance_class" {
  type = string
}

variable "allocated_storage" {
  description = "Initial storage in GiB"
  type        = number
}

variable "max_allocated_storage" {
  description = "Storage autoscaling limit in GiB"
  type        = number
}

variable "multi_az" {
  description = "Synchronous standby in a second AZ"
  type        = bool
}

variable "db_name" {
  type    = string
  default = "employee_db"
}

variable "username" {
  type    = string
  default = "employee_user"
}

variable "backup_retention_days" {
  type = number
}

variable "deletion_protection" {
  type = bool
}

variable "skip_final_snapshot" {
  description = "true for dev (fast teardown), false for prod"
  type        = bool
}

variable "secret_name" {
  description = "Secrets Manager secret the app reads, e.g. enterprise-hr-portal/dev/db"
  type        = string
}

variable "secret_recovery_window_days" {
  description = "Days before a deleted secret is gone for good (0 = delete immediately, handy in dev)"
  type        = number
}
