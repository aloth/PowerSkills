<#
.SYNOPSIS
    Work IQ skill - Microsoft 365 automation via the Work IQ CLI.

.DESCRIPTION
    Thin structured wrapper around the official Work IQ CLI
    (https://github.com/microsoft/work-iq). Covers install/check helpers so
    the skill also serves as a first-time-setup path, plus ergonomic
    subcommands for ask/agents/fetch/call-function/do-action/etc.

.EXAMPLE
    .\workiq.ps1 install
    .\workiq.ps1 accept-eula
    .\workiq.ps1 ask --question "What's on my calendar tomorrow?"
    .\workiq.ps1 fetch --url "https://graph.microsoft.com/v1.0/me/messages"
#>
param(
    [Parameter(Position=0)] [string]$Action,
    [Parameter(ValueFromRemainingArguments)] [string[]]$Rest,
    [hashtable]$Args_,
    [hashtable]$Config
)

# --- Standalone bootstrap -------------------------------------------------
$_standalone = (-not $Args_ -or $Args_.Count -eq 0) -and -not (Get-Variable -Name SkillsRoot -Scope Script -ErrorAction SilentlyContinue)
$script:SkillDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($_standalone) {
    . (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))) "lib\bootstrap.ps1")
    if ($Rest) { $Args_ = Parse-CliArgs -Arguments $Rest } else { $Args_ = @{} }
    if (-not $Config) { $Config = @{} }
}

$script:DefaultTimeout = if ($Config -and $Config.default_timeout) { [int]$Config.default_timeout } else { 120 }

# --- Locate the Work IQ executable ---------------------------------------
# Prefer the real .exe (Node spawn on Windows chokes on .cmd shims with
# EINVAL). Fall back to whatever "workiq" resolves to on PATH.
function Resolve-WorkIqExe {
    $candidates = @(
        (Join-Path $env:APPDATA "npm\node_modules\@microsoft\workiq\bin\win-x64\workiq.exe"),
        (Join-Path $env:ProgramFiles "nodejs\node_modules\@microsoft\workiq\bin\win-x64\workiq.exe")
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    $cmd = Get-Command workiq -ErrorAction SilentlyContinue
    if ($cmd) {
        # If PATH gave us a .cmd/.bat shim, try to swap to the .exe next to
        # it. Otherwise keep whatever PATH offered.
        $exe = $cmd.Source -replace '\.(cmd|bat)$','.exe'
        if (Test-Path $exe) { return $exe }
        return $cmd.Source
    }
    return $null
}

function Assert-WorkIq {
    $exe = Resolve-WorkIqExe
    if (-not $exe) {
        throw "workiq CLI not found. Run: .\powerskills.ps1 workiq install"
    }
    return $exe
}

# --- Run workiq and capture stdout/stderr/exit ---------------------------
# Uses PowerShell's call operator with splatted args (@args), which is the
# only reliable way on Windows PowerShell 5.1 to pass args with spaces
# (e.g. `workiq ask -q "how many mails do I have"`) without them getting
# split by Start-Process' ArgumentList or the classic .exe launcher.
# stdout/stderr are separated via a background job that redirects stderr
# with 2>&1 wrapper streams.
function Invoke-WorkIq {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [int]$TimeoutSec = 0
    )
    $exe = Assert-WorkIq
    $timeout = if ($TimeoutSec -gt 0) { $TimeoutSec } else { $script:DefaultTimeout }

    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    $job = $null
    try {
        # Run in a job so we can enforce a timeout. Splat @using:Arguments
        # so PowerShell handles arg quoting for us.
        $job = Start-Job -ScriptBlock {
            param($Exe, $Args_, $OutFile, $ErrFile)
            & $Exe @Args_ 1>$OutFile 2>$ErrFile
            return $LASTEXITCODE
        } -ArgumentList $exe, $Arguments, $stdoutFile, $stderrFile

        if (-not (Wait-Job $job -Timeout $timeout)) {
            Stop-Job $job -ErrorAction SilentlyContinue
            throw "workiq timed out after $timeout seconds"
        }
        $exit = Receive-Job $job
        if ($null -eq $exit) { $exit = 0 }

        $stdout = if (Test-Path $stdoutFile) { Get-Content $stdoutFile -Raw -Encoding UTF8 } else { "" }
        $stderr = if (Test-Path $stderrFile) { Get-Content $stderrFile -Raw -Encoding UTF8 } else { "" }
        # Strip ANSI CSI/OSC sequences that Work IQ likes to emit.
        $ansi = [regex]"\x1B(?:\][^\x07]*\x07|[@-_][0-?]*[ -/]*[@-~])"
        if ($stdout) { $stdout = $ansi.Replace($stdout, "") }
        if ($stderr) { $stderr = $ansi.Replace($stderr, "") }
        return @{
            stdout    = $stdout
            stderr    = $stderr
            exit_code = [int]$exit
            command   = @($exe) + $Arguments
        }
    } finally {
        if ($job) { Remove-Job $job -Force -ErrorAction SilentlyContinue }
        Remove-Item $stdoutFile -ErrorAction SilentlyContinue
        Remove-Item $stderrFile -ErrorAction SilentlyContinue
    }
}

