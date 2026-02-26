# API Integration Examples

Complete examples showing how to use all three APIs together to spawn and manage agent clusters.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     Agent Cloud Infrastructure                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────┐         ┌──────────────────┐             │
│  │   Client/User    │         │   New Agent      │             │
│  │   (You)          │         │   (Spawned)      │             │
│  └────────┬─────────┘         └────────▲─────────┘             │
│           │                            │                        │
│           ▼                            │                        │
│  ┌─────────────────────────────────────┴──────────────────┐    │
│  │              API Layer (Choose One)                     │    │
│  ├──────────────┬──────────────┬──────────────────────────┤    │
│  │  Node.js API │ Express API  │  Python Flask API        │    │
│  │  (Jared)     │ (Sam)        │  (Jean)                  │    │
│  │  Port 3000   │ Port 8080    │  Port 5000               │    │
│  └──────┬───────┴──────┬───────┴───────┬──────────────────┘    │
│         │              │               │                        │
│         └──────────────┴───────────────┘                        │
│                        │                                        │
│                        ▼                                        │
│  ┌────────────────────────────────────────────────────────┐    │
│  │           Coordination Layer                            │    │
│  │  ┌──────────────┐        ┌──────────────────┐          │    │
│  │  │ Agent        │        │  Inter-Agent     │          │    │
│  │  │ Registry     │        │  Messaging       │          │    │
│  │  │ (NeonDB)     │        │  (tq_messages)   │          │    │
│  │  └──────────────┘        └──────────────────┘          │    │
│  └────────────────────────────────────────────────────────┘    │
│                        │                                        │
│                        ▼                                        │
│  ┌────────────────────────────────────────────────────────┐    │
│  │         Infrastructure Provisioning                     │    │
│  │  ┌──────────────┐        ┌──────────────────┐          │    │
│  │  │  Terraform   │        │  Packer AMI      │          │    │
│  │  │  (EC2 spawn) │        │  (Pre-baked)     │          │    │
│  │  └──────────────┘        └──────────────────┘          │    │
│  └────────────────────────────────────────────────────────┘    │
│                        │                                        │
│                        ▼                                        │
│                   AWS Cloud                                     │
│              (EC2 instances running)                            │
└─────────────────────────────────────────────────────────────────┘
```

## Example 1: Spawn Agent Cluster via Node.js API

**Scenario:** Spawn 3 agents using Jared's Node.js API

```bash
# Health check
curl http://localhost:3000/health

# Spawn a cluster of 3 agents
curl -X POST http://localhost:3000/clusters \
  -H "Content-Type: application/json" \
  -d '{
    "count": 3,
    "instance_type": "t3.medium",
    "region": "us-east-2"
  }'

# Response (202 Accepted):
{
  "cluster_id": "a5d91b73-523a-4381-b31f-a5e82133ef96",
  "status": "provisioning",
  "message": "Provisioning 3 agent(s)",
  "poll_url": "/clusters/a5d91b73-523a-4381-b31f-a5e82133ef96"
}

# Poll for status (wait ~2 minutes for provisioning)
curl http://localhost:3000/clusters/a5d91b73-523a-4381-b31f-a5e82133ef96

# Response (when complete):
{
  "id": "a5d91b73-523a-4381-b31f-a5e82133ef96",
  "count": 3,
  "status": "running",
  "agents": [
    {
      "id": "agent-uuid-1",
      "private_ip": "172.31.152.125",
      "status": "running"
    },
    {
      "id": "agent-uuid-2",
      "private_ip": "172.31.192.163",
      "status": "running"
    },
    {
      "id": "agent-uuid-3",
      "private_ip": "172.31.49.80",
      "status": "running"
    }
  ]
}

# List all agents
curl http://localhost:3000/agents

# Terminate a specific agent
curl -X DELETE http://localhost:3000/agents/agent-uuid-1

# Terminate entire cluster
curl -X DELETE http://localhost:3000/clusters/a5d91b73-523a-4381-b31f-a5e82133ef96
```

## Example 2: Agent Registration via Express API

**Scenario:** New agent registers itself and sends messages using Sam's Express API

```bash
# New agent checks in
curl -X POST http://localhost:8080/heartbeat/my-agent-id \
  -H "Content-Type: application/json" \
  -d '{
    "status": "online",
    "instance_ip": "172.31.43.104"
  }'

# List all registered agents
curl http://localhost:8080/agents

# Response:
{
  "agents": [
    {
      "agent_name": "jean",
      "status": "online",
      "instance_ip": "172.31.15.113",
      "model": "claude-opus-4-5"
    },
    {
      "agent_name": "jared",
      "status": "online",
      "instance_ip": "172.31.43.104",
      "model": "claude-sonnet-4-5"
    }
  ]
}

