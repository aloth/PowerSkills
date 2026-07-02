---
name: powerskills-workiq
description: Microsoft 365 automation via Work IQ (Graph-backed CLI). Ask natural-language questions against Outlook mail, calendar, Teams messages, SharePoint, OneDrive, and People. Fetch entities by URL, run OpenAPI actions (sendMail, copy, move), call functions (getSchedule, delta, reminderView), list Work IQ agents. Use when needing tenant-side M365 data without depending on a running Outlook desktop client. Includes install/check helpers so the skill covers first-time setup.
license: MIT
metadata:
  author: aloth
  cli: powerskills
  parent: powerskills
---

# PowerSkills - Work IQ

Microsoft 365 automation through the official [Work IQ](https://github.com/microsoft/work-iq) CLI. Talks straight to Graph via silent SSO, so it reaches mail, calendar, Teams, SharePoint, OneDrive, and People without needing a running Outlook desktop client.

## Why not just use `outlook`?

| Aspect | `powerskills workiq` | `powerskills outlook` |
|--------|----------------------|------------------------|
| Backend | Microsoft Graph via Work IQ CLI | Local Outlook COM |
| Reach | Mail + Calendar + Teams + SharePoint + OneDrive + People | Mail + Calendar only |
| Outlook client required | No | Yes (must be running) |
| Elevation | Works from admin or user shell | Non-admin only (COM integrity) |
| Tenant setup | Requires user consent (some tenants need admin consent) | None |
| Output shape | Structured Graph entities + deep-links | COM properties |

Use `workiq` for the strong, cloud-side path. Keep `outlook` for offline or COM-only situations.

## Requirements

- Windows 10 or 11
- PowerShell 5.1 or later
- Node.js and npm (for `install` action)
- Microsoft 365 work account signed in on the machine (Windows Account Manager / SSO)
- Work IQ CLI (`workiq`) on `PATH` - the `install` action handles this

## Setup in one command

If Work IQ is not installed yet, this skill can bootstrap it:

```powershell
.\powerskills.ps1 workiq install
.\powerskills.ps1 workiq accept-eula
.\powerskills.ps1 workiq check
```

`install` runs `npm install -g @microsoft/workiq`. `accept-eula` records EULA acceptance. `check` reports version, EULA state, and whether the CLI is reachable on `PATH`.

## Actions

```powershell
.\powerskills.ps1 workiq <action> [--params]
```

| Action | Params | Description |
|--------|--------|-------------|
| `check` | | Report install state: `installed`, `version`, `path`, `eula_accepted` |
| `install` | `[--scope user\|machine]` | Install Work IQ globally via npm (`user` scope by default) |
| `accept-eula` | | Accept Work IQ EULA (required once before any query) |
| `version` | | Show Work IQ CLI version |
| `ask` | `--question "text" [--agent name] [--timeout 120]` | Natural-language query against a Work IQ agent |
| `agents` | `[--get-card name]` | List Work IQ agents, or return one agent card |
| `fetch` | `--url <graph-path>` | Fetch a Work IQ entity by path (e.g. `/me`, `/me/messages`) |
| `search-paths` | `--filter <regex> [--backend graph-v1\|sharepoint-rest\|dataverse]` | Discover Graph paths by regex (helps build `fetch`/`call-function` URLs) |
| `get-schema` | `--path <api-path> [--method get\|post\|patch\|delete] [--api-version v1.0\|beta]` | Return the OpenAPI schema for a given path |
| `call-function` | `--url <path-with-query>` | Call a read-only Graph function (e.g. `/me/calendar/getSchedule?...`). Include the query string in `--url`. |
| `do-action` | `--url <path> [--body <json>]` | POST a Graph action (e.g. `/me/sendMail`) |
| `create` | `--url <collection> --body <json>` | POST a new entity (e.g. `/me/messages`) |
| `update` | `--url <entity> --body <json>` | PATCH an existing entity (e.g. `/me/events/{id}`) |
| `delete` | `--url <entity>` | DELETE an entity |
| `debug` | `--conversation <id>` | Create a Work IQ debug share link for a conversation |
| `raw` | `--args "arg1 arg2 ..."` | Escape hatch: run any raw `workiq` sub-command |
| `help` | | Show this file |

## Examples

```powershell
# One-time setup
.\powerskills.ps1 workiq install
.\powerskills.ps1 workiq accept-eula
.\powerskills.ps1 workiq check

# Natural language against your inbox / calendar / Teams
.\powerskills.ps1 workiq ask --question "What's on my calendar tomorrow?"
.\powerskills.ps1 workiq ask --question "Summarize unread emails from the last 24h and prioritize"
.\powerskills.ps1 workiq ask --question "Show Teams messages from #engineering in the last 3 hours"

# List agents available in this tenant
.\powerskills.ps1 workiq agents

# Discover Graph paths and fetch entities
.\powerskills.ps1 workiq search-paths --filter "calendar"
.\powerskills.ps1 workiq fetch --url "/me/messages?$top=5"
.\powerskills.ps1 workiq get-schema --path "/me/calendar/events"

# Call a Graph function (query string lives in --url)
.\powerskills.ps1 workiq call-function --url "/me/calendar/getSchedule?startDateTime=2026-07-02T00:00:00&endDateTime=2026-07-02T23:59:59"

# Send a mail via Graph action
.\powerskills.ps1 workiq do-action --url "/me/sendMail" `
  --body '{"message":{"subject":"Hi","body":{"contentType":"Text","content":"Test"},"toRecipients":[{"emailAddress":{"address":"someone@example.com"}}]}}'

# Escape hatch for anything the wrapper does not surface yet
.\powerskills.ps1 workiq raw --args "policy list"
```

## Output

Every action returns the standard PowerSkills envelope:

```json
{
  "status": "success",
  "exit_code": 0,
  "data": { ... },
  "timestamp": "2026-07-01T18:00:00+02:00"
}
```

For actions that surface raw Work IQ output (`ask`, `raw`, `fetch`), `data` contains:

- `stdout` - the text Work IQ returned (ANSI codes are stripped)
- `stderr` - any warnings Work IQ printed
- `exit_code` - Work IQ's own exit code
- `command` - the exact argv that was executed (for debugging)

Structured actions (`check`, `version`, `agents`) return parsed fields.

## Notes and quirks

- **stdio transport only.** Work IQ's `mcp` command runs over stdio. This skill does not spin up an HTTP MCP server; if you want MCP integration, register `workiq mcp` in your host's MCP config directly.
- **`.cmd` vs `.exe`.** On Windows, calling shims from Node causes `spawn EINVAL`. This skill resolves the real `workiq.exe` under `%APPDATA%\npm\node_modules\@microsoft\workiq\bin\win-x64\workiq.exe` when possible, and falls back to whatever is on `PATH`.
- **First-run consent.** The first `ask` may pop a browser window for consent. After that, silent SSO takes over.
- **Tenant policy.** Some enterprise tenants require an admin to consent to Work IQ before users can use it. If `ask` fails with a consent error, share the message with your IT admin.
- **Deep-links can be long.** `ask` output often contains multi-hundred-character deep-link URLs. The wrapper leaves them intact so the agent can follow them.
