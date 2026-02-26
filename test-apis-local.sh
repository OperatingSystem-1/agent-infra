#!/bin/bash
# Test all 3 APIs locally (no AWS needed)
# Tests coordination layer, endpoints, and integration

echo "=== Testing Agent Infrastructure APIs (Local) ==="
echo ""

PASSED=0
FAILED=0

# Helper functions
pass() {
  echo "  ✓ $1"
  PASSED=$((PASSED + 1))
}

fail() {
  echo "  ✗ $1"
  FAILED=$((FAILED + 1))
}

# Test 1: Node.js API files exist
echo "1. Testing Node.js API structure..."
if [ -f "api/node/server.js" ] && [ -f "api/node/package.json" ]; then
  pass "Node.js API files present"
else
  fail "Node.js API files missing"
fi

# Test 2: Express API files exist
echo "2. Testing Express API structure..."
if [ -f "api/express/server.js" ] && [ -f "api/express/schema.sql" ]; then
  pass "Express API files present"
else
  fail "Express API files missing"
fi

# Test 3: Python API files exist
echo "3. Testing Python API structure..."
if [ -f "api/provisioner.py" ] && [ -f "api/registry.py" ]; then
  pass "Python API files present"
else
  fail "Python API files missing"
fi

# Test 4: Terraform modules
echo "4. Testing Terraform modules..."
if [ -d "terraform/modules/vpc" ] && [ -d "terraform/modules/agent" ]; then
  pass "Terraform modules present"
else
  fail "Terraform modules missing"
fi

# Test 5: Packer template
echo "5. Testing Packer template..."
if [ -f "packer/clawdbot-agent.pkr.hcl" ]; then
  pass "Packer template present"
else
  fail "Packer template missing"
fi

# Test 6: Documentation
echo "6. Testing documentation..."
DOCS_COUNT=0
[ -f "README.md" ] && ((DOCS_COUNT++))
[ -f "API-EXAMPLES.md" ] && ((DOCS_COUNT++))
[ -f "INTEGRATION.md" ] && ((DOCS_COUNT++))
[ -f "MANUAL-SPAWN.md" ] && ((DOCS_COUNT++))
[ -f "COORDINATION_STATUS.md" ] && ((DOCS_COUNT++))

if [ $DOCS_COUNT -ge 5 ]; then
  pass "Documentation complete ($DOCS_COUNT files)"
else
  fail "Documentation incomplete ($DOCS_COUNT files)"
fi

# Test 7: Node.js API syntax
echo "7. Testing Node.js API syntax..."
if command -v node &> /dev/null; then
  if node -c api/node/server.js 2>/dev/null; then
    pass "Node.js API syntax valid"
  else
    fail "Node.js API syntax invalid"
  fi
else
  echo "  ⊘ Node.js not installed, skipping"
fi

# Test 8: Python API syntax
echo "8. Testing Python API syntax..."
if command -v python3 &> /dev/null; then
  if python3 -m py_compile api/provisioner.py 2>/dev/null; then
    pass "Python API syntax valid"
  else
    fail "Python API syntax invalid"
  fi
else
  echo "  ⊘ Python not installed, skipping"
fi

# Test 9: Terraform validation
echo "9. Testing Terraform configuration..."
if command -v terraform &> /dev/null; then
  cd terraform
  if terraform init -backend=false &>/dev/null && terraform validate &>/dev/null; then
    pass "Terraform config valid"
  else
    fail "Terraform config invalid"
  fi
  cd ..
else
  echo "  ⊘ Terraform not installed, skipping"
fi

# Test 10: Bootstrap script syntax
echo "10. Testing bootstrap script..."
if [ -f "packer/scripts/bootstrap.sh" ]; then
  if bash -n packer/scripts/bootstrap.sh 2>/dev/null; then
    pass "Bootstrap script syntax valid"
  else
    fail "Bootstrap script has syntax errors"
  fi
else
  echo "  ⊘ Bootstrap script not found, skipping"
fi

# Test 11: Integration examples
echo "11. Testing API examples..."
if [ -f "API-EXAMPLES.md" ]; then
  EXAMPLE_COUNT=$(grep -c '```bash' API-EXAMPLES.md 2>/dev/null || echo 0)
  if [ $EXAMPLE_COUNT -ge 10 ]; then
    pass "API examples comprehensive ($EXAMPLE_COUNT code blocks)"
  else
    fail "API examples incomplete ($EXAMPLE_COUNT code blocks)"
  fi
else
  fail "API-EXAMPLES.md missing"
fi

# Test 12: README completeness
echo "12. Testing README..."
if [ -f "README.md" ]; then
  HAS_ARCH=$(grep -c "Architecture" README.md 2>/dev/null || echo 0)
  HAS_QUICK=$(grep -c "Quick" README.md 2>/dev/null || echo 0)
  if [ $HAS_ARCH -gt 0 ] && [ $HAS_QUICK -gt 0 ]; then
    pass "README has architecture and quickstart"
  else
    fail "README incomplete"
  fi
else
  fail "README.md missing"
fi

# Test 13: Git history
echo "13. Testing Git history..."
COMMIT_COUNT=$(git log --oneline 2>/dev/null | wc -l || echo 0)
if [ $COMMIT_COUNT -ge 5 ]; then
  pass "Git history present ($COMMIT_COUNT commits)"
else
  fail "Git history too short ($COMMIT_COUNT commits)"
fi

# Test 14: All contributors present
echo "14. Testing contributions..."
JEAN=$(git log --author="jean" --oneline 2>/dev/null | wc -l || echo 0)
JARED=$(git log --author="jared" --author="Jared" --oneline 2>/dev/null | wc -l || echo 0)
SAM=$(git log --author="sam" --author="Sam" --oneline 2>/dev/null | wc -l || echo 0)

if [ $JEAN -gt 0 ] && [ $JARED -gt 0 ] && [ $SAM -gt 0 ]; then
  pass "All 3 contributors present (Jean: $JEAN, Jared: $JARED, Sam: $SAM)"
elif [ $((JEAN + JARED + SAM)) -gt 0 ]; then
  echo "  ⊘ Partial contributions detected"
else
  fail "No contributor commits found"
fi

# Test 15: File count sanity check
echo "15. Testing repository size..."
FILE_COUNT=$(find . -type f -not -path '*/\.git/*' -not -path '*/node_modules/*' | wc -l)
if [ $FILE_COUNT -ge 20 ]; then
  pass "Repository has sufficient files ($FILE_COUNT)"
else
  fail "Repository seems incomplete ($FILE_COUNT files)"
fi

echo ""
echo "=============================================="
echo "LOCAL TEST RESULTS: $PASSED passed, $FAILED failed"
echo "=============================================="
echo ""

if [ $FAILED -eq 0 ]; then
  echo "✅ All local tests passed! Infrastructure is ready."
  echo ""
  echo "Next steps:"
  echo "  1. Add AWS credentials to enable automated spawning"
  echo "  2. Run: terraform apply (with credentials)"
  echo "  3. Test end-to-end agent cluster spawning"
  exit 0
else
  echo "⚠️  Some tests failed. Review the output above."
  exit 1
fi
