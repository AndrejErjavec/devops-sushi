# VPC
resource "aws_vpc" "school" {
  cidr_block = "10.0.0.0/16"
  tags = { Team = var.team, Name = "${var.team}-vpc" }
}

# Public subnet A — hosts internet-facing resources and the NAT gateway
# the next (B) would be 10.0.2.0/24
resource "aws_subnet" "public_a" {
  vpc_id = aws_vpc.school.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "eu-west-1a"
  tags = {
    Name = "${var.team}-public-subnet"
  }
}

# Private subnet A — hosts internal resources with no direct internet access
# the next (B) would be 10.0.102.0/24
resource "aws_subnet" "private_a" {
  vpc_id = aws_vpc.school.id
  cidr_block = "10.0.101.0/24"
  availability_zone = "eu-west-1a"
  map_public_ip_on_launch = false
  tags = {
    Name = "${var.team}-private-subnet"
  }
}

# Internet Gateway — connects the VPC to the public internet
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.school.id
  tags = { Name = "${var.team}-igw" }
}

# Elastic IP — static public IP address for the NAT gateway
resource "aws_eip" "nat" {
  domain = "vpc"
}

# NAT Gateway — allows private subnet instances to initiate outbound internet traffic
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id
  tags = { Name = "${var.team}-nat" }
}

# Public route table — routes outbound traffic to the internet via the IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.school.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${var.team}-public-rt" }
}

# Associate public route table with public subnet A
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

# Private route table — routes outbound traffic to the internet via the NAT gateway
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.school.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = { Name = "${var.team}-private-rt" }
}

# Associate private route table with private subnet A
resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

variable "team" {
  type = string
  default = "devops-sushi"
}

output "vpc_id" {
  value = aws_vpc.school.id
}

# Fetch the latest Amazon Linux 2023 AMI
data "aws_ami" "al2023" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# EC2 instance — runner deployed inside the VPC
resource "aws_instance" "runner" {
  ami           = data.aws_ami.al2023.id
  instance_type = "t3.micro"

  tags = {
    Name = "${var.team}-runner"
  }
}
