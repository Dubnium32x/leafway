@echo off
setlocal

where dub >nul 2>nul
if errorlevel 1 (
    echo [ERROR] DUB is not installed or not on PATH.
    pause
    exit /b 1
)

if not exist raylib.dll (
    echo [ERROR] raylib.dll is missing from the project root.
    pause
    exit /b 1
)

echo Building Leafway for Windows...
dub build --build=debug --parallel --verbose
if errorlevel 1 (
    echo [ERROR] Build failed. See output above for details.
    pause
    exit /b 1
)

if not exist dist\windows (
    mkdir dist\windows
    if errorlevel 1 (
        echo [ERROR] Failed to create dist\windows directory.
        pause
        exit /b 1
    )
)

copy /Y leafway.exe dist\windows\leafway.exe >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy leafway.exe.
    pause
    exit /b 1
)

copy /Y raylib.dll dist\windows\raylib.dll >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy raylib.dll.
    pause
    exit /b 1
)

xcopy resources dist\windows\resources /E /I /Y >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy resources folder.
    pause
    exit /b 1
)

echo Windows build staged in dist\windows
pause