#!/usr/bin/env python3
"""Linux/GCC investigation of pinned normalization overloads and unsafe casts.
Usage: check-abs-overloads.py PINNED_ROOT LIBR_PATH BASELINE_DLL WORK_DIR
The reference checkout and vendor tree are read-only. Only rPSTool/work receives
modules. No proposed computational correction is applied to package build inputs.
"""
import ctypes, hashlib, importlib.util, json, math, os, pathlib, subprocess, sys
sys.dont_write_bytecode = True
repo = pathlib.Path(__file__).resolve().parents[3]
root, libr, dll, output = [pathlib.Path(x).resolve() for x in sys.argv[1:5]]
source = repo/'src/vendor/pstalgo/src/analyses/CreateBufferPolygons.cpp'
manifest=json.loads(pathlib.Path(__file__).with_name('source-blobs.json').read_text())
raw=source.read_bytes()
assert hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()==manifest['blobs']['pstalgo/src/analyses/CreateBufferPolygons.cpp']
if not dll.is_relative_to(repo) or not output.is_relative_to(repo/'work'):
    raise SystemExit('DLL and build output must remain inside rPSTool/work or the rPSTool checkout')

if len(sys.argv)>5:
    case_name=sys.argv[5]
    module=output/'sanitized.so'
    argv=sys.argv
    sys.argv=[str(repo/'tools/reference/raster/native-cases.py'),str(root),str(libr),str(module),'unused']
    spec=importlib.util.spec_from_file_location('raster_oracle',sys.argv[0])
    oracle=importlib.util.module_from_spec(spec);spec.loader.exec_module(oracle)
    sys.argv=argv
    args=dict(x=[[0,0,2,2],[0,2,2,0]],values1=[0,0],values2=[1e12,2e12],
              mode='normalized',m=.1,blur_radius=1,resolution=1)
    if case_name=='zero_blur':
        args.update(values1=[1,2],values2=[3,4],blur_radius=0)
    elif case_name=='relative_large':
        args['mode']='relative_percent'
    print(json.dumps(oracle.native(dict(name=case_name,args=args,ranges=[])),allow_nan=False))
    raise SystemExit(0)

output.mkdir(parents=True,exist_ok=True)
tu=output/'overload.cpp'
tu.write_text('#include '+json.dumps(str(source))+'\n'
    'namespace psta { extern "C" int probe_integer_abs() { return std::is_integral<decltype(abs(0.f))>::value; } }\n')
for name, extra in [('integer',[]),('floating',['-include','math.h']),
                    ('sanitized',['-fsanitize=float-cast-overflow','-fno-sanitize-recover=float-cast-overflow'])]:
    subprocess.run(['g++','-std=c++17','-shared','-fPIC','-O1','-g',
        '-I'+str(repo/'src/compat'),'-I'+str(repo/'src/vendor/pstalgo/include'),
        '-I'+str(repo/'src/vendor/pstalgo/src/analyses'),
        '-include',str(repo/'src/rpst-compat.h'),*extra,str(tu),str(dll),
        '-Wl,-Bsymbolic','-o',str(output/(name+'.so'))],check=True)

env=os.environ.copy()
env['LD_LIBRARY_PATH']=str(libr.parent)+os.pathsep+env.get('LD_LIBRARY_PATH','')
oracle_path=repo/'tools/reference/raster/native-cases.py'
observations={}
ctypes.CDLL(str(libr),mode=ctypes.RTLD_GLOBAL)
for name in ['integer','floating']:
    path=output/(name+'.json')
    subprocess.run([sys.executable,'-Wignore::SyntaxWarning',str(oracle_path),str(root),str(libr),
                    str(output/(name+'.so')),str(path),'--original'],env=env,check=True)
    observations[name]=json.loads(path.read_text())
    module=ctypes.CDLL(str(output/(name+'.so')))
    module.probe_integer_abs.restype=ctypes.c_int
    assert module.probe_integer_abs()==(name=='integer')

def summary(e):
    pixels=[v for row in e['values'] for v in row]
    coords=[v for g in e['polygons'] for p in g for r in p for xy in r for v in xy]
    return dict(sha256=hashlib.sha256(json.dumps(e,sort_keys=True,allow_nan=False).encode()).hexdigest(),
        min=e['min'],max=e['max'],dimensions=[e['width'],e['height']],
        pixel_nan=sum(v=='NaN' for v in pixels),pixel_inf=sum(v in ['Inf','-Inf'] for v in pixels),
        polygon_count=e['polygon_count'],nonfinite_coordinates=sum(isinstance(v,str) for v in coords))
cases=[]
for a,b in zip(observations['integer'],observations['floating']):
    assert a['name']==b['name'] and a['args']==b['args'] and a['ranges']==b['ranges']
    cases.append(dict(name=a['name'],args=a['args'],ranges=a['ranges'],
        same=a['expected']==b['expected'],integer=summary(a['expected']),floating=summary(b['expected'])))
sanitizers=[]
for case in ['large_values','zero_blur','relative_large']:
    run=subprocess.run([sys.executable,'-Wignore::SyntaxWarning',str(pathlib.Path(__file__).resolve()),
        str(root),str(libr),str(dll),str(output),case],env=env,text=True,capture_output=True)
    if case=='relative_large':
        assert run.returncode==0 and not run.stderr
    else:
        assert run.returncode!=0 and 'outside the range of representable values of type' in run.stderr
    sanitizers.append(dict(name=case,returncode=run.returncode,
        diagnostic=run.stderr.replace(str(source),'pstalgo/src/analyses/CreateBufferPolygons.cpp').strip(),
        success=run.returncode==0))
report=dict(pin=manifest['pin'],verified_blobs=len(manifest['blobs']),
    authority='Pinned source, identical dependencies, GCC integer abs versus added standard math.h overloads; observations, not approved expected values.',
    source_sha=manifest['blobs']['pstalgo/src/analyses/CreateBufferPolygons.cpp'],
    abs_types=dict(integer='int',floating='float'),cases=cases,sanitizers=sanitizers,
    differing_normalized=sum(not c['same'] for c in cases if c['args']['mode']=='normalized'),
    differing_relative_percent=sum(not c['same'] for c in cases if c['args']['mode']=='relative_percent'))
fields=[]
for key, value in report.items():
    encoded = ('[\n    '+',\n    '.join(json.dumps(c,separators=(',',':'),allow_nan=False) for c in value)+'\n  ]') if key=='cases' else json.dumps(value,indent=2,allow_nan=False).replace('\n','\n  ')
    fields.append('  '+json.dumps(key)+': '+encoded)
path=output/'observed.json';path.write_text('{\n'+',\n'.join(fields)+'\n}\n')
print('Report:',path)
