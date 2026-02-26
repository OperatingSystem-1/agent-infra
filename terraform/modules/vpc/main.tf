# Agent Cluster VPC
# Isolated network for agent-to-agent communication

variable "cluster_name" {
  description = "Name for this agent cluster"
  type        = string
  default     = "clawdbot-cluster"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.42.0.0/16"
}

variable "azs" {
  description = "Availability zones to use"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

# VPC
resource "aws_vpc" "agents" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = var.cluster_name
  }
}

# Internet Gateway (for agents to reach APIs)
resource "aws_internet_gateway" "agents" {
  vpc_id = aws_vpc.agents.id
  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

# Public subnets (for NAT / bastion if needed)
resource "aws_subnet" "public" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.agents.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.azs[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name = "${var.cluster_name}-public-${count.index}"
    Tier = "public"
  }
}

# Private subnets (where agents live)
resource "aws_subnet" "agents" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.agents.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.cluster_name}-agents-${count.index}"
    Tier = "private"
  }
}

# NAT Gateway (so private agents can reach external APIs)
resource "aws_eip" "nat" {
  domain = "vpc"
  tags = {
    Name = "${var.cluster_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "agents" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.cluster_name}-nat"
  }
}

# Route tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.agents.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.agents.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.agents.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.agents.id
  }

  tags = {
    Name = "${var.cluster_name}-private-rt"
  }
}

# Route table associations
resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.agents[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security group for agents
resource "aws_security_group" "agents" {
  name        = "${var.cluster_name}-agents-sg"
  description = "Security group for ClawdBot agents"
  vpc_id      = aws_vpc.agents.id

  # Agent-to-agent communication (all traffic within SG)
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # All outbound (APIs, model providers, etc)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-agents-sg"
  }
}

# Outputs
output "vpc_id" {
  value = aws_vpc.agents.id
}

output "agent_subnet_ids" {
  value = aws_subnet.agents[*].id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "agent_security_group_id" {
  value = aws_security_group.agents.id
}
