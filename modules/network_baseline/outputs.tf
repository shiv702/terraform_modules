output "vpc_id" {
  value = aws_vpc.this.id
}

output "subnet_ids" {
  value = { for k, s in aws_subnet.this : k => s.id }
}

output "public_subnet_ids" {
  value = { for k, s in aws_subnet.this : k => s.id if lower(var.subnets[k].type) == "public" }
}

output "private_subnet_ids" {
  value = { for k, s in aws_subnet.this : k => s.id if lower(var.subnets[k].type) == "private" }
}