# Fail with the standard skill envelope when the underlying CLI errored.
function Assert-WorkIqOk {
    param($Result, [string]$Context)
    if ($Result.exit_code -ne 0) {
        $msg = $Result.stderr
        if (-not $msg) { $msg = $Result.stdout }
        if (-not $msg) { $msg = "workiq exited with code $($Result.exit_code)" }
        throw "$Context failed: $msg"
    }
}

# --- Actions -------------------------------------------------------------

function Action-Help {
    $skillMd = Join-Path $script:SkillDir "SKILL.md"
    $help = if (Test-Path $skillMd) { [string](Get-Content $skillMd -Raw) } else { "" }
    return @{
        skill   = "workiq"
        help    = $help
        actions = @(
            "check", "install", "accept-eula", "version",
            "ask", "agents", "fetch", "search-paths", "get-schema",
            "call-function", "do-action", "create", "update", "delete",
            "debug", "raw", "help", "list-actions"
        )
    }
}

function Action-Check {
    $exe = Resolve-WorkIqExe
    $installed = [bool]$exe
    $version = $null
    $eula = $null
    if ($installed) {
        $v = Invoke-WorkIq -Arguments @("version") -TimeoutSec 30
        if ($v.exit_code -eq 0) { $version = $v.stdout.Trim() }
        # Detect EULA: workiq refuses to run 'ask' before EULA is accepted;
        # we probe via `config` which is EULA-independent, and treat an
        # explicit "EULA" mention in stderr as the signal when calling ask.
        $probe = Invoke-WorkIq -Arguments @("agents", "list") -TimeoutSec 30
        if ($probe.exit_code -eq 0) {
            $eula = $true
        } elseif ($probe.stderr -match "EULA|Lizenz|license") {
            $eula = $false
        } else {
            $eula = $null  # unknown
        }
    }
    return @{
        installed      = $installed
        path           = $exe
        version        = $version
        eula_accepted  = $eula
        hint           = if (-not $installed) { "Run: powerskills workiq install" }
                         elseif ($eula -eq $false) { "Run: powerskills workiq accept-eula" }
                         else { $null }
    }
}

function Action-Install {
    $scope = if ($Args_.scope) { $Args_.scope } else { "user" }
    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npm) {
        throw "npm not found on PATH. Install Node.js from https://nodejs.org/ first."
    }
    $npmArgs = @("install", "-g", "@microsoft/workiq")
    if ($scope -eq "user") { $npmArgs += "--scope=user" }
    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    try {
        # npm ships as npm.cmd on Windows; use cmd.exe to invoke it safely.
        $proc = Start-Process -FilePath "cmd.exe" `
            -ArgumentList (@("/c", "npm") + $npmArgs) `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
        $stdout = Get-Content $stdoutFile -Raw -Encoding UTF8
        $stderr = Get-Content $stderrFile -Raw -Encoding UTF8
        if ($proc.ExitCode -ne 0) {
            $msg = if ($stderr) { $stderr } else { $stdout }
            throw "npm install failed (exit $($proc.ExitCode)): $msg"
        }
        $exe = Resolve-WorkIqExe
        return @{
            installed  = [bool]$exe
            path       = $exe
            scope      = $scope
            npm_stdout = $stdout
            next_step  = "Run: powerskills workiq accept-eula"
        }
    } finally {
        Remove-Item $stdoutFile -ErrorAction SilentlyContinue
        Remove-Item $stderrFile -ErrorAction SilentlyContinue
    }
}

function Action-AcceptEula {
    $r = Invoke-WorkIq -Arguments @("accept-eula") -TimeoutSec 30
    Assert-WorkIqOk $r "accept-eula"
    return @{
        accepted  = $true
        output    = $r.stdout.Trim()
    }
}

function Action-Version {
    $r = Invoke-WorkIq -Arguments @("version") -TimeoutSec 30
    Assert-WorkIqOk $r "version"
    return @{ version = $r.stdout.Trim() }
}

function Action-Ask {
    $q = $Args_.question
    if (-not $q) { throw "Required: --question" }
    $timeout = if ($Args_.timeout) { [int]$Args_.timeout } else { $script:DefaultTimeout }
    $argv = @("ask", "-q", $q)
    if ($Args_.agent) { $argv += @("-a", [string]$Args_.agent) }
    $r = Invoke-WorkIq -Arguments $argv -TimeoutSec $timeout
    Assert-WorkIqOk $r "ask"
    return $r
}

function Action-Agents {
    if ($Args_.'get-card') {
        $r = Invoke-WorkIq -Arguments @("agents", "get-card", [string]$Args_.'get-card') -TimeoutSec 30
    } else {
        $r = Invoke-WorkIq -Arguments @("agents", "list") -TimeoutSec 30
    }
    Assert-WorkIqOk $r "agents"
    return $r
}

function Action-Fetch {
    $url = $Args_.url
    if (-not $url) { throw "Required: --url" }
    $r = Invoke-WorkIq -Arguments @("fetch", "--urls", $url) -TimeoutSec $script:DefaultTimeout
    Assert-WorkIqOk $r "fetch"
    return $r
}

