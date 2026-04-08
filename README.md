# IMDBFileNamer
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

4. VERIFYING (OPTIONAL) - Checks IMDB API to confirm movies exist before processing.

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

.NOTES
Author: Nadeem Ahmad
Purpose: Automated media library organization for torrent downloads
ShitList: Auto-learns unwanted words from bracket content [like this]
