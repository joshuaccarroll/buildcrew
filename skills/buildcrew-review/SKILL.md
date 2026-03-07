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

**Goal**: Challenge the plan ruthlessly before any code is written. Your job is to find what's wrong with it — not to approve it quickly. This phase uses 3 parallel lens sub-agents (Round 1), a serial convergence loop (Round 2), and a final inline synthesis (Pass 3).

> **Adversarial mindset**: Assume something is wrong with this plan. Your task is to find it. A plan that survives adversarial review is a plan worth building.

---

### Round 1 — 3 Parallel Lenses

In a **single response**, spawn all 3 parallel lens Task sub-agents simultaneously. Do NOT wait for one to finish before launching the next — all 3 must be spawned in a single response (parallel, not sequential):

**Lens 1 — Technical Soundness**: Spawn a Task sub-agent **(general-purpose type)** with this exact prompt:

```
You are a principal engineer reviewing an implementation plan through a technical soundness lens. Your job is to find the most serious technical flaw — not to approve it quickly. Assume something is wrong. If you were a staff engineer whose name would be on this PR, what would you block on?

Read `.claude/current-plan.md` and interrogate it against:

1. **Scope Assessment** — Is this actually solving the right problem?
   - What's the most likely way this plan misunderstands the task?
   - Is the scope appropriate, or are we over/under-building?
   - What hidden complexities does this plan not address?

2. **Architecture Fit** — What's the most serious architectural risk?
   - Does this align with existing architecture, or does it fight it?
   - Will this create technical debt that will cost 3x to unwind?

3. **Step Ordering** — What ordering mistake will bite us mid-build?
   - Are foundations laid before features?
   - Each step: does it produce a verifiable state?
   - Human prerequisites (API keys, accounts, DNS) — are they early enough?
   - **Cross-reference lint**: For each step that names a file, function, or config key, verify
     it matches an actual artifact in the codebase or is explicitly created by an earlier step.
     Flag any dangling reference (typo, renamed symbol, removed file) as NEEDS_REVISION.

4. **Context Budget** — Will this plan produce oversized artifacts?
   Will the implementation plan produce documents or code that will strain the context window
   in later phases? Flag any step that generates 200+ lines of output. These should be broken
   into smaller steps or noted as a context risk.

5. **Testability** — What in this plan is untestable, and why?
   - What edge cases are conspicuously absent?
   - What will be hardest to verify actually works?

Write your review to `.claude/review-lens1.md`. Do NOT modify `.claude/current-plan.md`.
Keep your review concise: max 80 lines. Focus on the top 3-5 findings, not exhaustive nitpicking.

End your review with a verdict line on its own line:
VERDICT: PASS
or
VERDICT: NEEDS_REVISION
```

If `.claude/plan-review-prev.md` exists, use this alternate prompt for Lens 1 instead:

```
You are a principal engineer reviewing a REVISED implementation plan through a technical soundness lens. The plan was already reviewed once and flagged for revision. Your job is NOT to find everything wrong from scratch — it is to verify that the previous technical issues were addressed and that revisions did not introduce regressions.

Read `.claude/plan-review-prev.md` and `.claude/review-lens1-prev.md` first to understand what was previously flagged. Then read `.claude/current-plan.md` to evaluate the revised plan.

The previous review files reflect an earlier version of the plan. Do not re-inherit the previous verdict — evaluate the current plan on its own merits, informed by what changed.

Focus on:
1. **Were previous technical issues addressed?** For each finding in `.claude/review-lens1-prev.md`, did the revision substantively resolve it? Note which were addressed and which were not.
2. **Did revisions introduce regressions?** Did fixing one issue break another part of the plan? Are new structural problems present that weren't there before?
3. **New blocking issues only** — only flag NEW issues if they are genuinely blocking (security holes, data loss risk, core logic errors, complete misunderstanding of requirements). Do not nitpick things not flagged in the previous cycle.

Write your review to `.claude/review-lens1.md`. Do NOT modify `.claude/current-plan.md`.
Keep your review concise: max 50 lines.

End your review with a verdict line on its own line:
VERDICT: PASS
or
VERDICT: NEEDS_REVISION
```

**Lens 2 — Completeness & Gaps**: Also spawn a Task sub-agent **(general-purpose type)** with this exact prompt:

```
You are reviewing an implementation plan through a completeness and gaps lens. Your job is to find what's missing — acceptance criteria not covered, edge cases not handled, failure modes not addressed. Assume something has been overlooked.

Read `.claude/current-plan.md`. If `.claude/spec.md` exists, read it too.

Before walking the plan:
Check whether `.claude/research.md` exists.
- If it exists and contains a `## UX Impact` section: read it. Verify that the plan addresses each touch point listed. Record any gaps as findings.
- If it exists but does NOT contain a `## UX Impact` section, and the spec describes user-visible behavior changes: record a finding that UX analysis was expected but not produced.
- If `research.md` does not exist: skip this check.

