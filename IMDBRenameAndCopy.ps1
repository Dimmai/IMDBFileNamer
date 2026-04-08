<#
.SYNOPSIS
Media processor that cleans, renames, and organizes downloaded video files into a structured library.

.DESCRIPTION
This script processes completed downloads from qBittorrent by:

1. CLEANING FILENAMES - Removes junk like release groups, codecs (x264/HEVC), 
   resolutions (1080p/4K), audio tags (DTS/AC3), and language markers using a 
   configurable ShitList that learns over time.

2. DETECTING CONTENT TYPE - Identifies whether a file is:
   - Movie (standard film)
   - TV Series (contains S02E03, 2x03, or Season/Episode patterns)
   - Hindi/Bollywood (based on keywords like hindi, desi, bollywood)

3. EXTRACTING METADATA - Pulls title and year from filenames, and for TV shows,
   parses season and episode numbers.

4. VERIFYING (OPTIONAL) - Checks OMDB API to confirm movies exist before processing.

5. ORGANIZING - Copies files to appropriate library folders:
   - Movies:      F:\Movies\<Year>\Movie Title (Year).ext
   - TV Series:   F:\Serier\<Series Name>\Season XX\Series Name SXXEXX.ext
   - Hindi:       F:\Hindi\<Year>\Movie Title (Year).ext

6. VALIDATING - Compares source and destination file sizes to ensure copy integrity.

7. CLEANING UP - Deletes successfully copied source files and moves empty or junk 
   folders to a ToBeDeleted directory.

Safety features include mutex locking (prevents multiple instances), SafeRun debug mode 
(simulates all operations), drive restrictions (blocks F: drive), and interactive 
conflict resolution for existing files.

.PARAMETER folderPath
Root folder containing completed downloads to process. Default: G:\Download\Download\Complete

.PARAMETER UseMetadataTitleFirst
Reserved parameter for future use. Default: $false

.PARAMETER EnableLogging
Enables logging to error_log.txt. Default: $true

.PARAMETER EnableSafeRun
Debug mode that simulates all operations without modifying files. Default: $false

.EXAMPLE
# Normal execution - process all downloads
.\IMDBRenameAndCopy.ps1

.EXAMPLE
# Process specific folder
.\IMDBRenameAndCopy.ps1 -folderPath "G:\Download\Complete\MovieName"

.EXAMPLE
# SafeRun debug mode (no files are modified)
.\IMDBRenameAndCopy.ps1 -EnableSafeRun $true

.EXAMPLE
# Disable logging, process specific folder
.\IMDBRenameAndCopy.ps1 -folderPath "G:\Downloads\TVShow" -EnableLogging $false

.EXAMPLE
# qBittorrent completion call (add to qBittorrent "Run external program" on completion)
powershell -File "D:\Applications\Imdb\IMDBRenameAndCopy.ps1" "%F"

.NOTES
Author     : Nadeem Ahmad
Created    : 2026-03-09
Purpose    : Automated media library organization for torrent downloads
ShitList   : Auto-learns unwanted words from bracket content [like this]
Log file   : D:\Applications\Imdb\error_log.txt
ShitList   : D:\Applications\Imdb\ShitList.txt

To run from qBittorrent on download completion:
   In qBittorrent → Tools → Options → Downloads → "Run external program"
   Add: powershell -File "D:\Applications\Imdb\IMDBRenameAndCopy.ps1" "%F"
#>

param (
    [string]$folderPath = "G:\Download\Download\Complete",
    [bool]$UseMetadataTitleFirst = $false,     
    [bool]$EnableLogging = $true,
    [bool]$EnableSafeRun = $true
)

# ---------------------- DEBUG ----------------------
$global:DebugShowNameOnly = $EnableSafeRun
$ErrorActionPreference = "Stop"

if ($EnableSafeRun) {
    Write-Host "⚠️ DEBUG MODE ENABLED — NO FILE OPERATIONS WILL OCCUR" -ForegroundColor Yellow
}

# ---------------------- IMDB / OMDB VALIDATION ----------------------
$EnableImdbVerification = $true
$OmdbApiKey = "a1673d08"
$PauseIfImdbNotMatched = $true

