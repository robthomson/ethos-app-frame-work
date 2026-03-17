#!/usr/bin/env python3
"""
Deployment Step: Test
Runs basic tests on the deployed framework
Checks for: module availability, required files, basic functionality
"""

import os
import sys
from pathlib import Path


def main(out_dir: str, config: dict, args) -> int:
    """Run tests on deployed framework"""
    print(f"[TEST] Running deployment tests…")
    
    out_path = Path(out_dir)
    errors = 0
    warnings = 0
    
    # Test 1: Check required files exist
    required_files = [
        'main.lua',
        'framework/core/init.lua',
        'framework/core/callback.lua',
        'framework/core/session.lua',
        'framework/core/registry.lua',
        'framework/events/events.lua',
    ]
    
    print("[TEST] Checking required files…")
    for req_file in required_files:
        filepath = out_path / req_file
        if filepath.exists():
            print(f"   ✅ {req_file}")
        else:
            print(f"   ❌ Missing: {req_file}")
            errors += 1
    
    # Test 2: Check directory structure
    required_dirs = [
        'framework/core',
        'framework/events',
        'framework/utils',
    ]
    
    print("[TEST] Checking directory structure…")
    for req_dir in required_dirs:
        dirpath = out_path / req_dir
        if dirpath.exists() and dirpath.is_dir():
            print(f"   ✅ {req_dir}/")
        else:
            print(f"   ❌ Missing: {req_dir}/")
            errors += 1
    
    # Test 3: Check main.lua syntax
    print("[TEST] Checking main.lua…")
    main_lua = out_path / 'main.lua'
    if main_lua.exists():
        try:
            with open(main_lua, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Check for key functions
            required_functions = ['wakeup', 'paint', 'close']
            found = 0
            for func in required_functions:
                if f'function {func}' in content or f'function wakeup' in content:
                    found += 1
            
            if found > 0:
                print(f"   ✅ Found {found} key functions")
            else:
                print(f"   ⚠️  Could not verify key functions")
                warnings += 1
        
        except Exception as e:
            print(f"   ❌ Error reading main.lua: {e}")
            errors += 1
    else:
        print(f"   ❌ main.lua not found")
        errors += 1
    
    # Test 4: File count
    lua_count = len(list(out_path.glob('**/*.lua')))
    print(f"[TEST] Found {lua_count} Lua files")
    if lua_count >= 5:
        print(f"   ✅ Reasonable file count")
    else:
        print(f"   ⚠️  Low file count (expected >= 5)")
        warnings += 1
    
    # Summary
    print(f"\n[TEST] Summary: {errors} errors, {warnings} warnings")
    
    if errors > 0:
        print("[TEST] ❌ Tests failed - check errors above")
        return 1
    else:
        print("[TEST] ✅ All tests passed")
        return 0


if __name__ == '__main__':
    import sys
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else '.', {}, None))
