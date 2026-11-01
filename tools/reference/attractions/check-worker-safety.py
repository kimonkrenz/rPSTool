#!/usr/bin/env python3
"""Development-only fault injection into owned generated build copies.
Usage: check-worker-safety.py PINNED_ROOT LIBR_PATH PST_DLL
No edits to pristine PST, installed binaries, or public runtime test hooks.
"""
import ast, ctypes, hashlib, pathlib, platform, subprocess, sys, tempfile
sys.dont_write_bytecode=True
root,libr,dll=map(lambda x:str(pathlib.Path(x).resolve()),sys.argv[1:])
repo=pathlib.Path(__file__).resolve().parents[3]
tree=ast.parse((repo/'tools/reference/attractions/generate-reference.py').read_text())
blobs=next(ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign) and
    any(isinstance(t,ast.Name) and t.id=='BLOBS' for t in n.targets))
for path,expected in blobs.items():
    raw=(pathlib.Path(root)/path).read_bytes()
    assert hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()==expected,path
ctypes.CDLL(libr,mode=ctypes.RTLD_GLOBAL)
engine=ctypes.CDLL(dll,mode=ctypes.RTLD_GLOBAL)
loader,system=ctypes.cdll.LoadLibrary,platform.system
try:
    ctypes.cdll.LoadLibrary=lambda path:engine
    platform.system=lambda:'Darwin'
    sys.path.insert(0,str(pathlib.Path(root)/'pstalgo/python'))
    import pstalgo as pst
    from pstalgo.attractionreach import SPSTAAttractionReachDesc
    from pstalgo.attractiondistance import SPSTAAttractionDistanceDesc
finally:ctypes.cdll.LoadLibrary,platform.system=loader,system
import array
h=pst.CreateGraph(array.array('d',[0,0,3,0]))
assert h
scratch=repo/'work/attractions';scratch.mkdir(parents=True,exist_ok=True)
try:
    with tempfile.TemporaryDirectory(dir=scratch) as tmp:
        tmp=pathlib.Path(tmp)
        for name,entry,desc_type,anchor in [
            ('AttractionReach','PSTAAttractionReach',SPSTAAttractionReachDesc,'void CAttractionAlgo::CWorker::Run()\n\t{'),
            ('AttractionDistance','PSTAAttractionDistance',SPSTAAttractionDistanceDesc,'void AttractionDistanceWorker(SAttractionDistanceWorkerContext& ctx)\n\t{')]:
            original=repo/'inst/upstream/build-inputs'/ (name+'.cpp')
            generated=tmp/'.rpst-build'/ (name+'.cpp')
            subprocess.run(['Rscript',str(repo/'src/portability/limit-workers.R'),str(original),str(generated)],check=True)
            text=generated.read_text()
            assert text.count(anchor)==1 and text.count('task.get();')==1
            # One deliberate worker exception; retain production wait/get and
            # normal graph/descriptor/ownership setup exactly.
            injected=text.replace(anchor,anchor+'\n\t\tthrow std::runtime_error("rPSTool worker failure probe");')
            injected=injected.replace(entry+'(', 'RPSTInjected'+name+'(')
            injected=injected.replace('rpst_worker_count()', 'rpst_probe_worker_count()')
            shim=tmp/(name+'-probe.cpp')
            ending=('try { RPSTInjectedAttractionReach(d); return false; } '
                    'catch (const std::exception& e) { return std::strcmp(e.what(),"rPSTool worker failure probe")==0; }') if name=='AttractionReach' else 'return !RPSTInjectedAttractionDistance(d);'
            shim.write_text('unsigned int rpst_probe_worker_count() { return 1; }\n'+injected+
                '\nextern "C" bool rpst_failure_probe(const '+desc_type.__name__+'* d) { '+ending+' }\n')
            lib=tmp/(name+'-probe.so')
            subprocess.run(['c++','-std=c++17','-DNDEBUG','-shared','-fPIC','-pthread','-Wl,-Bsymbolic',
                '-I'+str(repo/'src/compat'),'-I'+str(repo/'src/vendor/pstalgo/include'),
                '-I'+str(repo/'src/vendor/pstalgo/src/analyses'),'-I'+str(repo/'src/vendor/pstalgo/src'),
                '-include',str(repo/'src/rpst-compat.h'),str(shim),'-o',str(lib)],check=True)
            probe=ctypes.CDLL(str(lib));fn=probe.rpst_failure_probe
            fn.argtypes=[ctypes.POINTER(desc_type)];fn.restype=ctypes.c_bool
            d=desc_type();d.m_Graph=h;d.m_OriginType=2;d.m_DistanceType=1;d.m_OutputCount=1
            coords=(ctypes.c_double*2)(0,1);values=(ctypes.c_float*1)(17)
            d.m_AttractionPoints=coords;d.m_AttractionPointCount=1
            if name=='AttractionReach':d.m_OutScores=values
            else:d.m_OutMinDistances=values
            assert fn(ctypes.byref(d)),name+' swallowed worker failure'
            print(name+': injected worker failure propagated after safe wait/join')
finally:pst.FreeGraph(h)
