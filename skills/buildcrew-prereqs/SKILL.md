---
name: buildcrew-prereqs
description: BuildCrew Prerequisite Detection phase — identify manual setup requirements before research begins
allowed-tools: Read, Write, Bash
---

# BuildCrew — Prerequisite Detection

`[Phase: prereqs | Input: .claude/spec.md | Output: .claude/prereqs-report.md, .claude/phase-result.json | Next: RESEARCH]`

You are executing the prereqs phase of the BuildCrew autonomous development workflow.

## Your Task

Scan `.claude/spec.md` for external prerequisites that require manual setup before the build can succeed. Run verification commands to check each one. Write findings to `.claude/prereqs-report.md` and signal the result via `.claude/phase-result.json`.

---

## PREREQS: Prerequisite Detection

**Goal**: Detect external dependencies that cannot be satisfied by code alone, verify them, and block the pipeline early if they are unmet.

### Step 1 — Read the spec

Read `.claude/spec.md` in full. Scan for signals that manual setup is required, including but not limited to:

- **Cloud providers**: AWS, GCP, Azure, DigitalOcean, Cloudflare, Vercel, Heroku, Fly.io
- **API keys / tokens**: any mention of `API_KEY`, `SECRET`, `TOKEN`, `ACCESS_KEY`, or named service credentials (e.g., `STRIPE_SECRET_KEY`, `SENDGRID_API_KEY`, `GITHUB_TOKEN`)
- **Environment variables**: `MY_VAR`, `DATABASE_URL`, `REDIS_URL`, `.env` files, `export VAR=`, `process.env.VAR`
- **Database provisioning**: Postgres, MySQL, MongoDB, Redis, SQLite schema creation, migrations against a live DB
- **DNS / domain configuration**: custom domains, CNAME records, SSL certificates, Let's Encrypt setup
- **Third-party accounts / service registration**: OAuth apps, webhook endpoints, Twilio numbers, Stripe Connect
- **OAuth credentials**: `CLIENT_ID`, `CLIENT_SECRET`, redirect URIs, OAuth app creation in external dashboards
- **CLI tools required at runtime**: `aws`, `gcloud`, `kubectl`, `terraform`, `docker`, `pg_isready`, `redis-cli`, etc.

If the spec contains none of these signals, skip to Step 3 with verdict `none_required`.

### Step 2 — Verify each prerequisite

For each detected prerequisite:

1. Write a plain-English description of what is needed.
2. Choose a concrete verification command appropriate to the prerequisite type:

   | Prerequisite type | Example verification command |
   |---|---|
   | AWS credentials | `aws sts get-caller-identity` |
   | GCP credentials | `gcloud auth print-access-token` |
   | Azure credentials | `az account show` |
   | Env var set | `test -n "${VAR_NAME}" && echo "set" || echo "missing"` |
   | Postgres reachable | `pg_isready -h localhost -p 5432` |
   | Redis reachable | `redis-cli ping` |
   | Docker running | `docker info` |
   | kubectl configured | `kubectl cluster-info` |
   | CLI tool installed | `command -v toolname` |
   | Generic env var | `echo "${VAR_NAME:-MISSING}"` |

3. Run the verification command via Bash. Record whether it **passed** (exit 0) or **failed** (non-zero exit or output indicates missing/error).

### Step 3 — Write `.claude/prereqs-report.md`

If no prerequisites were detected:

```
No manual prerequisites detected.
```

Otherwise, write one section per prerequisite:

````markdown
## <Prerequisite Name>

**What is needed**: <plain-English description>

**Verification command**: `<command>`

**Result**: PASS | FAIL

**Output**:
```
<command output>
```
````

### Step 4 — Determine verdict and write `.claude/phase-result.json`

| Verdict | Condition |
|---|---|
| `none_required` | No prerequisite signals found in spec |
| `all_satisfied` | Prerequisites found; all verification commands exited 0 |
| `blocked` | One or more verification commands failed |

Write `.claude/phase-result.json` last — the workflow terminates the Claude process when this file appears. Do not write it until all other work is complete.

```json
{
  "phase": "prereqs",
  "verdict": "<none_required|all_satisfied|blocked>",
  "details": "<brief summary: e.g., 'No prerequisites detected' or '2 of 3 prerequisites satisfied; STRIPE_SECRET_KEY not set'>"
}
```
