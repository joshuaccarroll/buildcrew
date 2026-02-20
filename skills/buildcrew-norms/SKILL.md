---
name: buildcrew-norms
description: Analyze codebase patterns, conventions, and team norms to generate coding standards
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task
---

# BuildCrew Norms Analysis

Analyze the current codebase and git history to generate team coding conventions. Output goes to `.buildcrew/norms/`.

**If `.buildcrew/norms/` already contains files, overwrite them completely. Do not attempt to merge.**

---

## Phase 1: Static Analysis

Run all four sub-agents in parallel using the Task tool. Cap file sampling at 10 files per category.

### Sub-agent 1: Config & Formatting

```
Spawn a Task sub-agent (general-purpose type) with this prompt:

"Analyze linter, formatter, and editor configurations in this project.

Check for these files (read each one that exists):
- .eslintrc, .eslintrc.js, .eslintrc.json, .eslintrc.yml, eslint.config.js, eslint.config.mjs
- .prettierrc, .prettierrc.js, .prettierrc.json, prettier.config.js
- biome.json, biome.jsonc
- .editorconfig
- tsconfig.json, tsconfig.*.json
- pyproject.toml (look for [tool.ruff], [tool.black], [tool.isort] sections)
- .rubocop.yml
- .golangci.yml, .golangci.yaml
- rustfmt.toml, .rustfmt.toml
- deno.json, deno.jsonc

Report what you found in this exact format:

CONFIGS_FOUND:
[list each config file found and its key settings -- indent size, quote style, semicolons, line length, etc.]

CONFLICTS:
[note any conflicting configs, e.g. both eslint and biome, or contradictory rules. Write NONE if no conflicts.]"
```

### Sub-agent 2: File & Naming Conventions

```
Spawn a Task sub-agent (general-purpose type) with this prompt:

"Analyze file and directory naming conventions in this project.

1. Use Glob to find source files: **/*.{ts,tsx,js,jsx,py,go,rs,rb,java,kt,swift,sh}
2. Sample up to 10 files from different directories
3. Determine naming conventions:
   - File names: PascalCase, camelCase, kebab-case, or snake_case?
   - Directory names: what convention?
   - Test file locations: co-located (same dir), __tests__/, tests/, test/, spec/?
   - Test file naming: *.test.*, *.spec.*, *_test.*, test_*.*?
4. Check import/module style from the sampled files:
   - Import ordering (stdlib > external > internal? alphabetical?)
   - Relative vs absolute imports
   - Named vs default exports (JS/TS)
   - Module aliases (@/, ~/, #/)

Report in this exact format:

FILE_CONVENTIONS:
[file naming pattern with examples]

DIR_CONVENTIONS:
[directory naming pattern]

TEST_LOCATIONS:
[where tests live, with naming pattern]

IMPORT_STYLE:
[import ordering and style conventions]"
```

### Sub-agent 3: Code Patterns & Architecture

```
Spawn a Task sub-agent (general-purpose type) with this prompt:

"Analyze code patterns and architecture in this project.

1. Read up to 10 representative source files (pick from different directories, prefer files with >30 lines)
2. Identify patterns:
   - Function style: arrow functions vs function declarations, async patterns
   - Error handling: try/catch, Result types, error returns, custom error classes
   - Comment style: JSDoc, docstrings, inline comments, header comments
   - State management patterns (if applicable)
   - API/routing patterns (if applicable)
   - Type usage: interfaces vs types, generics patterns, any/unknown usage
3. Scan for shared utilities directories:
   - Check for: utils/, lib/, helpers/, shared/, common/, core/, internal/
   - For each that exists, list the key exports/functions available
   - Note what each utility does (one line per utility)

Report in this exact format:

CODE_PATTERNS:
[function style, error handling, async patterns, type usage]

ARCHITECTURE:
[high-level architecture pattern: MVC, layered, modular, monolith, microservice, etc.]

SHARED_UTILITIES:
[inventory of utils/lib/helpers dirs and their contents. Write NONE if no shared utility directories found.]

COMMENT_STYLE:
[documentation and comment conventions]"
```

### Sub-agent 4: Dependencies & Package Info

```
Spawn a Task sub-agent (general-purpose type) with this prompt:

"Analyze project dependencies and build configuration.

Check for and read these manifest files:
- package.json (note: scripts, dependencies, devDependencies, engines)
- go.mod
- pyproject.toml, setup.py, setup.cfg, requirements.txt, Pipfile
- Cargo.toml
- Gemfile
- composer.json
- pom.xml, build.gradle, build.gradle.kts
- .tool-versions, .node-version, .python-version, .ruby-version, .nvmrc

Also check for:
- Dockerfile, docker-compose.yml (containerization)
- Makefile (build targets)
- CI configs: .github/workflows/*.yml, .gitlab-ci.yml, .circleci/config.yml, Jenkinsfile

Report in this exact format:

PACKAGE_MANAGER:
[npm/yarn/pnpm/pip/poetry/cargo/go modules/bundler/composer/maven/gradle]

KEY_DEPENDENCIES:
[list the 5-10 most important dependencies with their purpose]

DEV_TOOLS:
[linters, formatters, test runners, build tools from devDependencies or equivalent]

BUILD_SYSTEM:
[how the project builds and runs -- scripts, Makefile targets, CI pipeline summary]

VERSIONING:
[version pinning strategy: exact, caret, tilde, ranges. Lock file present? Which one?]"
```

