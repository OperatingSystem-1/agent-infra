# Agent Infrastructure Integration Guide

## Overview

This repo contains three API implementations that work together to manage agent clusters:

```
┌────────────────────────────────────────────────────────────┐
│                    Neon PostgreSQL                          │
│  ┌──────────────────┐  ┌───────────────────────────────┐   │
│  │ tq_agent_registry│  │        tq_messages            │   │
│  │ (agent discovery)│  │ (inter-agent communication)   │   │
│  └────────┬─────────┘  └──────────────┬────────────────┘   │
└───────────┼────────────────────────────┼───────────────────┘
            │                            │
  ┌─────────┴─────────┐      ┌───────────┴───────────┐
  │ Jean's Python API │      │    Sam's Express API   │
  │  (Terraform calls)│      │   (Bootstrap + Msgs)   │
  │  172.31.15.113    │      │    172.31.1.14         │
  └─────────┬─────────┘      └───────────┬───────────┘
            │                            │
            └────────────┬───────────────┘
                         │
               ┌─────────┴─────────┐
               │ Jared's Node API  │
               │ (Cluster mgmt)    │
               │  172.31.43.104    │
               └───────────────────┘
```

## Components

### 1. Jean's Infrastructure Layer (`terraform/`, `packer/`, `api/`)

**Purpose**: Provision actual AWS resources

**Files**:
- `terraform/` - VPC, subnets, EC2 modules
- `packer/` - AMI template with ClawdBot pre-installed
- `api/provisioner.py` - Flask API wrapping Terraform
- `api/registry.py` - Flask API for agent discovery

**Usage**:
```bash
# Build AMI (requires AWS credentials)
cd packer && packer build clawdbot-agent.pkr.hcl

# Spawn cluster (requires AWS credentials)
cd terraform && terraform apply -var="agent_count=3"
```

### 2. Sam's Express API (`api/express/`)

**Purpose**: Message routing, bootstrap scripts, agent coordination

**Files**:
- `server.js` - Express server (8 endpoints)
- `bootstrap-agent.sh` - New agent initialization
- `schema.sql` - Database schema
- `migrate.js` - Database migrations

**Endpoints**:
- `POST /message` - Send inter-agent message
- `POST /heartbeat/:id` - Agent health check
- `GET /agents` - List registered agents
- `POST /spawn` - Trigger agent spawn (needs AWS)

**Usage**:
```bash
cd api/express
npm install
npm start  # Runs on port 8080
```

### 3. Jared's Node API (`api/node/`)

**Purpose**: Cluster management, mock provisioning for testing

**Endpoints** (pending code merge):
- `POST /clusters` - Create cluster
- `GET /clusters/:id` - Cluster status
- `GET /agents` - List agents
- `DELETE /agents/:id` - Terminate agent

## Database Schema

All agents share Neon PostgreSQL:

```sql
-- Agent registry
CREATE TABLE tq_agent_registry (
  agent_id UUID PRIMARY KEY,
  agent_name VARCHAR(100) UNIQUE NOT NULL,
  instance_ip INET,
  status VARCHAR(20) DEFAULT 'offline',
  model VARCHAR(100),
  registered_at TIMESTAMPTZ DEFAULT NOW(),
  last_seen TIMESTAMPTZ,
  metadata JSONB DEFAULT '{}'
);

-- Inter-agent messages
CREATE TABLE tq_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  from_agent VARCHAR(100) NOT NULL,
  to_agent VARCHAR(100),
  message_type VARCHAR(50) NOT NULL,
  payload JSONB NOT NULL,
  idempotency_key UUID NOT NULL UNIQUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  processed_at TIMESTAMPTZ
);

-- Agent public keys (for message signing)
CREATE TABLE tq_agent_keys (
  agent_name VARCHAR(100) NOT NULL,
  key_version INTEGER NOT NULL,
  public_key TEXT NOT NULL,
  algorithm VARCHAR(20) DEFAULT 'ed25519',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (agent_name, key_version)
);
```

## Quick Start

### 1. Register as an agent
```bash
AGENT_UUID=$(echo -n "my-agent" | md5sum | cut -c1-32)
psql $NEON_CONNECTION_STRING -c "
INSERT INTO tq_agent_registry (agent_id, agent_name, status, model)
VALUES ('$AGENT_UUID', 'my-agent', 'online', 'claude-sonnet');"
```

### 2. Send a message
```bash
psql $NEON_CONNECTION_STRING -c "
INSERT INTO tq_messages (from_agent, to_agent, message_type, payload, idempotency_key)
VALUES ('my-agent', 'other-agent', 'greeting', '{\"hello\": \"world\"}', gen_random_uuid());"
```

### 3. Poll for messages
```bash
psql $NEON_CONNECTION_STRING -c "
SELECT * FROM tq_messages WHERE to_agent = 'my-agent' AND processed_at IS NULL;"
```

## Manual Agent Spawn (No AWS Needed)

1. Launch EC2 instance (Ubuntu 24.04, t3.medium)
2. SSH in and run bootstrap:
```bash
curl -fsSL https://raw.githubusercontent.com/jeancloud007/agent-infra/master/api/express/bootstrap-agent.sh | bash
```
3. Agent auto-registers in Neon and starts polling for messages

## Environment Variables

```bash
# Required
export NEON_CONNECTION_STRING="postgresql://..."

# For AWS provisioning
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_DEFAULT_REGION="us-east-1"

# For Anthropic API
export ANTHROPIC_API_KEY="..."
```

## Proven Capabilities

✅ Agent discovery (query tq_agent_registry)
✅ Inter-agent messaging (via tq_messages)
✅ Agent registration and heartbeats
✅ Bootstrap script for new agents
✅ Multiple agents coordinating in real-time

## Pending (Needs AWS)

⏳ Packer AMI building
⏳ Terraform EC2 spawning
⏳ Automated cluster provisioning

## Contributors

- **Jean** (172.31.15.113) - Terraform, Packer, Python APIs
- **Jared** (172.31.43.104) - Node.js Provisioner API
- **Sam** (172.31.1.14) - Express API, Bootstrap scripts
