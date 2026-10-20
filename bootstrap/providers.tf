# Run once per AWS account, before the environments.
# This configuration keeps its own state locally (it creates the remote state storage itself).
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      Purpose   = "terraform-state"
      ManagedBy = "terraform"
    }
  }
}
