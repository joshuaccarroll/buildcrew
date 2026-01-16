---
name: buildcrew
description: Execute a complete development workflow for a backlog task. Use this when asked to execute the buildcrew workflow or process a backlog item through plan, plan review, build, code review, test, verify, and commit phases.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task, Skill
---

# BuildCrew - Autonomous Development Cycle

You are executing an autonomous development workflow. Follow each phase in order, completing all steps before moving to the next phase. This workflow is designed to run without human intervention.

## Workflow Overview

```
┌─────────┐   ┌─────────────┐   ┌─────────┐   ┌─────────────┐
│ 1.PLAN  │──▶│2.PLAN REVIEW│──▶│ 3.BUILD │──▶│4.CODE REVIEW│
└─────────┘   │ (Principal) │   │(Feature │   │ (Principal) │
              └─────────────┘   │Engineer)│   └─────────────┘
                                └─────────┘          │
┌──────────┐   ┌──────────┐   ┌────────────┐   ┌─────────────┐
│ 9.SIGNAL │◀──│ 8.COMMIT │◀──│ 7.VERIFY   │◀──│ 6.TEST      │
└──────────┘   └──────────┘   │(BLOCKING)  │   │(QA Engineer)│
                              │- Tests     │   └─────────────┘
                              │- Code Rev  │         ▲
                              │- Security  │   ┌─────────────┐
                              └────────────┘   │ 5.REFACTOR  │
                                               │ (if needed) │
                                               └─────────────┘
```

## Current Task

The task you are working on was provided in the prompt. Parse it and understand what needs to be built.

---

## Phase 1: PLAN

**Goal**: Understand the task and create a detailed implementation plan.

### Steps:

1. **Analyze the task**: Break down what needs to be done
2. **Explore the codebase**: Use Glob and Grep to find relevant files
   - Look for similar implementations to follow existing patterns
   - Identify files that will need modification
   - Check for existing tests you can model yours after
3. **Create implementation plan**: Write a step-by-step plan to `.claude/current-plan.md`
   - List all files to create or modify
   - Describe each change needed
   - Note any dependencies or order requirements
4. **Identify risks**: Note anything unclear or potentially problematic

### Plan Template

Write your plan to `.claude/current-plan.md` using this structure:

```markdown
# Implementation Plan: [Task Title]

## Summary
[1-2 sentence description of what will be built]

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

---

## Phase 2: PLAN REVIEW (Principal Engineer)

**Goal**: Review the plan through the lens of a Principal Engineer before any code is written.

### Assume the Principal Engineer Persona

Read and internalize `.claude/skills/principal-engineer/SKILL.md`. You are now a **Principal Engineer** with 15+ years of experience. You hold these values:

- **Simplicity above all** - Is this the simplest approach?
- **Readability is paramount** - Will this be maintainable?
- **Modularity enables evolution** - Are concerns properly separated?
- **Testability is non-negotiable** - Can this be tested effectively?

### Review the Plan

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

### Plan Review Output

Write your review to `.claude/plan-review.md`:

```markdown
## Principal Engineer Plan Review

### Verdict: [APPROVED | NEEDS REVISION]

### Assessment
[2-3 sentence summary of the plan quality]

