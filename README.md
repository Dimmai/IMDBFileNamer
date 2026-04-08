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
