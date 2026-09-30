#!/usr/bin/env bash
# =============================================================================
# deploy_cangaroo.sh — build a STANDALONE CANgaroo folder that runs outside MSYS2
# -----------------------------------------------------------------------------
# Where to put it : the top folder of your CANgaroo clone
#                   (e.g. C:\dev\CANgaroo-ND\deploy_cangaroo.sh — any path without spaces)
# How to run      : in the "MSYS2 MINGW64" shell:
#                       cd /c/dev/CANgaroo-ND        # your clone
#                       bash deploy_cangaroo.sh
# Result          : ./dist/ holds cangaroo.exe plus every DLL, Qt plugin and the
#                   Python runtime it needs. Copy the whole dist folder anywhere
#                   (e.g. C:\Tools\CANgaroo-ND) and double-click cangaroo.exe.
#
# This mirrors the upstream CANgaroo GitHub Actions Windows job
# (.github/workflows/cmake.yml, "build-windows"), minus the Kvaser/PEAK SDKs
# which we do not build. Instead of the CI's hard-coded DLL list (which names
# version-specific files like libicuuc78.dll), it asks ntldd what every
# binary in dist/ actually needs and copies exactly that from /mingw64/bin,
# looping until nothing new turns up.
# =============================================================================
set -euo pipefail

# ---- 0. Sanity: must be the MINGW64 environment -----------------------------
if [[ "${MSYSTEM:-}" != "MINGW64" ]]; then
    echo "ERROR: run this from the 'MSYS2 MINGW64' shell (MSYSTEM=${MSYSTEM:-unset})." >&2
    exit 1
fi

# ---- 1. Tools this script needs (installs only what is missing) --------------
# ntldd lists a DLL/EXE's dependencies; windeployqt6 ships with qt6-tools.
pacman -S --needed --noconfirm mingw-w64-x86_64-ntldd mingw-w64-x86_64-qt6-tools

# ---- 2. Fresh release build ---------------------------------------------------
# Clean first so dist/ never contains a stale exe. Ignore the three harmless
# "SyntaxError ... 'import'" lines qmake prints (pybind11 include lookup).
rm -f .qmake.stash Makefile* src/Makefile*
qmake6 CONFIG+=release
mingw32-make -j"$(nproc)"

# ---- 3. Start dist/ from scratch ---------------------------------------------
rm -rf dist
mkdir -p dist
cp bin/cangaroo.exe dist/

# ---- 4. Qt runtime: Qt6*.dll + platform/style/imageformat/canbus plugins ------
windeployqt6 --release --no-system-d3d-compiler --no-translations dist/cangaroo.exe

# ---- 5. Python runtime (CANgaroo embeds Python for its scripting window) ------
# CANgaroo looks for <exe folder>/lib/pythonX.Y/os.py at start-up and sets
# PYTHONHOME to the exe folder if it finds it (src/core/PythonEngine.cpp,
# findBundledPythonHome), so this layout makes Python work with no install.
PYVER=$(python3 -c "import sysconfig; print(sysconfig.get_config_var('VERSION'))")
cp "/mingw64/bin/libpython${PYVER}.dll" dist/
mkdir -p "dist/lib/python${PYVER}"
cp -r "/mingw64/lib/python${PYVER}/"* "dist/lib/python${PYVER}/" 2>/dev/null || true
# Trim: test suites and bytecode caches are not needed at run time.
find "dist/lib/python${PYVER}" -type d \( -name __pycache__ -o -name test -o -name tests \) \
     -prune -exec rm -rf {} + 2>/dev/null || true

# ---- 6. MinGW runtime DLLs: resolve dependencies of EVERY binary in dist/ -----
# Includes the exe, the Qt DLLs and the plugin DLLs (e.g. platforms/qwindows.dll
# pulls in harfbuzz/freetype/png). Repeat until a pass copies nothing new.
copy_missing_deps() {
    local copied=0 bin dep
    while IFS= read -r -d '' bin; do
        # ntldd line format: "libfoo.dll => C:\msys64\mingw64\bin\libfoo.dll (0x...)"
        while IFS= read -r dep; do
            dep=$(cygpath -u "$dep")
            if [[ -f "$dep" && ! -f "dist/$(basename "$dep")" ]]; then
                cp "$dep" dist/
                echo "  + $(basename "$dep")"
                copied=1
            fi
        done < <(ntldd -R "$bin" 2>/dev/null | grep -i 'mingw64' | awk '{print $3}' | sort -u)
    done < <(find dist -type f \( -iname '*.exe' -o -iname '*.dll' \) \
                  ! -path "dist/lib/python*" -print0)
    return $copied
}
echo "Resolving MinGW runtime DLLs..."
pass=1
until copy_missing_deps; do
    pass=$((pass + 1))
    if (( pass > 6 )); then break; fi   # safety stop; normally 2-3 passes
done

# ---- 7. Optional: drop the Vector plugin to silence the harmless vxlapi64 errors
# Comment this out if you ever install Vector's XL Driver Library.
rm -f dist/canbus/qtvectorcanbus.dll

# ---- 8. Bundle CANgaroo's example Python scripts ------------------------------
mkdir -p dist/examples
cp examples/*.py dist/examples/ 2>/dev/null || true

# ---- 9. Report ---------------------------------------------------------------
echo
echo "Remaining 'not found' dependencies (Windows system DLLs are expected to be absent):"
ntldd dist/cangaroo.exe | grep -i 'not found' || echo "  none"
echo
echo "Standalone build ready: $(cygpath -w "$PWD/dist")"
echo "Copy that whole folder anywhere and run cangaroo.exe."
