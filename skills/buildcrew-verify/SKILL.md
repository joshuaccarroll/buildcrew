---
name: buildcrew-verify
description: BuildCrew Verify + Security Audit + Commit + Signal phases — final verification and commit
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task
---

# BuildCrew — Verify + Commit + Signal

`[Phases 8-10/10: VERIFY + COMMIT + SIGNAL | Input: all .claude/ artifacts, built code | Output: .claude/verify-report.md, git commit, .claude/workflow-status.json | Next: done]`

You are executing phases 8-10 of the BuildCrew autonomous development workflow.

## Your Task

The task was provided in the prompt. All prior artifacts are available in `.claude/`.

---

## Phase 8: VERIFY (Blocking Gate)

**Goal**: Comprehensive verification that all quality gates pass before committing.

> **THIS PHASE IS BLOCKING** - The task cannot proceed to commit until ALL checks pass.

### Discovering What Changed

Run `git diff --name-only HEAD` to discover changed files for audit.

### Verify Checklist

All items must be checked and pass:

#### 1. Test Suite Verification
- [ ] All tests pass (zero failures)
- [ ] Coverage meets project threshold (if configured)
- [ ] No skipped tests without justification

**If tests fail**: Write phase-result.json with `blocked` verdict, `failing_check: "tests"`.

#### 2. Code Review Verification
- [ ] Code review completed (see `.claude/code-review.md`)
- [ ] No unresolved Critical issues (BLOCKING)
- [ ] No unresolved Major concerns (BLOCKING)
- [ ] Advisory findings (Minor Suggestions) are permitted — they do NOT block verification
- [ ] If `.buildcrew/norms/NORMS.md` exists, spot-check that new code follows established norms. Flag norms deviations as Minor Suggestions (advisory, not blocking).

**Note**: The gate checks for absence of unresolved blocking findings, not just an "APPROVED" verdict string. Advisory findings are acceptable.

**If blocking findings remain**: Write phase-result.json with `blocked` verdict, `failing_check: "code_review"`.

#### 3. Security Audit (Security Engineer)

Invoke the **Security Engineer** persona for a comprehensive security audit.

Security principles: Never hardcode secrets | always validate external inputs at boundaries | escape user data in outputs (XSS) | use parameterized queries (SQL injection) | never expose stack traces to users | sanitize file paths | never trust client-side validation alone.

OWASP Top 10 scan focus: broken access control (IDOR, CORS, privilege escalation) | cryptographic failures (weak algorithms, plaintext secrets) | injection (SQL, NoSQL, command, XSS, template) | insecure design | security misconfiguration (default creds, debug mode, missing headers) | vulnerable dependencies (CVEs) | auth failures | data integrity | logging gaps | SSRF.

Secrets detection patterns: AWS keys (AKIA...), API keys, private keys (BEGIN...PRIVATE KEY), database URLs, JWT tokens. Check .env files, config files, test files, docs.

Write findings to `.claude/security-audit.md`.

**Security checks include:**
- OWASP Top 10 vulnerability scan
- Secrets detection (API keys, passwords, tokens)
- Input validation review
- Output encoding verification
- Dependency vulnerability audit

**Blocking criteria:**
- [ ] No CRITICAL vulnerabilities
- [ ] No HIGH vulnerabilities (unless explicitly accepted with justification)
- [ ] No hardcoded secrets
- [ ] Dependencies audit clean (no critical CVEs)

**If security issues found**: Write phase-result.json with `blocked` verdict, `failing_check: "security"`.

#### 4. Architecture Validation
- [ ] Changes align with existing architecture
- [ ] No circular dependencies introduced
- [ ] No breaking changes to public APIs (unless intended)
- [ ] Documentation updated if public interfaces changed

**If architecture issues found**: Write phase-result.json with `blocked` verdict, `failing_check: "architecture"`.

### Verify Report

Write verification status to `.claude/verify-report.md`:

```markdown
## Verification Report

### Date: [timestamp]
### Task: [task description]

### Test Suite
- **Status**: [PASS | FAIL]
- **Tests Run**: X
- **Tests Passed**: X
- **Tests Failed**: X
- **Coverage**: X%

### Code Review
- **Status**: [APPROVED | NEEDS_REFACTOR | NEEDS_REBUILD]
- **Reviewer**: Principal Engineer
- **Critical Issues**: X (fixed: Y)
- **Major Concerns**: X (fixed: Y)

### Security Audit
- **Status**: [PASS | FAIL]
- **Critical Vulnerabilities**: X
- **High Vulnerabilities**: X
- **Secrets Found**: [YES | NO]
- **Dependency Issues**: X

### Architecture
- **Status**: [VALID | INVALID]
- **Notes**: [Any architectural concerns]

---

### FINAL VERDICT: [VERIFIED | BLOCKED]

**If BLOCKED**: [Reason and required actions]
```

---

## Phase 9: COMMIT

**Goal**: Create a meaningful commit with all changes.

### Steps:

1. **Stage changes**: `git add` all relevant files
2. **Generate commit message**: Use conventional commit format

```
type(scope): brief description

- Detail 1
- Detail 2

Task: [original task description]
```

3. **Create commit**: Do NOT push (local only)
4. **Do not create, switch, or delete git branches**. The orchestrator manages branching. Commit to the current branch.

### Commit Types:
- `feat`: New feature
- `fix`: Bug fix
- `refactor`: Code restructuring
- `test`: Adding tests
- `docs`: Documentation changes
- `style`: Formatting, whitespace
- `chore`: Maintenance tasks

---

## Phase 10: SIGNAL COMPLETION

**Goal**: Signal to the orchestrator that this task is complete.

### Write Status File

Create `.claude/workflow-status.json`:

**On Success:**
```json
{
  "status": "complete",
  "task": "[original task]",
  "summary": "[brief summary of what was done]",
  "files_changed": ["list", "of", "files"],
  "commit": "[commit hash if available]",
  "reviews_passed": {
    "plan_review": true,
    "code_review": true,
    "tests": true,
    "security_audit": true,
    "verify": true
  }
}
```

---

## Phase Result Protocol

When all verification, commit, and signal phases are complete, write `.claude/phase-result.json`:

**If everything passed and committed:**
```json
{
  "phase": "verify_and_commit",
  "verdict": "complete",
  "details": "All checks passed, committed successfully"
}
```

**If blocked:**
```json
{
  "phase": "verify_and_commit",
  "verdict": "blocked",
  "failing_check": "tests|code_review|security|architecture",
  "details": "[Description of what failed]"
}
```

Then exit.
