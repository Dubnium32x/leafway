diskodev
disko_dev
Do Not Disturb

diskodev [RAYL],  — 4/12/26, 2:31 PM
Cuz I haven't tested it on wine yet
diskodev [RAYL],  — Yesterday at 7:14 PM
We should join the hangout thing today. I do have to shower here but I wanna see ya toy with the new map maker update
diskodev [RAYL],  — Yesterday at 7:38 PM
im in the vc
where you at air fops
PresentFox — Yesterday at 7:38 PM
headache
diskodev [RAYL],  — Yesterday at 7:40 PM
aw
i think ill make a map
for fun
diskodev [RAYL],  — Yesterday at 8:28 PM
i shall be in vc, hopefully your headache goes away
diskodev [RAYL],  — Yesterday at 9:52 PM
ok, i got all the updates and quirks outta the way
diskodev [RAYL],  — Yesterday at 10:11 PM
nvm, made more updates
more like optimization changes
it should
be ok now
for reals
diskodev [RAYL],  — 3:17 AM
still awake?
PresentFox — 4:01 AM
cant call rn
diskodev [RAYL],  — 4:01 AM
No ik
PresentFox — 4:01 AM
also does the compiler take a few minutes for u?
diskodev [RAYL],  — 4:01 AM
Not insisting on one this late
Only a few seconds why
PresentFox — 4:01 AM
its taking more than like 5 minutes on my side
diskodev [RAYL],  — 4:01 AM
Damn
Well hopefully we won't need to worry about modifying it for a bit
Only to change the entity and object values
PresentFox — 4:06 AM
is the app 1 single .d file?!
why isnt it split into multiple files?
diskodev [RAYL],  — 4:07 AM
I didn't see a need to do so
PresentFox — 4:08 AM
you should
each module compiled is single threaded
but what im seeing is it can compile multiple files faster than one big file alone 
diskodev [RAYL],  — 4:10 AM
Perhaps
Sorry I didn't think about that
PresentFox — 4:12 AM
all good lol
can u try to split its files at somepoint tho to make the speed faster
diskodev [RAYL],  — 4:12 AM
All that matters is it's compiled
Yeah I can look at do it
PresentFox — 4:13 AM
only reason i mention it is because its still compiling
diskodev [RAYL],  — 4:13 AM
Oh shit
PresentFox — 4:13 AM
:Natani_Pray:
diskodev [RAYL],  — 4:13 AM
It'll be fine
I'm glad you came to me with this
Not sure with why its doing that
Let me know when it finishes
It's so weird because it takes 3 seconds for it to compile
On my end
PresentFox — 4:52 AM
its still not done
diskodev [RAYL],  — 4:53 AM
WTF
Nah it halted
PresentFox — 4:55 AM
probably idk
diskodev [RAYL],  — 4:56 AM
We'll diagnose it when I get home
I decided to go for a drive
PresentFox — 5:04 AM
found the issue
the optimizations that release does is making it build like 10x worse
so i just set it to debug for now
update these files:
{
	"authors": [
		"DiSKOdev"
	],
	"copyright": "Copyright Â© 2026, DiSKOdev",
	"dependencies": {

dub.json
1 KB
$ErrorActionPreference = "Stop"

if (-not (Get-Command dub -ErrorAction SilentlyContinue)) {
    throw "DUB is not installed or not on PATH."
}

build-windows.ps1
1 KB
@echo off
setlocal

where dub >nul 2>nul
if errorlevel 1 (
    echo [ERROR] DUB is not installed or not on PATH.

build-windows.bat
2 KB
diskodev [RAYL],  — 5:08 AM
Ok
PresentFox — 5:14 AM
sent the wrong files
here are the right ones
{
	"authors": [
		"DiSKOdev"
	],
	"copyright": "Copyright Â© 2026, DiSKOdev",
	"dependencies": {
		"raygui-d": "~>4.0.1",
		"raylib-d": "~>5.5.3"
	},
	"libs-linux": ["raylib"],
	"lflags-linux": [
		"-L.",
		"-Wl,-rpath=$$ORIGIN"
	],

	"libs-windows": [
		"raylib",
		"winmm",
		"gdi32",
		"opengl32",
		"user32",
		"shell32",
		"advapi32"
	],
	"lflags-windows": [
		"/LIBPATH:."
	],
	
	"description": "A 3D Map Editor for Playdate Games",
	"license": "GPL-3.0",
	"name": "leafway"
}

dub.json
1 KB
@echo off
setlocal

where dub >nul 2>nul
if errorlevel 1 (
    echo [ERROR] DUB is not installed or not on PATH.

build-windows.bat
2 KB
$ErrorActionPreference = "Stop"

if (-not (Get-Command dub -ErrorAction SilentlyContinue)) {
    throw "DUB is not installed or not on PATH."
}

build-windows.ps1
1 KB
﻿
PresentFox
presentfox
Air/Force
 
 
 
 
 
 
Info about me: https://presentfox.furrcard.com/

ENFJ 7w6
C
typedef struct{
  float x, y, z;
  int YouABitch;
} someData;

void createLabubu() {}
void minecraft() {}
void die() {}
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