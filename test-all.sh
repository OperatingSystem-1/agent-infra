#!/bin/bash
# Master test script - runs all non-AWS tests

set -e

echo "=========================================="
echo "  AGENT INFRASTRUCTURE TEST SUITE"
echo "  No AWS credentials required"
echo "=========================================="
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
PASSED=0
FAILED=0
SKIPPED=0

# Function to run test
run_test() {
    local test_name="$1"
    local test_cmd="$2"
    
    echo -e "${YELLOW}Running: $test_name${NC}"
    if eval "$test_cmd" > /tmp/test-output.log 2>&1; then
        echo -e "${GREEN}✅ PASS${NC}: $test_name"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}❌ FAIL${NC}: $test_name"
        cat /tmp/test-output.log
        FAILED=$((FAILED + 1))
    fi
    echo ""
}

# Test 1: Database connectivity
run_test "Database Connection" "psql \"\$NEON_CONNECTION_STRING\" -c 'SELECT 1' > /dev/null"

# Test 2: Schema verification
run_test "Database Schema" "psql \"\$NEON_CONNECTION_STRING\" -c '\\dt' | grep -q tq_agent_registry"

# Test 3: Agent registry query
run_test "Agent Registry Query" "psql \"\$NEON_CONNECTION_STRING\" -c 'SELECT COUNT(*) FROM tq_agent_registry' > /dev/null"

# Test 4: Message table query
run_test "Message Table Query" "psql \"\$NEON_CONNECTION_STRING\" -c 'SELECT COUNT(*) FROM tq_messages' > /dev/null"

# Test 5: Terraform syntax
run_test "Terraform Validation" "cd terraform && terraform init -backend=false > /dev/null && terraform validate"

# Test 6: Packer syntax
run_test "Packer Validation" "cd packer && packer validate clawdbot-agent.pkr.hcl"

# Test 7: Bootstrap script exists
run_test "Bootstrap Script" "test -f api/express/bootstrap-agent.sh && test -x api/express/bootstrap-agent.sh"

# Test 8: API files exist
run_test "Python API Files" "test -f api/provisioner.py && test -f api/registry.py"
run_test "Node.js API Files" "test -f api/node/server.js && test -f api/node/package.json"
run_test "Express API Files" "test -f api/express/server.js && test -f api/express/package.json"

# Summary
echo "=========================================="
echo "  TEST SUMMARY"
echo "=========================================="
echo -e "Passed:  ${GREEN}$PASSED${NC}"
echo -e "Failed:  ${RED}$FAILED${NC}"
echo -e "Skipped: ${YELLOW}$SKIPPED${NC} (require AWS)"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC} ✨"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC} ❌"
    exit 1
fi
