---
name: buildcrew-verify
description: BuildCrew Verify + Security Audit + Commit + Signal phases — final verification and commit
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task
---

# BuildCrew — Verify + Commit + Signal

`[Phases: verify, commit, signal | Input: all .claude/ artifacts, built code | Output: .claude/verify-report.md, git commit, .claude/workflow-status.json | Next: done]`

You are executing the verify, commit, and signal phases of the BuildCrew autonomous development workflow.

## Your Task

The task was provided in the prompt. All prior artifacts are available in `.claude/`.

---

## VERIFY (Blocking Gate)

**Goal**: Comprehensive verification that all quality gates pass before committing.

> **THIS PHASE IS BLOCKING** - The task cannot proceed to commit until ALL checks pass.

### Discovering What Changed

Run `git diff --name-only HEAD` to discover changed files for audit.

### Gather Evidence

Before running the checklist, gather fresh execution proof. This ensures the verify agent uses current test results — NOT stale artifacts from earlier phases.

**Step 1: Run the project's test command.** Detect by checking in order (use the first match):

1. `test.sh` in project root — if `[ -x test.sh ]`, run `./test.sh`
2. `Makefile` exists and has a test target — if `grep -q '^test[:\t ]' Makefile`, run `make test`
3. `package.json` exists and has a test script — if `grep -q '"test"' package.json`, run `npm test`
4. `pyproject.toml` exists AND `command -v pytest` succeeds — run `pytest`
5. `Cargo.toml` exists AND `command -v cargo` succeeds — run `cargo test`

If none found, note "No test runner detected" and skip test execution — do NOT fail the Test Suite check on that basis alone.

Capture full stdout+stderr from the test command. Record the exit code.

**Step 2: Capture changed files.** Run `git diff --stat HEAD` (changes are uncommitted at verify time — this shows both staged and unstaged changes relative to the last commit; evidence gathering runs BEFORE `git add`/commit).

**Step 3: Write `.claude/verify-evidence.md`** with these sections:

```markdown
## Test Output

<full stdout+stderr from test command, or "No test runner detected">

## Changed Files

<git diff --stat HEAD output, or "No changes detected">
```

**Output truncation**: if test output exceeds 500 lines, keep the first 50 lines and last 200 lines with a `... (N lines truncated) ...` marker between them. This prevents the evidence file from blowing up context windows on verbose test suites while preserving the summary/failure lines that typically appear at the end.

**If the test command exits non-zero**, the Test Suite check in the checklist below automatically fails — use the captured output as the failure reason.

`.claude/verify-evidence.md` is a transient artifact — it will be committed alongside the code changes.

### Verify Checklist

All items must be checked and pass:

#### 1. Test Suite Verification
- [ ] All tests pass — use results from Gather Evidence step above (`.claude/verify-evidence.md`), not `.claude/test-report.md`
- [ ] Coverage meets project threshold (if configured)
- [ ] No skipped tests without justification

**If tests fail**: Write phase-result.json with `blocked` verdict, `failing_check: "tests"`.

#### 2. Code Review Verification
- [ ] Code review completed (see `.claude/code-review.md`)
- [ ] No unresolved Critical issues (BLOCKING)
- [ ] No unresolved Major concerns (BLOCKING)
- [ ] Advisory findings (Minor Suggestions) are permitted — they do NOT block verification

**Note**: The gate checks for absence of unresolved blocking findings, not just an "APPROVED" verdict string. Advisory findings are acceptable.

**If blocking findings remain**: Write phase-result.json with `blocked` verdict, `failing_check: "quality"`.

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
- **Status**: [CLEAN | BLOCKED]
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

### Evidence
- **Source**: `.claude/verify-evidence.md`
- **Test Result**: [PASS | FAIL | NO TEST RUNNER]
- **Files Changed**: [count from diff stat]

---

### FINAL VERDICT: [VERIFIED | BLOCKED]

**If BLOCKED**: [Reason and required actions]
```

---

## COMMIT

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

## SIGNAL

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

## Lessons Awareness

Before finalizing, check if this task encountered any failures that were resolved:
- Review `.claude/code-review.md` and `.claude/test-report.md` for failure/retry evidence
- Check existing `.buildcrew/lessons.md` for relevance to the code being committed

If failures were resolved during this task and no lesson has been recorded for them, append a retrospective lesson to `.buildcrew/lessons.md` using this format:

---

## Lesson: [date]

**Phase**: verify
**What went wrong**: [specific description of what failed]
**What fixed it**: [specific description of what was changed]
**Rule**: [one-sentence rule to prevent this in future]
**Applies to**: [relevant phase] persona

---

**IMPORTANT**: Write any lessons to `.buildcrew/lessons.md` BEFORE writing `.claude/phase-result.json`. Writing phase-result.json triggers process termination. Any file writes after phase-result.json may be lost.

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
  "failing_check": "tests|quality|security|architecture",
  "details": "[Description of what failed]"
}
```

Then exit.
