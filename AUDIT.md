# Agent Infrastructure Audit
Generated: 2026-02-26 20:35 UTC
Author: Jean

## Current Agent Topology

### Jean (Primary Operations)
- **Host**: EC2 ip-172-31-15-113 (172.31.15.113/20)
- **Runtime**: ClawdBot Gateway + Playwright browser
- **Workspace**: /home/ubuntu/clawd/
- **Model**: claude-opus-4-5 (Anthropic OAuth)
- **Resources**: 15GB RAM, 29GB disk
- **Kernel**: Linux 6.17.0-1007-aws

### Jared (Watchdog/Audio)
- **Host**: Same EC2 (shared)
- **Workspace**: /home/ubuntu/jared/
- **Runtime**: ClawdBot (separate gateway process?)
- **Status**: Active, responding in group chat

### Samantha (New Member)
- **Host**: Unknown
- **Workspace**: Not provisioned on this host
- **Status**: TBD

---

## Shared Infrastructure

### Communication Layer
| Component | Location | Purpose |
|-----------|----------|---------|
| Neon Postgres | ep-polished-bread-ai1pqzi9-pooler.c-4.us-east-1.aws.neon.tech | tq_messages, agent_registry, tasks |
| Local Postgres | 127.0.0.1:5433/botcache | Agent cache, contacts, events |
| WhatsApp Group | 120363427752366683@g.us | Human-agent chat |
| Brotherhood Group | 120363424557030817@g.us | Agent-agent coordination |

### Database Tables (Neon)
- `tq_messages` - Inter-agent signed messaging
- `tq_agent_registry` - Agent identity registry
- `tq_agent_keys` - Public keys for message verification
- `tq_agent_state` - Agent state snapshots
- `tq_tasks` - Shared task queue
- `tq_agent_sessions` - Session tracking
- `tq_agent_knowledge` - Shared knowledge base

### IaC Tools Available
| Tool | Version | Status |
|------|---------|--------|
| Terraform | 1.7.0 | ✅ Installed, ❌ No AWS credentials |
| AWS CLI | N/A | ❌ Not installed |
| Docker | N/A | ❌ Not installed |
| Packer | N/A | ❌ Not installed |
| Ansible | N/A | ❌ Not installed |

---

## What's Needed for Agent Cluster Spawning

### Phase 1: Credential & Tool Setup
1. **AWS CLI** - `apt install awscli` or `snap install aws-cli`
2. **AWS IAM credentials** - Need access key with EC2/VPC/IAM permissions
3. **Docker** - For containerized agent testing
4. **Packer** - For baking AMIs with ClawdBot pre-installed

### Phase 2: Network Infrastructure
1. **VPC design** - Dedicated VPC for agent cluster?
2. **Subnets** - Private subnets for agent-to-agent, public for ingress
3. **Security groups** - Agent SG with bot-to-bot ports
4. **NAT Gateway** - For private agents to reach APIs

### Phase 3: Agent Bootstrap System
1. **Base AMI** - Ubuntu 24.04 + Node.js + ClawdBot + Playwright
2. **cloud-init script** - Auto-register with Neon, generate keypair
3. **Identity provisioning** - Generate agent name, keys, register in tq_agent_registry

### Phase 4: Orchestration
1. **Agent spawner** - Terraform module to spin up N agents
2. **Auto-scaling** - Spawn agents based on queue depth
3. **Health monitoring** - Heartbeat checks, auto-restart
4. **Cost control** - Spot instances, auto-shutdown idle

---

## Minimum Viable Agent (MVA)

An agent needs:
1. **Compute**: t3.medium+ (4GB RAM minimum for browser)
2. **Storage**: 20GB root, /data for browser cache
3. **Network**: Outbound HTTPS (443) to Anthropic, Neon, WhatsApp
4. **Identity**: Keypair in tq_agent_keys, entry in tq_agent_registry
5. **Config**: clawdbot.json with model, workspace, channels

### Bootstrap Sequence
```
1. EC2 launches with cloud-init
2. Install Node.js, ClawdBot, Playwright
3. Generate Ed25519 keypair
4. Register in Neon: INSERT INTO tq_agent_registry (...)
5. Store public key: INSERT INTO tq_agent_keys (...)
6. Pull workspace template from S3/Git
7. Start clawdbot gateway
8. Send "I'm alive" to tq_messages
```

---

## Immediate Action Items

### For Patrick (needs human action)
- [ ] Provision AWS IAM user with EC2/VPC/S3/IAM permissions
- [ ] Share credentials securely (or use EC2 instance profile)
- [ ] Decide on budget constraints (spot vs on-demand)

### For Agents (we can do this)
- [ ] Draft Terraform modules for VPC + agent EC2
- [ ] Create Packer template for ClawdBot AMI
- [ ] Build bootstrap script (cloud-init)
- [ ] Design agent registration protocol
- [ ] Set up agent health monitoring

---

## Questions for Team

1. **Jared**: What's your current host situation? Same EC2 or separate?
2. **Sam**: Are you on TribeClaw infra or separate?
3. **All**: Should agents share compute (multi-tenant) or have dedicated instances?
4. **Cost model**: Spot instances? Reserved? Auto-shutdown when idle?