1. **Acceptance Criteria Coverage** — Does the plan address every AC?
   - Which acceptance criteria from the spec are not covered by any step?
   - Will the user know the feature exists and how to use it?
   - Does this plan actually solve the stated task from the end user's perspective?

2. **Edge Case Reality Check** — What will real users hit on day one?
   - What edge cases are conspicuously absent?
   - What existing workflows does this break?
   - What happens when something goes wrong — helpful error, or stack trace?
   - What happens to in-progress work if the operation fails halfway through?

3. **Failure Handling** — Where can this go wrong with no recovery path?
   - Network failures, missing files, bad input, permission errors?
   - Are all failure paths handled with actionable error messages?

4. **Human Prerequisites Audit** — Are all human-required actions identified?
   - What will block a human who tries to run this without reading the plan?
   - Are API keys, accounts, DNS changes, or external services identified early enough?

Write your review to `.claude/review-lens2.md`. Do NOT modify `.claude/current-plan.md`. Do NOT use AskUserQuestion.
Keep your review concise: max 80 lines. Focus on the top 3-5 findings, not exhaustive nitpicking.

End your review with a verdict line on its own line:
VERDICT: PASS
or
VERDICT: NEEDS_REVISION
```

If `.claude/plan-review-prev.md` exists, use this alternate prompt for Lens 2 instead:

```
You are reviewing a REVISED implementation plan through a completeness and gaps lens. The plan was already reviewed once and flagged for revision. Your job is NOT to find everything wrong from scratch — it is to verify that the previous completeness issues were addressed and that revisions did not accidentally drop or weaken acceptance criteria.

Read `.claude/plan-review-prev.md` and `.claude/review-lens2-prev.md` first to understand what was previously flagged. Then read `.claude/current-plan.md` to evaluate the revised plan. If `.claude/spec.md` exists, read it too.

The previous review files reflect an earlier version of the plan. Do not re-inherit the previous verdict — evaluate the current plan on its own merits, informed by what changed.

Focus on:
1. **Were previous completeness issues resolved?** For each finding in `.claude/review-lens2-prev.md`, did the revision substantively address it? Note which were addressed and which were not.
2. **Were acceptance criteria preserved?** Did the revisions accidentally drop, weaken, or contradict any acceptance criteria from `.claude/spec.md` or the original task? Verify each criterion is still covered.
3. **Did revisions introduce new gaps?** Are there new missing pieces in the plan not present before?
4. **New blocking issues only** — only flag NEW issues if they are genuinely blocking (acceptance criteria dropped, critical user flow broken, fundamental misunderstanding of the task). Do not nitpick things not flagged in the previous cycle.

Write your review to `.claude/review-lens2.md`. Do NOT modify `.claude/current-plan.md`. Do NOT use AskUserQuestion.
Keep your review concise: max 50 lines.

End your review with a verdict line on its own line:
VERDICT: PASS
or
VERDICT: NEEDS_REVISION
```

**Lens 3 — Simplicity & Over-engineering**: Also spawn a Task sub-agent **(general-purpose type)** with this exact prompt:

```
You are reviewing an implementation plan through a simplicity lens. Your job is to find what should be cut, simplified, or replaced with a simpler alternative. Complexity is the enemy — attack it. Assume the plan is more complex than it needs to be.

Read `.claude/current-plan.md`. If `.buildcrew/context/principles.md` exists, check alignment.

1. **What to Cut** — What is the most unnecessary thing in this plan?
   - What would you remove if you had to ship in half the time?
   - What steps are "nice to have" rather than "must have"?
   - What abstractions are being added for hypothetical futures?

2. **Simpler Alternatives** — Is there a fundamentally simpler way to deliver the same value?
   - Could 3 steps be collapsed into 1?
   - Is there an existing tool, library, or pattern that makes a custom solution unnecessary?
   - What would you cut if you were a skeptical senior engineer?

3. **Over-engineering Red Flags** — Poor separation of concerns? Unnecessary layers?
   - Is the plan building infrastructure when a simple solution exists?
   - Are there more than 2 levels of indirection for a simple operation?
   - Helper functions, utilities, or wrappers being added for one-time use?
   - Configuration for features that don't need to be configurable yet?

4. **Value Challenge** — Is this the simplest thing that delivers the stated value?
   - What would a skeptical user say about this feature's complexity?
   - If this shipped as-is, what would you be embarrassed about?

Write your review to `.claude/review-lens3.md`. Do NOT modify `.claude/current-plan.md`.
Keep your review concise: max 80 lines. Focus on the top 3-5 findings, not exhaustive nitpicking.

End your review with a verdict line on its own line:
VERDICT: PASS
or
VERDICT: NEEDS_REVISION
```

If `.claude/plan-review-prev.md` exists, use this alternate prompt for Lens 3 instead:

```
You are reviewing a REVISED implementation plan through a simplicity lens. The plan was already reviewed once and flagged for revision. Your job is NOT to find everything wrong from scratch — it is to verify that the previous over-engineering issues were addressed and that revisions did not introduce new complexity.

