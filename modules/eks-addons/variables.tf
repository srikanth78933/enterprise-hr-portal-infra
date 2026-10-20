variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  description = "Cluster OIDC issuer without https://"
  type        = string
}

# Chart versions are pinned so every environment gets the same, tested versions
variable "aws_load_balancer_controller_version" {
  type    = string
  default = "3.5.0"
}

variable "secrets_store_provider_aws_version" {
  description = "AWS provider chart; it also installs the Secrets Store CSI driver"
  type        = string
  default     = "3.1.3"
}

variable "metrics_server_version" {
  type    = string
  default = "3.13.1"
}

variable "cluster_autoscaler_version" {
  description = "Chart 9.58.x ships Cluster Autoscaler 1.35 (match the Kubernetes minor version)"
  type        = string
  default     = "9.58.0"
}
