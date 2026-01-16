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
- Test complete user workflows
- Real browser/environment
- Critical paths only
- Low volume, high value

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

### Success Criteria
- [ ] All happy path tests pass
- [ ] All error scenarios handled
- [ ] Edge cases covered
- [ ] Coverage threshold met
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
```
