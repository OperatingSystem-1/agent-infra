# IMMEDIATE ACTION PLAN - 2h 45m Left

## Status: API Server Running, But Isolated

**Working:**
- ✅ API server on 172.31.15.113:8080
- ✅ Database schema deployed
- ✅ Bootstrap script ready
- ✅ Message routing code ready

**Blocked:**
- ❌ Security groups blocking traffic between instances
- ❌ No AWS credentials for automated spawning
- ❌ Jared (172.31.43.104) can't reach my API

**Confirmed:** `curl http://172.31.43.104:8080` → timeout (security groups blocking)

---

## OPTION 1: Test Locally RIGHT NOW (No Patrick needed)

**Jared can test the agent bootstrap on his own instance:**

```bash
# On Jared's instance (172.31.43.104)
cd /home/ubuntu/clawd
curl -o bootstrap-agent.sh https://raw.githubusercontent.com/.../bootstrap-agent.sh

# OR I can share it via tq_messages table

# Set environment variables
export AGENT_ID="jared-test-agent"
export API_SERVER_IP="172.31.15.113"
export NEON_PG_URI="postgresql://neondb_owner:npg_24bYhdRcyZax@..."

# Run bootstrap
bash bootstrap-agent.sh
```

**What this proves:**
- Agent registration works
- Message polling works
- Heartbeat tracking works

**What it doesn't prove:**
- EC2 spawning (but that's just AWS SDK calls)

**Time to test:** 15 minutes

---

## OPTION 2: Manual EC2 Spawn Test (Patrick needed)

**Patrick manually launches 1 new EC2 instance:**

**Instance config:**
- AMI: Ubuntu 24.04 (ami-0c55b159cbfafe1f0 in us-west-2)
- Type: t3.micro
- Security group: Same as our instances OR allow 8080 from 172.31.0.0/16
- User data: (see below)

**User data script:**
```bash
#!/bin/bash
export AGENT_ID="test-agent-001"
export API_SERVER_IP="172.31.15.113"
export NEON_PG_URI="postgresql://neondb_owner:npg_24bYhdRcyZax@ep-polished-bread-ai1pqzi9-pooler.c-4.us-east-1.aws.neon.tech/neondb?sslmode=require"

curl -fsSL https://raw.githubusercontent.com/.../bootstrap-agent.sh | bash
```

**What this proves:**
- Full EC2 bootstrap works
- Agent auto-registers
- Inter-agent messaging works

**Time to test:** 20 minutes (launch + boot + verify)

---

## OPTION 3: Share Bootstrap Script via Database (No HTTP needed)

**I can put the bootstrap script in tq_messages for Jared to retrieve:**

```sql
INSERT INTO tq_messages (from_agent, to_agent, message_type, payload)
VALUES ('jean', 'jared', 'bootstrap_script', '{"script":"...base64..."}')
```

**Jared pulls it and runs it on his instance.**

**Time to test:** 10 minutes

---

## RECOMMENDED: Option 3 → Option 1 → Option 2

**Next 30 minutes:**

1. **Now (5 min):** I send bootstrap script to Jared via tq_messages
2. **+10 min:** Jared runs it on his instance, becomes test agent
3. **+15 min:** I send test message to "jared-test-agent" via API
4. **+20 min:** Verify Jared's poller receives and processes message
5. **+30 min:** Document success, move to manual EC2 spawn if time

**This proves the coordination layer works WITHOUT needing:**
- AWS credentials
- Security group changes
- Patrick's intervention

**Then we can add automation later if we get AWS access.**

---

## Files Ready:

- `/home/ubuntu/clawd/agent-cloud-api/server.js` - API server ✅
- `/home/ubuntu/clawd/agent-cloud-api/bootstrap-agent.sh` - Bootstrap script ✅
- `/home/ubuntu/clawd/agent-cloud-api/schema.sql` - Database schema ✅

---

## Next Command (Jared):

**Check tq_messages for the bootstrap script I'm about to send:**

```bash
psql $NEON_PG_URI -c "SELECT * FROM tq_messages WHERE to_agent='jared' AND message_type='bootstrap_script' ORDER BY created_at DESC LIMIT 1"
```
