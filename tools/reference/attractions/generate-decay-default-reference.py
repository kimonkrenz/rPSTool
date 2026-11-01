#!/usr/bin/env python3
"""Development-only direct oracle for the Attraction Reach nonconstant-decay default.

Usage: generate-decay-default-reference.py PINNED_PST_ROOT LIBR_PATH PST_LIB OUTPUT

Calls the official pinned ctypes wrapper (pstalgo.AttractionReach) against the
pinned engine with weight_func_constant = 1 for power, curve and divide (the
effective value rPSTool uses when decay_constant is not supplied, matching the
original PST for QGIS wizard default C = 1), plus constant = 0, 2 and 3 as
discriminating alternatives. Evidence level: N (engine); application default
selection is evidence level S (attractionreachwiz.py:84-85). No rPSTool code is called.
"""
import array, ctypes, hashlib, json, math, os, pathlib, platform, subprocess, sys
sys.dont_write_bytecode = True
PIN = "63df80a2cf3dd289be95ea3d91667c3490719b75"
FILES = ['pstalgo/python/pstalgo/__init__.py', 'pstalgo/python/pstalgo/attractionreach.py',
         'pstalgo/python/pstalgo/common.py', 'pstalgo/python/pstalgo/creategraph.py',
         'pstalgo/src/analyses/AttractionReach.cpp',
         'pstqgis/src/pst/ui/wizards/attractionreachwiz.py']
root, libr, dll, output = sys.argv[1:]
root = pathlib.Path(root).resolve()
head = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
if head != PIN: raise SystemExit('Pinned PST checkout is %s, expected %s' % (head, PIN))
blobs = {}
for f in FILES:
    raw = (root / f).read_bytes()
    blobs[f] = hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()
    tracked = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD:' + f], text=True).strip()
    if tracked != blobs[f]: raise SystemExit('Pinned file modified in worktree: ' + f)
ctypes.CDLL(libr, mode=ctypes.RTLD_GLOBAL)
engine = ctypes.CDLL(dll)
loader, system = ctypes.cdll.LoadLibrary, platform.system
try:
    ctypes.cdll.LoadLibrary = lambda path: engine
    platform.system = lambda: 'Darwin'
    sys.path.insert(0, str(root / 'pstalgo/python'))
    import pstalgo as pst
finally:
    ctypes.cdll.LoadLibrary, platform.system = loader, system
os.environ['RPST_NUM_THREADS'] = '1'
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'common'))
from rnumeric import r_number

def arr(v, code='d'): return array.array(code, v)
# Small bent network with unequal line lengths; attractions of unequal value.
x = [0, 0, 4, 0, 4, 0, 4, 3, 4, 3, 9, 3, 9, 3, 9, -2]
points = [1, 1, 5, 2, 8, 4]
values = [2.0, 1.0, 3.0]
h = pst.CreateGraph(arr(x))
cases = []
try:
    n = pst.GetGraphInfo(h).m_LineCount
    for decay, mode in [('constant', 0), ('power', 1), ('curve', 2), ('divide', 3)]:
        for const in ([0, 1, 2] if decay != 'constant' else [0, 1]):
            for dist_name, dist, radius in [('steps', 2, dict(steps=2)), ('walking', 1, dict(walking=9)),
                                            ('straight', 0, dict(straight=7))]:
                out = array.array('f', [17] * n)
                pst.AttractionReach(h, origin_type=2, distance_type=dist, radius=pst.Radii(**radius),
                    weight_func=mode, weight_func_constant=const, attraction_points=arr(points),
                    attraction_values=arr(values, 'f'), out_scores=out)
                cases.append(dict(decay=decay, constant=float(const), distance=dist_name,
                                  radius=radius, scores=list(out)))
finally:
    pst.FreeGraph(h)
def rv(v):
    if isinstance(v, dict): return 'list(' + ', '.join(k + '=' + rv(e) for k, e in v.items()) + ')'
    if isinstance(v, list): return 'list(' + ', '.join(rv(e) for e in v) + ')'
    if isinstance(v, str): return json.dumps(v)
    if isinstance(v, float) and (math.isnan(v) or math.isinf(v)): return 'NaN' if math.isnan(v) else ('Inf' if v > 0 else '-Inf')
    return r_number(v)
head_txt = '# Direct pinned PST C API (official ctypes wrapper); evidence level N. Worker cap 1.\n'
for f, sha in sorted(blobs.items()): head_txt += '# %s git blob %s\n' % (f, sha)
graph = dict(x=[x[i:i + 4] for i in range(0, len(x), 4)], points=[points[i:i + 2] for i in range(0, len(points), 2)], values=values)
pathlib.Path(output).write_text(head_txt + 'list(pst_commit=' + rv(PIN) + ', graph=' + rv(graph) +
    ', cases=list(\n  ' + ',\n  '.join(rv(c) for c in cases) + '\n))\n')
print('Wrote %d cases' % len(cases), file=sys.stderr)
