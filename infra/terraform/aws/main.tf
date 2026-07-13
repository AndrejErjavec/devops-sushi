provider "aws" {
  region = var.aws_region
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_key_pair" "this" {
  key_name   = "${var.cluster_name}-key"
  public_key = file(pathexpand(var.public_key_path))
}

resource "aws_security_group" "rke" {
  name        = "${var.cluster_name}-rke"
  description = "RKE demo cluster access"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "Kubernetes API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "RKE internal traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-rke"
  }
}

locals {
  nodes = concat(
    [
      {
        name  = "control-1"
        roles = "controlplane,etcd,worker"
      }
    ],
    [
      for index in range(var.worker_count) : {
        name  = "worker-${index + 1}"
        roles = "worker"
      }
    ]
  )
}

resource "aws_instance" "node" {
  for_each = { for node in local.nodes : node.name => node }

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.rke.id]
  key_name                    = aws_key_pair.this.key_name

  root_block_device {
    volume_size = 40
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/user-data.sh", {})

  tags = {
    Name    = "${var.cluster_name}-${each.key}"
    Cluster = var.cluster_name
    Roles   = each.value.roles
  }
}
