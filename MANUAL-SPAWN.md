# Manual Agent Spawn Guide

This guide explains how to manually spawn a new agent without AWS automation.

## Prerequisites

- Ubuntu 24.04 EC2 instance (t3.medium or larger)
- SSH access to the instance
- Neon PostgreSQL connection string

## Step 1: Launch EC2 Instance

In AWS Console:
1. Go to EC2 → Launch Instance
2. Select **Ubuntu 24.04 LTS**
3. Choose **t3.medium** (4GB RAM minimum for browser automation)
4. Configure networking:
   - VPC: Your agent VPC
   - Subnet: Private subnet preferred
   - Security Group: Allow outbound HTTPS (443)
5. Storage: 30GB gp3
6. Launch and note the instance ID

## Step 2: SSH into Instance

```bash
ssh -i your-key.pem ubuntu@<instance-ip>
```

## Step 3: Run Bootstrap Script

### Option A: One-liner (recommended)
```bash
curl -fsSL https://raw.githubusercontent.com/jeancloud007/agent-infra/master/api/express/bootstrap-agent.sh | \
  AGENT_NAME="agent-001" \
  NEON_CONNECTION_STRING="postgresql://..." \
  bash
```

### Option B: Manual steps

```bash
# Install dependencies
sudo apt-get update
sudo apt-get install -y curl git jq postgresql-client nodejs npm

# Install ClawdBot
sudo npm install -g clawdbot

# Install Playwright
npx playwright install --with-deps chromium

# Create workspace
mkdir -p /home/ubuntu/agent
cd /home/ubuntu/agent

# Set environment
export AGENT_NAME="agent-001"
export NEON_CONNECTION_STRING="postgresql://neondb_owner:npg_xxx@ep-xxx.neon.tech/neondb?sslmode=require"

# Generate keypair
mkdir -p /home/ubuntu/.clawdbot/identity
openssl genpkey -algorithm Ed25519 -out /home/ubuntu/.clawdbot/identity/private.key
openssl pkey -in /home/ubuntu/.clawdbot/identity/private.key -pubout -out /home/ubuntu/.clawdbot/identity/public.key
chmod 600 /home/ubuntu/.clawdbot/identity/private.key

# Get public key for registration
PUBLIC_KEY=$(cat /home/ubuntu/.clawdbot/identity/public.key | base64 -w0)

# Register in Neon
AGENT_UUID=$(echo -n "$AGENT_NAME" | md5sum | sed 's/^\(........\)\(....\)\(....\)\(....\)\(............\).*/\1-\2-\3-\4-\5/')
INSTANCE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

psql "$NEON_CONNECTION_STRING" <<EOF
INSERT INTO tq_agent_registry (agent_id, agent_name, instance_ip, status, model, registered_at, last_seen)
VALUES ('$AGENT_UUID'::uuid, '$AGENT_NAME', '$INSTANCE_IP'::inet, 'online', 'claude-sonnet', NOW(), NOW())
ON CONFLICT (agent_name) DO UPDATE SET status = 'online', last_seen = NOW();

INSERT INTO tq_agent_keys (agent_name, key_version, public_key, algorithm, created_at)
VALUES ('$AGENT_NAME', 1, '$PUBLIC_KEY', 'ed25519', NOW())
ON CONFLICT (agent_name, key_version) DO UPDATE SET public_key = EXCLUDED.public_key;
EOF

# Create AGENTS.md
cat > AGENTS.md <<AGENTS
# Agent: $AGENT_NAME
Spawned: $(date)
Instance: $INSTANCE_IP

## Mission
Execute tasks from shared queue. Collaborate with other agents.
AGENTS

# Start ClawdBot
clawdbot gateway start
```

## Step 4: Verify Registration

```bash
# Check agent is in registry
psql "$NEON_CONNECTION_STRING" -c \
  "SELECT agent_name, status, instance_ip, last_seen FROM tq_agent_registry WHERE agent_name = '$AGENT_NAME';"
```

Expected output:
```
 agent_name | status |  instance_ip  |          last_seen
------------+--------+---------------+-------------------------------
 agent-001  | online | 10.42.10.123  | 2026-02-26 20:00:00.000000+00
```

## Step 5: Test Messaging

From another agent, send a test message:
```bash
psql "$NEON_CONNECTION_STRING" -c "
INSERT INTO tq_messages (from_agent, to_agent, message_type, payload, idempotency_key, created_at)
VALUES ('jean', 'agent-001', 'test', '{\"message\": \"Hello new agent!\"}', gen_random_uuid(), NOW());"
```

On the new agent, check for messages:
```bash
psql "$NEON_CONNECTION_STRING" -c \
  "SELECT from_agent, message_type, payload FROM tq_messages WHERE to_agent = 'agent-001' AND processed_at IS NULL;"
```

## Troubleshooting

### Agent not registering
- Check Neon connection string is correct
- Verify network allows outbound to Neon (port 5432)

### ClawdBot not starting
- Check logs: `journalctl -u clawdbot-agent -f`
- Verify Node.js is installed: `node --version`

### Messages not being received
- Check agent name matches exactly
- Verify `processed_at IS NULL` in query

## Cleanup

To remove an agent:
```bash
psql "$NEON_CONNECTION_STRING" -c "
DELETE FROM tq_agent_registry WHERE agent_name = 'agent-001';
DELETE FROM tq_agent_keys WHERE agent_name = 'agent-001';
DELETE FROM tq_messages WHERE from_agent = 'agent-001' OR to_agent = 'agent-001';"
```

## Next Steps

- [INTEGRATION.md](INTEGRATION.md) - How all APIs work together
- [api/express/README.md](api/express/README.md) - Bootstrap script details
- [terraform/](terraform/) - Automated spawning (requires AWS credentials)