# ---------------------- SAFETY CHECKS ----------------------
if ($folderPath -match '^[Ff]:\\') {
    Write-Host "❌ This script cannot run on the F: drive. Please choose another location." -ForegroundColor Red
    exit 1
}

if ($folderPath -notmatch '^[Gg]:\\') {
    $response = Read-Host "⚠️  Source drive is not G:\. Are you sure you want to continue? (y/N)"
    if ($response -notmatch '^[Yy]') { Write-Host "❌ Operation cancelled."; exit 1 }
}

$itemCount = (Get-ChildItem -LiteralPath $folderPath | Measure-Object).Count
if ($itemCount -gt 20) {
    $response = Read-Host "⚠️  Found $itemCount items. Continue? (y/N)"
    if ($response -notmatch '^[Yy]') { Write-Host "❌ Operation cancelled."; exit 1 }
}

# ---------------------- MUTEX ----------------------
$MutexName = "Global\QbitTorrent_Processor_Mutex_v1"
$Mutex = $null
$MutexAcquired = $false
try {
    $Mutex = New-Object System.Threading.Mutex($false, $MutexName)
    $MutexAcquired = $Mutex.WaitOne(60000)
    if (-not $MutexAcquired) { Write-Warning "Another instance is running."; exit 1 }
    Write-Host "🔒 Mutex acquired — proceeding..." -ForegroundColor Green
} catch {
    Write-Error "Failed to acquire mutex: $($_.Exception.Message)"; exit 1
}

# ---------------------- PATHS ----------------------
$basePath = "D:\Applications\Imdb\"
$destinationRoot = "F:\Movies"
$destinationRootSeries = "F:\Serier"
$destinationRootHindi = "F:\Hindi"
$mainFolder = "G:\Download\Download\Complete"
$toBeDeletedFolder = "G:\Download\Download\ToBeDeleted"

if (-not (Test-Path $toBeDeletedFolder)) { 
    New-Item -LiteralPath $toBeDeletedFolder -ItemType Directory -Force | Out-Null 
}

$logFilePath = "${basePath}error_log.txt"
$shitlistPath = "${basePath}ShitList.txt"

# Initialize ShitList
if (-not (Test-Path $shitlistPath)) { 
    Write-Host "⚠️ ShitList.txt not found! Creating empty file..." -ForegroundColor Yellow
    New-Item -LiteralPath $shitlistPath -ItemType File -Force | Out-Null 
}

# Load ShitList (ignore comments and empty lines)
$global:ShitList = Get-Content $shitlistPath | 
    Where-Object { $_ -and $_ -notmatch '^\s*#' } | 
    ForEach-Object { $_.Trim().ToLower() } | 
    Sort-Object -Unique

Write-Host "📋 Loaded $($global:ShitList.Count) words from ShitList" -ForegroundColor Cyan

$supportedVideoExtensions = @(".mp4", ".mkv", ".avi", ".mpg", ".mov", ".m4v") | ForEach-Object { $_.ToLower() }
$supportedSubtitleExtensions = @(".srt", ".sub") | ForEach-Object { $_.ToLower() }

$seriesPatterns = "S\d+E\d+", "Season\s*\d+", "Episode\s*\d+", "\.S\d+\.E\d+\.", "\.S\d+\.", "\.E\d+\.", "Part\s*\d+", "-\d+x\d+-"
$hindiIndicators = "hindi", "hind", "hdhi", "hindi-dub", "hindi.dub", "desi", "bollywood", "india", "indian"

# ---------------------- LOGGING ----------------------
function Log-Error {
    param ([string]$message)
    if ($EnableLogging) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "$timestamp - $message"
        Write-Host $logMessage
        Add-Content -LiteralPath $logFilePath -Value $logMessage
    }
}

