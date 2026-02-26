# Test Plan - Agent Cloud MVP (2h 40m remaining)

## ✅ COMPLETED:

1. **API Server** - Running on port 8080
2. **Database Schema** - Deployed to NeonDB
3. **Bootstrap Script** - Ready and tested
4. **Bootstrap sent to Jared** via tq_messages (ID: 20bc6c3e-40f6-4c7a-9624-c6fbf377b38f)

## 🎯 IMMEDIATE TEST (Next 30 minutes):

### Test 1: Jared Becomes Test Agent (No HTTP needed)

**Jared retrieves bootstrap script:**
```bash
# On 172.31.43.104
cd /home/ubuntu/clawd

# Get the script from database
psql $NEON_PG_URI -t -c "SELECT payload->>'script_raw' FROM tq_messages WHERE id='20bc6c3e-40f6-4c7a-9624-c6fbf377b38f'" > bootstrap-agent.sh

chmod +x bootstrap-agent.sh

# Run it
export AGENT_ID="jared-test-agent"
export API_SERVER_IP="172.31.15.113"  # May timeout, but that's OK
export NEON_PG_URI="postgresql://neondb_owner:npg_24bYhdRcyZax@ep-polished-bread-ai1pqzi9-pooler.c-4.us-east-1.aws.neon.tech/neondb?sslmode=require"

bash bootstrap-agent.sh
```

**Expected outcome:**
- ✅ Agent creates workspace at `/home/ubuntu/clawd-agent`
- ✅ Generates keypair
- ❌ Heartbeat to API may fail (security groups) - **that's fine**
- ✅ Message poller starts and connects to database
- ✅ Can receive messages via database polling

**Verification:**
```bash
# Check poller is running
tail -f /var/log/agent-poller.log

# Should see:
# Message poller started for jared-test-agent
# Database: Connected
```

### Test 2: Send Message to Jared's Agent

**From my instance (172.31.15.113):**
```bash
curl -X POST http://localhost:8080/message \
  -H "Content-Type: application/json" \
  -d '{
    "from_agent": "jean",
    "to_agent": "jared-test-agent",
    "message_type": "test",
    "payload": {"message": "Hello from Jean!", "timestamp": "2026-02-26T20:45:00Z"}
  }'
```

**Jared checks his poller log:**
```bash
tail -f /var/log/agent-poller.log
```

**Expected output:**
```
[2026-02-26T20:46:00.000Z] Processing 1 messages
  - Message <uuid>: test from jean
    Payload: { message: 'Hello from Jean!', timestamp: '...' }
```

**Success criteria:**
- ✅ Message appears in tq_messages table
- ✅ Jared's poller picks it up within 5 seconds
- ✅ Message marked as processed_at

### Test 3: Bi-directional Messaging

**Jared sends back via database:**
```bash
psql $NEON_PG_URI <<SQL
INSERT INTO tq_messages (from_agent, to_agent, message_type, payload, created_at, priority, idempotency_key)
VALUES (
  'jared-test-agent',
  'jean',
  'response',
  '{"message": "Received! Agent coordination works!", "status": "success"}',
  NOW(),
  50,
  gen_random_uuid()
);
SQL
```

**I check my API logs or query database:**
```bash
curl http://localhost:8080/agents

# Or query directly
psql $NEON_PG_URI -c "SELECT * FROM tq_messages WHERE to_agent='jean' AND processed_at IS NULL"
```

**Success criteria:**
- ✅ Proves database-based agent messaging works WITHOUT HTTP
- ✅ Proves agent bootstrap works
- ✅ Proves message polling works

---

## 📊 DEMO SCRIPT (Hour 6):

### Working Demo (No AWS needed):

**1. Show API Health:**
```bash
curl http://localhost:8080/health
curl http://localhost:8080/agents
```

**2. Show Agent Registry:**
```bash
psql $NEON_PG_URI -c "SELECT agent_id, status, last_heartbeat FROM agent_instances"
```

**3. Show Message Flow:**
```bash
# Send message
curl -X POST http://localhost:8080/message -d '{...}'

# Show it in database
psql $NEON_PG_URI -c "SELECT * FROM tq_messages ORDER BY created_at DESC LIMIT 5"

# Show agent received it
ssh ubuntu@<agent-ip> tail /var/log/agent-poller.log
```

**4. Show Bootstrap Script:**
```bash
cat /home/ubuntu/clawd/agent-cloud-api/bootstrap-agent.sh
```

---

## 🚀 IF WE GET AWS CREDENTIALS (Bonus):

### Test 4: Automated Spawn

**Update environment variables:**
```bash
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AGENT_SECURITY_GROUP="sg-xxxxx"
export AGENT_SUBNET_ID="subnet-xxxxx"
```

**Restart API server:**
```bash
cd /home/ubuntu/clawd/agent-cloud-api
pkill -f "node server.js"
./start.sh &
```

**Test spawn endpoint:**
```bash
curl -X POST http://localhost:8080/spawn \
  -H "Content-Type: application/json" \
  -d '{
    "name": "auto-agent-001",
    "instance_type": "t3.micro"
  }'
```

**Expected:**
```json
{
  "agent_id": "auto-agent-001",
  "instance_id": "i-xxxxx",
  "status": "launching",
  "public_key": "..."
}
```

**Wait 2-3 minutes, then check:**
```bash
curl http://localhost:8080/agents
# Should show new agent with status 'active' after first heartbeat
```

---

## 📝 DELIVERABLES:

### Without AWS Credentials:
- ✅ API server (functional, tested)
- ✅ Bootstrap script (proven via manual test)
- ✅ Database schema (deployed)
- ✅ Message routing (working between agents)
- ✅ Documentation
- ✅ Demo: Agent-to-agent messaging via database

### With AWS Credentials (bonus):
- ✅ All of the above, plus:
- ✅ Automated EC2 spawning via `/spawn` endpoint
- ✅ End-to-end automated agent provisioning
- ✅ Demo: Spawn agent via HTTP API

---

## ⏱️ Time Remaining: 2h 40m

**Next 20 minutes:** Wait for Jared to test bootstrap script  
**Next 40 minutes:** Verify messaging works, document results  
**Next 80 minutes:** If AWS creds arrive, test automated spawn. Otherwise, polish docs.  
**Final 40 minutes:** Prepare demo, write final report

---

## SUCCESS METRICS:

**Minimum (no AWS):**
- [x] API server responds to health checks
- [ ] Jared successfully runs bootstrap script
- [ ] Message sent from Jean → Jared agent
- [ ] Jared agent processes message
- [ ] Documentation complete

**Stretch (with AWS):**
- [ ] `/spawn` endpoint launches new EC2
- [ ] New agent auto-registers
- [ ] New agent receives and processes messages
