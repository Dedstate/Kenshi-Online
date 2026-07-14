@echo off
setlocal enabledelayedexpansion
title KenshiMP Installer
color 0A

echo.
echo  ============================================
echo   KenshiMP - Kenshi Multiplayer Mod
echo   One-Click Installer
echo   made with love by fourzerofour
echo  ============================================
echo.

:: ── Auto-detect Kenshi directory ──
:: Try common locations, then fall back to asking

set "KENSHI_DIR="

:: Check if we're already in the Kenshi folder
if exist "%~dp0kenshi_x64.exe" (
    set "KENSHI_DIR=%~dp0"
    goto :found_kenshi
)

:: Check if we're in a subfolder of Kenshi
if exist "%~dp0..\kenshi_x64.exe" (
    set "KENSHI_DIR=%~dp0..\"
    goto :found_kenshi
)

:: Try Steam default location
set "STEAM_KENSHI=C:\Program Files (x86)\Steam\steamapps\common\Kenshi"
if exist "%STEAM_KENSHI%\kenshi_x64.exe" (
    set "KENSHI_DIR=%STEAM_KENSHI%"
    goto :found_kenshi
)

:: Try GOG default
set "GOG_KENSHI=C:\GOG Games\Kenshi"
if exist "%GOG_KENSHI%\kenshi_x64.exe" (
    set "KENSHI_DIR=%GOG_KENSHI%"
    goto :found_kenshi
)

:: Ask user
echo  Could not auto-detect Kenshi installation.
echo  Please enter the path to your Kenshi folder:
echo  (The folder containing kenshi_x64.exe)
echo.
set /p "KENSHI_DIR=Path: "

if not exist "%KENSHI_DIR%\kenshi_x64.exe" (
    echo.
    echo  [ERROR] kenshi_x64.exe not found at: %KENSHI_DIR%
    echo  Make sure you entered the correct Kenshi folder.
    echo.
    pause
    exit /b 1
)

:found_kenshi
:: Remove trailing backslash if present
if "%KENSHI_DIR:~-1%"=="\" set "KENSHI_DIR=%KENSHI_DIR:~0,-1%"

echo  Found Kenshi at: %KENSHI_DIR%
echo.

:: ── Check if Kenshi is running ──
tasklist /FI "IMAGENAME eq kenshi_x64.exe" 2>NUL | find /I "kenshi_x64.exe" >NUL
if %errorlevel% equ 0 (
    echo  [WARNING] Kenshi is currently running!
    echo  Please close Kenshi before installing.
    echo.
    pause
    exit /b 1
)

:: ── Verify required files are present in the installer ──
set "MISSING_FILES="
if not exist "%~dp0KenshiMP.Core.dll" set "MISSING_FILES=!MISSING_FILES! KenshiMP.Core.dll"
if not exist "%~dp0Kenshi_MainMenu.layout" set "MISSING_FILES=!MISSING_FILES! Kenshi_MainMenu.layout"
if not exist "%~dp0Kenshi_MultiplayerPanel.layout" set "MISSING_FILES=!MISSING_FILES! Kenshi_MultiplayerPanel.layout"

if not "!MISSING_FILES!"=="" (
    echo  [ERROR] The installer package is incomplete.
    echo  Missing files:!MISSING_FILES!
    echo.
    echo  Re-download the latest release from:
    echo    https://github.com/WokiDev/Kenshi-Online/releases
    pause
    exit /b 1
)

:: ── Ensure required directories exist ──
if not exist "%KENSHI_DIR%\data\gui\layout" (
    echo  [WARNING] Kenshi GUI layout folder is missing.
    echo  Path: %KENSHI_DIR%\data\gui\layout
    echo  Verify your Kenshi installation is complete (Steam: Verify integrity).
    pause
    exit /b 1
)

:: ── Create backups ──
echo  [1/7] Creating backups...

set "BACKUP_DIR=%KENSHI_DIR%\KenshiMP_backup"
if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%"

if exist "%KENSHI_DIR%\Plugins_x64.cfg" (
    if not exist "%BACKUP_DIR%\Plugins_x64.cfg.bak" (
        copy /Y "%KENSHI_DIR%\Plugins_x64.cfg" "%BACKUP_DIR%\Plugins_x64.cfg.bak" >nul
        echo         Backed up Plugins_x64.cfg
    )
)

if exist "%KENSHI_DIR%\data\gui\layout\Kenshi_MainMenu.layout" (
    if not exist "%BACKUP_DIR%\Kenshi_MainMenu.layout.bak" (
        copy /Y "%KENSHI_DIR%\data\gui\layout\Kenshi_MainMenu.layout" "%BACKUP_DIR%\Kenshi_MainMenu.layout.bak" >nul
        echo         Backed up Kenshi_MainMenu.layout
    )
)

if exist "%KENSHI_DIR%\data\__mods.list" (
    if not exist "%BACKUP_DIR%\__mods.list.bak" (
        copy /Y "%KENSHI_DIR%\data\__mods.list" "%BACKUP_DIR%\__mods.list.bak" >nul
        echo         Backed up __mods.list
    )
)

:: ── Copy DLL ──
echo  [2/7] Installing KenshiMP.Core.dll...

copy /Y "%~dp0KenshiMP.Core.dll" "%KENSHI_DIR%\KenshiMP.Core.dll" >nul
if errorlevel 1 (
    echo  [ERROR] Failed to copy DLL. Is Kenshi running? Try running as Administrator.
    pause
    exit /b 1
)
echo         Copied KenshiMP.Core.dll

:: ── Patch Plugins_x64.cfg ──
:: We never blindly append: that risks producing
::   Plugin=RenderSystem_Direct3D11Plugin=KenshiMP.Core
:: on a single line if the file lacks a trailing newline.
:: PowerShell rewrites the file with consistent CRLF line endings.
echo  [3/7] Patching Plugins_x64.cfg...

