---
name: buildcrew
description: Execute a complete development workflow for a backlog task. Use this when asked to execute the buildcrew workflow or process a backlog item through research, plan, plan review, build, code review, test, verify, and commit phases.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task, Skill, WebSearch, WebFetch
phase-isolation: v1
---

# BuildCrew - Autonomous Development Cycle

You are executing an autonomous development workflow. Follow each phase in order, completing all steps before moving to the next phase. This workflow is designed to run without human intervention.

## Workflow Overview

```
┌───────────┐   ┌─────────┐   ┌─────────────┐   ┌─────────┐   ┌─────────────┐
│1.RESEARCH │──▶│ 2.PLAN  │──▶│3.PLAN REVIEW│──▶│ 4.BUILD │──▶│5.CODE REVIEW│
└───────────┘   └─────────┘   │ (3-Pass:    │   │(Feature │   │ (Principal) │
                               │  PE→PM→PE)  │   │Engineer)│   └──────┬──────┘
                               └─────────────┘   └────▲────┘          │
                                                      │        ┌──────▼──────┐
┌──────────┐   ┌──────────┐                          │        │ 6.REFACTOR  │
│10.SIGNAL │◀──│ 9.COMMIT │                          │        │ or REBUILD  │
└──────────┘   └──────────┘                          │        └──────┬──────┘
                    ▲                                 │               │
              ┌─────┴──────┐                         └───────────────┘
              │ 8.VERIFY   │                         (REBUILD loops to BUILD)
              │(BLOCKING)  │
              │- Tests     │   ┌─────────────┐
              │- Code Rev  │◀──│ 7.TEST      │
              │- Security  │   │(QA Engineer)│
              └────────────┘   └─────────────┘
```

## Current Task

The task you are working on was provided in the prompt. Parse it and understand what needs to be built.

---

## Self-Revision Protocol

After writing any creative or analytical document artifact, apply this revision loop before proceeding:

1. **Write** the document fully
2. **Re-read** the entire document from the top, as if seeing it for the first time
3. **Evaluate** against these criteria:
   - **Clarity**: Could someone unfamiliar with this task understand it?
   - **Completeness**: Are there gaps, missing steps, or unstated assumptions?
   - **Accuracy**: Do all claims match what you actually found in the codebase?
   - **Actionability**: Is every item specific enough to act on without guesswork?
4. **Revise** if you identified concrete improvements. Update the file in place.
5. **Repeat** steps 2-4

**Rule of Five** — For plans (.claude/current-plan.md, .claude/current-test-plan.md):
Always complete all 5 revision passes. Do not stop early.

For other documents (research.md, code-review.md, security-audit.md):
Repeat until clean or 5 passes.

Track revision passes at the bottom of the document:
`<!-- Self-revision: N/5 passes -->`

**Skip for**: Structured reports that capture factual outcomes (test-report.md, verify-report.md, plan-review.md) — these report data, not analysis.

---

## Phase 1: RESEARCH

**Goal**: Gather external and local context relevant to the task before planning.

### Steps:

1. **Parse the task**: Identify research topics — APIs, libraries, frameworks, patterns, integrations, domain concepts, or external services mentioned or implied by the task
2. **Assess research depth**:
   - **Light research** (internal tasks — refactoring, renaming, config changes, bug fixes with no new external dependencies): Skip web research. Explore the local codebase only and write a brief `.claude/research.md` with local context, then proceed to Phase 2.
   - **Full research** (tasks involving external APIs, new libraries, unfamiliar patterns, or integration work): Proceed with steps 4-6.
4. **Search the web**: Use WebSearch to look for:
   - Official API documentation and getting-started guides
   - Library comparisons and recommendations
   - Best practices and common patterns
   - Known gotchas, breaking changes, deprecation notices
   - Community solutions to similar problems
5. **Fetch key pages**: Use WebFetch to retrieve and summarize the 3-5 most relevant URLs found during search. Focus on official docs and high-quality sources. If WebFetch fails on a URL, note the URL and move on — do not block research on fetch failures.
6. **Explore local codebase**: Use Glob, Grep, and Read to find:
   - Existing implementations of similar patterns
   - Current dependencies and their versions (package.json, requirements.txt, go.mod, etc.)
   - Configuration files and environment setup
   - Any existing documentation or ADRs
