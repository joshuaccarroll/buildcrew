# Test Review — Part A

You are executing the test-review skill (Part A: Discovery and Baseline).

## Your Task

Review the test suite for the current project. This skill runs in two parts:
- **Part A (this file)**: Test discovery, runner detection, baseline verification, and batch division
- **Part B**: Lens analysis, convergence rounds, and fix application

## Test Discovery

Discover test files using standard patterns:
- `**/*.test.js`, `**/*.spec.js`, `**/*.test.ts`, `**/*.spec.ts` (JS/TS)
- `**/*_test.py`, `**/test_*.py` (Python)
- `**/\*_test.go` (Go)
- `**/*.rs` (Rust, cargo test)
- `**/*.bats` (Bash)

Exclude:
- `node_modules/`, `vendor/`, `.venv/`, `dist/`, `build/`, `target/`, `.git/`, `.buildcrew/`, `.claude/`

If no tests found, print a clear message and exit.

## Test Runner Detection

Detect and infer the test runner based on the files found:
- `.bats` files → bats
- `.test.js`, `.spec.js`, `jest.config.*` → jest
- `vitest.config.*` → vitest
- `pytest.ini`, `pyproject.toml`, `*_test.py` → pytest
- `*_test.go` → go test
- `Cargo.toml` → cargo test
- Other → prompt user

## Baseline Verification

Run the discovered test runner once. If it fails:
- Print a clear message that baseline failed
- Note that report-only mode is active (findings as recommendations, no fixes applied)
- Record `BASELINE_SHA` and `BASELINE_UNTRACKED` for revert mechanism in Part B

If baseline passes, proceed normally.

## Batch Division

Divide discovered test files into groups of 15. Report:
- Total test file count
- Number of batches
- Batch boundaries

## Output

Print the following to stdout:
- Test file count
- Runner name
- Baseline status
- Batch count and boundaries

Write `.claude/phase-result.json` when done: `{ "phase": "test-review", "verdict": "complete", "details": "<summary>" }`
