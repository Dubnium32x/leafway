@echo off
setlocal

where dub >nul 2>nul
if errorlevel 1 (
    echo DUB is not installed or not on PATH.
    exit /b 1
)

if not exist raylib.dll (
    echo raylib.dll is missing from the project root.
    exit /b 1
)

echo Building Leafway for Windows...
dub build --build=release
if errorlevel 1 exit /b 1

if not exist dist\windows mkdir dist\windows
copy /Y leafway.exe dist\windows\leafway.exe >nul
copy /Y raylib.dll dist\windows\raylib.dll >nul
xcopy resources dist\windows\resources /E /I /Y >nul

echo Windows build staged in dist\windows
