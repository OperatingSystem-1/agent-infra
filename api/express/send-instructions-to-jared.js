const { Pool } = require('pg');
const fs = require('fs');
const { randomUUID } = require('crypto');

const pool = new Pool({
  connectionString: 'postgresql://neondb_owner:npg_24bYhdRcyZax@ep-polished-bread-ai1pqzi9-pooler.c-4.us-east-1.aws.neon.tech/neondb?sslmode=require'
});

async function sendInstructions() {
  const instructions = fs.readFileSync('./JARED-QUICK-START.md', 'utf8');
  
  const payload = {
    type: "quick_start_guide",
    jean_ip: "172.31.1.14",
    api_port: "8080",
    bootstrap_message_id: "20bc6c3e-40f6-4c7a-9624-c6fbf377b38f",
    instructions: instructions,
    quick_commands: [
      "cd /home/ubuntu/clawd && mkdir -p agent-test && cd agent-test",
      "export NEON_PG_URI='postgresql://neondb_owner:npg_24bYhdRcyZax@ep-polished-bread-ai1pqzi9-pooler.c-4.us-east-1.aws.neon.tech/neondb?sslmode=require'",
      "psql $NEON_PG_URI -t -c \"SELECT payload->>'script_raw' FROM tq_messages WHERE id='20bc6c3e-40f6-4c7a-9624-c6fbf377b38f'\" > bootstrap-agent.sh",
      "chmod +x bootstrap-agent.sh",
      "export AGENT_ID='jared-test-agent' API_SERVER_IP='172.31.1.14'",
      "bash bootstrap-agent.sh",
      "tail -f /var/log/agent-poller.log"
    ]
  };
  
  const result = await pool.query(`
    INSERT INTO tq_messages (from_agent, to_agent, message_type, payload, created_at, priority, idempotency_key)
    VALUES ($1, $2, $3, $4, NOW(), 100, $5)
    RETURNING id, created_at
  `, ['jean', 'jared', 'instructions', JSON.stringify(payload), randomUUID()]);
  
  console.log('✅ Instructions sent to Jared');
  console.log('Message ID:', result.rows[0].id);
  console.log('Sent at:', result.rows[0].created_at);
  
  await pool.end();
}

sendInstructions().catch(console.error);