Read `.claude/plan-review-prev.md` and `.claude/review-lens3-prev.md` first to understand what was previously flagged. Then read `.claude/current-plan.md` to evaluate the revised plan.

The previous review files reflect an earlier version of the plan. Do not re-inherit the previous verdict — evaluate the current plan on its own merits, informed by what changed.

Focus on:
1. **Were previous simplicity issues resolved?** For each finding in `.claude/review-lens3-prev.md`, did the revision substantively address it? Note which were addressed and which were not.
2. **Did revisions introduce new complexity?** Did fixing one issue create a more complex solution elsewhere?
3. **New blocking issues only** — only flag NEW issues if they are genuinely blocking (fundamental over-engineering that will make the feature unmaintainable). Do not nitpick things not flagged in the previous cycle.

Write your review to `.claude/review-lens3.md`. Do NOT modify `.claude/current-plan.md`.
Keep your review concise: max 50 lines.

End your review with a verdict line on its own line:
VERDICT: PASS
or
VERDICT: NEEDS_REVISION
```

After all 3 lens sub-agents complete, verify that `.claude/review-lens1.md`, `.claude/review-lens2.md`, and `.claude/review-lens3.md` exist and contain `VERDICT:` lines. For any lens file that is missing or contains no VERDICT line, log a warning: `"Lens [N] sub-agent failed to produce output"` and treat that lens as PASS with no findings (do not promote a missing lens to NEEDS_REVISION — the remaining lenses provide adequate coverage).

If all 3 lens sub-agents failed to produce their review files, write `.claude/phase-result.json`:

```json
{
  "phase": "plan_review",
  "verdict": "needs_revision",
  "details": "All 3 lens sub-agents failed to produce output — possible tool or context issue"
}
```

Then exit.

---

### Round 2: Serial Convergence Loop (up to 3 rounds)

After Round 1 completes, run a serial convergence loop — up to 3 iterations — to refine the plan based on lens findings.

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

Read `.claude/review-lens1.md`, `.claude/review-lens2.md`, `.claude/review-lens3.md`, and `.claude/current-plan.md` (which reflects all convergence improvements).

Synthesize:

1. The hardest question: is this the right approach, or just an approach?
2. Do the lenses agree? Where do they conflict? What does conflict reveal?
3. Did the convergence loop resolve the issues flagged by the lenses?
4. Is there a fundamentally simpler way to deliver the same value that was overlooked?
5. Step ordering: foundations first, verification checkpoints present, prerequisites early?
6. What would you be embarrassed about if this shipped as-is?
7. If `.claude/plan-review-prev.md` exists: were previous findings substantively addressed?
8. If this is a revision cycle: bias toward convergence if previous issues were addressed, even if imperfectly. Do not reject for issues not flagged in the previous cycle unless they are genuinely critical (security, data loss, core logic error).

**Pass 3 Verdict**: APPROVED / NEEDS_REVISION / REJECTED

Only issue APPROVED if you would genuinely stake your reputation on this plan proceeding to build. Holding a revised plan to a higher standard than the original creates a non-converging loop. If the revisions addressed the substance of previous findings, approve.

If NEEDS_REVISION or REJECTED: update `.claude/current-plan.md` with targeted edits based on the synthesized findings from the 3 lenses. **Do NOT re-enter the review cycle** — the orchestrator handles retries externally.

---

### Plan Review Output

Write the combined review to `.claude/plan-review.md`:

```markdown
## Plan Review (3-Pass)

### Lens 1: Technical Soundness
**Verdict**: [PASS | NEEDS_REVISION]
- [Key findings from technical soundness review]

### Lens 2: Completeness & Gaps
**Verdict**: [PASS | NEEDS_REVISION]
- [Key findings from completeness review]
- [Acceptance criteria gaps identified]
- [Edge cases flagged]

### Lens 3: Simplicity & Over-engineering
**Verdict**: [PASS | NEEDS_REVISION]
- [Key findings from simplicity review]

### Convergence Loop
**Rounds**: [N rounds run | CONVERGED after N rounds | early stop]
- [Summary of improvements made]

### Pass 3: Convergence Synthesis
**Verdict**: [APPROVED | NEEDS_REVISION | REJECTED]
- [Final assessment — do lenses agree? Conflicts? Simpler approach?]

### Overall Verdict: [APPROVED | NEEDS_REVISION | REJECTED]

### Strengths
- [What's good about this plan]

### Required Changes (if NEEDS_REVISION)
1. [Specific change to make to the plan]

### Approved to Proceed: [YES | NO - revise plan first]
```

Source Lens 1 findings from `.claude/review-lens1.md`, Lens 2 findings from `.claude/review-lens2.md`, and Lens 3 findings from `.claude/review-lens3.md`.
