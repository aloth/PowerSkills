<#
.SYNOPSIS
    System skill — shell commands, process info, environment.
.EXAMPLE
    .\system.ps1 info
    .\system.ps1 exec --command "whoami"
    .\system.ps1 processes --limit 10
#>
param(
    [Parameter(Position=0)] [string]$Action,
    [Parameter(ValueFromRemainingArguments)] [string[]]$Rest,
    [hashtable]$Args_,
    [hashtable]$Config
)

# ─── Standalone bootstrap ───
$_standalone = (-not $Args_ -or $Args_.Count -eq 0) -and -not (Get-Variable -Name SkillsRoot -Scope Script -ErrorAction SilentlyContinue)
if ($_standalone) {
    . (Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) "lib\bootstrap.ps1")
    if ($Rest) { $Args_ = Parse-CliArgs -Arguments $Rest } else { $Args_ = @{} }
    if (-not $Config) { $Config = @{} }
}

$defaultTimeout = if ($Config.default_timeout) { [int]$Config.default_timeout } else { 30 }

# ─── Main logic ───
function Invoke-SystemAction {
    switch ($Action) {
        "exec" {
            $command = $Args_.command
            if (-not $command) { throw "Required: --command" }
            $timeout = if ($Args_.timeout) { [int]$Args_.timeout } else { $defaultTimeout }

            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "powershell.exe"
            $psi.Arguments = "-NoProfile -NonInteractive -Command `"$($command -replace '"','\"')`""
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError  = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true

            $proc = [System.Diagnostics.Process]::Start($psi)
            $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
            $stderrTask = $proc.StandardError.ReadToEndAsync()

            if (-not $proc.WaitForExit($timeout * 1000)) {
                $proc.Kill()
                return @{ stdout = ""; stderr = "TIMEOUT after ${timeout}s"; exit_code = 124 }
            }
            return @{ stdout = $stdoutTask.Result; stderr = $stderrTask.Result; exit_code = $proc.ExitCode }
        }
        "info" {
            return @{
                hostname = $env:COMPUTERNAME
                user     = $env:USERNAME
                domain   = $env:USERDOMAIN
                os       = (Get-CimInstance Win32_OperatingSystem).Caption
                arch     = $env:PROCESSOR_ARCHITECTURE
                ps_version = $PSVersionTable.PSVersion.ToString()
                uptime_hours = [math]::Round((Get-CimInstance Win32_OperatingSystem).LastBootUpTime.Subtract((Get-Date)).TotalHours * -1, 1)
            }
        }
        "processes" {
            $limit = if ($Args_.limit) { [int]$Args_.limit } else { 20 }
            $procs = Get-Process | Sort-Object CPU -Descending | Select-Object -First $limit | ForEach-Object {
                @{
                    name = $_.ProcessName
                    pid  = $_.Id
                    cpu  = [math]::Round($_.CPU, 2)
                    mem_mb = [math]::Round($_.WorkingSet64 / 1MB, 1)
                }
            }
            return $procs
        }
        "env" {
            $name = $Args_.name
            if (-not $name) { throw "Required: --name" }
            $val = [Environment]::GetEnvironmentVariable($name)
            return @{ name = $name; value = $val }
        }
        default {
            throw "Unknown action: $Action. Use: exec, info, processes, env"
        }
    }
}

# ─── Execute ───
if ($_standalone) {
    try { $result = Invoke-SystemAction; Write-SkillResult -Data $result }
    catch { Write-SkillError -Message $_.Exception.Message }
} else {
    return (Invoke-SystemAction)
}
