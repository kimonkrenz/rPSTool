#!/usr/bin/env python3
"""Development-only supported attraction C-API oracle; official pinned PST exports only.
Usage: generate-reference.py PINNED_PST_ROOT LIBR_PATH PST_DLL OUTPUT
No replacement computation, rPSTool .Call, or writes into the reference checkout.
"""
import array, ctypes, hashlib, json, math, pathlib, platform, sys, unittest
sys.dont_write_bytecode = True
PIN = "63df80a2cf3dd289be95ea3d91667c3490719b75"
BLOBS = {'pstalgo/CMakeLists.txt': '6daa31c7d8d85d81750f865fa5a943795bd778e5',
 'pstalgo/README.txt': '3eb6d17d11318173567063d29ca398ee591cb386',
 'pstalgo/include/pstalgo/BFS.h': 'f28cf9e8c972621e8ac4e11b9628c871bb76b731',
 'pstalgo/include/pstalgo/Debug.h': '6b85862abe7ff4c2ddf67d2020c97cf39eb3b8b5',
 'pstalgo/include/pstalgo/Error.h': 'c3040bb5f6f7175e74779f95c12ed9b18a826c3d',
 'pstalgo/include/pstalgo/Limits.h': '40e4ac0e16724adeeefd29d849f1697227be589a',
 'pstalgo/include/pstalgo/Raster.h': 'faf13cb535c09b34e10bce9ddf70e69ee0f8755f',
 'pstalgo/include/pstalgo/Types.h': '3687baabfc75cebc257c417723a0047f11992911',
 'pstalgo/include/pstalgo/Vec2.h': '4c471e512f8b2fb76b7c23bab606340cf5cfebab',
 'pstalgo/include/pstalgo/analyses/AngularChoice.h': 'f147e6c632090630e4f8c0eec3bf679ff9b4f66f',
 'pstalgo/include/pstalgo/analyses/AngularIntegration.h': '29a5e940da508004f48bb0116378e00534c087bc',
 'pstalgo/include/pstalgo/analyses/AttractionDistance.h': '8de9a0c5e8eead63d9bcf6d3e8e7c22e5b87d710',
 'pstalgo/include/pstalgo/analyses/AttractionReach.h': '12a20ebf81a3d97b243f1e54c93c3e0493da6aeb',
 'pstalgo/include/pstalgo/analyses/CalculateIsovists.h': '450746407426054a30f2f948c74240a88fc7561b',
 'pstalgo/include/pstalgo/analyses/Common.h': 'ec9e1421d224c957341a22b12eff80974545013e',
 'pstalgo/include/pstalgo/analyses/CreateBufferPolygons.h': '0552e566ff35ef5e1f1437a0567aa8e829a68e5d',
 'pstalgo/include/pstalgo/analyses/CreateGraph.h': 'ab0eda724c0df4bd20e3ed42506cd3dbad0aaa75',
 'pstalgo/include/pstalgo/analyses/CreateJunctions.h': 'f71b30c21be2016337a63ff0dfa8865a296ee09b',
 'pstalgo/include/pstalgo/analyses/CreateSegmentMap.h': '228a261a30992b349e57aa367685c226ad59a82c',
 'pstalgo/include/pstalgo/analyses/NetworkIntegration.h': '7ef36cb1ba6690700b8443338fb2cde54e98dc4c',
 'pstalgo/include/pstalgo/analyses/ODBetweenness.h': '190762734bf433d4a414fc968d6a071345e727e8',
 'pstalgo/include/pstalgo/analyses/RasterToPolygons.h': '4325ed0238f3fa70bf790649bc7199d105e5cfff',
 'pstalgo/include/pstalgo/analyses/Reach.h': '2ff22f9799e9cc9290238368b030df23c87341da',
 'pstalgo/include/pstalgo/analyses/SegmentBetweenness.h': '2dbd06350fd154bbd8f5889502b37b2cb3c26cf0',
 'pstalgo/include/pstalgo/analyses/SegmentGroupIntegration.h': 'd1b8dea2ae3c64da04aeac3f94261a06a6102be6',
 'pstalgo/include/pstalgo/analyses/SegmentGrouping.h': '26eea3469c720a8223337a23b16ccfa067c05ee7',
 'pstalgo/include/pstalgo/analyses/VisualConnectivity.h': 'ff3bf0d95062772610f6d0ff00649439a191ab18',
 'pstalgo/include/pstalgo/experimental/ArrayView.h': '03c8092876643478d884e2e7a6130006cc85b7f3',
 'pstalgo/include/pstalgo/experimental/DirectedMultiDistanceGraph.h': '50dc9b8236418d9cbc8cec537b54bd0f5dc38804',
 'pstalgo/include/pstalgo/experimental/FastSegmentBetweenness.h': 'd2174ee3ed4a59a22263e70d84b5acdae99ba4b0',
 'pstalgo/include/pstalgo/experimental/IntPrioQueue.h': '38bd288d65f0582fdd48690fa9cf3bf224051bc4',
 'pstalgo/include/pstalgo/experimental/ShortestPathTraversal.h': '2d2016328108b5abe8a4d95f22527f6ae5da8041',
 'pstalgo/include/pstalgo/experimental/SparseDirectedGraph.h': 'fda9a9dd42aa11b450e2bd40519da00bb9565daf',
 'pstalgo/include/pstalgo/experimental/StraightLineMinDistance.h': '88a25ff8dd9d013c4d2072a87987e692305bf8e3',
 'pstalgo/include/pstalgo/geometry/AABSPTree.h': 'ba6ff35092d01e0d17ef0c9c3f947ed9fae9c01a',
 'pstalgo/include/pstalgo/geometry/ConvexHull.h': '71591492e145fcf300c2816bf43ad337ff133ca2',
 'pstalgo/include/pstalgo/geometry/Geometry.h': 'a1c51401559d4473199c8b5638324b5ec9e6e9f9',
 'pstalgo/include/pstalgo/geometry/IsovistCalculator.h': '403f08bec04b544d4c0ead6a8d92c5414d32557a',
 'pstalgo/include/pstalgo/geometry/LooseBspTree.h': '2a49e97487eefb3734010758084e556a36e333ab',
 'pstalgo/include/pstalgo/geometry/Plane2D.h': '9fe7c828bb351b956bb2c74c43d8439cc6242633',
 'pstalgo/include/pstalgo/geometry/Polygon.h': 'abfc8464fec2e081bcb1a7db64b60449519813d4',
 'pstalgo/include/pstalgo/geometry/Rect.h': 'e82bf2da569278d2bd7e55beae02d3d51fd071d1',
 'pstalgo/include/pstalgo/geometry/RegionPoints.h': 'b82cabae4806badc92b6c09449dcb076374f5837',
 'pstalgo/include/pstalgo/geometry/SignedDistanceField.h': 'f6c997b4005fd8d6a059ca9d861a2f0072af04e9',
 'pstalgo/include/pstalgo/gfx/Blur.h': 'a980af4dda63bea449f8a1db44d97df10dabaf69',
 'pstalgo/include/pstalgo/graph/AxialGraph.h': '0ce07a46978e08c0da1972a561033c83993070fb',
 'pstalgo/include/pstalgo/graph/BFSTraversal.h': '307b33a5ff241ab62af623c0e26ecfe3a1022b3b',
 'pstalgo/include/pstalgo/graph/GraphColoring.h': 'e5b7a1188e34fb71ec312c8291ad5f6d25fca67e',
 'pstalgo/include/pstalgo/graph/SegmentGraph.h': 'fbf0067f9e7ac8a473ce90ecdfd23140705d3e35',
 'pstalgo/include/pstalgo/graph/SegmentGroupGraph.h': 'ea3059d00b1769923c6a2eb112e7af7907f3b979',
 'pstalgo/include/pstalgo/graph/SimpleGraph.h': '6befb876bdc4fbddc05e14f6e69cf7924f78fa82',
 'pstalgo/include/pstalgo/math/Gaussian.h': '1e3dab6832078d8fc391383649b28a78f899ef25',
 'pstalgo/include/pstalgo/math/Integral.h': 'fff9455ba838871c4929221a8d7fddd1ea6976b3',
 'pstalgo/include/pstalgo/maths.h': '1b9f25380136bbc24d53da4b17666eec64751d9f',
 'pstalgo/include/pstalgo/pstalgo.h': '3d3c43c4d0445336301e151d7c3a0c146803f9f2',
 'pstalgo/include/pstalgo/system/System.h': 'cab1a364e1f398f4691f3a71c09fa48e0d38593b',
 'pstalgo/include/pstalgo/test/CallbackTest.h': 'cc1662b028509c80092d732f5fb0b89b250e4302',
 'pstalgo/include/pstalgo/utils/Arr2d.h': 'ea7af37c39cbf88476e11aeae562428b77d91fb0',
 'pstalgo/include/pstalgo/utils/Bit.h': '347e6a368e214cce46681502c4987a8b211659ab',
 'pstalgo/include/pstalgo/utils/BitVector.h': '76be89ebacf4f6504310acaedf2c57c28f0f3c7b',
 'pstalgo/include/pstalgo/utils/Concurrency.h': '15ba47a7a57551f8ef8a4fedbd1a9f429ca11bc2',
 'pstalgo/include/pstalgo/utils/DebugUtils.h': '410fe857cbd1630d0d43d56a1cbd911bb917c2d1',
 'pstalgo/include/pstalgo/utils/DiscretePrioQueue.h': '58733a80643f180ec54caa8b20c1864fc19aae08',
 'pstalgo/include/pstalgo/utils/Macros.h': 'd2761cad5f5030c62cf69858dbfb99aec72a1b3a',
 'pstalgo/include/pstalgo/utils/Perf.h': '4222741abdaf00f6ae2a41d528f65818bc44d084',
 'pstalgo/include/pstalgo/utils/RefHeap.h': '846a2c825e975d74e7290ea3e5c222ea8c4f445c',
 'pstalgo/include/pstalgo/utils/SimpleAlignedAllocator.h': '89725de31f232c8628f29d0ab7e39eeba02d0aa8',
 'pstalgo/include/pstalgo/utils/Span.h': '56d8d49b03b2d473d3a251d8e50c84c0b07fed16',
 'pstalgo/python/pstalgo/__init__.py': 'f11b2fb682a588ef97517486d18afc826667b0ed',
 'pstalgo/python/pstalgo/attractiondistance.py': '5229a3e3e5b6acb67b3f8630c22d5d3d4d120012',
 'pstalgo/python/pstalgo/attractionreach.py': '1955a767f04314f88e33810a2263a813beac382d',
 'pstalgo/python/pstalgo/common.py': 'a2877a666f7242ac56e6125a487c7334f35b1bad',
 'pstalgo/python/pstalgo/creategraph.py': '7ddeeb5acaad804d1ba07c4b7d04496a45194ec8',
 'pstalgo/python/pstalgo/networkintegration.py': '5a41c2c2eb3c83baacd7148c8224b2e233f98289',
 'pstalgo/src/BFS.cpp': '8661b3fc712210b968bb9db29f66746aa14047ea',
 'pstalgo/src/Debug.cpp': '0ca2819c2af0aec7d5bd3d9b30302e1868d0e2ac',
 'pstalgo/src/Limits.cpp': '1c5a2f3df51e7991eb761cfb8da4c1bef80cb8db',
 'pstalgo/src/PSTA.cpp': '9e3d721baee183875c2a628feff7087dffa55f0b',
 'pstalgo/src/Platform.cpp': '7b631a56d3c2242631c9fb74bb028eeb270c6ae3',
 'pstalgo/src/Platform.h': 'd48d45608ded5e4e0097a989fe909c2c469946d3',
 'pstalgo/src/Progress.h': '16363ffc0188423d9e0ca4c4b497fb110a7e4356',
 'pstalgo/src/ProgressUtil.cpp': 'ae6e85ad3ae846b5029a81911b47cfc74fa117ea',
 'pstalgo/src/ProgressUtil.h': 'b6fe6f2f9789c6b9e34926c8c1fd156d8664e40a',
 'pstalgo/src/Raster.cpp': '8376884180723cc934959e3145cee1a18d798ba2',
 'pstalgo/src/analyses/AngularChoice.cpp': '89181df0f83dfc7570a1af2cfc58f5a1b18d1164',
 'pstalgo/src/analyses/AngularChoiceAlgo.cpp': '61bdd0460368a473b785f613307a0db2c519ea39',
 'pstalgo/src/analyses/AngularChoiceAlgo.h': 'b037f8d46e14fa8f5822378bfc79b1d41ed61c1a',
 'pstalgo/src/analyses/AngularIntegration.cpp': '99d83548ce1246811abd4aa07600fa9335f2e0c2',
 'pstalgo/src/analyses/AttractionDistance.cpp': 'c13ae9901c80f1debbb9e732e3922c4251b16693',
 'pstalgo/src/analyses/AttractionReach.cpp': 'a756e8350a6364aaa6d3f8c6add9dcc6fef72ded',
 'pstalgo/src/analyses/CalculateIsovists.cpp': '39403e3793af66f0b9fb2e48b44b80b2e7d16fc1',
 'pstalgo/src/analyses/Common.cpp': 'f623c3bea895685a6219ed28c9471cbd4be92329',
 'pstalgo/src/analyses/CreateBufferPolygons.cpp': '595008e09408e995e846d4dead566cf52af2c65a',
 'pstalgo/src/analyses/CreateGraph.cpp': 'd0e6a7ac4858465d4e938ab65c6c491b0ac5c798',
 'pstalgo/src/analyses/CreateJunctions.cpp': '87175e043fbb5a1fb025f7549f40cea76a2ff8e6',
 'pstalgo/src/analyses/CreateSegmentMap.cpp': 'fe35bee74cb5aebf6322a33d6233fb925540f1cc',
 'pstalgo/src/analyses/NetworkIntegration.cpp': 'abfb44f778b0eba71c914a93072eb698dc86de46',
 'pstalgo/src/analyses/ODBetweenness.cpp': '2fa61949a95c6ca619fd49f46104199ee0df93d7',
 'pstalgo/src/analyses/RasterToPolygons.cpp': 'ad6233de60004987f8ac021b98c1808e4708b1fd',
 'pstalgo/src/analyses/Reach.cpp': '4f313cd214125f439de00750ace9d996bc2243ca',
 'pstalgo/src/analyses/SegmentBetweenness.cpp': 'fff26fec3ade352e36a8943b038947605e65cd03',
 'pstalgo/src/analyses/SegmentGroupIntegration.cpp': '2687814b6d50ec09b90b7d1caed03feda976363d',
 'pstalgo/src/analyses/SegmentGrouping.cpp': '62cfacbf0520b9db8cfc870043bb4396faeec04a',
 'pstalgo/src/analyses/VisualConnectivity.cpp': '8bc6869258f2e126b0d659d9ad2aee2555238237',
 'pstalgo/src/experimental/DirectedMultiDistanceGraph.cpp': '8414df738d388c72f38237b2ddae1bf32a2947b7',
 'pstalgo/src/experimental/FastSegmentBetweenness.cpp': '3e3f41225d9973befc0aa7a6ac598f76874fc7e7',
 'pstalgo/src/experimental/ShortestPathTraversal.cpp': '13ad4ebd2964b7eb7976e0a4e4352e8c046ba3f0',
 'pstalgo/src/experimental/SparseDirectedGraph.cpp': 'bd1d9f8df2dd658ce45a0570c82176efa06660c1',
 'pstalgo/src/geometry/AABSPTree.cpp': '8418222bd7801ffff4d883f2361767f25b17bc77',
 'pstalgo/src/geometry/ConvexHull.cpp': '6db95341395eab9823b415ff6e9e55e401401b67',
 'pstalgo/src/geometry/Geometry.cpp': '2b9a62773f1786eba046775f2914ba928df3de14',
 'pstalgo/src/geometry/IsovistCalculator.cpp': '30480acd74a7552442cf32a62ae04199036853d7',
 'pstalgo/src/geometry/Polygon.cpp': 'db0aae1ecff2b988e02b3e8c195c277bfbf4a627',
 'pstalgo/src/geometry/RegionPoints.cpp': '3c010e6f1509855646c702aa496b7bd1068f5bb5',
 'pstalgo/src/geometry/SignedDistanceField.cpp': 'b15ecec6d32f0aa7f2ccafb173237bc6d8a8668e',
 'pstalgo/src/gfx/Blur.cpp': '77cfbbb26b2959be4576d631f47136046595d013',
 'pstalgo/src/graph/AxialGraph.cpp': 'c5331259014488f3960c24c79db7c68277a4a80e',
 'pstalgo/src/graph/GraphColoring.cpp': '606cb72cdea363c989b343cd935af4144d54a691',
 'pstalgo/src/graph/SegmentGraph.cpp': 'e277e69913e152e46b96de5b87dcb2cc6fe1d9e0',
 'pstalgo/src/graph/SegmentGroupGraph.cpp': 'ab83e462136401fa6fa1ab653e25fc31e06f65d0',
 'pstalgo/src/graph/SimpleGraph.cpp': 'a8a77295ed4a09a37998fab7e0102fcd255009e1',
 'pstalgo/src/math/Gaussian.cpp': '6ece0ebdf3a11d74fc06bd53a1bae5ea5e61c983',
 'pstalgo/src/system/System.cpp': '81f6b6bbc04d3ca8228ad6b9747ca3c032a8057b',
 'pstalgo/src/test/CallbackTest.cpp': '4f1c289fcf8aad8fccaede322247bd3de015fbf0',
 'pstalgo/src/utils/SimpleAlignedAllocator.cpp': '298480229203a4bc4dd4fd7a9a4dee60489b40df',
 'pstalgo/src/utils/SphereTree.cpp': '475a30b9dd9f820d753e5a885f4044ad5c4ef9b4',
 'pstalgo/src/utils/SphereTree.h': 'cb55ca91e47bcf3bf9596799ee03f8147e2807d4',
 'pstalgo/test/tests/__init__.py': '0c27231de24df8ef3460866a55434568f977c7c1',
 'pstalgo/test/tests/common.py': '5012bc7a7f907f63c30def1278e079889ec768bb',
 'pstalgo/test/tests/graphs.py': '30337ddfc24f80e425a41029839c7d1c2e08d997',
 'pstalgo/test/tests/testattractiondistance.py': '5e148288c807abf738a84e6e5a426aa1f706c446',
 'pstalgo/test/tests/testattractionreach.py': 'dfc2465b8f84d1f250d6467ad6cef783e94ec230',
 'pstalgo/test/tests/testcreategraph.py': '1286871d1057b8da4ccba6959f5b05df5df4518a',
 'pstalgo/test/tests/testnetworkintegration.py': '2654a0f39a633de1b489a811b9146e9c171192ac',
 'pstqgis/src/pst/analyses/attractiondistanceanalysis.py': '8c0ab9a1df2050777be8ddaabd1080bf9bdc44cf',
 'pstqgis/src/pst/analyses/attractionreachanalysis.py': '42dd001d4f20171df47a82481b97868c35d241fa',
 'pstqgis/src/pst/analyses/networkintegrationanalysis.py': 'cbe709e153d222742b93e822aae8600f8dbe32ab',
 'pstqgis/src/pst/analyses/utils.py': 'e868049d8ae018d76cc1d2c8c0123271cd9da639',
 'pstqgis/src/pst/model/model.py': '57fc2595cf886a6c8bdbdfcdda30517f9e7c800c'}
