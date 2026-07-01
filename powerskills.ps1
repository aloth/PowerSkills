<#
.SYNOPSIS
    PowerSkills CLI — Windows capabilities for AI agents.
.DESCRIPTION
    Standalone PowerShell toolkit exposing Outlook, Edge browser (CDP),
    desktop automation, and system commands as structured JSON skills.
.EXAMPLE
    .\powerskills.ps1 list
    .\powerskills.ps1 outlook inbox --limit 10
    .\powerskills.ps1 browser tabs
    .\powerskills.ps1 desktop screenshot
    .\powerskills.ps1 system exec --command "whoami"
#>

param(
    [Parameter(Position=0)] [string]$Skill = "list",
    [Parameter(Position=1)] [string]$Action = "",
    [Parameter(ValueFromRemainingArguments)] [string[]]$Rest
)

$ErrorActionPreference = "Stop"
$script:SkillsRoot = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "skills"
$script:ConfigPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "config.json"

# ─── Config ───
function Get-PSConfig {
    $defaults = @{
        edge_debug_port = 9222
        default_timeout = 30
        outlook_body_max_chars = 5000
        output_dir = ""
    }
    if (Test-Path $script:ConfigPath) {
        try {
            $file = Get-Content $script:ConfigPath -Raw | ConvertFrom-Json
            foreach ($prop in $file.PSObject.Properties) {
                $defaults[$prop.Name] = $prop.Value
            }
        } catch {}
    }
    return $defaults
}

# ─── Parse named args from Rest ───
function Parse-Args {
    param([string[]]$Args_)
    $parsed = @{}
    $i = 0
    while ($i -lt $Args_.Count) {
        if ($Args_[$i] -match '^--(.+)$') {
            $key = $Matches[1]
            if (($i + 1) -lt $Args_.Count -and $Args_[$i+1] -notmatch '^--') {
                $parsed[$key] = $Args_[$i+1]
                $i += 2
            } else {
                $parsed[$key] = $true
                $i++
            }
        } else {
            $i++
        }
    }
    return $parsed
}

# ─── Output helper ───
function Write-Result {
    param($Data, [int]$ExitCode = 0)
    $envelope = @{
        status = if ($ExitCode -eq 0) { "success" } else { "error" }
        exit_code = $ExitCode
        data = $Data
        timestamp = (Get-Date).ToString("o")
    }
    $envelope | ConvertTo-Json -Depth 10 -Compress
    exit $ExitCode
}

function Write-Error-Result {
    param([string]$Message)
    Write-Result -Data @{ error = $Message } -ExitCode 1
}

# ─── Skill list ───
if ($Skill -eq "list") {
    $skills = @()
    foreach ($dir in (Get-ChildItem -Path $script:SkillsRoot -Directory)) {
        $skillMd = Join-Path $dir.FullName "SKILL.md"
        $skillPs = Join-Path $dir.FullName "$($dir.Name).ps1"
        if (Test-Path $skillPs) {
            $desc = ""
            if (Test-Path $skillMd) {
                $lines = Get-Content $skillMd -TotalCount 5
                foreach ($line in $lines) {
                    if ($line -match '^>\s*(.+)') { $desc = $Matches[1]; break }
                }
            }
            $skills += @{ name = $dir.Name; description = $desc; path = $skillPs }
        }
    }
    Write-Result -Data $skills
}
# ─── Skill help ───
elseif ($Action -eq "help" -or $Action -eq "" -or $Action -eq "list-actions") {
    $skillMd = Join-Path $script:SkillsRoot "$Skill\SKILL.md"
    if (Test-Path $skillMd) {
        # Cast to [string] to strip PSObject NoteProperties that Get-Content -Raw
        # attaches (PSPath, PSProvider, Drive, ...). Without this, ConvertTo-Json
        # in Windows PowerShell 5.1 recurses into those properties and hangs.
        $content = [string](Get-Content $skillMd -Raw)
        Write-Result -Data @{ skill = $Skill; help = $content }
    } else {
        Write-Error-Result "Unknown skill: $Skill. Run: .\powerskills.ps1 list"
    }
}
# ─── Dispatch to skill ───
else {
    $skillScript = Join-Path $script:SkillsRoot "$Skill\$Skill.ps1"
    if (-not (Test-Path $skillScript)) {
        Write-Error-Result "Skill not found: $Skill"
    }

    $args_ = Parse-Args -Args_ $Rest
    $config = Get-PSConfig

    try {
        $result = & $skillScript -Action $Action -Args_ $args_ -Config $config
        Write-Result -Data $result
    } catch {
        Write-Error-Result $_.Exception.Message
    }
}
