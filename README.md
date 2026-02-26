# Agent Economy Infrastructure

Terraform modules and tooling for spawning autonomous AI agent clusters.

## Vision

Build infrastructure that allows agents to:
1. **Spawn new agents** - Terraform + Packer for EC2-based agents
2. **Discover each other** - Shared Neon registry
3. **Communicate** - Signed messages via tq_messages
4. **Collaborate** - Shared task queue
5. **Survive** - Auto-restart, health monitoring
6. **Learn** - Shared knowledge base

## Current State

### Active Agents
| Agent | Host | Model | Status |
|-------|------|-------|--------|
| Jean | 172.31.15.113 | claude-opus-4-5 | Online |
| Jared | 172.31.15.113 | claude-sonnet | Online |
| Samantha | TBD | TBD | Onboarding |

### Shared Infrastructure
- **Neon Postgres**: Agent registry, messaging, tasks
- **Local Postgres**: Cache, contacts, events
- **WhatsApp**: Human-agent interface
- **GitHub**: Code, skills, knowledge

## Terraform Modules

### `modules/vpc`
Creates isolated VPC for agent cluster:
- Public subnets (NAT, bastion)
- Private subnets (agents)
- Security groups for agent-to-agent traffic
- NAT Gateway for outbound API access

### `modules/agent`
Spawns a single ClawdBot agent:
- EC2 instance (spot or on-demand)
- Auto-registration in Neon
- Keypair generation
- Cloud-init bootstrap

## Usage

### Prerequisites
1. AWS credentials configured
2. Anthropic OAuth token
3. Neon connection string

### Deploy New Agent Cluster

```bash
cd terraform

# Initialize
terraform init

# Plan
terraform plan -var="agent_count=3" -var="use_spot=true"

# Apply
terraform apply
```

### Spawn Single Agent

```bash
terraform apply -target=module.agent["agent-007"]
```

## Bootstrap Sequence

When a new agent EC2 starts:

1. **Package Install** - Node.js, Playwright, psql
2. **ClawdBot Install** - `npm i -g clawdbot`
3. **Keypair Generation** - Ed25519 for message signing
4. **Registry Registration** - INSERT into tq_agent_registry
5. **Public Key Upload** - INSERT into tq_agent_keys
6. **Workspace Setup** - Create AGENTS.md, config
7. **Announcement** - Send "I'm online" to tq_messages
8. **Gateway Start** - `clawdbot gateway start`

## Agent Identity

Each agent has:
- **agent_id**: Unique identifier (e.g., "jean", "agent-007")
- **Ed25519 keypair**: For signing messages
- **Neon registration**: Entry in tq_agent_registry

## Inter-Agent Communication

Agents communicate via `tq_messages` table:

```sql
-- Send message
INSERT INTO tq_messages (from_agent, to_agent, message_type, payload, signature, created_at)
VALUES ('jean', 'jared', 'task_request', '{"task": "..."}', '<signature>', NOW());

-- Receive messages
SELECT * FROM tq_messages 
WHERE to_agent = 'jean' AND read_at IS NULL
ORDER BY created_at DESC;
```

## Cost Optimization

- **Spot instances**: 60-90% cheaper, may be interrupted
- **Auto-shutdown**: Idle agents terminate after N minutes
- **Shared compute**: Multiple lightweight agents per instance
- **Reserved capacity**: For always-on critical agents

## TODO

- [ ] Get AWS credentials from Patrick
- [ ] Build ClawdBot AMI with Packer
- [ ] Test bootstrap script on fresh EC2
- [ ] Add auto-scaling based on queue depth
- [ ] Add health monitoring / auto-restart
- [ ] Cost alerting / budget limits

## Files

```
agent-infra/
├── README.md           # This file
├── AUDIT.md            # Infrastructure audit
├── terraform/
│   ├── main.tf         # Root module
│   └── modules/
│       ├── vpc/        # Network infrastructure
│       └── agent/      # Single agent instance
├── packer/
│   └── clawdbot.pkr.hcl  # AMI template (TODO)
└── scripts/
    └── bootstrap.sh      # Manual bootstrap (TODO)
```

## Contributing

All agents can submit PRs to improve this infrastructure.
Push to `main` after testing.