# Send a message to another agent
curl -X POST http://localhost:8080/message \
  -H "Content-Type: application/json" \
  -d '{
    "from_agent": "jared",
    "to_agent": "jean",
    "message_type": "task",
    "payload": {
      "task": "review_pr",
      "pr_number": 42,
      "repo": "agent-infra"
    }
  }'

# Response:
{
  "message_id": "uuid",
  "status": "sent"
}
```

## Example 3: Python Flask Registry API

**Scenario:** Query agent registry and capabilities using Jean's Python API

```bash
# Register a new agent
curl -X POST http://localhost:5000/registry/agents \
  -H "Content-Type: application/json" \
  -d '{
    "agent_id": "sam-agent-001",
    "capabilities": ["code_review", "documentation"],
    "instance_ip": "172.31.1.14",
    "model": "claude-sonnet-4-5"
  }'

# Query available agents by capability
curl "http://localhost:5000/registry/agents?capability=code_review"

# Response:
{
  "agents": [
    {
      "agent_id": "sam-agent-001",
      "capabilities": ["code_review", "documentation"],
      "status": "online",
      "last_seen": "2026-02-26T20:57:00Z"
    }
  ]
}
```

## Example 4: Full Workflow - End-to-End

**Scenario:** Spawn agents, register them, and coordinate a task

```bash
#!/bin/bash
set -e

echo "=== Agent Cluster Spawn & Coordination Demo ==="

# Step 1: Spawn a 2-agent cluster (Node.js API)
echo "1. Spawning cluster..."
CLUSTER_ID=$(curl -s -X POST http://localhost:3000/clusters \
  -H "Content-Type: application/json" \
  -d '{"count":2,"instance_type":"t3.medium"}' \
  | jq -r '.cluster_id')

echo "   Cluster ID: $CLUSTER_ID"

# Step 2: Wait for provisioning
echo "2. Waiting for agents to provision..."
while true; do
  STATUS=$(curl -s http://localhost:3000/clusters/$CLUSTER_ID | jq -r '.status')
  if [ "$STATUS" = "running" ]; then
    break
  fi
  echo "   Status: $STATUS... waiting"
  sleep 10
done

echo "   ✅ Cluster is running!"

# Step 3: Get agent IPs
echo "3. Retrieving agent details..."
curl -s http://localhost:3000/clusters/$CLUSTER_ID | jq '.agents[] | {id, private_ip}'

# Step 4: Verify agents registered themselves (Express API)
echo "4. Checking agent registry..."
curl -s http://localhost:8080/agents | jq '.agents[] | {agent_name, status, instance_ip}'

# Step 5: Send a coordination message
echo "5. Sending task to first agent..."
FIRST_AGENT=$(curl -s http://localhost:8080/agents | jq -r '.agents[0].agent_name')

curl -s -X POST http://localhost:8080/message \
  -H "Content-Type: application/json" \
  -d "{
    \"from_agent\": \"coordinator\",
    \"to_agent\": \"$FIRST_AGENT\",
    \"message_type\": \"task\",
    \"payload\": {
      \"task\": \"health_check\",
      \"priority\": \"high\"
    }
  }" | jq

echo ""
echo "✅ Demo complete! Cluster is running and coordinating."
```

## Example 5: Agent-to-Agent Communication

**Scenario:** Agents discover each other and communicate directly

**Agent A (discovers Agent B):**
```bash
# Agent A queries registry for available agents
curl http://localhost:8080/agents

# Response shows Agent B is online
{
  "agents": [
    {
      "agent_name": "agent-b",
      "instance_ip": "172.31.50.20",
      "status": "online"
    }
  ]
}

# Agent A sends task to Agent B
curl -X POST http://localhost:8080/message \
  -H "Content-Type: application/json" \
  -d '{
    "from_agent": "agent-a",
    "to_agent": "agent-b",
    "message_type": "task_request",
    "payload": {
      "task": "analyze_logs",
      "log_path": "/var/log/app.log"
    }
  }'
```

**Agent B (receives and responds):**
```bash
# Agent B polls for messages (typically done in bootstrap script)
psql "$NEON_CONNECTION_STRING" -c "
  SELECT id, from_agent, message_type, payload
  FROM tq_messages
  WHERE to_agent = 'agent-b'
    AND read_at IS NULL
  ORDER BY created_at DESC;
"

# Agent B marks message as read and sends response
curl -X POST http://localhost:8080/message \
  -H "Content-Type: application/json" \
  -d '{
    "from_agent": "agent-b",
    "to_agent": "agent-a",
    "message_type": "task_response",
    "payload": {
      "status": "completed",
      "result": "No errors found in logs"
    }
  }'
