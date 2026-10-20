variable "name" {
  description = "Web ACL name"
  type        = string
}

variable "rate_limit" {
  description = "Maximum requests per IP in any 5-minute window before blocking"
  type        = number
  default     = 2000
}
