variable "name" {
  description = "Name prefix, e.g. enterprise-hr-portal-prod-elk"
  type        = string
}

variable "short_name" {
  description = "Short name for the Kibana load balancer and target group (max 26 characters), e.g. hrp-prod-kibana"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  description = "Private (compute) subnet for the ELK instance"
  type        = string
}

variable "alb_subnet_ids" {
  description = "Public (frontend) subnets for the Kibana load balancer"
  type        = list(string)
}

variable "client_security_group_ids" {
  description = "Security groups allowed to send data (EKS cluster security group): Logstash 5044, Elasticsearch 9200"
  type        = list(string)
}

variable "kibana_allowed_cidrs" {
  description = "CIDRs allowed to open Kibana through the load balancer"
  type        = list(string)
}

variable "certificate_arn" {
  description = "Optional ACM certificate ARN; when set Kibana is served on HTTPS 443 and 80 redirects"
  type        = string
  default     = ""
}

variable "instance_type" {
  type    = string
  default = "m7i.xlarge"
}

variable "data_volume_size" {
  description = "Size in GiB of the EBS volume that stores Elasticsearch data"
  type        = number
  default     = 100
}

variable "config_bucket_name" {
  description = "S3 bucket Jenkins uploads the monitoring repo's elk/ folder to"
  type        = string
}

variable "secret_name" {
  description = "Secrets Manager secret holding the ELK passwords"
  type        = string
}

variable "secret_recovery_window_days" {
  type    = number
  default = 7
}

variable "use_spot" {
  description = "Run the ELK instance as a Spot instance (cheaper; AWS can reclaim it, the data volume is kept)"
  type        = bool
  default     = false
}
