---
name: buildcrew-review
description: BuildCrew Plan Review phase — single-cycle 3-pass review of implementation plan
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task
---

# BuildCrew — Plan Review

`[Phase: plan-review | Input: .claude/current-plan.md | Output: .claude/plan-review.md (approved/revised plan) | Next: BUILD]`

You are executing the plan-review phase of the BuildCrew autonomous development workflow.

## Your Task

The task was provided in the prompt. The implementation plan is in `.claude/current-plan.md`.

---

## PLAN-REVIEW: Adversarial 3-Pass Review

**Goal**: Challenge the plan ruthlessly before any code is written. Your job is to find what's wrong with it — not to approve it quickly. This phase uses 3 adversarial review passes with fresh-context sub-agents for Passes 1 and 2.

> **Adversarial mindset**: Assume something is wrong with this plan. Your task is to find it. A plan that survives adversarial review is a plan worth building.

---

### Pass 1: Technical Review (Principal Engineer Sub-Agent)

Spawn a Task sub-agent **(general-purpose type)** with this exact prompt:

```
You are a principal engineer reviewing an implementation plan. Your job is to find the most serious flaw — not to approve it quickly. Assume something is wrong. If you were a staff engineer whose name would be on this PR, what would you block on? Only pass if you'd stake your reputation on it.

Read `.claude/current-plan.md` and interrogate it against:

1. **Scope Assessment** — Is this actually solving the right problem, or just the stated problem?
   - What's the most likely way this plan misunderstands the task?
   - Is the scope appropriate, or are we over/under-building?
   - What hidden complexities does this plan not address?

2. **Architecture Fit** — What's the most serious architectural risk here?
   - Does this align with existing architecture, or does it fight it?
   - Will this create technical debt that will cost 3x to unwind?
   - If `.buildcrew/norms/patterns.md` exists, read it — what pattern does this plan violate?

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

Write your review to `.claude/review-pass1-pe.md`. Do NOT modify `.claude/current-plan.md`.
Keep your review concise: max 80 lines. Focus on the top 3-5 findings, not exhaustive nitpicking.

End your review with a verdict line on its own line:
VERDICT: PASS
or
VERDICT: NEEDS_REVISION
```

After the sub-agent completes, verify that `.claude/review-pass1-pe.md` exists and contains a `VERDICT:` line. If the file is missing or contains no VERDICT line, log a warning ("Pass 1 sub-agent failed to produce review") and treat this pass as NEEDS_REVISION with details "Sub-agent failed to produce review".

---

### Pass 2: User Impact Review (Product Manager Sub-Agent)

Spawn a Task sub-agent **(general-purpose type)** with this exact prompt:

```
You are a product manager reviewing an implementation plan for user impact. Your job is to find where this plan fails the user. Assume the user will be confused or underserved. Where?

Read `.claude/current-plan.md`. If `.claude/spec.md` exists, read it too.

Walk through the plan from the end user's perspective with adversarial intent:

1. **User Flow Challenge**
   - "I'm a user who wants [goal]." Now walk through the plan step by step.
   - At what point does the user experience break down?
   - What will confuse a user who hasn't read the code?

2. **Acceptance Criteria Gap Hunt**
   - Does this plan actually solve the stated task from the end user's perspective?
   - What acceptance criteria are missing or too vague to verify?
   - If `.claude/spec.md` exists — does the plan address every acceptance criterion?
   - Will the user know the feature exists and how to use it?

3. **Edge Case Reality Check**
   - What edge cases will real users hit on day one?
   - What existing workflows does this break?
   - What happens when something goes wrong — does the user get a helpful error, or a stack trace?

4. **Value Challenge**
   - Is this the simplest thing that delivers value?
   - What would a skeptical user say about this feature?
   - If `.buildcrew/context/principles.md` exists, check alignment.

5. **Human Prerequisites Audit**
   - Are all human-required actions identified and sequenced early?
   - What will block a human who tries to run this without reading the plan?

Write your review to `.claude/review-pass2-pm.md`. Do NOT modify `.claude/current-plan.md`. Do NOT use AskUserQuestion.
Keep your review concise: max 80 lines. Focus on the top 3-5 findings, not exhaustive nitpicking.

End your review with a verdict line on its own line:
VERDICT: PASS
or
VERDICT: NEEDS_REVISION
```

After the sub-agent completes, verify that `.claude/review-pass2-pm.md` exists and contains a `VERDICT:` line. If the file is missing or contains no VERDICT line, log a warning ("Pass 2 sub-agent failed to produce review") and treat this pass as NEEDS_REVISION with details "Sub-agent failed to produce review".

If both sub-agents failed to produce their review files, write `.claude/phase-result.json`:

```json
{
  "phase": "plan_review",
  "verdict": "needs_revision",
  "details": "Both review sub-agents failed to produce output — possible tool or context issue"
}
```

Then exit.

---

### Pass 3: Convergence Review (Inline)

Read `.claude/review-pass1-pe.md`, `.claude/review-pass2-pm.md`, and `.claude/current-plan.md`.

Synthesize:

1. The hardest question: is this the right approach, or just an approach?
2. Do PE and PM agree? Where do they conflict? What does conflict reveal?
3. Has PM feedback been addressed without creating new technical problems?
4. Is there a fundamentally simpler way to deliver the same value that was overlooked?
5. Step ordering: foundations first, verification checkpoints present, prerequisites early?
6. What would you be embarrassed about if this shipped as-is?

**Pass 3 Verdict**: APPROVED / NEEDS_REVISION / REJECTED

Only issue APPROVED if you would genuinely stake your reputation on this plan proceeding to build.

If NEEDS_REVISION or REJECTED: update `.claude/current-plan.md` with targeted edits based on the synthesized findings from Pass 1 and Pass 2. **Do NOT re-enter the 3-pass cycle** — the orchestrator handles retries externally.

---

### Plan Review Output

Write the combined review to `.claude/plan-review.md`:

```markdown
## Plan Review (3-Pass)

### Pass 1: Technical Review (Principal Engineer)
**Verdict**: [PASS | NEEDS_REVISION]
- [Key findings from PE review]

### Pass 2: User Impact Review (Product Manager)
**Verdict**: [PASS | NEEDS_REVISION]
- [Key findings from PM review]
- [Acceptance criteria gaps identified]
- [Edge cases flagged]

### Pass 3: Convergence Review (Principal Engineer)
**Verdict**: [APPROVED | NEEDS_REVISION | REJECTED]
- [Final assessment — do PE and PM agree? Conflicts? Simpler approach?]

### Overall Verdict: [APPROVED | NEEDS_REVISION | REJECTED]

### Strengths
- [What's good about this plan]

### Required Changes (if NEEDS_REVISION)
1. [Specific change to make to the plan]

### Approved to Proceed: [YES | NO - revise plan first]
```

Source Pass 1 findings from `.claude/review-pass1-pe.md` and Pass 2 findings from `.claude/review-pass2-pm.md`.

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
