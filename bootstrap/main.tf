# Remote state storage shared by all environments:
#   S3 bucket      -> holds dev/terraform.tfstate and prod/terraform.tfstate
#   DynamoDB table -> state lock, so two people/pipelines can't apply at the same time

data "aws_caller_identity" "current" {}

# Versioned, encrypted, private, HTTPS-only bucket (same module the environments use)
module "state_bucket" {
  source = "../modules/s3"

  # Account ID suffix keeps the name globally unique
  bucket_name                        = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
  versioning                         = true
  force_destroy                      = false
  noncurrent_version_expiration_days = 90
}

resource "aws_dynamodb_table" "locks" {
  name         = "${var.project}-tf-locks"
  billing_mode = "PAY_PER_REQUEST"
  # Terraform's S3 backend requires exactly this key name
  hash_key = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }

  deletion_protection_enabled = true
}
