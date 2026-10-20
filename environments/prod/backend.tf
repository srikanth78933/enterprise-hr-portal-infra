# Remote state: S3 bucket + DynamoDB lock table, both created by ../../bootstrap (run it first).
terraform {
  backend "s3" {
    bucket         = "CHANGE-ME-enterprise-hr-portal-tfstate" # bootstrap output: state_bucket
    key            = "prod/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "enterprise-hr-portal-tf-locks" # bootstrap output: lock_table
    encrypt        = true
  }
}
