# Remote state: S3 bucket + DynamoDB lock table.
# The bucket name contains the AWS account ID, so it is passed at init time:
#   terraform init -backend-config="bucket=enterprise-hr-portal-tfstate-<account-id>"
# The Jenkinsfile does this automatically and creates the bucket and table if they don't exist.
terraform {
  backend "s3" {
    key            = "dev/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "enterprise-hr-portal-tf-locks"
    encrypt        = true
  }
}
