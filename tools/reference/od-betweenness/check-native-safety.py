#!/usr/bin/env python3
"""Linux development-only probes in owned verified generated OD copies.
Usage: check-native-safety.py PINNED_ROOT LIBR_PATH PST_DLL
No vendor edits, installed binary edits, or runtime fault-injection interface.
"""
import ast, ctypes, hashlib, os, pathlib, platform, subprocess, sys, tempfile
sys.dont_write_bytecode=True
root,libr,dll=map(lambda x:str(pathlib.Path(x).resolve()),sys.argv[1:])
repo=pathlib.Path(__file__).resolve().parents[3]
tree=ast.parse((repo/'tools/reference/od-betweenness/generate-reference.py').read_text())
blobs=next(ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign) and
    any(isinstance(t,ast.Name) and t.id=='BLOBS' for t in n.targets))
for path,expected in blobs.items():
    raw=(pathlib.Path(root)/path).read_bytes()
    if hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()!=expected:
        raise SystemExit('Pinned reference drift: '+path)
ctypes.CDLL(libr,mode=ctypes.RTLD_GLOBAL)
engine=ctypes.CDLL(dll,mode=ctypes.RTLD_GLOBAL)
loader,system=ctypes.cdll.LoadLibrary,platform.system
try:
    ctypes.cdll.LoadLibrary=lambda path:engine
    platform.system=lambda:'Darwin'
    sys.path.insert(0,str(pathlib.Path(root)/'pstalgo/python'))
    import pstalgo as pst
    from pstalgo.odbetweenness import SPSTAODBetweenness
finally:ctypes.cdll.LoadLibrary,platform.system=loader,system
import array
h=pst.CreateGraph(array.array('d',[0,0,3,0]),points=array.array('d',[1.5,.5]))
assert h
scratch=repo/'work/od-betweenness';scratch.mkdir(parents=True,exist_ok=True)
try:
    with tempfile.TemporaryDirectory(dir=scratch) as tmp:
        tmp=pathlib.Path(tmp)
        generated=tmp/'.rpst-build/ODBetweenness.cpp'
        subprocess.run(['Rscript',str(repo/'src/portability/limit-workers.R'),
            str(repo/'inst/upstream/build-inputs/ODBetweenness.cpp'),str(generated)],check=True)
        text=generated.read_text()
        assert text.count('task.get();')==1 and text.count('SStep step{};')==1 and text.count('SStep next_step{};')==1
        anchor='void CODBetweennessWorker::Run()\n\t{'
        guard='m_Trace.size() >= static_cast<size_t>(std::numeric_limits<int>::max())'
        assert text.count(anchor)==1 and text.count(guard)==1
        for variant in ['worker_failure','trace_bound','worker_count']:
            code=text.replace('PSTAODBetweenness(', 'RPSTInjectedODBetweenness(')
            extra=''
            if variant=='worker_failure':
                code=code.replace(anchor,anchor+'\n\t\tthrow std::runtime_error("OD worker failure probe");')
            elif variant=='trace_bound':
                # Exercise the production guard without allocating INT_MAX
                # traces; only the threshold is lowered in this owned probe.
                code=code.replace(guard,'m_Trace.size() >= static_cast<size_t>(0)')
            else:
                extra='#include <atomic>\nstatic std::atomic<unsigned int> rpst_probe_runs(0);\n'
                code=code.replace(anchor,anchor+'\n\t\t++rpst_probe_runs;')
            ending='return RPSTInjectedODBetweenness(d);' if variant!='worker_count' else (
                'rpst_probe_runs=0; return RPSTInjectedODBetweenness(d) && rpst_probe_runs==1;')
            source=tmp/(variant+'.cpp');lib=tmp/(variant+'.so')
            source.write_text(extra+code+'\nextern "C" bool rpst_od_probe(const SPSTAODBetweenness* d) { '+ending+' }\n')
            subprocess.run(['c++','-std=c++17','-DNDEBUG','-shared','-fPIC','-pthread','-Wl,-Bsymbolic',
                '-I'+str(repo/'src/compat'),'-I'+str(repo/'src/vendor/pstalgo/include'),
                '-I'+str(repo/'src/vendor/pstalgo/src/analyses'),'-I'+str(repo/'src/vendor/pstalgo/src'),
                '-include',str(repo/'src/rpst-compat.h'),str(source),'-o',str(lib)],check=True)
            probe=ctypes.CDLL(str(lib));fn=probe.rpst_od_probe
            fn.argtypes=[ctypes.POINTER(SPSTAODBetweenness)];fn.restype=ctypes.c_bool
            for cap in ['1','2','8']:
                os.environ['RPST_NUM_THREADS']=cap
                for distance in [1,3]:
                    d=SPSTAODBetweenness();d.m_Graph=h;d.m_DistanceType=distance;d.m_OutputCount=1
                    coords=(ctypes.c_double*2)(0,1);scores=(ctypes.c_float*1)(17)
                    d.m_OriginPoints=coords;d.m_OriginCount=1;d.m_OutScores=scores
                    result=fn(ctypes.byref(d))
                    if variant=='worker_count':assert result and scores[0]==1
                    else:assert not result and scores[0]==17
            print(variant+': passed both costs at caps 1/2/8')
finally:pst.FreeGraph(h)
