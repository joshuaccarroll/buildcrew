---
name: buildcrew-research
description: BuildCrew Research + Plan phases — gather context and create implementation plan
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task, WebSearch, WebFetch
---

# BuildCrew — Research + Plan

`[Phases 1-2/10: RESEARCH + PLAN | Input: task description | Output: .claude/research.md, .claude/current-plan.md | Next: PLAN_REVIEW]`

You are executing phases 1-2 of the BuildCrew autonomous development workflow.

## Your Task

The task was provided in the prompt. Parse it and understand what needs to be built.

> **Retrieval-led reasoning**: Always read actual project files, configs, and dependencies. Never assume API signatures, framework behavior, or library versions from training data. When in doubt, read the file.

---

## Phase 1: RESEARCH

**Goal**: Gather external and local context relevant to the task before planning.

### Steps:

1. **Parse the task**: Identify research topics — APIs, libraries, frameworks, patterns, integrations, domain concepts, or external services mentioned or implied by the task
2. **Assess research depth**:
   - **Light research** (internal tasks — refactoring, renaming, config changes, bug fixes with no new external dependencies): Skip web research. Explore the local codebase only and write a brief `.claude/research.md` with local context, then proceed to Phase 2.
   - **Full research** (tasks involving external APIs, new libraries, unfamiliar patterns, or integration work): Proceed with steps 4-6.

### Steps 4-5: Web Research (via Sub-Agent)

If full research is needed, launch a Task sub-agent (general-purpose type).
Prompt it with the research topics and template. It searches, fetches, and
returns structured findings. Incorporate into research.md.

### Step 6: Codebase Exploration (via Sub-Agent)

Launch a Task sub-agent (Explore type). Prompt it with patterns to search for.
It returns file paths, patterns found, dependency versions, constraints.
Incorporate into research.md.

### Step 7: Write Research Findings

Save to `.claude/research.md` using the template below. Be extremely concise. Sacrifice grammar for the sake of concision.

### Step 8: Flag Critical Discoveries

If research reveals something that fundamentally changes the task (e.g., an API is deprecated, a library has been abandoned, there's a much simpler approach), call this out prominently in the Key Findings section.

### Research Document Template

For tasks requiring full research:

```markdown
# Research: [Task Title]

## Research Topics
- [Topic 1 inferred from task]
- [Topic 2 inferred from task]

## Key Findings
- [Most important discovery]
- [Second most important discovery]

## API & Library Documentation
### [API/Library Name]
- **Docs**: [URL]
- **Key points**: [Relevant details]
- **Example usage**: [Code snippet if applicable]

## Alternative Approaches
| Approach | Pros | Cons | Recommendation |
|----------|------|------|----------------|
| [Approach 1] | ... | ... | ... |

## Local Codebase Context
- [Relevant existing patterns found]
- [Current stack/dependency info]
- [Constraints from existing architecture]

## Constraints & Gotchas
- [Known issues, breaking changes, deprecations]

## Sources
- [URL 1]
- [URL 2]
```

For internal-only tasks (light research):

```markdown
# Research: [Task Title]

## Research Topics
- No external APIs, libraries, or patterns to research

## Local Codebase Context
- [Relevant existing patterns found]
- [Current stack/dependency info]

## Key Findings
- This task is internal to the codebase; no external research required.
```

### Error Handling

- If WebSearch is unavailable or returns no results, proceed with local-only research. Note the limitation in the research document.
- If WebFetch fails on specific URLs, log the URLs as "could not fetch" in the Sources section and continue.
- The research phase should never block the workflow — always produce a `.claude/research.md`, even if it only contains local context.

After writing the research document, run iterative sub-agent review on `.claude/research.md`:

```
iteration = 0
while iteration < 5:
    Spawn a Task sub-agent (general-purpose type) with this prompt:

    "Read .claude/research.md. Review it critically as if you are seeing it for the first time.
    Look for: gaps, missing details, unclear sections, over-engineering, incorrect assumptions,
    missing edge cases, and areas that could be improved.

    Make concrete improvements directly to the file. Be specific and substantive --
    do not add filler or unnecessary content.

    If the document is solid and no meaningful improvements can be made,
    respond with exactly: CONVERGED

    Do not explain what you reviewed. Either improve the file or respond CONVERGED."

    if sub-agent output contains "CONVERGED":
        break
    iteration += 1
```

---

## Compaction Checkpoint

Your research is captured in .claude/research.md. For the Plan phase below,
reference that file. Do not re-search or re-explore.

---

## Phase 2: PLAN

**Goal**: Understand the task and create a detailed implementation plan.

### Steps:

1. **Load research findings**: Read `.claude/research.md` from the Research phase. Use the key findings, API docs, local context, and constraints to inform your plan.
2. **Analyze the task**: Break down what needs to be done
4. **Explore the codebase**: Use Glob and Grep to find relevant files
   - Look for similar implementations to follow existing patterns
   - Identify files that will need modification
   - Check for existing tests you can model yours after
5. **Create implementation plan**: Write a step-by-step plan to `.claude/current-plan.md`. Be extremely concise. Sacrifice grammar for the sake of concision.
   - List all files to create or modify
   - Describe each change needed
   - Note any dependencies or order requirements
   - Reference relevant project context (users, principles, domain) when applicable
   - Include a "Research Context" section summarizing key findings from `.claude/research.md`
6. **Identify risks**: Note anything unclear or potentially problematic

### Plan Template

Write your plan to `.claude/current-plan.md` using this structure:

```markdown
# Implementation Plan: [Task Title]

## Summary
[1-2 sentence description of what will be built]

## Research Context
[Key findings from .claude/research.md that inform this plan]

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

After writing the plan, run iterative sub-agent review on `.claude/current-plan.md`:

```
iteration = 0
converged = false
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

    if sub-agent output contains "CONVERGED":
        converged = true
        break
    iteration += 1
```

After the review loop completes, assess whether human review is recommended based on these objective criteria (any = true):
- Task description mentions "breaking change", "migration", or "deprecation"
- Plan modifies more than 10 files
- Plan involves security-sensitive areas (auth, crypto, secrets, permissions)
- Plan changes public APIs, CLI interfaces, or database schemas
- The review sub-agents did NOT converge within 5 iterations (the `converged` flag is false after the loop)

---

## Phase Result Protocol

When both Research and Plan are complete, write `.claude/phase-result.json`:

```json
{
  "phase": "research_and_plan",
  "verdict": "complete",
  "human_review": true,
  "human_review_reason": "Plan modifies 14 files and changes CLI interface",
  "details": "Research and plan written"
}
```

Include `human_review: true` and a `human_review_reason` string when any of the objective criteria above are met. When `human_review` is false or absent, omit `human_review_reason`.

Then exit.
