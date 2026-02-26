#!/bin/bash
# Test agent registration locally (no AWS needed)
# Validates the bootstrap flow against Neon

set -e

AGENT_NAME="${1:-test-agent-$(date +%s)}"
AGENT_MODEL="${2:-claude-sonnet-4-20250514}"

echo "=== Testing Agent Registration: $AGENT_NAME ==="

# Connection string
NEON_CONN="${NEON_CONNECTION_STRING:-postgresql://neondb_owner:npg_24bYhdRcyZax@ep-polished-bread-ai1pqzi9-pooler.c-4.us-east-1.aws.neon.tech/neondb?sslmode=require}"

# Generate test keypair
echo "[1/5] Generating keypair..."
TEMP_DIR=$(mktemp -d)
openssl genpkey -algorithm Ed25519 -out "$TEMP_DIR/private.key" 2>/dev/null
openssl pkey -in "$TEMP_DIR/private.key" -pubout -out "$TEMP_DIR/public.key" 2>/dev/null
PUBLIC_KEY_B64=$(cat "$TEMP_DIR/public.key" | base64 -w0)
echo "Public key generated: ${PUBLIC_KEY_B64:0:40}..."

# Generate UUID from agent name
AGENT_UUID=$(echo -n "$AGENT_NAME" | md5sum | sed 's/^\(........\)\(....\)\(....\)\(....\)\(............\).*/\1-\2-\3-\4-\5/')
echo "[2/5] Agent UUID: $AGENT_UUID"

# Register in database
echo "[3/5] Registering in Neon..."
INSTANCE_IP="127.0.0.1"

psql "$NEON_CONN" <<EOF
-- Insert agent
INSERT INTO tq_agent_registry (agent_id, agent_name, instance_ip, status, model, registered_at, last_seen, metadata)
VALUES (
  '$AGENT_UUID'::uuid,
  '$AGENT_NAME', 
  '$INSTANCE_IP'::inet,
  'online',
  '$AGENT_MODEL',
  NOW(),
  NOW(),
  '{"test": true, "bootstrap_time": "$(date -Iseconds)"}'::jsonb
)
ON CONFLICT (agent_name) DO UPDATE SET
  status = 'online',
  last_seen = NOW(),
  metadata = tq_agent_registry.metadata || '{"test_updated": true}'::jsonb;

-- Insert key
INSERT INTO tq_agent_keys (agent_name, key_version, public_key, algorithm, created_at)
VALUES ('$AGENT_NAME', 1, '$PUBLIC_KEY_B64', 'ed25519', NOW())
ON CONFLICT (agent_name, key_version) DO UPDATE SET
  public_key = EXCLUDED.public_key,
  created_at = NOW();
EOF

echo "[4/5] Verifying registration..."
psql "$NEON_CONN" -c "SELECT agent_id, agent_name, status, model, last_seen FROM tq_agent_registry WHERE agent_name = '$AGENT_NAME';"
psql "$NEON_CONN" -c "SELECT agent_name, key_version, algorithm, created_at FROM tq_agent_keys WHERE agent_name = '$AGENT_NAME';"

# Announce
echo "[5/5] Sending announcement..."
psql "$NEON_CONN" <<EOF
INSERT INTO tq_messages (from_agent, to_agent, message_type, payload, created_at)
VALUES (
  '$AGENT_NAME',
  'broadcast',
  'announcement',
  '{"event": "agent_online", "agent": "$AGENT_NAME", "model": "$AGENT_MODEL", "test": true}'::jsonb,
  NOW()
);
EOF

echo ""
echo "=== Registration Test Complete ==="
echo "Agent: $AGENT_NAME"
echo "UUID: $AGENT_UUID"
echo ""
echo "Cleanup: psql \$NEON_CONNECTION_STRING -c \"DELETE FROM tq_agent_registry WHERE agent_name = '$AGENT_NAME'; DELETE FROM tq_agent_keys WHERE agent_name = '$AGENT_NAME';\""

# Cleanup temp files
rm -rf "$TEMP_DIR"
