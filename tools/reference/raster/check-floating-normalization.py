#!/usr/bin/env python3
"""GNU/Linux direct-PST proof of the authorised floating absolute-value contract.
Usage: check-floating-normalization.py PINNED_ROOT LIBR_PATH BASELINE_DLL PACKAGE_DLL WORK_DIR
Builds independent pinned comparison translation units, never R bindings.
Original overload evidence remains in check-abs-overloads.py.
"""
import hashlib, json, os, pathlib, subprocess, sys
repo = pathlib.Path(__file__).resolve().parents[3]
root, libr, baseline, package, out = [pathlib.Path(x).resolve() for x in sys.argv[1:6]]
assert out.is_relative_to(repo/'work')
out.mkdir(parents=True, exist_ok=True)
manifest = json.loads((repo/'tools/reference/raster/source-blobs.json').read_text())
source = repo/'src/vendor/pstalgo/src/analyses/CreateBufferPolygons.cpp'
raw = source.read_bytes()
assert hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest() == manifest['blobs']['pstalgo/src/analyses/CreateBufferPolygons.cpp']
old = b'std::max(abs(min), abs(max))'
new = b'std::max(std::abs(min), std::abs(max))'
assert raw.count(old) == 1 and raw.count(new) == 0
approved = raw.replace(old, new)
assert approved.replace(new, old) == raw
(out/'approved.cpp').write_bytes(approved)
flags = ['g++','-std=c++17','-shared','-fPIC','-O1','-g',
         '-I'+str(repo/'src/compat'),'-I'+str(repo/'src/vendor/pstalgo/include'),
         '-I'+str(source.parent),'-include',str(repo/'src/rpst-compat.h')]
for name, path, extra in [('original',source,[]),('floating',source,['-include','math.h']),
                         ('approved',out/'approved.cpp',[]),
                         ('sanitized',out/'approved.cpp',['-fsanitize=float-cast-overflow','-fno-sanitize-recover=float-cast-overflow'])]:
    subprocess.run(flags+extra+[str(path),str(baseline),'-Wl,-Bsymbolic','-o',str(out/(name+'.so'))],check=True)
env = os.environ.copy()
env['LD_LIBRARY_PATH'] = str(libr.parent)+os.pathsep+env.get('LD_LIBRARY_PATH','')
oracle = repo/'tools/reference/raster/native-cases.py'
results = {}
for name in ['original','floating','approved','sanitized','package']:
    dll = package if name == 'package' else out/(name+'.so')
    output = out/(name+'.json')
    # Original normalized large/zero-blur integer casts are unsafe and already
    # retained as sanitizer evidence. The original 75 cases are sufficient
    # for the unchanged Relative Percent comparison; add overflow separately.
    extra = ['--original'] if name == 'original' else []
    subprocess.run([sys.executable,'-Wignore::SyntaxWarning',str(oracle),str(root),str(libr),str(dll),str(output)]+extra,env=env,check=True)
    results[name] = json.loads(output.read_text())
for name in ['floating','sanitized','package']:
    assert (out/(name+'.json')).read_bytes() == (out/'approved.json').read_bytes(), name
relative = [x for x in results['approved'] if x['args']['mode']=='relative_percent']
original = {x['name']:x for x in results['original']}
for case in relative:
    if case['name'] in original: assert case == original[case['name']]
# The extra Relative Percent overflow case is safe in the unchanged TU, too.
probe = out/'relative-overflow.py'
probe.write_text('import importlib.util, json, sys\nsys.dont_write_bytecode=True\nspec=importlib.util.spec_from_file_location("oracle",sys.argv[1]); m=importlib.util.module_from_spec(spec)\nsys.argv=sys.argv[1:]; spec.loader.exec_module(m)\nc=next(c for c in m.cases if c["name"]=="relative_overflow")\nprint(json.dumps(m.native(c),sort_keys=True,allow_nan=False))\n')
run = subprocess.run([sys.executable,'-Wignore::SyntaxWarning',str(probe),str(oracle),str(root),str(libr),str(out/'original.so'),'unused'],env=env,text=True,capture_output=True,check=True)
assert json.loads(run.stdout) == relative[-1]['expected']
report = dict(pin=manifest['pin'], verified_blobs=len(manifest['blobs']),
    authority='Explicitly authorised floating std::abs(float) in pinned PST normalization; independent direct exported C API.',
    source_blob_sha=manifest['blobs']['pstalgo/src/analyses/CreateBufferPolygons.cpp'],
    approved_source_md5=hashlib.md5(approved).hexdigest(),
    cases=len(results['approved']), relative_percent_unchanged=len(relative),
    identical_runs=['floating_math_header','narrow_std_abs','float_cast_sanitized','package_c_api'],
    result_sha256=hashlib.sha256((out/'approved.json').read_bytes()).hexdigest(),
    case_results=[dict(name=c['name'], mode=c['args']['mode'],
        result_sha256=hashlib.sha256(json.dumps(c['expected'],sort_keys=True,allow_nan=False).encode()).hexdigest())
        for c in results['approved']])
(out/'verified.json').write_text(json.dumps(report,indent=2,allow_nan=False)+'\n')
print('Approved floating contract: 79 cases exact across independent math-header, narrow std::abs, sanitized and package C API runs; all '+str(len(relative))+' Relative Percent cases unchanged.')