root, libr, dll, output = sys.argv[1:]
root = pathlib.Path(root).resolve()
for path, expected in BLOBS.items():
    raw = (root/path).read_bytes()
    actual = hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()
    if actual != expected:
        raise SystemExit('Pinned reference drift: '+path)
print('Verified '+str(len(BLOBS))+' pinned blobs', file=sys.stderr)
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
sys.path.insert(0, str(root/'pstalgo/test'))
suite = unittest.defaultTestLoader.loadTestsFromNames([
    'tests.testattractionreach', 'tests.testattractiondistance'])
upstream = unittest.TextTestRunner(stream=sys.stderr).run(suite)
if not upstream.wasSuccessful():
    raise SystemExit('Pinned upstream tests failed')

def number(value):
    if math.isnan(value): return 'NaN'
    if math.isinf(value): return '+Inf' if value > 0 else '-Inf'
    return value

# Use the verified worker/scratch/exception build adaptations, cap one for
# repeatable float accumulation. No rPSTool registered .Call is used.
import os
os.environ['RPST_NUM_THREADS'] = '1'
def arr(rows, code='d'):
    return array.array(code, [v for row in rows for v in row] if rows and isinstance(rows[0], list) else rows)
origins = {'points':0, 'junctions':1, 'lines':2, 'point_groups':3}
distances = {'straight':0, 'walking':1, 'steps':2, 'angular':3, 'axmeter':4, 'weights':5, 'none':6}
cases=[]
graph_cases=[dict(name='chain_groups',x=[[0,0,3,0],[3,0,6,0],[6,0,9,0],[20,0,23,0]],
    points=[[1,1],[2,1],[7,2],[8,2]],points_per_polygon=[2,2,0],polygon_point_interval=1),
    dict(name='wave',x=[[0,0,2,0],[2,0,2,2],[2,2,4,2],[4,2,4,0]],points=[[1,1],[3,1]]),
    dict(name='no_origins',x=[[0,0,3,0]],points=[])]
