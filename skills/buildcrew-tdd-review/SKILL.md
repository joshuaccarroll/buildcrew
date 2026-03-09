# TDD Review Phase

`[Phase: tdd-review | Input: .claude/tdd-manifest.json | Output: .claude/tdd-review.md | Next: build]`

allowed-tools: Read, Write, Glob, Grep, Task

You are executing the **tdd-review** phase of the BuildCrew pipeline. Your job is to review the failing test files written by tdd-scaffold — before build consumes them. You are **read-only**: you may not modify test files or production code.

## Context

The tdd-scaffold phase just wrote failing tests (RED state). These tests will drive the build phase. Your job is to catch quality issues now, before bad tests mislead the implementation.

**Important**: Tests are intentionally failing. Do NOT run the test suite. Do NOT flag RED-state failures as issues.

## Step 1 — Read the manifest

Read `.claude/tdd-manifest.json`. Extract:
- `test_files`: the list of files to review (typically 2–8 files)
- `ac_coverage`: which ACs each test covers

Do not review any files outside `test_files`. Do not batch — review all files in a single pass.

## Step 2 — Spawn 3 parallel lens agents

Spawn all three agents in a **single response** using the Task tool. Each lens is independent and read-only.

Substitute `[TEST_FILES]` with the comma-separated list of test file paths from the manifest.

**Lens 1 — Correctness & Reliability**

```
You are reviewing test files for Correctness & Reliability only.

Read each of these test files: [TEST_FILES]

You MAY read the production code these tests cover to evaluate whether assertions
test the right behavior. Do NOT modify any files.

Evaluate:
- Will these tests actually fail when the app misbehaves? Are assertions specific
  enough to catch real bugs, or so broad they'd pass on broken code?
- Over-mocking: are mocks so extensive the test passes even if production code is broken?
- False confidence: assertions on truthiness/existence rather than specific expected values
- Missing negative tests: error paths, boundary conditions, invalid inputs

Return up to 5 findings. Format: one finding per section with file:line reference
and a one-line fix suggestion.
Do NOT modify any files. Read-only analysis only.
If no meaningful findings: respond with exactly NO_FINDINGS
```

**Lens 2 — Design & Intent**

```
You are reviewing test files for Design & Intent only.

Read each of these test files: [TEST_FILES]

You MAY read the production code these tests cover to evaluate implementation coupling.
Do NOT modify any files.

Evaluate:
- Do test names describe WHAT behavior is tested, not HOW?
- Are tests coupled to implementation details? Would a refactor break tests even
  though behavior is unchanged?
- Arrange-Act-Assert clarity: can you immediately understand the requirement each
  test documents?
- Test smells: testing private methods directly, asserting on internal state

Return up to 5 findings. Format: one finding per section with file:line reference
and a one-line fix suggestion.
Do NOT modify any files. Read-only analysis only.
If no meaningful findings: respond with exactly NO_FINDINGS
```

**Lens 3 — Speed & Isolation**

```
You are reviewing test files for Speed & Isolation only.

Read each of these test files: [TEST_FILES]

You MAY read the production code these tests cover to evaluate setup complexity.
Do NOT modify any files.

Evaluate:
- Are tests fast? Flag: unnecessary disk I/O, real network calls, sleep/wait calls
- Are tests isolated? Flag: shared mutable state, reliance on test execution order,
  global variables modified without cleanup
- Dead weight: orphaned tests for deleted features, commented-out tests, unused fixtures
- Duplication: copy-pasted setup or assertions that should be shared helpers

Return up to 5 findings. Format: one finding per section with file:line reference
and a one-line fix suggestion.
Do NOT modify any files. Read-only analysis only.
If no meaningful findings: respond with exactly NO_FINDINGS
```

## Step 3 — Consolidate findings

Read all three lens agent responses. Write `.claude/tdd-review.md` with this structure:

```markdown
# TDD Review Findings

## Correctness & Reliability
<findings or "No issues found">

## Design & Intent
<findings or "No issues found">

## Speed & Isolation
<findings or "No issues found">

## Consolidated Verdict
<approved or needs_revision>

### Blocking issues (if needs_revision)
<list issues that would undermine the RED-state guarantee>
```

## Step 4 — Determine verdict

**`approved`** — proceed to build when:
- No lens found a blocking issue
- All NO_FINDINGS, or findings are minor style notes only

**`needs_revision`** — when any finding would undermine the RED-state guarantee:
- Tests that would pass trivially even when the app is broken (false positives)
- Assertions so weak they cannot catch the bugs the spec describes
- Tests that assert on the wrong thing entirely (wrong AC coverage)

Note: slow tests, style issues, and minor coupling are NOT blocking — only issues that undermine correctness of the RED-state guarantee block.

## Step 5 — Write phase-result.json

Use the Write tool to write `.claude/phase-result.json` as your final step:

For approved verdict:
```json
{ "phase": "tdd-review", "verdict": "approved", "details": "<one-line summary>" }
```

For needs_revision verdict:
```json
{ "phase": "tdd-review", "verdict": "needs_revision", "details": "<one-line summary of blocking issues>" }
```

Writing `.claude/phase-result.json` is mandatory. Do not end your response without writing it.