# ---------------------- IMDB LOOKUP ----------------------
function Test-ImdbMovie {
    param(
        [string]$Title,
        [string]$Year
    )

    if (-not $EnableImdbVerification) { return $true }
    if ($Year -notmatch '^\d{4}$') { return $true }

    try {
        $encodedTitle = [uri]::EscapeDataString($Title)
        $url = "https://www.omdbapi.com/?t=$encodedTitle&y=$Year&apikey=$OmdbApiKey"
        $response = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 10

        if ($response.Response -eq "True") {
            Log-Error "🎬 IMDB Match Found → $($response.Title) ($($response.Year))"
            return $true
        } else {
            Write-Host ""
            Write-Host "⚠️ IMDB MATCH NOT FOUND:" -ForegroundColor Yellow
            Write-Host "Title: $Title"
            Write-Host "Year : $Year"
            Write-Host ""

            if ($PauseIfImdbNotMatched) {
                $choice = Read-Host "Continue anyway? (Y/N)"
                if ($choice -notmatch '^[Yy]') {
                    throw "User aborted due to missing IMDB match."
                }
            }
            return $false
        }
    }
    catch {
        Log-Error "⚠️ IMDB lookup failed: $($_.Exception.Message)"
        return $true
    }
}

# ---------------------- SHITLIST MANAGEMENT ----------------------
function Update-ShitList {
    param ([string]$word)
    $word = $word.Trim().ToLower()
    if ($word -and $word -notin $global:ShitList -and $word.Length -gt 1) {
        Add-Content -LiteralPath $shitlistPath -Value "# Added on $(Get-Date -Format 'yyyy-MM-dd'): $word"
        Add-Content -LiteralPath $shitlistPath -Value $word -Encoding UTF8
        $global:ShitList += $word
        Log-Error "📌 Added '$word' to ShitList."
    }
}

function Cleanup-ShitList {
    $currentList = Get-Content $shitlistPath | 
        Where-Object { $_ -and $_ -notmatch '^\s*#' } | 
        ForEach-Object { $_.Trim().ToLower() } | 
        Sort-Object -Unique
    
    # Backup old file
    $backupPath = $shitlistPath + ".bak"
    Copy-Item -LiteralPath $shitlistPath -Destination $backupPath -Force
    
    # Write clean list with header
    $header = @"
# ShitList - Auto-generated on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# Words in this list will be removed from filenames
# Add one word per line, lines starting with # are ignored
# ------------------------------------------------------------

"@
    
    $header | Set-Content $shitlistPath -Encoding UTF8
    $currentList | ForEach-Object { Add-Content $shitlistPath $_ }
    
    $global:ShitList = $currentList
    Log-Error "🧹 Cleaned ShitList - now contains $($global:ShitList.Count) unique words"
}

# ---------------------- CORE CLEANING FUNCTION ----------------------
function GetCleanTitle {
    param([string]$title)
    
    # PRESERVE YEAR EARLY - save it before we do heavy cleaning
    $year = "Unknown"
    if ($title -match '\b(19|20)\d{2}\b') {
        $year = $matches[0]
    }
    
    # Step 1: Extract and learn from bracket content
    $bracketMatches = [regex]::Matches($title, '\[([^\]]*)\]')
    foreach ($match in $bracketMatches) {
        $content = $match.Groups[1].Value
        $content -split '[\.\s_,-]' | ForEach-Object {
            if ($_.Length -gt 1 -and $_ -notmatch '^\d+$') {
                $cleanWord = $_ -replace '[\d\.]', ''  # Remove digits and dots
                if ($cleanWord.Length -gt 1) {
                    Update-ShitList $cleanWord
                }
            }
        }
    }
    
    # Step 2: Remove brackets and parentheses
    $title = $title -replace '\[[^\]]*\]', ''
    $title = $title -replace '\([^\)]*\)', ''
    
    # Step 3: Replace dots and underscores with spaces
    $title = $title -replace '[._]', ' '
    
    # Step 4: Aggressive removal of common patterns
    # Remove audio codec patterns (AAC5.1, AAC5, AC3, DTS, etc.)
    $title = $title -replace '(?i)\b(?:AAC|AC3|DTS|MP3|EAC3|TRUEHD)[\d\.]*\b', ''
    # Remove resolution patterns
    $title = $title -replace '(?i)\b\d{3,4}p\b', ''
    # Remove source patterns
    $title = $title -replace '(?i)\b(?:WEBRip|WEB-DL|BluRay|HDRip|BRRip|DVDRip)\b', ''
    # Remove codec patterns
    $title = $title -replace '(?i)\b(?:x264|x265|HEVC|AVC|AV1)\b', ''
    # Remove release group (dash followed by uppercase word at end)
    $title = $title -replace '\s*-\s*[A-Z0-9]+$', ''
    $title = $title -replace '\s*-\s*[A-Z0-9]+\s*$', ''
    
    # Step 5: Apply ShitList
    foreach ($badWord in $global:ShitList) {
        $pattern = '(?i)(^|[\s])' + [regex]::Escape($badWord) + '($|[\s])'
        $title = $title -replace $pattern, ' '
    }
    
    # Step 6: Clean up special characters
    $title = $title -replace '[!?@#$%^&*=+|\\/<>:;",]', ' '
    
    # Step 7: Remove leftover standalone letters/numbers
    $title = $title -replace '\s+\w\s+', ' '
    $title = $title -replace '^\w\s+', ''
    $title = $title -replace '\s+\w$', ''
    
    # Step 8: Collapse spaces and trim
    $title = $title -replace '\s+', ' '
    $title = $title.Trim()
    
    # Step 9: Remove any trailing dash
    $title = $title -replace '\s*-\s*$', ''
    $title = $title -replace '^\s*-\s*', ''
    
    # Step 10: Clean up double spaces again
    $title = $title -replace '\s+', ' '
    $title = $title.Trim()
    
    # Step 11: Remove year from title if present (we saved it earlier)
    if ($year -ne "Unknown") {
        $title = $title -replace "\b$year\b", ''
        $title = $title -replace '\s+', ' '
        $title = $title.Trim()
    }
    
    if (-not $title) { $title = "Unknown Title" }
    
    return @($title, $year)
}

