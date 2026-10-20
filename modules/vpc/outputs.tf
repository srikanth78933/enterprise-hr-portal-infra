output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "frontend_subnet_ids" {
  value = aws_subnet.frontend[*].id
}

output "compute_subnet_ids" {
  value = aws_subnet.compute[*].id
}

output "data_subnet_ids" {
  value = aws_subnet.data[*].id
}

output "nat_public_ips" {
  description = "Outbound public IPs of the compute subnets (allow-list these on external services if needed)"
  value       = aws_eip.nat[*].public_ip
}
