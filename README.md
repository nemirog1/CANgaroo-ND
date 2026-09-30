
# <img src="src/assets/cangaroo.png" width="48" height="48"> CANgaroo
**Open-source CAN bus analyzer for Linux 🐧 / Windows 🪟**

> ### ℹ️ About this fork — CANgaroo-ND
> **CANgaroo-ND** is ND Performance's fork of [Schildkroet/CANgaroo](https://github.com/Schildkroet/CANgaroo),
> maintained for use with the **ND_UGW** multi-bus CAN/LIN gateway (a multi-channel gs_usb / candleLight device).
> It tracks upstream and carries a small number of changes, listed in [ND fork changes](#-nd-fork-changes) below.
> Base: upstream commit `d04e441` (2026-09-20). Everything else in this README is upstream's documentation.

**🔩 Supported Interfaces & Hardware:**

| Interface | Linux | Windows | Notes |
| :--- | :---: | :---: | :--- |
| **SocketCAN** | ✅ | — | Any kernel CAN interface (`can0`, `vcan0`, …) |
| **PEAK PCAN** | ✅ | ✅ | PCAN-USB, PCAN-USB Pro, PCAN-PCIe, … via PCAN-Basic SDK (`CONFIG+=peakcan`) |
| **Kvaser** | ✅ | ✅ | USB/CAN Leaf and other Kvaser devices via CANlib SDK (`CONFIG+=kvaser`) |
| **Vector** | — | ✅ | VN-series and other Vector devices via Qt serialbus (XL Driver Library required at runtime), CAN FD supported |
| **TinyCAN** | ✅ | ✅ | TinyCAN USB adapters via Qt serialbus (enable in Measurement > Driver menu) |
| **Candlelight / CANable / CANnectivity** | ✅ | ✅ | CANable (Candlelight firmware), MKS CANable, cantact, CANnectivity, and other gs_usb devices. Multi-channel devices supported. CAN FD supported. |
| **SLCAN** | ✅ | ✅ | CANable (SLCAN firmware), Arduino CAN shields |
| **CANblaster** | ✅ | ✅ | UDP-based remote CAN via [CANblaster](https://github.com/OpenAutoDiagLabs/CANblaster) |
| **GrIP** | ✅ | ✅ | GrIP protocol |
| **lin_usb (LindeAPI)** | ✅ | ✅ | USB LIN adapter (VID `0x1d50` / PID `0x606f`). Multi-channel. Master, slave, and monitor modes. Hardware LIN scheduling via LDF. |
| **aio_usb (aiode)** | ✅ | ✅ | Digital I/O and analog inputs on the same USB adapter (VID `0x1d50` / PID `0x606f`), controlled from the GPIO Control window |
| **zscanfd** | ✅ | ✅ | Zilogic _USB to CAN Adapter_ and _USB to CAN FD Adapter_ via zscanfd driver (CONFIG+=zscanfd) in windows (zscanfd.dll required at runtime) and Linux support via SocketCAN |

## ⚙️ Features

*   **Real-time CAN/CAN-FD/LIN Decoding**: Support for standard CAN, high-speed CAN-FD, and LIN bus frames.
*   **Wide Hardware Compatibility**: Works with **SocketCAN** (Linux), **PEAK PCAN**, **Kvaser**, **Vector**, **TinyCAN**, **CANable**, **Candlelight**, **SLCAN**, **CANblaster** (UDP), **GrIP**, **lin_usb** (LIN) and **Zilogic USB to CAN FD Adaptor**.
*   **DBC & LDF Database Support**: Load multiple `.dbc` files for CAN signal decoding and `.ldf` files for LIN bus signal decoding.
*   **Powerful Data Visualization**: Integrated Graphing tools supporting Time-series, Scatter charts, Text-based monitoring, and interactive Gauge views with zoom and live tooltips. Supports both CAN and LIN signals.
*   **Advanced Filtering & Logging**: Isolate critical data with live filters and export captures for offline analysis.
*   **Network Rights Management**: Per-network access control for bus interfaces.
*   **Python Scripting**: Built-in script editor with an embedded Python interpreter (via pybind11). Send and receive CAN and LIN messages, decode signals using loaded DBC/LDF files, and automate tasks. Scripts can be started manually or automatically with the measurement. Ready-to-use example scripts are included in the `examples/` directory.
*   **GPIO Control**: Configure digital lines as inputs or outputs, switch outputs and watch input levels and analog values live on aio_usb and GrIP devices.
*   **CAN Gateway**: Forward messages between two CAN interfaces with configurable per-message filter rules. Active during a running measurement.
*   **LIN Control**: Send LIN Sleep/Wakeup commands, switch schedule tables, and issue LIN diagnostic requests and responses (slave node) on LIN-capable interfaces directly from the UI.
*   **Trace Replay**: Replay captured CAN logs (Vector ASC, candump, PCAP, and PCAPng formats) with adjustable speed, per-message RX/TX direction filtering, channel mapping to live interfaces, and optional autoplay with the measurement. Supports classic CAN, CAN-FD, RTR, and error frames.
*   **Multiple Export Formats**: Save traces as Vector ASC, Vector MDF4, Linux candump, PCAP, or PCAPng (Wireshark-compatible).
*   **Modern Workspace**: A clean, dockable userinterface optimized for multi-monitor setups.

<br>![Cangaroo Trace View](docs/view.png)<br>

## Languages

* 🇩🇪 German
* 🇺🇸 English
* 🇪🇸 Spain
* 🇨🇳 Chinese

## 🔧 ND fork changes

Modified by ND Performance, 2026-09-30 (GPL-2.0-or-later, as the original).

### 1. Candlelight / gs_usb driver: no more lag at high frame rates (Windows)

**File:** `src/driver/CandleApiDriver/CandleApiInterface.cpp` — `readMessage()` only.

**Problem.** Each interface's listener thread (`BusListener::run()`) sleeps `QThread::msleep(1)` after every
`readMessage()` call. The Candlelight driver returned exactly **one frame per call**, and on Windows `Sleep(1)`
costs ~1–2 ms, so each Candlelight channel was capped at roughly **500–1000 frames/s**. Frames were not lost —
the driver's reader thread kept filling an unbounded per-channel queue — but on a busy bus (e.g. a 500 kbit/s
automotive bus at ~1000+ frames/s) the queue grew without limit, the display fell further and further behind
real time, and the trace views faded the ever-older rows grey as "stale".
Measured before the fix: a ~1000 frames/s channel was consumed at ~510 frames/s and its lag grew by ~0.5 s every second.

**Fix.** `readMessage()` still blocks (up to the timeout) for the first frame exactly as before, then drains
every further frame already queued for that channel with a zero-timeout read (up to 512 per call) and returns
them together. The per-frame handling (overflow flag, TX-echo matching, error frames, classic/FD data,
timestamps) is unchanged. `BusListener` and its 1 ms sleep are **deliberately untouched**: upstream added that
sleep (commit `1df9254`) to stop drivers that ignore their timeout, such as GrIP, from busy-spinning a CPU core.

**Verified** on an ND_UGW with two buses at ~1530 + ~350 frames/s: both channels delivered in real time,
no backlog, no loss.

> The LindeAPI (lin_usb) driver uses the same one-frame-per-call pattern and would benefit from the same change;
> it is not modified here.

### 2. Standalone Windows package script

**File:** `deploy_cangaroo.sh` (repository root). Builds a release and assembles a self-contained `dist/`
folder (Qt runtime and plugins, MinGW runtime DLLs, embedded Python runtime, example scripts) that runs by
double-clicking `cangaroo.exe` on a PC without MSYS2. See [Windows (MSYS2)](#-windows-msys2--recommended-for-this-fork) below.

### 3. Prebuilt Windows package in `dist/`

The repository includes a ready-to-run 64-bit Windows build in [`dist/`](dist/), produced by `deploy_cangaroo.sh`
from this fork's source. **No build tools needed:** download or clone the repo, copy the whole `dist` folder
anywhere and double-click `dist\cangaroo.exe`. It is refreshed by re-running the script and committing the result,
so it may lag the newest source commit slightly.

### 4. Build documentation

[`docs/BUILD_WINDOWS.md`](docs/BUILD_WINDOWS.md): complete Windows build and packaging guide.

### 5. `.gitignore`

Upstream's rules ignore `*.dll`, `bin/`, `build/` and similar, which would strip the package. A block at the end of
`.gitignore` re-includes everything under `dist/`; it must stay last. A local `error.log` is ignored.

### Known issue (under investigation)

In the **Aggregated** trace view, rows from a slower channel (e.g. 83.3 kbit/s bus, 100 ms messages) can fade
grey and then refresh in a top-to-bottom sweep while a much busier channel is also running. The frames
themselves arrive in real time (the Rolling Log view keeps up, and saved traces are complete and correctly
timed); this is a display-side issue still being isolated.

## 🛠️ Building
### 🐧 Linux

#### Install dependencies

| Distribution | Command |
| :--- | :--- |
| **Ubuntu / Debian** | `sudo apt install build-essential qt6-base-dev qt6-charts-dev qt6-serialport-dev qt6-serialbus-dev qt6-svg-dev qt6-tools-dev qt6-l10n-tools libqt6opengl6-dev libnl-3-dev libnl-route-3-dev libusb-1.0-0-dev python3-dev pybind11-dev pkg-config` |
| **Fedora** | `sudo dnf install gcc-c++ make qt6-qtbase-devel qt6-qtcharts-devel qt6-qtserialport-devel qt6-qtserialbus-devel qt6-qtsvg-devel qt6-qttools-devel libnl3-devel libusb1-devel python3-devel pybind11-devel pkgconfig` |
| **Arch Linux** | `sudo pacman -S base-devel qt6-base qt6-charts qt6-serialport qt6-serialbus qt6-svg qt6-tools libnl libusb python pybind11 pkgconf` |

#### Build:

```bash
qmake6
make -j$(nproc)
```
The binary will be in `bin/cangaroo`.

#### SocketCAN privileges

CANgaroo uses `ip link` to configure SocketCAN interfaces (bitrate, sample point, CAN FD), which requires `CAP_NET_ADMIN`. The recommended way is a targeted sudoers rule so no password prompt appears:

```bash
sudo groupadd cangaroo
sudo usermod -aG cangaroo $USER
```

Create `/etc/sudoers.d/cangaroo`:
```
%cangaroo ALL=(ALL) NOPASSWD: /sbin/ip link set * down, /sbin/ip link set * up type can *
```

Log out and back in for the group membership to take effect. If you prefer not to use a group, you can instead grant `CAP_NET_ADMIN` directly to the `ip` binary (applies to all users):
```bash
sudo setcap cap_net_admin+ep /sbin/ip
```

> **Note:** If the interface is set to *"Configured by OS"* in the setup dialog, CANgaroo will not touch the interface configuration and no elevated privileges are needed.

#### USB device permissions (udev rules)

Devices accessed directly via libusb (gs_usb / Candlelight, lin_usb / LindeAPI, aio_usb) need a udev rule so that regular users can open them without `sudo`.

Create `/etc/udev/rules.d/99-cangaroo.rules`:

```
# gs_usb / Candlelight / CANable (gs_usb firmware)
SUBSYSTEMS=="usb", ATTRS{idVendor}=="1d50", ATTRS{idProduct}=="606b", MODE="0666", GROUP="plugdev", TAG+="uaccess"
SUBSYSTEMS=="usb", ATTRS{idVendor}=="1d50", ATTRS{idProduct}=="606f", MODE="0666", GROUP="plugdev", TAG+="uaccess"
SUBSYSTEMS=="usb", ATTRS{idVendor}=="1209", ATTRS{idProduct}=="ca01", MODE="0666", GROUP="plugdev", TAG+="uaccess"
```

Then reload and re-plug the device:

```bash
sudo udevadm control --reload-rules && sudo udevadm trigger
```

> **Note:** Your user must be in the `plugdev` group (`sudo usermod -aG plugdev $USER`, then log out and back in).

### 🪟 Windows (MSYS2) — recommended for this fork

> 📘 **Full step-by-step guide:** [`docs/BUILD_WINDOWS.md`](docs/BUILD_WINDOWS.md) — from a bare PC (Git, MSYS2, packages) through build, standalone packaging, testing, committing, updating and troubleshooting. The summary below is the short version.

This mirrors the upstream project's own Windows CI build (MinGW + Qt 6 from MSYS2).

**Important:** install MSYS2 to a path **without spaces** — the default `C:\msys64`. Under
`C:\Program Files\msys64` the qmake-generated Makefile breaks (`C:/Program: No such file or directory`, Error 127).
Run every command below in the **MSYS2 MINGW64** shell (Start menu, purple icon) — not `cmd`, PowerShell,
"MSYS2 MSYS" or "UCRT64".

#### 1. Install and update MSYS2

Install from [msys2.org](https://www.msys2.org) into `C:\msys64`, open **MSYS2 MINGW64**, then:
```bash
pacman -Syu        # if it closes the window, reopen MSYS2 MINGW64 and continue:
pacman -Su         # repeat until there is nothing to do
```

#### 2. Install the toolchain, Qt 6 and dependencies
```bash
pacman -S --needed mingw-w64-x86_64-toolchain mingw-w64-x86_64-qt6 mingw-w64-x86_64-qt6-tools \
    mingw-w64-x86_64-make mingw-w64-x86_64-python mingw-w64-x86_64-pybind11 \
    mingw-w64-x86_64-pkgconf mingw-w64-x86_64-ntldd git
```
Check: `cygpath -w /mingw64` must print `C:\msys64\mingw64`, and `which qmake6 mingw32-make gcc python`
must list four paths under `/mingw64/bin/`.

#### 3. Clone
```bash
cd /c/Users/<you>/source/repos
git clone https://github.com/nemirog1/CANgaroo-ND.git
cd CANgaroo-ND
```

#### 4. Build and run (inside MSYS2)
```bash
qmake6 CONFIG+=release
mingw32-make -j$(nproc)
./bin/cangaroo.exe
```
Clean rebuild: `rm -f .qmake.stash Makefile* src/Makefile*`, then the two build commands again.

#### 5. Standalone package (runs outside MSYS2)
```bash
bash deploy_cangaroo.sh
```
Result: `dist\` in the clone. Copy the **whole folder** anywhere and double-click `cangaroo.exe`.
To publish a refreshed package: `git add -A dist` then commit and push (the script deletes and rebuilds `dist\` each run, so removed files are picked up too).
To confirm it is really standalone, make sure `C:\msys64\mingw64\bin` is not on the Windows `PATH` when you launch it.

#### Harmless messages
* `SyntaxError: Expected one or more names after 'import'` (three times, during qmake): `src.pro`'s Python
  one-liner that locates pybind11 gets its quotes mangled; the headers are found in `/mingw64/include` anyway.
* `VectorDriver: failed to enumerate devices: Cannot load library vxlapi64` in the log: the Vector XL driver
  library is not installed. The deploy script removes the Vector plugin from `dist/`; for in-shell runs, move
  `/mingw64/share/qt6/plugins/canbus/qtvectorcanbus.dll` elsewhere to silence it.

#### Notes
* Qt Creator is no longer packaged by MSYS2 for MINGW64. If you want the IDE, install the standalone
  [Qt Creator](https://download.qt.io/official_releases/qtcreator/) and point its kit at
  `C:\msys64\mingw64\bin\qmake6.exe`, `gcc.exe`/`g++.exe` and `gdb.exe`.
* Candlelight / gs_usb devices appear as `candle<N>_ch<M>` (e.g. an ND_UGW shows `candle0_ch0` … `candle0_ch6`).
  Only one program can have a gs_usb device open at a time.

### 🪟 Windows (Qt online installer — upstream instructions)

* Install [Qt 6](https://www.qt.io/download-qt-installer) (Community / Open Source) including the **Qt Serial Bus** component.
* Install [Python 3](https://www.python.org/downloads/) and [pybind11](https://github.com/pybind/pybind11) (`pip install pybind11`).
* Open `cangaroo.pro` in Qt Creator and build.

#### Deployment

Include the required Qt6 libraries or run `windeployqt` on the `.exe`:
```
windeployqt --release cangaroo.exe
```

### Optional hardware drivers

**PEAK PCAN** (`CONFIG+=peakcan`) — Windows only:
  1. Download [PCAN-Basic SDK](https://www.peak-system.com/fileadmin/media/files/PCAN-Basic.zip) and extract to `src/driver/PeakCanDriver/pcan-basic-api/`.
  2. Build with `qmake CONFIG+=peakcan` (or add `peakcan` to the Qt Creator qmake arguments).
  3. Place `PCANBasic.dll` (from `pcan-basic-api/x64/`) next to the built `.exe`.

**Kvaser** (`CONFIG+=kvaser`) — Linux and Windows:

  *Linux:*
  1. Download and build [linuxcan](https://www.kvaser.com/downloads-kvaser/) (V5.51.461 or newer):
     ```bash
     tar -xf linuxcan.tar.gz
     make -C linuxcan/canlib
     sudo make -C linuxcan/canlib install
     sudo ldconfig
     ```
  2. Build with `qmake6 CONFIG+=kvaser`.

  *Windows:*
  1. Install the [Kvaser CANlib SDK](https://www.kvaser.com/downloads-kvaser/) (V5.51.461 or newer).
  2. Build with `qmake CONFIG+=kvaser CANLIB_DIR="C:/path/to/Kvaser/Canlib"`.
  3. Place `canlib32.dll` (from `Canlib/Bin/`) next to the built `.exe`.

**Vector** (always enabled) — Windows only:
  * Install the [Vector XL Driver Library](https://www.vector.com/int/en/products/products-a-z/libraries-drivers/xl-driver-library/) on the target machine.
  * No build-time SDK needed — Qt's `serialbus` module handles the integration.

**TinyCAN** (toggle in Measurement > Driver menu) — Linux and Windows:
  * Install the [TinyCAN](https://www.mhs-elektronik.de/) driver/library on the target machine.
  * No build-time SDK needed — Qt's `serialbus` module handles the integration.
  * Enable the driver via **Measurement > Driver > TinyCAN** and restart the application.

**Zilogic USB to CAN FD Adaptor** (`CONFIG+=zscanfd`) — Windows:
  1. Download the [zscanfd.dll device driver](The download link has been added to the `src.pro` file) on the target machine.
  2. Download the [qtzscanfdbus.dll Qt plugin](The download link has been added to the `src.pro` file) on the target machine.
  3. Build with `qmake CONFIG+=zscanfd` (or add `zscanfd` to the Qt Creator qmake arguments).
  4. Place the `qtzscanfdbus.dll` from `plugin/canbus`
  5. Place the `zscanfd.dll` from `bin/cangaroo`

## Reference adapter firmware

[`firmware/STM32G4_TinyUSB_CanLinAio/`](firmware/STM32G4_TinyUSB_CanLinAio/README.md)
is a bare STM32CubeIDE project (STM32G473, TinyUSB) for building your own
adapter. It implements the device side of all three USB interfaces CANgaroo
talks to: **gs_usb** (CAN / CAN FD), **lin_usb** (LIN) and **aio_usb** (I/O +
analog). It contains only the USB transport. Plug your CAN, LIN and GPIO code
into its weak `gs_engine_*`, `lin_engine_*` and `aio_hw_*` hooks. `SampleApp/`
inside it is a standalone libusb host program that exercises every request.
The wire protocol is documented in [`docs/usb_interfaces.md`](docs/usb_interfaces.md).

## ARXML to DBC Conversion

Cangaroo natively supports DBC. If you have ARXML files, you can convert them using `canconvert`:
```bash
# Install canconvert
pip install canconvert

# Convert ARXML to DBC
canconvert TCU.arxml TCU.dbc
```

## 📥 Download

Upstream releases: [Schildkroet/CANgaroo](https://github.com/Schildkroet/CANgaroo). This fork (CANgaroo-ND) ships a prebuilt Windows package in [`dist/`](dist/) — copy the folder and run `cangaroo.exe`; to build it yourself see [Windows (MSYS2)](#-windows-msys2--recommended-for-this-fork).

## 📜 Credits

Written by Hubert Denkmair <hubert@denkmair.de>

Further development by:
* Ethan Zonca <e@ethanzonca.com>
* WeAct Studio
* Schildkroet (https://github.com/Schildkroet/CANgaroo)
* Wikilift (https://github.com/wikilift/CANgaroo)
* Jayachandran Dharuman (https://github.com/OpenAutoDiagLabs/cangaroo)
* ND Performance — CANgaroo-ND fork (https://github.com/nemirog1/CANgaroo-ND)

## DISCLAIMER

This software is provided "as is", without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and non-infringement. In no event shall the authors, maintainers, contributors, or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
Use of this software is entirely at your own risk. The authors and maintainers accept no responsibility for any harm, data loss, system damage, legal issues, or any other consequences resulting from the use, misuse, or inability to use this software. It is your sole responsibility to ensure that this software is suitable for your intended use case and complies with all applicable laws and regulations in your jurisdiction.
This project is not affiliated with, endorsed by, or in any way officially connected to any third-party organizations, products, or services that may be referenced within it.