---

## Phase 2: Git & PR Analysis

Run these commands. If any fail (e.g., no git repo, no commits), skip gracefully and note the limitation.

### Git History Analysis

```bash
# Commit message format (recent 50 commits)
git log --oneline -50 2>/dev/null || echo "NO_GIT_HISTORY"

# Team size and contributors
git shortlog -sn --no-merges -20 2>/dev/null || echo "NO_CONTRIBUTORS"

# Merge strategy patterns
git log --merges -20 --oneline 2>/dev/null || echo "NO_MERGES"

# Branch naming (from recent refs)
git branch -r --sort=-committerdate 2>/dev/null | head -20 || echo "NO_REMOTE_BRANCHES"
```

Analyze the output for:
- **Commit format**: conventional commits? (feat:, fix:, chore:), sentence case, lowercase, ticket prefixes?
- **Commit casing**: lowercase, Title Case, UPPERCASE prefix?
- **Team size**: solo developer vs team
- **Merge strategy**: squash, merge commits, rebase, fast-forward?
- **Branch naming**: feature/, fix/, kebab-case, ticket-number prefixes?

### PR Analysis (optional)

Check if `gh` CLI is available AND the repo has a remote:

```bash
# Check gh availability
command -v gh >/dev/null 2>&1 && echo "GH_AVAILABLE" || echo "GH_UNAVAILABLE"

# Check for remote
git remote get-url origin >/dev/null 2>&1 && echo "HAS_REMOTE" || echo "NO_REMOTE"
```

**If both available**, fetch PR data:

```bash
gh pr list --state merged --limit 20 --json title,body,reviews,mergedAt 2>/dev/null || echo "GH_PR_FETCH_FAILED"
```

Analyze for:
- PR title format (conventional? ticket prefix? sentence case?)
- PR body structure (template? sections? checklist?)
- Review patterns (how many reviewers? approval required?)
- Merge strategy (squash, merge, rebase)

**If `gh` unavailable or no remote**: Skip PR analysis entirely. Note in `git-conventions.md`: "PR analysis skipped -- gh CLI unavailable or no remote configured."

---

## Phase 3: Synthesis

Using all data from Phases 1 and 2, write the following files. Each file should be terse, actionable, and use bullet points. Avoid filler.

### Write `.buildcrew/norms/code-style.md`

```markdown
# Code Style Norms

<!-- Generated by BuildCrew norms analysis. Edit freely -- regenerate with /buildcrew norms -->

## Naming
- [file naming convention]
- [variable/function naming convention]
- [class/component naming convention]

## Formatting
- [indent style and size]
- [quote style]
- [semicolons]
- [line length]
- [trailing commas]

## Imports
- [ordering convention]
- [relative vs absolute]
- [aliases]

## File Organization
- [directory structure conventions]
- [where new files of each type should go]
```

### Write `.buildcrew/norms/patterns.md`

```markdown
# Architecture & Pattern Norms

<!-- Generated by BuildCrew norms analysis. Edit freely -- regenerate with /buildcrew norms -->

## Architecture
- [high-level architecture pattern]
- [key architectural boundaries]

## Common Patterns
- [error handling pattern]
- [async/promise pattern]
- [state management pattern]
- [API/routing pattern]

## Shared Utilities
- [utility directory]: [what's available]
- [when to use existing utils vs creating new ones]

## Anti-patterns
- [things to avoid based on codebase conventions]
```

### Write `.buildcrew/norms/testing.md`

If no test framework was detected, write:

```markdown
# Testing Norms

<!-- Generated by BuildCrew norms analysis. Edit freely -- regenerate with /buildcrew norms -->

No test framework detected. When tests are added, update this file with conventions.
```

Otherwise:

```markdown
# Testing Norms

<!-- Generated by BuildCrew norms analysis. Edit freely -- regenerate with /buildcrew norms -->

## Framework
- [test framework and runner]
- [test command]

## File Layout
- [test file location convention]
- [test file naming convention]

## Conventions
- [describe/it vs test style]
- [mocking approach]
- [assertion library/style]
- [setup/teardown patterns]

## Coverage
- [coverage tool if any]
- [coverage requirements if configured]
```

### Write `.buildcrew/norms/git-conventions.md`

If no git history exists, write:

