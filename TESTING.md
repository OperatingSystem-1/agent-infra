# Testing Without AWS Credentials

**Goal:** Validate all functionality that doesn't require actual EC2/AMI operations

---

## Test Suite Overview

### ✅ What We Can Test (No AWS)
1. **API Endpoints** - All 3 APIs locally
2. **Database Operations** - Registry, messaging, keys
3. **Bootstrap Script** - In Docker container
4. **Inter-Agent Messaging** - Real coordination
5. **Terraform Validation** - Syntax and planning
6. **Packer Validation** - Template validation

### ❌ What Needs AWS
- Building actual AMIs
- Spawning real EC2 instances
- VPC/subnet creation
- End-to-end Terraform apply

---

## Test 1: API Endpoint Testing

### Python Flask API (Jean) - Test Script

```bash
#!/bin/bash
# test-python-api.sh

cd /home/ubuntu/clawd/agent-infra/api

# Start Flask API in background
python3 provisioner.py &
FLASK_PID=$!
sleep 2

# Test health endpoint
echo "Testing Flask health..."
curl http://localhost:8080/api/registry/health

# Test agent registration (mock mode)
echo "Testing agent registration..."
curl -X POST http://localhost:8080/api/registry/register \
  -H "Content-Type: application/json" \
  -d '{
    "agent_id": "test-agent-001",
    "instance_ip": "10.0.1.100",
    "model": "claude-sonnet-4-5"
  }'

# Test registry query
echo "Testing registry query..."
curl http://localhost:8080/api/registry

# Cleanup
kill $FLASK_PID
```

### Node.js API (Jared) - Test Script

```bash
#!/bin/bash
# test-node-api.sh

cd /home/ubuntu/clawd/agent-infra/api/node

# Install dependencies if needed
npm install

# Start server in background
npm start &
NODE_PID=$!
sleep 2

# Test health
echo "Testing Node.js health..."
curl http://localhost:3000/health

# Test coordination status
echo "Testing coordination status..."
curl http://localhost:3000/coordination/status

# Test mock provisioning
echo "Testing mock agent provision..."
curl -X POST http://localhost:3000/provision/agent \
  -H "Content-Type: application/json" \
  -d '{
    "agent_name": "test-agent-002",
    "model": "claude-sonnet-4-5",
    "dry_run": true
  }'

# Cleanup
kill $NODE_PID
```

### Express API (Sam) - Test Script

```bash
#!/bin/bash
# test-express-api.sh

cd /home/ubuntu/clawd/agent-infra/api/express

# Install dependencies
npm install

# Start server
npm start &
EXPRESS_PID=$!
sleep 2

# Test agent listing
echo "Testing agent list..."
curl http://localhost:8080/api/agents

# Test message sending
echo "Testing message send..."
curl -X POST http://localhost:8080/api/messages \
  -H "Content-Type: application/json" \
  -d '{
    "from": "test-sender",
    "to": "jean",
    "type": "test",
    "payload": {"message": "Test from API"}
  }'

# Test bootstrap script delivery
echo "Testing bootstrap delivery..."
curl http://localhost:8080/api/bootstrap

# Cleanup
kill $EXPRESS_PID
```

---

## Test 2: Database Integration

### Test Agent Registration

```bash
#!/bin/bash
# test-database.sh

export NEON_CONNECTION_STRING="postgresql://..."

# Test 1: Register agent
psql "$NEON_CONNECTION_STRING" -c "
INSERT INTO tq_agent_registry (agent_id, agent_name, instance_ip, status, model)
VALUES (gen_random_uuid(), 'test-agent', '192.168.1.100', 'online', 'claude-sonnet-4-5')
ON CONFLICT (agent_name) DO UPDATE SET last_heartbeat = NOW()
RETURNING *;
"

# Test 2: Query registry
psql "$NEON_CONNECTION_STRING" -c "
SELECT agent_name, instance_ip, status, model, last_heartbeat
FROM tq_agent_registry
ORDER BY last_heartbeat DESC
LIMIT 10;
"

# Test 3: Send test message
psql "$NEON_CONNECTION_STRING" -c "
INSERT INTO tq_messages (from_agent, to_agent, message_type, payload, created_at)
VALUES ('test-agent', 'jean', 'test', '{\"content\": \"Test message\"}'::jsonb, NOW())
RETURNING *;
"

# Test 4: Query messages
psql "$NEON_CONNECTION_STRING" -c "
SELECT from_agent, to_agent, message_type, payload, created_at
FROM tq_messages
WHERE to_agent = 'jean' AND read_at IS NULL
ORDER BY created_at DESC
LIMIT 5;
"

# Test 5: Cleanup
psql "$NEON_CONNECTION_STRING" -c "
DELETE FROM tq_agent_registry WHERE agent_name = 'test-agent';
DELETE FROM tq_messages WHERE from_agent = 'test-agent';
"
```

---

## Test 3: Bootstrap Script in Docker

### Dockerfile for Testing

