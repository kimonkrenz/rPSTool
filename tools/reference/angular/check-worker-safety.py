#!/usr/bin/env python3
"""Linux development-only worker faults in owned verified angular build copies.
Usage: check-worker-safety.py PINNED_ROOT LIBR_PATH PST_DLL
"""
import ast,ctypes,hashlib,os,pathlib,platform,subprocess,sys,tempfile
sys.dont_write_bytecode=True
root,libr,dll=map(lambda x:str(pathlib.Path(x).resolve()),sys.argv[1:])
repo=pathlib.Path(__file__).resolve().parents[3]
tree=ast.parse((repo/'tools/reference/angular/generate-reference.py').read_text())
blobs=next(ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='BLOBS' for t in n.targets))
for path,expected in blobs.items():
    raw=(pathlib.Path(root)/path).read_bytes()
    if hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()!=expected:raise SystemExit('Pinned reference drift: '+path)
ctypes.CDLL(libr,mode=ctypes.RTLD_GLOBAL);engine=ctypes.CDLL(dll,mode=ctypes.RTLD_GLOBAL)
loader,system=ctypes.cdll.LoadLibrary,platform.system
try:
    ctypes.cdll.LoadLibrary=lambda path:engine;platform.system=lambda:'Darwin'
    sys.path.insert(0,str(pathlib.Path(root)/'pstalgo/python'));import pstalgo as pst
finally:ctypes.cdll.LoadLibrary,platform.system=loader,system
import array
h=pst.CreateSegmentGraph(array.array('d',[0,0,3,0,3,0,6,0]),None,None)
assert h
scratch=repo/'work/angular';scratch.mkdir(parents=True,exist_ok=True)
try:
    with tempfile.TemporaryDirectory(dir=scratch) as tmp:
        tmp=pathlib.Path(tmp);generated=tmp/'.rpst-build/AngularChoiceAlgo.cpp'
        subprocess.run(['Rscript',str(repo/'src/portability/limit-workers.R'),str(repo/'inst/upstream/build-inputs/AngularChoiceAlgo.cpp'),str(generated)],check=True)
        text=generated.read_text();assert text.count('task.get();')==1
        entry='void Run(unsigned int first_segment_index, unsigned int num_segments, std::atomic<unsigned int>& segments_processed_counter)\n\t{'
        end='\t\t\t// TODO: Handle cancelling\n\t\t}\n\t}'
        assert text.count(entry)==1 and text.count(end)==1
        extra='#include <atomic>\nstatic std::atomic<int> probe_active(0);\nstruct ProbeActive { ProbeActive(){++probe_active;} ~ProbeActive(){--probe_active;} };\n'
        shim='''
#include <pstalgo/analyses/AngularIntegration.h>
#include <pstalgo/analyses/AngularChoice.h>
extern "C" bool rpst_angular_probe(void* h, int mode, bool weighted, unsigned int precision) {
  unsigned int counts[2]={17,17}; float depths[2]={17,17}, weights[2]={17,17}, dw[2]={17,17}, scores[2]={17,17};
  try {
    if (mode==0) {
      SPSTAAngularIntegrationDesc d{}; d.m_Graph=h; d.m_WeighByLength=weighted; d.m_AnglePrecision=precision;
      d.m_OutNodeCounts=counts;d.m_OutTotalDepths=depths;d.m_OutTotalWeights=weights;d.m_OutTotalDepthWeights=dw;
      PSTAAngularIntegration(&d);
    } else {
      SPSTAAngularChoiceDesc d{}; d.m_Graph=h; d.m_WeighByLength=weighted; d.m_AnglePrecision=precision;
      d.m_OutChoice=scores;d.m_OutNodeCount=counts;d.m_OutTotalDepth=depths;d.m_OutTotalDepthWeight=dw;
      PSTAAngularChoice(&d);
    }
  } catch (const std::exception& e) {
    return std::string(e.what())=="angular worker probe" && probe_active==0;
  }
  return false;
}
'''
        for variant in ['worker_entry','completed_worker']:
            code=extra+text.replace(entry,entry+'\n\t\tProbeActive active;')
            if variant=='worker_entry':code=code.replace(entry,entry+'\n\t\tthrow std::runtime_error("angular worker probe");')
            else:code=code.replace(end,end[:-2]+'\t\tthrow std::runtime_error("angular worker probe");\n\t}')
            source=tmp/(variant+'.cpp');lib=tmp/(variant+'.so');source.write_text(code+shim)
            subprocess.run(['c++','-std=c++17','-DNDEBUG','-shared','-fPIC','-pthread','-Wl,-Bsymbolic',
                '-I'+str(repo/'src/compat'),'-I'+str(repo/'src/vendor/pstalgo/include'),'-I'+str(repo/'src/vendor/pstalgo/src/analyses'),
                '-include',str(repo/'src/rpst-compat.h'),str(source),str(repo/'src/vendor/pstalgo/src/analyses/AngularIntegration.cpp'),
                str(repo/'src/vendor/pstalgo/src/analyses/AngularChoice.cpp'),'-o',str(lib)],check=True)
            probe=ctypes.CDLL(str(lib));fn=probe.rpst_angular_probe
            fn.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_bool,ctypes.c_uint];fn.restype=ctypes.c_bool
            for cap in ['1','2','8']:
                os.environ['RPST_NUM_THREADS']=cap
                for mode in [0,1]:
                    for weighted in [False,True]:
                        for precision in [1,7,4294967295]:assert fn(h,mode,weighted,precision)
            print(variant+': propagated and joined, both analyses/weights, caps 1/2/8, precision 1/7/UINT_MAX')
            counts=array.array('I',[0,0]);pst.AngularIntegration(h,pst.Radii(),out_node_counts=counts)
            assert list(counts)==[2,2]
finally:pst.FreeSegmentGraph(h)
