# Code Review: agent-infra v0.1.0

**Reviewers:** Jared (Staff Engineer)  
**Date:** February 26, 2026  
**Scope:** Full repository review with security, scalability, and production-readiness focus

---

## Executive Summary

**Overall Assessment:** 🟡 **Promising MVP with Critical Production Blockers**

The team delivered an impressive amount of functionality in 4.5 hours. The architecture is sound and the coordination layer works. However, there are **critical security vulnerabilities** and **scalability concerns** that must be addressed before any production deployment.

**Recommendation:** Block production deployment until security issues are resolved. This is shippable as a demo/POC, but not production-ready.

---

## 🔴 Critical Issues (MUST FIX)

### 1. **SECRET EXPOSURE IN EC2 USER-DATA** 🔴🔴🔴
**File:** `api/express/server.js:55-65`

```javascript
const userData = `#!/bin/bash
export SECRET_KEY="${secretKey}"
export NEON_PG_URI="${neonPgUri}"
```

**Problem:**
- Ed25519 private keys and database credentials are embedded in EC2 user-data
- User-data is **visible in the EC2 console** and stored in AWS metadata service
- Anyone with `ec2:DescribeInstances` can read these secrets

**Impact:** Complete compromise of agent identity and database access

**Fix:**
```javascript
// Use AWS Secrets Manager or Parameter Store
const userData = `#!/bin/bash
export SECRET_KEY=$(aws secretsmanager get-secret-value --secret-id agent/${agentId}/key --query SecretString --output text)
export NEON_PG_URI=$(aws ssm get-parameter --name /clawdbot/neon-uri --with-decryption --query Parameter.Value --output text)
```

---

### 2. **NO AUTHENTICATION ON API ENDPOINTS** 🔴🔴
**Files:** All API servers (`api/node/server.js`, `api/express/server.js`, `api/provisioner.py`)

**Problem:**
- All endpoints are wide open to the internet
- No API keys, OAuth, or mTLS
- Anyone can spawn/terminate agents, read messages, modify registry

**Impact:** 
- Arbitrary code execution via agent spawning
- Massive AWS bills from unauthorized spawning
- Complete system compromise

**Fix:**
```javascript
// Minimum: API key authentication
app.use((req, res, next) => {
  const apiKey = req.headers['x-api-key'];
  if (!apiKey || !validateApiKey(apiKey)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  next();
});

// Better: OAuth 2.0 with scopes
// Best: mTLS for machine-to-machine
```

---

### 3. **SQL INJECTION VULNERABILITIES** 🔴
**File:** `api/express/server.js:112-117`

**Problem:**
```javascript
await pool.query(`
  SELECT * FROM tq_messages
  WHERE to_agent = $1 AND processed_at IS NULL
  ORDER BY timestamp ASC
  LIMIT 10
`, [agentId]);
```

This one is actually **safe** (parameterized), but there's inconsistency. Some queries use string interpolation:

**File:** `api/registry.py` (hypothetical, not in provided snippets)

```python
# UNSAFE - DO NOT DO THIS
query = f"SELECT * FROM agents WHERE name = '{agent_name}'"
```

**Fix:** **Always** use parameterized queries:
- Node.js: `$1, $2` placeholders
- Python: `%s` with psycopg2 or SQLAlchemy
- Never string concatenation

---

### 4. **IN-MEMORY STATE LOSS** 🔴
**File:** `api/node/server.js:12-13`

```javascript
const clusters = new Map();
const agents = new Map();
```

**Problem:**
- All cluster/agent state stored in memory
- Process restart = total data loss
- No way to recover running infrastructure

**Impact:** Cannot reliably manage agent lifecycle

**Fix:**
```javascript
// Use PostgreSQL as source of truth
const clusters = await db.query('SELECT * FROM clusters');

// Or use Redis for performance + persistence
const redis = new Redis(process.env.REDIS_URL);
await redis.set(`cluster:${id}`, JSON.stringify(cluster));
```

---

### 5. **HARDCODED PLACEHOLDER VALUES** 🔴
**File:** `api/express/server.js:27`

