output "region" {
  value = var.region
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "configure_kubectl" {
  description = "Run this to use kubectl with the new cluster"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "nat_public_ips" {
  value = module.vpc.nat_public_ips
}

output "rds_endpoint" {
  value = module.rds.address
}

output "db_secret_name" {
  value = module.rds.secret_name
}

output "app_irsa_role_arn" {
  value = module.app_irsa.role_arn
}

output "waf_web_acl_arn" {
  value = var.enable_waf ? module.waf[0].web_acl_arn : null
}

# Values to copy into the deploy repo (enterprise-hr-portal-deploy)
output "deploy_repo_values" {
  value = {
    "config/env-${var.environment}.yaml -> env.DB_HOST"                     = module.rds.address
    "environments/${var.environment}/values.yaml -> secrets.awsSecretName"  = module.rds.secret_name
    "environments/${var.environment}/values.yaml -> serviceAccount.roleArn" = module.app_irsa.role_arn
    "Jenkinsfile -> AWS_REGION"                                             = var.region
    "Jenkinsfile -> EKS_CLUSTER (for ${var.environment})"                   = module.eks.cluster_name
  }
}
