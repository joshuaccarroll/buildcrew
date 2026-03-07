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

### Revision Cycle Detection

If `.claude/plan-review-prev.md` exists, this is a **revision cycle** — the plan was already reviewed and revised. Your job shifts from "find everything wrong" to "verify previous issues were addressed and check for regressions." Read `.claude/plan-review-prev.md` first to understand what was previously flagged.

---

## PLAN-REVIEW: Adversarial 3-Pass Review

**Goal**: Challenge the plan ruthlessly before any code is written. Your job is to find what's wrong with it — not to approve it quickly. This phase uses Pass 1 (PE sub-agent) followed by a serial convergence loop (Passes 2–4) and a final inline synthesis (Pass 3).

> **Adversarial mindset**: Assume something is wrong with this plan. Your task is to find it. A plan that survives adversarial review is a plan worth building.

---

### Pass 1: Technical Review (Principal Engineer)

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

3. **Simplicity Check** — What's the most unnecessary thing in this plan?
   - What would you cut if you had to ship in half the time?
   - What abstractions are being added for hypothetical futures?

4. **Testability Assessment** — What in this plan is untestable, and why?
   - What edge cases are conspicuously absent?
   - What will be hardest to verify actually works?

5. **Red Flags** — What would make you reject this in a real code review?
   - Over-engineering? Poor separation of concerns? Security holes?

6. **Context Budget** — Will this plan produce oversized artifacts?
   Will the implementation plan produce documents or code that will strain the context window
   in later phases? Flag any step that generates 200+ lines of output (large config files,
   extensive test suites, long documentation). These should be broken into smaller steps or
   noted as a context risk.

7. **Step Ordering** — What ordering mistake will bite us mid-build?
   - Are foundations laid before features?
   - Each step: does it produce a verifiable state?
   - Human prerequisites (API keys, accounts, DNS) — are they early enough?
   - **Cross-reference lint**: For each step that names a file, function, or config key, verify
     it matches an actual artifact in the codebase or is explicitly created by an earlier step.
     Flag any dangling reference (typo, renamed symbol, removed file) as NEEDS_REVISION.

Write your review to `.claude/review-pass1-pe.md`. Do NOT modify `.claude/current-plan.md`.
Keep your review concise: max 80 lines. Focus on the top 3-5 findings, not exhaustive nitpicking.

End your review with a verdict line on its own line:
VERDICT: PASS
or
VERDICT: NEEDS_REVISION
```

If `.claude/plan-review-prev.md` exists, use this alternate prompt for Pass 1 instead:

```
You are a principal engineer reviewing a REVISED implementation plan. The plan was already reviewed once and flagged for revision. Your job is NOT to find everything wrong from scratch — it is to verify that the previous issues were addressed and that revisions did not introduce regressions.

Read `.claude/plan-review-prev.md` and `.claude/review-pass1-pe-prev.md` first to understand what was previously flagged. Then read `.claude/current-plan.md` to evaluate the revised plan.

The previous review files reflect an earlier version of the plan. Do not re-inherit the previous verdict — evaluate the current plan on its own merits, informed by what changed.

Focus on:
1. **Were previous issues addressed?** For each finding in `.claude/review-pass1-pe-prev.md`, did the revision substantively resolve it? Note which were addressed and which were not.
2. **Did revisions introduce regressions?** Did fixing one issue break another part of the plan? Are new structural problems present that weren't there before?
3. **New blocking issues only** — only flag NEW issues if they are genuinely blocking (security holes, data loss risk, core logic errors, complete misunderstanding of requirements). Do not nitpick things not flagged in the previous cycle.

Write your review to `.claude/review-pass1-pe.md`. Do NOT modify `.claude/current-plan.md`.
Keep your review concise: max 50 lines.

