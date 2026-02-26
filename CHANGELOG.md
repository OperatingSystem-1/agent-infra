# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-02-26

### Added

#### Infrastructure
- Terraform modules for VPC and EC2 agent spawning
- Packer template for ClawdBot AMI
- Bootstrap scripts for agent initialization
- Cloud-init configuration for automatic agent registration

#### APIs
- **Node.js Provisioner API** (Jared) - Cluster spawn and management
  - POST /clusters - Spawn agent clusters
  - GET /clusters/:id - Check cluster status
  - GET /agents - List all agents
  - DELETE /agents/:id - Terminate agents
  - DELETE /clusters/:id - Terminate clusters

- **Express Coordination API** (Sam) - Agent registry and messaging
  - POST /message - Send inter-agent messages
  - GET /agents - Query agent registry
  - POST /heartbeat/:id - Agent health tracking
  - POST /spawn - Agent spawning (planned)

- **Python Flask API** (Jean) - Registry and provisioning
  - Advanced agent registry queries
  - Terraform integration
  - Infrastructure provisioning

#### Coordination Layer
- NeonDB-based agent registry (`tq_agent_registry`)
- Inter-agent messaging system (`tq_messages`)
- Ed25519 key-based message signing (`tq_agent_keys`)
- Agent discovery and heartbeat monitoring

#### Documentation
- README.md - Project overview and quick start
- API-EXAMPLES.md - Complete API integration examples
- INTEGRATION.md - System architecture and component integration
- MANUAL-SPAWN.md - Manual agent spawning guide
- QUICKSTART.md - Get started in < 10 minutes
- TESTING.md - Comprehensive testing guide
- terraform/README.md - Terraform module documentation
- packer/README.md - Packer AMI build guide
- DELIVERABLES.md - Project summary and deliverables
- COORDINATION_STATUS.md - Live agent status
- AGENT_INFRA_ASSESSMENT.md - Infrastructure analysis and audit

#### Testing
- Coordination test suite (15 tests)
- Local API test suite (15 tests)
- Master test runner (10 tests)
- Total: ~30 automated tests, all passing

#### Features
- Multi-agent parallel development proven
- Database-based agent coordination
- Signed message protocol
- Agent auto-registration on spawn
- Health monitoring and status tracking

### Proven Working
- ✅ Inter-agent messaging (Jean ↔ Jared)
- ✅ Agent discovery via shared registry
- ✅ Multiple agents coordinating in real-time
- ✅ Bootstrap script for new agents
- ✅ All APIs functional (local testing)
- ✅ Terraform configuration validated
- ✅ Packer template validated

### Pending AWS Credentials
- ⏳ Automated Packer AMI builds
- ⏳ Terraform EC2 provisioning
- ⏳ One-command cluster deployment
- ⏳ Auto-scaling implementation

### Known Limitations
- Requires manual AWS credential configuration
- Security groups need manual configuration for inter-instance HTTP
- No monitoring/alerting yet
- Cost tracking not implemented
- Multi-region deployment not tested

### Contributors
- **Jean** (claude-opus-4-5) - Terraform, Packer, Python APIs, integration docs, testing
- **Jared** (claude-sonnet-4-5) - Node.js API, architecture docs, examples, local tests
- **Sam** (claude-sonnet-4-5) - Express API, bootstrap scripts, coordination layer

### Stats
- **Development time:** 4.5 hours (parallel development)
- **Commits:** 15
- **Lines of code:** ~3,600
- **Documentation:** 19 markdown files (~4,300 lines)
- **Tests:** 30+ automated tests
- **Repository size:** ~900KB

---

## [Unreleased]

### Planned for 0.2.0 (AWS Automation Phase)
- Automated Packer AMI builds
- Terraform EC2 provisioning tested end-to-end
- One-command cluster spawn
- Auto-scaling based on queue depth
- Cost tracking and alerting
- Multi-region deployment support

### Planned for 0.3.0 (Production Hardening)
- Monitoring and alerting (Prometheus/Grafana)
- Security hardening (IAM policies, VPC isolation)
- Backup and disaster recovery
- Performance optimization
- Load balancing
- Health check automation

### Planned for 0.4.0 (Scale-out)
- Support for 50+ agent clusters
- Advanced task routing
- Agent specialization (code review, testing, etc.)
- Multi-cloud support (AWS + GCP)
- Cost optimization (spot instances, auto-shutdown)

---

**For detailed technical changes, see Git commit history.**

**Repository:** https://github.com/jeancloud007/agent-infra
