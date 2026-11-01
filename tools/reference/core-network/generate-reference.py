#!/usr/bin/env python3
"""Development only: pinned official wrappers -> exported C API -> R fixture.
Usage: generate-reference.py PINNED_PST_ROOT LIBR_PATH RPST_DLL_PATH OUTPUT
PST source must be the exact pinned archive. Linux loader adaptation is isolated
here: unchanged wrappers otherwise only recognize Windows/macOS filenames.
The native DLL contains pinned core plus documented build transformations; no
rPSTool .Call analysis or R calculation participates in this oracle generation.
"""
import array, ctypes, hashlib, pathlib, platform, sys, unittest
root, libr, dll, output = sys.argv[1:]
root = pathlib.Path(root)
pinned_blobs = {'python/pstalgo/common.py': 'a2877a666f7242ac56e6125a487c7334f35b1bad',
 'python/pstalgo/reach.py': '0ae2cc3e6c8680511dbfc533d1847c65b65910a2',
 'python/pstalgo/segmentbetweenness.py': '332fb7138f10c4714bda1951eb55739df68fd3ca',
 'python/pstalgo/angularchoice.py': 'a34eb2dd27cd071fd0aac8df76539527e68085b5',
 'python/pstalgo/networkintegration.py': '5a41c2c2eb3c83baacd7148c8224b2e233f98289',
 'python/pstalgo/angularintegration.py': '3ce39247e2a31b41ebcdb3c5eb9e5cb0548d41c8',
 'test/tests/common.py': '5012bc7a7f907f63c30def1278e079889ec768bb',
 'test/tests/graphs.py': '30337ddfc24f80e425a41029839c7d1c2e08d997',
 'test/tests/testreach.py': 'beb02c52febf9d2c1065905daf8c7736515e079b',
 'test/tests/testsegmentbetweenness.py': '74ff01812b048969ae23a4cb30d98255aec42b2d',
 'test/tests/testangularchoice.py': '3bd2bcfab1d3e9942ad4102d3a3b56b7f5221f33',
 'test/tests/testnetworkintegration.py': '2654a0f39a633de1b489a811b9146e9c171192ac',
 'test/tests/testangularintegration.py': '3e162e77ae3319f8c030944d3b8bcc059834069b'}
for path, expected in pinned_blobs.items():
    raw = (root / "pstalgo" / path).read_bytes()
    actual = hashlib.sha1(("blob "+str(len(raw))+"\0").encode()+raw).hexdigest()
    if actual != expected: raise SystemExit("Pinned reference drift: "+path)
ctypes.CDLL(libr, mode=ctypes.RTLD_GLOBAL)
engine = ctypes.CDLL(dll)
loader, system = ctypes.cdll.LoadLibrary, platform.system
ctypes.cdll.LoadLibrary = lambda path: engine
platform.system = lambda: "Darwin"
sys.path.insert(0, str(root / "pstalgo/python"))
import pstalgo as pst
ctypes.cdll.LoadLibrary, platform.system = loader, system
sys.path.insert(0, str(root / "pstalgo/test"))
# Run original upstream numerical tests unmodified, not our fixture comparisons.
suite = unittest.defaultTestLoader.loadTestsFromNames([
    "tests.testreach", "tests.testsegmentbetweenness", "tests.testangularchoice",
    "tests.testnetworkintegration", "tests.testangularintegration"])
if not unittest.TextTestRunner().run(suite).wasSuccessful():
    raise SystemExit("Pinned upstream tests failed")

rows = [[0,0,3,0], [3,0,3,3], [3,3,6,3], [6,3,9,3]]
coords = array.array('d', [v for row in rows for v in row])
a = pst.CreateGraph(coords, None, None, None, None)
s = pst.CreateSegmentGraph(coords, None, None)
assert a and s
cases = []
radii = [{}, {'straight':3}, {'walking':3}, {'steps':1}, {'angular':100},
         {'axmeter':10}, {'straight':6,'walking':6,'steps':2,'angular':190,'axmeter':30}]
