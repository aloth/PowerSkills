<#
.SYNOPSIS
    PowerSkills test suite
.EXAMPLE
    .\tests\test-all.ps1
    .\tests\test-all.ps1 -SkipBrowser
    .\tests\test-all.ps1 -SkipOutlook
#>
param(
    [switch]$SkipBrowser,
    [switch]$SkipOutlook
)

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$pass = 0
$fail = 0

function Test-Skill {
    param([string]$Name, [scriptblock]$Code)
    
    try {
        $out = & $Code 2>&1
        $json = $out | ConvertFrom-Json -ErrorAction Stop
        if ($json.status -eq "success") {
            $script:pass++
            Write-Host "  PASS  " -ForegroundColor Green -NoNewline
            Write-Host $Name
        }
        else {
            $script:fail++
            Write-Host "  FAIL  " -ForegroundColor Red -NoNewline
            Write-Host "$Name - $($json.data.error)"
        }
    }
    catch {
        $script:fail++
        Write-Host "  FAIL  " -ForegroundColor Red -NoNewline
        Write-Host "$Name - $_"
    }
}

Write-Host ""
Write-Host "PowerSkills Test Suite" -ForegroundColor Cyan
Write-Host "======================"
Write-Host "Root: $root"
Write-Host ""

# Core
Write-Host "[ Core ]" -ForegroundColor Cyan
Test-Skill "list skills" { & "$root\powerskills.ps1" list }

# System
Write-Host ""
Write-Host "[ System ]" -ForegroundColor Cyan
Test-Skill "system info (dispatcher)" { & "$root\powerskills.ps1" system info }
Test-Skill "system info (standalone)" { & "$root\skills\system\system.ps1" info }
Test-Skill "system exec" { & "$root\powerskills.ps1" system exec --command "echo test123" }
Test-Skill "system processes" { & "$root\powerskills.ps1" system processes --limit 3 }

# Desktop
Write-Host ""
Write-Host "[ Desktop ]" -ForegroundColor Cyan
Test-Skill "desktop windows (dispatcher)" { & "$root\powerskills.ps1" desktop windows }
Test-Skill "desktop windows (standalone)" { & "$root\skills\desktop\desktop.ps1" windows }

# Outlook
if (-not $SkipOutlook) {
    Write-Host ""
    Write-Host "[ Outlook ]" -ForegroundColor Cyan
    Test-Skill "outlook folders" { & "$root\powerskills.ps1" outlook folders }
    Test-Skill "outlook inbox" { & "$root\powerskills.ps1" outlook inbox --limit 2 }
}
else {
    Write-Host ""
    Write-Host "[ Outlook ] SKIPPED" -ForegroundColor Yellow
}

# Browser
if (-not $SkipBrowser) {
    Write-Host ""
    Write-Host "[ Browser ]" -ForegroundColor Cyan
    Test-Skill "browser tabs" { & "$root\powerskills.ps1" browser tabs }
}
else {
    Write-Host ""
    Write-Host "[ Browser ] SKIPPED" -ForegroundColor Yellow
}

# Summary
Write-Host ""
Write-Host "======================"
$total = $pass + $fail
Write-Host "Results: " -NoNewline
Write-Host "$pass passed" -ForegroundColor Green -NoNewline
Write-Host ", " -NoNewline
if ($fail -gt 0) {
    Write-Host "$fail failed" -ForegroundColor Red
}
else {
    Write-Host "0 failed"
}

if ($fail -gt 0) { exit 1 } else { exit 0 }
