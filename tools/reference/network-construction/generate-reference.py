#!/usr/bin/env python3
"""Development-only pinned C API structural oracle. No R analysis calls.
Usage: generate-reference.py PINNED_ROOT LIBR_PATH PST_DLL OUTPUT_JSON
Compare pristine and adapted DLL runs byte-for-byte before installing fixtures.
"""
import ctypes,hashlib,json,pathlib,platform,subprocess,sys,unittest
sys.dont_write_bytecode=True
root,libr,dll,output=sys.argv[1:5]
root=pathlib.Path(root).resolve();libr=str(pathlib.Path(libr).resolve());dll=str(pathlib.Path(dll).resolve())
manifest=json.loads(pathlib.Path(__file__).with_name('source-blobs.json').read_text())
for name,expected in manifest['blobs'].items():
    raw=(root/name).read_bytes()
    if hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()!=expected:raise SystemExit('Pinned reference drift: '+name)
ctypes.CDLL(libr,mode=ctypes.RTLD_GLOBAL);engine=ctypes.CDLL(dll)
loader,system=ctypes.cdll.LoadLibrary,platform.system
try:
    ctypes.cdll.LoadLibrary=lambda _:engine;platform.system=lambda:'Darwin'
    sys.path.insert(0,str(root/'pstalgo/python'));import pstalgo as pst
finally:ctypes.cdll.LoadLibrary,platform.system=loader,system
from pstalgo.createjunctions import SCreateJunctionsDesc,SCreateJunctionsRes,PSTACreateJunctions
from pstalgo.createsegmentmap import SCreateSegmentMapDesc,SCreateSegmentMapRes,PSTACreateSegmentMap

def native(case,seed):
    args=case['args'];keep=[]
    def buf(rows,ctype):
        values=[v for row in rows for v in row] if rows and isinstance(rows[0],list) else rows
        a=(ctype*max(1,len(values)))(*values);keep.append(a);return ctypes.cast(a,ctypes.POINTER(ctype))
    def coords(rows):return buf(rows,ctypes.c_double)
    if case['kind']=='junctions':
        desc=SCreateJunctionsDesc();res=SCreateJunctionsRes()
        desc.m_Coords0=coords(args['x'])
        if 'line_indices' in args:
            desc.m_Lines0=buf([[v-1 for v in row] for row in args['line_indices']],ctypes.c_uint)
            desc.m_LineCount0=len(args['line_indices'])
        else:desc.m_LineCount0=len(args['x'])
        if 'y' in args:
            desc.m_Coords1=coords(args['y'])
            if 'line_indices_y' in args:
                desc.m_Lines1=buf([[v-1 for v in row] for row in args['line_indices_y']],ctypes.c_uint)
                desc.m_LineCount1=len(args['line_indices_y'])
            else:desc.m_LineCount1=len(args['y'])
        if 'unlinks' in args:desc.m_UnlinkCoords=coords(args['unlinks']);desc.m_UnlinkCount=len(args['unlinks'])
        res.m_PointCoords=coords([[seed,seed]]);res.m_PointCount=seed
        h=PSTACreateJunctions(engine,desc,res)
        if not h:raise RuntimeError('Native Junctions failure: '+case['name'])
        try:return dict(points=[list(res.m_PointCoords[2*i:2*i+2]) for i in range(res.m_PointCount)])
        finally:pst.Free(h)
    desc=SCreateSegmentMapDesc();res=SCreateSegmentMapRes()
    for key,field,default in [('snap','m_Snap',1),('tail','m_MinTail',10),('deviation','m_Min3NodeColinearDeviation',1),('extrude','m_ExtrudeCut',0)]:
        setattr(desc,field,args.get(key,default))
    desc.m_RoadNetworkType={'axial_or_segment':1,'road_center_lines':2}[args['network_type']]
    desc.m_PolyCoords=coords(args['coords']);desc.m_PolyCoordCount=len(args['coords'])
    desc.m_PolySections=buf(args['sections'],ctypes.c_int);desc.m_PolySectionCount=len(args['sections']);desc.m_PolyCount=len(args['sections'])
    if 'unlinks' in args:desc.m_UnlinkCoords=coords(args['unlinks']);desc.m_UnlinkCount=len(args['unlinks'])
    res.m_SegmentCount=seed;res.m_UnlinkCount=seed
    res.m_SegmentCoords=coords([[seed,seed]]);res.m_UnlinkCoords=coords([[seed,seed]])
    res.m_Segments=buf([seed]*3,ctypes.c_uint)
    h=PSTACreateSegmentMap(engine,desc,res)
    if not h:raise RuntimeError('Native SegmentMap failure: '+case['name'])
    try:
        segments=[];bases=[]
        for i in range(res.m_SegmentCount):
            p0,p1,base=res.m_Segments[3*i:3*i+3]
            segments.append([*res.m_SegmentCoords[2*p0:2*p0+2],*res.m_SegmentCoords[2*p1:2*p1+2]]);bases.append(base)
        return dict(segments=segments,base_id=bases,unlinks=[list(res.m_UnlinkCoords[2*i:2*i+2]) for i in range(res.m_UnlinkCount)])
    finally:pst.Free(h)

