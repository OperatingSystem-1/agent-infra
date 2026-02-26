-- Agent Cloud Database Schema

-- Agent instances tracking
CREATE TABLE IF NOT EXISTS agent_instances (
  agent_id TEXT PRIMARY KEY,
  instance_id TEXT,
  private_ip TEXT,
  public_ip TEXT,
  status TEXT DEFAULT 'launching', -- 'launching' | 'active' | 'unhealthy' | 'terminated'
  created_at TIMESTAMP DEFAULT NOW(),
  last_heartbeat TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_agent_status ON agent_instances(status);
CREATE INDEX IF NOT EXISTS idx_agent_heartbeat ON agent_instances(last_heartbeat DESC);

-- Ensure tq_messages has processed_at column
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'tq_messages' AND column_name = 'processed_at'
  ) THEN
    ALTER TABLE tq_messages ADD COLUMN processed_at TIMESTAMP;
  END IF;
END $$;

-- View for active agents
CREATE OR REPLACE VIEW active_agents AS
SELECT ai.*, ak.public_key
FROM agent_instances ai
LEFT JOIN tq_agent_keys ak ON ak.agent_name = ai.agent_id
WHERE ai.status = 'active' 
  AND ai.last_heartbeat > NOW() - INTERVAL '5 minutes';
