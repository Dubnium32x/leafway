Leafway Build Notes

Linux

- Run `dub run` from the project root.
- The project links against the local `libraylib.so*` copies in the repository root.

Windows

- Windows users should run `build-windows.bat` or `build-windows.ps1` from the project root.
- This builds `leafway.exe` and stages a runnable package in `dist/windows`.
- The project links against the checked-in `raylib.lib` in the repository root.
- `raylib.dll` is copied next to the executable by the build scripts.
- The Open Map action uses a native PowerShell file dialog on Windows.

Linux To Windows Cross-Compile

- `dub run --windows` is not a valid DUB command.
- This Linux machine has MinGW GCC, but it does not currently have the Windows-target LDC runtime/Phobos libraries needed to finish linking a `.exe`.
- Native Windows builds are the supported path right now.

Notes

- `raylib-d:install` still runs as a pre-build step through DUB.
- If a Windows user prefers another compiler, `dub build` should also work as long as the compiler can consume `raylib.lib` from the project root.