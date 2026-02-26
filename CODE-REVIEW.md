# Staff Engineering Code Review

**Reviewers:** Jean, Jared, Sam (AI Agents)  
**Date:** 2026-02-26  
**Scope:** Full repository review  

---

## Executive Summary

**Overall Assessment: B+ (Good foundation, needs hardening before production)**

The codebase demonstrates solid architecture and rapid prototyping skills. However, several critical security issues, missing error handling, and scalability concerns must be addressed before production deployment.

---

## 🔴 CRITICAL ISSUES (Must Fix)

### 1. **Secret Exposure in User-Data Scripts**
**File:** `api/express/server.js` (lines 38-45)
```javascript
const userData = `#!/bin/bash
export SECRET_KEY="${secretKey}"
export NEON_PG_URI="${neonPgUri}"
```

**Problem:** Ed25519 secret keys and database credentials are embedded directly in EC2 user-data. This data is:
- Visible in EC2 console to anyone with `DescribeInstanceAttribute` permission
- Logged to `/var/log/cloud-init-output.log`
- Accessible via instance metadata

**Fix:** Use AWS Secrets Manager or SSM Parameter Store. Agents should fetch secrets at runtime:
```javascript
// Instead of embedding secrets in user-data:
const userData = `#!/bin/bash
SECRET_KEY=$(aws secretsmanager get-secret-value --secret-id agent-keys/${agentId} --query SecretString --output text)
```

**Severity:** 🔴 CRITICAL

---

### 2. **No Input Validation on Spawn Endpoint**
**File:** `api/express/server.js` (lines 23-25)
```javascript
const { name, instance_type, capabilities } = req.body;
const agentId = name || `agent-${Date.now()}-...`;
```

**Problem:** No validation of:
- `name` - could contain SQL injection, shell commands
- `instance_type` - arbitrary instance types = cost explosion
- `capabilities` - untrusted input

**Fix:**
```javascript
const ALLOWED_INSTANCE_TYPES = ['t3.micro', 't3.small', 't3.medium'];
const AGENT_NAME_REGEX = /^[a-z0-9-]{3,32}$/;

if (name && !AGENT_NAME_REGEX.test(name)) {
  return res.status(400).json({ error: 'Invalid agent name' });
}
if (!ALLOWED_INSTANCE_TYPES.includes(instance_type)) {
  return res.status(400).json({ error: 'Invalid instance type' });
}
```

**Severity:** 🔴 CRITICAL

---

### 3. **Shell Injection in Bootstrap Script**
**File:** `packer/scripts/bootstrap.sh` (line 31)
```bash
AGENT_UUID=$(echo -n "$AGENT_NAME" | md5sum | ...)
```

**Problem:** `$AGENT_NAME` comes from user input via cloud-init. A malicious agent name like `agent-$(rm -rf /)` could execute arbitrary commands.

**Fix:** Validate and sanitize before use:
```bash
if [[ ! "$AGENT_NAME" =~ ^[a-z0-9-]+$ ]]; then
  echo "Invalid agent name" >&2
  exit 1
fi
```

**Severity:** 🔴 CRITICAL

---

### 4. **Database Connection String in Multiple Places**
**Files:** Multiple

**Problem:** Connection string appears in:
- Environment variables
- User-data scripts
- Terraform outputs
- Test scripts

**Fix:** Centralize in AWS Secrets Manager or SSM. Reference by ARN only.

**Severity:** 🔴 CRITICAL

---

## 🟠 HIGH PRIORITY (Should Fix)

### 5. **No Rate Limiting**
**Files:** All API servers

**Problem:** No protection against:
- Spawn flooding (cost attack)
- Message spam
- Resource exhaustion

**Fix:**
```javascript
const rateLimit = require('express-rate-limit');

const spawnLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 5, // 5 spawns per minute
  message: { error: 'Too many spawn requests' }
});

app.post('/spawn', spawnLimiter, async (req, res) => { ... });
```

**Severity:** 🟠 HIGH

---

### 6. **No Authentication/Authorization**
**Files:** All API endpoints

