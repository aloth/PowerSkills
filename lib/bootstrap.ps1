<#
.SYNOPSIS
    Shared bootstrap for standalone skill execution.
.DESCRIPTION
    Dot-source this at the top of a skill script to enable standalone mode.
    Provides Parse-CliArgs and Invoke-SkillAction helpers.
#>

function Parse-CliArgs {
    param([string[]]$Arguments)
    $parsed = @{}; $i = 0
    while ($i -lt $Arguments.Count) {
        if ($Arguments[$i] -match '^--(.+)$') {
            $key = $Matches[1]
            if (($i+1) -lt $Arguments.Count -and $Arguments[$i+1] -notmatch '^--') {
                $parsed[$key] = $Arguments[$i+1]; $i += 2
            } else { $parsed[$key] = $true; $i++ }
        } else { $i++ }
    }
    return $parsed
}

function Write-SkillResult {
    param($Data, [int]$ExitCode = 0)
    $envelope = @{
        status    = if ($ExitCode -eq 0) { "success" } else { "error" }
        exit_code = $ExitCode
        data      = $Data
        timestamp = (Get-Date).ToString("o")
    }
    $envelope | ConvertTo-Json -Depth 10 -Compress
    exit $ExitCode
}

function Write-SkillError {
    param([string]$Message)
    Write-SkillResult -Data @{ error = $Message } -ExitCode 1
}