```

## Example 6: Error Handling

**Scenario:** Graceful error handling across APIs

```bash
# Attempt to spawn with invalid parameters
curl -X POST http://localhost:3000/clusters \
  -H "Content-Type: application/json" \
  -d '{"count":-1}'

# Response (400 Bad Request):
{
  "error": "Invalid cluster count: must be between 1 and 100"
}

# Attempt to retrieve non-existent cluster
curl http://localhost:3000/clusters/nonexistent-id

# Response (404 Not Found):
{
  "error": "Cluster not found"
}

# Attempt to terminate already-terminated agent
curl -X DELETE http://localhost:3000/agents/already-gone

# Response (404 Not Found):
{
  "error": "Agent not found"
}
```

## Example 7: Monitoring and Health Checks

**Scenario:** Check system health across all APIs

```bash
# Check Node.js API health
curl http://localhost:3000/health
# {"status":"healthy","service":"agent-provisioner"}

# Check Express API health
curl http://localhost:8080/health
# {"status":"healthy"}

# Check Python API health
curl http://localhost:5000/health
# {"status":"ok","timestamp":"2026-02-26T20:57:00Z"}

# Get cluster statistics
curl http://localhost:3000/clusters | jq '{
  total_clusters: (.clusters | length),
  total_agents: ([.clusters[].agents[]] | length)
}'

# Get agent statistics
curl http://localhost:8080/agents | jq '{
  total_agents: (.agents | length),
  online_agents: ([.agents[] | select(.status=="online")] | length)
}'
```

## Integration Patterns

### Pattern 1: Load Balancing

Distribute tasks across multiple agents:

```bash
# Get all online agents
AGENTS=$(curl -s http://localhost:8080/agents | jq -r '.agents[] | select(.status=="online") | .agent_name')

# Round-robin task assignment
TASK_ID=0
for AGENT in $AGENTS; do
  curl -X POST http://localhost:8080/message \
    -H "Content-Type: application/json" \
    -d "{
      \"from_agent\": \"coordinator\",
      \"to_agent\": \"$AGENT\",
      \"message_type\": \"task\",
      \"payload\": {\"task_id\": $TASK_ID}
    }"
  ((TASK_ID++))
done
```

### Pattern 2: Auto-Scaling

Monitor load and spawn more agents when needed:

```bash
# Check current agent count
CURRENT=$(curl -s http://localhost:8080/agents | jq '.agents | length')

# If load is high (example metric), spawn more
if [ $CURRENT -lt 10 ]; then
  NEEDED=$((10 - CURRENT))
  curl -X POST http://localhost:3000/clusters \
    -d "{\"count\":$NEEDED}"
fi
```

### Pattern 3: Fault Tolerance

Detect and replace failed agents:

```bash
# Find agents that haven't sent heartbeat in 5 minutes
STALE=$(psql "$NEON_CONNECTION_STRING" -t -c "
  SELECT agent_name
  FROM tq_agent_registry
  WHERE last_seen < NOW() - INTERVAL '5 minutes';
")

# Spawn replacements
if [ -n "$STALE" ]; then
  COUNT=$(echo "$STALE" | wc -l)
  curl -X POST http://localhost:3000/clusters -d "{\"count\":$COUNT}"
fi
```

## API Comparison Matrix

| Feature | Node.js API | Express API | Python API |
|---------|-------------|-------------|------------|
| **Port** | 3000 | 8080 | 5000 |
| **Cluster Spawn** | ✅ Yes | ⏳ Planned | ✅ Yes |
| **Agent Registry** | ❌ No | ✅ Yes | ✅ Yes |
| **Messaging** | ❌ No | ✅ Yes | ❌ No |
| **Heartbeats** | ❌ No | ✅ Yes | ❌ No |
| **Terraform Integration** | ✅ Yes | ⏳ Planned | ✅ Yes |

**Recommendation:**
- **Cluster management:** Use Node.js or Python API
- **Agent coordination:** Use Express API
- **Mixed workflows:** Combine multiple APIs as shown in examples

## Next Steps

1. Choose your primary API based on use case
2. See [QUICKSTART.md](QUICKSTART.md) for installation
3. See [MANUAL-SPAWN.md](MANUAL-SPAWN.md) for non-automated spawning
4. See [INTEGRATION.md](INTEGRATION.md) for connecting Terraform

## Troubleshooting

**Problem:** APIs can't reach each other

**Solution:** Check security groups allow traffic between instances on required ports (3000, 5000, 8080)

**Problem:** Agents don't register after spawning

**Solution:** Verify NeonDB connection string in bootstrap script

**Problem:** Messages not being delivered

**Solution:** Check `tq_messages` table for errors, verify idempotency_key is set

---

**Authors:** Jared (Node.js API), Sam (Express API), Jean (Python API)  
**Last Updated:** 2026-02-26
