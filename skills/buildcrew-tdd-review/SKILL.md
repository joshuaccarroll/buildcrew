# BuildCrew — TDD Review

`[Phase: tdd-review | Input: .claude/tdd-manifest.json | Output: .claude/phase-result.json | Next: build]`

You are executing the tdd-review phase of the BuildCrew autonomous development workflow.

## Your Task

Review the failing TDD test files listed in `.claude/tdd-manifest.json` to ensure they properly test the spec's acceptance criteria and remain in RED state (failing) before implementation begins.

---

## TDD REVIEW (Test Reviewer)

**Goal**: Convergence loop to ensure TDD tests comprehensively cover the spec's acceptance criteria while remaining in RED state (failing assertions only — not import or syntax failures).

### Prerequisites

- `.claude/tdd-manifest.json` exists (written by tdd-scaffold phase)
- Manifest contains: `test_files`, `test_dir`, `run_command`, `checksums`
- All TDD tests are currently failing (verified at end of tdd-scaffold)

### Step 1: Initial Analysis (Round 1)

Run the test suite using the `run_command` from the manifest to establish baseline RED state:

```bash
$(cat .claude/tdd-manifest.json | jq -r '.run_command')
```

Inspect output for:
- **Assertion failures**: Tests reach assertions and fail (correct)
- **Import/compilation failures**: Tests fail before reaching assertions (indicates incomplete stubs)
- **Unexpected passes**: Tests pass trivially (indicates weak test assertions)

### Step 2: Convergence Rounds (Rounds 2–3)

Run up to 2 serial improvement rounds. Each round:

1. **Analysis**: Review test files to identify gaps in coverage or weak assertions
2. **Improvement decision**: Either improve test files or respond `CONVERGED` if no changes needed
3. **If changes made**: Re-run test suite to verify RED state is preserved (tests still fail)
4. **If converged**: No further rounds

### Step 3: Post-Review

After convergence rounds complete:

1. **RED state re-verification**: Run `run_command` from manifest one final time:
   - Tests fail on assertions only → correct RED state (continue)
   - Tests fail on imports/compilation → log warning but continue
   - Tests unexpectedly pass → log warning but continue

2. **Checksum update**: For any modified test files, recompute SHA-256 checksums:
   ```bash
   openssl dgst -sha256 <file> | awk '{print $2}'
   ```
   Update the `checksums` map in `.claude/tdd-manifest.json`. Do not modify other fields.

3. **Phase result**: Write `.claude/phase-result.json`:
   ```json
   {
     "phase": "tdd-review",
     "verdict": "complete",
     "details": "<N> convergence rounds. RED state: <status>. <N> test files improved."
   }
   ```

## Acceptance Criteria

- TDD test files are reviewed for coverage of spec acceptance criteria
- Convergence rounds are scoped to test_files from manifest only
- After any changes, RED state is verified with run_command
- Checksums updated for any modified test files
- Phase always completes with verdict: `complete`

## Implementation Notes

- **Scope constraint**: Only touch files listed in `test_files` from manifest — do not modify production code or other test files
- **Non-blocking**: This phase is non-blocking; workflow continues regardless of outcome
- **RED state requirement**: Tests must fail on assertions, not imports or syntax
