#!/usr/bin/env python3
"""Development-only pinned exported-C-API fixture generator.
Usage: generate-reference.py PINNED_PST_ROOT LIBR_PATH RPST_DLL_PATH OUTPUT
First runs the retained exact-blob/sentinel investigation and upstream tests.
No rPSTool .Call analysis participates. Missing diagnostics follow the explicitly
adopted wrapper policy; every numerical value comes from a pinned PST export.
"""
import array, math, pathlib, runpy, sys
root, libr, dll, output = sys.argv[1:]
argv = sys.argv
sys.argv = [str(pathlib.Path(__file__).with_name('check-output-writes.py')), root, libr, dll]
reference = runpy.run_path(sys.argv[0])
sys.argv = argv
pst, arr = reference['pst'], reference['arr']
PIN, BLOBS = reference['PIN'], reference['BLOBS']
networks = {
    'chain': [[0,0,1,0], [1,0,2,0], [2,0,3,0]],
    'bent': [[0,0,3,0], [3,0,3,3], [3,3,6,3], [6,3,9,3]],
    'single': [[0,0,1,0]]}
radii = [{}, {'straight':3}, {'walking':3}, {'steps':1}, {'angular':100},
         {'axmeter':10}, {'straight':6,'walking':6,'steps':2,'angular':190,'axmeter':30}]
cases = []

def flat(rows):
    return [v for row in rows for v in row]

def reach(graph, network, origins, radius, name):
    n = len(origins)
    count, length, area = arr('I',[0]*n), arr('f',[0]*n), arr('f',[0]*n)
    pst.Reach(graph,pst.Radii(**radius),origin_points=arr('d',flat(origins)),
              out_reached_count=count,out_reached_length=length,out_reached_area=area)
    cases.append(dict(routine='reach',network=network,name=name,points=origins,radius=radius,
                      count=list(count),score=list(length),depth=list(area)))

def betweenness(graph, network, weights, points, radius, distance, name):
    n = len(networks[network])
    # Two different impossible initialization pairs verify buffer-independent
    # numerical outputs and the same actual-write masks before recording a case.
    runs = []
    for count_seed, depth_seed in [(2**32-1, -math.inf), (2**32-2, -1.0)]:
        score, count, depth = arr('f',[-9]*n), arr('I',[count_seed]*n), arr('f',[depth_seed]*n)
        pst.SegmentBetweenness(graph,getattr(pst.DistanceType,distance.upper()),pst.Radii(**radius),
            weights=arr('f',weights) if weights is not None else None,
            attraction_points=arr('d',flat(points)) if points is not None else None,
            out_betweenness=score,out_node_count=count,out_total_depth=depth)
        written = [v != count_seed for v in count]
        assert written == [v != depth_seed for v in depth]
        runs.append((list(score), [v if ok else None for v,ok in zip(count,written)],
                     [v if ok else None for v,ok in zip(depth,written)], written))
    assert runs[0] == runs[1]
    scores, counts, depths, written = runs[0]
    norms = {}
    standard = arr('f',[0]*n)
    pst.StandardNormalize(arr('f',scores),n,standard)
    norms['standard'] = list(standard)
    indices = [i for i,ok in enumerate(written) if ok]
    for name_norm in ['freeman','syntax']:
        defined = arr('f',[0]*len(indices))
        if indices:
            if name_norm == 'freeman':
                pst.BetweennessNormalize(arr('f',[scores[i] for i in indices]),
                    arr('I',[counts[i] for i in indices]),len(indices),defined)
            else:
                pst.BetweennessSyntaxNormalize(arr('f',[scores[i] for i in indices]),
                    arr('f',[depths[i] for i in indices]),len(indices),defined)
        normalized = [None]*n
        for i,v in zip(indices,defined): normalized[i] = v
        norms[name_norm] = normalized
    cases.append(dict(routine='betweenness',network=network,name=name,points=points,
        weights=weights,radius=radius,distance=distance,count=counts,score=scores,
        depth=depths,normalizations=norms))

