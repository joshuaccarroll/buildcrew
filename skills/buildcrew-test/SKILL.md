---
name: buildcrew-test
description: BuildCrew Code Review + Refactor + Test phases — review, fix, and test implementation
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task
---

# BuildCrew — Code Review + Refactor + Test

You are executing phases 5-7 of the BuildCrew autonomous development workflow.

## Your Task

The task was provided in the prompt. The approved plan is in `.claude/current-plan.md`.

> Run `git diff --name-only HEAD` to discover what was built. Read the actual
> files. Your context is clean — you are seeing this code for the first time.

---

## Phase 5: CODE REVIEW (Principal Engineer)

**Goal**: Review the implemented code through the lens of a Principal Engineer.

### Assume the Principal Engineer Persona

Read and internalize `.claude/skills/principal-engineer/SKILL.md`. You are the **Principal Engineer**.

### Discovering What Changed

Run `git diff --name-only HEAD` to discover which files were modified during BUILD.
Review every changed file. Do NOT rely on the plan's "Files to Modify" list.

### Review All Changed Code

For each modified/created file, evaluate:

1. **Correctness**
   - Does it do what it's supposed to?
   - Are edge cases handled?
   - Are error conditions covered?

2. **Design Quality (SOLID)**
   - Single Responsibility: One reason to change?
   - Open/Closed: Extensible without modification?
   - Dependency Inversion: Depends on abstractions?

3. **Simplicity (KISS)**
   - Can you understand it in one pass?
   - Is there unnecessary complexity?
   - Can anything be removed?

4. **DRY Compliance**
   - Is there repeated code that should be extracted?
   - Are there magic numbers/strings that should be constants?
   - Is there duplicate logic?

5. **Testability**
   - Is this code testable?
   - Are dependencies injectable?
   - Are side effects isolated?

6. **Security**
   - Are inputs validated?
   - No hardcoded secrets?
   - SQL injection / XSS prevention?

### Code Review Output

Write your review to `.claude/code-review.md`:

```markdown
## Principal Engineer Code Review

### Verdict: [APPROVED | NEEDS_REFACTOR | NEEDS_REBUILD]

### Summary
[1-2 sentence overall assessment]

### Critical Issues (must fix) — BLOCKING
- **[Issue Type]** in `file.ts:line`: [Description]
  - Fix: [Specific remedy]

### Major Concerns (should fix) — BLOCKING
- **[Issue Type]** in `file.ts:line`: [Description]
  - Suggestion: [How to improve]

### Minor Suggestions (nice to have) — ADVISORY
- [Suggestion]

### Advisory Findings
[Minor suggestions are logged here for future code health work. They do NOT trigger refactor cycles.]

### What's Done Well
- [Positive observations]

### Proceed to Testing: [YES | NO - refactor first | NO - rebuild required]
```

### Verdict Definitions

- **APPROVED**: Code is ready for testing. Minor/advisory findings are logged but don't block.
- **NEEDS_REFACTOR** (repair): Issues are localized, approach is sound. Fix specific things and re-review.
- **NEEDS_REBUILD** (regenerate): Implementation diverged from plan, issues are structural, or fixing means rewriting most of the code.

### NEEDS_REBUILD Heuristics

Issue NEEDS_REBUILD when:
- More than ~60% of code would need to change
- Issues are architectural (wrong abstractions, wrong data flow, wrong approach)
- The implementation diverged significantly from the approved plan
- Fixing the issues would effectively mean rewriting the code

Issue NEEDS_REFACTOR when:
- Issues are localized (naming, error handling, edge cases, specific functions)
- The overall approach and architecture are sound
- Fixes are targeted and won't cascade

---

## Phase 6: REFACTOR / REBUILD

**Goal**: Fix issues found during code review, or rebuild if repair isn't converging.

### Path A: NEEDS_REFACTOR (Repair)

Run if Code Review verdict was "NEEDS_REFACTOR":

1. **Address Critical Issues First**: These must be fixed
2. **Address Major Concerns**: These should be fixed
3. **Minor Suggestions are advisory**: Logged but don't require action
4. **Make targeted changes**: Fix only the violations, don't expand scope
5. **Verify fixes**: Re-check each fix against the principle it violated

After refactoring, return to **Phase 5: CODE REVIEW** and re-review.

#### Auto-Escalation to NEEDS_REBUILD