cases=[]
def j(name,**args):cases.append(dict(kind='junctions',name=name,args=args))
lines=[[-10,0,10,0],[0,-10,0,10],[5,-10,5,10],[-5,-10,-5,10]]
j('three_sorted_crossings',x=lines)
for name,unlink in [('first',[[-5,0]]),('middle',[[0,0]]),('last',[[5,0]]),('far',[[10000,10000]]),('two',[[-5,0],[5,0]])]:j('unlink_'+name,x=lines,unlinks=unlink)
j('two_collinear_shared_endpoint',x=[[0,0,1,0],[1,0,2,0]])
j('three_way_endpoint',x=[[0,0,1,0],[1,0,2,0],[1,0,1,1]])
j('two_layers_endpoint',x=[[0,0,1,0]],y=[[1,0,1,1]])
j('two_layers_crossings',x=[lines[0]],y=lines[1:])
j('explicit_empty_second',x=lines,y=[])
j('native_written_empty',x=[[0,0,0,0],[1,1,1,1]])
for t in [.019,.021,.98,.981]:j('tail_fraction_'+str(t),x=[[0,0,100,0],[100*t,-1,100*t,1]])
j('indexed_prefix',x=[[100,0],[0,0],[10,0],[5,-5],[5,5],[1e250,1e250]],line_indices=[[2,3],[4,5]])
j('indexed_both',x=[[-10,0],[10,0]],line_indices=[[1,2]],y=[[0,-10],[0,10],[1e250,1e250]],line_indices_y=[[1,2]])
j('large_world_center',x=[[1e12-10,1e12,1e12+10,1e12],[1e12,1e12-10,1e12,1e12+10]])
j('reversed_duplicate',x=[[-10,0,10,0],[10,0,-10,0],[0,-10,0,10]])
j('zero_length_and_cross',x=[[0,0,0,0],[-10,0,10,0],[0,-10,0,10]])
shapes=[
 ('chain',[[0,0],[10,0],[20,0]],[3]),
 ('bent',[[0,0],[10,1],[20,0],[20,10]],[4]),
 ('cross',[[0,0],[20,0],[10,-10],[10,10]],[2,2]),
 ('near_miss',[[0,0],[20,0],[10,1],[10,10]],[2,2]),
 ('tails',[[0,0],[20,0],[10,-1],[10,10]],[2,2]),
 ('large_closed',[[0,0],[10,0],[10,10],[0,10],[0,0]],[5]),
 ('same_base_sections',[[0,0],[10,0],[20,0],[20,0],[30,0],[40,0]],[-4,3]),
 ('different_base_sections',[[0,0],[10,0],[20,0],[20,0],[30,0],[40,0]],[3,3]),
 ('empty_singleton_sections',[[100,100],[0,0],[10,0]],[0,1,2]),
 ('zero_length',[[0,0],[0,0]],[2]),
 ('duplicate_reverse',[[0,0],[10,0],[10,0],[0,0]],[2,2]),
 ('disconnected',[[0,0],[10,0],[100,0],[110,0]],[2,2])]
settings=[{},dict(snap=0,tail=0,deviation=0,extrude=0),dict(snap=.5,tail=2,deviation=.5,extrude=2),dict(snap=1.01,tail=10,deviation=2,extrude=1)]
for name,coords_,sections_ in shapes:
    for mode in ['axial_or_segment','road_center_lines']:
        for i,setting in enumerate(settings):
            cases.append(dict(kind='segment_map',name=f'{name}_{mode}_{i}',args=dict(coords=coords_,sections=sections_,network_type=mode,**setting)))
for pos in [[10,0],[110,0],[109.99,0],[10000,10000]]:
    cases.append(dict(kind='segment_map',name='cut_unlink_'+str(pos[0]),args=dict(coords=shapes[2][1],sections=[2,2],network_type='axial_or_segment',snap=0,tail=0,deviation=0,unlinks=[pos])))
cases.append(dict(kind='segment_map',name='safe_unit_closed',args=dict(coords=[[0,0],[1,0],[1,1],[0,1],[0,0]],sections=[5],network_type='axial_or_segment',snap=0,tail=0,deviation=0)))
cases.append(dict(kind='segment_map',name='trailing_negative_section',args=dict(coords=[[0,0],[10,0]],sections=[-3],network_type='axial_or_segment',snap=0,tail=0,deviation=0)))
cases.append(dict(kind='segment_map',name='large_world_map',args=dict(coords=[[1e12,1e12],[1e12+10,1e12],[1e12+20,1e12]],sections=[3],network_type='axial_or_segment',snap=0,tail=0,deviation=1)))
if len(sys.argv)>5:
    case=cases[int(sys.argv[5])]
    one,two=native(case,17),native(case,29)
    assert one==two,case
    print(json.dumps(one));raise SystemExit(0)
sys.path.insert(0,str(root/'pstalgo/test'))
suite=unittest.defaultTestLoader.loadTestsFromNames(['tests.testcreatejunctions','tests.testcreatesegmentmap'])
if not unittest.TextTestRunner().run(suite).wasSuccessful():raise SystemExit('Pinned upstream tests failed')
for i,case in enumerate(cases):
    p=subprocess.run([sys.executable,__file__,str(root),libr,dll,output,str(i)],capture_output=True,text=True,timeout=10)
    if p.returncode:raise SystemExit(f'{case["name"]}: {p.returncode}\n{p.stderr}')
    case['native']=json.loads(p.stdout)
pathlib.Path(output).write_text(json.dumps(dict(pst_commit=manifest['pin'],cases=cases),indent=2)+'\n')
print(f'{len(cases)} structural fixtures, two caller seeds per case, verified {len(manifest["blobs"])} blobs',file=sys.stderr)
