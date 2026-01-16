# Coding Principles

These principles guide both plan review and code review in the Josh Workflow. The Principal Engineer persona enforces these standards rigorously.

> "The best code is the code you don't have to write." - Principal Engineer

---

## Core Values

### 1. Simplicity Above All
The simplest solution that works is the correct solution.

- Every abstraction must earn its place
- If you can't explain it simply, it's too complex
- Delete code whenever possible
- Prefer explicit over implicit

### 2. Readability is Paramount
Code is read 10x more than it's written.

- Names should reveal intent
- Functions should tell a story
- Comments explain "why", code explains "what"
- Optimize for the next developer

### 3. Modularity Enables Evolution
Good architecture allows decisions to be deferred.

- Clear boundaries between components
- Dependencies point inward (toward core domain)
- Each module should be replaceable
- Coupling is the enemy of change

### 4. Testability is Non-Negotiable
Untested code is legacy code.

- Design for testability from the start
- If it's hard to test, the design is wrong
- Tests document behavior
- Test coverage reflects confidence

---

## Core Principles (Always Apply)

### DRY - Don't Repeat Yourself
- Extract repeated code into reusable functions
- Define constants once, reference everywhere
- Avoid copy-paste coding
- **Threshold**: 3+ similar lines should be extracted
- **Exception**: Sometimes duplication is clearer than the wrong abstraction

### SOLID
- **S**ingle Responsibility: One reason to change per function/class
- **O**pen/Closed: Open for extension, closed for modification
- **L**iskov Substitution: Subtypes must be substitutable
- **I**nterface Segregation: No fat interfaces with unused methods
- **D**ependency Inversion: Depend on abstractions, not concretions

### KISS - Keep It Simple, Stupid
- Prefer simple solutions over clever ones
- Avoid premature optimization
- Minimize nesting and complexity (max 3 levels)
- If it's hard to explain, it's too complex
- Straightforward > clever

### YAGNI - You Aren't Gonna Need It
- Don't build features until they're needed
- Remove dead code and unused imports
- No "just in case" code paths
- No configuration for hypothetical futures
- Delete commented-out code

---

## Anti-Patterns to Reject

The Principal Engineer will **NOT TOLERATE** these patterns:

### Over-Engineering
- Building for hypothetical future requirements
- Abstractions with only one implementation
- "Enterprise" patterns in simple applications
- Configuration over convention when convention suffices
- Factory factories and strategy strategy patterns

### Poor Separation of Concerns
- Business logic in UI components
- Database queries in controllers/handlers
- Side effects hidden in pure functions
- God classes that do everything
- Mixing presentation and data access

### Code Smells
- Functions longer than 20 lines
- Files longer than 300 lines
- Deep nesting (> 3 levels)
- Magic numbers and strings
- Boolean parameters that change behavior
- Circular dependencies
- Leaky abstractions

### Testing Failures
- Untested business logic
- Tests that don't test anything meaningful
- Missing edge case coverage
- Integration tests masquerading as unit tests
- Tests coupled to implementation details

---

## Code Style

### Naming
- Use descriptive, intention-revealing names
- Follow project conventions (camelCase, PascalCase, snake_case)
- Avoid abbreviations except well-known ones (URL, API, ID)
- Boolean variables should read as questions: `isActive`, `hasPermission`
- Functions should be verbs: `calculateTotal`, `fetchUser`, `validateInput`

### Functions
- Keep functions small (< 20 lines preferred, hard limit 30)
- Do one thing well
- Use meaningful parameter names
- Avoid more than 3 parameters (use an options object)
- Minimize side effects; isolate them when necessary
- Return early to avoid deep nesting

### Files
- One concept per file
- Organize imports: stdlib, external, internal
- End files with a newline
- Remove trailing whitespace
- Keep files under 300 lines

---

## Security (Highest Priority)

Security issues are **blocking** - no exceptions.

- **Never** hardcode secrets, API keys, or passwords
- **Always** validate external inputs at system boundaries
- **Always** escape user data in outputs (XSS prevention)
- **Always** use parameterized queries for databases (SQL injection)
- **Never** expose stack traces or internal errors to users
- **Always** sanitize file paths
- **Never** trust client-side validation alone
- **Always** use HTTPS for sensitive data

---

## Error Handling

- Handle errors explicitly, don't let them propagate silently
- Provide clear, actionable error messages
- Log errors with sufficient context for debugging
- Use try/catch appropriately, don't swallow exceptions
- Fail fast - detect and report errors early
- Recover gracefully when possible

---

## Testing Requirements

### Test Pyramid
- **Unit Tests**: Fast, isolated, test single units
- **Integration Tests**: Test component interactions
- **E2E Tests**: Critical paths only, expensive but valuable

### Test Quality
- Tests should fail when behavior breaks
- Tests should pass only when behavior is correct
- Use AAA pattern: Arrange, Act, Assert
- Descriptive test names: `should [behavior] when [condition]`
- No test interdependencies
- Keep tests fast (< 10ms for unit tests)

### Coverage Expectations
- New code should be tested
- Business logic: high coverage
- Utilities: edge cases covered
- UI components: behavior tested

---

## Custom Rules

<!--
Add your project-specific rules below.
These will be enforced during plan review and code review.

Example:

### API Design
- All endpoints must return consistent error format: { error: string, code: number }
- Use plural nouns for resource collections: /users, /products
- Version all public APIs: /v1/users
- Include correlation IDs in all responses

### Database
- All queries must use parameterized statements
- No N+1 query patterns
- Index foreign keys
- Use transactions for multi-step operations

### Frontend
- Components must be under 200 lines
- State management through designated store only
- No inline styles except dynamic values
- Accessibility: all interactive elements must be keyboard accessible
-->

---

## Enforcement

These principles are enforced at two checkpoints:

1. **Plan Review (Phase 2)**: Principal Engineer reviews the plan before coding begins
2. **Code Review (Phase 4)**: Principal Engineer reviews the implementation

### Severity Levels

| Level | Impact | Action |
|-------|--------|--------|
| **Critical** | Security, correctness | Must fix before proceeding |
| **Major** | Design, maintainability | Should fix before proceeding |
| **Minor** | Style, conventions | Fix if quick, otherwise note |

---

## Philosophy

> These principles are guidelines, not dogma. The goal is **maintainable, readable, correct code**.

Use judgment:
- Sometimes a bit of repetition is clearer than a forced abstraction
- Performance-critical code may need optimization that looks "ugly"
- Legacy code constraints may limit ideal solutions
- Pragmatism over perfection - but never compromise on security
