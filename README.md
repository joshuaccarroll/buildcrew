# BuildCrew

**AI-powered development with expert personas that review each other's work.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## The Problem

AI can write code fast. But fast code without review becomes technical debt.

When you let AI code without guardrails, you get:
- Over-engineered abstractions nobody asked for
- Security vulnerabilities hiding in plain sight
- Tests that pass but don't test anything meaningful
- Features that ship but don't solve the actual problem

**BuildCrew fixes this by giving AI the same quality gates your human team uses.**

---

## The Solution

BuildCrew is an autonomous development pipeline where **expert AI personas review each other's work**.

Every feature goes through:
1. A **Product Manager** who challenges scope and finds the real problem
2. A **UX Designer** who creates intuitive, accessible interfaces
3. A **Feature Engineer** who ships pragmatic, user-focused code
4. A **Principal Engineer** who reviews plans and code for quality
5. A **QA Engineer** who writes tests that actually catch bugs
6. A **Security Engineer** who blocks vulnerabilities before they ship

**No single AI agent has the final say.** Each persona has expertise, standards, and veto power.

| Without BuildCrew | With BuildCrew |
|-------------------|----------------|
| AI writes code fast, you review later | Expert personas review in real-time |
| Security issues slip through | Security blocks deployment |
| Tests for coverage, not correctness | Tests that catch real bugs |
| Over-engineered for hypothetical futures | Pragmatic code for today's needs |

---

## Quick Start

### 1. Install (once, globally)

```bash
curl -fsSL https://raw.githubusercontent.com/joshuaccarroll/buildcrew/main/install.sh | bash
```

### 2. Initialize your project

```bash
cd your-project
buildcrew init
```

### 3. Run

```bash
buildcrew run
```

That's it. If you don't have a backlog yet, BuildCrew launches the Product Manager to help you define your project. Once you have tasks, it processes each one through the full persona pipeline.

**Ad-hoc usage:** Invoke any persona directly with `/buildcrew <persona-name>` (e.g., `/buildcrew security-engineer` for a security audit).

---

## The Expert Personas

### Product Manager
*"Users tell you what they want. Your job is to understand what they need."*

- Challenges scope and finds the real problem
- Pushes back on over-complication
- Creates phased implementation plans
- **Invoked via**: `/build` or `/buildcrew product-manager`

### UX Designer
*"Good design is invisible. Users shouldn't have to think."*

- Applies 7 core design principles
- Creates comprehensive design specs
- Champions accessibility from the start
- **Invoked via**: `/build` (optional) or `/buildcrew ux-designer`

### Feature Engineer
*"A feature in production is worth 10 features in planning."*

- Ships user-focused features pragmatically
- Follows existing codebase patterns
- Balances velocity with quality
- **Will avoid**: Scope creep, gold-plating, premature abstraction

### Principal Engineer
*"The best code is the code you don't have to write."*

- Reviews plans before implementation
- Reviews code for quality and patterns
- Blocks over-engineering and code smells
- **Will reject**: Functions > 20 lines, files > 300 lines, deep nesting, magic numbers

### QA Engineer
*"A test that can't fail is worthless."*

- Creates test plans with real coverage
- Writes tests that fail meaningfully
- Covers happy paths AND edge cases
- **Will catch**: Untested business logic, false positives, missing boundaries

### Security Engineer
*"Security is not a feature. It's a foundation."*

- Performs OWASP Top 10 audits
- Detects hardcoded secrets
- Validates input handling
- **Will block**: Any critical/high vulnerabilities before commit

---

## The Workflow

```
┌──────────────────────────────────────────────────────────────────┐
│                         BuildCrew Pipeline                        │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│   PLAN ──► PLAN REVIEW ──► BUILD ──► CODE REVIEW ──► TEST        │
│              (Principal)      (Feature)   (Principal)    (QA)     │
│                                                                   │
│                           ┌─────────────┐                         │
│   COMMIT ◄── SECURITY ◄──┤   VERIFY    │◄── REFACTOR (if needed) │
│              (blocks!)    │  (blocking) │                         │
│                           └─────────────┘                         │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

**Key features:**
- **Quality gates** at every phase
- **Automatic iteration** when reviews find issues
- **Blocking security** - no commit until vulnerabilities are fixed
- **Customizable** - modify phases or remove them entirely

---

## Customization

### Custom Workflow

Skip phases, add new ones, or change the flow:

```bash
# Copy the example and edit
cp .buildcrew/workflow.md.example .buildcrew/workflow.md
```

```markdown
# Minimal workflow - just build, test, commit
## Phases

