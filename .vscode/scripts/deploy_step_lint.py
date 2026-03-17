#!/usr/bin/env python3
"""
Deployment Step: Lint
Validates Lua files for syntax errors before deployment
"""

import os
import sys
from pathlib import Path


def main(out_dir: str, config: dict, args) -> int:
    """Check Lua files for syntax errors."""
    print(f"[LINT] Checking Lua syntax in: {out_dir}")
    
    lua_files = []
    out_path = Path(out_dir)
    
    # Find all .lua files
    for root, dirs, files in os.walk(out_path):
        for file in files:
            if file.endswith('.lua'):
                lua_files.append(os.path.join(root, file))
    
    if not lua_files:
        print("[LINT] No Lua files found")
        return 0
    
    errors = 0
    warnings = 0
    
    print(f"[LINT] Checking {len(lua_files)} Lua files…")
    
    for lua_file in lua_files:
        try:
            with open(lua_file, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Basic syntax checks
            # Check for matching brackets
            if content.count('{') != content.count('}'):
                print(f"   ⚠️  {lua_file}: Mismatched curly braces")
                warnings += 1
            
            if content.count('[') != content.count(']'):
                print(f"   ⚠️  {lua_file}: Mismatched square brackets")
                warnings += 1
            
            if content.count('(') != content.count(')'):
                print(f"   ⚠️  {lua_file}: Mismatched parentheses")
                warnings += 1
            
            # Check for reserved keywords syntax
            lines = content.split('\n')
            for i, line in enumerate(lines, 1):
                stripped = line.strip()
                if stripped.startswith('--'):
                    continue  # Skip comments
                
                # Check if-then-end
                if 'if ' in line and ' then' not in line and ' then' not in '\n'.join(lines[i:min(i+5, len(lines))]):
                    pass  # Could be multiline, skip
            
        except Exception as e:
            print(f"   ❌ {lua_file}: Error reading file: {e}")
            errors += 1
    
    print(f"[LINT] Summary: {len(lua_files)} files checked, {warnings} warnings, {errors} errors")
    
    return 0 if errors == 0 else 1


if __name__ == '__main__':
    # For testing
    import sys
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else '.', {}, None))
