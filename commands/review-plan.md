Save the current plan to a md file if not already saved. Then use the Task tool to spawn a sub-agent to iteratively review and improve it.

## Instructions

1. **Identify the document to review**:
   - If a plan file already exists (e.g., `.claude/current-plan.md`, `PROJECT_*.md`, or another plan document), use that file
   - If the plan content is only in the conversation (e.g., from plan mode), write it to a `.md` file first

2. **Run iterative sub-agent review** (up to 5 iterations):

```
iteration = 0
converged = false
while iteration < 5:
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

3. **Report results**:
   - State how many iterations were run
   - Whether convergence was reached
   - Summarize the key changes made across iterations
