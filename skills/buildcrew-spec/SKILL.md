---
name: buildcrew-spec
description: BuildCrew Specification Refinement phase — convert raw backlog items into structured, testable specs
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task
---

# BuildCrew — Specification Refinement

`[Phase: spec | Input: task description | Output: .claude/spec.md | Next: RESEARCH]`

> **Context budget**: This spec is read by every subsequent phase. Keep it under 200 lines.
> If it's getting long, the task scope is probably too large — revisit "Out of Scope."

You are executing the spec phase of the BuildCrew autonomous development workflow.

## Your Task

The task was provided in the prompt. Your job is to convert this raw backlog item into a structured specification before any research or planning begins.

---

## SPEC: Specification Refinement (Product Manager)

**Goal**: Transform a raw backlog item into a precise, testable specification that every subsequent phase can anchor to.

**Persona**: You are the **Product Manager**. You ask the hard questions before anyone writes a line of code.

### Step 1: Assess Clarity

Before writing anything, assess whether this task is specific enough to produce clear acceptance criteria.

**Sufficient clarity** (proceed to spec):
- Task describes a concrete user-facing behavior or outcome
- The definition of "done" is at least partially inferrable
- You can write at least 2 testable acceptance criteria

**Insufficient clarity** (flag and skip):
- Task is purely aspirational with no concrete behavior described (e.g., "improve performance")
- Task refers to undefined external artifacts (e.g., "implement the thing we discussed")
- Task is ambiguous enough that 2 engineers would build completely different features
- Task describes multiple unrelated outcomes (e.g., "add login AND redesign the dashboard") — recommend splitting into separate backlog items, each with its own spec

If the task is **insufficient**, write `.claude/spec.md` with a `VAGUE` verdict:

```markdown
# Specification: [Task Title]

## Verdict: VAGUE

## Why This Item Was Flagged
[Specific reason — what information is missing that prevents writing acceptance criteria]

## What to Clarify
- [Question 1 that needs answering before this can proceed]
- [Question 2]

## Suggested Rewrite
[A more specific version of the task that could proceed]
```

Then write `.claude/phase-result.json` with `verdict: "vague"` and `details` explaining the issue. Log the reason clearly.

### Step 2: Explore Context (for sufficient tasks)

Before writing the spec:

1. **Read the codebase** (lightly): Understand what already exists relevant to this task. Use Glob/Grep to find related files.
2. **Read project context**: Check `.buildcrew/context/principles.md`, `.buildcrew/context/users.md`, and `.buildcrew/context/domain.md` if they exist.

### Step 3: Write the Specification

Write a concise spec to `.claude/spec.md`. The spec must answer these five questions:

1. **What exact behavior should exist when this is done?**
2. **What does "done" look like from the user's perspective?**
3. **What should explicitly NOT be built?** (scope boundaries)
4. **Testable acceptance criteria** — concrete pass/fail checks, not vague goals
5. **The One Thing**: What is the single primary deliverable? State it in one sentence.
   If the sentence requires "and" to connect unrelated deliverables, the scope is too large.
   Note the split in "Out of Scope" and recommend creating a separate task.

Keep the spec focused and brief. No rigid template with dozens of fields — just a simple markdown document structured around these four answers.

### Spec Template

```markdown
# Specification: [Task Title]

## Summary
[1-3 sentences. Exact behavior when done. Inputs, outputs, triggers, state changes.]

## User Experience
[One short paragraph. "When a user does X, they see Y. They can now Z."]

## Out of Scope
- [NOT being built]
- [Belongs in a separate task]

**This task delivers**: [one sentence — the single primary deliverable]

## Acceptance Criteria
- [ ] AC-01: [Specific, verifiable condition]
- [ ] AC-02: [Another verifiable condition]
- [ ] AC-03: [Edge case or error condition]
```

### Acceptance Criteria Writing Rules

**Good AC** (specific, verifiable):
- ✓ "AC-01: Running `buildcrew run --dry-run` with 3 pending tasks prints exactly 3 `[DRY RUN] Would execute` lines and exits 0"
- ✓ "AC-02: When the spec phase produces `verdict: vague`, the task is marked blocked in BACKLOG.md with a descriptive reason"
- ✓ "AC-03: Running `buildcrew lessons` with an empty lessons.md prints 'No lessons recorded yet'"

**Bad AC** (vague, untestable):
- ✗ "The feature works correctly"
- ✗ "Performance is improved"
- ✗ "Users can use the feature"

**Minimum**: 2 acceptance criteria. **Maximum**: 8 (if you need more, the task scope is too large — note this in Out of Scope).

### Formatting Norms

- **No narrative**: Use bullet points and short sentences. Specs are reference documents.
- **No repeated context**: Do not restate the task description. The task is already known.
- **One behavior per AC**: Do not combine checks. "Login works and redirects" is two ACs.
- **ACs are the contract**: If a behavior matters, it must be in an AC. If it's not in an AC,
  it will not be verified at outcome time.
- **Tables over prose**: For multi-step behaviors or comparisons, use a table.

### Step 4: Iterative Spec Review (up to 5 iterations)

Run iterative sub-agent review until convergence:

```
iteration = 0
while iteration < 5:
    Spawn a Task sub-agent (general-purpose) with this prompt:

    "Read .claude/spec.md. You are a QA engineer reviewing this spec for the first time.

    Apply the contractor test: Could a capable contractor in a different timezone
    build this correctly without asking a single question? If the answer is no for
    any acceptance criterion, rewrite it until the answer is yes.

    Also check:
    - Are all ACs binary pass/fail? Could a test definitively pass or fail each one?
    - Is anything in the description vague enough to be interpreted two different ways?
    - Does 'Out of Scope' cover the most likely scope-creep risks?
    - Are there obvious edge cases or error conditions missing from ACs?
    - Is each AC specific about inputs, outputs, commands, and expected results?
    - Is the spec under 200 lines total? Prefer concise, testable ACs over exhaustive prose.

    Make concrete improvements directly to the file.

    If the spec passes the contractor test and no meaningful improvements remain,
    respond with exactly: CONVERGED

    Do not explain what you reviewed. Improve the file or respond CONVERGED."

    if sub-agent output contains "CONVERGED":
        break
    iteration += 1
```

---

## Phase Result Protocol

**If spec was written successfully:**
```json
{
  "phase": "spec",
  "verdict": "complete",
  "details": "Specification written with N acceptance criteria"
}
```

**If task was too vague to spec:**
```json
{
  "phase": "spec",
  "verdict": "vague",
  "details": "Task too vague to produce acceptance criteria: [reason]. Flagged in spec.md."
}
```

Then exit.
