---
name: buildcrew-research
description: BuildCrew Research + Plan phases — gather context and create implementation plan
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task, WebSearch, WebFetch
---

# BuildCrew — Research + Plan

`[Phases: research, plan | Input: task description | Output: .claude/research.md, .claude/current-plan.md | Next: plan-review]`

> **Context budget**: The research document feeds directly into plan writing.
> Keep it under 150 lines. Prefer URLs over pasted documentation.
> Prefer code snippets (10-20 lines) over prose descriptions of APIs.
> If you are pasting more than 30 lines of external content, summarize it instead.

You are executing the research and plan phases of the BuildCrew autonomous development workflow.

## Your Task

The task was provided in the prompt. Parse it and understand what needs to be built.

> **Retrieval-led reasoning**: Always read actual project files, configs, and dependencies. Never assume API signatures, framework behavior, or library versions from training data. When in doubt, read the file.

---

## RESEARCH

**Goal**: Gather external and local context relevant to the task before planning.

### Steps:

1. **Parse the task**: Identify research topics — APIs, libraries, frameworks, patterns, integrations, domain concepts, or external services mentioned or implied by the task
2. **Assess research depth**:
   - **Light research** (internal tasks — refactoring, renaming, config changes, bug fixes with no new external dependencies): Skip web research. Explore the local codebase only and write a brief `.claude/research.md` with local context, then proceed to the plan phase.
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

## UX Impact
*(Skip body for internal tasks — replace with: `N/A — internal/refactoring task with no user-visible behavior changes.`)*
- **User roles affected**: [who]
- **Touch points**: [what the user interacts with]
- **Error experience**: [what the user sees when something goes wrong]
- **Minimum viable surface**: [fewest UI/CLI elements that deliver the value]

## Sources
- [URL 1]
- [URL 2]
```

**For internal-only tasks**, use a minimal research document:

```markdown
# Research: [Task Title]

## Local Context
- [Relevant files, patterns, constraints found in the codebase]
- [Existing utilities to reuse]

## Implementation Notes
- [Key decisions, gotchas, ordering constraints]
```

### Error Handling

- If WebSearch is unavailable or returns no results, proceed with local-only research. Note the limitation in the research document.
- If WebFetch fails on specific URLs, log the URLs as "could not fetch" in the Sources section and continue.
- The research phase should never block the workflow — always produce a `.claude/research.md`, even if it only contains local context.

### Step 8b: UX Consideration (user-facing tasks only)

Before proceeding to the plan phase, consider the user experience for any task that has
user-visible behavior changes:

1. **Who touches this?** Which user roles interact with this feature (end user, developer, admin, CI system)?
2. **What do they see?** For each touch point: what do they click/type? What feedback do they get? What happens on error?
3. **What is the minimum viable surface?** Resist adding options, flags, config, or UI elements unless the spec explicitly requires them. The simplest UX that delivers the value is the right UX.

**User-facing** means any change that modifies: CLI output, command-line flags, error messages, or any behavior observable by a person running the tool. If in doubt, apply this step — the cost of UX consideration for an internal task is low; the cost of missing it is high. Skip this step only for tasks with zero observable behavior changes (e.g., pure refactors with no output changes, internal data structure changes with no CLI/output impact).

Populate the `## UX Impact` section in the template above with task-specific content. For user-facing tasks, fill in all four fields. If this task is not user-facing per the definition above, replace the section body with: `N/A — internal/refactoring task with no user-visible behavior changes.`

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

    Also read `.claude/spec.md` to understand whether this task has user-visible behavior changes. Then check: if the task is user-facing per the definition in Step 8b, does `research.md` contain a `## UX Impact` section with all four fields populated (not just the N/A marker)? If missing, sparse, or replaced with N/A when the task is clearly user-facing, flag it and recommend the researcher revisit Step 8b.

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

## PLAN

**Goal**: Understand the task and create a detailed implementation plan.

### Steps:

1. **Load research findings**: Read `.claude/research.md` from the Research phase. Use the key findings, API docs, local context, and constraints to inform your plan.
2. **Analyze the task**: Break down what needs to be done
3. **Identify human prerequisites**: Surface anything the human must do -- account creation, API keys, DNS configuration, external service setup, purchasing, approvals. These go in a dedicated plan section and should be sequenced as early as possible.
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
   - **Order steps using these principles**:
     1. Human prerequisites and external setup first (things that block the human)
     2. Infrastructure, platform, and environment setup before feature work
     3. Zero-change migrations before functional changes (migrate first, verify, then iterate)
     4. Each step should produce a verifiable state -- include a "Verify" line after each step
6. **Identify risks**: Note anything unclear or potentially problematic

### Plan Template

Write your plan to `.claude/current-plan.md` using this structure:

```markdown
# Implementation Plan: [Task Title]

## Summary
[1-2 sentence description of what will be built]

## Research Context
[Key findings from .claude/research.md that inform this plan]

## Human Prerequisites
[Anything the human must do before or during implementation -- account creation, API keys, DNS, service setup. "None" if not applicable.]
- [ ] [e.g., Create account on X service]
- [ ] [e.g., Obtain API key for Y]

## Files to Modify
- `path/to/file.ts` - [what changes]
- `path/to/other.ts` - [what changes]

## Files to Create
- `path/to/new.ts` - [purpose]

## Implementation Steps

> Order: foundations/infrastructure first, human-blocked items first, zero-change migrations before feature work. Each step should produce a verifiable state.

### Step 1: [Name]
- [ ] Sub-task 1
- [ ] Sub-task 2
- **Verify**: [What to check before moving to Step 2]

### Step 2: [Name]
- [ ] Sub-task 1
- [ ] Sub-task 2
- **Verify**: [What to check before moving to Step 3]

## Architecture Notes
- [How this fits into the existing architecture]
- [Patterns being followed]

## Testing Strategy
- [How to verify this works]
- [Test types needed: unit, integration, e2e]
- **Interface contracts for TDD**: [Public interfaces — functions, CLI commands, API endpoints — that tests can exercise before implementation exists]
- **TDD-exempt areas**: [Anything untestable before implementation — visual, perf, etc.]

## Dependencies & Ordering Rationale
- [Any prerequisites that must be done first]
- [External dependencies needed]
- **Why this order**: [Explain why steps are sequenced this way]

## Risks/Notes
- [Any concerns or open questions]
```

After writing the plan, assess whether human review is recommended based on these objective criteria (any = true):
- Task description mentions "breaking change", "migration", or "deprecation"
- Plan involves platform migration, replatforming, or infrastructure-first sequencing where ordering errors could waste the entire build
- Plan modifies more than 10 files
- Plan involves security-sensitive areas (auth, crypto, secrets, permissions)
- Plan changes public APIs, CLI interfaces, or database schemas

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
