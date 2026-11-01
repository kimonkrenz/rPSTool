#!/usr/bin/env python3
"""Direct pinned C API oracle, never calls an rPSTool binding.
Usage: native-cases.py PINNED_ROOT LIBR_PATH PST_DLL OUTPUT_JSON
Approved floating-contract runs must regenerate identical bytes.
--original selects the 75-case integer/floating overload inventory.
Python is development only.
"""
import ctypes as C
import hashlib, json, math, pathlib, platform, sys, unittest
sys.dont_write_bytecode = True
root, libr, dll, output = sys.argv[1:5]
original_inventory = len(sys.argv)>5 and sys.argv[5]=='--original'
root = pathlib.Path(root).resolve()
manifest = json.loads(pathlib.Path(__file__).with_name('source-blobs.json').read_text())
assert manifest['pin'] == '63df80a2cf3dd289be95ea3d91667c3490719b75'
for name, expected in manifest['blobs'].items():
    raw = (root/name).read_bytes()
    actual = hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()
    if actual != expected: raise SystemExit('Pinned reference drift: '+name)
C.CDLL(str(pathlib.Path(libr).resolve()), mode=C.RTLD_GLOBAL)
engine = C.CDLL(str(pathlib.Path(dll).resolve()))
loader, system = C.cdll.LoadLibrary, platform.system
try:
    C.cdll.LoadLibrary = lambda _: engine
    platform.system = lambda: 'Darwin'
    sys.path.insert(0, str(root/'pstalgo/python'))
    import pstalgo as pst
finally:
    C.cdll.LoadLibrary, platform.system = loader, system
from pstalgo.createbufferpolygons import SCompareResultsDesc, SRasterToPolygonsDesc, PSTACompareResults, PSTARasterToPolygons
from pstalgo.raster import SRasterData, PSTAGetRasterData

def clean(x):
    if isinstance(x, float) and not math.isfinite(x):
        return 'NaN' if math.isnan(x) else 'Inf' if x > 0 else '-Inf'
    if isinstance(x, list): return [clean(v) for v in x]
    if isinstance(x, dict): return {k:clean(v) for k,v in x.items()}
    return x

def native(case):
    a=case['args']; keep=[]
    def buf(rows, typ):
        flat=[v for row in rows for v in row] if rows and isinstance(rows[0], list) else rows
        b=(typ*max(1,len(flat)))(*flat); keep.append(b)
        return C.cast(b,C.POINTER(typ))
    d=SCompareResultsDesc()
    d.LineCount1=len(a['x']);d.LineCoords1=buf(a['x'],C.c_double);d.Values1=buf(a['values1'],C.c_float)
    d.Values2=buf(a['values2'],C.c_float)
    if 'y' in a: d.LineCount2=len(a['y']);d.LineCoords2=buf(a['y'],C.c_double)
    d.Mode=0 if a['mode']=='normalized' else 1
    d.M=a.get('m',0);d.BlurRadius=a['blur_radius'];d.Resolution=a['resolution']
    h=PSTACompareResults(engine,d)
    if not h: raise RuntimeError('Native comparison failed: '+case['name'])
    try:
        r=SRasterData()
        assert PSTAGetRasterData(engine,d.OutRaster,r)==0
        assert r.Format==2
        values=[list((C.c_float*r.Width).from_address(r.Bits+y*r.Pitch)) for y in range(r.Height)]
        p=SRasterToPolygonsDesc();p.Raster=d.OutRaster
        p.RangeCount=len(case['ranges']);p.Ranges=buf(case['ranges'],C.c_float)
        ph=PSTARasterToPolygons(engine,p)
        if not ph: raise RuntimeError('Native polygon conversion failed: '+case['name'])
        try:
            counts=list(p.OutPolygonCountPerRange[:p.RangeCount]);polygons=[];at=xy=0
            for count in counts:
                group=[]
                for _ in range(count):
                    nr=p.OutPolygonData[at];at+=1;polygon=[]
                    for _ in range(nr):
                        n=p.OutPolygonData[at];at+=1
                        polygon.append([list(p.OutPolygonCoords[2*(xy+i):2*(xy+i)+2]) for i in range(n)])
                        xy+=n
                    group.append(polygon)
                polygons.append(group)
            return clean(dict(bbox=[r.BBMinX,r.BBMinY,r.BBMaxX,r.BBMaxY],
                width=r.Width,height=r.Height,pitch=r.Pitch,format='float',
                min=d.OutMin,max=d.OutMax,values=values,polygon_count=counts,polygons=polygons))
        finally: pst.Free(ph)
    finally: pst.Free(h)