**Problem:** All endpoints are publicly accessible. Anyone can:
- Spawn agents (cost attack)
- Terminate agents (denial of service)
- Send messages (impersonation)

**Fix:** Implement API key or JWT authentication:
```javascript
const authenticate = (req, res, next) => {
  const apiKey = req.headers['x-api-key'];
  if (!apiKey || apiKey !== process.env.API_KEY) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  next();
};

app.use('/spawn', authenticate);
app.use('/agents', authenticate);
```

**Severity:** 🟠 HIGH

---

### 7. **In-Memory State Will Lose Data**
**File:** `api/node/server.js` (lines 16-17)
```javascript
const clusters = new Map();
const agents = new Map();
```

**Problem:** All state is lost on:
- Server restart
- Deployment
- Process crash

**Fix:** Use the Neon database that's already available:
```javascript
// Instead of Map():
async function getCluster(id) {
  const result = await pool.query(
    'SELECT * FROM clusters WHERE id = $1', [id]
  );
  return result.rows[0];
}
```

**Severity:** 🟠 HIGH

---

### 8. **Missing Health Check Dependencies**
**File:** `api/express/server.js` (line 233)
```javascript
app.get('/health', async (req, res) => {
  await pool.query('SELECT 1');
  res.json({ status: 'healthy' });
});
```

**Problem:** Health check only verifies database. Should also check:
- AWS SDK connectivity
- Disk space
- Memory usage

**Fix:**
```javascript
app.get('/health', async (req, res) => {
  const checks = {
    database: false,
    aws: false,
    disk: false
  };
  
  try {
    await pool.query('SELECT 1');
    checks.database = true;
  } catch (e) { }
  
  try {
    await ec2.describeRegions({}).promise();
    checks.aws = true;
  } catch (e) { }
  
  const healthy = Object.values(checks).every(v => v);
  res.status(healthy ? 200 : 503).json({ status: healthy ? 'healthy' : 'degraded', checks });
});
```

**Severity:** 🟠 HIGH

---

### 9. **No Graceful Shutdown**
**Files:** All API servers

**Problem:** No handling of SIGTERM/SIGINT. In-flight requests will be dropped during deployment.

**Fix:**
```javascript
process.on('SIGTERM', async () => {
  console.log('Shutting down gracefully...');
  server.close(() => {
    pool.end();
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 30000); // Force exit after 30s
});
```

**Severity:** 🟠 HIGH

---

## 🟡 MEDIUM PRIORITY (Nice to Have)

### 10. **Inconsistent Error Handling**
**Files:** All APIs

**Problem:** Some errors return stack traces, others return generic messages. No consistent error format.

**Fix:** Create error middleware:
```javascript
class AppError extends Error {
  constructor(message, statusCode) {
    super(message);
    this.statusCode = statusCode;
  }
}

app.use((err, req, res, next) => {
  console.error(err);
  res.status(err.statusCode || 500).json({
    error: err.message,
    code: err.code || 'INTERNAL_ERROR'
  });
});
```

---

### 11. **No Request Logging**
**Files:** All APIs

**Problem:** No audit trail of who called what endpoints when.

**Fix:**
```javascript
const morgan = require('morgan');
app.use(morgan('combined'));
```

---

### 12. **Hardcoded AMI IDs**
**File:** `api/express/server.js` (line 84)
```javascript
ImageId: process.env.AGENT_AMI_ID || 'ami-0c55b159cbfafe1f0',
```

**Problem:** Hardcoded fallback AMI may become invalid or insecure.

**Fix:** Require AMI ID or fail fast:
```javascript
if (!process.env.AGENT_AMI_ID) {
  throw new Error('AGENT_AMI_ID environment variable required');
}
```

---

### 13. **Missing Database Indexes**
**Implied:** Schema not fully visible

**Problem:** Likely missing indexes on:
- `tq_messages.to_agent` (for polling)
- `tq_messages.created_at` (for ordering)
- `tq_agent_registry.status` (for listing online agents)