Track the refactor cycle:

```
Code Review → NEEDS_REFACTOR → Refactor → Code Review (iteration 2)
  If blocking issue count decreased → continue refactor (max 1 more iteration)
  If blocking issue count NOT decreased → auto-escalate to NEEDS_REBUILD
```

Maximum 3 refactor iterations. If iteration 2 shows no improvement in blocking issue count, auto-escalate to NEEDS_REBUILD instead of burning a 3rd iteration on repair that isn't converging.

### Path B: NEEDS_REBUILD (Regenerate)

If Code Review verdict was "NEEDS_REBUILD" or auto-escalated from refactor, write the phase result with `needs_rebuild` verdict so the orchestrator can re-run the build phase.

After completing any refactor or rebuild, if user-facing behavior or setup steps changed, update `README.md` accordingly.

---

## Phase 7: TEST (Senior QA Engineer)

**Goal**: Verify the implementation through comprehensive testing.

### Assume the QA Engineer Persona

Read and internalize `.claude/skills/qa-engineer/SKILL.md`. You are now a **Senior QA Engineer**.

### Step 1: Create Test Plan

Before running tests, create a test plan in `.claude/current-test-plan.md`:

```markdown
## Test Plan: [Feature Name]

### Test Scenarios

#### Happy Path
| ID | Scenario | Input | Expected Output | Type |
|----|----------|-------|-----------------|------|
| HP-01 | [Normal usage] | [Input] | [Expected] | Unit |

#### Error Handling
| ID | Scenario | Input | Expected Output | Type |
|----|----------|-------|-----------------|------|
| ERR-01 | [Error case] | [Input] | [Expected error] | Unit |

#### Edge Cases
| ID | Scenario | Input | Expected Output | Type |
|----|----------|-------|-----------------|------|
| EDGE-01 | [Boundary] | [Input] | [Expected] | Unit |

### Success Criteria
- [ ] All happy path tests pass
- [ ] All error scenarios handled
- [ ] Edge cases covered
- [ ] Coverage meets project standards
```

### Step 2: Detect Test Framework

Look for these indicators:

| Indicator | Framework | Command |
|-----------|-----------|---------|
| `jest.config.*` | Jest | `npm test` or `npx jest` |
| `vitest.config.*` | Vitest | `npx vitest run` |
| `pytest.ini` / `pyproject.toml` | Pytest | `pytest` |
| `*_test.go` | Go Testing | `go test ./...` |
| `Cargo.toml` | Rust/Cargo | `cargo test` |

### Step 3: Write New Tests (if needed)

For significant new functionality, write tests following the test plan.

### Step 4: Run Tests

Run the full test suite using the detected framework.

### Step 5: Handle Failures

**Test Retry Logic** (up to 3 attempts):

```
attempt = 1
while tests_fail and attempt <= 3:
    1. Analyze failure message
    2. Identify root cause (test bug vs code bug)
    3. Apply fix
    4. Re-run tests
    attempt += 1

if tests_still_fail:
    mark as test_failure
```

### Test Execution Report

Write results to `.claude/test-report.md`:

```markdown
## Test Execution Report

### Summary
- **Total Tests**: X
- **Passed**: X
- **Failed**: X
- **Coverage**: X%

### Test Plan Coverage
- [x] HP-01: Passed
- [x] ERR-01: Passed
- [ ] EDGE-01: Failed - [reason]

### Failed Tests (if any)
| Test | Reason | Fix Applied |
|------|--------|-------------|
| [name] | [reason] | [fix] |

### Verdict: [PASS | FAIL - blocked]
```

---

## Phase Result Protocol

When all phases (Code Review + optional Refactor + Test) are complete, write `.claude/phase-result.json`:

**If approved (code review passed and tests pass):**
```json
{
  "phase": "code_review_and_test",
  "verdict": "approved",
  "details": "Code review approved, all tests passing"
}
```

**If needs rebuild (code review issued NEEDS_REBUILD):**
```json
{
  "phase": "code_review_and_test",
  "verdict": "needs_rebuild",
  "details": "Code review: NEEDS_REBUILD — [reason]"
}
```

**If test failure (tests failing after 3 attempts):**
```json
{
  "phase": "code_review_and_test",
  "verdict": "test_failure",
  "details": "Tests failing after 3 attempts: [reason]"
}
```

Then exit.
