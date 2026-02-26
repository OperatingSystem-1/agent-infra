#!/bin/bash
# Agent Bootstrap Script - Standalone version for manual testing
# Usage: curl -fsSL https://url-to-this-script | bash
# Or: bash bootstrap-agent.sh

set -e

# Configuration (set these before running)
AGENT_ID="${AGENT_ID:-agent-$(date +%s)-$(openssl rand -hex 3)}"
API_SERVER_IP="${API_SERVER_IP:-172.31.15.113}"
NEON_PG_URI="${NEON_PG_URI:-postgresql://neondb_owner:npg_24bYhdRcyZax@ep-polished-bread-ai1pqzi9-pooler.c-4.us-east-1.aws.neon.tech/neondb?sslmode=require}"

# Log everything
exec > >(tee /var/log/agent-bootstrap.log)
exec 2>&1

echo "=========================================="
echo "Agent Bootstrap Started"
echo "Agent ID: $AGENT_ID"
echo "API Server: $API_SERVER_IP"
echo "Time: $(date)"
echo "=========================================="

# Install Node.js if not present
if ! command -v node &> /dev/null; then
  echo "Installing Node.js..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -
  sudo apt-get install -y nodejs
fi

# Install system dependencies
echo "Installing dependencies..."
sudo apt-get update -qq
sudo apt-get install -y postgresql-client curl git jq

# Create workspace
echo "Creating workspace..."
mkdir -p /home/ubuntu/clawd-agent
cd /home/ubuntu/clawd-agent

# Generate keypair (using Node.js)
echo "Generating keypair..."
cat > generate-keys.js <<'EOF'
const nacl = require('tweetnacl');
const util = require('tweetnacl-util');
const keypair = nacl.sign.keyPair();
console.log(JSON.stringify({
  publicKey: util.encodeBase64(keypair.publicKey),
  secretKey: util.encodeBase64(keypair.secretKey)
}));
EOF

npm install tweetnacl tweetnacl-util --silent
KEYS=$(node generate-keys.js)
PUBLIC_KEY=$(echo $KEYS | jq -r .publicKey)
SECRET_KEY=$(echo $KEYS | jq -r .secretKey)

echo "Public key: $PUBLIC_KEY"

# Register agent via API
echo "Registering agent with API server..."
REGISTRATION=$(curl -s -X POST http://$API_SERVER_IP:8080/heartbeat/$AGENT_ID \
  -H "Content-Type: application/json" \
  -d "{\"private_ip\":\"$(hostname -I | awk '{print $1}')\",\"public_ip\":\"$(curl -s ifconfig.me)\"}")

echo "Registration response: $REGISTRATION"

# Create workspace files
cat > AGENTS.md <<EOF
# Agent: $AGENT_ID
Role: Worker agent
Spawned: $(date)
API Server: $API_SERVER_IP
EOF

cat > SOUL.md <<EOF
I am $AGENT_ID, a worker agent in the agent cloud.
EOF

# Create message poller
cat > poll-messages.js <<'JSEOF'
const { Pool } = require('pg');
const axios = require('axios');

const pool = new Pool({ connectionString: process.env.NEON_PG_URI });
const agentId = process.env.AGENT_ID;
const apiServer = process.env.API_SERVER_IP;

console.log(`Message poller started for ${agentId}`);
console.log(`API Server: ${apiServer}`);
console.log(`Database: Connected`);

// Send heartbeat every 30 seconds
setInterval(async () => {
  try {
    const privateIp = require('os').networkInterfaces().eth0?.[0]?.address || 'unknown';
    await axios.post(`http://${apiServer}:8080/heartbeat/${agentId}`, {
      private_ip: privateIp,
      metrics: {
        uptime: process.uptime(),
        memory: process.memoryUsage().heapUsed / 1024 / 1024
      }
    });
    console.log(`[${new Date().toISOString()}] Heartbeat sent`);
  } catch (err) {
    console.error(`[${new Date().toISOString()}] Heartbeat failed:`, err.message);
  }
}, 30000);

// Poll for messages every 5 seconds
setInterval(async () => {
  try {
    const result = await pool.query(`
      SELECT * FROM tq_messages
      WHERE to_agent = $1 AND processed_at IS NULL
      ORDER BY created_at ASC
      LIMIT 10
    `, [agentId]);
    
    if (result.rows.length > 0) {
      console.log(`[${new Date().toISOString()}] Processing ${result.rows.length} messages`);
    }
    
    for (const msg of result.rows) {
      console.log(`  - Message ${msg.id}: ${msg.message_type} from ${msg.from_agent}`);
      console.log(`    Payload:`, msg.payload);
      
      // Mark as processed
      await pool.query(`
        UPDATE tq_messages 
        SET processed_at = NOW() 
        WHERE id = $1
      `, [msg.id]);
    }
  } catch (err) {
    console.error(`[${new Date().toISOString()}] Message poll failed:`, err.message);
  }
}, 5000);

// Handle shutdown gracefully
process.on('SIGINT', async () => {
  console.log('\nShutting down...');
  await pool.end();
  process.exit(0);
});
JSEOF

# Install Node dependencies
echo "Installing Node dependencies..."
npm install pg axios --silent

# Export environment variables for poller
export AGENT_ID="$AGENT_ID"
export API_SERVER_IP="$API_SERVER_IP"
export NEON_PG_URI="$NEON_PG_URI"

# Start message poller in background
echo "Starting message poller..."
nohup node poll-messages.js > /var/log/agent-poller.log 2>&1 &
POLLER_PID=$!

echo "Message poller started (PID: $POLLER_PID)"

# Send initial heartbeat
echo "Sending initial heartbeat..."
curl -X POST "http://$API_SERVER_IP:8080/heartbeat/$AGENT_ID" \
  -H "Content-Type: application/json" \
  -d "{\"private_ip\":\"$(hostname -I | awk '{print $1}')\"}" || echo "Heartbeat failed (may succeed on retry)"

echo ""
echo "=========================================="
echo "Agent Bootstrap Complete"
echo "Agent ID: $AGENT_ID"
echo "Poller log: tail -f /var/log/agent-poller.log"
echo "To stop: kill $POLLER_PID"
echo "=========================================="
