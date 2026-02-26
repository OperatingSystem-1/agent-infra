# Terraform Agent Infrastructure

Terraform modules for provisioning agent clusters on AWS.

## Prerequisites

- Terraform >= 1.5.0
- AWS CLI configured with credentials
- Neon PostgreSQL connection string
- Anthropic API key (optional)

## Quick Start

```bash
cd terraform

# Initialize
terraform init

# Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Plan
terraform plan

# Apply
terraform apply
```

## Modules

### VPC Module (`modules/vpc/`)

Creates isolated network infrastructure for agents:

- VPC with configurable CIDR
- Public subnets (for NAT gateway)
- Private subnets (for agent instances)
- NAT Gateway for outbound internet
- Security groups for agent-to-agent traffic

**Inputs:**
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `cluster_name` | string | `clawdbot-cluster` | Name prefix for resources |
| `vpc_cidr` | string | `10.42.0.0/16` | VPC CIDR block |
| `azs` | list(string) | `["us-east-1a", "us-east-1b"]` | Availability zones |

**Outputs:**
| Output | Description |
|--------|-------------|
| `vpc_id` | VPC ID |
| `agent_subnet_ids` | Private subnet IDs for agents |
| `public_subnet_ids` | Public subnet IDs |
| `agent_security_group_id` | Security group for agents |

### Agent Module (`modules/agent/`)

Provisions individual agent EC2 instances:

- EC2 instance (spot or on-demand)
- Cloud-init bootstrap script
- Auto-registration in Neon
- Keypair generation

**Inputs:**
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `agent_name` | string | required | Unique agent identifier |
| `agent_model` | string | `claude-sonnet-4-20250514` | LLM model |
| `instance_type` | string | `t3.medium` | EC2 instance type |
| `subnet_id` | string | required | Subnet to launch in |
| `security_group_ids` | list(string) | required | Security groups |
| `ami_id` | string | required | ClawdBot AMI ID |
| `use_spot` | bool | `true` | Use spot instances |

**Outputs:**
| Output | Description |
|--------|-------------|
| `agent_instance_id` | EC2 instance ID |
| `agent_private_ip` | Private IP address |
| `agent_name` | Agent name |

## Variables

### Required

```hcl
# Neon PostgreSQL connection
neon_connection_string = "postgresql://user:pass@host/db?sslmode=require"

# Anthropic API key
anthropic_api_key = "sk-ant-..."
```

### Optional

```hcl
# AWS region (default: us-east-1)
aws_region = "us-east-1"

# Cluster name prefix
cluster_name = "clawdbot-cluster"

# Number of agents to spawn
agent_count = 3

# LLM model for agents
agent_model = "claude-sonnet-4-20250514"

# Use spot instances for cost savings
use_spot = true

# Custom AMI (leave empty to auto-detect)
ami_id = ""
```

## Examples

### Spawn 3-Agent Cluster

```bash
terraform apply \
  -var="agent_count=3" \
  -var="cluster_name=my-cluster" \
  -var="neon_connection_string=postgresql://..." \
  -var="anthropic_api_key=sk-ant-..."
```

### Spawn Single Agent

```bash
terraform apply -target=module.agents[\"agent-001\"]
```

### Destroy Cluster

```bash
terraform destroy
```

## Outputs

After successful apply:

```
cluster_summary = <<-EOT
  Cluster: my-cluster
  Region: us-east-1
  Agents: 3
  Model: claude-sonnet-4-20250514
  Spot: true
EOT

agents = {
  "agent-001" = {
    instance_id = "i-0abc123..."
    private_ip = "10.42.10.100"
  }
  "agent-002" = {
    instance_id = "i-0def456..."
    private_ip = "10.42.10.101"
  }
  "agent-003" = {
    instance_id = "i-0ghi789..."
    private_ip = "10.42.10.102"
  }
}
```

## Cost Estimates

| Component | Monthly Cost |
|-----------|--------------|
| NAT Gateway | ~$32 |
| t3.medium (spot) | ~$7-10 per agent |
| t3.medium (on-demand) | ~$30 per agent |

**Example:** 3 agents on spot = ~$50-60/month total

## Troubleshooting

### "No valid credential sources found"
```bash
# Configure AWS credentials
aws configure
# Or export environment variables
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
```

### "Error: Timeout while waiting for instance to become running"
- Check security group allows outbound HTTPS
- Verify subnet has internet access (via NAT or IGW)

### "Agent not registering in Neon"
- Check Neon connection string is correct
- Verify agent can reach Neon endpoint (port 5432)

## Related Docs

- [MANUAL-SPAWN.md](../MANUAL-SPAWN.md) - Manual spawn without Terraform
- [../packer/](../packer/) - AMI building with Packer
- [../INTEGRATION.md](../INTEGRATION.md) - Full system architecture
