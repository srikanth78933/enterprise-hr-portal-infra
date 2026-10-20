variable "name" {
  description = "Prefix for resource names, e.g. enterprise-hr-portal-dev"
  type        = string
}

variable "cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "azs" {
  description = "Availability Zones, one subnet of each tier per AZ"
  type        = list(string)
}

variable "frontend_subnet_cidrs" {
  description = "Public subnets for the ALB and NAT gateways (one per AZ)"
  type        = list(string)
}

variable "compute_subnet_cidrs" {
  description = "Private subnets for EKS nodes and pods (one per AZ)"
  type        = list(string)
}

variable "data_subnet_cidrs" {
  description = "Isolated subnets for RDS (one per AZ, no internet route)"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "true = one NAT gateway for all AZs (cheaper, for dev); false = one per AZ (prod)"
  type        = bool
  default     = false
}

variable "enable_interface_endpoints" {
  description = "Create interface endpoints for Secrets Manager, STS and CloudWatch Logs"
  type        = bool
  default     = false
}