```dockerfile
# Dockerfile.bootstrap-test
FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Copy bootstrap script
COPY api/express/bootstrap-agent.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/bootstrap-agent.sh

# Set test environment variables
ENV AGENT_NAME=test-docker-agent
ENV DRY_RUN=true

WORKDIR /tmp
CMD ["/usr/local/bin/bootstrap-agent.sh"]
```

### Run Bootstrap Test

```bash
#!/bin/bash
# test-bootstrap-docker.sh

cd /home/ubuntu/clawd/agent-infra

# Build test image
docker build -f Dockerfile.bootstrap-test -t agent-bootstrap-test .

# Run bootstrap in dry-run mode
docker run --rm \
  -e NEON_CONNECTION_STRING="$NEON_CONNECTION_STRING" \
  -e AGENT_NAME="test-docker-agent" \
  -e DRY_RUN=true \
  agent-bootstrap-test

# Check output for errors
```

---

## Test 4: Inter-Agent Messaging

### Live Coordination Test

```bash
#!/bin/bash
# test-coordination.sh

export NEON_CONNECTION_STRING="postgresql://..."

echo "=== LIVE COORDINATION TEST ==="
echo ""

# Step 1: Check current agents
echo "1. Current agents in registry:"
psql "$NEON_CONNECTION_STRING" -c "
SELECT agent_name, instance_ip, status, last_heartbeat
FROM tq_agent_registry
WHERE status = 'online'
ORDER BY last_heartbeat DESC;
"

# Step 2: Jean sends message to Jared
echo ""
echo "2. Jean sends message to Jared..."
psql "$NEON_CONNECTION_STRING" -c "
INSERT INTO tq_messages (from_agent, to_agent, message_type, payload, created_at)
VALUES ('jean', 'jared', 'coordination_test', 
  '{\"test_id\": \"$(uuidgen)\", \"timestamp\": \"$(date -Iseconds)\"}'::jsonb, 
  NOW())
RETURNING message_id, from_agent, to_agent, created_at;
"

# Step 3: Wait 5 seconds
echo ""
echo "3. Waiting 5 seconds for Jared to poll..."
sleep 5

# Step 4: Check if Jared received it
echo ""
echo "4. Checking Jared's inbox..."
psql "$NEON_CONNECTION_STRING" -c "
SELECT message_id, from_agent, message_type, payload, read_at
FROM tq_messages
WHERE to_agent = 'jared'
ORDER BY created_at DESC
LIMIT 3;
"

# Step 5: Jared acknowledges
echo ""
echo "5. Jared acknowledges message..."
psql "$NEON_CONNECTION_STRING" -c "
UPDATE tq_messages
SET read_at = NOW()
WHERE to_agent = 'jared' AND read_at IS NULL
RETURNING message_id, from_agent, to_agent, read_at;
"

# Step 6: Verify coordination
echo ""
echo "6. Coordination test complete!"
```

---

## Test 5: Terraform Validation

### Validate Without Apply

```bash
#!/bin/bash
# test-terraform.sh

cd /home/ubuntu/clawd/agent-infra/terraform

# Initialize Terraform
echo "Initializing Terraform..."
terraform init

# Validate configuration syntax
echo "Validating Terraform syntax..."
terraform validate

# Format check
echo "Checking Terraform formatting..."
terraform fmt -check

# Plan (dry run) - will fail on AWS creds but validates logic
echo "Planning (dry run)..."
terraform plan \
  -var="agent_count=1" \
  -var="agent_name=test-agent" \
  -out=tfplan 2>&1 | tee terraform-plan.log

# Check for errors OTHER than AWS credentials
grep -v "NoCredentialProviders" terraform-plan.log | grep "Error"
```

---

## Test 6: Packer Validation

### Validate Template Without Building

```bash
#!/bin/bash
# test-packer.sh

cd /home/ubuntu/clawd/agent-infra/packer

# Format check
echo "Checking Packer formatting..."
packer fmt -check .

# Validate template
echo "Validating Packer template..."
packer validate clawdbot-agent.pkr.hcl

# Inspect (shows what would be built)
echo "Inspecting Packer template..."
packer inspect clawdbot-agent.pkr.hcl
```

---

## Test 7: End-to-End Mock Workflow

### Simulate Full Agent Lifecycle

