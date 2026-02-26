# Security Policy

## Overview

This document outlines the security posture of the agent-infra project and provides a roadmap for production hardening.

**Current Status:** 🟡 **PROTOTYPE / PROOF OF CONCEPT**

**Production Readiness:** ❌ **NOT PRODUCTION READY**

---

## Known Security Issues

**⚠️ DO NOT USE WITH REAL AWS CREDENTIALS UNTIL CRITICAL ISSUES ARE RESOLVED ⚠️**

See GitHub Issues tagged with `security` and `critical` for tracked vulnerabilities.

### Critical Issues (Block Production)

1. **No API Authentication** ([#9](https://github.com/jeancloud007/agent-infra/issues/9))
   - All API endpoints are publicly accessible
   - Anyone can spawn/terminate agents
   - **Impact:** Unauthorized access, cost attacks, data breaches

2. **Secrets Exposed in EC2 User-Data** ([#10](https://github.com/jeancloud007/agent-infra/issues/10))
   - Ed25519 private keys embedded in user-data
   - Database credentials visible in EC2 console
   - **Impact:** Complete system compromise

3. **Shell Injection Vulnerability** ([#11](https://github.com/jeancloud007/agent-infra/issues/11))
   - Agent names not sanitized in bootstrap script
   - Allows arbitrary command execution
   - **Impact:** Remote code execution on EC2 instances

4. **No Input Validation** ([#1](https://github.com/jeancloud007/agent-infra/issues/1))
   - API accepts unbounded values
   - Can spawn unlimited resources
   - **Impact:** Cost attacks, resource exhaustion

5. **CORS Misconfiguration** ([#4](https://github.com/jeancloud007/agent-infra/issues/4))
   - `app.use(cors())` allows all origins
   - **Impact:** Cross-site request forgery

---

## Security Hardening Roadmap

### Phase 1: Critical Security Fixes (Week 1)

**Timeline:** 2-3 days  
**Goal:** Block catastrophic security holes

**Tasks:**
- [ ] Add API authentication (API keys minimum, OAuth preferred)
- [ ] Move secrets to AWS Secrets Manager
- [ ] Sanitize all shell inputs in bootstrap scripts
- [ ] Add input validation with schemas (Joi/Zod)
- [ ] Fix CORS to whitelist allowed origins
- [ ] Implement cost controls (max agent count validation)
- [ ] Add AWS Budget alerts

**Definition of Done:**
- All critical GitHub issues resolved
- Security team sign-off on authentication mechanism
- Penetration test passes on auth layer

---

### Phase 2: Defense in Depth (Week 2-3)

**Timeline:** 1 week  
**Goal:** Add multiple layers of security

**Tasks:**
- [ ] Add rate limiting on expensive operations
- [ ] Implement request logging and audit trail
- [ ] Add IAM roles for agent EC2 instances
- [ ] Enable encryption at rest (RDS, S3)
- [ ] Enable encryption in transit (TLS everywhere)
- [ ] Add AWS WAF rules for common attacks
- [ ] Implement principle of least privilege (IAM policies)
- [ ] Add security group egress filtering

**Definition of Done:**
- No secrets in code, logs, or metadata
- All network traffic encrypted
- IAM policies follow least-privilege
- CloudTrail logging enabled

---

### Phase 3: Security Operations (Week 4-6)

**Timeline:** 2-3 weeks  
**Goal:** Operational security maturity

**Tasks:**
- [ ] Set up CloudWatch alarms for suspicious activity
- [ ] Implement automated secret rotation
- [ ] Add intrusion detection (GuardDuty)
- [ ] Create incident response runbook
- [ ] Set up vulnerability scanning (Snyk/Dependabot)
- [ ] Add container security scanning (if using Docker)
- [ ] Implement backup and disaster recovery
- [ ] Create security documentation and threat model

**Definition of Done:**
- Security team can detect and respond to incidents
- Secrets rotate automatically
- Recovery procedures tested
- Threat model documented

---

## Threat Model

### Assets to Protect

1. **AWS Account** - Prevent unauthorized EC2 spawning
2. **Database** - Contains agent keys, messages, cluster state
3. **Agent Private Keys** - Ed25519 keys for message signing
4. **Source Code** - Intellectual property
5. **Customer Data** - If agents process sensitive information

### Attack Vectors

**External Attackers:**
- Exploit unauthenticated APIs to spawn resources
- Inject shell commands via unsanitized inputs
- Extract secrets from EC2 metadata
- CORS attacks from malicious websites
- DDoS attacks on API endpoints

**Insider Threats:**
- Developers with access to AWS console
- Compromised CI/CD pipeline
- Social engineering for credentials

**Supply Chain:**
- Compromised npm/pip packages
- Malicious Terraform modules
- Backdoored AMIs

### Trust Boundaries

1. **Public Internet ↔ API Gateway** - Authentication required
2. **API Gateway ↔ Internal Services** - TLS + IAM
3. **EC2 Instances ↔ Database** - Encrypted connections
4. **Agents ↔ Agents** - Signed messages (Ed25519)

---

## Security Best Practices

### For Developers

**DO:**
- ✅ Use parameterized SQL queries
- ✅ Validate all user inputs
- ✅ Store secrets in AWS Secrets Manager
- ✅ Enable MFA on AWS accounts
- ✅ Use least-privilege IAM policies
- ✅ Keep dependencies up to date
- ✅ Review security scan results

**DON'T:**
- ❌ Hardcode credentials in code
- ❌ Use `shell=True` in subprocess calls
- ❌ Trust user input
- ❌ Disable SSL/TLS verification
- ❌ Use wildcard CORS origins
- ❌ Commit secrets to git
- ❌ Use root user for AWS operations

### For Operators

**DO:**
- ✅ Enable CloudTrail logging
- ✅ Set up CloudWatch alarms
- ✅ Use AWS Config for compliance
- ✅ Enable AWS GuardDuty
- ✅ Rotate credentials regularly
- ✅ Test disaster recovery procedures
- ✅ Keep AMIs up to date with security patches

**DON'T:**
- ❌ Share AWS credentials
- ❌ Disable security features "to make it work"
- ❌ Ignore CloudWatch alarms
- ❌ Run with overly permissive security groups
- ❌ Skip security updates

---

## Credential Management

### Current State (INSECURE)

- ❌ Secrets in EC2 user-data
- ❌ Database credentials in environment variables
- ❌ Ed25519 keys generated on-instance
- ❌ No rotation policy

### Target State (SECURE)

- ✅ Secrets stored in AWS Secrets Manager
- ✅ IAM roles for service-to-service auth
- ✅ Automatic credential rotation (30-90 days)
- ✅ Audit log of all secret accesses
- ✅ Encrypted at rest and in transit

### Implementation

```bash
# Store secret
aws secretsmanager create-secret \
  --name agent-infra/db-credentials \
  --secret-string '{"username":"admin","password":"..."}' \
  --kms-key-id alias/agent-infra

# Retrieve in application
import boto3
client = boto3.client('secretsmanager')
response = client.get_secret_value(SecretId='agent-infra/db-credentials')
creds = json.loads(response['SecretString'])
```

---

## Incident Response

### Detection

**Indicators of Compromise:**
- Unusual spike in EC2 instance count
- Unauthorized API calls in CloudTrail
- Failed authentication attempts
- GuardDuty findings
- Unexpected AWS charges

### Response Procedure

1. **Contain**
   - Disable compromised IAM credentials
   - Isolate affected EC2 instances (security group changes)
   - Block suspicious IP addresses at WAF/security group

2. **Investigate**
   - Review CloudTrail logs
   - Check CloudWatch metrics
   - Examine EC2 instance logs
   - Identify attack vector

3. **Remediate**
   - Terminate compromised instances
   - Rotate all credentials
   - Patch vulnerability
   - Update security rules

4. **Recover**
   - Restore from backups if needed
   - Validate system integrity
   - Resume normal operations

5. **Document**
   - Write incident report
   - Update runbooks
   - Implement preventive measures

---

## Security Contact

**For security issues, please contact:**

- **Email:** [REDACTED] (Patrick to provide)
- **PGP Key:** [REDACTED]
- **Response SLA:** 24 hours for critical, 72 hours for non-critical

**Do NOT file GitHub issues for security vulnerabilities.** Use private disclosure.

---

## Compliance

### Current Compliance Status

- ❌ SOC 2 - Not compliant
- ❌ HIPAA - Not compliant
- ❌ PCI-DSS - Not compliant
- ❌ GDPR - Needs data protection impact assessment

### Path to Compliance

**SOC 2 Type II (6-12 months):**
1. Implement security controls
2. Document policies and procedures
3. Conduct audit readiness assessment
4. Engage auditing firm
5. Complete 3-6 month observation period

---

## Security Scanning

### Recommended Tools

**Static Analysis:**
- Snyk (npm/Python dependencies)
- Bandit (Python security linter)
- ESLint security plugins (JavaScript)
- tfsec (Terraform scanning)

**Dynamic Analysis:**
- OWASP ZAP (API penetration testing)
- Burp Suite (manual security testing)
- AWS Inspector (EC2 vulnerability scanning)

**Infrastructure:**
- Checkov (IaC security scanning)
- Prowler (AWS security audit)
- ScoutSuite (multi-cloud security audit)

---

## Version History

- **v0.1.0** (2026-02-26) - Initial security policy
  - Documented known critical vulnerabilities
  - Created hardening roadmap
  - Defined threat model

---

**Status:** 🔴 **CRITICAL SECURITY ISSUES UNRESOLVED**

**Do not deploy to production until Phase 1 hardening is complete.**

**Last Updated:** February 26, 2026  
**Next Review:** After Phase 1 completion
