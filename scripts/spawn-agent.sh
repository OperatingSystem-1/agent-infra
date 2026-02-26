#!/bin/bash
# Quick agent spawning script
# Usage: ./spawn-agent.sh <agent-name> [model] [instance-type]

set -e

AGENT_NAME="${1:-agent-$(date +%s)}"
AGENT_MODEL="${2:-claude-sonnet-4-20250514}"
INSTANCE_TYPE="${3:-t3.medium}"

echo "=== Spawning Agent: $AGENT_NAME ==="
echo "Model: $AGENT_MODEL"
echo "Instance: $INSTANCE_TYPE"
echo ""

# Check AWS credentials
if ! aws sts get-caller-identity &>/dev/null; then
    echo "ERROR: AWS credentials not configured"
    echo "Run: aws configure"
    exit 1
fi

# Check for required env vars
if [ -z "$NEON_CONNECTION_STRING" ]; then
    echo "ERROR: NEON_CONNECTION_STRING not set"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$INFRA_DIR/terraform"
STATE_DIR="$INFRA_DIR/state/$AGENT_NAME"

mkdir -p "$STATE_DIR"

# Copy terraform files
cp -r "$TERRAFORM_DIR"/* "$STATE_DIR/"

cd "$STATE_DIR"

# Initialize terraform
echo "[1/4] Initializing Terraform..."
terraform init -input=false

# Create tfvars
cat > terraform.tfvars <<EOF
cluster_name = "$AGENT_NAME"
agent_count = 1
agent_model = "$AGENT_MODEL"
use_spot = true
neon_connection_string = "$NEON_CONNECTION_STRING"
anthropic_api_key = "${ANTHROPIC_API_KEY:-}"
EOF

# Plan
echo "[2/4] Planning..."
terraform plan -out=tfplan

# Apply
echo "[3/4] Applying..."
terraform apply tfplan

# Output
echo "[4/4] Agent spawned!"
terraform output

echo ""
echo "=== Agent $AGENT_NAME is launching ==="
echo "Check registration: psql \$NEON_CONNECTION_STRING -c \"SELECT * FROM tq_agent_registry WHERE agent_name = '$AGENT_NAME'\""
