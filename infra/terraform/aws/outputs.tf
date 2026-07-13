output "node_public_ips" {
  description = "Public IPs for generated RKE cluster.yml."
  value = {
    for name, node in aws_instance.node : name => node.public_ip
  }
}

output "node_private_ips" {
  description = "Private IPs useful for internal_address in RKE."
  value = {
    for name, node in aws_instance.node : name => node.private_ip
  }
}

output "ssh_user" {
  value = "ubuntu"
}
