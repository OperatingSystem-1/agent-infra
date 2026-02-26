# Agent EC2 Instance Module
# Spawns a ClawdBot agent with auto-registration

variable "agent_name" {
  description = "Unique agent identifier (e.g., 'agent-007')"
  type        = string
}

variable "agent_model" {
  description = "LLM model to use (e.g., 'claude-opus-4-5')"
  type        = string
  default     = "claude-sonnet-4-20250514"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "subnet_id" {
  description = "Subnet to launch in"
  type        = string
}

variable "security_group_ids" {
  description = "Security groups to attach"
  type        = list(string)
}

variable "ami_id" {
  description = "ClawdBot AMI ID"
  type        = string
}

variable "neon_connection_string" {
  description = "Neon Postgres connection string"
  type        = string
  sensitive   = true
}

variable "anthropic_oauth_token" {
  description = "Anthropic OAuth token (from Max subscription)"
  type        = string
  sensitive   = true
}

variable "use_spot" {
  description = "Use spot instances for cost savings"
  type        = bool
  default     = true
}

resource "aws_instance" "agent" {
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = var.subnet_id

  vpc_security_group_ids = var.security_group_ids

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  # Spot instance configuration
  dynamic "instance_market_options" {
    for_each = var.use_spot ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        spot_instance_type = "persistent"
        instance_interruption_behavior = "stop"
      }
    }
  }

  user_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
    agent_name    = var.agent_name
    agent_model   = var.agent_model
    neon_conn     = var.neon_connection_string
    anthropic_key = var.anthropic_oauth_token
  }))

  tags = {
    Name      = "clawdbot-${var.agent_name}"
    Role      = "agent"
    Managed   = "terraform"
    AgentName = var.agent_name
  }

  lifecycle {
    create_before_destroy = true
  }
}

output "agent_instance_id" {
  value = aws_instance.agent.id
}

output "agent_private_ip" {
  value = aws_instance.agent.private_ip
}

output "agent_name" {
  value = var.agent_name
}
