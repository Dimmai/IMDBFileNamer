@echo off
:: Get the first argument from Directory Opus, use current directory as fallback
set "folderPath=%~1"
if "%folderPath%"=="" set "folderPath=%CD%"

:: Run PowerShell script hidden -NoExit is removed
powershell -ExecutionPolicy Bypass -File "D:\Applications\Imdb\IMDBRenameAndCopy.ps1" -folderPath "%folderPath%"
@echo off

IF %ERRORLEVEL% NEQ 0 (
    echo Error occurred: %ERRORLEVEL%
	pause
)

