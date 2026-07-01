---
name: powerskills
description: Windows automation toolkit for AI agents. Provides Outlook email/calendar, Edge browser (CDP), desktop screenshots/window management, and shell commands via PowerShell. Install this for the full suite, or install individual sub-skills (powerskills-outlook, powerskills-browser, powerskills-desktop, powerskills-system) separately.
license: MIT
metadata:
  author: aloth
  cli: powerskills
---

# PowerSkills

Windows capabilities for AI agents via PowerShell. Each skill in `skills/` is independently discoverable.

## Setup

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

## Getting the executable scripts

AgentSkills (`npx skills add aloth/PowerSkills`) only publishes the Markdown skill definitions into `~\.agents\skills\powerskills\` (and the per-skill sub-folders). The `.ps1` files that actually do the work are **not** copied there. To run any action you need a working copy of this repository on disk:

```powershell
# Clone once, anywhere you like
git clone https://github.com/aloth/PowerSkills.git C:\Tools\PowerSkills
```

Invoke the CLI with the full path to `powerskills.ps1`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File C:\Tools\PowerSkills\powerskills.ps1 <skill> <action> [--param value ...]
```

To avoid repeating the path, either store it agent-side once or set an env var and reference that from any shell:

```powershell
[Environment]::SetEnvironmentVariable("POWERSKILLS_ROOT", "C:\Tools\PowerSkills", "User")
# New shells then use:
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:POWERSKILLS_ROOT\powerskills.ps1" list
```

## Usage

```powershell
.\powerskills.ps1 <skill> <action> [--param value ...]
.\powerskills.ps1 list                          # Discover available skills
.\powerskills.ps1 outlook inbox --limit 10       # Run an action
```

## Output Format

All actions return JSON:

```json
{"status": "success", "exit_code": 0, "data": {...}, "timestamp": "..."}
```

## Configuration

Edit `config.json`:

```json
{
  "edge_debug_port": 9222,
  "default_timeout": 30,
  "outlook_body_max_chars": 5000
}
```

## Skills

| Skill | Description |
|-------|-------------|
| [outlook](skills/outlook/SKILL.md) | Email & calendar via Outlook COM |
| [browser](skills/browser/SKILL.md) | Edge automation via CDP |
| [desktop](skills/desktop/SKILL.md) | Screenshots, window management, keystrokes |
| [system](skills/system/SKILL.md) | Shell commands, processes, system info |
