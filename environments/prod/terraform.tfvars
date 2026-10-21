# ===============================================================
# PROD environment
# ===============================================================
project     = "enterprise-hr-portal"
environment = "prod"
region      = "ap-south-1"
azs         = ["ap-south-1a", "ap-south-1b"]

# ---------------- Network (10.0.0.0/16) ----------------
vpc_cidr              = "10.0.0.0/16"
frontend_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
compute_subnet_cidrs  = ["10.0.16.0/20", "10.0.32.0/20"]
data_subnet_cidrs     = ["10.0.48.0/24", "10.0.49.0/24"]

# One NAT gateway per AZ: losing one AZ does not cut outbound traffic in the other
single_nat_gateway = false
# Secrets Manager, STS and CloudWatch Logs calls stay inside the VPC
enable_interface_endpoints = true

# ---------------- EKS ----------------
# Must match EKS_CLUSTER in the Jenkinsfile (mycompany-<env>-eks)
cluster_name       = "mycompany-prod-eks"
kubernetes_version = "1.35"

# CHANGE ME: who may reach the Kubernetes API, e.g. ["<jenkins-public-ip>/32", "<your-ip>/32"]
eks_public_access_cidrs = ["0.0.0.0/0"]

# CHANGE ME: IAM principals that get cluster-admin, e.g. the Jenkins IAM user
# cluster_admin_arns = ["arn:aws:iam::123456789012:user/jenkins"]
cluster_admin_arns = []

# Spot nodes: cheaper and use the separate Spot vCPU quota (set ON_DEMAND for steady workloads).
# Several types give Spot more capacity pools. This account is on the AWS Free plan, which only
# allows Free Tier instance types (m7i-flex.large, c7i-flex.large, t3.small, ...).
node_capacity_type  = "SPOT"
node_instance_types = ["m7i-flex.large", "c7i-flex.large"]
node_min_size       = 2
node_max_size       = 4
node_desired_size   = 2

# ---------------- Database ----------------
# AWS Free plan limits (account cannot create larger/Multi-AZ databases or keep backups > 1 day).
# Production values to restore after upgrading the account plan:
#   db_instance_class = "db.t4g.medium", db_allocated_storage = 50, db_max_allocated_storage = 200,
#   db_multi_az = true, db_backup_retention_days = 7
db_instance_class              = "db.t4g.micro"
db_allocated_storage           = 20
db_max_allocated_storage       = 50
db_multi_az                    = false
db_backup_retention_days       = 1
db_deletion_protection         = true
db_skip_final_snapshot         = false
db_secret_recovery_window_days = 7

# ---------------- Edge ----------------
enable_waf = true

# ---------------- S3 buckets (optional) ----------------
# Each entry creates a private, encrypted, HTTPS-only bucket named
# enterprise-hr-portal-prod-<key>-<account-id>. Examples:
#
# s3_buckets = {
#   documents = { app_access = true, force_destroy = false }        # app pods can read/write via IRSA
#   reports   = { expiration_days = 90 }                           # objects deleted after 90 days
#   exports   = { versioning = false, force_destroy = false }
# }
s3_buckets = {}

# ---------------- Monitoring (ELK on one EC2) ----------------
enable_elk           = true
elk_instance_type    = "m7i-flex.large"
elk_data_volume_size = 100
# Spot instance for ELK (cheaper; data stays on its separate EBS volume if AWS reclaims it)
elk_use_spot = true
# CHANGE ME: who may open Kibana, e.g. ["<your-ip>/32"]
kibana_allowed_cidrs = ["0.0.0.0/0"]
