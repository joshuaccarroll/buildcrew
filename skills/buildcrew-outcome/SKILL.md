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

> **Important**: This is NOT a test-suite pass/fail check. That happens in the verify phase. This is about exercising the feature yourself and verifying each acceptance criterion is genuinely met.

### Step 1: Read the Spec

Read `.claude/spec.md`. Extract every acceptance criterion (lines starting with `- [ ] AC-`).

If `.claude/spec.md` does not exist or has no acceptance criteria:
- Write an outcome report noting no spec was found
- Issue `verdict: "failed"` with details: "No spec or acceptance criteria found. Run the spec phase before outcome verification."

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

### Step 2.5: Integration Smoke Test

After verifying individual acceptance criteria, run a holistic "can it actually work" check.
This catches failure modes that ACs often miss because ACs test specific behaviors, not startup
and dependency integrity.

**Skip smoke tests only if ALL of the following are true for this task:**
1. No new binary, CLI command, server route, or background worker was added
2. No new environment variable or config key is consumed
3. No new external API or third-party service is called
4. The modified code paths are not callable from any existing entry point (i.e., no existing startup path, public function, or command routes through the changed code)

If any condition is false, run the applicable checks below.

**Checks (map directly to SMOKE-XX IDs):**

1. **SMOKE-01 — Startup, clean state**: Run the entry point with no config or credentials
   present. The expected result is a helpful error message, not a crash or unhandled exception.
   A startup that panics or throws on missing config is a blocker regardless of whether ACs pass.

2. **SMOKE-02 — Startup, valid config**: Run the entry point with a valid, complete config.
   Verify it initializes successfully. If startup depends on external services, also verify it
   fails gracefully when those services are unreachable (clear error, no silent hang).

3. **SMOKE-03 — End-to-end, happy path**: Trace one complete user journey from input to output
   using valid config and credentials — not just "does the function return the right value" but
   "can a user trigger this feature and get a useful result."

For dependency wiring concerns (env var documentation, config validation behavior, API error
handling) that don't fit neatly into SMOKE-01–03, add a **SMOKE-04 — Dependency wiring** check
and record it as a separate entry.

**External service handling**: If a check cannot be executed because it requires an external
service (database, third-party API, cloud provider) that is unavailable in this environment,
mark it as `SMOKE-XX: SKIPPED (requires external service: [name])`. SKIPPED entries do not
count as failures.

**Record results** as `SMOKE-XX` entries in the outcome report (alongside AC-XX entries).
Use the canonical IDs and labels defined in the test plan — these must match exactly so test and
outcome reports can be cross-referenced:
- `SMOKE-01: Startup — clean state — PASS / FAIL / SKIPPED (requires external service: X) — [notes]`
- `SMOKE-02: Startup — valid config — PASS / FAIL / SKIPPED — [notes]`
- `SMOKE-03: End-to-end — happy path — PASS / FAIL / SKIPPED — [notes]`

**Verdict impact**: A SMOKE failure is always a critical failure — issue verdict `failed`, not
`partial`. A crashed startup or unhandled exception is not a partial outcome; the feature does
not work. The `partial` verdict applies only to AC-level mismatches where the core feature
functions but specific edge-case criteria are unmet.

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

### Smoke Test Results

| ID | Check | Result | Notes |
|----|-------|--------|-------|
| SMOKE-01 | Startup — clean state | PASS / FAIL / SKIPPED (requires external service: X) | [notes] |
| SMOKE-02 | Startup — valid config | PASS / FAIL / SKIPPED | [notes] |
| SMOKE-03 | End-to-end — happy path | PASS / FAIL / SKIPPED | [notes] |

(Omit this section entirely if smoke tests were skipped — record reason in Summary)

### Summary
- **Passed**: X of Y criteria
- **Failed**: X criteria
- **Skipped**: X criteria (requires external service)
- **Smoke tests skipped**: [YES — reason | NO]

### Failures (if any)
For each failed criterion:
- **AC-XX**: [What was expected] vs [What actually happened]
  - Fix attempted: [YES — what was tried | NO — [reason not attempted]]
  - Fix result: [succeeded | failed | not attempted]

### VERDICT: [PASSED | PARTIAL | FAILED]
- PASSED: All verifiable criteria pass (skipped criteria are acceptable)
- PARTIAL: Some criteria pass, some fail (blocks commit unless --no-strict is set)
- FAILED: More than half of criteria fail, or any critical criterion fails
```

---

## Phase Result Protocol

When outcome verification is complete, write `.claude/phase-result.json` using the Write tool:

**If all verifiable criteria pass:**
```json
{
  "phase": "outcome",
  "verdict": "passed",
  "details": "All N acceptance criteria verified. Smoke tests: PASS (or SKIPPED — reason)"
}
```

**If some criteria fail (partial):**
```json
{
  "phase": "outcome",
  "verdict": "partial",
  "details": "X of N criteria passed. Failed: [AC-01: reason]. SMOKE: [SMOKE-01: result]. STRICT_MODE=[true|false]"
}
```

**If most/critical criteria fail:**
```json
{
  "phase": "outcome",
  "verdict": "failed",
  "details": "Acceptance criteria not met: [AC-01: reason]. SMOKE failures: [SMOKE-01: result]. Rebuild needed."
}
```

Writing `.claude/phase-result.json` is mandatory. Do not end your response without writing it using the Write tool.

Then exit.
