# Principal Engineer Rules

Rules for architecture review, plan review, and code review.

---

## Review Standards

### Plan Review Checklist

1. **Scope Assessment**
   - Is the plan solving the actual problem?
   - Is the scope appropriate (not too broad, not too narrow)?
   - Are there hidden complexities not addressed?

2. **Architecture Fit**
   - Does this align with existing architecture?
   - If it diverges, is there good reason?
   - Will this create technical debt?

3. **Simplicity Check**
   - Is this the simplest approach?
   - Are there simpler alternatives?
   - What can be removed from the plan?

4. **Risk Assessment**
   - What could go wrong?
   - What are the dependencies?
   - What's the blast radius if this fails?

5. **Testability**
   - How will this be tested?
   - Is the design testable?
   - What's the testing strategy?

### Code Review Checklist

1. **Correctness**
   - Does it do what it's supposed to?
   - Are edge cases handled?
   - Are error conditions covered?

2. **Design Quality**
   - Single Responsibility: One reason to change?
   - Open/Closed: Extensible without modification?
   - Dependency Inversion: Depends on abstractions?

3. **Readability**
   - Can you understand it in one pass?
   - Are names intention-revealing?
   - Is the control flow clear?

4. **Simplicity**
   - Is there unnecessary complexity?
   - Can anything be removed?
   - Are there simpler alternatives?

5. **Testability**
   - Is this code testable?
   - Are dependencies injectable?
   - Are side effects isolated?

6. **Cleanup Check**
   - Are there any unused imports?
   - Are there any orphaned files created but not used?
   - Are there any dead code paths?
   - Were any old files made obsolete that should be deleted?
   - Are there commented-out code blocks that should be removed?

---

## Anti-Patterns to Reject

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

## Review Output Format

### Plan Review
```markdown
## Principal Engineer Plan Review

### Verdict: [APPROVED | NEEDS REVISION | REJECTED]

### Strengths
- [What's good about this plan]

### Concerns
- [Issues that must be addressed]

### Required Changes (if any)
1. [Specific change needed]

### Recommendations (optional)
- [Suggestions for improvement]
```

### Code Review
```markdown
## Principal Engineer Code Review

### Verdict: [APPROVED | NEEDS REVISION | REJECTED]

### Summary
[1-2 sentence overall assessment]

### Critical Issues (must fix)
- **[Issue Type]** in `file.ts:line`: [Description]

### Major Concerns (should fix)
- **[Issue Type]** in `file.ts:line`: [Description]

### Minor Suggestions (nice to have)
- [Suggestion]

### What's Done Well
- [Positive observations]
```

---

## Severity Levels

| Level | Impact | Action |
|-------|--------|--------|
| **Critical** | Security, correctness | Must fix before proceeding |
| **Major** | Design, maintainability | Should fix before proceeding |
| **Minor** | Style, conventions | Fix if quick, otherwise note |
