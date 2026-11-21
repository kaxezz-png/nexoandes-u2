output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "subnet_ids" {
  value = { for k, s in aws_subnet.public : k => s.id }
}

output "subnet_cidrs" {
  value = { for k, s in aws_subnet.public : k => "${s.cidr_block} (${s.availability_zone})" }
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "target_group_arn" {
  value = aws_lb_target_group.portal.arn
}

output "asg_name" {
  value = aws_autoscaling_group.portal.name
}

output "launch_template_id" {
  value = aws_launch_template.portal.id
}

output "launch_template_version" {
  value = aws_launch_template.portal.latest_version
}

output "ami_id" {
  value = local.ami_id
}