for routine in ['reach','betweenness','integration','angular_choice','angular_integration']:
    for radius in radii:
        if routine.startswith('angular_') and 'axmeter' in radius:
            if len(radius)==1: continue
            radius = {k:v for k,v in radius.items() if k!='axmeter'}
        for distance in (['walking','steps','angular','axmeter'] if routine=='betweenness' else ['steps']):
            for weighted in ([False,True] if routine=='angular_choice' else [False]):
                count = array.array('I',[0]*4)
                depth, score, extra = [array.array('f',[0]*4) for _ in range(3)]
                r = pst.Radii(**radius)
                if routine=='reach':
                    pst.Reach(a,r,out_reached_count=count,out_reached_length=score,out_reached_area=depth)
                elif routine=='betweenness':
                    pst.SegmentBetweenness(a,getattr(pst.DistanceType,distance.upper()),r,
                        out_betweenness=score,out_node_count=count,out_total_depth=depth)
                elif routine=='integration':
                    pst.NetworkIntegration(a,r,out_line_integration=score,out_line_node_count=count,out_line_total_depth=depth)
                elif routine=='angular_choice':
                    pst.AngularChoice(s,r,weigh_by_length=weighted,out_choice=score,
                        out_node_count=count,out_total_depth=depth,out_total_depth_weight=extra if weighted else None)
                else:
                    pst.AngularIntegration(s,r,out_node_counts=count,out_total_depths=depth)
                    pst.AngularIntegrationNormalize(count,depth,4,score)
                norms = {}
                if routine in ['betweenness','angular_choice']:
                    normalized = array.array('f',[0]*4)
                    pst.StandardNormalize(score,4,normalized); norms['standard']=list(normalized)
                    if routine=='betweenness':
                        pst.BetweennessNormalize(score,count,4,normalized); norms['freeman']=list(normalized)
                        pst.BetweennessSyntaxNormalize(score,depth,4,normalized)
                    else:
                        pst.AngularChoiceNormalize(score,count,4,normalized); norms['turner']=list(normalized)
                        pst.AngularChoiceSyntaxNormalize(score,extra if weighted else depth,4,normalized)
                    norms['syntax']=list(normalized)
                cases.append(dict(routine=routine,radius=radius,distance=distance,weighted=weighted,
                    count=list(count),score=list(score),depth=list(depth),extra=list(extra),normalizations=norms))
pst.FreeGraph(a);pst.FreeSegmentGraph(s)

import sys as _sys, pathlib as _pathlib
_sys.path.insert(0, str(_pathlib.Path(__file__).resolve().parents[1] / 'common'))
from rnumeric import r_number  # exact R numeric literals (development-only helper)
def r_value(v):
    if isinstance(v,dict): return 'list('+', '.join(k+'='+r_value(x) for k,x in v.items())+')'
    if isinstance(v,list): return 'list('+', '.join(r_value(x) for x in v)+')' if v and isinstance(v[0],(dict,list)) else 'c('+', '.join(r_value(x) for x in v)+')'
    if isinstance(v,str): return '"'+v+'"'
    if isinstance(v,bool): return 'TRUE' if v else 'FALSE'
    if isinstance(v,float):
        if v != v: return 'NaN'
        if v==float('inf'): return 'Inf'
        if v==float('-inf'): return '-Inf'
    return r_number(v)
files = ['python/pstalgo/'+n+'.py' for n in ['common','reach','segmentbetweenness','angularchoice','networkintegration','angularintegration']]
files += ['test/tests/'+n+'.py' for n in ['common','graphs','testreach','testsegmentbetweenness','testangularchoice','testnetworkintegration','testangularintegration']]
header = '# Direct pinned C API through official wrappers; tools/reference/core-network/generate-reference.py.\n'
for f in files:
    raw=(root/'pstalgo'/f).read_bytes()
    blob=hashlib.sha1(('blob '+str(len(raw))+'\0').encode()+raw).hexdigest()
    header+='# '+f+' git blob '+blob+'\n'
fixture=dict(pst_commit='63df80a2cf3dd289be95ea3d91667c3490719b75',rows=rows,cases=cases)
text = 'list(pst_commit='+r_value(fixture['pst_commit'])+',\n  rows='+r_value(rows)+',\n  cases=list(\n    '+',\n    '.join(r_value(case) for case in cases)+'\n  ))\n'
pathlib.Path(output).write_text(header+text)
