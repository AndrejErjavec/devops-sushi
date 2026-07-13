variable "aws_region" {
  description = "AWS region for the demo cluster."
  type        = string
  default     = "eu-central-1"
}

variable "cluster_name" {
  description = "Name used for AWS tags and node hostnames."
  type        = string
  default     = "devops-sushi"
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH into the nodes."
  type        = string
}

variable "public_key_path" {
  description = "Path to the SSH public key installed on EC2 nodes."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "instance_type" {
  description = "EC2 instance type for RKE nodes."
  type        = string
  default     = "t3.medium"
}

variable "worker_count" {
  description = "Number of worker-only nodes."
  type        = number
  default     = 2
}