findstr /B /C:"Plugin=KenshiMP.Core" "%KENSHI_DIR%\Plugins_x64.cfg" >nul 2>&1
if errorlevel 1 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = Join-Path '%KENSHI_DIR%' 'Plugins_x64.cfg'; $lines = @(); if (Test-Path $p) { $lines = @(Get-Content -LiteralPath $p) }; $lines = @($lines | Where-Object { $_ -ne 'Plugin=KenshiMP.Core' }); $lines += 'Plugin=KenshiMP.Core'; Set-Content -LiteralPath $p -Value $lines -Encoding ASCII"
    if errorlevel 1 (
        echo  [ERROR] Failed to patch Plugins_x64.cfg. Try running as Administrator.
        pause
        exit /b 1
    )
    echo         Added KenshiMP.Core plugin entry
) else (
    echo         Plugin entry already exists
)

:: ── Install Main Menu Layout (always overwrite with pre-patched copy) ──
:: The previous version used a fragile in-place PowerShell regex insertion
:: that often produced malformed XML on user systems. The shipped
:: Kenshi_MainMenu.layout is a vanilla layout with the MULTIPLAYER button
:: already in place — overwriting is reliable across Kenshi versions and
:: locales because the layout file has not changed since FCS 1.0.
:: The original is preserved in KenshiMP_backup\.
echo  [4/7] Installing main menu layout...

copy /Y "%~dp0Kenshi_MainMenu.layout" "%KENSHI_DIR%\data\gui\layout\Kenshi_MainMenu.layout" >nul
if errorlevel 1 (
    echo  [ERROR] Failed to install Kenshi_MainMenu.layout.
    pause
    exit /b 1
)
echo         Installed Kenshi_MainMenu.layout (with MULTIPLAYER button)

:: ── Copy Multiplayer Layouts ──
echo  [5/7] Installing multiplayer layouts...

copy /Y "%~dp0Kenshi_MultiplayerPanel.layout" "%KENSHI_DIR%\data\gui\layout\Kenshi_MultiplayerPanel.layout" >nul
if errorlevel 1 (
    echo  [ERROR] Failed to install Kenshi_MultiplayerPanel.layout.
    pause
    exit /b 1
)
echo         Copied Kenshi_MultiplayerPanel.layout

if exist "%~dp0Kenshi_MultiplayerHUD.layout" (
    copy /Y "%~dp0Kenshi_MultiplayerHUD.layout" "%KENSHI_DIR%\data\gui\layout\Kenshi_MultiplayerHUD.layout" >nul
    echo         Copied Kenshi_MultiplayerHUD.layout
) else (
    echo  [WARNING] Kenshi_MultiplayerHUD.layout not found (in-game HUD may not work)
)

:: ── Install Multiplayer Mod ──
echo  [6/7] Installing kenshi-online.mod...

if exist "%~dp0kenshi-online.mod" (
    :: Copy to data/ (always loaded by the game engine)
    copy /Y "%~dp0kenshi-online.mod" "%KENSHI_DIR%\data\kenshi-online.mod" >nul
    echo         Copied kenshi-online.mod to data\

    :: Also copy to mods/kenshi-online/ (standard mod location)
    if not exist "%KENSHI_DIR%\mods\kenshi-online" mkdir "%KENSHI_DIR%\mods\kenshi-online"
    copy /Y "%~dp0kenshi-online.mod" "%KENSHI_DIR%\mods\kenshi-online\kenshi-online.mod" >nul
    echo         Copied kenshi-online.mod to mods\

    :: Add to __mods.list if not present, normalising line endings via PowerShell.
    if not exist "%KENSHI_DIR%\data\__mods.list" type nul > "%KENSHI_DIR%\data\__mods.list"
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = Join-Path '%KENSHI_DIR%' 'data\__mods.list'; $lines = @(); if (Test-Path $p) { $lines = @(Get-Content -LiteralPath $p) }; $lines = @($lines | Where-Object { $_ -ne 'kenshi-online' -and $_ -ne '' }); $lines += 'kenshi-online'; Set-Content -LiteralPath $p -Value $lines -Encoding ASCII"
    echo         Registered kenshi-online in mod load list
) else (
    echo         [INFO] kenshi-online.mod not in package (mod template spawning disabled)
)

:: ── Copy Server ──
echo  [7/7] Installing dedicated server...

if exist "%~dp0KenshiMP.Server.exe" (
    copy /Y "%~dp0KenshiMP.Server.exe" "%KENSHI_DIR%\KenshiMP.Server.exe" >nul
    echo         Copied KenshiMP.Server.exe
) else (
    echo         [INFO] KenshiMP.Server.exe not in package (hosting optional)
)

:: ── Done ──
echo.
echo  ============================================
echo   Installation complete!
echo  ============================================
echo.
echo   TO JOIN A GAME:
echo   1. Launch Kenshi normally
echo   2. Click MULTIPLAYER on the main menu
echo   3. Click JOIN GAME, enter the host's IP
echo   4. Click CONNECT, then click NEW GAME
echo   5. You'll auto-connect when the world loads!
echo.
echo   TO HOST A GAME:
echo   1. Launch Kenshi normally
echo   2. Click MULTIPLAYER on the main menu
echo   3. Click HOST GAME (starts the server)
echo   4. Port 27800 is auto-forwarded via UPnP
echo   5. Share your IP with friends!
echo   6. Click NEW GAME to start playing
echo.
echo   Default port: 27800
echo   Backups saved to: %BACKUP_DIR%
echo   To uninstall, run uninstall.bat
echo.
pause
