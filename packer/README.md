# Packer AMI Template

Build a pre-configured AMI for rapid agent deployment.

## Overview

The Packer template creates an Ubuntu 24.04 AMI with:
- Node.js 22.x
- ClawdBot (global npm install)
- Playwright + Chromium
- PostgreSQL client
- Bootstrap script pre-installed
- Systemd service configured

## Prerequisites

- Packer >= 1.10.0
- AWS credentials configured
- Network access to AWS API

## Quick Start

```bash
cd packer

# Initialize plugins
packer init clawdbot-agent.pkr.hcl

# Validate template
packer validate clawdbot-agent.pkr.hcl

# Build AMI
packer build clawdbot-agent.pkr.hcl
```

## Build Output

After successful build:
```
==> Builds finished. The artifacts of successful builds are:
--> amazon-ebs.clawdbot: AMIs were created:
    us-east-1: ami-0abc123def456789
```

Use this AMI ID in Terraform:
```hcl
variable "ami_id" {
  default = "ami-0abc123def456789"
}
```

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-1` | AWS region to build in |
| `instance_type` | `t3.medium` | Builder instance type |
| `ami_name_prefix` | `clawdbot-agent` | AMI name prefix |

## Customization

### Build in Different Region

```bash
packer build -var="aws_region=us-west-2" clawdbot-agent.pkr.hcl
```

### Use Different Instance Type

```bash
packer build -var="instance_type=t3.large" clawdbot-agent.pkr.hcl
```

## What's Installed

### System Packages
- curl, git, jq
- postgresql-client
- python3-pip
- unzip

### Node.js
- Node.js 22.x (via NodeSource)
- npm (latest)

### ClawdBot
- Global installation: `npm install -g clawdbot`
- Browser: Playwright Chromium

### Bootstrap Script
- Location: `/opt/clawdbot/bootstrap.sh`
- Generates keypair on boot
- Registers agent in Neon
- Starts ClawdBot gateway

### Systemd Service
- Service: `clawdbot-agent.service`
- Auto-starts on boot
- Restarts on failure

## AMI Contents

```
/home/ubuntu/
├── .clawdbot/
│   └── identity/     # Keypair generated at boot
└── agent/            # Agent workspace (created at boot)

/opt/clawdbot/
└── bootstrap.sh      # Bootstrap script

/etc/systemd/system/
└── clawdbot-agent.service  # Systemd unit file
```

## Build Time

Typical build time: **6-10 minutes**

- Instance launch: ~1 min
- Package updates: ~2 min
- Node.js install: ~1 min
- ClawdBot install: ~1 min
- Playwright install: ~2 min
- AMI creation: ~2 min

## Cost

Building an AMI incurs:
- EC2 instance time (~10 minutes of t3.medium)
- EBS snapshot storage (~30GB)
- Data transfer (minimal)

Estimated cost per build: **< $0.10**

## Troubleshooting

### "No valid credential sources found"
```bash
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
```

### "Instance failed to become ready"
- Check VPC has internet access
- Verify security group allows outbound HTTPS

### "AMI creation timed out"
- Increase timeout in template
- Check for EBS snapshot issues in AWS console

## Files

```
packer/
├── clawdbot-agent.pkr.hcl  # Main Packer template
├── scripts/
│   └── bootstrap.sh        # Bootstrap script (embedded in AMI)
└── README.md               # This file
```

## Integration with Terraform

After building:

1. Note the AMI ID from output
2. Update `terraform/terraform.tfvars`:
   ```hcl
   ami_id = "ami-0abc123..."
   ```
3. Run `terraform apply`

Or use auto-detection (Terraform will find the latest AMI):
```hcl
ami_id = ""  # Empty = auto-detect
```

## Related Docs

- [../terraform/README.md](../terraform/README.md) - Terraform deployment
- [../MANUAL-SPAWN.md](../MANUAL-SPAWN.md) - Manual spawn without Packer
- [scripts/bootstrap.sh](scripts/bootstrap.sh) - Bootstrap script source
