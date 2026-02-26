#!/bin/bash
# ClawdBot Agent Bootstrap Script
# Called via cloud-init user-data at instance launch
set -e

LOG_FILE="/var/log/clawdbot-bootstrap.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=========================================="
echo "ClawdBot Agent Bootstrap - $(date)"
echo "=========================================="

# Environment variables passed via user-data
AGENT_NAME="${AGENT_NAME:-agent-$(hostname | cut -d'-' -f2)}"
AGENT_MODEL="${AGENT_MODEL:-claude-sonnet-4-20250514}"
NEON_CONNECTION_STRING="${NEON_CONNECTION_STRING}"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"

echo "[1/7] Agent identity: $AGENT_NAME"
echo "[1/7] Model: $AGENT_MODEL"

# Get instance metadata
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
INSTANCE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
AVAILABILITY_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)

echo "[2/7] Instance: $INSTANCE_ID in $AVAILABILITY_ZONE ($INSTANCE_IP)"

# Generate Ed25519 keypair for message signing
echo "[3/7] Generating agent keypair..."
PRIVATE_KEY_FILE="/home/ubuntu/.clawdbot/identity/private.key"
PUBLIC_KEY_FILE="/home/ubuntu/.clawdbot/identity/public.key"

if [ ! -f "$PRIVATE_KEY_FILE" ]; then
  openssl genpkey -algorithm Ed25519 -out "$PRIVATE_KEY_FILE"
  chmod 600 "$PRIVATE_KEY_FILE"
  openssl pkey -in "$PRIVATE_KEY_FILE" -pubout -out "$PUBLIC_KEY_FILE"
  chown ubuntu:ubuntu "$PRIVATE_KEY_FILE" "$PUBLIC_KEY_FILE"
fi

PUBLIC_KEY_B64=$(cat "$PUBLIC_KEY_FILE" | base64 -w0)
echo "[3/7] Public key generated"

# Register with Neon database
echo "[4/7] Registering agent in Neon..."
if [ -n "$NEON_CONNECTION_STRING" ]; then
  # Generate a deterministic UUID from agent name
  AGENT_UUID=$(echo -n "$AGENT_NAME" | md5sum | sed 's/^\(........\)\(....\)\(....\)\(....\)\(............\).*/\1-\2-\3-\4-\5/')
  
  psql "$NEON_CONNECTION_STRING" <<EOF
-- Upsert agent registry (agent_id is UUID)
INSERT INTO tq_agent_registry (agent_id, agent_name, instance_ip, status, model, registered_at, last_seen, metadata)
VALUES (
  '$AGENT_UUID'::uuid,
  '$AGENT_NAME', 
  '$INSTANCE_IP'::inet,
  'online',
  '$AGENT_MODEL',
  NOW(),
  NOW(),
  '{"instance_id": "$INSTANCE_ID", "az": "$AVAILABILITY_ZONE", "bootstrap_time": "$(date -Iseconds)"}'::jsonb
)
ON CONFLICT (agent_name) DO UPDATE SET
  instance_ip = EXCLUDED.instance_ip,
  status = 'online',
  last_seen = NOW(),
  metadata = tq_agent_registry.metadata || EXCLUDED.metadata;

-- Upsert public key (agent_name, key_version is the primary key)
INSERT INTO tq_agent_keys (agent_name, key_version, public_key, algorithm, created_at)
VALUES ('$AGENT_NAME', 1, '$PUBLIC_KEY_B64', 'ed25519', NOW())
ON CONFLICT (agent_name, key_version) DO UPDATE SET
  public_key = EXCLUDED.public_key,
  created_at = NOW();
EOF
  echo "[4/7] Registered in Neon (UUID: $AGENT_UUID)"
else
  echo "[4/7] SKIPPED - No NEON_CONNECTION_STRING"
fi

# Create workspace
echo "[5/7] Setting up workspace..."
WORKSPACE="/home/ubuntu/agent"
mkdir -p "$WORKSPACE"
cd "$WORKSPACE"

# Generate AGENTS.md
cat > AGENTS.md <<AGENTS
# Agent: $AGENT_NAME

Auto-spawned agent in the agent economy cluster.
Instance: $INSTANCE_ID
Spawned: $(date)

## Mission
Execute tasks from the shared queue. Collaborate with other agents.
Report status. Learn and improve.

## Capabilities
- Task execution from shared queue
- Browser automation (Playwright)
- Code generation and review
- Inter-agent messaging (signed)
- Knowledge base contribution

## Coordination
- Check tq_messages for incoming tasks
- Post status to tq_agent_standups
- Share learnings to tq_agent_knowledge
AGENTS

# Generate clawdbot config
echo "[6/7] Configuring ClawdBot..."
mkdir -p /home/ubuntu/.clawdbot

cat > /home/ubuntu/.clawdbot/clawdbot.json <<CONFIG
{
  "agent": {
    "name": "$AGENT_NAME",
    "model": "$AGENT_MODEL"
  },
  "browser": {
    "enabled": true,
    "headless": true,
    "noSandbox": true
  },
  "models": {
    "providers": {
      "anthropic": {
        "baseUrl": "https://api.anthropic.com",
        "auth": "api-key"
      }
    }
  }
}
CONFIG

# Store API key if provided
if [ -n "$ANTHROPIC_API_KEY" ]; then
  echo "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY" > /home/ubuntu/.clawdbot/.env
  chmod 600 /home/ubuntu/.clawdbot/.env
fi

chown -R ubuntu:ubuntu /home/ubuntu/.clawdbot /home/ubuntu/agent

# Announce to the network
echo "[7/7] Announcing agent online..."
if [ -n "$NEON_CONNECTION_STRING" ]; then
  # Generate a UUID for idempotency key
  IDEMPOTENCY_UUID=$(cat /proc/sys/kernel/random/uuid)
  psql "$NEON_CONNECTION_STRING" <<EOF
INSERT INTO tq_messages (from_agent, to_agent, message_type, payload, idempotency_key, created_at)
VALUES (
  '$AGENT_NAME',
  'broadcast',
  'announcement',
  '{"event": "agent_online", "agent": "$AGENT_NAME", "instance": "$INSTANCE_ID", "ip": "$INSTANCE_IP", "model": "$AGENT_MODEL", "time": "$(date -Iseconds)"}'::jsonb,
  '$IDEMPOTENCY_UUID'::uuid,
  NOW()
);
EOF
  echo "[7/7] Announced to network"
fi

echo "=========================================="
echo "Bootstrap complete at $(date)"
echo "Agent $AGENT_NAME is ready"
echo "=========================================="

# Start the gateway service
sudo systemctl start clawdbot-agent.service