### Phase 1: BUILD
agent: feature-engineer

### Phase 2: TEST
agent: qa-engineer

### Phase 3: COMMIT
agent: none
```

### Project Rules

Add your team's standards:

```bash
# Copy the example and edit
cp .buildcrew/rules/project-rules.md.example .buildcrew/rules/project-rules.md
```

```markdown
## Extend: Custom Rules

### Linting
- Run `npm run lint` before committing

### Naming Conventions
- Components: PascalCase, utilities: camelCase

### Operational
- Use exponential backoff for API calls
- Batch updates to prevent thundering herd
```

See `.buildcrew/rules/project-rules.md.example` for more examples.

---

## CLI Commands

```bash
buildcrew              # Show help
buildcrew init         # Link project to BuildCrew
buildcrew run          # Run workflow on BACKLOG.md
buildcrew run --single # Process one task and stop
buildcrew run --dry-run # Preview without executing
buildcrew plugins      # Show recommended plugins
buildcrew update       # Update BuildCrew
buildcrew uninstall    # Remove BuildCrew
```

---

## How It Works

1. **Install once** to `~/.buildcrew/` with all personas, rules, and workflows
2. **Link any project** with `buildcrew init` (creates `.buildcrew/` for your customizations)
3. **Rules merge** in order: global defaults → persona rules → your project rules

---

## Permissions & Safety

> **⚠️ Review before use:** These permissions enable autonomous operation. Review `.claude/settings.json` after `buildcrew init` and customize for your security requirements. See [Customize Permissions](#customize-permissions) below.

BuildCrew configures Claude Code with comprehensive permissions for **autonomous operation** while blocking genuinely dangerous commands.

### What's Allowed (No Prompts)

| Category | Commands |
|----------|----------|
| **File Operations** | Read, Write, Edit, Glob, Grep |
| **Package Managers** | npm, yarn, pnpm, bun, pip, poetry, cargo, go, gem, composer |
| **Build Tools** | make, cmake, gcc, docker, kubectl, terraform |
| **Git Operations** | All except force-push and hard reset |
| **Shell Utilities** | ls, cat, grep, find, sed, awk, curl, jq, tar, etc. |
| **File Management** | mkdir, cp, mv, rm, chmod, ln |
| **Project Scripts** | ./test.sh, ./build.sh, ./scripts/* |

### What's Blocked (Always)

| Category | Why |
|----------|-----|
| **Privilege escalation** | `sudo`, `su`, `doas` |
| **System destruction** | `rm -rf /`, `rm -rf ~`, system directories |
| **Git destruction** | `git push --force`, `git reset --hard`, `git clean -fd` |
| **Remote access** | `ssh`, `scp`, `rsync` |
| **System control** | `shutdown`, `reboot`, `systemctl`, `launchctl` |
| **Secrets files** | `.env`, `*.pem`, `*.key`, `.aws/*`, credentials |

### Customize Permissions

Add project-specific permissions in `.claude/settings.local.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(ssh deploy@staging:*)"
    ],
    "deny": [
      "Bash(npm publish:*)"
    ]
  }
}
```

The local file merges with the global settings. Deny rules always win.

### Safety Features

- **No auto-push** - Commits stay local until you review and push
- **Blocking gates** - Security issues must be fixed before commit
- **Deny-list protection** - System directories protected even when `rm` is allowed

---

## Requirements

- **Claude Code CLI** installed and authenticated
- **jq** for JSON parsing (`brew install jq`)

---

## Acknowledgments

BuildCrew was inspired by [The Ralph Loop](https://ghuntley.com/ralph/) by Geoffrey Huntley.

---

## License

MIT

---

## Links

- **Repository**: [github.com/joshuaccarroll/buildcrew](https://github.com/joshuaccarroll/buildcrew)
- **Issues**: [GitHub Issues](https://github.com/joshuaccarroll/buildcrew/issues)
- **Claude Code**: [claude.ai/code](https://claude.ai/code)
- **The Ralph Loop**: [ghuntley.com/ralph](https://ghuntley.com/ralph/)
