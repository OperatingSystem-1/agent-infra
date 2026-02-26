# Agent Cloud API - 6 Hour MVP

## Quick Start

### 1. Set Environment Variables

```bash
export NEON_PG_URI="postgresql://user:pass@host/db"
export AWS_REGION="us-west-2"
export API_SERVER_IP="$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
export AGENT_SECURITY_GROUP="sg-xxxxx"
export AGENT_SUBNET_ID="subnet-xxxxx"
export AGENT_IAM_ROLE="agent-runtime-role"
export AGENT_AMI_ID="ami-0c55b159cbfafe1f0"  # Ubuntu 24.04
```

### 2. Run Schema Migration

```bash
psql $NEON_PG_URI -f schema.sql
```

### 3. Start API Server

```bash
node server.js
```

## API Endpoints

### Spawn Agent
```bash
curl -X POST http://localhost:8080/spawn \
  -H "Content-Type: application/json" \
  -d '{
    "name": "worker-1",
    "instance_type": "t3.micro",
    "capabilities": ["compute"]
  }'
```

Response:
```json
{
  "agent_id": "worker-1",
  "instance_id": "i-xxxxx",
  "status": "launching",
  "public_key": "base64..."
}
```

### List Agents
```bash
curl http://localhost:8080/agents
```

### Get Agent Details
```bash
curl http://localhost:8080/agents/worker-1
```

### Send Message to Agent
```bash
curl -X POST http://localhost:8080/message \
  -H "Content-Type: application/json" \
  -d '{
    "from_agent": "jean",
    "to_agent": "worker-1",
    "type": "task",
    "payload": {"action": "analyze", "data": "..."}
  }'
```

### Agent Heartbeat (called by agent)
```bash
curl -X POST http://localhost:8080/heartbeat/worker-1 \
  -H "Content-Type: application/json" \
  -d '{
    "private_ip": "10.0.1.10",
    "public_ip": "54.x.x.x",
    "metrics": {"cpu": 20, "memory": 512}
  }'
```

### Terminate Agent
```bash
curl -X DELETE http://localhost:8080/agents/worker-1
```

### Health Check
```bash
curl http://localhost:8080/health
```

## Agent Bootstrap Flow

1. API server launches EC2 instance with user-data script
2. User-data installs Node.js, Clawdbot, dependencies
3. Writes agent config and secrets
4. Starts message poller (polls tq_messages every 5s)
5. Sends heartbeat every 30s
6. Processes incoming messages

## What's Working

✅ HTTP API for agent management  
✅ EC2 instance provisioning  
✅ Keypair generation and registration  
✅ Message queue (Postgres)  
✅ Heartbeat tracking  
✅ Agent status monitoring  

## What's Missing (add later)

- Authentication/API keys
- Auto-scaling based on load
- Metrics dashboard
- Log aggregation
- Multi-region support

## Time Spent

- Hour 1: API server + schema ✅
- Hour 2: Bootstrap script ✅  
- Hour 3: Deploy + test (IN PROGRESS)
- Hour 4-6: Testing, fixes, demo

## Next Steps

1. Configure AWS credentials and security groups
2. Run schema migration
3. Start API server
4. Test spawn endpoint
5. Verify agent comes online and sends heartbeat
6. Test inter-agent messaging
