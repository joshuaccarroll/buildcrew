# QA Engineer Rules

Rules for test planning, test design, and test execution.

---

## Testing Philosophy

### Tests Should Fail Meaningfully
> "A test that can't fail is worthless. A test that fails for the wrong reason is dangerous."

- Every test must have a clear failure condition
- Tests should fail fast and fail loudly
- Failure messages must be actionable
- A passing test suite with bugs is worse than no tests

### Tests Should Pass Only When Correct
> "Tests are executable specifications."

- Tests define the contract
- If the test passes, the feature works
- No false positives - ever
- Tests should break when behavior changes

### Test What Matters
> "Coverage is a metric, not a goal."

- Focus on behavior, not implementation
- Test the edges and boundaries
- Test the happy path AND the sad paths
- Test what could actually break

---

## Test Pyramid

### Unit Tests
- Test single units in isolation
- Mock external dependencies
- Fast execution (< 10ms per test)
- High volume, low cost

### Integration Tests
- Test component interactions
- Use real dependencies where practical
- Verify contracts between systems
- Medium volume, medium cost

### End-to-End Tests
- Test complete user workflows end-to-end
- Real browser/environment (not mocked)
- Critical paths only -- high value, low volume
- Maintain a persistent experience harness (see "Experience Testing Harness" section)
- Include adversarial scenarios in every harness run
- Harness failures usually indicate code bugs (fix the application code; see failure classification for exceptions)

---

## Test Design Standards

### Test Structure (AAA Pattern)
```
Arrange - Set up test data and conditions
Act     - Execute the code under test
Assert  - Verify the outcome
```

### Test Naming Convention
Use descriptive names that explain the scenario:
- `should return empty array when no items match filter`
- `should throw ValidationError when email is invalid`
- `should retry 3 times before failing on network error`

### What Makes a Good Test

1. **Isolated**: No dependencies on other tests
2. **Repeatable**: Same result every time
3. **Self-Validating**: Clear pass/fail
4. **Timely**: Fast execution
5. **Focused**: Tests one thing

---

## Test Design Checklist

- [ ] Tests the actual requirement, not implementation
- [ ] Has clear, descriptive name
- [ ] Uses AAA pattern
- [ ] Handles setup/teardown properly
- [ ] Mocks are minimal and purposeful
- [ ] Assertions are specific
- [ ] Error messages are helpful
- [ ] No test interdependencies

---

## Test Scenarios to Cover

### Happy Path
- Standard successful flow
- Expected inputs producing expected outputs
- Normal user behavior

### Error Handling
- Invalid inputs
- Missing required data
- External service failures
- Network errors
- Timeout scenarios

### Edge Cases
- Empty inputs
- Maximum/minimum values
- Null/undefined handling
- Special characters
- Unicode and i18n

### Boundary Conditions
- Off-by-one scenarios
- Limit thresholds
- State transitions
- Race conditions

### Adversarial / Unexpected Usage
- Wrong input types (string where number expected, object where string expected)
- Out-of-sequence operations (skip required setup, run teardown first)
- Absurdly large or deeply nested input
- Conflicting configuration or environment state
- Invalid state mid-way (file deleted during processing, dependency unavailable, input stream closes early)
- Concurrent/duplicate requests
- Expired or revoked credentials mid-operation

### Experience Testing Harness
> "The best test is one that uses your software the way a real person would."

The experience harness is a persistent, project-level E2E test file that simulates actual user interaction:

- **CLI projects**: Execute real shell commands, pipe output, check exit codes
- **Web apps**: Use Playwright/Cypress to click, type, navigate, and assert
- **APIs**: Make real HTTP requests, check response status/body/headers
- **Libraries**: Import and call the public API with realistic usage patterns

Harness principles:
- **Persistent**: Lives in the project test directory, committed to git. Never recreated from scratch.
- **Cumulative**: Each task adds scenarios; existing passing scenarios are never removed.
- **Adversarial**: Every harness update includes at least one "try to break it" scenario.
- **Regression-aware**: The full harness runs on every test phase, catching regressions from new work.
- **Auto-fix**: Harness failures usually indicate real user-facing bugs -- fix the application code. Exceptions: intentional behavior changes and stale test fixtures (see failure classification).

---

## Coverage Expectations

- New code should be tested
- Business logic: high coverage
- Utilities: edge cases covered
- UI components: behavior tested

---

## Test Plan Format

```markdown
## Test Plan: [Feature Name]

### Overview
[Brief description of what's being tested]

### Test Scenarios

#### Happy Path
| ID | Scenario | Input | Expected Output | Type |
|----|----------|-------|-----------------|------|
| HP-01 | [Scenario] | [Input] | [Expected] | Unit |

#### Error Handling
| ID | Scenario | Input | Expected Output | Type |
|----|----------|-------|-----------------|------|
| ERR-01 | [Scenario] | [Input] | [Expected] | Unit |

#### Edge Cases
| ID | Scenario | Input | Expected Output | Type |
|----|----------|-------|-----------------|------|
| EDGE-01 | [Scenario] | [Input] | [Expected] | Unit |

#### Adversarial / Unexpected Usage
| ID | Scenario | Input | Expected Output | Type |
|----|----------|-------|-----------------|------|
| ADV-01 | [Misuse/abuse] | [Input] | [Expected defense] | E2E |

### Experience Harness Status
- **Harness exists**: [YES | NO -- will create]
- **Scenarios to add**: [list of new scenarios for this task]
- **Adversarial scenario**: [description of deliberate misuse test]

### Success Criteria
- [ ] All happy path tests pass
- [ ] All error scenarios handled
- [ ] Edge cases covered
- [ ] Coverage threshold met
- [ ] Adversarial scenarios tested
- [ ] Experience harness updated and passing
```

---

## Test Execution Report

```markdown
## Test Execution Report

### Summary
- **Total Tests**: X
- **Passed**: X
- **Failed**: X
- **Coverage**: X%

### Failed Tests
| Test | File | Reason | Fix Required |
|------|------|--------|--------------|
| [name] | [file] | [reason] | [fix] |

### Coverage Analysis
- **Branches**: X%
- **Functions**: X%
- **Lines**: X%

### Experience Harness
- **Harness File**: [path]
- **Status**: [CREATED | EXTENDED | EXISTING (unchanged)]
- **Scenarios Run**: X passed / Y total
- **New Scenarios Added**: X
- **Adversarial Scenarios**: X
- **Bugs Found & Auto-Fixed**: [list or "None"]
```
