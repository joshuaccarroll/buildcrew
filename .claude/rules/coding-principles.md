# Coding Principles

These principles guide code review in the Josh Workflow. All code should be evaluated against these standards during the REVIEW phase.

---

## Core Principles (Always Apply)

### DRY - Don't Repeat Yourself
- Extract repeated code into reusable functions
- Define constants once, reference everywhere
- Avoid copy-paste coding
- **Threshold**: 3+ similar lines should be extracted

### SOLID
- **S**ingle Responsibility: One reason to change per function/class
- **O**pen/Closed: Open for extension, closed for modification
- **L**iskov Substitution: Subtypes must be substitutable
- **I**nterface Segregation: No fat interfaces
- **D**ependency Inversion: Depend on abstractions

### KISS - Keep It Simple, Stupid
- Prefer simple solutions over clever ones
- Avoid premature optimization
- Minimize nesting and complexity
- If it's hard to explain, it's too complex

### YAGNI - You Aren't Gonna Need It
- Don't build features until they're needed
- Remove dead code and unused imports
- No "just in case" code paths

---

## Code Style

### Naming
- Use descriptive, intention-revealing names
- Follow project conventions (camelCase, PascalCase, snake_case)
- Avoid abbreviations except well-known ones (URL, API, ID)
- Boolean variables should read as questions: `isActive`, `hasPermission`

### Functions
- Keep functions small (< 20 lines preferred)
- Do one thing well
- Use meaningful parameter names
- Avoid more than 3 parameters (consider an options object)

### Files
- One concept per file
- Organize imports: stdlib, external, internal
- End files with a newline
- Remove trailing whitespace

---

## Security (Highest Priority)

- **Never** hardcode secrets, API keys, or passwords
- **Always** validate external inputs
- **Always** escape user data in outputs
- **Always** use parameterized queries for databases
- **Never** expose stack traces or internal errors to users
- **Always** sanitize file paths

---

## Error Handling

- Handle errors explicitly, don't let them propagate silently
- Provide clear, actionable error messages
- Log errors with sufficient context for debugging
- Use try/catch appropriately, don't swallow exceptions

---

## Testing

- Write tests for new functionality
- Test edge cases and error conditions
- Keep tests fast and isolated
- Use descriptive test names that explain the scenario

---

## Custom Rules

<!--
Add your project-specific rules below.
These will be checked during code review along with the core principles.

Example:
### API Design
- All endpoints must return consistent error format
- Use plural nouns for resource collections
- Version all public APIs
-->

---

## Notes

These principles are guidelines, not absolute rules. Use judgment:
- Sometimes a bit of repetition is clearer than a forced abstraction
- Performance-critical code may need optimization
- Legacy code constraints may limit ideal solutions

The goal is **maintainable, readable, correct code** - not perfect adherence to every principle.
