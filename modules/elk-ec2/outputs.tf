output "instance_id" {
  value = aws_instance.this.id
}

output "private_ip" {
  description = "Address the Beats in EKS send to"
  value       = aws_instance.this.private_ip
}

output "kibana_url" {
  value = "${var.certificate_arn == "" ? "http" : "https"}://${aws_lb.kibana.dns_name}"
}

output "config_bucket" {
  value = module.config_bucket.bucket_name
}

output "secret_name" {
  value = aws_secretsmanager_secret.elk.name
}
