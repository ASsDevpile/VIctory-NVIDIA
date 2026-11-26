@echo off
setlocal enabledelayedexpansion
title XENITH VI for an RTX card
cd /d "%~dp0"

rem A copy of the XENITH VI launcher (ASsDevpile/XenithVI, GPL-3.0-or-later),
rem changed for this fork: the modes call scripts\play-nvidia.ps1, which sets
rem this fork's speed settings, and the settings this fork adds on an RTX
rem card (render scale, the card named, quality, the pipeline skip list) live
rem beside Xenith's own in xenith.ini. An empty setting means the script's
rem default.

set "GAME="
set "RESOLUTION="
set "ADAPTER="
set "QUALITY=on"
set "RAYTRACING=off"
set "BUILD=diag"
set "SKIP="
set "CONSOLE=S"
set "UPSCALER="
set "PRELOAD=off"
set "CACHE_DIR="
set "SAVES_DIR="
set "NVIDIA_CARD="
set "EXTRA_ADVICE="
if exist "xenith.ini" for /f "usebackq tokens=1,* delims==" %%a in ("xenith.ini") do set "%%a=%%b"
for /f "delims=" %%c in ('powershell -NoProfile -Command "Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name }" 2^>nul') do call :found_card "%%c"

if not defined GAME (
    echo No title configured yet.
    set /p "GAME=Path to the title's game_*.exe (no quotes): "
    call :save
)

:menu
set "MODE="
set "RUN_PRELOAD="
if not exist "%GAME%" echo Warning: "%GAME%" does not exist.

