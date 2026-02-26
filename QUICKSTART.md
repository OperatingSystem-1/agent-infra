# Agent Cluster Quick Start

**Goal**: Spawn N agents in < 10 minutes

## Prerequisites

1. AWS credentials configured:
```bash
aws configure
# Or export AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY (see AWS docs)
```

2. Neon connection string (we have this)
3. Anthropic API key

## Option A: Fast Path (Use Base Ubuntu AMI)

This skips the Packer build and bootstraps agents from scratch at launch. Slower startup (~5 min per agent) but works immediately.

```bash
cd /home/ubuntu/clawd/projects/agent-infra/terraform

# Copy and edit tfvars
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Initialize
terraform init

# Plan (review what will be created)
terraform plan

# Apply (spawns the cluster)
terraform apply -auto-approve
```

## Option B: With Packer AMI (Recommended for Production)

Pre-bake the AMI so agents start in < 2 minutes.

```bash
cd /home/ubuntu/clawd/projects/agent-infra/packer

# Build the AMI
packer init clawdbot-agent.pkr.hcl
packer build clawdbot-agent.pkr.hcl

# Note the AMI ID from output, then:
cd ../terraform
terraform apply -var="ami_id=ami-xxxxx"
```

## Spawn More Agents

```bash
# Add 5 more agents
terraform apply -var="agent_count=8"
```

## Destroy Cluster

```bash
terraform destroy -auto-approve
```

## Cost Estimates

| Instance Type | Spot Price | On-Demand | Monthly (24/7) |
|--------------|------------|-----------|----------------|
| t3.medium    | ~$0.01/hr  | $0.04/hr  | $7-30/agent   |
| t3.large     | ~$0.02/hr  | $0.08/hr  | $15-60/agent  |

Shared infra (NAT Gateway): ~$32/month

## Monitoring

Check agent status:
```sql
SELECT agent_id, status, instance_ip, last_seen 
FROM tq_agent_registry 
ORDER BY last_seen DESC;
```

Check announcements:
```sql
SELECT * FROM tq_messages 
WHERE message_type = 'announcement' 
ORDER BY created_at DESC LIMIT 10;
```

## Troubleshooting

**Agent not registering**: Check cloud-init logs
```bash
ssh ubuntu@<agent-ip> 'cat /var/log/clawdbot-bootstrap.log'
```

**ClawdBot not starting**: Check systemd
```bash
ssh ubuntu@<agent-ip> 'sudo systemctl status clawdbot-agent'
```