function Action-SearchPaths {
    $filter = $Args_.filter
    if (-not $filter) { throw "Required: --filter" }
    $argv = @("search-paths", "--filter", $filter)
    if ($Args_.backend) { $argv += @("--backend", [string]$Args_.backend) }
    $r = Invoke-WorkIq -Arguments $argv -TimeoutSec 30
    Assert-WorkIqOk $r "search-paths"
    return $r
}

function Action-GetSchema {
    $path = $Args_.path
    if (-not $path) { throw "Required: --path" }
    $argv = @("get-schema", "--path", $path)
    if ($Args_.method) { $argv += @("--method", [string]$Args_.method) }
    if ($Args_.'api-version') { $argv += @("--api-version", [string]$Args_.'api-version') }
    $r = Invoke-WorkIq -Arguments $argv -TimeoutSec 30
    Assert-WorkIqOk $r "get-schema"
    return $r
}

function Action-CallFunction {
    # Note: workiq call-function takes ONLY --url (which may include a
    # query string). It does not expose a separate --params flag; build
    # your query string into --url yourself.
    $url = $Args_.url
    if (-not $url) { throw "Required: --url" }
    $r = Invoke-WorkIq -Arguments @("call-function", "--url", $url) -TimeoutSec $script:DefaultTimeout
    Assert-WorkIqOk $r "call-function"
    return $r
}

function Action-DoAction {
    $url = $Args_.url
    $body = $Args_.body
    if (-not $url) { throw "Required: --url" }
    $argv = @("do-action", "--url", $url)
    if ($body) { $argv += @("--body", [string]$body) }
    $r = Invoke-WorkIq -Arguments $argv -TimeoutSec $script:DefaultTimeout
    Assert-WorkIqOk $r "do-action"
    return $r
}

function Action-Create {
    $url = $Args_.url
    $body = $Args_.body
    if (-not $url) { throw "Required: --url" }
    if (-not $body) { throw "Required: --body (JSON)" }
    $r = Invoke-WorkIq -Arguments @("create", "--url", $url, "--body", [string]$body) -TimeoutSec $script:DefaultTimeout
    Assert-WorkIqOk $r "create"
    return $r
}

function Action-Update {
    $url = $Args_.url
    $body = $Args_.body
    if (-not $url) { throw "Required: --url" }
    if (-not $body) { throw "Required: --body (JSON)" }
    $r = Invoke-WorkIq -Arguments @("update", "--url", $url, "--body", [string]$body) -TimeoutSec $script:DefaultTimeout
    Assert-WorkIqOk $r "update"
    return $r
}

function Action-Delete {
    $url = $Args_.url
    if (-not $url) { throw "Required: --url" }
    $r = Invoke-WorkIq -Arguments @("delete", "--url", $url) -TimeoutSec $script:DefaultTimeout
    Assert-WorkIqOk $r "delete"
    return $r
}

function Action-Debug {
    $conv = $Args_.conversation
    if (-not $conv) { throw "Required: --conversation" }
    # `workiq debug` takes conversationId as a POSITIONAL argument.
    $r = Invoke-WorkIq -Arguments @("debug", $conv) -TimeoutSec 30
    Assert-WorkIqOk $r "debug"
    return $r
}

function Action-Raw {
    $raw = $Args_.args
    if (-not $raw) { throw "Required: --args ""arg1 arg2 ...""" }
    # Split on whitespace, but respect double-quoted groups.
    $tokens = [regex]::Matches($raw, '"([^"]*)"|(\S+)') | ForEach-Object {
        if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value }
    }
    $r = Invoke-WorkIq -Arguments $tokens -TimeoutSec $script:DefaultTimeout
    # Do NOT Assert-WorkIqOk here - raw is an escape hatch; caller inspects
    # exit_code themselves.
    return $r
}

# --- Dispatcher ----------------------------------------------------------

function Invoke-WorkIqAction {
    switch ($Action) {
        { $_ -in @("", "help", "list-actions") } { return (Action-Help) }
        "check"          { return (Action-Check) }
        "install"        { return (Action-Install) }
        "accept-eula"    { return (Action-AcceptEula) }
        "version"        { return (Action-Version) }
        "ask"            { return (Action-Ask) }
        "agents"         { return (Action-Agents) }
        "fetch"          { return (Action-Fetch) }
        "search-paths"   { return (Action-SearchPaths) }
        "get-schema"     { return (Action-GetSchema) }
        "call-function"  { return (Action-CallFunction) }
        "do-action"      { return (Action-DoAction) }
        "create"         { return (Action-Create) }
        "update"         { return (Action-Update) }
        "delete"         { return (Action-Delete) }
        "debug"          { return (Action-Debug) }
        "raw"            { return (Action-Raw) }
        default {
            throw "Unknown action: $Action. Run: powerskills workiq help"
        }
    }
}

# --- Execute -------------------------------------------------------------
if ($_standalone) {
    try { $result = Invoke-WorkIqAction; Write-SkillResult -Data $result }
    catch { Write-SkillError -Message $_.Exception.Message }
} else {
    return (Invoke-WorkIqAction)
}
