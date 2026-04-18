$ErrorActionPreference = "Stop"

if (-not (Get-Command dub -ErrorAction SilentlyContinue)) {
    throw "DUB is not installed or not on PATH."
}

if (-not (Test-Path "raylib.dll")) {
    throw "raylib.dll is missing from the project root."
}

Write-Host "Building Leafway for Windows..."
dub build --build=debug --parallel --verbose

New-Item -ItemType Directory -Force -Path "dist/windows" | Out-Null
Copy-Item "leafway.exe" "dist/windows/leafway.exe" -Force
Copy-Item "raylib.dll" "dist/windows/raylib.dll" -Force
Copy-Item "resources" "dist/windows/resources" -Recurse -Force

Write-Host "Windows build staged in dist/windows"