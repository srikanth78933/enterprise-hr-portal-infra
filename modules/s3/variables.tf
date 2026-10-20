variable "bucket_name" {
  description = "Globally unique bucket name"
  type        = string
}

variable "versioning" {
  description = "Keep previous versions of objects (protects against overwrite/delete)"
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Allow terraform destroy to delete the bucket even when it contains objects (dev only)"
  type        = bool
  default     = false
}

variable "expiration_days" {
  description = "Delete objects this many days after creation (null = keep forever)"
  type        = number
  default     = null
}

variable "noncurrent_version_expiration_days" {
  description = "Delete previous object versions after this many days"
  type        = number
  default     = 30
}
