#!/bin/bash
set -e

API_URL="http://localhost:3000"

echo "=== Testing Agent Provisioner API ==="
echo

echo "1. Health Check"
curl -s $API_URL/health | jq
echo

echo "2. Spawn a 3-agent cluster"
CLUSTER_ID=$(curl -s -X POST $API_URL/clusters \
  -H "Content-Type: application/json" \
  -d '{"count":3,"instance_type":"t3.medium","region":"us-east-2"}' \
  | jq -r '.cluster_id')

echo "   Cluster ID: $CLUSTER_ID"
echo

echo "3. Wait for provisioning (3 seconds)..."
sleep 3

echo "4. Check cluster status"
curl -s $API_URL/clusters/$CLUSTER_ID | jq
echo

echo "5. List all agents"
curl -s $API_URL/agents | jq '.agents[] | {id, private_ip, status}'
echo

echo "6. Get specific agent"
AGENT_ID=$(curl -s $API_URL/agents | jq -r '.agents[0].id')
echo "   Agent ID: $AGENT_ID"
curl -s $API_URL/agents/$AGENT_ID | jq
echo

echo "7. List all clusters"
curl -s $API_URL/clusters | jq
echo

echo "✅ All tests passed!"
