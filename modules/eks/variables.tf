variable "cluster_name" {
  description = "EKS cluster name (Jenkins uses it in aws eks update-kubeconfig)"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version, e.g. 1.35"
  type        = string
}

variable "subnet_ids" {
  description = "Compute (private) subnets for the control plane ENIs and the worker nodes"
  type        = list(string)
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API endpoint (Jenkins and admin IPs)"
  type        = list(string)
}

variable "admin_principal_arns" {
  description = "IAM users/roles that get cluster-admin access (e.g. the Jenkins IAM user). The identity running Terraform gets it automatically."
  type        = list(string)
  default     = []
}

variable "cluster_log_types" {
  description = "Control plane logs sent to CloudWatch"
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group"
  type        = list(string)
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

variable "node_disk_size" {
  description = "Root volume size in GiB for each node"
  type        = number
  default     = 30
}
