# Remote state in S3 with native S3 locking (no DynamoDB table needed).
# Create the bucket once before "terraform init" (see README).
terraform {
  backend "s3" {
    bucket       = "CHANGE-ME-enterprise-hr-portal-tfstate"
    key          = "prod/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