set "SCRIPT=scripts\play-nvidia.ps1"
if not exist "%SCRIPT%" (
    echo No %SCRIPT% here. Run it from the repository root.
    pause
    exit /b 1
)
echo.
echo XENITH VI - RTX   build %BUILD%
echo title             %GAME%
if defined NVIDIA_CARD (echo card              %NVIDIA_CARD%) else echo card              no NVIDIA card found (the run still picks the fastest)
if defined RESOLUTION echo render height    %RESOLUTION%
if defined ADAPTER echo adapter           %ADAPTER%
echo quality %QUALITY%   ray tracing %RAYTRACING%
echo console %CONSOLE%   upscaler %UPSCALER%   preload %PRELOAD%
echo.
echo   1  Play                          (the fork's settings)
echo   2  Play, release build           (faster)
echo   3  Play without quality patches  (full speed, more glitches)
echo   4  Ray tracing on                (lit indirect light, slower)
echo   5  Pipelines skipped             (%SKIP%)
echo   6  Settings
echo   7  Preload shaders           (translate and warm, once)
echo   0  Exit
echo.
set "CHOICE="
set /p "CHOICE=Choose [1]: "
if not defined CHOICE set "CHOICE=1"
if "%CHOICE%"=="0" exit /b 0
if "%CHOICE%"=="1" set "MODE=play"
if "%CHOICE%"=="2" (set "MODE=play" & set "BUILD=release")
if "%CHOICE%"=="3" (set "MODE=play" & set "QUALITY=off")
if "%CHOICE%"=="4" set "MODE=rt"
if "%CHOICE%"=="5" set "MODE=skip"
if "%CHOICE%"=="6" goto settings
if "%CHOICE%"=="7" (set "MODE=play" & set "RUN_PRELOAD=1")
if not defined MODE (
    echo No such mode: %CHOICE%
    goto menu
)

if "%MODE%"=="skip" (
    echo Pipelines skipped now: %SKIP%
    echo A list of 16-digit shader hashes, comma-separated. scripts\rt_off_hashes.txt
    echo has the ones this fork starts with.
    set "NEW="
    set /p "NEW=New list (empty keeps it): "
    if defined NEW set "SKIP=!NEW!"
    call :save
    goto menu
)

set "ARGS=-Exe "%GAME%" -Build %BUILD%"
if /i "%QUALITY%"=="on" set "ARGS=%ARGS% -Quality"
if "%MODE%"=="rt" set "ARGS=%ARGS% -RayTracing"
if defined RESOLUTION set "ARGS=%ARGS% -Resolution %RESOLUTION%"
if defined ADAPTER set "ARGS=%ARGS% -Adapter "%ADAPTER%""
if /i "%CONSOLE%"=="X" set "ARGS=%ARGS% -Console X"
if /i "%UPSCALER%"=="dlss" set "ARGS=%ARGS% -Upscaler dlss"
if /i "%PRELOAD%"=="on" set "RUN_PRELOAD=1"
if defined CACHE_DIR set "ARGS=%ARGS% -CacheDir "%CACHE_DIR%""
if defined SAVES_DIR set "ARGS=%ARGS% -SavesDir "%SAVES_DIR%""
if defined RUN_PRELOAD set "ARGS=%ARGS% -Preload"
if defined SKIP set "ARGS=%ARGS% -More @{VICTORY_SKIP_PIPELINES='%SKIP%'}"

echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %ARGS%
echo.
pause
goto menu

:settings
echo.
echo Settings (empty values mean the launch script's defaults)
echo.
echo    1  Game path        %GAME%
echo    2  Render height    %RESOLUTION%  (2160, 1440, 1080, 720, 540, 480)
echo    3  Adapter          %ADAPTER%  (empty: the fastest%EXTRA_ADVICE%)
echo    4  Quality          %QUALITY%  (fewer stretched bodies, rainbow skin)
echo    5  Ray tracing      %RAYTRACING%
echo    6  Build            %BUILD%  (diag or release)
echo    7  Skip pipelines   %SKIP%
echo    8  Console          %CONSOLE%  (S is faster, X is the full output)
echo    9  Upscaler         %UPSCALER%  (empty: FSR; dlss: a proxy DLL beside the game)
echo   10  Preload shaders  %PRELOAD%
echo   11  Cache folder     %CACHE_DIR%  (empty: the victory.toml pick)
echo   12  Saves folder     %SAVES_DIR%  (empty: beside the persistent storage)
echo    0  Back
echo.
set "WHICH="
set /p "WHICH=Edit [0]: "
if not defined WHICH set "WHICH=0"
if "%WHICH%"=="0" goto menu
if "%WHICH%"=="1" call :ask GAME "1 Path to the title's game_*.exe"
if "%WHICH%"=="2" call :ask RESOLUTION "2 Render height (2160 1440 1080 720 540 480, empty: half the output)"
if "%WHICH%"=="3" call :ask ADAPTER "3 Adapter (name part like 5070, or index like 1; empty: the fastest%EXTRA_ADVICE%)"
if "%WHICH%"=="4" call :ask QUALITY "4 Quality patches on or off"
if "%WHICH%"=="5" call :ask RAYTRACING "5 Ray tracing on or off"
if "%WHICH%"=="6" call :ask BUILD "6 Build (diag or release)"
if "%WHICH%"=="7" call :ask SKIP "7 Pipelines to skip, comma-separated hashes"
if "%WHICH%"=="8" call :ask CONSOLE "8 Console S or X"
if "%WHICH%"=="9" call :ask UPSCALER "9 Upscaler fsr or dlss"
if "%WHICH%"=="10" call :ask PRELOAD "10 Preload shaders on or off"
if "%WHICH%"=="11" call :ask CACHE_DIR "11 Cache folder (a full path, empty: the default)"
if "%WHICH%"=="12" call :ask SAVES_DIR "12 Saves folder (a full path, empty: the default)"
goto settings

:found_card
if not defined NVIDIA_CARD echo %~1| findstr /i "nvidia geforce rtx gtx" >nul && set "NVIDIA_CARD=%~1" && set "EXTRA_ADVICE=; found: %~1"
exit /b 0

:ask
set "CURRENT="
for %%v in (%1) do set "CURRENT=!%%v!"
echo Current: [!CURRENT!]
set "VALUE="
set /p "VALUE=%~2 (empty keeps the current one): "
if defined VALUE set "%~1=%VALUE%"
goto :eof

:save
(for %%k in (GAME RESOLUTION ADAPTER QUALITY RAYTRACING BUILD SKIP UPSCALER CONSOLE PRELOAD CACHE_DIR SAVES_DIR) do echo %%k=!%%k!)>xenith.ini
goto :eof
