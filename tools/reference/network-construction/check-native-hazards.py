#!/usr/bin/env python3
"""Development-only direct pinned PST network-construction investigation.
Usage: check-native-hazards.py PINNED_ROOT LIBR_PATH PST_DLL
Run repository/vendor verification first. Prints deterministic JSON to stdout;
source verification/upstream tests go to stderr. Child processes isolate native
crashes and disable core dumps. This reproduction requires Unix and is not part
of installed package tests. No rPSTool analysis binding is called.
"""
import array, ctypes, hashlib, json, pathlib, platform, resource, signal, subprocess, sys, unittest
sys.dont_write_bytecode=True
root,libr,dll=map(lambda p:str(pathlib.Path(p).resolve()),sys.argv[1:4])
manifest=json.loads(pathlib.Path(__file__).with_name('source-blobs.json').read_text())
assert manifest['pin']=='63df80a2cf3dd289be95ea3d91667c3490719b75'
for name,expected in manifest['blobs'].items():
    raw=(pathlib.Path(root)/name).read_bytes()
    actual=hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()
    if actual!=expected:raise SystemExit('Pinned reference drift: '+name)
if len(sys.argv)==4:print('Verified '+str(len(manifest['blobs']))+' exact pinned blobs',file=sys.stderr)
ctypes.CDLL(libr,mode=ctypes.RTLD_GLOBAL)
engine=ctypes.CDLL(dll)
loader,system=ctypes.cdll.LoadLibrary,platform.system
try:
    ctypes.cdll.LoadLibrary=lambda _:engine
    platform.system=lambda:'Darwin'
    sys.path.insert(0,root+'/pstalgo/python')
    import pstalgo as pst
finally:
    ctypes.cdll.LoadLibrary,platform.system=loader,system
if len(sys.argv)>4:
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    case=sys.argv[4]
    from pstalgo.createjunctions import SCreateJunctionsDesc,SCreateJunctionsRes,PSTACreateJunctions
    if case.startswith('empty_junctions'):
        seed=int(case.split(':')[1]);desc=SCreateJunctionsDesc();res=SCreateJunctionsRes()
        coords=(ctypes.c_double*2)(seed,seed)
        res.m_PointCoords=ctypes.cast(coords,ctypes.POINTER(ctypes.c_double));res.m_PointCount=seed
        before=ctypes.cast(res.m_PointCoords,ctypes.c_void_p).value
        h=PSTACreateJunctions(engine,desc,res)
        try:print(json.dumps(dict(success=bool(h),count=res.m_PointCount,pointer_unchanged=before==ctypes.cast(res.m_PointCoords,ctypes.c_void_p).value)))
        finally:pst.Free(h)
    else:
        configs={
            'open_control':([0,0,1,0,2,0],0,1),
            'square_default':([0,0,1,0,1,1,0,1,0,0],0,1),
            'square_zero_deviation':([0,0,1,0,1,1,0,1,0,0],0,0),
            'large_square_default':([0,0,10,0,10,10,0,10,0,0],0,1),
            'collinear_loop_zero_deviation':([0,0,1,0,2,0,0,0],0,0),
            'snapped_open_square':([0,0,10,0,10,10,0,10,0,.1],.2,20),
        }
        coords,snap,deviation=configs[case]
        res,h=pst.CreateSegmentMap(pst.RoadNetworkType.AXIAL_OR_SEGMENT,array.array('d',coords),array.array('i',[len(coords)//2]),snap=snap,tail=0,deviation=deviation,extrude=0)
        if not h:
            print(json.dumps(dict(success=False)))
            raise SystemExit(0)  # Never read result fields following native failure.
        try:
            rows=[]
            for i in range(res.m_SegmentCount):
                p0,p1,base=res.m_Segments[3*i:3*i+3]
                rows.append([*res.m_SegmentCoords[2*p0:2*p0+2],*res.m_SegmentCoords[2*p1:2*p1+2],base])
            print(json.dumps(dict(success=bool(h),segments=rows)))
        finally:pst.Free(h)
else:
    sys.path.insert(0,root+'/pstalgo/test')
    suite=unittest.defaultTestLoader.loadTestsFromNames(['tests.testcreatejunctions','tests.testcreatesegmentmap'])
    if not unittest.TextTestRunner().run(suite).wasSuccessful():raise SystemExit(1)
    results=[]
    for case in ['empty_junctions:17','empty_junctions:29','open_control','square_zero_deviation','large_square_default','square_default','collinear_loop_zero_deviation','snapped_open_square']:
        p=subprocess.run([sys.executable,__file__,root,libr,dll,case],text=True,capture_output=True,timeout=10)
        results.append(dict(case=case,returncode=p.returncode,stdout=p.stdout.strip(),stderr=p.stderr.strip()))
    for entry in results:
        case=entry['case']
        if case in ['square_default','collinear_loop_zero_deviation','snapped_open_square']:
            assert entry['returncode']==-signal.SIGSEGV,entry
        else:
            assert entry['returncode']==0,entry
            value=json.loads(entry['stdout']);assert value['success'],entry
            if case.startswith('empty_junctions'):
                assert value['count']==int(case.split(':')[1]) and value['pointer_unchanged'],entry
            else:
                assert len(value['segments'])==(1 if case=='open_control' else 4),entry
    print(json.dumps(results,indent=2))
