<#
.SYNOPSIS
    Outlook skill — COM automation for email and calendar.
.EXAMPLE
    .\outlook.ps1 inbox --limit 10
    .\outlook.ps1 read --index 0 --folder sent
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

$maxBody = if ($Config.outlook_body_max_chars) { [int]$Config.outlook_body_max_chars } else { 5000 }

# ─── Connect to Outlook ───
function Get-OutlookNamespace {
    try {
        $ol = New-Object -ComObject Outlook.Application
        return $ol.GetNamespace("MAPI")
    } catch {
        throw "Cannot connect to Outlook. Is it running? (Non-admin PowerShell required)"
    }
}

function Get-FolderId {
    param([string]$Name)
    switch ($Name) {
        "inbox"   { 6 }
        "sent"    { 5 }
        "drafts"  { 16 }
        "calendar" { 9 }
        default   { 6 }
    }
}

function Format-MailItem {
    param($Item, [int]$Index)
    return @{
        index          = $Index
        subject        = $Item.Subject
        sender         = $Item.SenderName
        sender_email   = $(try { $Item.SenderEmailAddress } catch { "" })
        received       = $Item.ReceivedTime.ToString("yyyy-MM-dd HH:mm")
        unread         = $Item.UnRead
        importance     = $Item.Importance
        has_attachments = $Item.Attachments.Count -gt 0
    }
}

function Format-MailItemFull {
    param($Item)
    $body = $Item.Body
    if ($body.Length -gt $maxBody) { $body = $body.Substring(0, $maxBody) + "`n... [truncated]" }
    $attachments = @()
    for ($i = 1; $i -le $Item.Attachments.Count; $i++) {
        $attachments += $Item.Attachments.Item($i).FileName
    }
    return @{
        subject      = $Item.Subject
        sender       = $Item.SenderName
        sender_email = $(try { $Item.SenderEmailAddress } catch { "" })
        to           = $(try { $Item.To } catch { "" })
        cc           = $(try { $Item.CC } catch { "" })
        received     = $Item.ReceivedTime.ToString("yyyy-MM-dd HH:mm:ss")
        body         = $body
        unread       = $Item.UnRead
        importance   = $Item.Importance
        attachments  = $attachments
    }
}

