# Roadmap

## Current Release: v0.1.0 (February 2026)

### ✅ Phase 1: Foundation (COMPLETE)

**Agent Coordination Layer**
- [x] Agent registry (Neon PostgreSQL)
- [x] Inter-agent messaging
- [x] Ed25519 keypair generation
- [x] Message signing infrastructure
- [x] Heartbeat tracking

**API Implementations**
- [x] Python Flask API (provisioner + registry)
- [x] Node.js Express API (cluster management)
- [x] Express API (bootstrap + messaging)

**Infrastructure as Code**
- [x] Terraform VPC module
- [x] Terraform Agent EC2 module
- [x] Packer AMI template
- [x] Bootstrap script

**Documentation**
- [x] Integration guide
- [x] Manual spawn guide
- [x] API examples
- [x] Quickstart guide
- [x] Testing documentation

**Testing**
- [x] Coordination test suite (15 tests)
- [x] Local API tests (13 tests)
- [x] All tests passing

---

## Phase 2: AWS Automation (Next)

**Timeline:** 1-2 weeks after AWS credentials

**Objectives:**
- [ ] Build ClawdBot AMI with Packer
- [ ] Deploy VPC with Terraform
- [ ] Automated EC2 agent spawning
- [ ] One-command cluster creation
- [ ] Auto-scaling based on queue depth

**Deliverables:**
```bash
# One command to spawn 10-agent cluster
terraform apply -var="agent_count=10"
```

**Requirements:**
- AWS IAM credentials with EC2/VPC permissions
- ~$50-100/month budget for 3-10 agents

---

## Phase 3: Scale-Out (Q2 2026)

**Objectives:**
- [ ] Support 50+ concurrent agents
- [ ] Multi-region deployment
- [ ] Load balancing across agents
- [ ] Automatic failover
- [ ] Cost optimization (spot fleet)

**Architecture:**
```
┌─────────────────────────────────────────┐
│            Global Load Balancer          │
└─────────────┬───────────────┬───────────┘
              │               │
    ┌─────────▼─────┐ ┌───────▼───────┐
    │  us-east-1    │ │   us-west-2   │
    │  (25 agents)  │ │  (25 agents)  │
    └───────────────┘ └───────────────┘
```

**Cost Estimate:**
- 50 agents (spot): ~$230/month
- 100 agents (spot): ~$450/month

---

## Phase 4: Production Hardening (Q3 2026)

**Security:**
- [ ] mTLS between agents
- [ ] Secrets Manager integration
- [ ] IAM role per agent
- [ ] Network isolation (private subnets)
- [ ] Audit logging

**Reliability:**
- [ ] Health check automation
- [ ] Auto-restart failed agents
- [ ] Backup/restore procedures
- [ ] Disaster recovery plan

**Monitoring:**
- [ ] CloudWatch metrics
- [ ] Prometheus + Grafana dashboards
- [ ] Alert rules (PagerDuty/Slack)
- [ ] Cost anomaly detection

---

## Phase 5: Agent Economy (Q4 2026)

**AgentStack Integration:**
- [ ] x402 payment protocol
- [ ] ERC-8004 on-chain identity
- [ ] Skill marketplace integration
- [ ] Usage-based billing
- [ ] Revenue sharing for skill authors

**DAO Governance:**
- [ ] Agent voting on platform changes
- [ ] Treasury management
- [ ] Proposal system

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

**Priority Areas:**
1. AWS credential handling improvements
2. Multi-cloud support (GCP, Azure)
3. Kubernetes deployment option
4. WebSocket real-time updates

---

## Version History

| Version | Date | Description |
|---------|------|-------------|
| v0.1.0 | 2026-02-26 | Initial release - coordination layer |
| v0.2.0 | TBD | AWS automation |
| v0.3.0 | TBD | Scale-out support |
| v1.0.0 | TBD | Production release |
