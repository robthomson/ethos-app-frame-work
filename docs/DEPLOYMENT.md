# Getting Started: Deployment Guide

## New Project Structure

The project has been reorganized to match the rfsuite/betaflight pattern:

```
ethos-app-frame-work/
├── src/
│   └── rotorflight/                 ← All source code here
│       ├── main.lua                 ← Entry point
│       ├── framework/               ← Core framework
│       │   ├── core/
│       │   ├── events/
│       │   └── utils/
│       ├── app/                     ← Application
│       └── tasks/                   ← Background tasks
│
├── .vscode/                         ← Deployment tools
│   ├── tasks.json                   ← Build tasks
│   ├── launch.json                  ← Debug configs
│   ├── settings.json                ← VS Code settings
│   ├── deploy.json                  ← Deploy configuration
│   └── scripts/
│       └── deploy.py                ← Deployment script
│
├── Documentation/
└── ... (docs as before)
```

---

## Quick Deploy

### From VS Code

**Option 1: Keyboard Shortcut**
```
Ctrl+Shift+B           # Deploy to Radio (default task)
```

**Option 2: Command Palette**
```
Ctrl+Shift+P
> Tasks: Run Task
> Deploy to Radio
```

**Option 3: Run → Run without Debugging**
```
Ctrl+F5                # Deploy to Radio
```

### From Command Line

```bash
# Deploy to connected radio
python .vscode/scripts/deploy.py --radio

# Deploy to simulator
python .vscode/scripts/deploy.py --sim

# Check radio info
python .vscode/scripts/deploy.py --info
```

### Manual (No Automation)

1. Connect Ethos radio via USB
2. Radio appears as removable drive (e.g., `E:/`)
3. Copy `src/rotorflight/` → `E:/SCRIPTS/rotorflight/`
4. Safely eject and power cycle radio

---

## Deployment Tasks in VS Code

## Available VS Code Tasks

### Core Deployment Tasks

**Deploy to Radio** (Default)
- Direct deployment without extra steps
- Keyboard: `Ctrl+Shift+B`

**Deploy to Simulator**
- Deploys to simulator for testing
- No radio needed

### Deployment with Steps

**Deploy & Test [Radio]**
- Deploys and runs lint + test steps
- Validates code before radio deployment

**Deploy & Lint [Radio]**
- Deploys with syntax checking
- Catches Lua errors early

**Deploy & i18n [Radio]**
- Deploys with internationalization processing
- Processes @i18n(key)@ tags

**Deploy & Test [Simulator]**
- Deploys to simulator with validation
- Useful for testing without radio

### Validation Tasks

**Lint Code**
- Checks Lua syntax without deploying
- Scans all .lua files for errors

**Test Deployment**
- Validates framework structure
- Checks required files and directories

**Process i18n**
- Processes internationalization tags
- Requires i18n/en.json file

### Utility Tasks

**Monitor Serial**
- Captures output from radio serial port
- Requires pyserial (pip install pyserial)

**Radio Info**
- Shows connected radio information
- Displays deployed files

**Dry Run Deploy**
- Shows what would be deployed
- No files copied (verification only)

---

## Setup Instructions

### Prerequisites

- **Python 3.6+** installed
- **VS Code** (optional, but recommended)
- **Ethos Radio** connected via USB (or simulator available)

### Windows Setup

1. **Verify Python**
   ```powershell
   python --version              # Should be 3.6+
   ```

2. **Open VS Code**
   - File → Open Folder
   - Select `ethos-app-frame-work/`

3. **Try Deploy**
   - Connect Ethos radio via USB
   - Press `Ctrl+Shift+B`
   - Watch deployment in terminal

### macOS/Linux Setup

1. **Verify Python**
   ```bash
   python3 --version             # Should be 3.6+
   ```

2. **Make script executable**
   ```bash
   chmod +x .vscode/scripts/deploy.py
   ```

3. **Update settings**
   - Edit `.vscode/settings.json`
   - Update `ethos.root` path for your simulator location

4. **Try Deploy**
   ```bash
   python3 .vscode/scripts/deploy.py --info
   ```

---

## Troubleshooting

### "Radio not found"

**Issue**: Script can't find connected Ethos radio

**Solutions**:
1. Connect radio via USB cable (not just any cable)
2. Ensure radio is powered on
3. Put radio in USB/disk mode:
   - Ethos Settings → USB Mode → USB Drive
4. Check Device Manager (Windows) or `lsblk` (Linux)
5. Try manual copy if auto-detection fails

**Verify**:
```bash
python .vscode/scripts/deploy.py --info
```

### "Permission denied" (macOS/Linux)

**Issue**: Script doesn't have execute permissions

**Solution**:
```bash
chmod +x .vscode/scripts/deploy.py
```

### "Python not found"

**Issue**: `python` command not recognized

**Solutions**:
- Windows: Install Python from python.org, select "Add to PATH"
- macOS: `brew install python3`
- Linux: `sudo apt install python3` (Ubuntu)