```markdown
# Git Conventions

<!-- Generated by BuildCrew norms analysis. Edit freely -- regenerate with /buildcrew norms -->

No git history available. Conventions will be established as the project develops.
```

Otherwise:

```markdown
# Git Conventions

<!-- Generated by BuildCrew norms analysis. Edit freely -- regenerate with /buildcrew norms -->

## Commits
- [format: conventional/freeform/ticket-prefix]
- [casing convention]
- [scope usage if conventional]

## Branches
- [naming convention]
- [prefix patterns]

## Merge Strategy
- [squash/merge/rebase]

## PR Patterns
- [title format]
- [body structure]
- [review expectations]
```

### Write `.buildcrew/norms/dependencies.md`

```markdown
# Dependency Norms

<!-- Generated by BuildCrew norms analysis. Edit freely -- regenerate with /buildcrew norms -->

## Package Manager
- [which package manager, lock file]

## Versioning Policy
- [pinning strategy]

## Key Packages
- [package]: [purpose/when to use]
- [list 5-10 most important]

## Build & Run
- [how to build]
- [how to run dev]
- [how to run tests]
- [CI pipeline summary if detected]
```

### Write `.buildcrew/norms/NORMS.md`

This is the index file. It **must not exceed 2KB** (~100 lines). Keep entries as terse one-line bullet summaries with pointers to detail files.

```markdown
<!-- Generated by BuildCrew norms analysis. Edit freely -- regenerate with /buildcrew norms -->
# Team Norms

## Code Style (see norms/code-style.md)
- [1-line naming summary]
- [1-line formatting summary]
- [1-line import ordering summary]

## Patterns (see norms/patterns.md)
- [1-line architecture summary]
- [1-line error handling summary]
- [key shared utilities to reuse]

## Testing (see norms/testing.md)
- [1-line framework + location summary]
- [1-line test style summary]

## Git (see norms/git-conventions.md)
- [1-line commit format summary]
- [1-line branch/merge summary]

## Dependencies (see norms/dependencies.md)
- [1-line package manager + key deps]
- [1-line build/run summary]
```

**After writing NORMS.md, verify its size.** Read the file back, count bytes. If it exceeds 2048 bytes, rewrite it with shorter bullet points -- move all detail to the individual files.

---

## NORMS.md Review Loop

After writing all files, run iterative sub-agent review on `NORMS.md` only:

```
iteration = 0
while iteration < 5:
    Spawn a Task sub-agent (general-purpose type) with this prompt:

    "Read .buildcrew/norms/NORMS.md. Review it critically as if you are seeing it for the first time.

    Requirements:
    - Must not exceed 2KB (2048 bytes). Check the file size.
    - Each bullet must be a terse, actionable one-liner
    - Must have pointers to detail files (norms/code-style.md, etc.)
    - No filler, no redundancy, no vague statements
    - Every norm should be specific enough to follow without reading the detail file

    Make concrete improvements directly to the file.

    If the document is solid and no meaningful improvements can be made,
    respond with exactly: CONVERGED

    Do not explain what you reviewed. Either improve the file or respond CONVERGED."

    if sub-agent output contains "CONVERGED":
        break
    iteration += 1
```

---

## Edge Cases

- **Empty/new git repo** (no commits): Skip Phase 2 git analysis entirely. Note in git-conventions.md.
- **Monorepo**: Analyze from current working directory, not repository root. All Glob/Grep calls should search `.` (cwd).
- **No test files found**: Write testing.md noting "No test framework detected" -- do not skip the file.
- **Conflicting configs** (e.g., both .eslintrc and biome.json): Note both configs and flag the conflict in code-style.md.
- **Very large codebases**: Cap file sampling at 10 files per category. Do not attempt to read every source file.
- **NORMS.md size**: If NORMS.md exceeds 2KB after synthesis, trim to bullet-point summaries only.

## Completion

When all `.buildcrew/norms/*.md` files are written and the NORMS.md review loop has finished, the skill is complete. Do not write a phase-result.json -- the caller checks for the existence of `.buildcrew/norms/NORMS.md` to determine success.

---

## Cancellation Handling

If the user interrupts, cancels, or asks to stop at any point during norms analysis:
- Stop all in-progress work immediately
- Respond with: "Norms analysis cancelled."
- Do NOT ask "What should Claude do instead?" or suggest alternative actions
- Do NOT clean up partial files (a partial `.buildcrew/norms/NORMS.md` may remain; the user can re-run `/buildcrew norms` to regenerate cleanly)
- Do not continue with any remaining skill phases

**Limitation**: If the skill is interrupted before its content loads (during "Initializing..."), these instructions will not be in context and Claude Code's default interrupt behavior will apply. The primary mitigation is the `buildcrew` workflow skill (`skills/buildcrew/SKILL.md`), which explicitly prohibits invoking `buildcrew-norms` during workflow execution.
