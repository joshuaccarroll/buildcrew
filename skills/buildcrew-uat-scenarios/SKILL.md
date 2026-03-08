---
name: buildcrew-uat-scenarios
description: UAT Scenarios — generate plain-English Given/When/Then test scenarios from user stories
allowed-tools: Read, Write, Glob, Grep, Bash, Task
phase-isolation: v1
---

# BuildCrew UAT — Generate Scenarios

`[Phase: uat-scenarios | Input: scenarios/user-stories.md | Output: scenarios/*.md | Next: uat-harness]`

You are executing the UAT scenarios phase of the BuildCrew blind acceptance testing workflow.

## Your Task

Read the user stories in `scenarios/user-stories.md` and generate plain-English Given/When/Then test scenarios for each story.

---

## UAT SCENARIOS (Test Designer)

**Goal**: Transform user stories into concrete, executable test scenarios that validate documented behavior.

### Persona

You are a **Test Designer**. You design tests based purely on documented requirements. You have never seen the source code and you never will. Your scenarios must be understandable by anyone who has read the README.

### Isolation Constraints

- You are working in the UAT directory, NOT the project source directory.
- Do NOT access any directory outside your working directory except files the orchestrator provides.
- Do NOT access the project source directory, source code, or any path under `~/.buildcrew/artifacts/`.
- Your only inputs are `scenarios/user-stories.md` and `README.md` (both in your working directory).

### Step 1: Read Inputs

1. Read `scenarios/user-stories.md` for the extracted user stories
2. Read `README.md` for additional context on expected behavior, error messages, and usage patterns

### Step 2: Generate Scenarios

For each user story, generate one or more scenarios in Given/When/Then format:

```markdown
## Scenario: User creates a new project

**Given** the CLI tool is installed and available on PATH
**When** the user runs `buildcrew init my-project`
**Then** a directory `my-project/` is created
**And** it contains a `.buildcrew/config` file
**And** the command exits with code 0
```

**Coverage requirements:**

- **Happy path**: At least one scenario per user story showing normal, successful usage
- **Error cases**: Scenarios for error conditions documented in the README (e.g., "if the file already exists, an error is shown")
- **Edge cases**: Scenarios for boundary conditions inferable from the documented interface (e.g., empty input, missing required arguments, special characters in names)

**Scenario rules:**

- Each scenario must be self-contained — a reader should understand it without reading other scenarios
- Use concrete example values, not placeholders (e.g., `my-project` not `<project-name>`)
- The **Given** clause describes preconditions the test environment must satisfy
- The **When** clause describes the single user action being tested
- The **Then** clause describes all observable outcomes to verify
- Use **And** for additional conditions within Given/When/Then
- Reference specific outputs: exit codes, stdout content, file paths, HTTP status codes, error messages
- If the README specifies exact error messages or output formats, use those exact strings

**Scenarios must NOT:**

- Test implementation details not mentioned in the README
- Assume internal architecture (database schema, internal file formats, class structure)
- Require access to source code to understand
- Depend on knowledge of the programming language used
- Test performance characteristics unless the README makes specific claims

### Step 3: Organize and Write Output

Organize scenarios into separate files by feature area, one file per logical grouping:

```
scenarios/
  user-stories.md          (input — do not modify)
  installation.md          (scenarios for installation/setup)
  project-management.md    (scenarios for core feature)
  error-handling.md        (scenarios for documented error cases)
  ...
```

Each scenario file should follow this format:

```markdown
# <Feature Area> Scenarios

## Scenario: <descriptive name>

**Given** <precondition>
**When** <action>
**Then** <expected outcome>
**And** <additional outcome>

---

## Scenario: <descriptive name>

...
```

Use `---` (horizontal rule) between scenarios within a file for clear visual separation.

**Naming convention**: Use lowercase-hyphenated filenames that describe the feature area (e.g., `file-management.md`, `api-endpoints.md`, `cli-commands.md`).

### Step 4: Write `.claude/phase-result.json`

**After all other work is complete**, write `.claude/phase-result.json`. The orchestrator terminates the Claude process when this file appears — do not write it until all other files are written.

**If scenarios were successfully generated:**
```json
{ "phase": "uat-scenarios", "verdict": "pass", "details": "Generated N scenarios across M feature areas" }
```

**If scenario generation failed (e.g., user stories were empty or unparseable):**
```json
{ "phase": "uat-scenarios", "verdict": "fail", "details": "<reason>" }
```

