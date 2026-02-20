# BuildCrew Default Workflow

This is the default workflow for BuildCrew. Projects can customize this by creating `.buildcrew/workflow.md`.

---

## Phases

### SPEC (optional)
**agent**: product-manager
**description**: Convert raw backlog item into a structured specification with testable acceptance criteria
**output**: .claude/spec.md
**skip**: `buildcrew run --skip-spec`

The Product Manager:
1. Assesses whether the task is specific enough to produce clear acceptance criteria
2. If too vague: flags the issue in spec.md and marks the task blocked
3. If sufficient: writes a spec with "What It Does", "Done from User Perspective", "Out of Scope", and testable acceptance criteria
4. Spawns a QA-lens sub-agent review to validate criteria are genuinely testable

---

### RESEARCH
**agent**: none
**description**: Gather external and local context relevant to the task before planning
**output**: .claude/research.md

Steps:
1. Parse the task to identify research topics (APIs, libraries, patterns, integrations)
2. Assess research depth (light for internal tasks, full for external dependencies)
3. Search the web for relevant documentation and best practices (if full research)
4. Fetch and summarize key pages (3-5 max)
5. Explore local codebase for existing patterns and dependencies
6. Write consolidated findings to .claude/research.md

---

### PLAN
**agent**: none
**description**: Analyze task, explore codebase, create implementation plan
**input**: .claude/research.md, .claude/spec.md (if present)
**output**: .claude/current-plan.md

Steps:
1. Load research findings from .claude/research.md
2. Read spec acceptance criteria from .claude/spec.md (if present)
3. Explore the codebase to understand existing patterns
4. Create a detailed implementation plan incorporating research context
5. Write plan to .claude/current-plan.md

---