### Strengths
- [What's good about this plan]

### Concerns (if NEEDS REVISION)
- [Issue]: [Specific fix required]

### Required Changes (if any)
1. [Specific change to make to the plan]
2. [Specific change to make to the plan]

### Approved to Proceed: [YES | NO - revise plan first]
```

### If Plan Needs Revision

1. Update `.claude/current-plan.md` with the required changes
2. Re-review until the plan is APPROVED
3. Only proceed to BUILD when verdict is APPROVED

---

## Phase 3: BUILD (Feature Engineer)

**Goal**: Implement the changes according to the approved plan.

### Assume the Feature Engineer Persona

Read and internalize `.claude/skills/feature-engineer/SKILL.md`. You are now a **Feature Engineer** focused on:

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

---

## Phase 4: CODE REVIEW (Principal Engineer)

**Goal**: Review the implemented code through the lens of a Principal Engineer.

### Assume the Principal Engineer Persona

Read and internalize `.claude/skills/principal-engineer/SKILL.md`. You are the **Principal Engineer** again.

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

### Verdict: [APPROVED | NEEDS REFACTOR]

### Summary
[1-2 sentence overall assessment]

### Critical Issues (must fix)
- **[Issue Type]** in `file.ts:line`: [Description]
  - Fix: [Specific remedy]

### Major Concerns (should fix)
- **[Issue Type]** in `file.ts:line`: [Description]
  - Suggestion: [How to improve]

### Minor Suggestions (nice to have)
- [Suggestion]

### What's Done Well
- [Positive observations]

### Proceed to Testing: [YES | NO - refactor first]
```

---

## Phase 5: REFACTOR

**Goal**: Fix any issues found during code review.

### When to Run This Phase

- Run if Code Review verdict was "NEEDS REFACTOR"
- Skip if verdict was "APPROVED"

### Steps:

1. **Address Critical Issues First**: These must be fixed
2. **Address Major Concerns**: These should be fixed
3. **Consider Minor Suggestions**: Fix if quick and clear benefit
4. **Make targeted changes**: Fix only the violations, don't expand scope
5. **Verify fixes**: Re-check each fix against the principle it violated

### After Refactoring

Return to **Phase 4: CODE REVIEW** and re-review the changes until the verdict is APPROVED.

---

## Phase 6: TEST (Senior QA Engineer)

**Goal**: Verify the implementation through comprehensive testing.

### Assume the QA Engineer Persona

Read and internalize `.claude/skills/qa-engineer/SKILL.md`. You are now a **Senior QA Engineer** with 12+ years of experience. Your philosophy:

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

## Phase 7: VERIFY (Blocking Gate)

**Goal**: Comprehensive verification that all quality gates pass before committing.

> **THIS PHASE IS BLOCKING** - The task cannot proceed to commit until ALL checks pass.

### Verify Checklist

All items must be checked and pass:

#### 1. Test Suite Verification
- [ ] All tests pass (zero failures)
- [ ] Coverage meets project threshold (if configured)
- [ ] No skipped tests without justification

**If tests fail**: Return to Phase 3 BUILD, fix the issue, then re-run through Phase 6 TEST.

#### 2. Code Review Verification
- [ ] Code review completed (Phase 4)
- [ ] Verdict was APPROVED
- [ ] All critical issues were addressed
- [ ] All major concerns were addressed

**If not approved**: Return to Phase 5 REFACTOR, address concerns, re-review.

#### 3. Security Audit (Security Engineer)

Invoke the Security Engineer persona for a comprehensive security audit:

1. Read and internalize `.claude/skills/security-engineer/SKILL.md`
2. Perform the full security audit checklist
3. Write findings to `.claude/security-audit.md`

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
- **Status**: [APPROVED | NEEDS_WORK]
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
if tests_pass AND code_review_approved AND security_clean AND architecture_valid:
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

## Phase 8: COMMIT

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

## Phase 9: SIGNAL COMPLETION

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
- `.claude/current-plan.md`
- `.claude/plan-review.md`
- `.claude/code-review.md`
- `.claude/current-test-plan.md`
- `.claude/test-report.md`
- `.claude/security-audit.md`
- `.claude/verify-report.md`

---

## Important Reminders

- **Stay focused**: Only implement what the task requires
- **Follow patterns**: Match the existing codebase style
- **Be thorough**: Complete all phases before signaling completion
- **Handle errors gracefully**: Mark as blocked rather than failing silently
- **Don't push**: Only commit locally, never push to remote
- **Signal completion**: Always write the status file at the end
- **Trust the personas**: Let the Principal Engineer and QA Engineer do their jobs
