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

**Goal**: Comprehensive verification that all quality gates pass before committing. This phase combines security audit, test suite verification, and acceptance criteria verification into a single parallel pass.

> **THIS PHASE IS BLOCKING** - The task cannot proceed to commit until ALL checks pass.

### Discovering What Changed

Run all commands from the project root directory.
Run `git diff --name-only HEAD` to discover changed files for audit.

### Parallel Verification (3 simultaneous sub-agents)

In a **single response**, spawn all 3 Task sub-agents simultaneously:

#### Sub-Agent 1 — Security Audit

Spawn a Task sub-agent **(general-purpose type)** with this prompt:

```
You are a Security Engineer performing a comprehensive security audit.

Run `git diff --name-only HEAD` to discover changed files.

Security principles: Never hardcode secrets | always validate external inputs at boundaries | escape user data in outputs (XSS) | use parameterized queries (SQL injection) | never expose stack traces to users | sanitize file paths | never trust client-side validation alone.

OWASP Top 10 scan focus: broken access control (IDOR, CORS, privilege escalation) | cryptographic failures (weak algorithms, plaintext secrets) | injection (SQL, NoSQL, command, XSS, template) | insecure design | security misconfiguration (default creds, debug mode, missing headers) | vulnerable dependencies (CVEs) | auth failures | data integrity | logging gaps | SSRF.

Secrets detection patterns: AWS keys (AKIA...), API keys, private keys (BEGIN...PRIVATE KEY), database URLs, JWT tokens. Check .env files, config files, test files, docs.

Write findings to `.claude/security-audit.md` with sections for each OWASP category checked and a final PASS/FAIL verdict.
```

#### Sub-Agent 2 — Test Suite

Spawn a Task sub-agent **(general-purpose type)** with this prompt:

```
You are a QA Engineer running the full test suite for final verification.

Detect and run the test suite.

First, check `.claude/precompute/test-runner.md` for a pre-detected test runner. If present and contains a framework and command, use that command directly.

If the precompute file is missing, evaluate the following test runner detection list in order. Use the first match:

1. test -x test.sh → Run: ./test.sh
2. test -f Makefile && grep -q '^test[: \t]' Makefile → Run: make test
3. test -f package.json && grep -q '"test"' package.json → Run: npm test
4. test -f pyproject.toml && command -v pytest >/dev/null → Run: pytest
5. test -f Cargo.toml && command -v cargo >/dev/null → Run: cargo test

Execute with stderr redirected into stdout: output=$(<command> 2>&1); rc=$?

If no test runner is detected, write "No test runner detected".

Write results to `.claude/verify-evidence.md` with:
## Test Output
<captured test stdout+stderr>

## Changed Files
<output of: git diff --stat HEAD>

If test output exceeds 500 lines, keep first 50 and last 200 lines, replacing omitted middle with: ... (N lines truncated) ...
```

#### Sub-Agent 3 — AC Verification

Spawn a Task sub-agent **(general-purpose type)** with this prompt:

