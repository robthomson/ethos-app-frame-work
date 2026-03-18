# RFSuite Simulator Sensor Tool

This folder contains the Python GUI script and optional build tools for updating simulated sensor values used in framework-based RFSuite testing.

---

## ✅ Requirements

- Python 3.7+
- `pip`
- Internet access (only for first-time `pyinstaller` install)

---

## 📁 File Layout

```text
bin/sensors/
  sensors.xml      # Sensor definitions used by the GUI
  sensors.exe      # Optional prebuilt Windows binary
  src/
    sensors.py     # Main GUI script
    sensors.ico    # Windows icon used for the built binary
    make.cmd       # Optional Windows build helper for sensors.exe
    readme.md      # This file
```

---

## 📂 Paths

The current framework keeps simulator sensor source files in:

```text
src/rfsuite/sim/sensors
```

Deploy mirrors that tree into each simulator target at:

```text
simulator/<target>/scripts/rfsuite/sim/sensors
```

This tool writes values into the deployed simulator folders, not back into `src/`.

---

## 🛠️ Build Instructions

Run the batch file to compile the GUI:
```bat
make.cmd
```
This will:
- Compile `sensors.py` to `sensors.exe`
- Output the `.exe` to `..\sensors.exe`
- Clean up all build artifacts

A prebuilt `bin/sensors/sensors.exe` can also be committed for convenience,
but `make.cmd` remains the canonical way to refresh it.

---

## 🖥️ Running the GUI

Double-click `sensors.exe` after building,
or from the CLI:
```bat
python src\sensors.py
```

If you prefer the bundled binary:
```bat
bin\sensors\sensors.exe
```

---

## 🔊 Features
- List all available sensors (except `rssi`)
- Set fixed values or random ranges for each
- Live inline status update + 5 second timeout
- Audio beep on successful update

---

## 📄 License
This project is part of the RFSuite framework migration. For licensing details, refer to the upstream repository.