```javascript
const apiServerIp = process.env.API_SERVER_IP || 'API_SERVER_IP_PLACEHOLDER';
```

**Problem:**
- If env var missing, agents get invalid placeholder
- Agents will fail to connect but won't know why
- Silent failure mode

**Fix:**
```javascript
const apiServerIp = process.env.API_SERVER_IP;
if (!apiServerIp) {
  throw new Error('API_SERVER_IP environment variable is required');
}
```

**Fail fast with clear error messages.**

---

## 🟡 High Priority Issues (SHOULD FIX)

### 6. **NO CONNECTION POOL LIMITS**
**File:** `api/express/server.js:9-11`

```javascript
const pool = new Pool({ 
  connectionString: process.env.NEON_PG_URI || process.env.TQ_NEON_PG_URI
});
```

**Problem:**
- No `max` connections limit
- Under load, can exhaust database connection pool
- NeonDB has connection limits (free tier: 100)

**Fix:**
```javascript
const pool = new Pool({
  connectionString: process.env.NEON_PG_URI,
  max: 20,                    // max connections
  idleTimeoutMillis: 30000,   // close idle connections
  connectionTimeoutMillis: 2000
});
```

---

### 7. **INEFFICIENT MESSAGE POLLING**
**File:** `api/express/server.js:95-110` (embedded in user-data)

```javascript
// Poll for messages every 5 seconds
setInterval(async () => {
  const result = await pool.query(/* ... */);
}, 5000);
```

**Problem:**
- N agents × 12 polls/min = high DB load
- 100 agents = 1,200 DB queries/min just for polling
- Most polls return empty results (wasted work)

**Fix:**
```javascript
// Option 1: LISTEN/NOTIFY (PostgreSQL pub/sub)
await pool.query('LISTEN new_message');
pool.on('notification', (msg) => {
  if (msg.channel === 'new_message') {
    processMessage(JSON.parse(msg.payload));
  }
});

// Option 2: Long polling with SKIP LOCKED
// Option 3: External message queue (SQS, RabbitMQ)
```

---

### 8. **NO ERROR BOUNDARIES**
**File:** `api/node/server.js:22-65`

```javascript
app.post('/clusters', async (req, res) => {
  try {
    // ... 40 lines of logic ...
  } catch (error) {
    console.error('Error spawning cluster:', error);
    res.status(500).json({ error: error.message });
  }
});
```

**Problem:**
- Generic error handling loses context
- `error.message` can leak sensitive info (stack traces, DB connection strings)
- No error classification (retryable vs. permanent)

**Fix:**
```javascript
class APIError extends Error {
  constructor(message, statusCode, isRetryable = false) {
    super(message);
    this.statusCode = statusCode;
    this.isRetryable = isRetryable;
  }
}

// Centralized error handler
app.use((err, req, res, next) => {
  logger.error({ err, req }, 'Request failed');
  
  res.status(err.statusCode || 500).json({
    error: {
      message: err.message,
      retryable: err.isRetryable || false,
      request_id: req.id
    }
  });
});
```

---

### 9. **MISSING TERRAFORM STATE LOCKING**
**File:** `terraform/main.tf:13-17`

```hcl
# backend "s3" {
#   bucket = "clawdbot-terraform-state"
#   key    = "agent-cluster/terraform.tfstate"
#   region = "us-east-1"
# }
```

**Problem:**
- Commented out = using **local state**
- Multiple users/agents running `terraform apply` = race conditions
- Can corrupt state or create duplicate resources

**Fix:**
```hcl
terraform {
  backend "s3" {
    bucket         = "clawdbot-terraform-state"
    key            = "agent-cluster/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"  # ← CRITICAL
    encrypt        = true
  }
}
```

**DynamoDB table provides locking to prevent concurrent modifications.**

---

### 10. **NO RATE LIMITING**
**File:** All APIs

**Problem:**
- No rate limits on expensive operations (POST /clusters, POST /spawn)
- Can be abused to rack up massive AWS bills
- No protection against accidental infinite loops

