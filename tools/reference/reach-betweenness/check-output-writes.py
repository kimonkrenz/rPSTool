#!/usr/bin/env python3
"""Development-only reproduction of pinned Betweenness output-write behaviour.
Usage: check-output-writes.py PINNED_PST_ROOT LIBR_PATH RPST_DLL_PATH
Uses unchanged official ctypes wrappers and exported C API, never rPSTool .Call.
The DLL must be built from verified pristine vendor plus documented build-only
transformations (run tools/verify-vendor.R and repository validation first).
"""
import array, ctypes, hashlib, json, pathlib, platform, sys, unittest
PIN = "63df80a2cf3dd289be95ea3d91667c3490719b75"
BLOBS = {'pstalgo/include/pstalgo/analyses/Reach.h': '2ff22f9799e9cc9290238368b030df23c87341da',
 'pstalgo/src/analyses/Reach.cpp': '4f313cd214125f439de00750ace9d996bc2243ca',
 'pstalgo/python/pstalgo/reach.py': '0ae2cc3e6c8680511dbfc533d1847c65b65910a2',
 'pstalgo/include/pstalgo/analyses/SegmentBetweenness.h': '2dbd06350fd154bbd8f5889502b37b2cb3c26cf0',
 'pstalgo/src/analyses/SegmentBetweenness.cpp': 'fff26fec3ade352e36a8943b038947605e65cd03',
 'pstalgo/python/pstalgo/segmentbetweenness.py': '332fb7138f10c4714bda1951eb55739df68fd3ca',
 'pstalgo/src/BFS.cpp': '8661b3fc712210b968bb9db29f66746aa14047ea',
 'pstalgo/include/pstalgo/BFS.h': 'f28cf9e8c972621e8ac4e11b9628c871bb76b731',
 'pstalgo/src/graph/AxialGraph.cpp': 'c5331259014488f3960c24c79db7c68277a4a80e',
 'pstalgo/include/pstalgo/graph/AxialGraph.h': '0ce07a46978e08c0da1972a561033c83993070fb',
 'pstalgo/src/utils/SphereTree.cpp': '475a30b9dd9f820d753e5a885f4044ad5c4ef9b4',
 'pstalgo/python/pstalgo/common.py': 'a2877a666f7242ac56e6125a487c7334f35b1bad',
 'pstalgo/python/pstalgo/creategraph.py': '7ddeeb5acaad804d1ba07c4b7d04496a45194ec8',
 'pstalgo/python/pstalgo/vector.py': 'dcee17a2f44e99ef996c04601c6c5535f01d2e2c',
 'pstalgo/test/tests/testreach.py': 'beb02c52febf9d2c1065905daf8c7736515e079b',
 'pstalgo/test/tests/testsegmentbetweenness.py': '74ff01812b048969ae23a4cb30d98255aec42b2d',
 'pstalgo/test/tests/common.py': '5012bc7a7f907f63c30def1278e079889ec768bb',
 'pstalgo/test/tests/graphs.py': '30337ddfc24f80e425a41029839c7d1c2e08d997',
 'pstqgis/src/pst/analyses/reachanalysis.py': '0af4cd552be54e98e382d8de5c32e69a357be40b',
 'pstqgis/src/pst/analyses/networkbetweennessanalysis.py': '96a3fbbfccc4f60885019927a2735e0bfb262acd',
 'pstqgis/src/pst/analyses/attractionbetweennessanalysis.py': 'db137f762f9ddd4c4281eddf0a29b5b0b46143af',
 'pstqgis/src/pst/analyses/attractiondistanceanalysis.py': '8c0ab9a1df2050777be8ddaabd1080bf9bdc44cf',
 'pstqgis/src/pst/analyses/memory.py': '84ecc7c401b9c8c9bc12f06cb3ed3233072b318c'}