### PLAN-REVIEW (Adversarial 3-Pass)
**agents**: principal-engineer, product-manager
**description**: Adversarial 3-pass review — find the most serious flaw in the plan
**input**: .claude/current-plan.md, .claude/spec.md (if present), .buildcrew/context/* (if present)
**output**: .claude/plan-review.md
**gate**: overall verdict == "APPROVED"
**circuit breaker**: 2 consecutive needs_revision → re-plan from scratch

Three sequential adversarial review passes:
- **Pass 1 — Technical Challenge (Principal Engineer)**: "Find the most serious flaw. What would you block on?"
- **Pass 2 — User Impact Challenge (Product Manager)**: "Where does this plan fail the user? What acceptance criteria are missing?"
- **Pass 3 — Convergence (Principal Engineer)**: "Is this the right approach, or just an approach?"

Per-pass verdicts: PASS or NEEDS_REVISION
Pass 3 verdict: APPROVED, NEEDS_REVISION, or REJECTED

If NEEDS_REVISION: Revise plan and re-enter review cycle (max 3 cycles)
If circuit breaker (2 consecutive failures): Re-plan from scratch with failure context
If REJECTED: Mark task as blocked

---

### BUILD
**agent**: feature-engineer
**description**: Implement the plan with focus on user value
**input**: .claude/current-plan.md
**autonomous error handling**: fix localized mechanical errors directly (one attempt) before escalating

The Feature Engineer:
1. Follows the approved plan
2. Implements incrementally
3. Follows existing patterns
4. Writes clean, readable code
5. Attempts autonomous fixes for localized mechanical errors (syntax, types, imports)

---

### CODE-REVIEW (Adversarial)
**agent**: principal-engineer
**description**: Adversarial code review — find the most serious flaw in the implementation
**output**: .claude/code-review.md
**gate**: no unresolved Critical or Major findings
**elegance check**: "Is there a fundamentally simpler approach that was missed?"
**autonomous error handling**: fix localized mechanical errors from refactor directly (one attempt)

The Principal Engineer:
- "Your name is on this PR. What would you block on?"
- Reviews correctness, design, simplicity, DRY, testability, security
- After finding flaws: asks if there's a fundamentally simpler approach (one-time elegance check)
- Flags simpler approach if found (doesn't trigger a new review cycle, just informs build)

Verdicts: APPROVED, NEEDS_REFACTOR, or NEEDS_REBUILD
- If NEEDS_REFACTOR: Continue to refactor + re-review (max 3 cycles)
- If NEEDS_REBUILD: Return to build with rejection context
- If APPROVED: Proceed to test

---

### REFACTOR / REBUILD
**agent**: none
**condition**: code_review.verdict == "NEEDS_REFACTOR" or "NEEDS_REBUILD"
**description**: Address issues from code review, or rebuild if repair isn't converging

**NEEDS_REFACTOR**: Fix blocking issues, return to code-review. Max 3 refactor cycles.
Auto-escalation: if iteration 2 shows no improvement in blocking issue count → NEEDS_REBUILD.

**NEEDS_REBUILD**: Discard implementation, preserve approved plan, restart build with rejection context.
**circuit breaker**: if build/test fails 2 consecutive times → re-plan from scratch

---

### TEST
**agent**: qa-engineer
**description**: Create test plan, write tests, run test suite
**output**: .claude/test-report.md
**circuit breaker**: 2 consecutive test_failure → re-plan from scratch

The QA Engineer:
1. Creates test plan for the implementation
2. Writes tests (unit, integration as needed)
3. Creates/extends the cumulative experience harness
4. Runs the test suite
5. Attempts autonomous fixes for localized test failures (one attempt) before escalating

---

### OUTCOME (optional, requires spec)
**agent**: qa-engineer
**description**: Validate each acceptance criterion from the spec against the actual implementation
**input**: .claude/spec.md (acceptance criteria), built code
**output**: .claude/outcome-report.md
**gate**: all verifiable criteria pass (STRICT_MODE) or warn on partial (default)
**circuit breaker**: 2 consecutive outcome failures → re-plan from scratch

Note: This phase only runs if `.claude/spec.md` exists (i.e., spec phase was not skipped).

The QA Engineer:
1. Reads each acceptance criterion from the spec
2. Exercises the feature against each criterion (runs it, checks output, tests edge cases)
3. Not just "do tests pass" but "does this do what the spec said it would do"
4. Produces a pass/fail report keyed to each acceptance criterion
5. Attempts autonomous fix for mechanically failing criteria (one attempt)

On failure: loops back to build with specific failing criteria feedback.

**--strict mode** (`buildcrew run --strict`): ALL criteria must pass before commit is allowed.
Without `--strict`: warn but allow commit with unmet criteria.

---

### VERIFY
**agent**: security-engineer
**description**: Security audit and final verification
**output**: .claude/security-audit.md
**gate**: all_checks_pass
**circuit breaker**: 2 consecutive blocked → re-plan from scratch

**BLOCKING GATE** - All checks must pass:
- [ ] All tests pass
- [ ] No unresolved Critical or Major code review findings (advisory/Minor findings permitted)
- [ ] No critical/high security vulnerabilities
- [ ] No hardcoded secrets

If any check fails: Return to build with findings

---

### COMMIT
**agent**: none
**description**: Create git commit for the changes

Create a conventional commit:
- Summarize the changes
- Reference the task
- Do NOT push (commits stay local)

---

### SIGNAL
**agent**: none
**description**: Write completion status for orchestrator
**output**: .claude/workflow-status.json

---

## Circuit Breaker

When any phase fails its quality gate **twice consecutively**:
1. BuildCrew stops the current phase
2. Appends a lesson to `.buildcrew/lessons.md`
3. Outputs: `[CIRCUIT BREAKER] Approach failed twice at <phase>. Re-planning from scratch with failure context.`
4. Restarts from research + plan with failure summary as context
5. The re-plan gets ONE attempt. If it also hits the circuit breaker, the task is marked blocked.

---

## Lessons System

After any failed iteration, BuildCrew automatically appends a lesson to `.buildcrew/lessons.md`:
- What went wrong (specific failure)
- What fixed it (resolution)
- A rule to prevent it next time
- Which persona/phase it applies to

Lessons are injected into every phase's context (like `users.md` or `principles.md`).
Cap: 100 entries. When exceeded, oldest 50 are condensed into a "Patterns" summary.

```bash
buildcrew lessons              # List all lessons
buildcrew lessons promote N    # Graduate lesson N to .buildcrew/rules/project-rules.md
buildcrew lessons prune        # Interactively remove stale lessons
```

---

## Customization

To customize this workflow for your project:

1. Create `.buildcrew/workflow.md` in your project
2. Define your phases using the same format
3. You can:
   - Remove phases (e.g., skip SPEC with `--skip-spec` or skip PLAN_REVIEW for speed)
   - Add phases (e.g., add DEPLOY after COMMIT)
   - Change agents assigned to phases
   - Modify gate conditions

### Example: Minimal Workflow

```markdown
## Phases

### BUILD
agent: feature-engineer
description: Build the feature

### TEST
agent: qa-engineer
description: Test it

### COMMIT
agent: none
description: Commit changes
```
