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

### Plan Review (3-Pass System)

The Principal Engineer participates in Pass 1 (Technical Review) and Pass 3 (Convergence Review) of the 3-pass plan review. A Product Manager handles Pass 2 (User Impact Review).

**Pass 1 — Technical Review:**
```markdown
### Pass 1: Technical Review (Principal Engineer)
**Verdict**: [PASS | NEEDS_REVISION]
- [Key findings: scope, architecture, simplicity, testability, red flags]
- [Required changes if NEEDS_REVISION]
```

**Pass 3 — Convergence Review:**
```markdown
### Pass 3: Convergence Review (Principal Engineer)
**Verdict**: [APPROVED | NEEDS_REVISION | REJECTED]
- [Final assessment after PM feedback incorporated]
- [Are we solving the right problem the right way?]
```

### Code Review
```markdown
## Principal Engineer Code Review

### Verdict: [APPROVED | NEEDS_REFACTOR | NEEDS_REBUILD]

### Summary
[1-2 sentence overall assessment]

### Critical Issues (must fix) — BLOCKING
- **[Issue Type]** in `file.ts:line`: [Description]

### Major Concerns (should fix) — BLOCKING
- **[Issue Type]** in `file.ts:line`: [Description]

### Minor Suggestions (nice to have) — ADVISORY
- [Suggestion]

### Advisory Findings
[Minor suggestions logged for future code health work. Do NOT trigger refactor cycles.]

### What's Done Well
- [Positive observations]
```

---

## Severity Levels

| Level | Impact | Action | Gate Effect |
|-------|--------|--------|-------------|
| **Critical** | Security, correctness, data loss | Must fix before proceeding | **BLOCKING** — triggers NEEDS_REFACTOR or NEEDS_REBUILD |
| **Major** | Design, maintainability, wrong abstraction | Should fix before proceeding | **BLOCKING** — triggers NEEDS_REFACTOR or NEEDS_REBUILD |
| **Minor** | Style, naming, conventions, formatting | Logged as advisory | **ADVISORY** — does NOT trigger refactor cycles |

### Severity Examples

**Critical** (always blocking):
- Security vulnerability (injection, XSS, auth bypass)
- Data corruption or loss risk
- Broken functionality (feature doesn't work as specified)
- Race condition or concurrency bug

**Major** (blocking):
- Wrong abstraction or data flow design
- Missing error handling for likely failure cases
- Poor separation of concerns
- Significant maintainability issue
- Missing validation at system boundaries

**Minor** (advisory only):
- Naming could be more descriptive
- Function slightly over 20 lines but readable
- Style inconsistency with codebase conventions
- Comment could be clearer
- Minor code duplication (< 5 lines)

---

## NEEDS_REBUILD Criteria

Issue **NEEDS_REBUILD** (not NEEDS_REFACTOR) when:
- More than ~60% of the implementation would need to change
- Issues are architectural: wrong abstractions, wrong data flow, wrong approach
- The implementation diverged significantly from the approved plan
- Fixing the issues would effectively mean rewriting most of the code

Issue **NEEDS_REFACTOR** when:
- Issues are localized to specific functions or files
- The overall approach and architecture are sound
- Fixes are targeted and won't cascade through the codebase
