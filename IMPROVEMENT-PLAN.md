# BuildCrew Improvement Plan

## Items

### 1. Create CLAUDE.md
Create a project-level CLAUDE.md for self-development quality. Content agreed upon — the tightened version covering the file monitor signal flow, file-based communication contracts, key files, conventions, and hard rules.

### 2. Remove legacy mode
Remove the single-invocation fallback entirely. Instead of silently degrading, fail clearly with an actionable error: "Phase-isolated skills not found. Run `buildcrew init` to install them."

### 3. Named phases
Replace all numbered phase references (Phase 1, Phase 2, etc.) with named phases throughout skill files, workflow.sh, and documentation. Agreed names:
- spec
- research
- plan
- plan-review
- build
- code-review
- refactor
- verify
- commit

Note: The `outcome` and `test` phases have been absorbed into `verify`.

### 4. Refactor adversarial review into reusable skill
Extract the review logic from buildcrew-review into a proper reusable skill with fresh-context subagents (PE + PM independently, then convergence synthesis). Remove the Phase 2 self-review loops — they are redundant with Phase 3. Update `/review-plan` command to be a thin wrapper around the same skill.

Architecture:
- `skills/buildcrew-review/SKILL.md` — real logic (fresh-context subagents, adversarial passes, convergence)
- `commands/review-plan.md` — thin wrapper: invoke buildcrew-review on current-plan.md
- Phase plan-review — directly invokes buildcrew-review skill (same code, same behavior)

### 5. Configurable MAX_INVOCATIONS
Make the global invocation ceiling configurable — passable as a CLI flag and/or settable in project config. Remove the hardcoded 15.

### 6. Verbose/debug mode
Add `--verbose` or `--debug` flag to `buildcrew run` that shows orchestrator-level decisions: which phase is running, why a circuit breaker fired, how many invocations have been used. Currently requires manual inspection of hidden JSON files.

### 7. Skill update propagation fix
After `buildcrew update` pulls new global files, if the current directory is an initialized project (detected by presence of `.buildcrew/`), automatically refresh symlinks — removing dead ones and creating new ones for added skills. If not in an initialized project, print a reminder to run `buildcrew init`.

---

## Order of execution
1. CLAUDE.md
2. Remove legacy mode
3. Named phases
4. Refactor adversarial review (+ remove Phase 2 self-review loops)
5. Configurable MAX_INVOCATIONS
6. Verbose/debug mode
7. Skill update propagation fix
