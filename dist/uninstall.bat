@echo off
setlocal enabledelayedexpansion
title KenshiMP Uninstaller
color 0C

echo.
echo  ============================================
echo   KenshiMP - Uninstaller
echo  ============================================
echo.

:: ── Auto-detect Kenshi directory ──
set "KENSHI_DIR="

if exist "%~dp0kenshi_x64.exe" (
    set "KENSHI_DIR=%~dp0"
    goto :found
)
if exist "%~dp0..\kenshi_x64.exe" (
    set "KENSHI_DIR=%~dp0..\"
    goto :found
)
set "STEAM_KENSHI=C:\Program Files (x86)\Steam\steamapps\common\Kenshi"
if exist "%STEAM_KENSHI%\kenshi_x64.exe" (
    set "KENSHI_DIR=%STEAM_KENSHI%"
    goto :found
)
set "GOG_KENSHI=C:\GOG Games\Kenshi"
if exist "%GOG_KENSHI%\kenshi_x64.exe" (
    set "KENSHI_DIR=%GOG_KENSHI%"
    goto :found
)
echo  Could not find Kenshi. Enter path:
set /p "KENSHI_DIR=Path: "
if not exist "%KENSHI_DIR%\kenshi_x64.exe" (
    echo  [ERROR] kenshi_x64.exe not found.
    pause
    exit /b 1
)

:found
if "%KENSHI_DIR:~-1%"=="\" set "KENSHI_DIR=%KENSHI_DIR:~0,-1%"
echo  Found Kenshi at: %KENSHI_DIR%
echo.

:: Check if running
tasklist /FI "IMAGENAME eq kenshi_x64.exe" 2>NUL | find /I "kenshi_x64.exe" >NUL
if %errorlevel% equ 0 (
    echo  [WARNING] Kenshi is running. Close it first.
    pause
    exit /b 1
)

set "BACKUP_DIR=%KENSHI_DIR%\KenshiMP_backup"

echo  Removing KenshiMP...
echo.

:: ── Always strip the Plugin entry from Plugins_x64.cfg ──
:: This is the critical step that ensures Kenshi still launches if the user
:: has no backup or has already restored their config manually.
:: If we only removed KenshiMP.Core.dll without removing the plugin line,
:: Ogre would fail to load the (now missing) plugin and the game would not
:: start — this was issue #65 "Game won't open after uninstalling".
if exist "%KENSHI_DIR%\Plugins_x64.cfg" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = Join-Path '%KENSHI_DIR%' 'Plugins_x64.cfg'; if (Test-Path $p) { $lines = @(Get-Content -LiteralPath $p) | Where-Object { $_ -ne 'Plugin=KenshiMP.Core' }; Set-Content -LiteralPath $p -Value $lines -Encoding ASCII }"
    echo  [OK] Removed Plugin=KenshiMP.Core from Plugins_x64.cfg
)

:: ── Always strip the mod entry from __mods.list ──
if exist "%KENSHI_DIR%\data\__mods.list" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = Join-Path '%KENSHI_DIR%' 'data\__mods.list'; if (Test-Path $p) { $lines = @(Get-Content -LiteralPath $p) | Where-Object { $_ -ne 'kenshi-online' }; Set-Content -LiteralPath $p -Value $lines -Encoding ASCII }"
    echo  [OK] Removed kenshi-online from __mods.list
)

:: Remove DLL
if exist "%KENSHI_DIR%\KenshiMP.Core.dll" (
    del /F "%KENSHI_DIR%\KenshiMP.Core.dll"
    echo  [OK] Removed KenshiMP.Core.dll
)

:: Remove multiplayer panel layout
if exist "%KENSHI_DIR%\data\gui\layout\Kenshi_MultiplayerPanel.layout" (
    del /F "%KENSHI_DIR%\data\gui\layout\Kenshi_MultiplayerPanel.layout"
    echo  [OK] Removed Kenshi_MultiplayerPanel.layout
)

if exist "%KENSHI_DIR%\data\gui\layout\Kenshi_MultiplayerHUD.layout" (
    del /F "%KENSHI_DIR%\data\gui\layout\Kenshi_MultiplayerHUD.layout"
    echo  [OK] Removed Kenshi_MultiplayerHUD.layout
)

:: Remove server
if exist "%KENSHI_DIR%\KenshiMP.Server.exe" (
    del /F "%KENSHI_DIR%\KenshiMP.Server.exe"
    echo  [OK] Removed KenshiMP.Server.exe
)

:: Remove multiplayer mod
if exist "%KENSHI_DIR%\data\kenshi-online.mod" (
    del /F "%KENSHI_DIR%\data\kenshi-online.mod"
    echo  [OK] Removed data\kenshi-online.mod
)
if exist "%KENSHI_DIR%\mods\kenshi-online" (
    rmdir /S /Q "%KENSHI_DIR%\mods\kenshi-online"
    echo  [OK] Removed mods\kenshi-online\
)

:: Restore backups (in addition to the stripping above, this restores any
:: other modifications the installer might have made and gives the user a
:: byte-identical copy of their original config).
if exist "%BACKUP_DIR%\Plugins_x64.cfg.bak" (
    copy /Y "%BACKUP_DIR%\Plugins_x64.cfg.bak" "%KENSHI_DIR%\Plugins_x64.cfg" >nul
    echo  [OK] Restored original Plugins_x64.cfg
)

if exist "%BACKUP_DIR%\Kenshi_MainMenu.layout.bak" (
    copy /Y "%BACKUP_DIR%\Kenshi_MainMenu.layout.bak" "%KENSHI_DIR%\data\gui\layout\Kenshi_MainMenu.layout" >nul
    echo  [OK] Restored original Kenshi_MainMenu.layout
) else (
    :: No backup — strip the MultiplayerButton from the layout so the game
    :: doesn't render a dead button after uninstall.
    if exist "%KENSHI_DIR%\data\gui\layout\Kenshi_MainMenu.layout" (
        powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = Join-Path '%KENSHI_DIR%' 'data\gui\layout\Kenshi_MainMenu.layout'; if (Test-Path $p) { $c = Get-Content -LiteralPath $p -Raw; $c = [System.Text.RegularExpressions.Regex]::Replace($c, '(?s)\s*<Widget[^>]*name=""MultiplayerButton""[^>]*>.*?</Widget>', ''); Set-Content -LiteralPath $p -Value $c -NoNewline -Encoding UTF8 }"
        echo  [OK] Stripped MULTIPLAYER button from Kenshi_MainMenu.layout
    )
)

if exist "%BACKUP_DIR%\__mods.list.bak" (
    copy /Y "%BACKUP_DIR%\__mods.list.bak" "%KENSHI_DIR%\data\__mods.list" >nul
    echo  [OK] Restored original __mods.list
)

:: Clean up backup dir
if exist "%BACKUP_DIR%" (
    rmdir /S /Q "%BACKUP_DIR%" 2>nul
    echo  [OK] Removed backup folder
)

:: Remove config
set "CONFIG_DIR=%APPDATA%\KenshiMP"
if exist "%CONFIG_DIR%" (
    echo.
    set /p "DELCONFIG=Delete KenshiMP config (%CONFIG_DIR%)? [y/N]: "
    if /i "!DELCONFIG!"=="y" (
        rmdir /S /Q "%CONFIG_DIR%"
        echo  [OK] Removed config folder
    )
)

echo.
echo  ============================================
echo   KenshiMP has been uninstalled.
echo   Your game is back to vanilla.
echo  ============================================
echo.
pause
