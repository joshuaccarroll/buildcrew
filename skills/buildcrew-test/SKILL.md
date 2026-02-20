---
name: buildcrew-test
description: BuildCrew Code Review + Refactor + Test phases — review, fix, and test implementation
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task
---

# BuildCrew — Code Review + Refactor + Test

`[Phases 5-7/10: CODE_REVIEW + REFACTOR + TEST | Input: built code, .claude/current-plan.md | Output: .claude/code-review.md, .claude/test-report.md | Next: VERIFY]`

You are executing phases 5-7 of the BuildCrew autonomous development workflow.

## Your Task

The task was provided in the prompt. The approved plan is in `.claude/current-plan.md`.

> Run `git diff --name-only HEAD` to discover what was built. Read the actual
> files. Your context is clean — you are seeing this code for the first time.

---

## Phase 5: CODE REVIEW (Principal Engineer — Adversarial)

**Goal**: Find the most serious flaw in this implementation. Do not look for what's good — look for what's wrong.

### Assume the Principal Engineer Persona

You are the **Principal Engineer**. Your name is going on this PR. What would you block on?

> **Adversarial mindset**: Assume something is wrong with this code. Your task is to find it. If you were a staff engineer doing this review in production, what would make you reject the PR immediately?

### Discovering What Changed

Run `git diff --name-only HEAD` to discover which files were modified during BUILD.
Review every changed file. Do NOT rely on the plan's "Files to Modify" list.

### Adversarial Code Review

For each modified/created file, interrogate:

1. **Correctness — What's broken?**
   - Where does this fail that the author didn't anticipate?
   - What edge case is not handled that a real user will hit?
   - What error condition is silently swallowed?

2. **Design Quality (SOLID) — What's the worst abstraction here?**
   - What has too many responsibilities?
   - What's hard-coded that should be injectable?
   - What change in requirements would require touching 5 files?

3. **Simplicity (KISS) — What's the most unnecessary complexity?**
   - What would you cut if you had to ship in half the time?
   - What abstractions were built for hypothetical futures?
   - Can a junior engineer understand this in one pass?

4. **DRY Compliance — What's duplicated that will drift?**
   - What repeated logic will cause a subtle bug when one copy is updated?
   - What magic numbers/strings will confuse the next person?

5. **Testability — What's hardest to test, and why?**
   - What's tightly coupled that will make tests brittle?
   - What side effects are not isolated?

6. **Security — What's the worst vulnerability here?**
   - Where are inputs not validated?
   - Any hardcoded secrets or credentials?
   - SQL injection / XSS / command injection vectors?

### Elegance Check

After identifying flaws, ask: **"Knowing what I now know about this feature, is there a fundamentally simpler approach that was missed?"**

- This is a one-time check — do not loop on this question.
- If a fundamentally simpler approach exists, flag it prominently in the review under a **"Simpler Approach Available"** section with a brief description.
- A simpler approach means fewer files, fewer abstractions, or leveraging something that already exists. Not just style preferences.
- If flagged: the review verdict should still reflect code quality, but the Build phase can optionally refactor toward the simpler approach.
- If no simpler approach is apparent, omit this section.

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

**Autonomous Error Handling during Refactor:**

When applying refactor fixes, you may encounter compilation/build errors triggered by your changes. Fix these autonomously when:
- The error is directly caused by the refactor change you just made (e.g., you renamed a function and a caller is now broken)
- The fix is in the same file or a file you already touched during this refactor
- The error is mechanical: syntax, type mismatch from rename, import update needed

Escalate if the error suggests the refactor approach itself is wrong. ONE autonomous fix attempt per error — if it fails, stop and escalate.

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

### QA Engineer Persona

You are a **Senior QA Engineer**.

Testing philosophy:
- Tests should fail meaningfully — every test must have a clear failure condition
- Tests should pass only when correct — no false positives, ever
- Test behavior, not implementation — focus on what matters, not coverage numbers
- Test pyramid: high-volume unit tests > integration tests > few critical e2e tests
- AAA pattern: Arrange, Act, Assert | tests must be isolated, repeatable, focused
- Cover: happy path + error handling + edge cases + boundary conditions

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

#### Adversarial / Unexpected Usage
| ID | Scenario | Input | Expected Output | Type |
|----|----------|-------|-----------------|------|
| ADV-01 | [Misuse/abuse] | [Input] | [Expected defense] | E2E |

### Success Criteria
- [ ] All happy path tests pass
- [ ] All error scenarios handled
- [ ] Edge cases covered
- [ ] Coverage meets project standards
- [ ] Adversarial scenarios tested
- [ ] Experience harness updated and passing
```

After writing the test plan, run iterative sub-agent review on `.claude/current-test-plan.md`:

```
iteration = 0
while iteration < 5:
    Spawn a Task sub-agent (general-purpose type) with this prompt:

    "Read .claude/current-test-plan.md. Review it critically as if you are seeing it for the first time.
    Look for: gaps, missing details, unclear sections, over-engineering, incorrect assumptions,
    missing edge cases, and areas that could be improved.

    Make concrete improvements directly to the file. Be specific and substantive --
    do not add filler or unnecessary content.

    If the document is solid and no meaningful improvements can be made,
    respond with exactly: CONVERGED

    Do not explain what you reviewed. Either improve the file or respond CONVERGED."

    if sub-agent output contains "CONVERGED":
        break
    iteration += 1
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
| `*.bats` | Bats | `bats <test-dir>` |

