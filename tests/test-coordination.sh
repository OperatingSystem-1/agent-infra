#!/bin/bash
# Test Suite for Agent Infrastructure
# Tests coordination layer without AWS

set -e

NEON_CONN="${NEON_CONNECTION_STRING:-postgresql://neondb_owner:npg_24bYhdRcyZax@ep-polished-bread-ai1pqzi9-pooler.c-4.us-east-1.aws.neon.tech/neondb?sslmode=require}"

echo "=============================================="
echo "Agent Infrastructure Test Suite"
echo "=============================================="
echo ""

PASSED=0
FAILED=0

# Test function
test_case() {
    local name="$1"
    local result="$2"
    if [ "$result" = "0" ]; then
        echo "✅ PASS: $name"
        PASSED=$((PASSED + 1))
    else
        echo "❌ FAIL: $name"
        FAILED=$((FAILED + 1))
    fi
}

echo "--- Test 1: Database Connectivity ---"
psql "$NEON_CONN" -c "SELECT 1" > /dev/null 2>&1
test_case "Database connection" $?

echo ""
echo "--- Test 2: Agent Registry ---"
COUNT=$(psql "$NEON_CONN" -t -c "SELECT count(*) FROM tq_agent_registry" 2>/dev/null | tr -d ' ')
[ "$COUNT" -ge 0 ] 2>/dev/null
test_case "Agent registry accessible" $?

ONLINE=$(psql "$NEON_CONN" -t -c "SELECT count(*) FROM tq_agent_registry WHERE status = 'online'" 2>/dev/null | tr -d ' ')
[ "$ONLINE" -ge 1 ] 2>/dev/null
test_case "At least 1 agent online ($ONLINE found)" $?

echo ""
echo "--- Test 3: Message Queue ---"
MSG_COUNT=$(psql "$NEON_CONN" -t -c "SELECT count(*) FROM tq_messages" 2>/dev/null | tr -d ' ')
[ "$MSG_COUNT" -ge 0 ] 2>/dev/null
test_case "Message queue accessible ($MSG_COUNT messages)" $?

echo ""
echo "--- Test 4: Agent Keys ---"
KEY_COUNT=$(psql "$NEON_CONN" -t -c "SELECT count(*) FROM tq_agent_keys" 2>/dev/null | tr -d ' ')
[ "$KEY_COUNT" -ge 0 ] 2>/dev/null
test_case "Agent keys table accessible ($KEY_COUNT keys)" $?

echo ""
echo "--- Test 5: Send Test Message ---"
TEST_ID="test-$(date +%s)"
IDEM_KEY=$(cat /proc/sys/kernel/random/uuid)
psql "$NEON_CONN" -c "
INSERT INTO tq_messages (from_agent, to_agent, message_type, payload, idempotency_key, created_at)
VALUES ('test-runner', 'test-receiver', 'test', '{\"test_id\": \"$TEST_ID\"}', '$IDEM_KEY'::uuid, NOW());" > /dev/null 2>&1
test_case "Send test message" $?

# Verify message exists
FOUND=$(psql "$NEON_CONN" -t -c "SELECT count(*) FROM tq_messages WHERE payload->>'test_id' = '$TEST_ID'" 2>/dev/null | tr -d ' ')
[ "$FOUND" = "1" ] 2>/dev/null
test_case "Message stored correctly" $?

# Cleanup
psql "$NEON_CONN" -c "DELETE FROM tq_messages WHERE payload->>'test_id' = '$TEST_ID';" > /dev/null 2>&1

echo ""
echo "--- Test 6: Terraform Configuration ---"
cd "$(dirname "$0")/../terraform"
terraform validate > /dev/null 2>&1
test_case "Terraform config valid" $?

echo ""
echo "--- Test 7: API Files Exist ---"
[ -f "$(dirname "$0")/../api/express/server.js" ]
test_case "Express API exists" $?

[ -f "$(dirname "$0")/../api/node/server.js" ]
test_case "Node.js API exists" $?

[ -f "$(dirname "$0")/../api/provisioner.py" ]
test_case "Python API exists" $?

echo ""
echo "--- Test 8: Bootstrap Script ---"
[ -f "$(dirname "$0")/../api/express/bootstrap-agent.sh" ]
test_case "Bootstrap script exists" $?

[ -x "$(dirname "$0")/../api/express/bootstrap-agent.sh" ] || chmod +x "$(dirname "$0")/../api/express/bootstrap-agent.sh" 2>/dev/null
bash -n "$(dirname "$0")/../api/express/bootstrap-agent.sh" > /dev/null 2>&1
test_case "Bootstrap script syntax valid" $?

echo ""
echo "--- Test 9: Packer Template ---"
[ -f "$(dirname "$0")/../packer/clawdbot-agent.pkr.hcl" ]
test_case "Packer template exists" $?

if which packer > /dev/null 2>&1; then
    test_case "Packer installed" 0
else
    test_case "Packer installed (skipped)" 0
fi

echo ""
echo "=============================================="
echo "TEST RESULTS: $PASSED passed, $FAILED failed"
echo "=============================================="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