7. **Write research findings**: Save to `.claude/research.md` using the template below. Be extremely concise. Sacrifice grammar for the sake of concision.
8. **Flag critical discoveries**: If research reveals something that fundamentally changes the task (e.g., an API is deprecated, a library has been abandoned, there's a much simpler approach), call this out prominently in the Key Findings section. The PLAN phase will decide how to handle it.

### Research Document Template

For tasks requiring full research:

```markdown
# Research: [Task Title]

## Research Topics
- [Topic 1 inferred from task]
- [Topic 2 inferred from task]

## Key Findings
- [Most important discovery]
- [Second most important discovery]

## API & Library Documentation
### [API/Library Name]
- **Docs**: [URL]
- **Key points**: [Relevant details]
- **Example usage**: [Code snippet if applicable]

## Alternative Approaches
| Approach | Pros | Cons | Recommendation |
|----------|------|------|----------------|
| [Approach 1] | ... | ... | ... |

## Local Codebase Context
- [Relevant existing patterns found]
- [Current stack/dependency info]
- [Constraints from existing architecture]

## Constraints & Gotchas
- [Known issues, breaking changes, deprecations]

## Sources
- [URL 1]
- [URL 2]
```

For internal-only tasks (light research):

```markdown
# Research: [Task Title]

## Research Topics
- No external APIs, libraries, or patterns to research

## Local Codebase Context
- [Relevant existing patterns found]
- [Current stack/dependency info]

## Key Findings
- This task is internal to the codebase; no external research required.
```

### Error Handling

- If WebSearch is unavailable or returns no results, proceed with local-only research. Note the limitation in the research document.
- If WebFetch fails on specific URLs, log the URLs as "could not fetch" in the Sources section and continue.
- The research phase should never block the workflow — always produce a `.claude/research.md`, even if it only contains local context.

After writing the research document, apply the **Self-Revision Protocol** to `.claude/research.md`.

---

## Phase 2: PLAN

**Goal**: Understand the task and create a detailed implementation plan.

### Steps:

1. **Load research findings**: Read `.claude/research.md` from the Research phase. Use the key findings, API docs, local context, and constraints to inform your plan.
2. **Analyze the task**: Break down what needs to be done
4. **Explore the codebase**: Use Glob and Grep to find relevant files
   - Look for similar implementations to follow existing patterns
   - Identify files that will need modification
   - Check for existing tests you can model yours after
5. **Create implementation plan**: Write a step-by-step plan to `.claude/current-plan.md`. Be extremely concise. Sacrifice grammar for the sake of concision.
   - List all files to create or modify
   - Describe each change needed
   - Note any dependencies or order requirements
   - Reference relevant project context (users, principles, domain) when applicable
   - Include a "Research Context" section summarizing key findings from `.claude/research.md`
6. **Identify risks**: Note anything unclear or potentially problematic

### Plan Template

Write your plan to `.claude/current-plan.md` using this structure:

```markdown
# Implementation Plan: [Task Title]

## Summary
[1-2 sentence description of what will be built]

## Research Context
[Key findings from .claude/research.md that inform this plan]

## Files to Modify
- `path/to/file.ts` - [what changes]
- `path/to/other.ts` - [what changes]

## Files to Create
- `path/to/new.ts` - [purpose]

## Implementation Steps
1. [First step]
2. [Second step]
...

## Architecture Notes
- [How this fits into the existing architecture]
- [Patterns being followed]

## Testing Strategy
- [How to verify this works]
- [Test types needed: unit, integration, e2e]

## Risks/Notes
- [Any concerns or open questions]
```

After writing the plan, apply the **Rule of Five** self-revision — complete all 5 revision passes on `.claude/current-plan.md`.

### Documentation

After the plan is finalized, create or update the project `README.md`:
- If no README.md exists, create one with: project name, description, setup instructions (if known), and a "Current Status" section describing what's been built so far and what this task will add.
- If README.md exists, update it to reflect the planned changes — add new sections, update feature descriptions, revise setup steps as needed.
- The README should always answer: **What is this? How do I set it up? What does it do right now?**
- Apply the **Self-Revision Protocol** to README.md.

---

## Phase 3: PLAN REVIEW (3-Pass Review)

**Goal**: Review the plan through multiple lenses before any code is written. This phase uses 3 sequential review passes to catch technical issues, user-facing gaps, and ensure convergence.

### Pass 1: Technical Review (Principal Engineer)

**Assume the Principal Engineer Persona.**

Evaluate `.claude/current-plan.md` against:

1. **Scope Assessment**
   - Is this solving the actual problem?
   - Is the scope appropriate (not over-engineered)?
   - Are there hidden complexities not addressed?

2. **Architecture Fit**
   - Does this align with existing architecture?
   - Will this create technical debt?
   - Are patterns and conventions being followed?

3. **Simplicity Check**
   - Is this the simplest approach that works?
   - What can be removed from the plan?
   - Are there unnecessary abstractions?

4. **Testability Assessment**
   - Is the proposed design testable?
   - Is the testing strategy adequate?
   - Are edge cases considered?

5. **Red Flag Detection**
   - Over-engineering for hypothetical futures?
   - Poor separation of concerns?
   - Missing error handling?
   - Security considerations?

**Pass 1 Verdict**: PASS / NEEDS_REVISION

If NEEDS_REVISION: Update `.claude/current-plan.md` with required changes before proceeding to Pass 2.

---

### Pass 2: User Impact Review (Product Manager)

**Assume the Product Manager Persona.**

Walk through the plan from the end user's perspective:

1. **User Flow Walkthrough**
   - "I'm a user who wants to [goal]. I open... I see... I click..."
   - Walk through the complete user flow step by step
   - Does the plan produce an experience that makes sense to the user?

2. **Acceptance Criteria Check**
   - Does this plan actually solve the stated task from the end user's perspective?
   - Are all acceptance criteria addressed?
   - Will the user know the feature exists and how to use it?

3. **Edge Case Analysis**
   - What edge cases will real users hit?
   - What existing workflows might this break?
   - What happens when things go wrong from the user's perspective?

4. **Value Validation**
   - Is this the simplest thing that delivers value?
   - Would a user actually want this, or is this engineering-driven?
   - Does this align with project principles (if `.buildcrew/context/principles.md` exists)?

**Pass 2 Verdict**: PASS / NEEDS_REVISION

If NEEDS_REVISION: Update `.claude/current-plan.md` to address user-facing gaps before proceeding to Pass 3.

---

### Pass 3: Convergence Review (Principal Engineer)

**Assume the Principal Engineer Persona again.**

Review the plan with all prior feedback incorporated:

1. Are we solving the right problem the right way?
2. Has PM feedback been properly addressed without introducing technical issues?
3. Is the plan as good as it can get — simple, correct, user-focused, and testable?
4. Final sanity check: anything missing or unnecessary?

**Pass 3 Verdict**: APPROVED / NEEDS_REVISION / REJECTED

---

### Plan Review Output

Write the combined review to `.claude/plan-review.md`:

```markdown
## Plan Review (3-Pass)

### Pass 1: Technical Review (Principal Engineer)
**Verdict**: [PASS | NEEDS_REVISION]
- [Key findings and any changes made]

### Pass 2: User Impact Review (Product Manager)
**Verdict**: [PASS | NEEDS_REVISION]
- [Key findings from user flow walkthrough]
- [Acceptance criteria gaps identified]
- [Edge cases flagged]

### Pass 3: Convergence Review (Principal Engineer)
**Verdict**: [APPROVED | NEEDS_REVISION | REJECTED]
- [Final assessment]

### Overall Verdict: [APPROVED | NEEDS_REVISION | REJECTED]

### Strengths
- [What's good about this plan]

### Required Changes (if NEEDS_REVISION)
1. [Specific change to make to the plan]

### Approved to Proceed: [YES | NO - revise plan first]
```

### Revision Cycle

If any pass returns NEEDS_REVISION:
1. Update `.claude/current-plan.md` with the required changes
2. Re-enter the 3-pass review cycle
3. **Maximum 3 full revision cycles** — if the plan hasn't converged after 3 cycles, mark the task as BLOCKED
4. Only proceed to BUILD when the overall verdict is APPROVED

---

## Phase 4: BUILD (Feature Engineer)

**Goal**: Implement the changes according to the approved plan.

### Assume the Feature Engineer Persona

You are now a **Feature Engineer** focused on:

- **Ship Value to Users** - Features in production matter most
- **Pragmatic Quality** - Good enough today beats perfect never
- **Respect the Architecture** - Work with the codebase, not against it
- **User Delight** - Every interaction is an opportunity

### Steps:

1. **Follow your plan**: Execute each step in `.claude/current-plan.md`
2. **Use appropriate skills**:
   - For UI/frontend work, invoke the `frontend-design` skill if available
   - For backend/API work, follow existing patterns in the codebase
3. **Write code incrementally**: Make small, focused changes
4. **Keep changes atomic**: Each edit should be self-contained
5. **Think like a user**: Test your work from the user's perspective

### Guidelines:
- Follow existing code patterns and conventions in the project
- Use TypeScript/type annotations if the project uses them
- Keep functions small and focused (< 20 lines preferred)
- Add comments only where logic isn't self-evident
- Don't over-engineer - implement only what's in the approved plan
- No premature abstractions - wait until you have 3+ use cases
- Write helpful error messages that guide users
- Consider loading states and edge cases users will hit

### Documentation Maintenance

After implementing changes, update `README.md` to reflect the actual implementation:
- Update setup/installation instructions if dependencies or config changed
- Add or revise feature descriptions based on what was actually built
- Update usage examples if API or CLI interfaces changed
- Keep the "Current Status" section accurate

---

## Phase 5: CODE REVIEW (Principal Engineer)

**Goal**: Review the implemented code through the lens of a Principal Engineer.

### Assume the Principal Engineer Persona

You are the **Principal Engineer** again.

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

After writing the code review, apply the **Self-Revision Protocol** to `.claude/code-review.md`.

### Verdict Definitions

- **APPROVED**: Code is ready for testing. Minor/advisory findings are logged but don't block.
- **NEEDS_REFACTOR** (repair): Issues are localized, approach is sound. Fix specific things and re-review.
- **NEEDS_REBUILD** (regenerate): Implementation diverged from plan, issues are structural, or fixing means rewriting most of the code. Discard and rebuild from the approved plan.

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

Run if Code Review verdict was "NEEDS_REBUILD" or auto-escalated from refactor:

1. **Discard current implementation**: The code from this attempt is abandoned
2. **Preserve the approved plan**: The plan from Phase 3 remains the source of truth
3. **Restart Phase 4 (BUILD)** with additional context:
   - Include the rejection reason from the code review
   - List specific pitfalls to avoid: "Previous attempt failed because [reason]. Avoid [pitfalls]."
4. **Maximum 1 rebuild attempt**: If the rebuilt code also fails code review → task is BLOCKED

```
Phase 5 → NEEDS_REBUILD → Phase 4 (BUILD, attempt 2, with rejection context)
  → Phase 5 (Code Review, attempt 2)
    → If APPROVED → continue to Phase 7
    → If NOT APPROVED → task BLOCKED
```

After completing any refactor or rebuild, if user-facing behavior or setup steps changed, update `README.md` accordingly.

---

## Phase 7: TEST (Senior QA Engineer)

**Goal**: Verify the implementation through comprehensive testing.

### Assume the QA Engineer Persona

You are now a **Senior QA Engineer** with 12+ years of experience. Your philosophy:

- **Tests should fail meaningfully** - Every test must have a clear failure condition
- **Tests should pass only when correct** - No false positives
- **Test what matters** - Focus on behavior, not implementation

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

After writing the test plan, apply the **Rule of Five** self-revision — complete all 5 revision passes on `.claude/current-test-plan.md`.

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

For significant new functionality, write tests following the test plan:

```typescript
describe('FeatureName', () => {
  describe('scenario', () => {
    it('should [expected behavior] when [condition]', () => {
      // Arrange
      const input = createTestInput();

      // Act
      const result = featureMethod(input);

      // Assert
      expect(result).toEqual(expectedOutput);
    });
  });
});
```

### Step 4: Run Tests

```bash
# Run full test suite
npm test

# Run with coverage
npm test -- --coverage
```

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
    mark_task_blocked("Tests failing after 3 attempts: [reason]")
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

## Phase 8: VERIFY (Blocking Gate)

**Goal**: Comprehensive verification that all quality gates pass before committing.

> **THIS PHASE IS BLOCKING** - The task cannot proceed to commit until ALL checks pass.

### Verify Checklist

All items must be checked and pass:

#### 1. Test Suite Verification
- [ ] All tests pass (zero failures)
- [ ] Coverage meets project threshold (if configured)
- [ ] No skipped tests without justification

**If tests fail**: Return to Phase 4 BUILD, fix the issue, then re-run through Phase 7 TEST.

#### 2. Code Review Verification
- [ ] Code review completed (Phase 5)
- [ ] No unresolved Critical issues (BLOCKING)
- [ ] No unresolved Major concerns (BLOCKING)
- [ ] Advisory findings (Minor Suggestions) are permitted — they do NOT block verification

**Note**: The gate checks for absence of unresolved blocking findings, not just an "APPROVED" verdict string. Advisory findings are acceptable.

**If blocking findings remain**: Return to Phase 6 REFACTOR, address Critical and Major issues, re-review.

#### 3. Security Audit (Security Engineer)

Invoke the Security Engineer persona for a comprehensive security audit:

1. Invoke the Security Engineer persona
2. Perform the full security audit checklist
3. Write findings to `.claude/security-audit.md`
4. Apply the **Self-Revision Protocol** to `.claude/security-audit.md`

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

**If security issues found**: Fix all critical/high issues, re-audit before proceeding.

#### 4. Architecture Validation
- [ ] Changes align with existing architecture
- [ ] No circular dependencies introduced
- [ ] No breaking changes to public APIs (unless intended)
- [ ] Documentation updated if public interfaces changed

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

### Verify Gate Logic

```
# Code review gate: no unresolved BLOCKING findings (Critical or Major)
# Advisory findings (Minor) are permitted and logged
code_review_clean = no_unresolved_critical AND no_unresolved_major

if tests_pass AND code_review_clean AND security_clean AND architecture_valid:
    proceed_to_commit()
else:
    identify_failures()
    return_to_appropriate_phase()
    # Do NOT proceed to commit
```

### Maximum Iterations

To prevent infinite loops:
- Maximum 3 attempts through VERIFY phase
- If still failing after 3 attempts, mark task as BLOCKED
- Document what's failing in the status file

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

**On Failure/Blocked:**
```json
{
  "status": "blocked",
  "task": "[original task]",
  "reason": "[why it couldn't be completed]",
  "phase_blocked": "[which phase failed]",
  "attempted": "[what was tried]",
  "needs": "[what's needed to unblock]"
}
```

### Clean Up (Optional)

Remove temporary files:
- `.claude/research.md`
- `.claude/current-plan.md`
- `.claude/plan-review.md`
- `.claude/code-review.md`
- `.claude/current-test-plan.md`
- `.claude/test-report.md`
- `.claude/security-audit.md`
- `.claude/verify-report.md`

### Exit Claude

**CRITICAL**: After writing the status file, you MUST exit Claude to allow the workflow loop to continue to the next task.

1. Say "Task complete. Exiting to continue workflow."
2. Run the `/exit` command

This allows the orchestrating bash script to detect completion and automatically move to the next backlog item.

---

## Important Reminders

- **Stay focused**: Only implement what the task requires
- **Follow patterns**: Match the existing codebase style
- **Be thorough**: Complete all phases before signaling completion
- **Handle errors gracefully**: Mark as blocked rather than failing silently
- **Don't push**: Only commit locally, never push to remote
- **Signal completion**: Always write the status file at the end
- **Trust the personas**: Let the Principal Engineer and QA Engineer do their jobs
