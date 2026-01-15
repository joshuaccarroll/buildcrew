---
name: josh-workflow
description: Execute a complete development workflow for a backlog task. Use this when asked to execute the josh-workflow or process a backlog item through plan, build, review, test, and commit phases.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task, Skill
---

# Josh Workflow - Autonomous Development Cycle

You are executing an autonomous development workflow. Follow each phase in order, completing all steps before moving to the next phase. This workflow is designed to run without human intervention.

## Current Task

The task you are working on was provided in the prompt. Parse it and understand what needs to be built.

## Phase 1: PLAN

**Goal**: Understand the task and create a detailed implementation plan.

### Steps:

1. **Analyze the task**: Break down what needs to be done
2. **Explore the codebase**: Use Glob and Grep to find relevant files
   - Look for similar implementations to follow existing patterns
   - Identify files that will need modification
   - Check for existing tests you can model yours after
3. **Create implementation plan**: Write a step-by-step plan to `.claude/current-plan.md`
   - List all files to create or modify
   - Describe each change needed
   - Note any dependencies or order requirements
4. **Identify risks**: Note anything unclear or potentially problematic

### Plan Template

Write your plan to `.claude/current-plan.md` using this structure:

```markdown
# Implementation Plan: [Task Title]

## Summary
[1-2 sentence description of what will be built]

## Files to Modify
- `path/to/file.ts` - [what changes]
- `path/to/other.ts` - [what changes]

## Files to Create
- `path/to/new.ts` - [purpose]

## Implementation Steps
1. [First step]
2. [Second step]
...

## Testing Strategy
- [How to verify this works]

## Risks/Notes
- [Any concerns or open questions]
```

## Phase 2: BUILD

**Goal**: Implement the changes according to your plan.

### Steps:

1. **Follow your plan**: Execute each step in `.claude/current-plan.md`
2. **Use appropriate skills**:
   - For UI/frontend work, invoke the `frontend-design` skill
   - For backend/API work, follow existing patterns in the codebase
3. **Write code incrementally**: Make small, focused changes
4. **Keep changes atomic**: Each edit should be self-contained

### Guidelines:
- Follow existing code patterns and conventions in the project
- Use TypeScript/type annotations if the project uses them
- Keep functions small and focused
- Add comments only where logic isn't self-evident
- Don't over-engineer - implement only what's needed

## Phase 3: REVIEW

**Goal**: Ensure code quality by checking against coding principles.

### Steps:

1. **Read principles**: Load `.claude/rules/coding-principles.md`
2. **Review all changes**: For each modified file:
   - Check against DRY - is there repeated code that should be extracted?
   - Check against SOLID - does each function/class have a single responsibility?
   - Check against KISS - is there unnecessary complexity?
   - Check security - are inputs validated? No hardcoded secrets?
3. **Document violations**: List any issues found
4. **Read project-specific rules**: Check for additional rules in `.claude/rules/`

### Review Checklist

Use `.claude/skills/josh-workflow/review-checklist.md` for detailed criteria.

## Phase 4: REFACTOR

**Goal**: Fix any issues found during review.

### Steps:

1. **Prioritize fixes**: Address security issues first, then DRY, then style
2. **Make targeted changes**: Fix only the violations, don't expand scope
3. **Verify fixes**: Re-check each fix against the principle it violated
4. **Keep commits clean**: Refactoring should be minimal and focused

**Skip this phase if no violations were found in Phase 3.**

## Phase 5: TEST

**Goal**: Verify the implementation works correctly.

### Steps:

1. **Detect test framework**: Look for jest.config, pytest.ini, go.mod, Cargo.toml, etc.
2. **Run existing tests**: Execute the project's test suite
   ```bash
   # Try common test commands based on project type
   npm test        # Node.js/JavaScript
   yarn test       # Yarn projects
   pytest          # Python
   go test ./...   # Go
   cargo test      # Rust
   make test       # Makefile projects
   ```
3. **On failure**:
   - Analyze the error message
   - Identify the root cause
   - Fix the issue
   - Re-run tests
   - **Retry up to 3 times** before marking as blocked
4. **Add new tests if appropriate**: For significant new functionality

### Test Retry Logic

```
attempt = 1
while tests_fail and attempt <= 3:
    analyze_failure()
    apply_fix()
    run_tests()
    attempt += 1

if tests_still_fail:
    mark_task_blocked("Tests failing after 3 attempts")
```

## Phase 6: COMMIT

**Goal**: Create a meaningful commit with all changes.

### Steps:

1. **Stage changes**: `git add` all relevant files
2. **Generate commit message**: Use conventional commit format
   ```
   type(scope): brief description

   - Detail 1
   - Detail 2

   Task: [original task description]
   ```
3. **Create commit**: Do NOT push (local only)

### Commit Types:
- `feat`: New feature
- `fix`: Bug fix
- `refactor`: Code restructuring
- `test`: Adding tests
- `docs`: Documentation changes
- `style`: Formatting, whitespace
- `chore`: Maintenance tasks

## Phase 7: SIGNAL COMPLETION

**Goal**: Signal to the orchestrator that this task is complete.

### Steps:

1. **Write status file**: Create `.claude/workflow-status.json`

**On Success:**
```json
{
  "status": "complete",
  "task": "[original task]",
  "summary": "[brief summary of what was done]",
  "files_changed": ["list", "of", "files"],
  "commit": "[commit hash if available]"
}
```

**On Failure/Blocked:**
```json
{
  "status": "blocked",
  "task": "[original task]",
  "reason": "[why it couldn't be completed]",
  "attempted": "[what was tried]",
  "needs": "[what's needed to unblock]"
}
```

2. **Clean up**: Remove `.claude/current-plan.md` (optional, for cleanliness)

---

## Important Reminders

- **Stay focused**: Only implement what the task requires
- **Follow patterns**: Match the existing codebase style
- **Be thorough**: Complete all phases before signaling completion
- **Handle errors gracefully**: Mark as blocked rather than failing silently
- **Don't push**: Only commit locally, never push to remote
- **Signal completion**: Always write the status file at the end
