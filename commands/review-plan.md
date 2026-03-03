Save the current plan to a md file if not already saved. Then use the Task tool to spawn sub-agents to iteratively review and improve it.

## Instructions

1. **Identify the document to review**:
   - If a plan file already exists (e.g., `.claude/current-plan.md`, `PROJECT_*.md`, or another plan document), use that file
   - If the plan content is only in the conversation (e.g., from plan mode), write it to a `.md` file first

2. **Ensure `.claude/` directory exists**:
   - Run `mkdir -p .claude` before proceeding

3. **Round 1 — Parallel focused lenses** (3 agents simultaneously):

In a **single response**, spawn all 3 Task sub-agents (general-purpose type) simultaneously. Do not wait for one to finish before starting the next.

**Sub-Agent 1 — Technical Soundness:**

Spawn a Task sub-agent (general-purpose type) with this prompt (substitute `[FILE_PATH]` with the actual plan file path):

```
Read [FILE_PATH]. You are reviewing this plan for Technical Soundness only.
Evaluate: Is the scope right? Does the architecture fit? Are steps ordered correctly (foundations before features)? Is each step verifiable? Will any step produce artifacts that strain context windows?

Write your top 3-5 findings to .claude/review-lens-technical.md. Max 60 lines.
Format: one finding per section with a one-line fix suggestion.
Do NOT modify the plan file. Do NOT explore the codebase — review the plan document only.

If the plan is solid in this lens with no meaningful findings,
write a single line to .claude/review-lens-technical.md: NO_FINDINGS
```

**Sub-Agent 2 — Completeness & Gaps:**

Spawn a Task sub-agent (general-purpose type) with this prompt:

```
Read [FILE_PATH]. You are reviewing this plan for Completeness & Gaps only.
Evaluate: What edge cases are missing? What acceptance criteria are too vague to verify? What prerequisites aren't mentioned? What happens when something fails halfway?

Write your top 3-5 findings to .claude/review-lens-gaps.md. Max 60 lines.
Format: one finding per section with a one-line fix suggestion.
Do NOT modify the plan file. Do NOT explore the codebase — review the plan document only.

If the plan is solid in this lens with no meaningful findings,
write a single line to .claude/review-lens-gaps.md: NO_FINDINGS
```

**Sub-Agent 3 — Simplicity & Over-engineering:**

Spawn a Task sub-agent (general-purpose type) with this prompt:

```
Read [FILE_PATH]. You are reviewing this plan for Simplicity & Over-engineering only.
Evaluate: What would you cut to ship in half the time? What abstractions serve hypothetical futures? What could be replaced with a simpler approach?

Write your top 3-5 findings to .claude/review-lens-simplicity.md. Max 60 lines.
Format: one finding per section with a one-line fix suggestion.
Do NOT modify the plan file. Do NOT explore the codebase — review the plan document only.

If the plan is solid in this lens with no meaningful findings,
write a single line to .claude/review-lens-simplicity.md: NO_FINDINGS
```

4. **Apply Round 1 findings** (parent agent — not a sub-agent):

After all 3 sub-agents complete, read the lens report files:
- `.claude/review-lens-technical.md`
- `.claude/review-lens-gaps.md`
- `.claude/review-lens-simplicity.md`

If any file is missing, log a warning ("Lens agent failed to produce output: [filename]") and treat as no findings.

For each file that exists and does NOT contain only `NO_FINDINGS`:
- Apply the substantive findings directly to the plan file
- Skip nitpicks and minor style suggestions

After applying findings, delete the lens report files (`.claude/review-lens-*.md`).

5. **Rounds 2-4 — Serial convergence** (up to 3 iterations):

```
iteration = 0
converged = false
while iteration < 3:
    Launch a Task sub-agent (general-purpose type) with this prompt:

    "Read [FILE_PATH]. Review it critically as if you are seeing it for the first time.
    Look for: gaps, missing details, unclear sections, over-engineering, incorrect assumptions,
    missing edge cases, and areas that could be improved.

    Make concrete improvements directly to the file. Be specific and substantive --
    do not add filler or unnecessary content.

    If the document is solid and no meaningful improvements can be made,
    respond with exactly: CONVERGED

    Do not explain what you reviewed. Either improve the file or respond CONVERGED."

    if sub-agent output contains "CONVERGED":
        converged = true
        break
    iteration += 1
```

6. **Report results**:
   - How many lens agents produced findings in round 1
   - How many serial iterations ran
   - Whether convergence was reached
   - Summarize the key changes made across all rounds
