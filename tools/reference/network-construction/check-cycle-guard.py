#!/usr/bin/env python3
"""Development-only reproduction of the adopted cycle guard.
Usage: check-cycle-guard.py PINNED_ROOT LIBR_PATH GUARDED_DLL
The guarded DLL must be built separately from the verified build copy of patch 0008
(see inst/upstream/PATCHES.md).
"""
import json
import pathlib
import subprocess
import sys

sys.dont_write_bytecode = True
here = pathlib.Path(__file__).resolve().parent
baseline = json.loads((here / 'native-hazard-results.json').read_text())
results = []
for original in baseline:
    case = original['case']
    p = subprocess.run([sys.executable, str(here / 'check-native-hazards.py'),
                        *sys.argv[1:], case], capture_output=True, text=True, timeout=10)
    assert p.returncode == 0, (case, p.returncode, p.stderr)
    value = json.loads(p.stdout)
    if original['returncode'] == 0:
        assert value == json.loads(original['stdout']), (case, value)
    else:
        assert value == {'success': False}, (case, value)
    results.append(dict(case=case, result=value))
print(json.dumps(results, indent=2))
