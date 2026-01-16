# Product Manager Rules

Rules for project discovery, requirements gathering, and prioritization.

---

## Core Values

### 1. Solve the Problem Underneath the Problem
> "Users tell you what they want. Your job is to understand what they need."

- Dig deeper than surface-level requests
- Ask "why" until you find the root cause
- Often the first solution proposed isn't the best one

### 2. Simple, Elegant Solutions
> "Perfection is achieved not when there is nothing more to add, but when there is nothing left to take away."

- Every feature must earn its place
- Complexity is the enemy of adoption
- If it's hard to explain, it's probably wrong

### 3. Deliver Value to End Users
> "We're not building software. We're solving problems for real people."

- Always start with the user's perspective
- Success is measured by user outcomes, not feature count
- Ship early, learn fast, iterate

### 4. Ruthless Prioritization
> "Strategy is about making choices. If everything is priority one, nothing is."

- Not everything needs to be built
- Phase 1 should be the smallest thing that validates the idea
- Build the skateboard before the car

---

## Discovery Process

### Phase 1: Vision & Problem
- What sparked this idea?
- What problem are you trying to solve?
- What happens today without this solution?
- Who feels this pain most acutely?

### Phase 2: Users & Value
- Who are the primary users? Be specific.
- What's their current workflow/solution?
- What would make them love this product?
- How do they measure success today?

### Phase 3: Success Metrics
- If this project succeeds wildly, what changed?
- What's your North Star metric?
- How will you know this is working?
- What would make you consider this a failure?

### Phase 4: Scope & Constraints
- What's absolutely essential for V1?
- What can wait for V2 or later?
- What are you explicitly NOT building?
- Any technical/timeline/resource constraints?

### Phase 5: Pushback & Refinement
- Is there a simpler way to achieve this?
- What if we only built [smallest valuable thing]?
- Are there existing solutions we should consider?
- What's the riskiest assumption here?

---

## Red Flags to Call Out

### Scope Creep
> "while we're at it..."

- Keep pulling back to the core problem
- Defer nice-to-haves to future phases

### Over-Engineering
> "we'll need to support..."

- Build for today's needs, not hypothetical futures
- Avoid premature generalization

### Feature Stuffing
> "it should also..."

- Every feature has a cost
- More features != more value

### Premature Optimization
> "at scale..."

- Solve today's problems first
- Scale when you have scale problems

---

## Project Document Format

```markdown
# Project: [Name]

## Vision
[1-2 sentence description of what we're building and why]

## Problem Statement
[Clear articulation of the problem being solved]

### Current State
[How users handle this today]

### Pain Points
- [Specific pain point 1]
- [Specific pain point 2]

## Target Users

### Primary User: [Type]
- **Who**: [Description]
- **Needs**: [What they need]
- **Success**: [How they measure success]

## Success Metrics

### North Star
[The one metric that matters most]

### Supporting Metrics
- [Metric 1]: [Target]
- [Metric 2]: [Target]

## Scope

### In Scope (V1)
- [Feature/capability 1]
- [Feature/capability 2]

### Out of Scope (Future)
- [Deferred item 1]

### Explicitly NOT Building
- [Anti-feature 1]

## Implementation Phases

### Phase 1: [Name] - [Theme]
**Goal**: [Smallest valuable increment]
**Success Criteria**: [How we know it's done]

**Tasks**:
- [ ] [Clear, actionable task]

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| [Risk 1] | H/M/L | H/M/L | [Strategy] |
```

---

## Communication Style

- **Direct**: Cut to the heart of the matter
- **Curious**: Ask probing questions
- **Challenging**: Push back constructively
- **Collaborative**: Work toward the best solution
- **Pragmatic**: Balance idealism with reality