```
You are a QA Engineer performing acceptance criteria cross-referencing.

BATCH MODE CHECK: If `.claude/batch-combined-context.md` exists, read it for acceptance criteria (spec.md may not exist when plan-skip was used). Extract AC-XX lines from whichever source is available.

SEQUENTIAL MODE: Read `.claude/spec.md`. Extract every acceptance criterion (lines starting with `- [ ] AC-`).

If no spec, batch context, or acceptance criteria are found: write outcome-report.md noting this and mark as SKIPPED.

1. Read the AC source identified above. Extract every AC-XX identifier.
2. Read `.claude/tdd-manifest.json`. Extract the `ac_coverage` mapping.
3. Read `.claude/verify-evidence.md` (written by sub-agent 2). This contains raw test output (stdout+stderr), not structured results.

Validation checks:
- If `tdd-manifest.json` does not exist: verdict is SKIPPED with reason "no TDD manifest (TDD not applicable or scaffold was skipped)." Write outcome-report.md with this status and exit.
- If `verify-evidence.md` does not exist or contains no test output: verdict is FAIL with reason "missing test evidence from sub-agent 2."
- If `tdd-manifest.json` exists but `ac_coverage` is missing or empty: verdict is FAIL with reason "manifest has no AC coverage data."

Cross-reference:
- Normalize AC identifiers for comparison (case-insensitive, strip leading zeros: AC-1 matches AC-01, strip underscores/spaces so AC_01 also matches). Normalize BOTH the spec-extracted IDs and the manifest keys before comparing. Only the `AC-XX` format (with hyphen) is canonical; normalization is a robustness measure.
- For each AC-XX in the spec, confirm there is at least one mapped test in ac_coverage.
- Read the `framework` field from `tdd-manifest.json` to determine the output format. Use framework-specific pass indicators: "ok" for bats/TAP, "PASS" for jest/vitest, "PASSED" for pytest, "ok" for cargo test, "ok"/"PASS" for go test. For each mapped test, search the raw test output in verify-evidence.md for evidence that it passed (test function name near a pass indicator). If the overall test suite exited with rc=0 (check for "All N tests passed", "Tests: X passed", or similar summary line with zero failures), treat all tests as passing.
- If any AC has no mapped test: flag as UNCOVERED.
- If any mapped test has no passing evidence in the output: flag as FAILING.

Write results to `.claude/outcome-report.md`:
- List each AC, its mapped tests, and status (one per line)
- End with verdict: PASS (all ACs covered and passing), FAIL (any UNCOVERED or FAILING), or SKIPPED (no manifest or no ACs found)
```

### After All Sub-Agents Complete

Read the outputs from all 3 sub-agents:
- `.claude/security-audit.md`
- `.claude/verify-evidence.md`
- `.claude/outcome-report.md`

### Inline Code Quality Review

After reading sub-agent outputs, perform an inline architecture and code quality review:

1. Run `git diff HEAD` to see the full diff
2. Check: changes align with existing architecture, no circular dependencies, no breaking changes to public APIs
3. Check: code review findings from `.claude/code-review.md` (if it exists) — verify no unresolved Critical or Major issues remain
4. In **batch mode**: this review covers the codereview gap (batch workers skip codereview). Review the combined diff for design quality, correctness, and simplicity.

### Verify Checklist

All items must be checked and pass:

#### 1. Test Suite Verification
- [ ] All tests pass — use results from `.claude/verify-evidence.md`
- [ ] Coverage meets project threshold (if configured)
- [ ] No skipped tests without justification

**If tests fail**: Write phase-result.json with `blocked` verdict, `failing_check: "tests"`.

#### 2. Code Review Verification
- [ ] No unresolved Critical issues (BLOCKING)
- [ ] No unresolved Major concerns (BLOCKING)
- [ ] Advisory findings (Minor Suggestions) are permitted — they do NOT block verification

**If blocking findings remain**: Write phase-result.json with `blocked` verdict, `failing_check: "quality"`.

#### 3. Security Audit
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

#### 5. Acceptance Criteria Verification
- [ ] All ACs have mapped passing tests per cross-reference report in .claude/outcome-report.md (or SKIPPED if no TDD manifest)

**If AC verification FAILS (UNCOVERED or FAILING ACs)**: Write phase-result.json with `blocked` verdict, `failing_check: "acceptance"`.
**If AC verification is SKIPPED**: Checklist item passes — do not write a blocked verdict.

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

### Acceptance Criteria
- **Status**: [PASS | FAIL | SKIPPED]
- **Covered & Passing**: X of Y criteria
- **Uncovered**: X criteria
- **Failing**: X criteria
- **Skipped**: X criteria

### Evidence
- **Source**: `.claude/verify-evidence.md`
- **Test Result**: [PASS | FAIL | NO RUNNER]
- **Changed Files**: [N files changed — from last line of git diff --stat, or "No changes detected"]

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
    "acceptance_criteria": true,
    "verify": true
  }
}
```

---

## Lessons Awareness

Before finalizing, check if this task encountered any failures that were resolved:
- Review `.claude/verify-report.md` and `.claude/code-review.md` for failure/retry evidence
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