# ---------------------- FILE TYPE TESTS ----------------------
function Test-SeriesFile { 
    param([string]$fileName) 
    $seriesPatterns | Where-Object { $fileName -match $_ -and $fileName -notmatch "sample" } | 
        Measure-Object | Select-Object -Expand Count | ForEach-Object { $_ -gt 0 } 
}

function Test-HindiFile { 
    param([string]$fileName) 
    $hindiIndicators | Where-Object { $fileName.ToLower() -match $_ -and $fileName -notmatch "sample" } | 
        Measure-Object | Select-Object -Expand Count | ForEach-Object { $_ -gt 0 } 
}

function Get-SeasonEpisodeInfo {
    param([string]$fileName)

    if ($fileName -match '(?i)S(\d{1,2})E(\d{1,2})') {
        $season  = [int]$matches[1]
        $episode = [int]$matches[2]
    }
    elseif ($fileName -match '(?i)(\d{1,2})x(\d{1,2})') {
        $season  = [int]$matches[1]
        $episode = [int]$matches[2]
    }
    elseif ($fileName -match '(?i)Season\D*(\d{1,2}).*Episode\D*(\d{1,2})') {
        $season  = [int]$matches[1]
        $episode = [int]$matches[2]
    }
    else {
        return $null
    }

    $seasonFormatted  = $season.ToString("D2")
    $episodeFormatted = $episode.ToString("D2")

    return @{
        SeasonNumber   = $seasonFormatted
        EpisodeNumber  = $episodeFormatted
        Tag            = "S${seasonFormatted}E${episodeFormatted}"
    }
}

