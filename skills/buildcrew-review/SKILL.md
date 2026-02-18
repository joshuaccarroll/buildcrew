---
name: buildcrew-review
description: BuildCrew Plan Review phase — single-cycle 3-pass review of implementation plan
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task
---

# BuildCrew — Plan Review

`[Phase 3/10: PLAN_REVIEW | Input: .claude/current-plan.md | Output: .claude/plan-review.md (approved/revised plan) | Next: BUILD]`

You are executing phase 3 of the BuildCrew autonomous development workflow.

## Your Task

The task was provided in the prompt. The implementation plan is in `.claude/current-plan.md`.

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

### Revision Handling

If any pass returns NEEDS_REVISION:
1. Update `.claude/current-plan.md` with the required changes
2. When revising `.claude/current-plan.md`, run iterative sub-agent review on the updated plan:
   ```
   iteration = 0
   while iteration < 5:
       Spawn a Task sub-agent (general-purpose type) with this prompt:
       "Read .claude/current-plan.md. Review it critically as if you are seeing it for the first time.
       Look for: gaps, missing details, unclear sections, over-engineering, incorrect assumptions,
       missing edge cases, and areas that could be improved.
       Make concrete improvements directly to the file. Be specific and substantive --
       do not add filler or unnecessary content.
       If the document is solid and no meaningful improvements can be made,
       respond with exactly: CONVERGED
       Do not explain what you reviewed. Either improve the file or respond CONVERGED."
       if sub-agent output contains "CONVERGED": break
       iteration += 1
   ```
3. **Do NOT re-enter the 3-pass review cycle** — the orchestrator handles retries externally
4. Report the overall verdict as `needs_revision` in `.claude/phase-result.json`
5. Only report `approved` when all 3 passes return PASS/APPROVED in a single cycle

---

## Phase Result Protocol

When the plan review is complete, write `.claude/phase-result.json`:

**If approved:**
```json
{
  "phase": "plan_review",
  "verdict": "approved",
  "details": "3-pass review complete, plan approved"
}
```

**If needs revision (plan updated, needs another review cycle from orchestrator):**
```json
{
  "phase": "plan_review",
  "verdict": "needs_revision",
  "details": "Plan updated with revisions, needs re-review"
}
```

**If rejected:**
```json
{
  "phase": "plan_review",
  "verdict": "rejected",
  "details": "Plan fundamentally flawed: [reason]"
}
```

Then exit.