cases=[]
geometries={
    'cross':([[0,0,2,2],[0,2,2,0]],[1,2],[3,4],None),
    'signed':([[0,0,4,1],[0,3,4,2]],[-2,3],[1,-4],None),
    'same':([[0,0,2,2],[0,2,2,0]],[1,2],[1,2],None),
    'two_layers':([[0,0,3,1]],[2],[1,4],[[1,2,4,3],[2,-1,2,4]]),
    'zero_line':([[0,0,0,0],[0,0,2,2]],[5,2],[7,4],None),
    'translated':([[1000000000000,1000000000000,1000000000002,1000000000002]],[1],[2],None),
    'hole':([[0,0,8,0],[8,0,8,8],[8,8,0,8],[0,8,0,0]],[0]*4,[1]*4,None)}
for name,(x,v1,v2,y) in geometries.items():
    for mode in ['normalized','relative_percent']:
        for blur,res in [(1,1),(.25,.5),(2,1),(0,1)]:
            a=dict(x=x,values1=v1,values2=v2,mode=mode,blur_radius=blur,resolution=res,m=.1)
            if y is not None:a['y']=y
            cases.append(dict(name=f'{name}_{mode}_{blur}_{res}',args=a,
                ranges=[[-2,-.1],[-.1,0],[0,.1],[.1,.5],[.5,1],[1,2],[2,1000]]))
for m in [0,-1,1,100]:
    for values in [[0,0],[-1,-2],[1,2]]:
        cases.append(dict(name=f'relative_m_{m}_v_{values[0]}',args=dict(
            x=[[0,0,2,2],[0,2,2,0]],values1=values,values2=[0,2],mode='relative_percent',
            m=m,blur_radius=1,resolution=1),ranges=[[-10000,0],[0,10000]]))
for ranges in [[],[[2,1]],[[1,1]],[[.1,.5],[.1,.5]], [[-math.inf,math.inf]],
               [[-1,0],[0,1],[1,2]], [[0,1],[1,2]]]:
    cases.append(dict(name=f'ranges_{len(cases)}',args=dict(x=[[0,0,2,2],[0,2,2,0]],
        values1=[1,2],values2=[3,4],mode='normalized',blur_radius=1,resolution=1),ranges=ranges))
# These extra fixtures establish the explicitly approved floating contract.
for name, v1, v2, mode in [
    ('floating_zero_denominator', [0,0], [0,0], 'normalized'),
    ('floating_large_values', [0,0], [1e12,2e12], 'normalized'),
    ('floating_overflow', [3e38,1e38], [-3e38,2e38], 'normalized'),
    ('relative_overflow', [0,0], [3e38,2e38], 'relative_percent')]:
    cases.append(dict(name=name,args=dict(x=[[0,0,2,2],[0,2,2,0]],values1=v1,values2=v2,
        mode=mode,m=.1,blur_radius=1,resolution=1),ranges=[[-2,0],[0,1],[1,2]]))

if __name__=='__main__':
    sys.path.insert(0,str(root/'pstalgo/test'))
    from tests.testcreatebufferpolygons import TestCreateBufferPolygons
    suite=unittest.defaultTestLoader.loadTestsFromTestCase(TestCreateBufferPolygons)
    if not unittest.TextTestRunner(stream=sys.stderr).run(suite).wasSuccessful():raise SystemExit(1)
    if original_inventory: cases=cases[:75]
    result=[dict(**clean(case),expected=native(case)) for case in cases]
    pathlib.Path(output).write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')
    print(f'Verified {len(manifest["blobs"])} blobs; upstream smoke test and {len(cases)} native cases passed.')