root, libr, dll = sys.argv[1:]
root = pathlib.Path(root)
for path, expected in BLOBS.items():
    raw = (root / path).read_bytes()
    actual = hashlib.sha1(("blob " + str(len(raw)) + "\0").encode() + raw).hexdigest()
    if actual != expected:
        raise SystemExit("Pinned reference drift: " + path)
print("Verified", len(BLOBS), "exact pinned source/wrapper/test/caller blobs", flush=True)
ctypes.CDLL(libr, mode=ctypes.RTLD_GLOBAL)
engine = ctypes.CDLL(dll)
loader, system = ctypes.cdll.LoadLibrary, platform.system
ctypes.cdll.LoadLibrary = lambda path: engine
platform.system = lambda: "Darwin"
sys.path.insert(0, str(root / "pstalgo/python"))
import pstalgo as pst
ctypes.cdll.LoadLibrary, platform.system = loader, system
sys.path.insert(0, str(root / "pstalgo/test"))
suite = unittest.defaultTestLoader.loadTestsFromNames([
    "tests.testreach", "tests.testsegmentbetweenness"])
if not unittest.TextTestRunner().run(suite).wasSuccessful():
    raise SystemExit("Pinned upstream tests failed")

def arr(kind, values):
    return array.array(kind, values)

# Three unit lines, expanded endpoint pairs exactly as pst_graph() supplies.
graph = pst.CreateGraph(arr('d', [0,0,1,0, 1,0,2,0, 2,0,3,0]), None, None, None, None)
assert graph
try:
    results = []
    for distance in ['WALKING', 'STEPS', 'ANGULAR', 'AXMETER']:
        for name, weights, points, skipped in [
            ('zero_line', [1,0,1], None, [1]),
            ('negative_line', [1,-1,1], None, [1]),
            ('sparse_attraction', None, [0.5,0], [1,2]),
            ('zero_attraction', [0], [0.5,0], [0,1,2])]:
            runs = []
            for seed in [17, 29]:
                score, count, depth = arr('f', [-9]*3), arr('I', [seed]*3), arr('f', [seed]*3)
                pst.SegmentBetweenness(graph, getattr(pst.DistanceType, distance), pst.Radii(),
                    weights=arr('f',weights) if weights is not None else None,
                    attraction_points=arr('d',points) if points is not None else None,
                    out_betweenness=score, out_node_count=count, out_total_depth=depth)
                for i in skipped:
                    assert count[i] == seed and depth[i] == seed
                freeman, syntax = arr('f',[0]*3), arr('f',[0]*3)
                pst.BetweennessNormalize(score,count,3,freeman)
                pst.BetweennessSyntaxNormalize(score,depth,3,syntax)
                runs.append(dict(seed=seed,score=list(score),count=list(count),depth=list(depth),
                                 freeman=list(freeman),syntax=list(syntax)))
            assert runs[0]['score'] == runs[1]['score']
            assert runs[0]['count'] != runs[1]['count']
            assert runs[0]['depth'] != runs[1]['depth']
            if name == 'zero_line':
                assert runs[0]['freeman'] != runs[1]['freeman']
                assert runs[0]['syntax'] != runs[1]['syntax']
            results.append(dict(distance=distance,case=name,runs=runs))
    print(json.dumps(results, indent=2))
    # Point straight-only strict boundary and unchanged circle-area result.
    count, length, area = arr('I',[0]*3), arr('f',[0]*3), arr('f',[0]*3)
    pst.Reach(graph,pst.Radii(straight=1),origin_points=arr('d',[
        -0.4999,0, -0.5,0, -0.5001,0]),
        out_reached_count=count,out_reached_length=length,out_reached_area=area)
    assert list(count) == [1,0,0] and list(length) == [1,0,0]
    assert list(area) == [arr('f',[3.1415927])[0]]*3
    print('Point strict-boundary counts:',list(count),'lengths:',list(length),'areas:',list(area))
finally:
    pst.FreeGraph(graph)
print('Confirmed caller-dependent count/depth outputs for all four distances.')
