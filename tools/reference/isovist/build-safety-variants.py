#!/usr/bin/env python3
"""Build investigation-only baseline/checked/guarded modules; not package inputs.

Usage: build-safety-variants.py BASELINE_PST_DLL WORK_DIRECTORY
Run vendor verification first. Requires GCC on Linux. The baseline package DLL
supplies unchanged pinned dependencies. Local binding prevents its original
isovist implementation from preempting the inspected module.
"""
import hashlib
import pathlib
import re
import subprocess
import sys

repo = pathlib.Path(__file__).resolve().parents[3]
dll = pathlib.Path(sys.argv[1]).resolve()
out = pathlib.Path(sys.argv[2]).resolve()
if not dll.is_relative_to(repo) or not out.is_relative_to(repo / 'work'):
    raise SystemExit('DLL and work output must remain inside rPSTool')
raw = (repo / 'src/vendor/pstalgo/src/analyses/CalculateIsovists.cpp').read_bytes()
assert hashlib.md5(raw).hexdigest() == '42c16aa243ccc11e2b2e95692407ebb7'
original = raw.decode()
old = '\t\tResult& Result() { return m_Result; }'
new = '\t\tCIsovistContext::Result& Result() { return m_Result; }'
assert original.count(old) == 1
qualified = original.replace(old, new)
assert hashlib.md5(qualified.encode()).hexdigest() == 'a98b22b9a2f066e734ffc8a51fe35974'
lines = original.splitlines(keepends=True)
patch = (repo / 'inst/upstream/patches/0009-isovist-safety.patch').read_text()
hunks = re.split(r'(?m)^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@\n', patch)
assert hunks[0] == ('--- a/pstalgo/src/analyses/CalculateIsovists.cpp\n'
                    '+++ b/pstalgo/src/analyses/CalculateIsovists.cpp\n')
delta = 0
for i in range(1, len(hunks), 5):
    old_start, old_count, new_start, new_count, body = hunks[i:i+5]
    count = int(old_count or 1)
    at = int(old_start) - (1 if count else 0) + delta
    removed = [line[1:] for line in body.splitlines(keepends=True) if line.startswith('-')]
    added = [line[1:] for line in body.splitlines(keepends=True) if line.startswith('+')]
    assert count == len(removed) and int(new_count or 1) == len(added)
    assert lines[at:at+count] == removed
    lines[at:at+count] = added
    delta += len(added) - count
guarded = ''.join(lines).replace(old, new)
assert hashlib.md5(guarded.encode()).hexdigest() == 'f03bb50a1abf2111af63e626940267d7'
out.mkdir(parents=True, exist_ok=True)
for name, text in [('baseline', qualified), ('checked', qualified), ('guarded', guarded)]:
    source = out / (name + '.cpp')
    source.write_bytes(text.encode())
    flags = ['-O2', '-DNDEBUG'] if name == 'baseline' else ['-O0', '-g', '-D_GLIBCXX_ASSERTIONS']
    flags.append('-ffp-contract=off')  # rPSTool deterministic floating-point policy
    subprocess.run(['g++', '-std=c++17', '-shared', '-fPIC', *flags,
                    '-I' + str(repo / 'src/compat'),
                    '-I' + str(repo / 'src/vendor/pstalgo/include'),
                    '-I' + str(repo / 'src/vendor/pstalgo/src/analyses'),
                    '-include', str(repo / 'src/rpst-compat.h'), str(source),
                    str(dll), '-Wl,-Bsymbolic', '-o', str(out / (name + '.so'))],
                   check=True)
    print(name + ': ' + hashlib.sha256(source.read_bytes()).hexdigest())
