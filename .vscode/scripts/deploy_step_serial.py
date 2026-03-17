#!/usr/bin/env python3
"""
Deployment Step: Serial
Monitors serial output from radio for debugging
Captures log output from Ethos radio console

Requires: pyserial (install: pip install pyserial)
"""

import os
import sys
import time


def main(out_dir: str, config: dict, args) -> int:
    """Monitor serial output from radio"""
    print("[SERIAL] Attempting to open serial connection…")
    
    try:
        import serial
    except ImportError:
        print("[SERIAL] pyserial not installed")
        print("[SERIAL] Install with: pip install pyserial")
        print("[SERIAL] Skipping serial monitoring")
        return 0
    
    baud_rate = config.get('baud_rate', 460800) if isinstance(config, dict) else 460800
    timeout = config.get('serial_timeout', 5) if isinstance(config, dict) else 5
    
    # Find serial port
    port = None
    
    if sys.platform.startswith('win'):
        # Windows
        import winreg
        try:
            reg = winreg.ConnectRegistry(None, winreg.HKEY_LOCAL_MACHINE)
            key = winreg.OpenKey(reg, r'HARDWARE\DEVICEMAP\SERIALCOMM')
            for i in range(winreg.QueryInfoKey(key)[1]):
                try:
                    name, value = winreg.EnumValue(key, i)
                    port = value
                    break
                except:
                    pass
        except:
            pass
    else:
        # Linux/macOS
        import glob
        ports = glob.glob('/dev/ttyUSB*') + glob.glob('/dev/ttyACM*') + glob.glob('/dev/cu.usbserial*')
        if ports:
            port = ports[0]
    
    if not port:
        print("[SERIAL] No serial port found")
        return 0
    
    print(f"[SERIAL] Opening port: {port} @ {baud_rate} baud")
    
    try:
        ser = serial.Serial(port, baud_rate, timeout=1)
        time.sleep(0.5)
        
        print("[SERIAL] Connected! Monitoring output (Ctrl+C to exit)…")
        print("=" * 60)
        
        start_time = time.time()
        while time.time() - start_time < timeout:
            try:
                if ser.in_waiting:
                    line = ser.readline().decode('utf-8', errors='ignore').strip()
                    if line:
                        print(line)
            except KeyboardInterrupt:
                break
            except:
                pass
        
        print("=" * 60)
        ser.close()
        return 0
    
    except Exception as e:
        print(f"[SERIAL] Error: {e}")
        return 1


if __name__ == '__main__':
    import sys
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else '.', {}, None))
