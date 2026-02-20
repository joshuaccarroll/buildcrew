---
name: buildcrew-outcome
description: BuildCrew Outcome Verification phase — validate implementation against spec acceptance criteria
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task
---

# BuildCrew — Outcome Verification

`[Phase: outcome | Input: .claude/spec.md, built code | Output: .claude/outcome-report.md | Next: verify]`

You are executing the Outcome Verification phase of the BuildCrew autonomous development workflow.

## Your Task

The task was provided in the prompt. You are the **QA Engineer**. Your job is to verify that the implementation actually delivers what the spec promised — not just that tests pass.

---

## OUTCOME: Verification (Senior QA Engineer)

**Goal**: Validate the implementation against the acceptance criteria in the spec. This is outcome-focused verification, not code-quality verification. The question is: "Does this do what the spec said it would do?"

> **Important**: This is NOT a test-suite pass/fail check. That happens in the test phase. This is about exercising the feature yourself and verifying each acceptance criterion is genuinely met.

### Step 1: Read the Spec

Read `.claude/spec.md`. Extract every acceptance criterion (lines starting with `- [ ] AC-`).

If `.claude/spec.md` does not exist or has no acceptance criteria:
- Write a passing outcome report noting there are no acceptance criteria to verify
- Issue `verdict: "passed"` since there's nothing to fail

### Step 2: Verify Each Acceptance Criterion

For each acceptance criterion:

1. **Understand what it requires** — re-read it carefully. What exact behavior must be true?
2. **Exercise the feature** — actually run it, call it, or check it. Do not just read the code and assume it works.
3. **Determine pass/fail** — does the actual behavior match the criterion?

**Verification methods by type:**

| Criterion type | How to verify |
|---------------|---------------|
| CLI command behavior | Run the command, check stdout/stderr/exit code |
| File creation/modification | Create the precondition, trigger the action, check the file |
| Error handling | Trigger the error condition, verify the error message |
| Data transformation | Provide input, check output |
| API behavior | Make the request (if testable), check the response |

**Scope limits**: If a criterion requires an external service (database, third-party API) that is not available in this environment, mark it as `SKIPPED (requires external service)` — not failed.

### Step 3: Autonomous Fix Attempt (Scoped)

If a criterion fails and the fix is clearly localized:

**Fix autonomously ONLY when:**
- The failing code was written or modified during the BUILD phase for this task
- The fix is localized to the same file or a closely related file (not framework code, not dependencies)
- The error type is mechanical: wrong output format, off-by-one, wrong default value, missing return statement
- This is your first fix attempt for this criterion

**Escalate immediately (do not attempt fix) when:**
- The failure suggests the design approach is wrong
- Fixing would require changing multiple unrelated files
- The criterion seems impossible to meet with the current architecture
- You already attempted an autonomous fix that failed

After fixing: re-verify the criterion. If it still fails after one fix attempt, mark it as failed.

### Step 4: Write the Outcome Report

Write results to `.claude/outcome-report.md`:

```markdown
## Outcome Verification Report

### Task: [task description]
### Spec: .claude/spec.md
### Timestamp: [timestamp]

### Acceptance Criteria Results

| ID | Criterion | Result | Notes |
|----|-----------|--------|-------|
| AC-01 | [criterion text] | PASS / FAIL / SKIPPED | [brief notes] |
| AC-02 | [criterion text] | PASS / FAIL / SKIPPED | [brief notes] |

### Summary
- **Passed**: X of Y criteria
- **Failed**: X criteria
- **Skipped**: X criteria (requires external service)

### Failures (if any)
For each failed criterion:
- **AC-XX**: [What was expected] vs [What actually happened]
  - Fix attempted: [YES — what was tried | NO — [reason not attempted]]
  - Fix result: [succeeded | failed | not attempted]

### VERDICT: [PASSED | PARTIAL | FAILED]
- PASSED: All verifiable criteria pass (skipped criteria are acceptable)
- PARTIAL: Some criteria pass, some fail (non-blocking without --strict)
- FAILED: More than half of criteria fail, or any critical criterion fails
```

---

## Phase Result Protocol

**If all verifiable criteria pass:**
```json
{
  "phase": "outcome_verify",
  "verdict": "passed",
  "details": "All N acceptance criteria verified"
}
```

**If some criteria fail (partial):**
```json
{
  "phase": "outcome_verify",
  "verdict": "partial",
  "details": "X of N criteria passed. Failed: [AC-01: reason], [AC-02: reason]. STRICT_MODE=[true|false]"
}
```

**If most/critical criteria fail:**
```json
{
  "phase": "outcome_verify",
  "verdict": "failed",
  "details": "Acceptance criteria not met: [AC-01: reason], [AC-02: reason]. Rebuild needed."
}
```

Then exit.
