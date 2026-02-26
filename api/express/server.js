const express = require('express');
const { Pool } = require('pg');
const AWS = require('aws-sdk');
const nacl = require('tweetnacl');
const util = require('tweetnacl-util');

const app = express();
app.use(express.json());

// Database connection
const pool = new Pool({ 
  connectionString: process.env.NEON_PG_URI || process.env.TQ_NEON_PG_URI
});

// AWS SDK
const ec2 = new AWS.EC2({ region: process.env.AWS_REGION || 'us-west-2' });

// Helper: Generate Ed25519 keypair
function generateKeypair() {
  const keypair = nacl.sign.keyPair();
  return {
    publicKey: util.encodeBase64(keypair.publicKey),
    secretKey: util.encodeBase64(keypair.secretKey)
  };
}

// POST /spawn - Launch new agent instance
app.post('/spawn', async (req, res) => {
  try {
    const { name, instance_type, capabilities } = req.body;
    const agentId = name || `agent-${Date.now()}-${Math.random().toString(36).substr(2, 6)}`;
    
    console.log(`Spawning agent: ${agentId}`);
    
    // 1. Generate keypair
    const { publicKey, secretKey } = generateKeypair();
    
    // 2. Register in database
    await pool.query(`
      INSERT INTO tq_agent_keys (agent_name, key_version, public_key, algorithm, created_at)
      VALUES ($1, 1, $2, 'ed25519', NOW())
      ON CONFLICT (agent_name, key_version) DO NOTHING
    `, [agentId, publicKey]);
    
    // 3. Prepare user-data script
    const apiServerIp = process.env.API_SERVER_IP || 'API_SERVER_IP_PLACEHOLDER';
    const neonPgUri = process.env.NEON_PG_URI || process.env.TQ_NEON_PG_URI;
    
    const userData = `#!/bin/bash
set -e
export AGENT_ID="${agentId}"
export SECRET_KEY="${secretKey}"
export NEON_PG_URI="${neonPgUri}"
export API_SERVER_IP="${apiServerIp}"

# Log everything
exec > >(tee /var/log/agent-bootstrap.log)
exec 2>&1

echo "Agent bootstrap started: $AGENT_ID at $(date)"

# Install Node.js if not present
if ! command -v node &> /dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi

# Install dependencies
apt-get update
apt-get install -y postgresql-client curl git jq

# Install Clawdbot
npm install -g clawdbot@latest || true

# Create workspace
mkdir -p /home/ubuntu/clawd
cd /home/ubuntu/clawd

# Write secrets
mkdir -p /home/ubuntu/.clawdbot/secrets
chmod 700 /home/ubuntu/.clawdbot/secrets
echo "$SECRET_KEY" > /home/ubuntu/.clawdbot/secrets/agent-ed25519.key
chmod 600 /home/ubuntu/.clawdbot/secrets/agent-ed25519.key

# Write Clawdbot config
cat > /home/ubuntu/.clawdbot/config.yaml <<EOF
agent:
  name: $AGENT_ID
  model: anthropic/claude-sonnet-4-5

channels:
  whatsapp:
    enabled: false

heartbeat:
  enabled: true
  interval_seconds: 30
EOF

# Create workspace files
cat > AGENTS.md <<EOF
# Agent: $AGENT_ID
Role: Worker agent
Spawned: $(date)
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

console.log(\`Message poller started for \${agentId}\`);

// Send heartbeat every 30 seconds
setInterval(async () => {
  try {
    await axios.post(\`http://\${apiServer}:8080/heartbeat/\${agentId}\`);
    console.log('Heartbeat sent');
  } catch (err) {
    console.error('Heartbeat failed:', err.message);
  }
}, 30000);

// Poll for messages every 5 seconds
setInterval(async () => {
  try {
    const result = await pool.query(\`
      SELECT * FROM tq_messages
      WHERE to_agent = $1 AND processed_at IS NULL
      ORDER BY timestamp ASC
      LIMIT 10
    \`, [agentId]);
    
    for (const msg of result.rows) {
      console.log('Processing message:', msg.id, msg.type);
      
      // Mark as processed
      await pool.query(\`
        UPDATE tq_messages SET processed_at = NOW() WHERE id = $1
      \`, [msg.id]);
    }
  } catch (err) {
    console.error('Message poll failed:', err.message);
  }
}, 5000);
JSEOF

# Install Node dependencies
npm install pg axios

# Start message poller
nohup node poll-messages.js > /var/log/agent-poller.log 2>&1 &

# Send initial heartbeat
curl -X POST "http://$API_SERVER_IP:8080/heartbeat/$AGENT_ID" || true

echo "Agent $AGENT_ID bootstrap complete at $(date)"
`;
    
    // 4. Launch EC2 instance
    const params = {
      ImageId: process.env.AGENT_AMI_ID || 'ami-0c55b159cbfafe1f0', // Ubuntu 24.04 us-west-2
      InstanceType: instance_type || 't3.micro',
      MinCount: 1,
      MaxCount: 1,
      UserData: Buffer.from(userData).toString('base64'),
      IamInstanceProfile: { Name: process.env.AGENT_IAM_ROLE || 'agent-runtime-role' },
      SecurityGroupIds: [process.env.AGENT_SECURITY_GROUP],
      SubnetId: process.env.AGENT_SUBNET_ID,
      TagSpecifications: [{
        ResourceType: 'instance',
        Tags: [
          { Key: 'Name', Value: agentId },
          { Key: 'Role', Value: 'agent' },
          { Key: 'ManagedBy', Value: 'agent-cloud' }
        ]
      }]
    };
    
    const instance = await ec2.runInstances(params).promise();
    const instanceId = instance.Instances[0].InstanceId;
    
    console.log(`Instance launched: ${instanceId}`);
    
    // 5. Track instance in database
    await pool.query(`
      INSERT INTO agent_instances (agent_id, instance_id, status, created_at)
      VALUES ($1, $2, 'launching', NOW())
    `, [agentId, instanceId]);
    
    res.json({ 
      agent_id: agentId, 
      instance_id: instanceId, 
      status: 'launching',
      public_key: publicKey
    });
    
  } catch (err) {
    console.error('Spawn error:', err);
    res.status(500).json({ error: err.message });
  }
});

