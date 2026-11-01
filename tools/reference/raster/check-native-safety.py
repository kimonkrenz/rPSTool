#!/usr/bin/env python3
"""Development-only GNU/Linux native allocation and blur-worker fault probes.
Usage: check-native-safety.py PINNED_ROOT LIBR_PATH PACKAGE_DLL WORK_DIR
Uses verified generated copies, writes only owned work files, no installed hooks.
"""
import json, os, pathlib, subprocess, sys
repo=pathlib.Path(__file__).resolve().parents[3]
root,libr,dll,out=[pathlib.Path(x).resolve() for x in sys.argv[1:5]]
assert out.is_relative_to(repo/'work')
out.mkdir(parents=True,exist_ok=True)
for key,subdir in [('Raster.cpp',''),('Arr2d.h','include/pstalgo/utils'),('Blur.cpp','gfx'),('CreateBufferPolygons.cpp','analyses')]:
    subprocess.run(['Rscript',str(repo/'src/portability/harden-raster.R'),str(repo/'inst/upstream/build-inputs'/key),str(out/'.rpst-build'/subdir/key)],check=True)
flags=['g++','-std=c++17','-O1','-g','-I'+str(out/'.rpst-build/include'),'-I'+str(repo/'src/compat'),'-I'+str(repo/'src/vendor/pstalgo/include'),'-I'+str(repo/'src/vendor/pstalgo/src/analyses'),'-include',str(repo/'src/rpst-compat.h')]
env=os.environ.copy();env['LD_LIBRARY_PATH']=str(libr.parent)+os.pathsep+env.get('LD_LIBRARY_PATH','')
# Preinclude native dependencies before malloc injection so system declarations
# remain untouched. Constructor and FlipY failures happen before any write.
raster=out/'allocation.cpp'
raster.write_text('''#include <cstdlib>
#include <new>
#include <stdexcept>
#include <pstalgo/Debug.h>
#include <pstalgo/analyses/Common.h>
#include <pstalgo/Raster.h>
static bool fail_alloc=false;
static int allocations=0;
static void* probe_malloc(size_t n) { ++allocations; return fail_alloc ? nullptr : std::malloc(n); }
#define malloc probe_malloc
#include '''+json.dumps(str(out/'.rpst-build/Raster.cpp'))+'''
#undef malloc
extern "C" int probe_allocation() {
    fail_alloc=true; allocations=0;
    try { psta::CRaster r(UINT32_MAX,2,RasterFormat_Float); return 1; }
    catch(const std::length_error&) {} if(allocations) return 2;
    try { psta::CRaster r(2,2,RasterFormat_Float); return 3; }
    catch(const std::bad_alloc&) {} if(allocations!=1) return 4;
    fail_alloc=false;
    psta::CRaster r(2,3,RasterFormat_Float); SRasterData d;
    if(PSTAGetRasterData(&r,&d)!=PSTA_RESULT_OK || d.Pitch!=8 || d.Height!=3 || d.Bits!=r.Data()) return 5;
    psta::CRaster b(3,2,RasterFormat_Byte); SRasterData bd;
    if(PSTAGetRasterData(&b,&bd)!=PSTA_RESULT_OK || bd.Pitch!=3 || bd.Format!=RasterFormat_Byte) return 6;
    return 0;
}
''')
flip=out/'flip.cpp'
flip.write_text('''#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <vector>
#include <new>
static bool fail_alloc=false;
static int allocations=0;
static void* probe_malloc(size_t n) { ++allocations; return fail_alloc ? nullptr : std::malloc(n); }
#define malloc probe_malloc
#include <pstalgo/utils/Arr2d.h>
#undef malloc
extern "C" int probe_flip() {
    fail_alloc=true; allocations=0;
    psta::Arr2dView<float>(nullptr,0,0,0).FlipY();
    float x[4]={1,2,3,4};
    psta::Arr2dView<float>(x,2,1,2).FlipY(); if(allocations || x[0]!=1) return 1;
    try { psta::Arr2dView<float>(x,2,2,2).FlipY(); return 2; }
    catch(const std::bad_alloc&) {} if(x[0]!=1 || x[3]!=4) return 3;
    fail_alloc=false; psta::Arr2dView<float>(x,2,2,2).FlipY();
    return x[0]==3 && x[1]==4 && x[2]==1 && x[3]==2 ? 0:4;
}
''')
subprocess.run(flags+['-shared','-fPIC',str(raster),str(flip),str(dll),'-Wl,-Bsymbolic','-o',str(out/'allocation.so')],check=True)
runner=out/'allocation-run.py';runner.write_text('import ctypes,sys\nctypes.CDLL(sys.argv[1],mode=ctypes.RTLD_GLOBAL)\nm=ctypes.CDLL(sys.argv[2]);assert m.probe_allocation()==0;assert m.probe_flip()==0\n')
subprocess.run([sys.executable,str(runner),str(libr),str(out/'allocation.so')],env=env,check=True)
# Inject an exception after a worker has completed its writes. get(), rather
# than wait(), must propagate it and join all other workers before returning.
blur=(out/'.rpst-build/gfx/Blur.cpp').read_text()
assert blur.count('\n\t\t};')==2
for pass_index in [0,1]:
    parts=blur.split('\n\t\t};')
    parts[pass_index]+='\n\t\t\tthrow std::runtime_error("Injected late blur worker failure");'
    fault=out/('blur-fault-'+str(pass_index)+'.cpp');fault.write_text('#include <stdexcept>\n'+'\n\t\t};'.join(parts))
    module=out/('worker-'+str(pass_index)+'.so')
    subprocess.run(flags+['-shared','-fPIC',str(fault),str(out/'.rpst-build/analyses/CreateBufferPolygons.cpp'),str(dll),'-Wl,-Bsymbolic','-o',str(module)],check=True)
    runner=out/'worker-run.py'
    runner.write_text('''import importlib.util,sys
sys.dont_write_bytecode=True
spec=importlib.util.spec_from_file_location("oracle",sys.argv[1]);m=importlib.util.module_from_spec(spec)
sys.argv=sys.argv[1:];spec.loader.exec_module(m)
try: m.native(m.cases[0])
except RuntimeError as e:
    assert str(e).startswith("Native comparison failed:")
else: raise AssertionError("worker exception was hidden")
''')
    for cap in ['1','2','8']:
        runenv=env.copy();runenv['RPST_NUM_THREADS']=cap
        subprocess.run([sys.executable,'-Wignore::SyntaxWarning',str(runner),str(repo/'tools/reference/raster/native-cases.py'),str(root),str(libr),str(module),'unused'],env=runenv,check=True)
print('Native safety passed: byte/float inspection, allocation overflow/failure, FlipY zero/single-row/failure/success, late exceptions in both blur passes at caps 1/2/8.')