# ---------------------- COPY WITH PROGRESS ----------------------
function Copy-WithProgress {
    param (
        [Parameter(Mandatory)]
        [string]$SourcePath,
        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    try {
        $sourceItem = Get-Item -Path $SourcePath -ErrorAction Stop
    }
    catch {
        $msg = "❌ FATAL: Source not found after rename: $SourcePath"
        Log-Error $msg
        throw $msg
    }

    if ($sourceItem.Length -le 0) {
        $msg = "❌ FATAL: Source file is empty: $SourcePath"
        Log-Error $msg
        throw $msg
    }

    $totalSize   = $sourceItem.Length
    $bufferSize  = 1MB
    $bytesCopied = 0

    $inputStream  = [System.IO.File]::OpenRead($sourceItem.FullName)
    $outputStream = [System.IO.File]::Create($DestinationPath)
    $buffer       = New-Object byte[] $bufferSize

    try {
        while (($bytesRead = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $outputStream.Write($buffer, 0, $bytesRead)
            $bytesCopied += $bytesRead
            $percentComplete = [math]::Round(($bytesCopied / $totalSize) * 100, 2)
            Write-Progress `
                -Activity "Copying $($sourceItem.Name)" `
                -Status "$percentComplete% Complete" `
                -PercentComplete $percentComplete
        }
    }
    finally {
        $inputStream.Close()
        $outputStream.Close()
        Write-Progress -Activity "Copying" -Completed
    }

    Log-Error "✅ Copy completed: $DestinationPath"
    return $true
}

# ---------------------- MOVE TO TOBEDELETED ----------------------
function Move-ToBeDeleted {
    param ([string]$folderPath)
    try {
        $folderName = Split-Path $folderPath -Leaf
        $destinationPath = Join-Path $toBeDeletedFolder $folderName
        if (Test-Path $destinationPath) { 
            $folderName += "-$(Get-Date -Format 'yyyyMMddHHmmss')"
            $destinationPath = Join-Path $toBeDeletedFolder $folderName 
        }
        Move-Item -LiteralPath $folderPath -Destination $destinationPath -Force
        Log-Error "🗑️ Moved processed folder to ToBeDeleted: $folderName"
    } catch { 
        Log-Error "⚠️ Error moving folder: $($_.Exception.Message)" 
    }
}

function Resolve-DestinationPath {
    param (
        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    if (-not (Test-Path $DestinationPath)) {
        return $DestinationPath
    }

    $choice = Read-Host "⚠️ File exists: $(Split-Path $DestinationPath -Leaf). Replace? (y/N)"

    if ($choice -match '^[Yy]') {
        return $DestinationPath
    }

    $dir  = Split-Path $DestinationPath -Parent
    $name = [System.IO.Path]::GetFileNameWithoutExtension($DestinationPath)
    $ext  = [System.IO.Path]::GetExtension($DestinationPath)

    $i = 2
    do {
        $newPath = Join-Path $dir "$name`_$i$ext"
        $i++
    } while (Test-Path $newPath)

    Write-Host "➡️ Using new filename: $(Split-Path $newPath -Leaf)" -ForegroundColor Yellow
    return $newPath
}

# ---------------------- PROCESSING PLAN ----------------------
function Get-ProcessingPlan {
    param (
        [string]$baseName,
        [string]$fileExtension,
        [switch]$IsSubtitle
    )

    $result = GetCleanTitle $baseName
    $title  = $result[0]
    $year   = $result[1]

    if (-not $title -or $title -eq "Unknown Title") { 
        Log-Error "⚠️ Could not extract title from: $baseName"
        return $null 
    }

    $isSeries = Test-SeriesFile -fileName $baseName
    $isHindi  = Test-HindiFile -fileName $baseName

    $seasonEpisodeInfo = $null
    if ($isSeries) {
        $seasonEpisodeInfo = Get-SeasonEpisodeInfo $baseName
    }

    # Select destination root
    if ($isSeries) {
        $destinationRootFinal = $destinationRootSeries
        $typeLabel = "📺 Series"
    }
    elseif ($isHindi) {
        $destinationRootFinal = $destinationRootHindi
        $typeLabel = "🇮🇳 Hindi"
    }
    else {
        $destinationRootFinal = $destinationRoot
        $typeLabel = "🎬 Movie"
    }

    # Build destination path and filename
    if ($isSeries -and $seasonEpisodeInfo) {
        $seriesFolderName = $title -replace '(?i)\s*S\d{1,2}E\d{1,2}', ''
        $seriesFolderName = $seriesFolderName.Trim()
        $seasonFolderName = "Season $([int]$seasonEpisodeInfo.SeasonNumber)"
        $destinationFolder = Join-Path (Join-Path $destinationRootFinal $seriesFolderName) $seasonFolderName
        $displayName = $title
    }
    elseif (-not $isSeries) {
        Test-ImdbMovie -Title $title -Year $year
        
        if ($year -match '^\d{4}$') {
            if ([int]$year -lt 2008) {
                $destinationFolder = Join-Path $destinationRootFinal "1985-7"
            }
            else {
                $destinationFolder = Join-Path $destinationRootFinal $year
            }
            $displayName = "$title ($year)"
        }
        else {
            $destinationFolder = Join-Path $destinationRootFinal "UnknownYear"
            $displayName = $title
        }
    }
    else {
        $destinationFolder = $destinationRootFinal
        $displayName = "$title ($year)"
    }

    $newFileName = "$displayName$fileExtension"

    return @{
        NewFileName       = $newFileName
        DestinationFolder = $destinationFolder
        TypeLabel         = $typeLabel
        IsSeries          = $isSeries
        IsHindi           = $isHindi
        Title             = $title
        Year              = $year
        BaseName          = $baseName
    }
}

# ---------------------- PROCESS FOLDER ----------------------
function ProcessFolder($folderToProcess) {
    try {
        if ($global:DebugShowNameOnly) {
            Log-Error "🔍 DEBUG MODE — No files will be copied, renamed, deleted, or moved."
        }
        
        Log-Error "📂 Processing Folder: $folderToProcess"
        $videoCopiedSuccessfully = $false
        $isSeriesFolder = $false

        $videoFiles = Get-ChildItem -LiteralPath $folderToProcess -File |
            Where-Object { $_.Extension.ToLower() -in $supportedVideoExtensions }

        $subtitleFiles = Get-ChildItem -LiteralPath $folderToProcess -File |
            Where-Object { $_.Extension.ToLower() -in $supportedSubtitleExtensions }

        $verifiedFiles = @()

        # Process video files
        foreach ($file in $videoFiles) {
            $currentFileName = $file.Name

            try {
                $plan = Get-ProcessingPlan -baseName $file.BaseName -fileExtension $file.Extension

                if ($plan.IsSeries) { $isSeriesFolder = $true }
                if (-not $plan) { continue }

                Log-Error "$($plan.TypeLabel) → Destination: $($plan.DestinationFolder)"

                if ($global:DebugShowNameOnly) {
                    Log-Error "🔍 [DEBUG] '$($file.Name)' → '$($plan.NewFileName)'"
                    continue
                }

                # Rename file
                $currentFilePath = $file.FullName
                $newFilePath = Join-Path $file.DirectoryName $plan.NewFileName

                if (Test-Path -LiteralPath $newFilePath) {
                    Log-Error "🎬 Already renamed: $($plan.NewFileName)"
                }
                elseif (Test-Path -LiteralPath $currentFilePath) {
                    Rename-Item -LiteralPath $currentFilePath -NewName $plan.NewFileName
                    Log-Error "🎬 Renamed: $($file.Name) → $($plan.NewFileName)"
                }
                else {
                    Log-Error "❌ Source file not found at either path — skipping"
                    continue
                }

                # Create destination folder if needed
                if (-not (Test-Path $plan.DestinationFolder)) {                    
                    New-Item -Path $plan.DestinationFolder -ItemType Directory -Force | Out-Null
                    Log-Error "📁 Created folder: $($plan.DestinationFolder)"
                }

                # Copy file
                $destinationFilePath = Join-Path $plan.DestinationFolder $plan.NewFileName
                $destinationFilePath = Resolve-DestinationPath $destinationFilePath

                Copy-WithProgress -SourcePath $newFilePath -DestinationPath $destinationFilePath
             
                # Validate copy
                $src  = Get-Item -Path $newFilePath -ErrorAction Stop
                $dest = Get-Item -Path $destinationFilePath -ErrorAction Stop
                if ($src.Length -ne $dest.Length) {
                    throw "❌ Copy validation failed (size mismatch)"
                }

                Log-Error "✅ Copy verified: $($plan.NewFileName)"
                $videoCopiedSuccessfully = $true
                $verifiedFiles += $newFilePath
            }
            catch {
                Log-Error "❌ FATAL processing video '$currentFileName' : $($_.Exception.Message)"
                throw
            }
        }

        # Process subtitle files
        foreach ($file in $subtitleFiles) {
            try {
                $plan = Get-ProcessingPlan -baseName $file.BaseName -fileExtension $file.Extension -IsSubtitle

                if (-not $plan) { continue }

                Log-Error "$($plan.TypeLabel) (Subtitle) → Destination: $($plan.DestinationFolder)"

                if ($global:DebugShowNameOnly) {
                    Log-Error "🔍 [DEBUG] '$($file.Name)' → '$($plan.NewFileName)'"
                    continue
                }

                Rename-Item -Path $file.FullName -NewName $plan.NewFileName
                $newFilePath = Join-Path $file.DirectoryName $plan.NewFileName
                Log-Error "📜 Renamed: $($file.Name) → $($plan.NewFileName)"

                if (-not (Test-Path $plan.DestinationFolder)) {
                    New-Item -LiteralPath $plan.DestinationFolder -ItemType Directory -Force | Out-Null
                }

                $destinationFilePath = Join-Path $plan.DestinationFolder $plan.NewFileName
                Copy-Item -LiteralPath $newFilePath -Destination $destinationFilePath -Force

                $verifiedFiles += $newFilePath
                Log-Error "✅ Copied subtitle: $($plan.NewFileName)"
            }
            catch {
                Log-Error "⚠️ Error processing subtitle '$($file.Name)': $($_.Exception.Message)"
            }
        }

        # Cleanup
        if ($videoCopiedSuccessfully -and -not $global:DebugShowNameOnly) {
            foreach ($filePath in $verifiedFiles) {
                try {
                    Remove-Item -LiteralPath $filePath -Force
                    Log-Error "🗑️ Deleted source file: $filePath"
                }
                catch {
                    Log-Error "⚠️ Failed to delete file: $filePath"
                }
            }

            if ($folderToProcess -ne $mainFolder) {
                $remainingItems = Get-ChildItem -LiteralPath $folderToProcess -Force

                if ($remainingItems.Count -eq 0) {
                    try {
                        Remove-Item -LiteralPath $folderToProcess -Force
                        Log-Error "🧹 Folder empty — deleted: $folderToProcess"
                    }
                    catch {
                        Log-Error "⚠️ Failed to delete empty folder: $folderToProcess"
                    }
                    return
                }

                $remainingLargeVideos = Get-ChildItem -LiteralPath $folderToProcess -Recurse -File |
                    Where-Object {
                        $_.Extension.ToLower() -in $supportedVideoExtensions -and
                        $_.Length -gt 150MB
                    }

                if ($remainingLargeVideos.Count -gt 0) {
                    Log-Error "🎥 Remaining large video files found — folder will NOT be moved."
                }
                else {
                    Log-Error "📦 Only junk files remain — moving folder to ToBeDeleted."
                    Move-ToBeDeleted $folderToProcess
                }
            }
        }
        elseif (-not $global:DebugShowNameOnly) {
            if ($folderToProcess -ne $mainFolder) {
                $remainingLargeVideos = Get-ChildItem -LiteralPath $folderToProcess -Recurse -File |
                    Where-Object {
                        $_.Extension.ToLower() -in $supportedVideoExtensions -and
                        $_.Length -gt 150MB
                    }

                if ($remainingLargeVideos.Count -eq 0) {
                    Move-ToBeDeleted $folderToProcess
                }
                else {
                    Log-Error "🎥 Large video files exist but none processed — leaving folder."
                }
            }
        }
    }
    catch {
        Log-Error "⚠️ Error in ProcessFolder: $($_.Exception.Message)"
        throw
    }
}

# ---------------------- PROCESS SUBFOLDERS ----------------------
function ProcessSubfolders($folderPath) {
    if ($folderPath -eq $mainFolder) {
        ProcessFolder $mainFolder
        Get-ChildItem -LiteralPath $mainFolder -Directory | ForEach-Object { ProcessFolder $_.FullName }
    } 
    else { 
        ProcessFolder $folderPath 
    }
}

# ---------------------- MAIN EXECUTION ----------------------
try {
    Log-Error "---------------------------- 🚀 Starting folder processing..."
    Cleanup-ShitList
    ProcessSubfolders $folderPath
    Log-Error "🏁 Finished folder processing."
    Write-Host "`n✅ Processing complete! ShitList now contains $($global:ShitList.Count) words." -ForegroundColor Green
}
catch {
    Log-Error "❌ UNHANDLED FATAL ERROR: $($_.Exception.Message)"
    Write-Host "❌ Script aborted due to fatal error." -ForegroundColor Red
    exit 1
}
finally {
    if ($MutexAcquired -and $Mutex) {
        $Mutex.ReleaseMutex()
        Write-Host "🔓 Mutex released." -ForegroundColor Green
    }
    if ($Mutex) { $Mutex.Dispose() }
}

Start-Sleep -Seconds 5
