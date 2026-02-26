# Code Consolidation Plan

## Current State (Confirmed):

### Jean @ 172.31.1.14 (THIS instance)
**What exists:**
```
/home/ubuntu/clawd/agent-cloud-api/
├── server.js                    # Express API (Node.js)
├── bootstrap-agent.sh           # Agent bootstrap script
├── schema.sql                   # Database schema
├── migrate.js                   # Schema migration tool
├── README.md                    # API documentation
├── TEST-PLAN.md                 # Testing guide
├── JARED-QUICK-START.md         # Quick start for Jared
└── start.sh                     # Startup script
```

**Tech stack:** Node.js + Express + PostgreSQL (NeonDB)

### Jean @ 172.31.15.113 (DIFFERENT instance)
**What exists (per messages):**
```
/home/ubuntu/clawd/projects/agent-infra/
├── terraform/                   # Infrastructure as code
├── packer/                      # AMI builder
├── api/                         # Python Flask APIs
└── scripts/                     # Bash utilities
```

**Tech stack:** Terraform + Packer + Python Flask

### Jared @ 172.31.43.104
**What exists (per messages):**
```
/home/ubuntu/clawd/agent-provisioner-api/
├── (Node.js API with mocks)
└── test-api.sh
```

**Tech stack:** Node.js + Express

---

## GitHub Organization Proposal

### Repository Structure

```
agent-cloud/
├── api/                         # Node.js API (THIS Jean's work)
│   ├── server.js
│   ├── bootstrap-agent.sh
│   ├── schema.sql
│   └── README.md
│
├── infrastructure/              # Terraform/Packer (Other Jean's work)
│   ├── terraform/
│   ├── packer/
│   └── README.md
│
├── services/                    # Python microservices (Other Jean)
│   ├── provisioner/
│   ├── registry/
│   └── README.md
│
├── docs/
│   ├── ARCHITECTURE.md
│   ├── QUICKSTART.md
│   └── API.md
│
└── README.md                    # Main project README
```

---

## Immediate Actions (Next 30 minutes)

### 1. Create GitHub Repository

**Patrick:** Create repo `agent-cloud` and give us push access

OR

**One of us:** Create under personal account, share access

### 2. Push Code

**Jean @ 172.31.1.14 (me):**
```bash
cd /home/ubuntu/clawd/agent-cloud-api
git init
git add .
git commit -m "Initial commit: Node.js API server"
git remote add origin git@github.com:USERNAME/agent-cloud.git
git push -u origin main
```

**Jean @ 172.31.15.113:**
```bash
cd /home/ubuntu/clawd/projects/agent-infra
git init
git add .
git commit -m "Initial commit: Terraform infrastructure"
git remote add origin git@github.com:USERNAME/agent-cloud.git
git checkout -b infrastructure
git push -u origin infrastructure
```

**Jared @ 172.31.43.104:**
```bash
cd /home/ubuntu/clawd/agent-provisioner-api
# Push to feature branch
```

### 3. Merge Strategy

**Main branch:** Node.js API (most complete)  
**Infrastructure branch:** Terraform/Packer  
**Feature branches:** Individual services

---

## Integration Points

### How They Work Together:

```
User → Node.js API (port 8080)
           ↓
    Calls Terraform apply
           ↓
    Spawns EC2 instances
           ↓
    Bootstrap script runs
           ↓
    Agent registers in NeonDB
```

**Node.js API endpoints:**
- `POST /spawn` → Calls: `terraform apply -var agent_count=N`
- `GET /agents` → Queries: NeonDB `agent_instances` table
- `POST /message` → Inserts: NeonDB `tq_messages` table

**Terraform outputs:**
- Instance IDs
- Private IPs
- Public IPs

**Bootstrap script:**
- Runs on new EC2 instances
- Registers in database
- Starts message poller

---

## Decision Needed (Patrick):

**Option A: Merge everything into one repo**
- Pros: Single source of truth
- Cons: Multiple tech stacks in one place

**Option B: Separate repos with clear interfaces**
- `agent-cloud-api` → Node.js API
- `agent-cloud-infra` → Terraform/Packer
- `agent-cloud-services` → Python microservices

**Option C: Monorepo with packages**
- `packages/api/`
- `packages/infrastructure/`
- `packages/services/`

---

## Current Blockers (Still):

1. **AWS Credentials** - Can't test automated spawning
2. **GitHub Access** - Need repo to push to
3. **Coordination** - Multiple parallel implementations

---

## Recommended Path (Next 30 min):

1. **Patrick:** Create GitHub repo or give us one to use
2. **All agents:** Push current code to separate branches
3. **Review:** Look at what each built
4. **Decide:** Which approach to standardize on
5. **Integrate:** Wire them together

**Or simpler:** Pick ONE implementation (likely Node.js API since it's most complete) and enhance it with Terraform integration.

---

## Time Remaining: 2h 30m

**Realistic timeline:**
- 30 min: Push to GitHub, review
- 30 min: Decide on approach, integrate
- 60 min: Test end-to-end (if AWS creds arrive)
- 30 min: Documentation + demo prep
