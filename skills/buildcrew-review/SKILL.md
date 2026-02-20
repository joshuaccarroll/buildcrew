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

## Phase 3: PLAN REVIEW (3-Pass Adversarial Review)

**Goal**: Challenge the plan ruthlessly before any code is written. Your job is to find what's wrong with it — not to approve it quickly. This phase uses 3 adversarial review passes.

> **Adversarial mindset**: Assume something is wrong with this plan. Your task is to find it. A plan that survives adversarial review is a plan worth building.

### Pass 1: Technical Review (Principal Engineer)

**Assume the Principal Engineer Persona.**

**Your job is to find the most serious flaw in this plan.** Assume something is wrong. What is it? If you were a staff engineer whose name would be on this PR, what would you block on? Only pass if you'd stake your reputation on it.

Interrogate `.claude/current-plan.md` against:

1. **Scope Assessment** — Is this actually solving the right problem, or just the stated problem?
   - What's the most likely way this plan misunderstands the task?
   - Is the scope appropriate, or are we over/under-building?
   - What hidden complexities does this plan not address?

2. **Architecture Fit** — What's the most serious architectural risk here?
   - Does this align with existing architecture, or does it fight it?
   - Will this create technical debt that will cost 3x to unwind?
   - If `.buildcrew/norms/` exists, read `patterns.md`. What pattern does this plan violate?

3. **Simplicity Check** — What's the most unnecessary thing in this plan?
   - What would you cut if you had to ship in half the time?
   - What abstractions are being added for hypothetical futures?

4. **Testability Assessment** — What in this plan is untestable, and why?
   - What edge cases are conspicuously absent?
   - What will be hardest to verify actually works?

5. **Red Flags** — What would make you reject this in a real code review?
   - Over-engineering? Poor separation of concerns? Security holes?

6. **Step Ordering** — What ordering mistake will bite us mid-build?
   - Are foundations laid before features?
   - Each step: does it produce a verifiable state?
   - Human prerequisites (API keys, accounts, DNS) — are they early enough?

**Pass 1 Verdict**: PASS / NEEDS_REVISION

If NEEDS_REVISION: Update `.claude/current-plan.md` with required changes before proceeding to Pass 2.

---

### Pass 2: User Impact Review (Product Manager)

**Assume the Product Manager Persona.**

**Your job is to find where this plan fails the user.** Assume the user will be confused or underserved. Where?

Walk through the plan from the end user's perspective with adversarial intent:

1. **User Flow Challenge**
   - "I'm a user who wants [goal]." Now walk through the plan step by step.
   - At what point does the user experience break down?
   - What will confuse a user who hasn't read the code?

2. **Acceptance Criteria Gap Hunt**
   - Does this plan actually solve the stated task from the end user's perspective?
   - What acceptance criteria are missing or too vague to verify?
   - If `.claude/spec.md` exists, read it — does the plan address every acceptance criterion?
   - Will the user know the feature exists and how to use it?

3. **Edge Case Reality Check**
   - What edge cases will real users hit on day one?
   - What existing workflows does this break?
   - What happens when something goes wrong — does the user get a helpful error, or a stack trace?

4. **Value Challenge**
   - Is this the simplest thing that delivers value?
   - What would a skeptical user say about this feature?
   - Does this align with project principles (`.buildcrew/context/principles.md` if present)?

5. **Human Prerequisites Audit**
   - Are all human-required actions identified and sequenced early?
   - What will block a human who tries to run this without reading the plan?

**Pass 2 Verdict**: PASS / NEEDS_REVISION

If NEEDS_REVISION: Update `.claude/current-plan.md` to address user-facing gaps before proceeding to Pass 3.

---

### Pass 3: Convergence Review (Principal Engineer)

**Assume the Principal Engineer Persona again.**

**Final adversarial check**: Has this plan been sufficiently interrogated, or are we approving it to move on?

1. The hardest question: is this the right approach, or just an approach?
2. Has PM feedback been addressed without creating new technical problems?
3. Is there a fundamentally simpler way to deliver the same value that was overlooked?
4. Step ordering: foundations first, verification checkpoints present, prerequisites early?
5. What would you be embarrassed about if this shipped as-is?

**Pass 3 Verdict**: APPROVED / NEEDS_REVISION / REJECTED

Only issue APPROVED if you would genuinely stake your reputation on this plan proceeding to build.

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
