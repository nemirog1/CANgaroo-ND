# Building CANgaroo-ND on Windows — complete guide

From a bare Windows PC to a standalone `cangaroo.exe` you can copy anywhere and double-click.

| | |
|---|---|
| **Applies to** | CANgaroo-ND (ND Performance fork of [Schildkroet/CANgaroo](https://github.com/Schildkroet/CANgaroo)), branch `master`. Also works for upstream CANgaroo, minus the fork-specific files. |
| **Result** | `dist\` folder: `cangaroo.exe` + Qt 6 runtime + MinGW runtime + embedded Python — runs without MSYS2 |
| **Toolchain** | MSYS2 → MINGW64 environment → GCC (MinGW-w64), Qt 6, qmake, Python 3 + pybind11 |
| **Time** | 30–60 min the first time (mostly downloads, several GB); ~5 min for later rebuilds |
| **Last verified** | 2026-09-30 (Qt 6 from MSYS2, Python 3.14, upstream base `d04e441`). Package versions move on; the steps do not. |

This is the same toolchain the upstream project uses for its own Windows CI build
(`.github/workflows/cmake.yml`, job `build-windows`), so it is the best-trodden path.

---

## Contents

1. [What you install and why](#1-what-you-install-and-why)
2. [Install Git for Windows (for GitHub access)](#2-install-git-for-windows-for-github-access)
3. [Install MSYS2](#3-install-msys2)
4. [Update MSYS2](#4-update-msys2)
5. [Install the build packages](#5-install-the-build-packages)
6. [Verify the environment](#6-verify-the-environment)
7. [Get the source](#7-get-the-source)
8. [Build](#8-build)
9. [Run inside MSYS2](#9-run-inside-msys2)
10. [Make the standalone .exe package](#10-make-the-standalone-exe-package)
11. [Test that the package really is standalone](#11-test-that-the-package-really-is-standalone)
12. [Commit and push](#12-commit-and-push)
13. [Keeping up to date](#13-keeping-up-to-date)
14. [Troubleshooting](#14-troubleshooting)
15. [Optional: Qt Creator IDE](#15-optional-qt-creator-ide)
16. [Reference: what is special in this fork](#16-reference-what-is-special-in-this-fork)

---

## 1. What you install and why

| Tool | Purpose |
|---|---|
| **Git for Windows** (Git Bash) | Cloning/pushing the **private** GitHub repo. It includes Git Credential Manager, which handles GitHub sign-in with a browser pop-up. |
| **MSYS2** | A package manager plus a Unix-like shell for Windows. Supplies the compiler, Qt 6 and every library, all version-matched. |
| MINGW64 environment (inside MSYS2) | The 64-bit MinGW-w64 GCC world the upstream CI uses. All packages below are the `mingw-w64-x86_64-*` variants. |
| Qt 6 (from MSYS2) | GUI framework, plus Serial Bus / Serial Port / Charts / SVG modules. |
| Python 3 + pybind11 (from MSYS2) | CANgaroo embeds a Python interpreter for its scripting window; both are required to compile. |
| ntldd | Lists DLL dependencies; used by the deploy script to gather runtime DLLs. |

**Folder convention used in this guide.** Commands assume the source lives in **`C:\dev\CANgaroo-ND`**
(written `/c/dev/CANgaroo-ND` inside the MSYS2 and Git Bash shells). Any folder works as long as its full path has
**no spaces** — substitute your own path wherever `/c/dev` appears. To create the suggested one:
`mkdir -p /c/dev` (in either shell).

**Two shells, two jobs:**

- **Git Bash** → anything that talks to GitHub (clone, pull, push).
- **MSYS2 MINGW64** → everything that builds (qmake, make, deploy script).

(The MSYS2 `git` package is installed too and works for local operations, but it has no credential manager, so pushing to or cloning a private repo from it is awkward.)

---

## 2. Install Git for Windows (for GitHub access)

Skip if Git Bash is already installed.

1. Download from **https://git-scm.com/download/win** (64-bit installer).
2. Install with the defaults. Keep **Git Credential Manager** enabled (default).
3. Open **Git Bash** and set your identity once (skip if already set, e.g. by GitHub Desktop). Use your own name and the e-mail address of your GitHub account:
   ```bash
   git config --global user.name  "Your Name"
   git config --global user.email "you@example.com"
   ```

---

## 3. Install MSYS2

1. Download the installer from **https://www.msys2.org** — the `msys2-x86_64-YYYYMMDD.exe` link near the top.
2. Run it. On the install-folder page leave it at **`C:\msys64`**.

   > ⚠️ **The path must not contain spaces.** Do **not** install under `C:\Program Files\`.
   > With a space in the path, qmake writes an unquoted tool path into the Makefile and the build fails with
   > `/usr/bin/sh: line 1: C:/Program: No such file or directory` … `Error 127`. The only real fix is reinstalling to `C:\msys64`.

3. Finish. If it opens an MSYS2 window, close it.

---

## 4. Update MSYS2

Open **Start → MSYS2 MINGW64** (icon with a purple background; the prompt shows `MINGW64` in purple).

> Use exactly **MSYS2 MINGW64** for everything from here on — not "MSYS2 MSYS", "MSYS2 UCRT64", "MSYS2 CLANG64",
> `cmd` or PowerShell. Each environment has its own separate set of packages.

```bash
pacman -Syu
```
Answer `Y`. If it says the terminal must be closed, let it, reopen **MSYS2 MINGW64**, and continue with:
```bash
pacman -Su
```
Repeat `pacman -Su` until it reports `there is nothing to do`.

---

## 5. Install the build packages

Still in **MSYS2 MINGW64**:

```bash
pacman -S --needed \
    mingw-w64-x86_64-toolchain \
    mingw-w64-x86_64-qt6 \
    mingw-w64-x86_64-qt6-tools \
    mingw-w64-x86_64-make \
    mingw-w64-x86_64-python \
    mingw-w64-x86_64-pybind11 \
    mingw-w64-x86_64-pkgconf \
    mingw-w64-x86_64-ntldd \
    git
```

- When asked which members of the toolchain group to install, press **Enter** (= all).
- Answer `Y` to proceed. This is the big download (several GB).

What each is for:

| Package | Why |
|---|---|
| `mingw-w64-x86_64-toolchain` | GCC, G++, binutils, gdb, and the MinGW runtime |
| `mingw-w64-x86_64-qt6` | All Qt 6 modules (Core, Gui, Widgets, SerialBus, SerialPort, Charts, Svg, …) and `qmake6` |
| `mingw-w64-x86_64-qt6-tools` | `windeployqt6` (Qt runtime packager), lrelease, etc. |
| `mingw-w64-x86_64-make` | `mingw32-make` |
| `mingw-w64-x86_64-python` | Python 3 headers + `libpython3.x.dll` for the embedded interpreter |
| `mingw-w64-x86_64-pybind11` | C++ ↔ Python binding headers |
| `mingw-w64-x86_64-pkgconf` | `pkg-config`, used by `src/src.pro` to find `python3-embed` |
| `mingw-w64-x86_64-ntldd` | Dependency lister used by `deploy_cangaroo.sh` |
| `git` | Local git operations inside the build shell (optional) |

---

## 6. Verify the environment

```bash
cygpath -w /mingw64
which qmake6 mingw32-make gcc python windeployqt6 ntldd
qmake6 -query QT_VERSION
python --version
```

Expected:

- `C:\msys64\mingw64` — **no** "Program Files".
- Six paths, all under `/mingw64/bin/`.
- A Qt version `6.x.y` and a Python version `3.x.y`.

If any line is wrong, fix it before continuing (see [Troubleshooting](#14-troubleshooting)).

---

## 7. Get the source

Clone from **Git Bash**. The CANgaroo-ND repository (`https://github.com/nemirog1/CANgaroo-ND`) is **private**:
you need a GitHub account that has been given access, and Git Credential Manager will open a browser window to
sign in the first time. If you are working from your own fork or copy, use its URL instead.

```bash
mkdir -p /c/dev
cd /c/dev
git clone https://github.com/nemirog1/CANgaroo-ND.git
cd CANgaroo-ND
git remote add upstream https://github.com/Schildkroet/CANgaroo.git
git remote -v
git log -1 --oneline
```

- `origin` = the repository you cloned (push here, if you have write access).
- `upstream` = the original project (pull updates from here).
- The fork already contains the ND changes (patched Candlelight driver, `deploy_cangaroo.sh`, `.gitignore`,
  README). Nothing needs to be copied in by hand.

> Keep the clone in a path **without spaces** as well.

---

## 8. Build

Switch to **MSYS2 MINGW64** for all build steps:

```bash
cd /c/dev/CANgaroo-ND
qmake6 CONFIG+=release
mingw32-make -j$(nproc)
```

- qmake prints three lines like `SyntaxError: Expected one or more names after 'import'`. **Ignore them** — see
  [Troubleshooting](#14-troubleshooting).
- A successful build scrolls many `g++ …` lines for a few minutes and ends without the word `Error`.
- The executable is `bin\cangaroo.exe`.

**Clean rebuild** (after pulling changes, updating MSYS2, or if the build gets confused):
```bash
rm -f .qmake.stash Makefile* src/Makefile*
qmake6 CONFIG+=release
mingw32-make -j$(nproc)
```

---

## 9. Run inside MSYS2

For quick testing, run from the same **MSYS2 MINGW64** window (the Qt DLLs are on that shell's PATH):
```bash
./bin/cangaroo.exe
```
Double-clicking `bin\cangaroo.exe` in Explorer will **not** work — it cannot find the Qt DLLs. For that, make the package in the next step.

---

## 10. Make the standalone .exe package

In **MSYS2 MINGW64**, from the repo root:
```bash
cd /c/dev/CANgaroo-ND
bash deploy_cangaroo.sh
```

The script (in the repo root; commented step by step):

1. Checks it is running in MINGW64 and installs `ntldd` / `qt6-tools` if missing.
2. Does a **clean** release build (`qmake6 CONFIG+=release`, `mingw32-make`).
3. Recreates `dist\` and copies `bin\cangaroo.exe` into it.
4. Runs `windeployqt6 --release --no-system-d3d-compiler --no-translations` → Qt DLLs plus plugin folders
   (`platforms\`, `styles\`, `imageformats\`, `canbus\`, `iconengines\`, `tls\`, `networkinformation\`, `generic\`).
5. Bundles Python: `libpython3.X.dll` and the standard library in `dist\lib\python3.X\` (tests and caches trimmed).
   CANgaroo looks for `<exe folder>\lib\pythonX.Y\os.py` at start-up and uses it automatically, so no Python install is needed on the target PC.
6. Runs `ntldd -R` on **every** `.exe`/`.dll` in `dist\` (including the plugins) and copies each MinGW DLL they need
   from `/mingw64/bin`, repeating until nothing new is found. No hard-coded, version-specific DLL list.
7. Removes `dist\canbus\qtvectorcanbus.dll` (silences the harmless Vector `vxlapi64` error; remove that line from
   the script if you ever install Vector's XL Driver Library).
8. Copies `examples\*.py` into `dist\examples\` and prints any DLLs still reported "not found".

It ends with:
```
Standalone build ready: C:\dev\CANgaroo-ND\dist
```

The `dist\` folder is the deliverable. Copy the **whole folder** (not just the .exe) anywhere — e.g. `C:\Tools\CANgaroo-ND\` or a USB stick — and run `cangaroo.exe`. It is roughly 100–200 MB.

---

## 11. Test that the package really is standalone

1. Check that `C:\msys64\mingw64\bin` is **not** in the Windows PATH:
   *Start → "Edit the system environment variables" → Environment Variables…* → look at both **User** and **System** `Path`.
   If it is there, the test proves nothing, because Windows would find the DLLs through PATH.
2. Close all MSYS2 windows.
3. In Explorer, double-click `dist\cangaroo.exe`.
4. Checks:
   - The window opens with no "…dll was not found" dialog.
   - If you have a gs_usb / Candlelight device, plug it in → *Measurement → Setup* lists `candle0_ch0 …`.
   - The Script window runs a trivial Python line (proves the bundled Python works).

If Windows reports a missing DLL, copy that file from `C:\msys64\mingw64\bin\` into `dist\`, and then work out
which binary needed it (`ntldd -R dist/<file>.dll`) so the script can be improved.

Best final check: copy `dist\` to a different PC with no MSYS2 and run it there.

---

## 12. Commit and push

`dist\` is **committed** to this fork so it carries a ready-to-run build. The end of `.gitignore` re-includes
everything under `dist/` (upstream's rules ignore `*.dll`, `bin/`, `build/`, … and would otherwise strip the
package), and that block must stay last.

In **Git Bash**:
```bash
cd /c/dev/CANgaroo-ND
git status
git add -A dist
git add <any source files you changed>
git status                  # expect dist/... files and your sources; NOT bin/, build/, Makefile, .qmake.stash
git commit -m "Rebuild Windows package"
git push                                     # updates nd-candle-drain
git push origin nd-candle-drain:master       # keep the fork's master in step
```

- `git add -A dist` also records DLLs that disappeared between builds.
- The first push of `dist` is ~100–200 MB and takes a while. No single file exceeds GitHub's 100 MB limit
  (largest is `libicudt*.dll`, ~33 MB).
- Line-ending warnings (`LF will be replaced by CRLF`) are harmless.
- Every rebuild committed adds its binaries to the repo history. If the repo grows too large, switch to attaching a
  zip of `dist\` to a GitHub Release instead.

---

## 13. Keeping up to date

**Update the toolchain** (MSYS2 MINGW64):
```bash
pacman -Syu          # repeat / reopen as in step 4
```
Then do a clean rebuild and re-run `deploy_cangaroo.sh` (Qt/ICU/Python DLL versions may have changed).

**Pull upstream CANgaroo changes** (Git Bash):
```bash
cd /c/dev/CANgaroo-ND
git fetch upstream
git log --oneline HEAD..upstream/master                  # what's new upstream
git diff HEAD...upstream/master -- src/driver/CandleApiDriver/CandleApiInterface.cpp
git merge upstream/master                                # resolve conflicts if any
```
Be careful with `src/driver/CandleApiDriver/CandleApiInterface.cpp`: it carries the ND change to `readMessage()`
(see [section 16](#16-reference-what-is-special-in-this-fork)). If upstream changed that function, merge by hand and keep the "drain all queued frames" loop.

Then rebuild (step 8), repackage (step 10), test (step 11), commit and push (step 12).

---

## 14. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `'qmake6' is not recognized as an internal or external command` | Typed into Windows `cmd`/PowerShell | Use the **MSYS2 MINGW64** shell |
| `/usr/bin/sh: line 1: C:/Program: No such file or directory` … `Error 127` | MSYS2 installed under `C:\Program Files\` | Uninstall and reinstall MSYS2 to `C:\msys64`, reinstall packages (step 5), clean rebuild |
| `SyntaxError: Expected one or more names after 'import'` (3×, during qmake) | `src/src.pro` runs `python3 -c "import pybind11; …"` to find pybind11 and its quotes get mangled | **Harmless** — the headers are in `/mingw64/include` anyway. Only if compiling later fails with `pybind11/pybind11.h: No such file or directory`, edit that `win32:INCLUDEPATH` line in `src/src.pro` |
| `error: target not found: mingw-w64-x86_64-qt-creator` | MSYS2 no longer packages Qt Creator for MINGW64 | Not needed. See [section 15](#15-optional-qt-creator-ide) |
| `error: target not found: …` for other packages | Package database stale | `pacman -Syu`, then retry |
| Log: `VectorDriver: failed to enumerate devices: Cannot load library vxlapi64` | Vector XL Driver Library not installed | **Harmless.** Removed from `dist\` by the script. For in-shell runs: `mv /mingw64/share/qt6/plugins/canbus/qtvectorcanbus.dll ~/` |
| No `candle…` interfaces in *Measurement → Setup*, no `CandleAPI:` lines in the log | Windows cannot see the device (asleep, USB detached, cable) | Wake/replug the device; check Device Manager → *Universal Serial Bus devices* |
| `CandleAPI: discovery open failed for index N` | Another program has the device open | Close other CANgaroo instances, TSMaster, python probe scripts; only one program can open a gs_usb device |
| Double-clicking `bin\cangaroo.exe` fails with missing Qt DLLs | `bin\` is the raw build, not a package | Run from MSYS2 (step 9) or use `dist\` (step 10) |
| `dist\cangaroo.exe` reports a missing DLL | Dependency the script didn't catch | Copy it from `C:\msys64\mingw64\bin\` into `dist\`; report which DLL so the script can be fixed |
| `git push`/`git clone` asks for a password and rejects it | Using MSYS2 git (no credential manager) or an account password | Use **Git Bash**; sign in via the browser pop-up (Git Credential Manager) |
| `git status` shows `bin/`, `build/`, `Makefile` or `.qmake.stash` as new | `.gitignore` edited / re-include block moved | The `dist/` re-include block must be the last lines of `.gitignore`; upstream rules above it must remain |
| Build very slow | Single-threaded make | Use `-j$(nproc)` (or `-j8`) |

---

## 15. Optional: Qt Creator IDE

Not needed to build. If you want to browse or debug the code:

1. Download the standalone offline installer from **https://download.qt.io/official_releases/qtcreator/**
   (newest version folder → Windows x64 `.exe`; no Qt account needed).
2. Install, open *Edit → Preferences → Kits* and set:
   - **Qt Versions:** add `C:\msys64\mingw64\bin\qmake6.exe`
   - **Compilers:** GCC `C:\msys64\mingw64\bin\gcc.exe` / `g++.exe` (usually auto-detected)
   - **Debuggers:** `C:\msys64\mingw64\bin\gdb.exe`
   - **Kits:** a kit combining the three above.
3. *File → Open File or Project →* `cangaroo.pro`, choose that kit, set the build type to **Release**, build.

Do not use the UCRT64 `qt-creator` package from MSYS2: it pulls a second full Qt and mixes environments.

---

## 16. Reference: what is special in this fork

| File | Change |
|---|---|
| `src/driver/CandleApiDriver/CandleApiInterface.cpp` | `readMessage()` drains **all** frames queued for the channel per call (up to 512) instead of one. Fixes the ~500–1000 frames/s per-channel cap on Windows (caused by `BusListener`'s 1 ms sleep after each call) that made busy buses lag and rows turn grey. `BusListener` itself is deliberately unchanged. |
| `deploy_cangaroo.sh` | Builds and assembles the standalone `dist\` package (section 10). |
| `.gitignore` | Final block re-includes `dist/`; ignores a local `error.log`. |
| `dist/` | Committed prebuilt Windows package. |
| `README.md` | "ND fork changes" section, MSYS2 build summary. |
| `docs/BUILD_WINDOWS.md` | This document. |

Note: `deploy_cangaroo.sh` works on any machine — it only uses paths relative to the folder it is run from plus
the standard MSYS2 locations (`/mingw64/...`).

Device names: gs_usb devices appear as `candle<N>_ch<M>` — one entry per channel of a multi-channel device
(for example, a 7-channel ND_UGW shows `candle0_ch0` … `candle0_ch6`).
