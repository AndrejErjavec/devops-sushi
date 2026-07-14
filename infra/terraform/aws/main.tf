# AWS provider uporablja regijo, nastavljeno v variables.tf.
provider "aws" {
  region = var.aws_region
}

# Poišče najnovejšo uradno Ubuntu 22.04 (Jammy) AMI sliko.
data "aws_ami" "ubuntu" {
  most_recent = true
  # ID uradnega Canonical AWS računa.
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# Poišče privzeti VPC v izbrani AWS regiji.
data "aws_vpc" "default" {
  default = true
}

# Poišče vse subnete, ki pripadajo privzetemu VPC-ju.
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Registrira lokalni javni SSH ključ kot AWS key pair.
resource "aws_key_pair" "this" {
  key_name   = "${var.cluster_name}-key"
  # pathexpand razširi ~, file pa prebere vsebino javnega ključa.
  public_key = file(pathexpand(var.public_key_path))
}

# Firewall pravila za dostop do RKE/Kubernetes nodov.
resource "aws_security_group" "rke" {
  name        = "${var.cluster_name}-rke"
  description = "RKE demo cluster access"
  vpc_id      = data.aws_vpc.default.id

  # SSH je dovoljen samo iz CIDR-ja, podanega v allowed_ssh_cidr.
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # Kubernetes API uporablja TCP vrata 6443.
  ingress {
    description = "Kubernetes API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # Dovoli ves promet med instancami z isto security group.
  ingress {
    description = "RKE internal traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Dovoli instancam ves odhodni promet proti internetu.
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

# Sestavi seznam nodov: en control node in nastavljivo število workerjev.
locals {
  nodes = concat(
    # Control node ima za ta demo tudi etcd in worker vlogo.
    [
      {
        name  = "control-1"
        roles = "controlplane,etcd,worker"
      }
    ],
    # Ustvari worker-1, worker-2, ... glede na worker_count.
    [
      for index in range(var.worker_count) : {
        name  = "worker-${index + 1}"
        roles = "worker"
      }
    ]
  )
}

# Za vsak element v local.nodes ustvari eno EC2 instanco.
resource "aws_instance" "node" {
  # Ime noda postane unikaten ključ, npr. control-1 ali worker-1.
  for_each = { for node in local.nodes : node.name => node }

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  # Za demo uporabi prvi subnet iz privzetega VPC-ja.
  subnet_id                   = data.aws_subnets.default.ids[0]
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.rke.id]
  key_name                    = aws_key_pair.this.key_name

  # Sistemski EBS disk posamezne instance.
  root_block_device {
    volume_size = 40
    volume_type = "gp3"
  }

  # Ob prvem zagonu instance izvede pripravljalno shell skripto.
  user_data = templatefile("${path.module}/user-data.sh", {})

  # Oznake olajšajo prepoznavanje nodov in njihovih RKE vlog v AWS konzoli.
  tags = {
    Name    = "${var.cluster_name}-${each.key}"
    Cluster = var.cluster_name
    Roles   = each.value.roles
  }
}
