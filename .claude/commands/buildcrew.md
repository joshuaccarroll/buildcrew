---
name: buildcrew
description: Invoke a BuildCrew persona for ad-hoc tasks
arguments:
  - name: persona
    description: "Persona to invoke: principal-engineer, feature-engineer, security-engineer, qa-engineer, product-manager, ux-designer"
    required: true
---

# BuildCrew Persona Invocation

You are invoking a BuildCrew expert persona for an ad-hoc task.

## Available Personas

| Persona | Expertise | Use For |
|---------|-----------|---------|
| `principal-engineer` | Architecture, code review, quality | Plan reviews, code reviews, architecture guidance |
| `feature-engineer` | Pragmatic implementation | Building user-facing features quickly |
| `security-engineer` | Security audits, OWASP | Security reviews, vulnerability checks |
| `qa-engineer` | Testing, quality assurance | Test planning, writing tests, coverage |
| `product-manager` | Requirements, prioritization | Project discovery, scoping, planning |
| `ux-designer` | UI/UX, accessibility | Design specs, user flows, visual design |

## Invocation

The user requested: `/buildcrew $ARGUMENTS`

**Parse the persona argument and invoke the corresponding agent.**

### If persona is `principal-engineer`:
Use the Task tool to launch the `principal-engineer` agent with the user's context.
Ask the user what they need reviewed (plan, code, architecture).

### If persona is `feature-engineer`:
Use the Task tool to launch the `feature-engineer` agent.
Ask the user what feature they want to build.

### If persona is `security-engineer`:
Use the Task tool to launch the `security-engineer` agent.
Ask the user what they want audited (specific files, entire codebase, recent changes).

### If persona is `qa-engineer`:
Use the Task tool to launch the `qa-engineer` agent.
Ask the user what they need tested (create test plan, write tests, run tests).

### If persona is `product-manager`:
Use the Task tool to launch the `product-manager` agent.
Start the interactive discovery process for a new project.

### If persona is `ux-designer`:
Use the Task tool to launch the `ux-designer` agent.
Start the interactive design discovery process.

## Example Usage

```
/buildcrew security-engineer
→ Launches security audit on current project

/buildcrew product-manager
→ Starts interactive product discovery session

/buildcrew principal-engineer
→ Initiates code or plan review
```

## Important

Each persona has:
1. **Specific expertise** defined in their agent file
2. **Rules** they follow from the rules directory
3. **Output formats** for their deliverables

The persona will operate with their full expertise and follow BuildCrew's quality standards.
