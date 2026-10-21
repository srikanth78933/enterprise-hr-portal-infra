# ===============================================================
# DEV environment
# ===============================================================
project     = "enterprise-hr-portal"
environment = "dev"
region      = "ap-south-1"
azs         = ["ap-south-1a", "ap-south-1b"]

# ---------------- Network (10.1.0.0/16) ----------------
vpc_cidr              = "10.1.0.0/16"
frontend_subnet_cidrs = ["10.1.1.0/24", "10.1.2.0/24"]
compute_subnet_cidrs  = ["10.1.16.0/20", "10.1.32.0/20"]
data_subnet_cidrs     = ["10.1.48.0/24", "10.1.49.0/24"]

# One NAT gateway for both AZs keeps dev cheaper
single_nat_gateway = true
# Pods reach Secrets Manager/STS through the NAT gateway in dev
enable_interface_endpoints = false

# ---------------- EKS ----------------
# Must match EKS_CLUSTER in the Jenkinsfile (mycompany-<env>-eks)
cluster_name       = "mycompany-dev-eks"
kubernetes_version = "1.35"

# CHANGE ME: who may reach the Kubernetes API, e.g. ["<jenkins-public-ip>/32", "<your-ip>/32"]
eks_public_access_cidrs = ["0.0.0.0/0"]

# CHANGE ME: IAM principals that get cluster-admin, e.g. the Jenkins IAM user
# cluster_admin_arns = ["arn:aws:iam::123456789012:user/jenkins"]
cluster_admin_arns = []

# Spot nodes: cheaper and use the separate Spot vCPU quota (set ON_DEMAND for steady workloads).
# Several similar types give Spot more capacity pools to choose from.
node_capacity_type  = "SPOT"
node_instance_types = ["t3.medium", "t3a.medium"]
node_min_size       = 1
node_max_size       = 2
node_desired_size   = 2

# ---------------- Database ----------------
db_instance_class              = "db.t4g.micro"
db_allocated_storage           = 20
db_max_allocated_storage       = 50
db_multi_az                    = false
db_backup_retention_days       = 1
db_deletion_protection         = false
db_skip_final_snapshot         = true
db_secret_recovery_window_days = 0

# ---------------- Edge ----------------
enable_waf = false

# ---------------- S3 buckets (optional) ----------------
# Each entry creates a private, encrypted, HTTPS-only bucket named
# enterprise-hr-portal-dev-<key>-<account-id>. Examples:
#
# s3_buckets = {
#   documents = { app_access = true, force_destroy = true }        # app pods can read/write via IRSA
#   reports   = { expiration_days = 90 }                           # objects deleted after 90 days
#   exports   = { versioning = false, force_destroy = true }
# }
s3_buckets = {}

# ---------------- Monitoring ----------------
# ELK runs in prod only
enable_elk = false
