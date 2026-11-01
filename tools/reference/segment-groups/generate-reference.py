#!/usr/bin/env python3
"""Direct pinned exported-C-API structural/numerical fixtures, development only.
Usage: generate-reference.py PINNED_PST_ROOT LIBR_PATH PST_DLL OUTPUT
No rPSTool analysis or replacement numerical formula participates.
"""
import array
import ctypes
import hashlib
import math
import pathlib
import platform
import runpy
import subprocess
import sys

root, libr, dll, output = sys.argv[1:]
reference = pathlib.Path(__file__).with_name('check-output-writes.py')
context = runpy.run_path(str(reference))
PIN, BLOBS = context['PIN'], dict(context['BLOBS'])
# Additional transitive graph/color/traversal authority verified independently
# against GitHub's recursive tree for the same PIN.
EXTRA_BLOBS = {
  "pstalgo/src/graph/SegmentGraph.cpp": "e277e69913e152e46b96de5b87dcb2cc6fe1d9e0",
  "pstalgo/include/pstalgo/graph/SegmentGraph.h": "fbf0067f9e7ac8a473ce90ecdfd23140705d3e35",
  "pstalgo/src/graph/GraphColoring.cpp": "606cb72cdea363c989b343cd935af4144d54a691",
  "pstalgo/include/pstalgo/graph/GraphColoring.h": "e5b7a1188e34fb71ec312c8291ad5f6d25fca67e",
  "pstalgo/src/graph/SimpleGraph.cpp": "a8a77295ed4a09a37998fab7e0102fcd255009e1",
  "pstalgo/include/pstalgo/graph/SimpleGraph.h": "6befb876bdc4fbddc05e14f6e69cf7924f78fa82",
  "pstalgo/include/pstalgo/graph/BFSTraversal.h": "307b33a5ff241ab62af623c0e26ecfe3a1022b3b",
  "pstalgo/include/pstalgo/analyses/Common.h": "ec9e1421d224c957341a22b12eff80974545013e",
  "pstalgo/src/analyses/Common.cpp": "f623c3bea895685a6219ed28c9471cbd4be92329",
  "pstalgo/include/pstalgo/utils/BitVector.h": "76be89ebacf4f6504310acaedf2c57c28f0f3c7b"
}
BLOBS.update(EXTRA_BLOBS)
root = pathlib.Path(root)
for path, expected in BLOBS.items():
    raw = (root/path).read_bytes()
    actual = hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()
    if actual != expected:
        raise SystemExit('Pinned reference drift: '+path)
subprocess.run([sys.executable, str(reference), root, libr, dll], check=True, stdout=subprocess.DEVNULL)
ctypes.CDLL(libr, mode=ctypes.RTLD_GLOBAL)
engine = ctypes.CDLL(dll)
loader, system = ctypes.cdll.LoadLibrary, platform.system
try:
    ctypes.cdll.LoadLibrary = lambda path: engine
    platform.system = lambda: 'Darwin'
    sys.path.insert(0, str(root/'pstalgo/python'))
    import pstalgo as pst
finally:
    ctypes.cdll.LoadLibrary, platform.system = loader, system

points = [[-1,-1],[0,-1],[1,-1],[1,0],[1,1],[0,1],[-1,1],[-1,0],[0,0]]
pairs = [[0,1],[1,2],[2,3],[3,4],[4,5],[5,6],[6,7],[7,0],[3,8],[8,7],[1,8],[8,5]]
networks = {
    'chain': [[i*3,0,(i+1)*3,0] for i in range(5)],
    'square': [[0,0,3,0],[3,0,3,3],[3,3,0,3],[0,3,0,0]],
    'crosshair': [points[a]+points[b] for a,b in pairs],
    'angle_90plus': [[0,0,-1,0],[-1,0.01,0,0]],
    'angle_junction': [[0,0,-1,0],[-1,0.01,0,0],[0,0,1,1]],
    'isolated': [[0,0,1,0]],
    'disconnected': [[0,0,1,0],[5,0,6,0]],
    'mixed': [[0,0,1,0],[1,0,2,0],[2,0,3,0],[10,0,11,0]],
    'bent': [[0,0,3,0],[3,0,6,1],[6,1,6,4]],
    'high_degree': [[0,0,i,1] for i in range(1,41)],
    'reversed': [[3,3,0,3],[3,0,3,3],[3,0,0,0]],
    'translated': [[1e9,1e9,1e9+3,1e9],[1e9+3,1e9,1e9+6,1e9]],
}
settings = {
    'chain': [(0,False),(1,True)],
    'square': [(89,False),(89,True),(90,False),(90,True)],
    'crosshair': [(89,False),(89,True),(90,False),(180,False)],
    'angle_90plus': [(100,False),(180,False),(100,True),(180,True),(181,False)],
    'angle_junction': [(90,False),(90,True)],
    'isolated': [(1,False)], 'disconnected': [(1,False)], 'mixed': [(1,False),(1,True)],
    'bent': [(0,False),(20,False),(90,True)], 'high_degree': [(89,True)],
    'reversed': [(89,False),(90,True)], 'translated': [(1,False)],
}
explicit = {
    'chain': [[0,1,2,3,4],[0,1,1,1,2],[4,3,2,1,0],[0,2,2,2,4]],
    'crosshair': [[0,0,1,1,2,2,3,3,4,5,6,7]],
    'mixed': [[0,1,2,3],[3,2,1,0]],
    'disconnected': [[0,0]],
}
radii = [{}, {'walking':0}, {'walking':1}, {'walking':3}, {'walking':9},
         {'steps':0}, {'steps':1}, {'steps':2}, {'walking':3,'steps':0},
         {'walking':0,'steps':2}]
