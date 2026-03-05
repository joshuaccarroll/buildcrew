---
name: simplify-all
description: Review and clean up an entire codebase for reuse, quality, and efficiency issues
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task
---

# Simplify All — Whole-Codebase Review & Cleanup

You are performing a comprehensive code review and cleanup of an entire codebase (or a targeted subset). This is a standalone tool — it is not part of any buildcrew phase pipeline.

## Your Task

The task was provided in the prompt. If the user specified paths, directories, or file globs, scope your review to those. Otherwise, review the entire project.

---

## Step 1: Determine Scope

### If the user specified paths or globs in the prompt:
Use exactly those paths. Expand any globs and collect the file list.

### If no paths were specified (whole-project mode):
Discover all source files using Bash:

```bash
find . -type f \
  ! -path '*/.git/*' \
  ! -path '*/node_modules/*' \
  ! -path '*/vendor/*' \
  ! -path '*/dist/*' \
  ! -path '*/build/*' \
  ! -path '*/__pycache__/*' \
  ! -path '*/.next/*' \
  ! -path '*/.cache/*' \
  ! -path '*/.claude/*' \
  ! -path '*/.buildcrew/*' \
  ! -path '*/coverage/*' \
  ! -path '*/.venv/*' \
  ! -path '*/venv/*' \
  ! -name '*.lock' \
  ! -name 'package-lock.json' \
  ! -name 'yarn.lock' \
  ! -name '*.min.js' \
  ! -name '*.min.css' \
  ! -name '*.map' \
  ! -name '*.png' ! -name '*.jpg' ! -name '*.jpeg' ! -name '*.gif' ! -name '*.ico' ! -name '*.svg' \
  ! -name '*.woff' ! -name '*.woff2' ! -name '*.ttf' ! -name '*.eot' \
  ! -name '*.pyc' ! -name '*.o' ! -name '*.so' ! -name '*.dylib' \
  | head -500
```

Count the files. If there are more than 200 source files, tell the user the count and ask whether to proceed with all files or narrow the scope. If the user confirms, proceed. If >500 files, warn that the review will be thorough but may take several minutes.

Store the file list for use in sub-agent prompts.

---

## Step 2: Dispatch Parallel Review Sub-Agents

In a **single response**, spawn all 3 Task sub-agents (general-purpose type) simultaneously. Do not wait for one to finish before starting the next.

Pass the file list (or path scope) to each sub-agent so they know exactly what to review.

**Sub-Agent 1 — Reuse Analyst:**

Spawn a Task sub-agent (general-purpose type) with this exact prompt (substitute `FILE_LIST_OR_PATHS` with the actual file list or path instructions):

```
You are a Reuse Analyst reviewing an entire codebase for duplication and missed reuse opportunities.

Files to review:
FILE_LIST_OR_PATHS

Read each file listed above.

Evaluate the codebase against:

1. **Duplicate Logic** — Are there functions or code blocks that do the same thing in different files? Search broadly for similar patterns.
2. **Shared Helpers** — Does code in one file re-implement a function that already exists in a utility or shared module elsewhere in the project?
3. **Copy-Paste Patterns** — Are there blocks of code that appear more than once across the codebase, or are near-identical between files?
4. **Abstraction Missed** — Is a repeated pattern (2+ occurrences) not extracted into a reusable function when it clearly should be?
5. **Import/Dependency Redundancy** — Are there dependencies imported or re-implemented that the project already provides through existing infrastructure?

Severity:
- HIGH: Clear duplication of existing logic that would cause a maintenance hazard
- LOW: Minor reuse suggestion with minimal impact

Write your findings to `.claude/simplify-all-reuse.md`. Max 100 lines.
Format: one finding per section with severity label (HIGH/LOW), file:line, and a one-line fix suggestion.
Do NOT edit any source files. Read-only analysis only.

End your report with: REVIEW COMPLETE
```

**Sub-Agent 2 — Quality Analyst:**

Spawn a Task sub-agent (general-purpose type) with this exact prompt (substitute `FILE_LIST_OR_PATHS` with the actual file list or path instructions):