# ─── Main logic ───
function Invoke-OutlookAction {
    $ns = Get-OutlookNamespace

    switch ($Action) {
        "inbox" {
            $limit = if ($Args_.limit) { [int]$Args_.limit } else { 15 }
            $folder = $ns.GetDefaultFolder(6)
            $items = $folder.Items
            $items.Sort("[ReceivedTime]", $true)
            $result = @()
            $count = 0
            foreach ($item in $items) {
                if ($count -ge $limit) { break }
                $result += Format-MailItem -Item $item -Index $count
                $count++
            }
            return $result
        }
        "unread" {
            $limit = if ($Args_.limit) { [int]$Args_.limit } else { 20 }
            $folder = $ns.GetDefaultFolder(6)
            $items = $folder.Items.Restrict("[UnRead] = True")
            $items.Sort("[ReceivedTime]", $true)
            $result = @()
            $count = 0
            foreach ($item in $items) {
                if ($count -ge $limit) { break }
                $result += Format-MailItem -Item $item -Index $count
                $count++
            }
            return $result
        }
        "sent" {
            $limit = if ($Args_.limit) { [int]$Args_.limit } else { 15 }
            $folder = $ns.GetDefaultFolder(5)
            $items = $folder.Items
            $items.Sort("[ReceivedTime]", $true)
            $result = @()
            $count = 0
            foreach ($item in $items) {
                if ($count -ge $limit) { break }
                $result += Format-MailItem -Item $item -Index $count
                $count++
            }
            return $result
        }
        "read" {
            $idx = [int]$Args_.index
            $folderName = if ($Args_.folder) { $Args_.folder } else { "inbox" }
            $folderId = Get-FolderId $folderName
            $folder = $ns.GetDefaultFolder($folderId)
            $items = $folder.Items
            $items.Sort("[ReceivedTime]", $true)
            $count = 0
            foreach ($item in $items) {
                if ($count -eq $idx) {
                    return Format-MailItemFull -Item $item
                }
                $count++
            }
            throw "Email at index $idx not found in $folderName"
        }
        "search" {
            $query = $Args_.query
            if (-not $query) { throw "Required: --query" }
            $limit = if ($Args_.limit) { [int]$Args_.limit } else { 10 }
            $folderName = if ($Args_.folder) { $Args_.folder } else { "inbox" }
            $folderId = Get-FolderId $folderName
            $folder = $ns.GetDefaultFolder($folderId)
            $filter = "@SQL=""urn:schemas:httpmail:subject"" LIKE '%$query%' OR ""urn:schemas:httpmail:textdescription"" LIKE '%$query%'"
            $items = $folder.Items.Restrict($filter)
            $items.Sort("[ReceivedTime]", $true)
            $result = @()
            $count = 0
            foreach ($item in $items) {
                if ($count -ge $limit) { break }
                $result += Format-MailItem -Item $item -Index $count
                $count++
            }
            return $result
        }
        "calendar" {
            $days = if ($Args_.days) { [int]$Args_.days } else { 7 }
            $calendar = $ns.GetDefaultFolder(9)
            $now = Get-Date
            $end = $now.AddDays($days)
            $filter = "[Start] >= '$($now.ToString("g"))' AND [Start] <= '$($end.ToString("g"))'"
            $items = $calendar.Items
            $items.Sort("[Start]")
            $items.IncludeRecurrences = $true
            $filtered = $items.Restrict($filter)
            $result = @()
            $count = 0
            foreach ($item in $filtered) {
                if ($count -ge 30) { break }
                $result += @{
                    subject      = $item.Subject
                    start        = $item.Start.ToString("yyyy-MM-dd HH:mm")
                    end          = $item.End.ToString("yyyy-MM-dd HH:mm")
                    location     = $item.Location
                    organizer    = $(try { $item.Organizer } catch { "" })
                    is_recurring = $item.IsRecurring
                    all_day      = $item.AllDayEvent
                    busy_status  = $Item.BusyStatus
                }
                $count++
            }
            return $result
        }
        "send" {
            $to = $Args_.to
            $subject = $Args_.subject
            $body = $Args_.body
            if (-not $to -or -not $subject) { throw "Required: --to, --subject" }

            $ol = New-Object -ComObject Outlook.Application
            $mail = $ol.CreateItem(0)
            $mail.To = $to
            $mail.Subject = $subject
            $mail.Body = $body
            if ($Args_.cc) { $mail.CC = $Args_.cc }
            if ($Args_.importance) { $mail.Importance = [int]$Args_.importance }

            if ($Args_.draft) {
                $mail.Save()
                return @{ action = "draft_saved"; to = $to; subject = $subject }
            } else {
                $mail.Send()
                return @{ action = "sent"; to = $to; subject = $subject }
            }
        }
        "reply" {
            $idx = [int]$Args_.index
            $body = $Args_.body
            if (-not $body) { throw "Required: --body" }

            $folder = $ns.GetDefaultFolder(6)
            $items = $folder.Items
            $items.Sort("[ReceivedTime]", $true)
            $count = 0
            foreach ($item in $items) {
                if ($count -eq $idx) {
                    $reply = if ($Args_.'reply-all') { $item.ReplyAll() } else { $item.Reply() }
                    $reply.Body = $body + "`n`n" + $reply.Body
                    if ($Args_.draft) {
                        $reply.Save()
                        return @{ action = "reply_draft_saved"; subject = $item.Subject }
                    } else {
                        $reply.Send()
                        return @{ action = "reply_sent"; subject = $item.Subject }
                    }
                }
                $count++
            }
            throw "Email at index $idx not found"
        }
        "folders" {
            $root = $ns.GetDefaultFolder(6).Parent
            $result = @()
            foreach ($folder in $root.Folders) {
                $result += @{
                    name   = $folder.Name
                    count  = $folder.Items.Count
                    unread = $folder.UnReadItemCount
                }
            }
            return $result
        }
        default {
            throw "Unknown action: $Action. Use: inbox, unread, sent, read, search, calendar, send, reply, folders"
        }
    }
}

# ─── Execute ───
if ($_standalone) {
    try { $result = Invoke-OutlookAction; Write-SkillResult -Data $result }
    catch { Write-SkillError -Message $_.Exception.Message }
} else {
    return (Invoke-OutlookAction)
}
