<#
.SYNOPSIS
    Browser skill — Edge CDP automation via WebSocket.
.EXAMPLE
    .\browser.ps1 tabs
    .\browser.ps1 navigate --url "https://example.com"
    .\browser.ps1 screenshot --out-file page.png
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

$Port = if ($Config.edge_debug_port) { [int]$Config.edge_debug_port } else { 9222 }
$cdpBase = "http://localhost:$Port"

# ─── CDP helpers ───
function Get-Targets {
    return Invoke-RestMethod -Uri "$cdpBase/json" -TimeoutSec 5
}

function Get-PageTarget {
    $targets = Get-Targets
    if ($Args_.ContainsKey('target-id') -and $Args_.'target-id') {
        $specific = $targets | Where-Object { $_.id -eq $Args_.'target-id' -and $_.type -eq "page" }
        if ($specific) { return $specific | Select-Object -First 1 }
    }
    return $targets | Where-Object { $_.type -eq "page" } | Select-Object -First 1
}

function Send-CDP {
    param([string]$Method, [hashtable]$Params = @{})

    $page = Get-PageTarget
    if (-not $page) { throw "No browser page found. Is Edge running with --remote-debugging-port=$Port?" }

    $wsUrl = "ws://localhost:$Port/devtools/page/$($page.id)"
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ct = [System.Threading.CancellationToken]::None

    try {
        $ws.ConnectAsync([Uri]$wsUrl, $ct).Wait()

        $id = Get-Random -Minimum 1 -Maximum 99999
        $msg = @{ id = $id; method = $Method; params = $Params } | ConvertTo-Json -Depth 10 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($msg)
        $segment = New-Object System.ArraySegment[byte] -ArgumentList @(,$bytes)
        $ws.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()

        $buffer = New-Object byte[] 4194304  # 4MB
        $result = ""
        do {
            $recv = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buffer)), $ct).Result
            $result += [System.Text.Encoding]::UTF8.GetString($buffer, 0, $recv.Count)
        } while (-not $recv.EndOfMessage)

        $response = $result | ConvertFrom-Json
        if ($response.error) { throw "CDP error: $($response.error.message)" }
        return $response.result
    } finally {
        if ($ws.State -eq 'Open') {
            try { $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "", $ct).Wait() } catch {}
        }
        $ws.Dispose()
    }
}