**Verify**:
```bash
python --version              # Windows
python3 --version             # macOS/Linux
```

### "Deployment incomplete"

**Check**:
1. Radio has enough free space (need ~500KB minimum)
2. USB connection is stable
3. No radio operations running (close Ethos apps)
4. Try `--info` first to verify radio detects

### Deployment to radio worked but app won't run

1. Verify `/SCRIPTS/rotorflight/main.lua` exists on radio
2. Check Lua syntax:
   ```bash
   python -m py_compile src/rotorflight/main.lua
   ```
3. Check radio console for error messages
4. Try deploying to simulator first to isolate issue

---

## Development Workflow

### Typical Flow

1. **Edit Code**
   - Modify `src/rotorflight/` files
   - Use VS Code for editing with Lua support

2. **Test Locally**
   - Deploy to simulator (if available)
   - Verify logic without radio

3. **Deploy to Hardware**
   - Connect Ethos radio
   - Press `Ctrl+Shift+B` (Deploy to Radio)
   - Radio auto-runs updated code

4. **Debug**
   - Add print statements (console logs)
   - Use `framework:printStats()` to profile
   - Check Ethos console for errors

5. **Iterate**
   - Edit → Deploy → Test → Repeat

---

## Modular Deployment Steps

The deployment system is **modular and extensible**. Deploy steps run in sequence after copying files.

### Built-in Steps

#### Lint Step (`deploy_step_lint.py`)
Validates Lua syntax (parentheses, brackets, braces matching)

```bash
python deploy.py --radio --step lint
```

#### i18n Step (`deploy_step_i18n.py`)
Processes `@i18n(key)@` tags in files using JSON language files

```bash
python deploy.py --radio --step i18n --lang en
```

Requires: `i18n/en.json` file with translations

Example tag in code:
```lua
print("@i18n(messages.welcome)@")
```

#### Test Step (`deploy_step_test.py`)
Validates deployment structure:
- Checks required files exist
- Verifies directory structure
- Counts deployed files

```bash
python deploy.py --radio --step test
```

#### Serial Step (`deploy_step_serial.py`)
Monitors serial output from radio for debugging

```bash
python deploy.py --step serial
```

Requires: `pyserial` → `pip install pyserial`

### Creating Custom Steps

Create new deployment steps as needed:

**File**: `.vscode/scripts/deploy_step_<name>.py`

**Template**:
```python
#!/usr/bin/env python3
"""Deploy Step: <name>"""

def main(out_dir: str, config: dict, args) -> int:
    """
    Execute custom deployment step
    
    Args:
        out_dir: Path to deployed framework
        config: Deployment configuration dict
        args: Command line arguments
    
    Returns:
        0 = success, 1 = failure
    """
    print(f"[<NAME>] Processing…")
    
    # Your step logic here
    
    return 0
```

**Usage**:
```bash
python deploy.py --radio --step <name>
```

### Combining Steps

```bash
# Deploy with multiple validation steps
python deploy.py --radio --step lint --step test --step i18n

# Deploy to simulator with full validation
python deploy.py --sim --step lint --step test
```

---

## Advanced Configuration

### Custom Simulator Path

Edit `.vscode/settings.json`:

```json
{
  "ethos.root": "/path/to/your/simulator"
}
```

### Custom Radio Mount

Edit `.vscode/deploy.json`:

```json
{
  "radio_mount": "E:/",
  "target_dir": "/SCRIPTS/rotorflight"
}
```

### Custom Deployment Configuration

The deploy script looks for:
1. `.vscode/deploy.json` (if exists)
2. Default values if not found

Create `.vscode/deploy.json` to override defaults.

---

## Deployment Commands

### All Deploy Task Options

```bash
# Deploy to radio
python .vscode/scripts/deploy.py --radio

# Deploy to simulator
python .vscode/scripts/deploy.py --sim

# Show radio information
python .vscode/scripts/deploy.py --info

# Dry run (show what would deploy)
python .vscode/scripts/deploy.py --dry-run

# Help
python .vscode/scripts/deploy.py --help
```

---

## Next Steps

1. ✅ Structure reorganized
2. ✅ Deployment tools configured
3. 🔄 Connect radio via USB
4. 🔄 Press `Ctrl+Shift+B` to deploy
5. 🔄 Watch console output
6. 🔄 Verify app runs on radio

**Framework deployed and ready to customize!** 🚀

---

## File Reference

| File | Purpose |
|------|---------|
| `.vscode/tasks.json` | VS Code build tasks |
| `.vscode/launch.json` | Debug launch configs |
| `.vscode/settings.json` | VS Code project settings |
| `.vscode/deploy.json` | Deployment configuration |
| `.vscode/scripts/deploy.py` | Main deployment script |

---

## For Ethos Suite Integration (Optional)

If you want to use Ethos Suite for deployment instead:

1. Install Ethos Suite
2. Update `.vscode/deploy.json`:
   ```json
   {
     "use_ethossuite": true
   }
   ```
3. Update `deploy.py` to use Ethos Suite APIs

(See rfsuite for full example)