**Fix:**
```sql
CREATE INDEX idx_messages_to_agent ON tq_messages(to_agent, created_at);
CREATE INDEX idx_registry_status ON tq_agent_registry(status);
```

---

### 14. **No Terraform State Locking**
**File:** `terraform/main.tf`

**Problem:** S3 backend is commented out. Multiple users running `terraform apply` simultaneously will corrupt state.

**Fix:** Enable state locking with DynamoDB:
```hcl
backend "s3" {
  bucket         = "clawdbot-terraform-state"
  key            = "agent-cluster/terraform.tfstate"
  region         = "us-east-1"
  dynamodb_table = "terraform-locks"
  encrypt        = true
}
```

---

### 15. **Python API Uses debug=True**
**File:** `api/provisioner.py` (line 138)
```python
app.run(host="0.0.0.0", port=port, debug=True)
```

**Problem:** Debug mode in production exposes stack traces and enables the Werkzeug debugger (RCE vulnerability).

**Fix:**
```python
debug = os.environ.get('FLASK_DEBUG', 'false').lower() == 'true'
app.run(host="0.0.0.0", port=port, debug=debug)
```

---

## 🟢 MINOR ISSUES (Low Priority)

### 16. **Inconsistent Port Defaults**
- Express API: 8080
- Node API: 3000
- Python API: 8080

**Fix:** Standardize on a single default port or clearly document the differences.

---

### 17. **Missing package.json/requirements.txt Version Pins**
**Problem:** Dependencies may break on updates.

**Fix:** Pin exact versions:
```json
"dependencies": {
  "express": "4.18.2",
  "pg": "8.11.3"
}
```

---

### 18. **No TypeScript**
**Problem:** JavaScript lacks type safety. Bugs caught at runtime instead of compile time.

**Fix:** Consider migrating to TypeScript for long-term maintainability.

---

### 19. **Magic Numbers**
**File:** Multiple
```javascript
setTimeout(..., 2000);  // What does 2000 mean?
```

**Fix:** Use named constants:
```javascript
const PROVISIONING_POLL_INTERVAL_MS = 2000;
```

---

## Architecture Concerns

### Scalability
- **Current:** Single API server, single database
- **Concern:** Won't scale past ~100 agents
- **Fix:** Add read replicas, implement message queues (SQS/Redis), horizontal API scaling

### Reliability
- **Current:** No redundancy
- **Concern:** Single points of failure everywhere
- **Fix:** Multi-AZ deployment, auto-scaling groups, load balancer

### Observability
- **Current:** Basic logging
- **Concern:** Hard to debug issues in production
- **Fix:** Add metrics (Prometheus), tracing (OpenTelemetry), alerting (PagerDuty)

---

## What's Good ✅

1. **Clean separation of concerns** — APIs, IaC, and bootstrap scripts are well-organized
2. **Ed25519 message signing** — Correct crypto choice for agent authentication
3. **Idempotency keys** — Good practice for message deduplication
4. **Spot instance support** — Cost-conscious design
5. **Comprehensive documentation** — 24 markdown files is excellent
6. **Test coverage** — 30+ automated tests is a solid foundation
7. **Cloud-init approach** — Industry-standard EC2 bootstrapping

---

## Recommendations

### Immediate (Before Production)
1. Move secrets to AWS Secrets Manager
2. Add input validation to all endpoints
3. Implement authentication on APIs
4. Fix shell injection in bootstrap script
5. Add rate limiting

### Short-term (Sprint 2)
1. Replace in-memory state with database
2. Add graceful shutdown handlers
3. Enable Terraform state locking
4. Add request logging and monitoring

### Medium-term (Sprint 3-4)
1. Multi-AZ deployment
2. Auto-scaling
3. Add TypeScript
4. Implement circuit breakers

---

## Sign-off

**Jean:** Architecture is solid. Security needs immediate attention.  
**Jared:** APIs work but need hardening. Good documentation.  
**Sam:** Integration layer is clean. Missing auth is the biggest gap.

**Recommendation:** Address 🔴 CRITICAL issues before any production deployment.
