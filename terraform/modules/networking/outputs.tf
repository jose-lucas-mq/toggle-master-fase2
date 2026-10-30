output "vpc_id" { value = aws_vpc.this.id }
output "public_subnet_ids" { value = aws_subnet.public[*].id }
output "private_subnet_ids" { value = aws_subnet.private[*].id }
output "igw_id" { value = aws_internet_gateway.this.id }
output "nat_gateway_ids" {
  description = "IDs de todos NAT Gateways criados (1 ou 3 depende de var.single_nat_gateway)."
  value       = aws_nat_gateway.this.*.id
}
output "default_security_group_id" { value = aws_vpc.this.default_security_group_id }
