# Security Engineer Rules

Rules for security audits, vulnerability detection, and secure development.

> "Security is not a feature. It's a foundation."

---

## Security is Blocking

Security issues are **blocking** - no exceptions.

- **Never** hardcode secrets, API keys, or passwords
- **Always** validate external inputs at system boundaries
- **Always** escape user data in outputs (XSS prevention)
- **Always** use parameterized queries for databases (SQL injection)
- **Never** expose stack traces or internal errors to users
- **Always** sanitize file paths
- **Never** trust client-side validation alone
- **Always** use HTTPS for sensitive data

---

## OWASP Top 10 (2021) Checklist

### A01: Broken Access Control
- Authorization checks on all protected routes
- Proper role-based access control (RBAC)
- No IDOR vulnerabilities (Insecure Direct Object References)
- Rate limiting on sensitive endpoints
- CORS properly configured
- No privilege escalation paths

### A02: Cryptographic Failures
- No sensitive data in logs
- Encryption at rest for PII
- TLS for data in transit
- Proper key management
- No weak algorithms (MD5, SHA1 for security purposes)
- Passwords hashed with bcrypt/argon2 (not SHA/MD5)

### A03: Injection
- Parameterized queries (no SQL injection)
- NoSQL injection protection
- Command injection prevention
- XSS prevention (output encoding)
- Template injection prevention

### A04: Insecure Design
- Threat modeling performed
- Security requirements documented
- Defense in depth applied
- Principle of least privilege followed
- Fail-secure defaults

### A05: Security Misconfiguration
- No default credentials
- Error handling doesn't leak info
- Security headers configured (CSP, HSTS, X-Frame-Options)
- Unnecessary features disabled
- Dependencies up to date
- Debug mode disabled in production

### A06: Vulnerable and Outdated Components
- Dependencies audited
- No known CVEs in dependencies
- Regular dependency updates scheduled

### A07: Identification and Authentication Failures
- Strong password requirements enforced
- Account lockout mechanism
- Secure password storage (bcrypt, argon2)
- Session management secure
- Session timeout implemented

### A08: Software and Data Integrity Failures
- CI/CD pipeline secure
- Dependencies from trusted sources
- Integrity verification on updates
- No deserialization of untrusted data

### A09: Security Logging and Monitoring Failures
- Authentication events logged
- Authorization failures logged
- Input validation failures logged
- Logs protected from tampering
- No sensitive data in logs

### A10: Server-Side Request Forgery (SSRF)
- URL validation on server-side requests
- Allowlist for external services
- No raw URL forwarding from user input

---

## Secrets Detection Patterns

### Patterns to Search For
```regex
# AWS Keys
AKIA[0-9A-Z]{16}

# Generic API Keys
[aA][pP][iI][_-]?[kK][eE][yY].*['"][0-9a-zA-Z]{32,}['"]

# Private Keys
-----BEGIN (RSA|DSA|EC|OPENSSH) PRIVATE KEY-----

# Database URLs
(mongodb|postgres|mysql|redis):\/\/[^\s]+

# JWT Tokens
eyJ[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+
```

### Files to Check
- `.env*` files (should be gitignored)
- Configuration files
- Test files (often contain real credentials)
- Documentation (sometimes contains examples with real values)

---

## Input Validation

### All User Inputs Must Be Validated
- Type checking (string, number, boolean)
- Length limits
- Format validation (email, URL, etc.)
- Allowlist validation preferred over denylist
- Validation on server-side (never trust client)

### File Uploads
- File type validation (magic bytes, not just extension)
- File size limits
- Filename sanitization
- Storage outside web root
- Virus scanning for uploaded files

### Output Encoding
- HTML encoding for DOM insertion
- URL encoding for query parameters
- JavaScript encoding for script contexts
- SQL parameterization (not encoding)

---

## Blocking Criteria

The verify phase **FAILS** if:
- Any **CRITICAL** vulnerabilities found
- Any **HIGH** vulnerabilities found (unless explicitly accepted)
- Hardcoded secrets detected
- Critical dependency vulnerabilities present

---

## Audit Report Format

```markdown
# Security Audit Report

## Executive Summary
- **Audit Date**: [timestamp]
- **Scope**: [what was reviewed]
- **Overall Risk Level**: [CRITICAL | HIGH | MEDIUM | LOW]
- **Vulnerabilities Found**: X critical, Y high, Z medium
- **Immediate Action Required**: [YES | NO]

## Critical Vulnerabilities (Must Fix Before Deploy)

| ID | Category | Location | Description | Remediation |
|----|----------|----------|-------------|-------------|
| SEC-001 | [Category] | `file:line` | [Description] | [Fix] |

## Secrets Scan Results
- [ ] No hardcoded secrets found
- [ ] .env files properly gitignored

## Dependency Audit Results
**Vulnerabilities**: X critical, Y high, Z medium
```
