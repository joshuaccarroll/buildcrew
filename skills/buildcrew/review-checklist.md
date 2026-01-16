# Code Review Checklist

Use this checklist during Phase 3 (REVIEW) to verify code quality.

---

## DRY (Don't Repeat Yourself)

- [ ] No copy-pasted code blocks (3+ similar lines)
- [ ] Common logic extracted into reusable functions
- [ ] Constants defined once, not repeated as literals
- [ ] No duplicate type definitions

**If violated**: Extract into a shared function, constant, or module.

---

## SOLID Principles

### Single Responsibility
- [ ] Each function does ONE thing
- [ ] Each file/module has a clear, focused purpose
- [ ] Functions are under 30 lines (prefer under 20)

### Open/Closed
- [ ] Code is open for extension, closed for modification
- [ ] New features don't require changing existing code
- [ ] Uses composition over inheritance where appropriate

### Liskov Substitution
- [ ] Derived types can substitute base types
- [ ] Interface implementations fulfill the contract

### Interface Segregation
- [ ] No fat interfaces with unused methods
- [ ] Clients don't depend on methods they don't use

### Dependency Inversion
- [ ] High-level modules don't depend on low-level details
- [ ] Dependencies are injected, not hard-coded

---

## KISS (Keep It Simple)

- [ ] No premature optimization
- [ ] No unnecessary abstractions
- [ ] Straightforward control flow (minimal nesting)
- [ ] Clear naming that explains intent
- [ ] No clever tricks that obscure meaning

**If violated**: Simplify. Inline unnecessary abstractions. Flatten nested logic.

---

## YAGNI (You Aren't Gonna Need It)

- [ ] No features beyond the current task
- [ ] No "just in case" code
- [ ] No unused parameters or returns
- [ ] No commented-out code "for later"

**If violated**: Remove it. Add it later when actually needed.

---

## Security

- [ ] No hardcoded secrets, API keys, or passwords
- [ ] User inputs are validated before use
- [ ] SQL queries use parameterized statements
- [ ] HTML output is escaped to prevent XSS
- [ ] File paths are sanitized
- [ ] Error messages don't leak sensitive information

**If violated**: Fix immediately. Security issues are highest priority.

---

## Code Style

- [ ] Consistent naming (camelCase, PascalCase, snake_case as per project)
- [ ] Consistent indentation and formatting
- [ ] Imports are organized (stdlib, external, internal)
- [ ] No unused imports
- [ ] No trailing whitespace
- [ ] Files end with a newline

---

## Error Handling

- [ ] Errors are caught and handled appropriately
- [ ] Error messages are clear and actionable
- [ ] No swallowed exceptions (catch with no handling)
- [ ] Async errors are properly caught
- [ ] Edge cases are handled (null, undefined, empty)

---

## Documentation

- [ ] Complex logic has explanatory comments
- [ ] Public APIs have JSDoc/docstrings (if project uses them)
- [ ] No obvious "what" comments (the code shows what)
- [ ] "Why" comments where intent isn't clear

---

## Testing Considerations

- [ ] New code is testable (no hidden dependencies)
- [ ] Side effects are isolated and mockable
- [ ] Public interfaces are clear and stable
- [ ] Test data doesn't include real user data

---

## Review Summary Template

After reviewing, summarize findings:

```markdown
## Review Summary

### Violations Found
1. **[Principle]**: [Description] in `file.ts:line`
   - Fix: [What to do]

2. **[Principle]**: [Description] in `file.ts:line`
   - Fix: [What to do]

### No Issues
- [List areas that passed review]

### Recommendations (Optional)
- [Non-blocking suggestions for improvement]
```

---

## Quick Reference: Priority Order

When fixing violations, address them in this order:

1. **Security** - Highest priority, fix immediately
2. **Correctness** - Logic errors, wrong behavior
3. **DRY/Duplication** - Maintainability concern
4. **SOLID violations** - Architecture concern
5. **Style/Formatting** - Lowest priority
