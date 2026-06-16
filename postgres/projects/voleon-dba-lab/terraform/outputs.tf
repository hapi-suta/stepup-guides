output "node_ips" {
  value = { for k, v in aws_instance.node : k => v.public_ip }
}

output "node_private_ips" {
  value = { for k, v in aws_instance.node : k => v.private_ip }
}

output "ssh_commands" {
  value = { for k, v in aws_instance.node :
    k => "ssh -i ~/.ssh/id_ed25519 ec2-user@${v.public_ip}"
  }
}

output "security_group_id" {
  value = aws_security_group.lab.id
}

output "instance_ids" {
  value = { for k, v in aws_instance.node : k => v.id }
}