# ─── Main logic ───
function Invoke-BrowserAction {
    switch ($Action) {
        "tabs" {
            $targets = Get-Targets
            $pages = $targets | Where-Object { $_.type -eq "page" } | ForEach-Object {
                @{ id = $_.id; title = $_.title; url = $_.url }
            }
            return $pages
        }
        "navigate" {
            $url = $Args_.url
            if (-not $url) { throw "Required: --url" }
            $result = Send-CDP -Method "Page.navigate" -Params @{ url = $url }
            Start-Sleep -Seconds 2
            return @{ navigated = $url; frameId = $result.frameId }
        }
        "screenshot" {
            $result = Send-CDP -Method "Page.captureScreenshot" -Params @{ format = "png" }
            $outFile = $Args_.'out-file'
            if ($outFile) {
                [System.IO.File]::WriteAllBytes($outFile, [System.Convert]::FromBase64String($result.data))
                return @{ saved = $outFile }
            }
            return @{ base64_length = $result.data.Length }
        }
        "content" {
            $result = Send-CDP -Method "Runtime.evaluate" -Params @{ expression = "document.body.innerText"; returnByValue = $true }
            $text = $result.result.value
            if ($text.Length -gt 10000) { $text = $text.Substring(0, 10000) + "`n... [truncated]" }
            return @{ content = $text }
        }
        "html" {
            $result = Send-CDP -Method "Runtime.evaluate" -Params @{ expression = "document.documentElement.outerHTML"; returnByValue = $true }
            $html = $result.result.value
            if ($html.Length -gt 50000) { $html = $html.Substring(0, 50000) + "... [truncated]" }
            return @{ html = $html }
        }
        "evaluate" {
            $expr = $Args_.expression
            if (-not $expr) { throw "Required: --expression" }
            $result = Send-CDP -Method "Runtime.evaluate" -Params @{ expression = $expr; returnByValue = $true }
            return @{ value = $result.result.value; type = $result.result.type }
        }
        "click" {
            $selector = $Args_.selector
            if (-not $selector) { throw "Required: --selector" }
            $js = "document.querySelector('$selector')?.click(); document.querySelector('$selector') ? 'clicked' : 'not_found'"
            $result = Send-CDP -Method "Runtime.evaluate" -Params @{ expression = $js; returnByValue = $true }
            return @{ result = $result.result.value }
        }
        "type" {
            $selector = $Args_.selector
            $text = $Args_.text
            if (-not $selector -or -not $text) { throw "Required: --selector, --text" }
            $escaped = $text -replace "'","\\'"
            $js = "var el = document.querySelector('$selector'); if(el){el.focus();el.value='$escaped';el.dispatchEvent(new Event('input',{bubbles:true}));'typed'}else{'not_found'}"
            $result = Send-CDP -Method "Runtime.evaluate" -Params @{ expression = $js; returnByValue = $true }
            return @{ result = $result.result.value }
        }
        "new-tab" {
            $url = if ($Args_.url) { $Args_.url } else { "about:blank" }
            $null = Invoke-RestMethod -Uri "$cdpBase/json/new?$url" -TimeoutSec 5
            Start-Sleep -Seconds 1
            return @{ opened = $url }
        }
        "close-tab" {
            $targetId = $Args_.'target-id'
            if (-not $targetId) { throw "Required: --target-id" }
            try { $null = Invoke-RestMethod -Uri "$cdpBase/json/close/$targetId" -TimeoutSec 5 } catch {}
            return @{ closed = $targetId }
        }
        "scroll" {
            $target = $Args_.'scroll-target'
            if (-not $target) { $target = "bottom" }
            $js = switch ($target) {
                "top"    { "window.scrollTo(0,0);'scrolled_top'" }
                "bottom" { "window.scrollTo(0,document.body.scrollHeight);'scrolled_bottom'" }
                default  { "var el=document.querySelector('$target');if(el){el.scrollIntoView();'scrolled'}else{'not_found'}" }
            }
            $result = Send-CDP -Method "Runtime.evaluate" -Params @{ expression = $js; returnByValue = $true }
            return @{ result = $result.result.value }
        }
        "fill" {
            $fieldsJson = $Args_.'fields-json'
            if (-not $fieldsJson) { throw "Required: --fields-json" }
            $fields = $fieldsJson | ConvertFrom-Json
            $results = @()
            foreach ($field in $fields) {
                $sel = $field.selector
                $val = $field.value -replace "'","\\'"
                $js = "var el=document.querySelector('$sel');if(el){el.focus();el.value='$val';el.dispatchEvent(new Event('input',{bubbles:true}));'ok'}else{'not_found'}"
                $r = Send-CDP -Method "Runtime.evaluate" -Params @{ expression = $js; returnByValue = $true }
                $results += @{ selector = $sel; result = $r.result.value }
                if ($field.submit) {
                    $submitJs = "document.querySelector('$($field.submit)')?.click();'submitted'"
                    $null = Send-CDP -Method "Runtime.evaluate" -Params @{ expression = $submitJs; returnByValue = $true }
                    $results[-1].submitted = $true
                }
            }
            return $results
        }
        "wait" {
            $seconds = if ($Args_.seconds) { [int]$Args_.seconds } else { 3 }
            Start-Sleep -Seconds $seconds
            return @{ waited = $seconds }
        }
        default {
            throw "Unknown action: $Action. Use: tabs, navigate, screenshot, content, html, evaluate, click, type, new-tab, close-tab, scroll, fill, wait"
        }
    }
}

# ─── Execute ───
if ($_standalone) {
    try { $result = Invoke-BrowserAction; Write-SkillResult -Data $result }
    catch { Write-SkillError -Message $_.Exception.Message }
} else {
    return (Invoke-BrowserAction)
}
