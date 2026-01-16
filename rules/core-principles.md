# Core Principles

These foundational principles apply to all BuildCrew personas and workflows.

> "The best code is the code you don't have to write."

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

## Universal Principles

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

## Error Handling

- Handle errors explicitly, don't let them propagate silently
- Provide clear, actionable error messages
- Log errors with sufficient context for debugging
- Use try/catch appropriately, don't swallow exceptions
- Fail fast - detect and report errors early
- Recover gracefully when possible

---

## Philosophy

> These principles are guidelines, not dogma. The goal is **maintainable, readable, correct code**.

Use judgment:
- Sometimes a bit of repetition is clearer than a forced abstraction
- Performance-critical code may need optimization that looks "ugly"
- Legacy code constraints may limit ideal solutions
- Pragmatism over perfection - but never compromise on security
