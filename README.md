# PowerSkills

Windows capabilities for AI agents — Outlook, Edge browser, desktop automation, and shell commands as structured JSON skills.

## Quick Start

```powershell
# List available skills
.\powerskills.ps1 list

# Get skill help
.\powerskills.ps1 outlook help

# Run actions
.\powerskills.ps1 outlook inbox --limit 10
.\powerskills.ps1 browser tabs
.\powerskills.ps1 desktop screenshot --out-file screen.png
.\powerskills.ps1 system exec --command "whoami"
```

## Skills

| Skill | Description |
|-------|-------------|
| `outlook` | Email & calendar via Outlook COM |
| `browser` | Edge automation via CDP (Chrome DevTools Protocol) |
| `desktop` | Screenshots, window management, keystrokes |
| `system` | Shell commands, processes, system info |

## Output Format

All commands return JSON with consistent envelope:

```json
{
  "status": "success",
  "exit_code": 0,
  "data": { ... },
  "timestamp": "2026-03-06T16:00:00+01:00"
}
```

## Requirements

- Windows 10/11
- PowerShell 5.1+
- Microsoft Outlook (for `outlook` skill)
- Microsoft Edge with `--remote-debugging-port=9222` (for `browser` skill)

### Execution Policy

If scripts are blocked (`UnauthorizedAccess` error), set the execution policy:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

Or run one-off with bypass:

```powershell
powershell -ExecutionPolicy Bypass -File .\powerskills.ps1 list
```

## Standalone Skills

Each skill can be called directly without `powerskills.ps1`:

```powershell
.\skills\outlook\outlook.ps1 inbox --limit 5
.\skills\system\system.ps1 info
.\skills\browser\browser.ps1 tabs
```

Standalone mode uses `lib\bootstrap.ps1` for arg parsing and JSON output.

### Edge CDP Setup

```powershell
# Start Edge with debugging enabled
Start-Process "msedge" -ArgumentList "--remote-debugging-port=9222"
```

## Configuration

Edit `config.json`:

```json
{
  "edge_debug_port": 9222,
  "default_timeout": 30,
  "outlook_body_max_chars": 5000,
  "output_dir": ""
}
```

## For AI Agents

Each skill has a `SKILL.md` with action documentation. Point your agent to `skills/<name>/SKILL.md` for structured capability discovery.

### Agent Integration

Add to your skills directory or reference directly:

```yaml
# SKILL.md reference
skills:
  - name: powerskills
    description: Windows automation via PowerShell (Outlook, Edge, desktop)
    location: /path/to/PowerSkills/
```

## Project Structure

```
PowerSkills/
├── powerskills.ps1      # CLI entry point
├── config.json          # Configuration
├── skills/
│   ├── outlook/
│   │   ├── SKILL.md
│   │   └── outlook.ps1
│   ├── browser/
│   │   ├── SKILL.md
│   │   └── browser.ps1
│   ├── desktop/
│   │   ├── SKILL.md
│   │   └── desktop.ps1
│   └── system/
│       ├── SKILL.md
│       └── system.ps1
└── README.md
```

## License

MIT
