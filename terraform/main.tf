# ClawdBot Agent Cluster - Root Module
# Provisions VPC + N agent instances

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state in S3 (optional - comment out for local state)
  # backend "s3" {
  #   bucket = "clawdbot-terraform-state"
  #   key    = "agent-cluster/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "clawdbot-agents"
      ManagedBy = "terraform"
      Cluster   = var.cluster_name
    }
  }
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name for this agent cluster"
  type        = string
  default     = "clawdbot-cluster"
}

variable "agent_count" {
  description = "Number of agents to spawn"
  type        = number
  default     = 3
}

variable "agent_model" {
  description = "Default LLM model for agents"
  type        = string
  default     = "claude-sonnet-4-20250514"
}

variable "use_spot" {
  description = "Use spot instances"
  type        = bool
  default     = true
}

variable "neon_connection_string" {
  description = "Neon Postgres connection string"
  type        = string
  sensitive   = true
}

variable "anthropic_api_key" {
  description = "Anthropic API key (from env or tfvars)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "ami_id" {
  description = "ClawdBot AMI ID (from Packer build)"
  type        = string
  default     = "" # Will be set after Packer build
}

# Data sources
data "aws_ami" "clawdbot" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["clawdbot-agent-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

locals {
  # Use custom AMI if provided, otherwise fall back to self-built or base Ubuntu
  selected_ami = var.ami_id != "" ? var.ami_id : (
    length(data.aws_ami.clawdbot) > 0 ? data.aws_ami.clawdbot[0].id : data.aws_ami.ubuntu.id
  )
  
  # Generate agent names
  agent_names = [for i in range(var.agent_count) : "agent-${format("%03d", i + 1)}"]
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  cluster_name = var.cluster_name
  vpc_cidr     = "10.42.0.0/16"
  azs          = ["${var.aws_region}a", "${var.aws_region}b"]
}

# Agent Instances
module "agents" {
  source   = "./modules/agent"
  for_each = toset(local.agent_names)

  agent_name             = each.value
  agent_model            = var.agent_model
  instance_type          = "t3.medium"
  subnet_id              = module.vpc.agent_subnet_ids[0]
  security_group_ids     = [module.vpc.agent_security_group_id]
  ami_id                 = local.selected_ami
  neon_connection_string = var.neon_connection_string
  anthropic_oauth_token  = var.anthropic_api_key
  use_spot               = var.use_spot
}

# Outputs
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "agents" {
  value = {
    for name, agent in module.agents : name => {
      instance_id = agent.agent_instance_id
      private_ip  = agent.agent_private_ip
    }
  }
}

output "cluster_summary" {
  value = <<-EOT
    Cluster: ${var.cluster_name}
    Region: ${var.aws_region}
    Agents: ${var.agent_count}
    Model: ${var.agent_model}
    Spot: ${var.use_spot}
    AMI: ${local.selected_ami}
  EOT
}