// GET /agents - List all agents
app.get('/agents', async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT ai.agent_id, ai.instance_id, ai.status, ai.last_heartbeat, ai.created_at,
             ak.public_key
      FROM agent_instances ai
      LEFT JOIN tq_agent_keys ak ON ak.agent_name = ai.agent_id
      ORDER BY ai.created_at DESC
    `);
    
    res.json({ agents: result.rows });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /agents/:agent_id - Get specific agent
app.get('/agents/:agent_id', async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT ai.*, ak.public_key
      FROM agent_instances ai
      LEFT JOIN tq_agent_keys ak ON ak.agent_name = ai.agent_id
      WHERE ai.agent_id = $1
    `, [req.params.agent_id]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Agent not found' });
    }
    
    res.json({ agent: result.rows[0] });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /message - Send message to agent
app.post('/message', async (req, res) => {
  try {
    const { from_agent, to_agent, message_type, payload } = req.body;
    
    if (!from_agent || !to_agent || !message_type) {
      return res.status(400).json({ error: 'Missing required fields' });
    }
    
    const { randomUUID } = require('crypto');
    const idempotencyKey = randomUUID();
    
    const result = await pool.query(`
      INSERT INTO tq_messages (from_agent, to_agent, message_type, payload, created_at, priority, idempotency_key)
      VALUES ($1, $2, $3, $4, NOW(), 50, $5)
      RETURNING id
    `, [from_agent, to_agent, message_type, JSON.stringify(payload || {}), idempotencyKey]);
    
    res.json({ 
      message_id: result.rows[0].id, 
      status: 'sent' 
    });
    
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /heartbeat/:agent_id - Agent heartbeat
app.post('/heartbeat/:agent_id', async (req, res) => {
  try {
    const { agent_id } = req.params;
    const { metrics } = req.body;
    
    const result = await pool.query(`
      UPDATE agent_instances
      SET last_heartbeat = NOW(), 
          status = 'active',
          private_ip = COALESCE(private_ip, $2),
          public_ip = COALESCE(public_ip, $3)
      WHERE agent_id = $1
      RETURNING *
    `, [agent_id, req.body.private_ip, req.body.public_ip]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Agent not found' });
    }
    
    res.json({ status: 'ok', agent: result.rows[0] });
    
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// DELETE /agents/:agent_id - Terminate agent
app.delete('/agents/:agent_id', async (req, res) => {
  try {
    const { agent_id } = req.params;
    
    // Get instance ID
    const result = await pool.query(
      'SELECT instance_id FROM agent_instances WHERE agent_id = $1',
      [agent_id]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Agent not found' });
    }
    
    const instanceId = result.rows[0].instance_id;
    
    // Terminate EC2 instance
    if (instanceId) {
      await ec2.terminateInstances({ InstanceIds: [instanceId] }).promise();
    }
    
    // Update database
    await pool.query(`
      UPDATE agent_instances SET status = 'terminated' WHERE agent_id = $1
    `, [agent_id]);
    
    res.json({ status: 'terminated', agent_id, instance_id: instanceId });
    
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /health - Health check
app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'healthy', timestamp: new Date().toISOString() });
  } catch (err) {
    res.status(500).json({ status: 'unhealthy', error: err.message });
  }
});

// Start server
const PORT = process.env.PORT || 8080;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Agent Cloud API running on port ${PORT}`);
  console.log(`Health check: http://localhost:${PORT}/health`);
});
