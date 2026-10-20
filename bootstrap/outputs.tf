output "state_bucket" {
  description = "Put this in environments/*/backend.tf -> bucket"
  value       = module.state_bucket.bucket_name
}

output "lock_table" {
  description = "Put this in environments/*/backend.tf -> dynamodb_table"
  value       = aws_dynamodb_table.locks.name
}

output "region" {
  value = var.region
}
