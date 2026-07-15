variable "team" {
  type    = string
  default = "sushiops"
}

variable "admin_principal_arn" {
  type        = string
  description = "IAM user or role ARN to grant EKS cluster admin access"
  default     = "arn:aws:iam::937697200280:user/summer-school-ljubljana/andrej.erjavec"
}

# VPC
resource "aws_vpc" "school" {
  cidr_block = "10.0.0.0/16"
  tags       = { Team = var.team, Name = "${var.team}-vpc" }
}

# Public subnet A — AZ a
resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.school.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-west-1a"
  tags              = { Name = "${var.team}-public-subnet-a" }
}

# Private subnet A — AZ a
resource "aws_subnet" "private_a" {
  vpc_id                  = aws_vpc.school.id
  cidr_block              = "10.0.101.0/24"
  availability_zone       = "eu-west-1a"
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.team}-private-subnet-a" }
}

# Public subnet B — AZ b (hosts second NAT gateway for EKS HA)
resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.school.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-west-1b"
  tags              = { Name = "${var.team}-public-subnet-b" }
}

# Private subnet B — AZ b (hosts EKS worker nodes)
resource "aws_subnet" "private_b" {
  vpc_id                  = aws_vpc.school.id
  cidr_block              = "10.0.102.0/24"
  availability_zone       = "eu-west-1b"
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.team}-private-subnet-b" }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.school.id
  tags   = { Name = "${var.team}-igw" }
}

# Elastic IP — AZ a NAT gateway
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.team}-eip-a" }
}

# NAT Gateway — AZ a
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id
  tags          = { Name = "${var.team}-nat-a" }
}

# Public route table — routes traffic to IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.school.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${var.team}-public-rt" }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

# Private route table — AZ a routes traffic via NAT
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.school.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = { Name = "${var.team}-private-rt-a" }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

# Associate public subnet B with existing public route table
resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# Elastic IP — AZ b NAT gateway
resource "aws_eip" "nat_b" {
  domain = "vpc"
  tags   = { Name = "${var.team}-eip-b" }
}

# NAT Gateway — AZ b
resource "aws_nat_gateway" "nat_b" {
  allocation_id = aws_eip.nat_b.id
  subnet_id     = aws_subnet.public_b.id
  tags          = { Name = "${var.team}-nat-b" }
}

# Private route table — AZ b routes traffic via NAT b
resource "aws_route_table" "private_b" {
  vpc_id = aws_vpc.school.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_b.id
  }

  tags = { Name = "${var.team}-private-rt-b" }
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private_b.id
}

# IAM role for EKS control plane
resource "aws_iam_role" "eks_cluster" {
  name                 = "${var.team}-eks-cluster-role"
  permissions_boundary = "arn:aws:iam::937697200280:policy/summer-school-ljubljana-boundary"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# EKS cluster
resource "aws_eks_cluster" "main" {
  name     = "k8s-${var.team}"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.35"

  access_config {
    authentication_mode = "API"
  }

  vpc_config {
    subnet_ids = [
      aws_subnet.private_a.id,
      aws_subnet.private_b.id,
    ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
  ]
}

# Grant admin IAM user access to the EKS cluster
resource "aws_eks_access_entry" "admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.admin_principal_arn
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.admin_principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}

# IAM role for EKS worker nodes
resource "aws_iam_role" "eks_nodes" {
  name                 = "${var.team}-eks-node-role"
  permissions_boundary = "arn:aws:iam::937697200280:policy/summer-school-ljubljana-boundary"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_ecr_readonly" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# EKS node group — worker nodes in private subnets
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.team}-node-group"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  instance_types  = ["t3.medium"]

  scaling_config {
    desired_size = 2
    min_size     = 1
    max_size     = 3
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_readonly,
  ]
}

# Outputs
output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region eu-west-1 --name ${aws_eks_cluster.main.name}"
}
