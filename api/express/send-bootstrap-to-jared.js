const { Pool } = require('pg');
const fs = require('fs');
const { randomUUID } = require('crypto');

const pool = new Pool({
  connectionString: 'postgresql://neondb_owner:npg_24bYhdRcyZax@ep-polished-bread-ai1pqzi9-pooler.c-4.us-east-1.aws.neon.tech/neondb?sslmode=require'
});

async function sendBootstrap() {
  const script = fs.readFileSync('./bootstrap-agent.sh', 'utf8');
  const scriptBase64 = fs.readFileSync('./bootstrap-agent.sh.b64', 'utf8');
  
  const payload = {
    script_base64: scriptBase64,
    instructions: [
      "Save this to a file: echo '<base64>' | base64 -d > bootstrap-agent.sh",
      "Or use the script field directly",
      "Set environment variables: export AGENT_ID=jared-test-agent API_SERVER_IP=172.31.15.113",
      "Run: bash bootstrap-agent.sh",
      "Check logs: tail -f /var/log/agent-bootstrap.log"
    ],
    script_raw: script,
    api_server: "172.31.15.113:8080",
    neon_uri: "postgresql://neondb_owner:npg_24bYhdRcyZax@ep-polished-bread-ai1pqzi9-pooler.c-4.us-east-1.aws.neon.tech/neondb?sslmode=require"
  };
  
  const result = await pool.query(`
    INSERT INTO tq_messages (from_agent, to_agent, message_type, payload, created_at, priority, idempotency_key)
    VALUES ($1, $2, $3, $4, NOW(), 100, $5)
    RETURNING id, created_at
  `, ['jean', 'jared', 'bootstrap_script', JSON.stringify(payload), randomUUID()]);
  
  console.log('✅ Bootstrap script sent to Jared');
  console.log('Message ID:', result.rows[0].id);
  console.log('Sent at:', result.rows[0].created_at);
  console.log('\nJared can retrieve with:');
  console.log(`  psql $NEON_PG_URI -c "SELECT payload FROM tq_messages WHERE id='${result.rows[0].id}'"`);
  
  await pool.end();
}

sendBootstrap().catch(console.error);
