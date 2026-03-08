---
name: buildcrew-docs
description: BuildCrew Docs phase — update documentation based on changed files
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# BuildCrew Docs Phase

`[Phase: docs | Input: built code | Output: updated docs | Next: simplify]`

## Overview

This phase detects user-facing changes via git diff and updates the README.md accordingly.

## Implementation

1. Run `git diff --name-only HEAD` to discover files changed during build
2. Classify changes as user-facing if they match:
   - CLI: `bin/`, `*.sh` files under `bin/`
   - Config: `.buildcrew/config`, any `*.json` schema
   - Dependencies: `package.json`, `requirements.txt`, `Gemfile`, `go.mod`
   - API: files containing `api`, `schema`, or `routes`
3. If user-facing changes detected, update `README.md`
4. If no user-facing changes, skip README update
5. Always write `complete` verdict

## Phase Result Protocol

Write `.claude/phase-result.json`:

```json
{
  "phase": "docs",
  "verdict": "complete",
  "details": "Docs updated: [what was changed, or 'no user-facing changes detected']"
}
```