for network, rows in networks.items():
    graph = pst.CreateGraph(arr('d',flat(rows)),None,None,None,None)
    assert graph
    try:
        if network == 'chain':
            for radius in [{}, {'straight':1}, {'straight':0}, {'walking':0}, {'walking':1},
                           {'steps':0}, {'steps':1}, {'angular':0}, {'axmeter':2},
                           {'straight':1,'steps':1}, {'straight':1,'walking':1}]:
                reach(graph,network,[[0.5,0],[2.5,0],[0.5,2]],radius,'on-and-away')
            reach(graph,network,[[-0.4999,0],[-0.5,0],[-0.5001,0]],{'straight':1},'strict-boundary')
            variants = [('unit-lines',[1,1,1],None),('unequal-lines',[2,3,4],None),
                ('zero-line',[1,0,1],None),('negative-line',[1,-1,1],None),
                ('negative-raw',[1,-10,1],None),('fractional-lines',[1.1,2.2,3.3],None),
                ('zero-lines',[0,0,0],None),('negative-lines',[-1,-2,-3],None),
                ('sparse-unit',None,[[0.5,0]]),('sparse-zero',[0],[[0.5,0]]),
                ('same-line-unit',None,[[0.25,0],[0.75,0],[2.5,0]]),
                ('same-line-explicit-unit',[1,1,1],[[0.25,0],[0.75,0],[2.5,0]]),
                ('same-line-unequal',[2,3,4],[[0.25,0],[0.75,0],[2.5,0]]),
                ('same-line-permuted',[4,2,3],[[2.5,0],[0.25,0],[0.75,0]]),
                ('attraction-cancellation',[1,-1,2],[[0.25,0],[0.75,0],[2.5,0]]),
                ('away-attractions',None,[[0.5,2],[2.5,-2]]),
                ('all-lines-attracted',None,[[0.5,0],[1.5,0],[2.5,0]])]
            for distance in ['walking','steps','angular','axmeter']:
                for name, weights, points in variants:
                    betweenness(graph,network,weights,points,{},distance,name)
        elif network == 'bent':
            for radius in radii:
                reach(graph,network,[[7.5,3],[1.5,0],[3,2],[1,2]],radius,'ordered-points')
                for distance in ['walking','steps','angular','axmeter']:
                    for name, weights, points in [
                        ('unequal-lines',[1,2,3,4],None),
                        ('unequal-attractions',[2,3,4],[[1.5,0],[3,2],[7.5,4]])]:
                        betweenness(graph,network,weights,points,radius,distance,name)
        else:
            for distance in ['walking','steps','angular','axmeter']:
                betweenness(graph,network,[2],None,{},distance,'self-contribution')
    finally:
        pst.FreeGraph(graph)

import sys as _sys, pathlib as _pathlib
_sys.path.insert(0, str(_pathlib.Path(__file__).resolve().parents[1] / 'common'))
from rnumeric import r_number  # exact R numeric literals (development-only helper)
def r_value(v):
    if v is None: return 'NA_real_' # diagnostics; optional inputs use NULL below
    if isinstance(v,dict): return 'list('+', '.join(k+'='+('NULL' if x is None else r_value(x)) for k,x in v.items())+')'
    if isinstance(v,list):
        return 'list('+', '.join(r_value(x) for x in v)+')' if v and isinstance(v[0],list) else 'c('+', '.join(r_value(x) for x in v)+')'
    if isinstance(v,str): return '"'+v+'"'
    if isinstance(v,float):
        if math.isnan(v): return 'NaN'
        if v == math.inf: return 'Inf'
        if v == -math.inf: return '-Inf'
    return r_number(v)
header = '# Direct pinned C API through official wrappers; tools/reference/reach-betweenness/generate-reference.py.\n'
header += '# Missing diagnostics use the adopted rPSTool NA policy; numbers are PST outputs.\n'
for path,blob in BLOBS.items(): header += '# '+path+' git blob '+blob+'\n'
text = 'list(pst_commit="'+PIN+'",\n  networks='+r_value(networks)+',\n  cases=list(\n    '
text += ',\n    '.join(r_value(case) for case in cases)+'\n  ))\n'
pathlib.Path(output).write_text(header+text)
print('Recorded',len(cases),'optional-mode numerical cases; both sentinel pairs agreed.')
