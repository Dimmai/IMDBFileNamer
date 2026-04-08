param (
    [string]$TorrentDirectory  # This will capture "%D" from qBittorrent
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Add 4 second delay
Write-Host "Waiting 4 seconds before removing torrent..."
Start-Sleep -Seconds 4

# Run RemoveTorrent.ps1 (no parameter needed)
& "$scriptDir\QbitRemoveTorrent.ps1"

# Run GetFileMetaData1.ps1 and forward the "%D" parameter
& "$scriptDir\IMDBRenameAndCopy.ps1" -TorrentDirectory $TorrentDirectory