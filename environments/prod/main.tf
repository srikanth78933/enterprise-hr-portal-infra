# Wires the modules together for one environment. All environment-specific values are in terraform.tfvars.

locals {
  name = "${var.project}-${var.environment}"

  # Must match the deploy repo: namespace hr-portal-<env>, Helm release/ServiceAccount enterprise-hr-portal
  app_namespace       = "hr-portal-${var.environment}"
  app_service_account = "enterprise-hr-portal"
  app_secret_name     = "${var.project}/${var.environment}/db"
}

# ---------------------------------------------------------------
# Network: frontend / compute / data subnets
# ---------------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  name                       = local.name
  cidr                       = var.vpc_cidr
  azs                        = var.azs
  frontend_subnet_cidrs      = var.frontend_subnet_cidrs
  compute_subnet_cidrs       = var.compute_subnet_cidrs
  data_subnet_cidrs          = var.data_subnet_cidrs
  single_nat_gateway         = var.single_nat_gateway
  enable_interface_endpoints = var.enable_interface_endpoints
}

# ---------------------------------------------------------------
# Compute: EKS cluster and nodes in the compute subnets
# ---------------------------------------------------------------
module "eks" {
  source = "../../modules/eks"

  cluster_name         = var.cluster_name
  kubernetes_version   = var.kubernetes_version
  subnet_ids           = module.vpc.compute_subnet_ids
  public_access_cidrs  = var.eks_public_access_cidrs
  admin_principal_arns = var.cluster_admin_arns
  node_instance_types  = var.node_instance_types
  node_min_size        = var.node_min_size
  node_max_size        = var.node_max_size
  node_desired_size    = var.node_desired_size
}

# ---------------------------------------------------------------
# Data: RDS PostgreSQL in the data subnets + credentials in Secrets Manager
# ---------------------------------------------------------------
module "rds" {
  source = "../../modules/rds"

  name                        = local.name
  vpc_id                      = module.vpc.vpc_id
  subnet_ids                  = module.vpc.data_subnet_ids
  allowed_security_group_ids  = [module.eks.cluster_security_group_id]
  instance_class              = var.db_instance_class
  allocated_storage           = var.db_allocated_storage
  max_allocated_storage       = var.db_max_allocated_storage
  multi_az                    = var.db_multi_az
  backup_retention_days       = var.db_backup_retention_days
  deletion_protection         = var.db_deletion_protection
  skip_final_snapshot         = var.db_skip_final_snapshot
  secret_name                 = local.app_secret_name
  secret_recovery_window_days = var.db_secret_recovery_window_days
}

# ---------------------------------------------------------------
# S3 buckets listed in terraform.tfvars (s3_buckets); none by default
# ---------------------------------------------------------------
data "aws_caller_identity" "current" {}

module "s3" {
  source   = "../../modules/s3"
  for_each = var.s3_buckets

  # Account ID suffix keeps the name globally unique
  bucket_name                        = "${local.name}-${each.key}-${data.aws_caller_identity.current.account_id}"
  versioning                         = each.value.versioning
  force_destroy                      = each.value.force_destroy
  expiration_days                    = each.value.expiration_days
  noncurrent_version_expiration_days = each.value.noncurrent_version_expiration_days
}

locals {
  # Buckets the application pods may use
  app_bucket_arns = [for key, bucket in module.s3 : bucket.bucket_arn if var.s3_buckets[key].app_access]
}

# ---------------------------------------------------------------
# IRSA role for the application: its own DB secret (+ S3 buckets with app_access = true)
# ---------------------------------------------------------------
data "aws_iam_policy_document" "app" {
  statement {
    sid       = "ReadDatabaseSecret"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [module.rds.secret_arn]
  }

  dynamic "statement" {
    for_each = length(local.app_bucket_arns) > 0 ? [1] : []
    content {
      sid       = "ListAppBuckets"
      actions   = ["s3:ListBucket"]
      resources = local.app_bucket_arns
    }
  }

  dynamic "statement" {
    for_each = length(local.app_bucket_arns) > 0 ? [1] : []
    content {
      sid       = "ReadWriteAppObjects"
      actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      resources = [for arn in local.app_bucket_arns : "${arn}/*"]
    }
  }
}

module "app_irsa" {
  source = "../../modules/irsa"

  role_name         = "${local.name}-secrets-role"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  namespace         = local.app_namespace
  service_account   = local.app_service_account
  policy_json       = data.aws_iam_policy_document.app.json
}

# ---------------------------------------------------------------
# Cluster add-ons: Load Balancer Controller, Secrets Store CSI, metrics-server, Cluster Autoscaler
# ---------------------------------------------------------------
module "eks_addons" {
  source = "../../modules/eks-addons"

  cluster_name      = module.eks.cluster_name
  region            = var.region
  vpc_id            = module.vpc.vpc_id
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  # Add-on pods need running nodes
  depends_on = [module.eks]
}

# ---------------------------------------------------------------
# Edge: WAF web ACL for the ALB (attached through the app's Ingress annotation)
# ---------------------------------------------------------------
module "waf" {
  source = "../../modules/waf"
  count  = var.enable_waf ? 1 : 0

  name = "${local.name}-web-acl"
}

# ---------------------------------------------------------------
# Monitoring: ELK on one EC2 instance (enable_elk = true in prod only)
# The stack is deployed by the enterprise-hr-portal-monitoring repo.
# ---------------------------------------------------------------
module "elk" {
  source = "../../modules/elk-ec2"
  count  = var.enable_elk ? 1 : 0

  name                      = "${local.name}-elk"
  short_name                = "hrp-${var.environment}-kibana"
  vpc_id                    = module.vpc.vpc_id
  subnet_id                 = module.vpc.compute_subnet_ids[0]
  alb_subnet_ids            = module.vpc.frontend_subnet_ids
  client_security_group_ids = [module.eks.cluster_security_group_id]
  kibana_allowed_cidrs      = var.kibana_allowed_cidrs
  instance_type             = var.elk_instance_type
  data_volume_size          = var.elk_data_volume_size
  config_bucket_name        = "${local.name}-elk-config-${data.aws_caller_identity.current.account_id}"
  secret_name               = "${var.project}/${var.environment}/elk"
}