End your review with a verdict line on its own line:
VERDICT: PASS
or
VERDICT: NEEDS_REVISION
```

After the Pass 1 sub-agent completes, verify that `.claude/review-pass1-pe.md` exists and contains a `VERDICT:` line. If the file is missing or contains no VERDICT line, log a warning and treat Pass 1 as NEEDS_REVISION with details "Sub-agent failed to produce review".

If the Pass 1 sub-agent failed to produce its review file, write `.claude/phase-result.json`:

```json
{
  "phase": "plan_review",
  "verdict": "needs_revision",
  "details": "Pass 1 review sub-agent failed to produce output — possible tool or context issue"
}
```

Then exit.

---

### Passes 2–4: Serial Convergence Loop (up to 3 rounds)

After Pass 1 completes, run a serial convergence loop — up to 3 iterations — to refine the plan.

**Determine the prompt variant** based on revision cycle:

- **Fresh review** (no `.claude/plan-review-prev.md`): use the **standard prompt** below
- **Revision cycle** (`.claude/plan-review-prev.md` exists): use the **revision prompt** below

**Standard convergence prompt** (use when NOT in a revision cycle):

```
Read `.claude/current-plan.md`. Review it critically as if seeing it for the first time.
Look for gaps, missing details, unclear sections, over-engineering, incorrect assumptions,
missing edge cases, and areas that could be improved.

Make concrete improvements directly to the file. Be specific and substantive.

If the document is solid and no meaningful improvements can be made,
respond with exactly: CONVERGED

Do not explain what you reviewed. Either improve the file or respond CONVERGED.
```

**Revision convergence prompt** (use when `.claude/plan-review-prev.md` exists):

```
Read `.claude/plan-review-prev.md` to understand what was previously flagged. Then read `.claude/current-plan.md`.

Your job is NOT to re-review from scratch. Verify that previous findings were addressed and check for regressions. Only flag NEW issues if they are genuinely blocking (security, data loss, core logic error).

Make targeted improvements to `.claude/current-plan.md` if previous issues were NOT addressed.

If previous issues were substantively addressed (even if imperfectly), respond with exactly: CONVERGED

Do not explain what you reviewed. Either improve the file or respond CONVERGED.
```

**Loop execution** — for each iteration (0, 1, 2):

1. Spawn a Task sub-agent **(general-purpose type)** with the appropriate prompt above
2. If the sub-agent output contains exactly `CONVERGED` — the plan has converged. Stop the loop early.
3. If the sub-agent failed to produce output — log a warning ("Convergence sub-agent failed (iteration N)") and break the loop.
4. Otherwise — the sub-agent improved the plan. Continue to the next iteration.

After at most 3 iterations (or early stop), proceed to Pass 3.

---

### Pass 3: Convergence Synthesis (Inline)

Read `.claude/review-pass1-pe.md` and `.claude/current-plan.md` (which reflects all convergence improvements).

Synthesize:

1. The hardest question: is this the right approach, or just an approach?
2. Did the convergence loop resolve the issues flagged in Pass 1?
3. Is there a fundamentally simpler way to deliver the same value that was overlooked?
4. Step ordering: foundations first, verification checkpoints present, prerequisites early?
5. What would you be embarrassed about if this shipped as-is?
6. If `.claude/plan-review-prev.md` exists: were previous findings substantively addressed?
7. If this is a revision cycle: bias toward convergence if previous issues were addressed, even if imperfectly. Do not reject for issues not flagged in the previous cycle unless they are genuinely critical (security, data loss, core logic error).

**Pass 3 Verdict**: APPROVED / NEEDS_REVISION / REJECTED

Only issue APPROVED if you would genuinely stake your reputation on this plan proceeding to build. Holding a revised plan to a higher standard than the original creates a non-converging loop. If the revisions addressed the substance of previous findings, approve.

If NEEDS_REVISION or REJECTED: update `.claude/current-plan.md` with targeted edits based on the synthesized findings. **Do NOT re-enter the review cycle** — the orchestrator handles retries externally.

---

### Plan Review Output

Write the combined review to `.claude/plan-review.md`:

```markdown
## Plan Review (3-Pass)

### Pass 1: Technical Review (Principal Engineer)
**Verdict**: [PASS | NEEDS_REVISION]
- [Key findings from PE review]

### Pass 2: Convergence Loop
**Rounds**: [N rounds run | CONVERGED after N rounds | early stop]
- [Summary of improvements made]

### Pass 3: Convergence Synthesis
**Verdict**: [APPROVED | NEEDS_REVISION | REJECTED]
- [Final assessment — convergence loop resolved issues? Simpler approach?]

### Overall Verdict: [APPROVED | NEEDS_REVISION | REJECTED]

### Strengths
- [What's good about this plan]

### Required Changes (if NEEDS_REVISION)
1. [Specific change to make to the plan]

### Approved to Proceed: [YES | NO - revise plan first]
```

Source Pass 1 findings from `.claude/review-pass1-pe.md`.

