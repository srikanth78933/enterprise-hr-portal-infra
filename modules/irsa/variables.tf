variable "role_name" {
  description = "IAM role name"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider"
  type        = string
}

variable "oidc_provider_url" {
  description = "Cluster OIDC issuer without https://"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the ServiceAccount"
  type        = string
}

variable "service_account" {
  description = "Kubernetes ServiceAccount name allowed to assume the role"
  type        = string
}

variable "policy_json" {
  description = "IAM policy document (JSON) with the permissions the pods need"
  type        = string
}
