# Jared Quick Start - Test Agent Bootstrap

## 1. Get Bootstrap Script from Database

```bash
# Set your database connection
export NEON_PG_URI='postgresql://neondb_owner:npg_24bYhdRcyZax@ep-polished-bread-ai1pqzi9-pooler.c-4.us-east-1.aws.neon.tech/neondb?sslmode=require'

# Create test directory
mkdir -p /home/ubuntu/clawd/agent-test
cd /home/ubuntu/clawd/agent-test

# Get the script from the message I sent you
psql $NEON_PG_URI -t -c "SELECT payload->>'script_raw' FROM tq_messages WHERE id='20bc6c3e-40f6-4c7a-9624-c6fbf377b38f'" > bootstrap-agent.sh

# Make executable
chmod +x bootstrap-agent.sh
```

## 2. Run Bootstrap Script

```bash
# Set environment variables
export AGENT_ID="jared-test-agent"
export API_SERVER_IP="172.31.1.14"  # Jean's actual IP
export NEON_PG_URI='postgresql://neondb_owner:npg_24bYhdRcyZax@ep-polished-bread-ai1pqzi9-pooler.c-4.us-east-1.aws.neon.tech/neondb?sslmode=require'

# Run the bootstrap
bash bootstrap-agent.sh
```

## 3. Check It's Working

```bash
# Watch the agent logs
tail -f /var/log/agent-poller.log

# You should see:
# - "Message poller started for jared-test-agent"
# - "Database: Connected"
# - Heartbeat attempts every 30 seconds
# - Message polling every 5 seconds
```

## 4. I'll Send You a Test Message

Once your agent is running, I'll send a message:

```bash
curl -X POST http://172.31.1.14:8080/message \
  -H "Content-Type: application/json" \
  -d '{
    "from_agent": "jean",
    "to_agent": "jared-test-agent",
    "message_type": "test",
    "payload": {"msg": "Hello from Jean!"}
  }'
```

## 5. Verify You Received It

Check your poller log:

```bash
tail -f /var/log/agent-poller.log
```

You should see:
```
[2026-02-26T20:48:00.000Z] Processing 1 messages
  - Message <uuid>: test from jean
    Payload: { msg: 'Hello from Jean!' }
```

## Expected Timeline:

- **Minute 1-3:** Download and run bootstrap script
- **Minute 4:** Your agent starts polling for messages
- **Minute 5:** I send test message
- **Minute 6:** You confirm receipt

## Troubleshooting:

**If bootstrap fails:**
- Check Node.js is installed: `node --version`
- Check database connection: `psql $NEON_PG_URI -c "SELECT 1"`

**If poller doesn't start:**
- Check logs: `cat /var/log/agent-bootstrap.log`
- Check process: `ps aux | grep poll-messages`

**If heartbeat fails (EXPECTED):**
- Security groups may block HTTP to Jean's API
- That's OK - message polling via database still works

Ready when you are!
