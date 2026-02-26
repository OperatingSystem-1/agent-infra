# Agent Provisioner API

REST API for spawning and managing agent clusters.

## Status: MVP (Mocked Terraform calls)

Currently returns mock responses. Will integrate with Jean's Terraform modules when ready.

## Quick Start

```bash
npm install
node server.js
```

## API Endpoints

### Spawn a Cluster
```bash
POST /clusters
{
  "count": 3,
  "instance_type": "t3.medium",
  "region": "us-east-2"
}

# Response (202 Accepted)
{
  "cluster_id": "uuid",
  "status": "provisioning",
  "poll_url": "/clusters/uuid"
}
```

### Check Cluster Status
```bash
GET /clusters/:id

# Response
{
  "id": "uuid",
  "count": 3,
  "status": "running",
  "agents": [
    {
      "id": "agent-uuid",
      "private_ip": "172.31.x.x",
      "status": "running"
    }
  ]
}
```

### List All Agents
```bash
GET /agents
GET /agents?cluster_id=uuid
GET /agents?status=running
```

### Terminate Agent
```bash
DELETE /agents/:id
```

### Terminate Cluster
```bash
DELETE /clusters/:id
```

## Integration Points

### For Jean (Terraform)
Replace the mock provisioning in `POST /clusters` with:
```javascript
const { spawn } = require('child_process');

// In /clusters endpoint
const terraform = spawn('terraform', ['apply', '-auto-approve', ...]);
```

### For Sam (Bootstrap)
Agents should call back to register:
```bash
curl -X POST http://provisioner-api:3000/terraform/callback \
  -d '{"agent_id":"uuid","status":"running","metadata":{"public_ip":"x.x.x.x"}}'
```

## TODO (Integration)
- [ ] Replace mock provisioning with actual Terraform exec
- [ ] Add database persistence (currently in-memory)
- [ ] Add authentication/API keys
- [ ] Add WebSocket for real-time status updates
- [ ] Add cost estimation endpoint
- [ ] Add metrics/monitoring
