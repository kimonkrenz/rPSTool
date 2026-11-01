#!/usr/bin/env python3
"""Direct pinned C API reference for multi-radius families of the angular analyses; development only.
Usage: generate-multi-radius-reference.py PINNED_ROOT LIBR_PATH PST_DLL OUTPUT

Every number comes from the pinned exported C API (PSTAAngularChoice / PSTAAngularIntegration and their exported
normalisers), called once per radius exactly as the single-radius reference does. rPSTool analyses are never invoked. The
source-blob authority is the BLOBS table of generate-reference.py in this directory (parsed, not copied), so there is one
pin list. Each family fixes all radius fields but one; the test calls rPSTool once with the vector of radii and compares
every column with the corresponding direct result.
"""
import array,ast,hashlib,json,math,os,pathlib,platform,sys,ctypes
sys.dont_write_bytecode=True
here=pathlib.Path(__file__).resolve().parent
source=(here/'generate-reference.py').read_text()
tree=ast.parse(source)
PIN=next(ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign) and isinstance(n.targets[0],ast.Name) and n.targets[0].id=='PIN')
BLOBS=next(ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign) and isinstance(n.targets[0],ast.Name) and n.targets[0].id=='BLOBS')
root,libr,dll,output=sys.argv[1:];root=pathlib.Path(root).resolve()
for path,expected in BLOBS.items():
    raw=(root/path).read_bytes()
    if hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()!=expected:
        raise SystemExit('Pinned reference drift: '+path)
os.environ['RPST_NUM_THREADS']='1'
ctypes.CDLL(libr,mode=ctypes.RTLD_GLOBAL);engine=ctypes.CDLL(dll)
loader,system=ctypes.cdll.LoadLibrary,platform.system
try:
    ctypes.cdll.LoadLibrary=lambda path:engine;platform.system=lambda:'Darwin'
    sys.path.insert(0,str(root/'pstalgo/python'));import pstalgo as pst
finally:ctypes.cdll.LoadLibrary,platform.system=loader,system
# rv(): exact R literals, shared with the single-radius generator (same tail of that script).
sys.path.insert(0,str(here.parent/'common'))
from rnumeric import r_number
def rv(v):
    if isinstance(v,dict):return 'list('+', '.join(k+'='+rv(x) for k,x in v.items())+')'
    if isinstance(v,list):return 'list('+', '.join(rv(x) for x in v)+')'
    if isinstance(v,str):return json.dumps(v)
    if isinstance(v,bool):return 'TRUE' if v else 'FALSE'
    if isinstance(v,float):
        if math.isnan(v):return 'NaN'
        if math.isinf(v):return 'Inf' if v>0 else '-Inf'
    return r_number(v)
mesh=[[0,0,3,0],[3,0,6,0],[0,3,3,3],[3,3,6,3],[0,6,3,6],[3,6,6,6],[0,0,0,3],[0,3,0,6],[3,0,3,3],[3,3,3,6],
      [6,0,6,3],[6,3,6,6],[3,3,6,6],[6,6,9,7]]
graphs=[dict(name='mesh',x=mesh),
 dict(name='isolated',x=[[0,0,1,0],[10,0,12,0]]),
 dict(name='zero_length',x=[[0,0,0,0],[3,0,5,0]]),
 dict(name='large_star',x=[[0,0,4e18*math.cos(i*math.pi/4),4e18*math.sin(i*math.pi/4)] for i in range(8)])]
families=[('walking',[2.5,8.0,30.0],{}),('steps',[3,1,2],{'angular':180.0}),('angular',[135.0,45.0],{'walking':40.0}),
          ('straight',[10.0,0.0,4.0],{})]
# large_star has coordinates of 4e18: only radii of that order reach other spokes (its weighted Hillier values are
# non-finite in PST, which gives the multi-result tests genuine native NaN/Inf to pass through)
large_values={'walking':[1e19,6e18,2e18],'straight':[1e19,0.0,5e18]}
settings=[(0,1),(20,3),(90,7)]
def run(h,n,routine,radius,weighted,threshold,precision):
    outputs=[]
    for seed in [17,29]:
        counts=array.array('I',[seed]*n);depths=array.array('f',[seed]*n)
        weights=array.array('f',[seed]*n);depth_weights=array.array('f',[seed]*n);scores=array.array('f',[seed]*n)
        args=dict(graph_handle=h,radius=pst.Radii(**radius),weigh_by_length=weighted,angle_threshold=threshold,angle_precision=precision)
        if routine=='integration':
            pst.AngularIntegration(**args,out_node_counts=counts,out_total_depths=depths,out_total_weights=weights,out_total_depth_weights=depth_weights)
        else:
            pst.AngularChoice(**args,out_choice=scores,out_node_count=counts,out_total_depth=depths,out_total_depth_weight=depth_weights)
        values=[counts,depths,depth_weights]+([weights] if routine=='integration' else [scores])
        outputs.append([v.tobytes() for v in values])
    assert outputs[0]==outputs[1],(routine,radius)
    normalized={}
    for norm in (['turner','syntax','hillier'] if routine=='integration' else ['standard','turner','syntax']):
        result=array.array('f',[17]*n)
        if routine=='integration':
            suffix={'turner':'Normalize','syntax':'SyntaxNormalize','hillier':'HillierNormalize'}[norm]
            fn=getattr(pst,'AngularIntegration'+suffix+('LengthWeight' if weighted else ''))
            fn(weights if weighted else counts,depth_weights if weighted else depths,n,result)
        elif norm=='standard':pst.StandardNormalize(scores,n,result)
        elif norm=='turner':pst.AngularChoiceNormalize(scores,counts,n,result)
        else:pst.AngularChoiceSyntaxNormalize(scores,depth_weights if weighted else depths,n,result)  # QGIS plugin: angularchoiceanalysis.py l.128 (weighted) / l.177
        normalized[norm]=list(result)
    case=dict(counts=list(counts),depths=list(depths),depth_weights=list(depth_weights),normalized=normalized)
    if routine=='integration':case['weights']=list(weights)
    else:case['scores']=list(scores)
    return case
out=[]
for graph in graphs:
    n=len(graph['x']);h=pst.CreateSegmentGraph(array.array('d',[v for row in graph['x'] for v in row]),None,None)
    assert h,graph['name']
    try:
        for vary,values,fixed in families:
            if graph['name']=='large_star' and vary in large_values:values=large_values[vary]
            if graph['name']!='mesh' and vary not in ('walking','straight'):continue
            for weighted in [False,True]:
                for threshold,precision in settings:
                    for routine in ['choice','integration']:
                        runs=[]
                        for v in values:
                            radius=dict(fixed);radius[vary]=v
                            runs.append(run(h,n,routine,radius,weighted,threshold,precision))
                        out.append(dict(graph=graph['name'],routine=routine,weighted=weighted,threshold=threshold,
                                        precision=precision,vary=vary,values=values,fixed=fixed,runs=runs))
    finally:pst.FreeSegmentGraph(h)
header='# Direct pinned exported C API multi-radius angular families; no rPSTool .Call.\n'
for path,sha in sorted(BLOBS.items()):header+='# '+path+' git blob '+sha+'\n'
graph_defs={g['name']:g['x'] for g in graphs}
pathlib.Path(output).write_text(header+'list(pst_commit='+rv(PIN)+', graphs='+rv(graph_defs)+', families=list(\n  '+',\n  '.join(rv(c) for c in out)+'\n))\n')
print('Verified '+str(len(BLOBS))+' pinned blobs; '+str(len(out))+' families',file=sys.stderr)