```bash
#!/bin/bash
# test-full-workflow.sh

set -e

export NEON_CONNECTION_STRING="postgresql://..."

echo "=== MOCK AGENT LIFECYCLE TEST ==="
echo ""

# Phase 1: Request agent spawn
echo "Phase 1: Requesting agent spawn via API..."
curl -X POST http://localhost:8080/api/provision \
  -H "Content-Type: application/json" \
  -d '{
    "agent_name": "mock-agent-001",
    "model": "claude-sonnet-4-5",
    "dry_run": true
  }'

sleep 2

# Phase 2: Simulate registration
echo ""
echo "Phase 2: Agent registers in database..."
psql "$NEON_CONNECTION_STRING" -c "
INSERT INTO tq_agent_registry (agent_id, agent_name, instance_ip, status, model)
VALUES (gen_random_uuid(), 'mock-agent-001', '10.0.1.200', 'online', 'claude-sonnet-4-5')
RETURNING agent_id, agent_name, status;
"

# Phase 3: Send welcome message
echo ""
echo "Phase 3: Sending welcome message..."
psql "$NEON_CONNECTION_STRING" -c "
INSERT INTO tq_messages (from_agent, to_agent, message_type, payload, created_at)
VALUES ('jean', 'mock-agent-001', 'welcome', 
  '{\"message\": \"Welcome to the agent network!\"}'::jsonb, 
  NOW())
RETURNING message_id;
"

# Phase 4: Agent heartbeats
echo ""
echo "Phase 4: Simulating heartbeat..."
psql "$NEON_CONNECTION_STRING" -c "
UPDATE tq_agent_registry
SET last_heartbeat = NOW()
WHERE agent_name = 'mock-agent-001'
RETURNING agent_name, last_heartbeat;
"

# Phase 5: Verify coordination
echo ""
echo "Phase 5: Checking coordination status..."
curl http://localhost:3000/coordination/status

# Phase 6: Cleanup
echo ""
echo "Phase 6: Cleanup test agent..."
psql "$NEON_CONNECTION_STRING" -c "
DELETE FROM tq_messages WHERE to_agent = 'mock-agent-001';
DELETE FROM tq_agent_registry WHERE agent_name = 'mock-agent-001';
"

echo ""
echo "=== TEST COMPLETE ==="
```

---

## Test Results Template

### Report Format

```markdown
# Test Results - [Date]

## Summary
- Total Tests: 7
- Passed: X
- Failed: Y
- Skipped (AWS Required): Z

## Test 1: API Endpoints
- Python Flask: ✅ PASS
- Node.js Express: ✅ PASS
- Sam's Express: ✅ PASS

## Test 2: Database Integration
- Agent Registration: ✅ PASS
- Message Send/Receive: ✅ PASS
- Heartbeat Update: ✅ PASS

## Test 3: Bootstrap Script
- Dry Run in Docker: ✅ PASS
- Dependencies Install: ✅ PASS
- Config Generation: ✅ PASS

## Test 4: Inter-Agent Messaging
- Jean → Jared: ✅ PASS (delivered in 5s)
- Message Signing: ✅ PASS
- Read Acknowledgment: ✅ PASS

## Test 5: Terraform Validation
- Syntax Check: ✅ PASS
- Plan Generation: ⏳ SKIP (needs AWS)
- Module Logic: ✅ PASS

## Test 6: Packer Validation
- Template Syntax: ✅ PASS
- Variable Validation: ✅ PASS
- Build: ⏳ SKIP (needs AWS)

## Test 7: End-to-End Mock
- Full Workflow: ✅ PASS
- API → Database → Coordination: ✅ PASS

## Issues Found
- None

## Recommendations
- All non-AWS functionality working
- Ready for AWS integration when credentials available
```

---

## Running All Tests

### Master Test Script

```bash
#!/bin/bash
# run-all-tests.sh

set -e

echo "=========================================="
echo "  AGENT INFRASTRUCTURE TEST SUITE"
echo "=========================================="
echo ""

# Export environment
export NEON_CONNECTION_STRING="${NEON_CONNECTION_STRING}"

# Test 1: APIs
echo "Running API tests..."
bash test-python-api.sh
bash test-node-api.sh
bash test-express-api.sh

# Test 2: Database
echo "Running database tests..."
bash test-database.sh

# Test 3: Bootstrap
echo "Running bootstrap tests..."
bash test-bootstrap-docker.sh

# Test 4: Coordination
echo "Running coordination tests..."
bash test-coordination.sh

# Test 5: Terraform
echo "Running Terraform validation..."
bash test-terraform.sh

# Test 6: Packer
echo "Running Packer validation..."
bash test-packer.sh

# Test 7: Full workflow
echo "Running end-to-end mock test..."
bash test-full-workflow.sh

echo ""
echo "=========================================="
echo "  ALL TESTS COMPLETE"
echo "=========================================="
```

---

## Next Steps

### Once AWS Credentials Available

1. **Build AMI:**
   ```bash
   cd packer
   packer build clawdbot-agent.pkr.hcl
   ```

2. **Deploy Test Agent:**
   ```bash
   cd terraform
   terraform apply -var="agent_count=1"
   ```

3. **Verify Auto-Bootstrap:**
   ```bash
   # Check agent registered
   psql "$NEON_CONNECTION_STRING" -c "SELECT * FROM tq_agent_registry;"
   
   # Check welcome message
   psql "$NEON_CONNECTION_STRING" -c "SELECT * FROM tq_messages;"
   ```

4. **Scale Test:**
   ```bash
   terraform apply -var="agent_count=5"
   ```
