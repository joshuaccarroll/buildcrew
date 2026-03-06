---
name: buildcrew-simplify
description: BuildCrew Simplify phase — review changed code for reuse, quality, and efficiency
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task
---

# BuildCrew — Simplify

`[Phase: simplify | Input: built code | Output: .claude/simplify-report.md | Next: code-review]`

You are executing the simplify phase of the BuildCrew autonomous development workflow.

## Your Task

The task was provided in the prompt.

---

## SIMPLIFY (Non-blocking)

**Goal**: Review the changed code for unnecessary complexity, reuse opportunities, and efficiency improvements through 3 parallel specialized sub-agents. Apply targeted fixes based on HIGH-severity findings. This phase is non-blocking — always write `complete`.

---

### Step 1: Discover Changed Files

Run `git diff --name-only HEAD` to discover what was built. Read the actual files to understand the changes.

---

### Step 2: Dispatch Parallel Review Sub-Agents

In a **single response**, spawn all 3 Task sub-agents (general-purpose type) simultaneously. Do not wait for one to finish before starting the next.

**Sub-Agent 1 — Reuse Analyst:**

Spawn a Task sub-agent (general-purpose type) with this exact prompt:

```
You are a Reuse Analyst reviewing recently changed code for duplication and missed reuse opportunities.

Run `git diff --name-only HEAD` to discover changed files, then read them.

Evaluate each changed file against:

1. **Duplicate Logic** — Is there existing code in the project that does the same thing? Search the codebase for similar patterns before concluding something is novel.
2. **Shared Helpers** — Does the new code implement a function that already exists in a utility or shared module?
3. **Copy-Paste Patterns** — Are there blocks of code that appear more than once in the changed files or are near-identical to code elsewhere in the project?
4. **Abstraction Missed** — Is a repeated pattern (2+ occurrences) not extracted into a reusable function when it clearly should be?
5. **Import/Dependency Redundancy** — Are there dependencies imported or re-implemented that the project already provides through existing infrastructure?

Severity:
- HIGH: Clear duplication of existing logic that would cause a maintenance hazard
- LOW: Minor reuse suggestion with minimal impact

Write your findings to `.claude/simplify-reuse.md`. Max 60 lines.
Format: one finding per section with severity label (HIGH/LOW), file:line, and a one-line fix suggestion.
Do NOT edit any files. Read-only analysis only.

End your report with: REVIEW COMPLETE
```

**Sub-Agent 2 — Quality Analyst:**

Spawn a Task sub-agent (general-purpose type) with this exact prompt:

```
You are a Quality Analyst reviewing recently changed code for unnecessary complexity and maintainability issues.

Run `git diff --name-only HEAD` to discover changed files, then read them.

Evaluate each changed file against:

1. **Collapsible Conditionals** — Are there nested if/else chains that can be flattened or replaced with a guard clause?
2. **Over-Abstraction** — Are there abstractions (classes, interfaces, wrappers) added for a single use case that add indirection without benefit?
3. **Dead Code** — Are there commented-out blocks, unused variables, or unreachable branches in the changed code?
4. **Readability** — Are there variable or function names that obscure intent? Are there magic numbers without named constants?
5. **Error Handling Complexity** — Is error handling more elaborate than the failure modes warrant? Are errors caught and re-thrown without adding information?

Severity:
- HIGH: Complexity that will actively mislead future maintainers or hide bugs
- LOW: Style or clarity suggestion that would help but isn't blocking

Write your findings to `.claude/simplify-quality.md`. Max 60 lines.
Format: one finding per section with severity label (HIGH/LOW), file:line, and a one-line fix suggestion.
Do NOT edit any files. Read-only analysis only.

End your report with: REVIEW COMPLETE
```

**Sub-Agent 3 — Efficiency Analyst:**

Spawn a Task sub-agent (general-purpose type) with this exact prompt:

```
You are an Efficiency Analyst reviewing recently changed code for obvious performance issues.

Run `git diff --name-only HEAD` to discover changed files, then read them.

Evaluate each changed file against:

1. **Repeated Operations** — Are there expensive operations (file reads, network calls, regex compiles, sorts) inside loops that could be hoisted out?
2. **Unnecessary Allocations** — Are there objects or arrays created and discarded when an in-place operation would suffice?
3. **Redundant Iterations** — Are there multiple passes over the same data that could be combined into one?
4. **Blocking in Hot Paths** — Are there synchronous operations in code paths that run frequently or on every request?
5. **Naive Data Structures** — Is a linear scan used where a set/map lookup would be O(1)?

Severity:
- HIGH: Performance issue that will be observable in normal use (loops over large data, repeated I/O)
- LOW: Micro-optimization with negligible real-world impact

Write your findings to `.claude/simplify-efficiency.md`. Max 60 lines.
Format: one finding per section with severity label (HIGH/LOW), file:line, and a one-line fix suggestion.
Do NOT edit any files. Read-only analysis only.

End your report with: REVIEW COMPLETE
```

---

### Step 3: Verify Sub-Agent Output

After all 3 sub-agents complete, verify each output file exists:
- `.claude/simplify-reuse.md`
- `.claude/simplify-quality.md`
- `.claude/simplify-efficiency.md`

If any file is missing, log a warning ("Sub-agent failed to produce output: [filename]") and continue. Missing output means that lens produced no findings.

---

### Step 4: Apply HIGH-Severity Findings

Read all 3 output files. For each finding marked HIGH:

- Apply a **surgical fix** using Edit — only touch the specific lines identified.
- Do **not** change behavior, rename things for style preference, or refactor beyond the specific finding.
- Do **not** rewrite working code. If it works and is clear enough, leave it.
- Skip any HIGH finding that requires more than ~10 lines of change — log it as "deferred to code-review" in the report.

---

### Step 5: Write Consolidated Report

Write `.claude/simplify-report.md`:

```markdown
## Simplify Report

### Reuse Analysis
[paste HIGH findings, or "No HIGH findings"]

### Quality Analysis
[paste HIGH findings, or "No HIGH findings"]

### Efficiency Analysis
[paste HIGH findings, or "No HIGH findings"]

### Changes Applied
- [file:line — description of change made, or "None"]

### Deferred to Code-Review
- [findings skipped because they exceeded surgical scope, or "None"]
```