groupings, integrations = [], []

def equal(a,b):
    return len(a)==len(b) and all(x==y or isinstance(x,float) and isinstance(y,float) and math.isnan(x) and math.isnan(y) for x,y in zip(a,b))

for name, rows in networks.items():
    segment = pst.CreateSegmentGraph(array.array('d',[x for row in rows for x in row]),None,None)
    assert segment
    configurations = []
    try:
        for angle, split in settings[name]:
            ids, colors = array.array('I',[0]*len(rows)),array.array('I',[0]*len(rows))
            ng, nc = pst.SegmentGrouping(segment,angle,split,ids,colors)
            assert 1 <= nc <= ng <= len(rows)
            assert set(ids)==set(range(ng))
            assert all(c < nc for c in colors)
            groupings.append(dict(network=name,angle=angle,split=split,
                                  ids=[v+1 for v in ids],colors=[v+1 for v in colors],
                                  n_groups=ng,n_colors=nc))
            if list(ids) not in configurations: configurations.append(list(ids))
        for ids in explicit.get(name,[]):
            if ids not in configurations: configurations.append(ids)
        for ids in configurations:
            n = max(ids)+1
            group = pst.CreateSegmentGroupGraph(segment,array.array('I',ids),n)
            assert group
            try:
                for radius in radii:
                    runs = []
                    for count_seed, depth_seed, score_seed in [(2**32-1,-math.inf,17), (2**32-2,-1,math.nan)]:
                        scores, counts, depths = array.array('f',[score_seed]*n),array.array('I',[count_seed]*n),array.array('f',[depth_seed]*n)
                        pst.SegmentGroupIntegration(group,pst.Radii(**radius),out_integration=scores,
                                                    out_node_counts=counts,out_total_depths=depths)
                        written = [v != count_seed for v in counts]
                        assert written == [v != depth_seed for v in depths]
                        assert all(not ok or c <= n for c,ok in zip(counts,written))
                        # Adopted wrapper policy only. No integration score sentinel.
                        runs.append(([v if ok else None for v,ok in zip(scores,written)],
                                     [v if ok else None for v,ok in zip(counts,written)],
                                     [v if ok else None for v,ok in zip(depths,written)]))
                    assert all(equal(a,b) for a,b in zip(runs[0],runs[1]))
                    score,count,depth = runs[0]
                    integrations.append(dict(network=name,ids=[v+1 for v in ids],radius=radius,
                                             integration=score,node_count=count,total_depth=depth))
            finally:
                pst.FreeSegmentGroupGraph(group)
    finally:
        pst.FreeSegmentGraph(segment)

import sys as _sys, pathlib as _pathlib
_sys.path.insert(0, str(_pathlib.Path(__file__).resolve().parents[1] / 'common'))
from rnumeric import r_number  # exact R numeric literals (development-only helper)
def r(v):
    if v is None: return 'NA_real_'
    if isinstance(v,bool): return 'TRUE' if v else 'FALSE'
    if isinstance(v,str): return '"'+v+'"'
    if isinstance(v,dict): return 'list('+', '.join(k+'='+r(x) for k,x in v.items())+')'
    if isinstance(v,list):
        return ('list(' if v and isinstance(v[0],(list,dict)) else 'c(')+', '.join(r(x) for x in v)+')'
    if isinstance(v,float):
        if math.isnan(v): return 'NaN'
        if v==math.inf: return 'Inf'
        if v==-math.inf: return '-Inf'
    return r_number(v)
header = '# Direct PST v3.3.2 C API; generated by tools/reference/segment-groups/generate-reference.py.\n'
header += '# Only unwritten rows use the explicitly adopted NA policy; numeric values are PST outputs.\n'
for path,blob in BLOBS.items(): header += '# '+path+' git blob '+blob+'\n'
text = header+'list(pst_commit="'+PIN+'",\n networks='+r(networks)+',\n groupings=list(\n '
text += ',\n '.join(r(x) for x in groupings)+'),\n integrations=list(\n '
text += ',\n '.join(r(x) for x in integrations)+'))\n'
pathlib.Path(output).write_text(text)
print('Verified',len(BLOBS),'blobs; recorded',len(groupings),'groupings and',len(integrations),'integrations; diagnostic masks/seeds agree.')
