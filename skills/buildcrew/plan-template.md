# Implementation Plan Template

Use this template when creating plans in the plan phase of the workflow.

---

# Implementation Plan: [Task Title]

## Summary
[1-2 sentence description of what will be built and why]

## Context
- **Task Source**: Backlog item
- **Related Files**: [files that will inform the implementation]
- **Existing Patterns**: [patterns from the codebase to follow]

## Human Prerequisites
[Anything the human must do before or during implementation -- account creation, API keys, DNS, service setup. "None" if not applicable.]
- [ ] [e.g., Create account on X service]
- [ ] [e.g., Obtain API key for Y]

## Files to Modify
| File | Changes |
|------|---------|
| `path/to/file.ts` | [description of changes] |

## Files to Create
| File | Purpose |
|------|---------|
| `path/to/new.ts` | [what this file will contain] |

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

## Testing Strategy
- **Unit Tests**: [what to test]
- **Integration Tests**: [if applicable]
- **Manual Verification**: [how to verify it works]

## Dependencies & Ordering Rationale
- [Any prerequisites that must be done first]
- [External dependencies needed]
- **Why this order**: [Explain why steps are sequenced this way]

## Risks & Mitigation
| Risk | Impact | Mitigation |
|------|--------|------------|
| [Risk 1] | [High/Medium/Low] | [How to handle] |

## Out of Scope
- [Things explicitly NOT being done in this task]

---

## Notes for Claude

When filling out this template:

1. **Be specific**: Use exact file paths and function names
2. **Reference existing code**: Point to similar implementations
3. **Keep it actionable**: Each step should be executable
4. **Consider edge cases**: Note them in the risks section
5. **Stay focused**: Only plan what the task requires
6. **Order for testability**: Put foundations, infrastructure, and human-required actions first. For migrations, do a zero-change migration before adding features. Each step should produce a verifiable state.
