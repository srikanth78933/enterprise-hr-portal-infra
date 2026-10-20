output "lb_controller_role_arn" {
  value = module.lb_controller_irsa.role_arn
}

output "cluster_autoscaler_role_arn" {
  value = module.cluster_autoscaler_irsa.role_arn
}