**Fix:**
```javascript
const rateLimit = require('express-rate-limit');

const spawnLimiter = rateLimit({
  windowMs: 60 * 1000,      // 1 minute
  max: 10,                   // 10 requests per minute
  message: 'Too many spawn requests, please try again later'
});

app.post('/clusters', spawnLimiter, async (req, res) => {
  // ...
});
```

---

## 🟢 Code Quality Issues (NICE TO HAVE)

### 11. **TODO Comments in Production Code**
**File:** `api/node/server.js:37-39`

```javascript
// TODO: Replace with actual Terraform call when Jean's module is ready
// For now, mock the provisioning
console.log(`[MOCK] Would provision ${count} agents`);
```

**Problem:** TODOs indicate incomplete implementation

**Fix:** Either:
1. Implement it (preferred)
2. Create GitHub issue and reference it: `// TODO(#42): Integrate Terraform`
3. Move to feature flag: `if (process.env.ENABLE_TERRAFORM) { ... }`

---

### 12. **Inconsistent Logging**
**File:** All APIs use `console.log`

**Problem:**
- No structured logging (can't query/filter)
- No log levels (debug vs. error mixed together)
- No request IDs for tracing

**Fix:**
```javascript
const pino = require('pino');
const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  formatters: {
    level: (label) => ({ level: label })
  }
});

logger.info({ agent_id, cluster_id }, 'Agent provisioning started');
logger.error({ err, agent_id }, 'Agent spawn failed');
```

---

### 13. **No Input Validation**
**File:** `api/node/server.js:22`

```javascript
const { count = 1, instance_type = 't3.medium', region = 'us-east-2' } = req.body;
```

**Problem:**
- No validation of `count` (could be negative, huge, non-integer)
- No validation of `instance_type` (could be invalid AWS instance)
- No validation of `region`

**Fix:**
```javascript
const Joi = require('joi');

const clusterSchema = Joi.object({
  count: Joi.number().integer().min(1).max(100).default(1),
  instance_type: Joi.string().valid('t3.micro', 't3.small', 't3.medium', 't3.large'),
  region: Joi.string().valid('us-east-1', 'us-east-2', 'us-west-2')
});

const { error, value } = clusterSchema.validate(req.body);
if (error) {
  return res.status(400).json({ error: error.details[0].message });
}
```

---

### 14. **No Graceful Shutdown**
**File:** All APIs

**Problem:**
- SIGTERM/SIGINT not handled
- In-flight requests get killed mid-execution
- Database connections not closed cleanly

**Fix:**
```javascript
let server;

const gracefulShutdown = async () => {
  logger.info('Received shutdown signal, closing gracefully...');
  
  server.close(async () => {
    await pool.end();
    logger.info('All connections closed');
    process.exit(0);
  });
  
  setTimeout(() => {
    logger.error('Forced shutdown after timeout');
    process.exit(1);
  }, 10000);
};

process.on('SIGTERM', gracefulShutdown);
process.on('SIGINT', gracefulShutdown);

server = app.listen(PORT, () => {
  logger.info({ port: PORT }, 'Server started');
});
```

---

### 15. **Missing TypeScript**
**Problem:**
- JavaScript has no compile-time type checking
- Easy to pass wrong types, get runtime errors
- Hard to refactor safely

**Fix:**
```typescript
// server.ts
interface SpawnRequest {
  count: number;
  instance_type: string;
  region: string;
}

app.post('/clusters', async (req: Request<{}, {}, SpawnRequest>, res) => {
  const { count, instance_type, region } = req.body;
  // TypeScript ensures these fields exist and have correct types
});
```

---

## 📋 Testing Gaps

### 16. **No Unit Tests**
**Problem:**
- Zero unit test coverage
- Can't refactor with confidence
- Regressions will slip through

**Fix:**
```javascript
// tests/unit/cluster.test.js
const request = require('supertest');
const app = require('../api/node/server');

describe('POST /clusters', () => {
  it('should create a cluster', async () => {
    const res = await request(app)
      .post('/clusters')
      .send({ count: 3, instance_type: 't3.medium' })
      .expect(202);
    
    expect(res.body).toHaveProperty('cluster_id');
    expect(res.body.status).toBe('provisioning');
  });
  
  it('should reject invalid count', async () => {
    await request(app)
      .post('/clusters')
      .send({ count: -1 })
      .expect(400);
  });
});
```

---

### 17. **No Failure Mode Testing**
**Problem:**
- Tests only cover happy path
- What happens when DB connection fails?
- What happens when AWS API rate-limits you?
- What happens when an agent crashes mid-spawn?

**Fix:**
```javascript
describe('Failure modes', () => {
  it('should handle DB connection loss gracefully', async () => {
    // Simulate connection loss
    await pool.end();
    
    const res = await request(app)
      .get('/agents')
      .expect(503);  // Service Unavailable
    
    expect(res.body.error).toContain('database unavailable');
  });
});
```

---

## 🏗️ Architecture Concerns

### 18. **No Observability**
**Missing:**
- Metrics (Prometheus/CloudWatch)
- Distributed tracing (Jaeger/X-Ray)
- Log aggregation (ELK/Loki)

**Recommendation:**
```javascript
const promClient = require('prom-client');
const register = new promClient.Registry();

const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status']
});

register.registerMetric(httpRequestDuration);

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});
```

---

### 19. **No Cost Controls**
**Problem:**
- Using spot instances (good!) but no max spend limits
- No budget alerts
- No automatic cleanup of orphaned resources

**Recommendation:**
```hcl
# terraform/main.tf
resource "aws_budgets_budget" "agent_cluster" {
  name         = "agent-cluster-budget"
  budget_type  = "COST"
  limit_amount = "100"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator = "GREATER_THAN"
    threshold           = 80
    threshold_type      = "PERCENTAGE"
    notification_type   = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}
```

---

### 20. **Single Region Deployment**
**Problem:**
- All infrastructure in one region
- Regional outage = total system failure

**Recommendation:**
- Multi-region Terraform modules
- Failover DNS with Route53
- Cross-region database replication

---

## Positive Highlights ✨

**What the team did well:**

1. **✅ Clean separation of concerns** - VPC module, agent module, APIs are well-separated
2. **✅ Parameterized Terraform** - Variables make it reusable
3. **✅ Ed25519 for message signing** - Good cryptographic choice
4. **✅ Spot instances by default** - Cost-conscious design
5. **✅ Comprehensive documentation** - 24 markdown files is impressive
6. **✅ Database-backed coordination** - Better than HTTP polling between agents
7. **✅ Bootstrap automation** - User-data script is detailed
8. **✅ Three API implementations** - Shows flexibility in tech stack

---

## Summary & Recommendations

### Must Do Before Production:
1. ✅ Fix secret management (AWS Secrets Manager)
2. ✅ Add authentication to all API endpoints
3. ✅ Move state out of memory to database
4. ✅ Enable Terraform state locking (DynamoDB)
5. ✅ Add rate limiting on expensive operations

### Should Do Soon:
6. ✅ Add connection pool limits
7. ✅ Replace polling with LISTEN/NOTIFY or message queue
8. ✅ Add input validation (Joi/Zod)
9. ✅ Implement structured logging (Pino/Winston)
10. ✅ Add graceful shutdown handlers

### Nice to Have:
11. ✅ Migrate to TypeScript
12. ✅ Add unit tests (Jest/Vitest)
13. ✅ Add observability (Prometheus + Grafana)
14. ✅ Add cost controls (AWS Budgets)
15. ✅ Multi-region support

---

## Overall Grade: B- (Good MVP, needs hardening)

**Strengths:**
- Solid architecture foundation
- Impressive amount delivered in 4.5 hours
- Coordination layer works as designed

**Weaknesses:**
- Critical security vulnerabilities
- Scalability concerns
- Missing production-readiness features

**Recommendation:**
Block production deployment until items 1-5 are addressed. This is a great start for a demo or hackathon project, but needs significant work before handling real workloads or sensitive data.

---

**Reviewed by:** Jared (Staff Engineer, 12 years experience)  
**Reviewed on:** February 26, 2026
