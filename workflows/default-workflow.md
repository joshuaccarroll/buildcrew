# BuildCrew Default Workflow

This is the default 9-phase workflow for BuildCrew. Projects can customize this by creating `.buildcrew/workflow.md`.

---

## Phases

### Phase 1: PLAN
**agent**: none
**description**: Analyze task, explore codebase, create implementation plan
**output**: .claude/current-plan.md

Steps:
1. Read and understand the task from BACKLOG.md
2. Explore the codebase to understand existing patterns
3. Create a detailed implementation plan
4. Write plan to .claude/current-plan.md

---

### Phase 2: PLAN_REVIEW
**agent**: principal-engineer
**description**: Review plan for architecture, simplicity, testability
**input**: .claude/current-plan.md
**output**: .claude/plan-review.md
**gate**: verdict == "APPROVED"

The Principal Engineer reviews the plan and provides:
- Verdict: APPROVED, NEEDS_REVISION, or REJECTED
- Strengths and concerns
- Required changes (if any)

If NEEDS_REVISION: Return to Phase 1 with feedback
If REJECTED: Mark task as blocked

---

### Phase 3: BUILD
**agent**: feature-engineer
**description**: Implement the plan with focus on user value
**input**: .claude/current-plan.md

The Feature Engineer:
1. Follows the approved plan
2. Implements incrementally
3. Follows existing patterns
4. Writes clean, readable code

---

### Phase 4: CODE_REVIEW
**agent**: principal-engineer
**description**: Review implemented code for quality, patterns, and cleanup
**output**: .claude/code-review.md
**gate**: verdict == "APPROVED"

The Principal Engineer reviews:
- Correctness
- Design quality (SOLID principles)
- Readability
- Simplicity
- Testability
- Cleanup (unused imports, orphaned files, dead code)

If NEEDS_REVISION: Continue to Phase 5 (REFACTOR)
If APPROVED: Skip to Phase 6 (TEST)

---

### Phase 5: REFACTOR
**agent**: none
**condition**: code_review.verdict == "NEEDS_REVISION"
**description**: Address issues from code review

Fix issues identified in code review, then return to Phase 4.
Maximum 3 refactor cycles before marking task as blocked.

---

### Phase 6: TEST
**agent**: qa-engineer
**description**: Create test plan, write tests, run test suite
**output**: .claude/test-report.md

The QA Engineer:
1. Creates test plan for the implementation
2. Writes tests (unit, integration as needed)
3. Runs the test suite
4. Reports results

---

### Phase 7: VERIFY
**agent**: security-engineer
**description**: Security audit and final verification
**output**: .claude/security-audit.md
**gate**: all_checks_pass

**BLOCKING GATE** - All checks must pass:
- [ ] All tests pass
- [ ] Code review approved
- [ ] No critical/high security vulnerabilities
- [ ] No hardcoded secrets

If any check fails: Return to Phase 3 (BUILD) with findings

---

### Phase 8: COMMIT
**agent**: none
**description**: Create git commit for the changes

Create a conventional commit:
- Summarize the changes
- Reference the task
- Do NOT push (commits stay local)

---

### Phase 9: SIGNAL
**agent**: none
**description**: Write completion status for orchestrator
**output**: .claude/workflow-status.json

Write status file:
```json
{
  "status": "complete",
  "task": "[task description]",
  "summary": "[what was done]",
  "commit": "[commit hash]",
  "timestamp": "[ISO timestamp]"
}
```

---

## Customization

To customize this workflow for your project:

1. Create `.buildcrew/workflow.md` in your project
2. Define your phases using the same format
3. You can:
   - Remove phases (e.g., skip PLAN_REVIEW for speed)
   - Add phases (e.g., add DEPLOY after COMMIT)
   - Change agents assigned to phases
   - Modify gate conditions

### Example: Minimal Workflow

```markdown
## Phases

### Phase 1: BUILD
agent: feature-engineer
description: Build the feature

### Phase 2: TEST
agent: qa-engineer
description: Test it

### Phase 3: COMMIT
agent: none
description: Commit changes
```
