<#
.SYNOPSIS
    PowerSkills test suite — verifies all skills work correctly.
.DESCRIPTION
    Run from the PowerSkills root directory:
        .\tests\test-all.ps1
    
    Tests both dispatcher and standalone modes.
    Outlook and Browser tests require those apps to be running.
.EXAMPLE
    .\tests\test-all.ps1                    # Run all tests
    .\tests\test-all.ps1 -Skip outlook      # Skip Outlook tests
    .\tests\test-all.ps1 -Only system       # Only run system tests
#>
param(
    [string[]]$Skip = @(),
    [string[]]$Only = @()
)

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$pass = 0; $fail = 0; $skip_count = 0
$results = @()

function Test {
    param([string]$Name, [string]$Skill, [scriptblock]$Block)
    
    if ($Only.Count -gt 0 -and $Skill -notin $Only) { return }
    if ($Skill -in $Skip) {
        $script:skip_count++
        Write-Host "  SKIP  " -ForegroundColor Yellow -NoNewline
        Write-Host $Name
        return
    }

    try {
        $output = & $Block
        $json = $output | ConvertFrom-Json
        if ($json.status -eq "success" -and $json.exit_code -eq 0) {
            $script:pass++
            Write-Host "  PASS  " -ForegroundColor Green -NoNewline
            Write-Host $Name
            $script:results += @{ name = $Name; status = "pass" }
        } else {
            $script:fail++
            Write-Host "  FAIL  " -ForegroundColor Red -NoNewline
            Write-Host "$Name — status: $($json.status), error: $($json.data.error)"
            $script:results += @{ name = $Name; status = "fail"; error = $json.data.error }
        }
    } catch {
        $script:fail++
        Write-Host "  FAIL  " -ForegroundColor Red -NoNewline
        Write-Host "$Name — $_"
        $script:results += @{ name = $Name; status = "fail"; error = $_.ToString() }
    }
}

Write-Host ""
Write-Host "PowerSkills Test Suite" -ForegroundColor Cyan
Write-Host ("=" * 50)
Write-Host "Root: $root"
Write-Host ""

# ─── Core: Dispatcher ───
Write-Host "[ Core ]" -ForegroundColor Cyan

Test "Dispatcher: list skills" "core" {
    & "$root\powerskills.ps1" list
}

Test "Dispatcher: help for system" "core" {
    & "$root\powerskills.ps1" system help
}

# ─── System ───
Write-Host ""
Write-Host "[ System ]" -ForegroundColor Cyan

Test "system info (dispatcher)" "system" {
    & "$root\powerskills.ps1" system info
}

Test "system info (standalone)" "system" {
    & "$root\skills\system\system.ps1" info
}

Test "system exec: whoami" "system" {
    & "$root\powerskills.ps1" system exec --command "whoami"
}

Test "system exec: echo test" "system" {
    & "$root\skills\system\system.ps1" exec --command "echo hello-powerskills"
}

Test "system processes" "system" {
    & "$root\powerskills.ps1" system processes --limit 3
}

Test "system env: COMPUTERNAME" "system" {
    & "$root\powerskills.ps1" system env --name COMPUTERNAME
}

# ─── Desktop ───
Write-Host ""
Write-Host "[ Desktop ]" -ForegroundColor Cyan

Test "desktop windows list (dispatcher)" "desktop" {
    & "$root\powerskills.ps1" desktop windows
}

Test "desktop windows list (standalone)" "desktop" {
    & "$root\skills\desktop\desktop.ps1" windows
}

$screenshotPath = Join-Path $root "tests\test-screenshot.png"
Test "desktop screenshot" "desktop" {
    & "$root\powerskills.ps1" desktop screenshot --out-file $screenshotPath
}

# Clean up screenshot
if (Test-Path $screenshotPath) { Remove-Item $screenshotPath -Force }

# ─── Outlook ───
Write-Host ""
Write-Host "[ Outlook ]" -ForegroundColor Cyan

Test "outlook folders (dispatcher)" "outlook" {
    & "$root\powerskills.ps1" outlook folders
}

Test "outlook inbox --limit 3" "outlook" {
    & "$root\powerskills.ps1" outlook inbox --limit 3
}

Test "outlook inbox (standalone)" "outlook" {
    & "$root\skills\outlook\outlook.ps1" inbox --limit 2
}

Test "outlook unread --limit 3" "outlook" {
    & "$root\powerskills.ps1" outlook unread --limit 3
}

Test "outlook sent --limit 3" "outlook" {
    & "$root\powerskills.ps1" outlook sent --limit 3
}

Test "outlook read --index 0" "outlook" {
    & "$root\powerskills.ps1" outlook read --index 0 --folder inbox
}

Test "outlook calendar --days 3" "outlook" {
    & "$root\powerskills.ps1" outlook calendar --days 3
}

# ─── Browser ───
Write-Host ""
Write-Host "[ Browser ]" -ForegroundColor Cyan

Test "browser tabs (dispatcher)" "browser" {
    & "$root\powerskills.ps1" browser tabs
}

Test "browser tabs (standalone)" "browser" {
    & "$root\skills\browser\browser.ps1" tabs
}

# ─── Summary ───
Write-Host ""
Write-Host ("=" * 50)
$total = $pass + $fail + $skip_count
Write-Host "Results: " -NoNewline
Write-Host "$pass passed" -ForegroundColor Green -NoNewline
Write-Host ", " -NoNewline
if ($fail -gt 0) {
    Write-Host "$fail failed" -ForegroundColor Red -NoNewline
} else {
    Write-Host "0 failed" -NoNewline
}
if ($skip_count -gt 0) {
    Write-Host ", $skip_count skipped" -ForegroundColor Yellow -NoNewline
}
Write-Host " ($total total)"

# Output JSON summary too
$summary = @{
    status    = if ($fail -eq 0) { "success" } else { "partial" }
    passed    = $pass
    failed    = $fail
    skipped   = $skip_count
    total     = $total
    results   = $results
    timestamp = (Get-Date).ToString("o")
}
Write-Host ""
Write-Host "JSON:" -ForegroundColor DarkGray
$summary | ConvertTo-Json -Depth 5 -Compress

if ($fail -gt 0) { exit 1 } else { exit 0 }
