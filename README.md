# IMDBRenameAndCopy

[![PowerShell Version](https://img.shields.io/badge/PowerShell-5.0+-blue.svg)](https://github.com/PowerShell/PowerShell)

Automated media processor that cleans, renames, and organizes downloaded video files into a structured library. Designed for qBittorrent integration.

## Features

- **Smart Filename Cleaning** - Removes release groups, codecs, resolutions, audio tags, and junk text
- **Auto-Learning ShitList** - Automatically learns unwanted words from bracket content [like this]
- **Content Detection** - Automatically identifies Movies, TV Series, and Hindi/Bollywood content
- **Episode Parsing** - Supports S02E03, 2x03, and Season 2 Episode 3 formats
- **IMDB Verification** - Optional OMDB API validation to confirm movies exist
- **Structured Organization** - Creates consistent folder structures
- **Integrity Validation** - Compares source and destination file sizes after copy
- **Subtitle Support** - Processes and matches subtitle files (.srt, .sub)
- **Safety Features** - Mutex locking, SafeRun debug mode, drive restrictions, conflict resolution

## Requirements

- PowerShell 5.0 or higher
- Windows operating system
- Write access to destination drives (F:, G:) and log directory (D:)

## Installation

1. Clone or download this script to your desired location:
D:\Applications\Imdb\IMDBRenameAndCopy.ps1

Create the required directory structure:
D:\Applications\Imdb\
F:\Movies\
F:\Serier\
F:\Hindi\
G:\Download\Download\Complete\
G:\Download\Download\ToBeDeleted\
(Optional) Create initial ShitList.txt file in D:\Applications\Imdb\

Usage
Basic Commands
Process all downloads in default folder:

powershell
.\IMDBRenameAndCopy.ps1
Process a specific folder:

powershell
.\IMDBRenameAndCopy.ps1 -folderPath "G:\Download\Complete\MovieName"
SafeRun debug mode (no files are modified):

powershell
.\IMDBRenameAndCopy.ps1 -EnableSafeRun $true
Disable logging:

powershell
.\IMDBRenameAndCopy.ps1 -EnableLogging $false
Parameters
Parameter	Type	Default	Description
folderPath	string	G:\Download\Download\Complete	Root folder containing downloads
UseMetadataTitleFirst	bool	false	Reserved for future use
EnableLogging	bool	true	Enables logging to error_log.txt
EnableSafeRun	bool	false	Debug mode (simulates all operations)
qBittorrent Integration
Add to qBittorrent:

Go to Tools → Options → Downloads

Find "Run external program" field

Add this line:

powershell
powershell -File "D:\Applications\Imdb\IMDBRenameAndCopy.ps1" "%F"
Folder Structure
Source (G:) Destination (F:)

text
G:\Download\Complete\              F:\Movies\
    Movie.2024.1080p\                 2024\
    TV.Show.S02E03\                   Movie Title (2024).mkv
    Hindi.Movie.2024\                 
                                   F:\Serier\
G:\Download\ToBeDeleted\              TV Show\
    (junk folders)                    Season 02\
                                      TV Show S02E03.mkv
                                      
                                   F:\Hindi\
                                      2024\
                                      Hindi Movie (2024).avi
Configuration
ShitList.txt
Located at: D:\Applications\Imdb\ShitList.txt

Add one unwanted word per line:

text
# Resolution tags
1080p
720p
4k

# Codec tags
x264
x265
hevc

# Audio tags
ac3
dts
aac
The script automatically learns new words found in brackets [like this] and adds them to the ShitList.

IMDB Verification
Edit these variables in the script:

powershell
$EnableImdbVerification = $true
$OmdbApiKey = "your_api_key_here"
$PauseIfImdbNotMatched = $true
Get a free API key at: http://www.omdbapi.com/apikey.aspx

Safety Features
Feature	Description
Mutex Locking	Prevents multiple script instances from running simultaneously
SafeRun Mode	Performs a full simulation without modifying any files
Drive Restrictions	Blocks execution on F: drive, warns on non-G: drives
Copy Validation	Verifies file sizes after copying to ensure integrity
Interactive Conflicts	Prompts before overwriting existing files
Item Count Check	Warns when processing more than 20 items
Logging
Logs are written to: D:\Applications\Imdb\error_log.txt

Example log output:

text
2026-03-09 10:30:15 - 🚀 Starting folder processing...
2026-03-09 10:30:16 - 📂 Processing Folder: G:\Download\Complete\Movie.2024.1080p
2026-03-09 10:30:17 - 🎬 Movie → Destination: F:\Movies\2024
2026-03-09 10:30:18 - ✅ Copy verified: Movie Title (2024).mkv
2026-03-09 10:30:19 - 🗑️ Deleted source file
2026-03-09 10:30:20 - 🏁 Finished folder processing.
Troubleshooting
Issue	Solution
Script won't run on F: drive	This is intentional for safety. Move source files to G:
Another instance is running	Wait for current instance to finish or restart system
IMDB verification fails	Check API key or disable verification in script
Files not being processed	Verify file extensions are supported (.mp4, .mkv, .avi, etc.)
Destination folder access denied	Run PowerShell as administrator
Testing
Always test with SafeRun mode first:

powershell
.\IMDBRenameAndCopy.ps1 -EnableSafeRun $true
Author
Nadeem Ahmad

Created: 2026-03-09

Purpose: Automated media library organization for torrent downloads

Acknowledgments
OMDb API for movie verification

qBittorrent for download management

Disclaimer
This script moves and deletes files. Always test with SafeRun mode first and maintain backups of important data.

text

This should display correctly on GitHub with proper markdown formatting. The key fixes:
- Removed emojis from headers (some markdown parsers struggle with them)
- Proper code blocks with triple backticks
- Clean table formatting
- Consistent spacing
- Plain text folder structure using indentation