for graph_case in graph_cases:
    gc=graph_case
    h=pst.CreateGraph(arr(gc['x']), points=arr(gc['points']) if gc['points'] else None,
        points_per_polygon=arr(gc['points_per_polygon'],'I') if 'points_per_polygon' in gc else None,
        polygon_point_interval=gc.get('polygon_point_interval',0))
    try:
        info=pst.GetGraphInfo(h)
        sizes=len(gc.get('points_per_polygon',[]))
        counts={'lines':info.m_LineCount,'junctions':info.m_CrossingCount,'points':info.m_PointCount,'point_groups':sizes}
        for origin, origin_mode in origins.items():
            n=counts[origin]
            # Reach: every distance, every decay, independent finite/mixed radii,
            # all collection modes, negative/zero attraction values.
            for distance in ['straight','walking','steps','angular','axmeter','none']:
                for decay, weight_mode in [('constant',0),('power',1),('curve',2),('divide',3)]:
                    for finite in [False,True]:
                        if gc['name']!='chain_groups' and (decay!='constant' or finite): continue
                        radius= {} if not finite else dict(straight=10,walking=15,steps=3,angular=180,axmeter=60)
                        # Exercise the straight-only branch separately below.
                        args=dict(origin=origin,distance=distance,radius=radius,
                            attraction_points=[[0,1],[7,2],[30,1]], attraction_values=[2,0,-3],
                            decay=decay,decay_constant=2,collection='mean',distribution='divide')
                        out=array.array('f',[17]*n)
                        pst.AttractionReach(h,origin_type=origin_mode,distance_type=distances[distance],
                            radius=pst.Radii(**radius),weight_func=weight_mode,weight_func_constant=2,
                            attraction_points=arr(args['attraction_points']),attraction_values=arr(args['attraction_values'],'f'),out_scores=out)
                        cases.append(dict(graph=gc,analysis='reach',args=args,scores=list(out)))
            if gc['name']=='chain_groups':
                for collection, mode in [('mean',0),('sum',1),('min',2),('max',3)]:
                    for distribution, dm in [('copy',0),('divide',1)]:
                        for radius in [{},{'straight':5},{'steps':0}]:
                            args=dict(origin=origin,distance='straight',radius=radius,decay='divide',decay_constant=2,
                                attraction_points=[[0,1],[2,1]],points_per_polygon=[2],polygon_point_interval=1,
                                attraction_values=[3],distribution=distribution,collection=collection)
                            out=array.array('f',[-29]*n)
                            pst.AttractionReach(h,origin_type=origin_mode,distance_type=0,radius=pst.Radii(**radius),
                                weight_func=3,weight_func_constant=2,attraction_points=arr(args['attraction_points']),
                                points_per_attraction_polygon=arr([2],'I'),attraction_polygon_point_interval=1,
                                attraction_values=arr([3],'f'),attraction_distribution_func=dm,
                                attraction_collection_func=mode,out_scores=out)
                            cases.append(dict(graph=gc,analysis='reach',args=args,scores=list(out)))
            for distance in ['straight','walking','steps','angular','weights']:
                if origin=='point_groups' and distance=='straight': continue
                for polygon in [False,True]:
                    for want_indices in [False,True]:
                        if gc['name']!='chain_groups' and (polygon or not want_indices): continue
                        args=dict(origin=origin,distance=distance,radius={},destination_indices=want_indices,
                            attraction_points=[[0,1],[2,1],[7,1],[8,1]] if polygon else [[0,1],[7,1]])
                        if polygon: args.update(points_per_polygon=[2,2],polygon_point_interval=1)
                        if distance=='weights':args.update(line_weights=[float(i+1) for i in range(info.m_LineCount)],point_edge_weight=.75)
                        runs=[]
                        for seed in [17,-29]:
                            out=array.array('f',[seed]*n);idx=array.array('i',[-1]*n) if want_indices else None
                            pst.AttractionDistance(h,origin_type=origin_mode,distance_type=distances[distance],
                                radius=pst.Radii(),attraction_points=arr(args['attraction_points']),
                                points_per_polygon=arr(args['points_per_polygon'],'I') if polygon else None,
                                polygon_point_interval=1 if polygon else 0,
                                line_weights=arr(args['line_weights'],'f') if distance=='weights' else None,
                                weight_per_meter_for_point_edges=args.get('point_edge_weight',0),
                                out_min_distances=out,out_destination_indices=idx)
                            runs.append((out.tobytes(), None if idx is None else idx.tobytes()))
                        assert runs[0]==runs[1]
                        cases.append(dict(graph=gc,analysis='distance',args=args,scores=list(out),indices=list(idx) if idx is not None else []))
        if gc['name']=='chain_groups':
            for origin in origins:
                for decay,wm,constant,radius in [('power',1,2,{'steps':0}),('divide',3,-200,{})]:
                    args=dict(origin=origin,distance='steps',radius=radius,attraction_points=[[0,1]],
                        decay=decay,decay_constant=constant,collection='mean',distribution='divide')
                    out=array.array('f',[17]*counts[origin])
                    pst.AttractionReach(h,origin_type=origins[origin],distance_type=2,radius=pst.Radii(**radius),
                        weight_func=wm,weight_func_constant=constant,attraction_points=arr(args['attraction_points']),out_scores=out)
                    cases.append(dict(graph=gc,analysis='reach',args=args,scores=list(out)))
            for analysis in ['reach','distance']:
                args=dict(origin='points',distance='walking',radius={},attraction_points=[[0,1],[1,1],[float('nan'),float('nan')],[7,1]],
                    points_per_polygon=[4],polygon_point_interval=1)
                out=array.array('f',[17]*counts['points'])
                if analysis=='reach':
                    pst.AttractionReach(h,origin_type=0,distance_type=1,attraction_points=arr(args['attraction_points']),
                        points_per_attraction_polygon=arr([4],'I'),attraction_polygon_point_interval=1,out_scores=out)
                    cases.append(dict(graph=gc,analysis=analysis,args=args,scores=list(out)))
                else:
                    idx=array.array('i',[-1]*counts['points']);args['destination_indices']=True
                    pst.AttractionDistance(h,origin_type=0,distance_type=1,attraction_points=arr(args['attraction_points']),
                        points_per_polygon=arr([4],'I'),polygon_point_interval=1,out_min_distances=out,out_destination_indices=idx)
                    cases.append(dict(graph=gc,analysis=analysis,args=args,scores=list(out),indices=list(idx)))
        if gc['name']=='chain_groups':
            for origin in origins:
                for analysis in ['reach','distance']:
                    for distance in (['straight','steps'] if analysis=='reach' else ['straight','walking','steps','angular','weights']):
                        if analysis=='distance' and origin=='point_groups' and distance=='straight':continue
                        for polygon in [False,True]:
                            args=dict(origin=origin,distance=distance,radius={},attraction_points=[])
                            if polygon:args.update(points_per_polygon=[0,0],polygon_point_interval=1)
                            out=array.array('f',[17]*counts[origin])
                            if analysis=='reach':
                                pst.AttractionReach(h,origin_type=origins[origin],distance_type=distances[distance],
                                    attraction_points=arr([]),points_per_attraction_polygon=arr([0,0],'I') if polygon else None,
                                    attraction_polygon_point_interval=1 if polygon else 0,out_scores=out)
                                cases.append(dict(graph=gc,analysis=analysis,args=args,scores=list(out)))
                            else:
                                idx=array.array('i',[-1]*counts[origin]);args['destination_indices']=True
                                if distance=='weights':args['line_weights']=[1]*info.m_LineCount
                                pst.AttractionDistance(h,origin_type=origins[origin],distance_type=distances[distance],
                                    attraction_points=arr([]),points_per_polygon=arr([0,0],'I') if polygon else None,
                                    polygon_point_interval=1 if polygon else 0,line_weights=arr(args['line_weights'],'f') if distance=='weights' else None,
                                    out_min_distances=out,out_destination_indices=idx)
                                cases.append(dict(graph=gc,analysis=analysis,args=args,scores=list(out),indices=list(idx)))
        if gc['name']=='chain_groups':
            # Native finite straight index behaviour and network straight-limit
            # omission; network restrictions independent of primary cost.
            for origin in origins:
                for distance, radius in [('straight',{'straight':10}),('walking',{'straight':0}),
                    ('walking',{'walking':4}),('steps',{'steps':0}),('angular',{'angular':0}),
                    ('weights',{'walking':4})]:
                    if origin=='point_groups' and distance=='straight':continue
                    n=counts[origin];args=dict(origin=origin,distance=distance,radius=radius,
                        attraction_points=[[0,1],[7,1]],destination_indices=True)
                    if distance=='weights':args.update(line_weights=[1]*info.m_LineCount,point_edge_weight=.5)
                    out=array.array('f',[17]*n);idx=array.array('i',[-1]*n)
                    pst.AttractionDistance(h,origin_type=origins[origin],distance_type=distances[distance],radius=pst.Radii(**radius),
                        attraction_points=arr(args['attraction_points']),line_weights=arr(args.get('line_weights',[]),'f') if distance=='weights' else None,
                        weight_per_meter_for_point_edges=args.get('point_edge_weight',0),out_min_distances=out,out_destination_indices=idx)
                    cases.append(dict(graph=gc,analysis='distance',args=args,scores=list(out),indices=list(idx)))
    finally:pst.FreeGraph(h)
import sys as _sys, pathlib as _pathlib
_sys.path.insert(0, str(_pathlib.Path(__file__).resolve().parents[1] / 'common'))
from rnumeric import r_number  # exact R numeric literals (development-only helper)
def rv(v):
    if isinstance(v,dict):return 'list('+', '.join(k+'='+rv(x) for k,x in v.items())+')'
    if isinstance(v,list):return 'list('+', '.join(rv(x) for x in v)+')'
    if isinstance(v,str):return json.dumps(v)
    if isinstance(v,bool):return 'TRUE' if v else 'FALSE'
    if isinstance(v,float):
        if math.isnan(v):return 'NaN'
        if math.isinf(v):return 'Inf' if v>0 else '-Inf'
    return r_number(v)
header='# Direct pinned PST C API; tools/reference/attractions/generate-reference.py. Worker cap 1.\n'
for path,sha in sorted(BLOBS.items()):header+='# '+path+' git blob '+sha+'\n'
pathlib.Path(output).write_text(header+'list(pst_commit='+rv(PIN)+', cases=list(\n  '+',\n  '.join(rv(c) for c in cases)+'\n))\n')
print('Verified '+str(len(cases))+' supported attraction cases',file=sys.stderr)