### Step 2.5: Check Team Test Norms
If `.buildcrew/norms/testing.md` exists, read it. Follow the team's test conventions for file location, naming, mocking patterns, and assertion style. This takes precedence over the general conventions in this skill.

### Step 3: Create or Update Experience Testing Harness

The experience harness is a **persistent test file** in the project's test directory that simulates actual end-user interaction. Unlike unit tests, it exercises the system the way a real user would. It is cumulative -- each task extends it, existing scenarios are never removed unless the current task intentionally changes the tested behavior.

#### Harness Location Convention

| Project Type | Harness File | Tool |
|--------------|-------------|------|
| CLI / Shell  | `tests/e2e/experience.bats` or `tests/e2e/experience.test.ts` | Direct command execution |
| Web App      | `tests/e2e/experience.spec.ts` | Playwright / Cypress |
| API          | `tests/e2e/experience.test.ts` | HTTP client (fetch/axios) |
| Library      | `tests/e2e/experience.test.ts` | Import and call public API |

**Directory creation**: Create the harness inside whatever test directory the project already uses (`tests/`, `test/`, `spec/`, `__tests__/`, etc.), adding an `e2e/` subdirectory within it. Only create `tests/e2e/` if there is no existing test directory.

**Running the harness**: The harness may use a different tool than the unit test framework (e.g., Playwright for E2E vs. Jest for units). Detect the harness runner from the harness file extension and imports, not from the unit test framework detection. Run unit tests and harness tests as separate commands if needed. If the harness runner is not installed, install it as a dev dependency. If installation fails, fall back to the project's existing test runner and adjust the harness file format accordingly.

#### Before creating: Check for existing E2E tests

If the project already has E2E tests (e.g., `tests/e2e/workflow.bats`), check whether an `experience.*` file exists. If so, use it as the harness. Do not create a parallel file.

#### If the harness does not exist: Create it

1. **Happy path walkthrough**: A complete user journey from start to finish
2. **Error recovery path**: Trigger a common error, verify the message is helpful, recover
3. **Adversarial scenario**: At least one test that deliberately misuses the tool (wrong types, conflicting flags, absurd input, out-of-order operations)

#### If the harness exists: Extend it

1. **Add scenarios** covering new functionality from the current task
2. **Keep existing scenarios** -- never remove passing tests unless the current task intentionally changes the tested behavior. In that case, update the scenario to match the new behavior and note the change in a comment.
3. **Add one new adversarial scenario** relevant to the current change
4. **Run the full harness** to verify existing scenarios still pass (regression check)

**Harness size management**: If the harness exceeds ~50 scenarios, organize into logical groups using `describe` blocks or test sections. Do not split into multiple files -- the single-file convention is important for discoverability. If harness run time becomes a bottleneck (significantly longer than the unit test suite), note the slowest scenarios in the test report and consider whether any can be made faster without reducing coverage.

#### Adversarial Scenario Design

Generate adversarial tests by asking:
- What if the user provides the **wrong type** of input?
- What if the user runs this **out of sequence** or skips required steps?
- What if the user provides **absurdly large, empty, or malformed** data?
- What if the operation encounters **invalid state mid-way** (file deleted during processing, dependency unavailable, input stream closes early)?
- What if the user has **conflicting configuration** or environment state?

Each adversarial test must assert a **specific, graceful outcome** -- not just "doesn't crash" but "shows error message X" or "exits with code Y".

### Step 4: Write New Tests (if needed)

For significant new functionality, write tests following the test plan.

### Step 5: Run Tests

Run the full test suite using the detected framework.

### Step 6: Handle Failures

**Test Retry Logic** (up to 3 attempts):

```
attempt = 1
while tests_fail and attempt <= 3:
    1. Analyze failure message
    2. Classify:
       a. Harness failure (real bug) -> fix application code
       b. Harness failure (intentional change) -> update harness scenario
       c. Harness failure (test bug: wrong assertion, stale fixture) -> fix harness test
       d. Unit/integration test bug -> fix test code
       e. Code bug caught by unit/integration test -> fix application code
    3. Apply fix
    4. Re-run ALL tests (including harness)
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

### Experience Harness
- **Harness File**: [path]
- **Status**: [CREATED | EXTENDED | EXISTING (unchanged)]
- **Scenarios Run**: X passed / Y total
- **New Scenarios Added**: X
- **Adversarial Scenarios**: X
- **Bugs Found & Auto-Fixed**: [list or "None"]

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
