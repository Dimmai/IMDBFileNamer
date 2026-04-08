<#
================================================================================
SYNOPSIS
--------------------------------------------------------------------------------
This PowerShell script connects to the qBittorrent WebUI API and automatically
cleans up completed torrents based on their completion time.

DESCRIPTION
--------------------------------------------------------------------------------
- Authenticates against the qBittorrent WebUI using provided credentials.
- Retrieves ONLY torrents that are marked as "completed".
- Compares each torrent’s completion timestamp against a configurable cutoff
  time (`$PruneAfterMins`).
- Torrents completed earlier than the cutoff time are removed from qBittorrent
  while optionally preserving the downloaded files.
- Torrents completed more recently than the cutoff time are kept.
- Provides clear, color-coded console output for:
    • Authentication status
    • Torrents removed
    • Torrents retained
    • Summary statistics

IMPORTANT NOTES
--------------------------------------------------------------------------------
- This script removes torrents from qBittorrent, NOT the downloaded files
  (unless `deleteFiles=true` is explicitly set).
- `$ServerURL` MUST end with a trailing slash (/).
- `$PruneAfterMins = 0` means ALL completed torrents are eligible for removal.
- Requires qBittorrent WebUI to be enabled and reachable.

USE CASE
--------------------------------------------------------------------------------
Ideal for automation scenarios such as:
- Post-processing pipelines
- Media library ingestion workflows
- Preventing completed torrents from lingering in qBittorrent
- Scheduled cleanup via Task Scheduler

SECURITY WARNING
--------------------------------------------------------------------------------
Credentials are stored in plain text. Restrict file access accordingly or
replace with a secure credential mechanism if needed.
================================================================================
#>

# CONFIG
# WebUI credentials
$Username = 'Nadeem Ahmad'
$Password = 'Nbronxnade69!'

# Torrents removed if completed this many minutes ago or older
$PruneAfterMins = 0  # Change to desired minutes (e.g., 60 = 1 hour)

# URL of your qBittorrent WebUI (include http/https and port)
$ServerURL = 'http://192.168.0.3:8080/'  # MUST end with a slash

# SCRIPT
Clear-Host
$CurrentTime = Get-Date
$CutoffTime = $CurrentTime.AddMinutes(-$PruneAfterMins)

# Create a web session for cookie persistence
$WebSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession

try {
    # Authenticate
    $AuthResponse = Invoke-RestMethod -Uri "$($ServerURL)api/v2/auth/login" -Method Post -Body @{
        username = $Username
        password = $Password
    } -WebSession $WebSession

    if ($AuthResponse -ne "Ok.") {
        Write-Host "❌ Authentication failed: $AuthResponse" -ForegroundColor Red
        exit 1
    }

    Write-Host "✅ Successfully authenticated with qBittorrent" -ForegroundColor Green

    # Get only completed torrents
    $Torrents = Invoke-RestMethod -Uri "$($ServerURL)api/v2/torrents/info?filter=completed" -WebSession $WebSession

    if (-not $Torrents) {
        Write-Host "ℹ️ No completed torrents found" -ForegroundColor Yellow
        exit 0
    }

    $RemovedCount = 0

    foreach ($Torrent in $Torrents) {
        if ($Torrent.completion_on -gt 0) {
            $CompletionTime = [datetimeoffset]::FromUnixTimeSeconds($Torrent.completion_on).DateTime.ToLocalTime()
            
            if ($CompletionTime -lt $CutoffTime) {
                Write-Host "🗑️ Removing torrent: $($Torrent.name)" -ForegroundColor Yellow
                Write-Host "   ⏰ Completed: $CompletionTime"
                Write-Host "   🔑 Hash: $($Torrent.hash)"

                # Delete torrent (but keep files) - change to true to delete files
                $DeleteResponse = Invoke-RestMethod -Method Post `
                    -Uri "$($ServerURL)api/v2/torrents/delete" `
                    -Body "hashes=$($Torrent.hash)&deleteFiles=false" `
                    -WebSession $WebSession

                $RemovedCount++
                Write-Host "✅ Removed successfully`n" -ForegroundColor Green
            }
            else {
                Write-Host "⏳ Keeping torrent (recently completed): $($Torrent.name)" -ForegroundColor Cyan
                Write-Host "   ⏰ Completed: $CompletionTime`n"
            }
        }
    }

    Write-Host "===================================="
    Write-Host "🏁 Script completed"
    Write-Host "📊 Total torrents checked: $($Torrents.count)"
    Write-Host "🗑️ Torrents removed: $RemovedCount"
    Write-Host "⏰ Cutoff time was: $CutoffTime"
    Write-Host "===================================="

    # Logout
    Invoke-RestMethod -Uri "$($ServerURL)api/v2/auth/logout" -Method Post -WebSession $WebSession | Out-Null

} catch {
    Write-Host "❌ Error occurred: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "⚠️ Stack Trace: $($_.ScriptStackTrace)" -ForegroundColor DarkYellow
}