```
You are a Quality Analyst reviewing an entire codebase for unnecessary complexity and maintainability issues.

Files to review:
FILE_LIST_OR_PATHS

Read each file listed above.

Evaluate the codebase against:

1. **Collapsible Conditionals** — Are there nested if/else chains that can be flattened or replaced with a guard clause?
2. **Over-Abstraction** — Are there abstractions (classes, interfaces, wrappers) added for a single use case that add indirection without benefit?
3. **Dead Code** — Are there commented-out blocks, unused variables, unused functions, unreachable branches, or stale exports?
4. **Readability** — Are there variable or function names that obscure intent? Are there magic numbers without named constants?
5. **Error Handling Complexity** — Is error handling more elaborate than the failure modes warrant? Are errors caught and re-thrown without adding information?

Severity:
- HIGH: Complexity that will actively mislead future maintainers or hide bugs
- LOW: Style or clarity suggestion that would help but isn't blocking

Write your findings to `.claude/simplify-all-quality.md`. Max 100 lines.
Format: one finding per section with severity label (HIGH/LOW), file:line, and a one-line fix suggestion.
Do NOT edit any source files. Read-only analysis only.

End your report with: REVIEW COMPLETE
```

**Sub-Agent 3 — Efficiency Analyst:**

Spawn a Task sub-agent (general-purpose type) with this exact prompt (substitute `FILE_LIST_OR_PATHS` with the actual file list or path instructions):

```
You are an Efficiency Analyst reviewing an entire codebase for obvious performance issues.

Files to review:
FILE_LIST_OR_PATHS

Read each file listed above.

Evaluate the codebase against:

1. **Repeated Operations** — Are there expensive operations (file reads, network calls, regex compiles, sorts) inside loops that could be hoisted out?
2. **Unnecessary Allocations** — Are there objects or arrays created and discarded when an in-place operation would suffice?
3. **Redundant Iterations** — Are there multiple passes over the same data that could be combined into one?
4. **Blocking in Hot Paths** — Are there synchronous operations in code paths that run frequently or on every request?
5. **Naive Data Structures** — Is a linear scan used where a set/map lookup would be O(1)?

Severity:
- HIGH: Performance issue that will be observable in normal use (loops over large data, repeated I/O)
- LOW: Micro-optimization with negligible real-world impact

Write your findings to `.claude/simplify-all-efficiency.md`. Max 100 lines.
Format: one finding per section with severity label (HIGH/LOW), file:line, and a one-line fix suggestion.
Do NOT edit any source files. Read-only analysis only.

End your report with: REVIEW COMPLETE
```

---

## Step 3: Verify Sub-Agent Output

After all 3 sub-agents complete, verify each output file exists:
- `.claude/simplify-all-reuse.md`
- `.claude/simplify-all-quality.md`
- `.claude/simplify-all-efficiency.md`

If any file is missing, log a warning ("Sub-agent failed to produce output: [filename]") and continue. Missing output means that lens produced no findings.

---

## Step 4: Apply HIGH-Severity Findings

Read all 3 output files. For each finding marked HIGH:

- Apply a **surgical fix** using Edit — only touch the specific lines identified.
- Do **not** change behavior, rename things for style preference, or refactor beyond the specific finding.
- Do **not** rewrite working code. If it works and is clear enough, leave it.
- Skip any HIGH finding that requires more than ~10 lines of change — log it as "deferred" in the report.

---

## Step 5: Write Consolidated Report

Write `.claude/simplify-all-report.md`:

```markdown
## Simplify All Report

### Scope
[list of paths reviewed, or "entire project" with file count]

### Reuse Analysis
[paste HIGH findings, or "No HIGH findings"]

### Quality Analysis
[paste HIGH findings, or "No HIGH findings"]

### Efficiency Analysis
[paste HIGH findings, or "No HIGH findings"]

### Changes Applied
- [file:line — description of change made, or "None"]

### Deferred (Too Large for Surgical Fix)
- [findings skipped because they exceeded surgical scope, or "None"]

### LOW-Severity Summary
- Reuse: [count] low findings
- Quality: [count] low findings
- Efficiency: [count] low findings

See individual reports in `.claude/simplify-all-{reuse,quality,efficiency}.md` for details.
```

Print a summary to the user showing how many HIGH findings were found, how many were fixed, and how many were deferred.
