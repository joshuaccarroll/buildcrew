---
name: buildcrew
description: Execute a buildcrew workflow or adopt a BuildCrew persona inline
arguments:
  - name: request
    description: "Persona slug, slug:task, or plain task"
    required: false
---

## Dispatch

The user invoked `/buildcrew $ARGUMENTS`.

### Step 1: Empty input check

If `$ARGUMENTS` is absent or empty (no characters at all), output the following list and stop. Do not invoke any Skill tool. Do not read any rules files. **This guard fires only when `$ARGUMENTS` itself is absent or empty — a string like `product-manager:` (colon present, nothing after it) is NOT empty and must proceed to Step 2.**

```
Available BuildCrew personas:

  /buildcrew product-manager:<task>
    Example: /buildcrew product-manager:prioritize the backlog for next sprint

  /buildcrew principal-engineer:<task>
    Example: /buildcrew principal-engineer:review the authentication architecture

  /buildcrew feature-engineer:<task>
    Example: /buildcrew feature-engineer:add pagination to the users list

  /buildcrew qa-engineer:<task>
    Example: /buildcrew qa-engineer:write integration tests for the payment flow

  /buildcrew security-engineer:<task>
    Example: /buildcrew security-engineer:audit the API endpoints for injection vulnerabilities

  /buildcrew ux-designer:<task>
    Example: /buildcrew ux-designer:design the onboarding flow for new users

Use /buildcrew <slug>:<task> to adopt a persona inline.
Use /buildcrew <task description> to run the full development pipeline.
```

### Step 2: Slug detection

Trim leading and trailing whitespace from `$ARGUMENTS`. Normalize to lowercase for matching only — preserve the original string for all downstream use (e.g., passing to the Skill tool).

Use the following slug table:

| Slug | Rules file |
|---|---|
| `product-manager` | `product-manager-rules.md` |
| `principal-engineer` | `principal-engineer-rules.md` |
| `feature-engineer` | `feature-engineer-rules.md` |
| `qa-engineer` | `qa-engineer-rules.md` |
| `security-engineer` | `security-engineer-rules.md` |
| `ux-designer` | `ux-designer-rules.md` |

Apply detection in this exact order (check each condition in sequence; use the first match):

1. **Exact slug match**: The lowercased, trimmed string is exactly one of the 6 slugs above (a single token with no colon and no spaces) → **persona mode**; request is the empty string
2. **Slug-colon prefix**: The lowercased, trimmed string starts with `<slug>:` (slug immediately followed by a colon, with optional whitespace after the colon) → **persona mode**; extract everything after the first colon as the request (may be empty)
3. **Slug-space prefix**: The lowercased, trimmed string starts with `<slug>` followed by a space (the first whitespace-delimited token is a valid slug, but no colon appears anywhere in the entire string) → **pipeline mode**
4. **No slug match**: No valid slug is present → **pipeline mode**

**Important ordering note**: Check exact-slug match (condition 1) before slug-colon prefix (condition 2) to ensure a bare slug like `product-manager` (no colon) is caught by condition 1 rather than falling through.

### Step 3: Route

#### Persona mode

1. Attempt to read `~/.buildcrew/rules/core-principles.md` using the Read tool
   - If the file does not exist, output a message explaining that the rules files are missing and that the user should run `install.sh` from the repo root, then stop
2. Attempt to read `~/.buildcrew/rules/<slug>-rules.md` using the Read tool (where `<slug>` is the lowercase matched slug)
   - If the file does not exist, output the same error message about running `install.sh` from the repo root, then stop
3. After both files are read successfully, fully adopt the persona defined in those files
4. If the request is non-empty, work on it immediately in the adopted persona
5. If the request is empty (bare slug match, or `<slug>:` with nothing after the colon), introduce the persona by name and domain and explicitly invite the user to provide a task
6. Stay in this persona for the entire conversation
7. **Do NOT write any `.claude/` status files**
8. **Do NOT invoke the Skill tool**

#### Pipeline mode

Invoke the `buildcrew` skill via the Skill tool, passing the original (non-lowercased, non-trimmed) `$ARGUMENTS` string as the argument value. Use skill name `buildcrew`.
