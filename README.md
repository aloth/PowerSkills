# PowerSkills

[![License: MIT](https://img.shields.io/github/license/aloth/PowerSkills)](https://github.com/aloth/PowerSkills/blob/main/LICENSE)
[![Release](https://img.shields.io/github/v/release/aloth/PowerSkills)](https://github.com/aloth/PowerSkills/releases)
[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell&logoColor=white)](https://docs.microsoft.com/en-us/powershell/)
[![Windows](https://img.shields.io/badge/Windows-10%2F11-0078D6?logo=windows&logoColor=white)](https://github.com/aloth/PowerSkills)
[![Stars](https://img.shields.io/github/stars/aloth/PowerSkills)](https://github.com/aloth/PowerSkills/stargazers)

![PowerSkills Hero](assets/powerskills-ai-agents-windows-powershell-automation.jpg)

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
├── powerskills.ps1          # CLI entry point / dispatcher
├── config.json              # Configuration
├── lib/
│   └── bootstrap.ps1        # Shared arg parsing & JSON output helpers
├── assets/
│   └── powerskills-ai-agents-windows-powershell-automation.jpg
├── skills/
│   ├── outlook/
│   │   ├── SKILL.md         # Agent-readable skill documentation
│   │   └── outlook.ps1      # Outlook COM automation
│   ├── browser/
│   │   ├── SKILL.md
│   │   └── browser.ps1      # Edge CDP automation
│   ├── desktop/
│   │   ├── SKILL.md
│   │   └── desktop.ps1      # Win32 window/screenshot/clipboard
│   └── system/
│       ├── SKILL.md
│       └── system.ps1       # System info, processes, exec
├── tests/
│   └── test-all.ps1         # Test suite (-SkipBrowser, -SkipOutlook)
├── SKILL.md                 # Root skill metadata
├── LICENSE                  # MIT
└── README.md
```

## Contributing

Contributions are welcome! Here's how you can help:

- **Report bugs** - open an [issue](https://github.com/aloth/PowerSkills/issues) with the Bug Report template
- **Request features** - suggest new actions or skills via [Feature Request](https://github.com/aloth/PowerSkills/issues)
- **Add a skill** - create a new folder under `skills/` with a `.ps1` and `SKILL.md`
- **Improve existing skills** - better error handling, new actions, documentation fixes
- **Join the discussion** - share ideas in [Discussions](https://github.com/aloth/PowerSkills/discussions)

When adding or modifying skills, please follow the existing patterns:
1. Use `lib\bootstrap.ps1` for arg parsing and JSON output
2. Return results via `Write-SkillResult` / `Write-SkillError`
3. Include a `SKILL.md` with action documentation
4. Test both dispatcher and standalone modes

## License

MIT
