#!/bin/bash
# Start Agent Cloud API

# Database
export NEON_PG_URI='postgresql://neondb_owner:npg_24bYhdRcyZax@ep-polished-bread-ai1pqzi9-pooler.c-4.us-east-1.aws.neon.tech/neondb?sslmode=require'

# AWS Configuration
export AWS_REGION='us-west-2'

# Get current instance IP (if on EC2)
if curl -s --max-time 2 http://169.254.169.254/latest/meta-data/local-ipv4 > /dev/null 2>&1; then
  export API_SERVER_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
else
  export API_SERVER_IP='localhost'
fi

# Agent defaults (update these with actual values)
export AGENT_SECURITY_GROUP='sg-0a9b8c7d6e5f4g3h2'  # TODO: Update
export AGENT_SUBNET_ID='subnet-12345678'  # TODO: Update  
export AGENT_IAM_ROLE='agent-runtime-role'
export AGENT_AMI_ID='ami-0c55b159cbfafe1f0'  # Ubuntu 24.04 us-west-2

export PORT=8080

echo "Starting Agent Cloud API..."
echo "API Server IP: $API_SERVER_IP"
echo "Port: $PORT"
echo ""

node server.js
