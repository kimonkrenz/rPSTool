#!/usr/bin/env python3
"""Direct pinned isovist investigation, not an rPSTool analysis call.

Usage: native-cases.py PINNED_ROOT LIBR_PATH PST_DLL
Unix child processes isolate unsafe native inputs and disable core dumps.
All result handles are freed before their context. Reference files stay read-only.
"""
import array
import ctypes
import hashlib
import json
import pathlib
import platform
import resource
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
root, libr, dll = [str(pathlib.Path(p).resolve()) for p in sys.argv[1:4]]
manifest = json.loads(pathlib.Path(__file__).with_name('source-blobs.json').read_text())
assert manifest['pin'] == '63df80a2cf3dd289be95ea3d91667c3490719b75'
for name, expected in manifest['blobs'].items():
    raw = (pathlib.Path(root) / name).read_bytes()
    actual = hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()
    if actual != expected:
        raise SystemExit('Pinned reference drift: ' + name)
ctypes.CDLL(libr, mode=ctypes.RTLD_GLOBAL)
engine = ctypes.CDLL(dll)
loader, system = ctypes.cdll.LoadLibrary, platform.system
try:
    ctypes.cdll.LoadLibrary = lambda _: engine
    platform.system = lambda: 'Darwin'
    sys.path.insert(0, root + '/pstalgo/python')
    import pstalgo as pst
finally:
    ctypes.cdll.LoadLibrary, platform.system = loader, system

def polygons(target, groups):
    target.polygonCountPerGroup = array.array('I', map(len, groups))
    target.pointCountPerPolygon = array.array('I', [len(p) for g in groups for p in g])
    target.coords = array.array('d', [v for g in groups for p in g for xy in p for v in xy])

def rectangle(x, y, size):
    return [[x,y], [x,y+size], [x+size,y+size], [x+size,y]]

cases = []
for geometry in ['empty', 'grouped', 'empty_groups', 'inside_obstacle']:
    for fov in [45, 90, 180, 270, 360]:
        for resolution in [4, 64]:
            cases.append(dict(name=f'{geometry}_{fov}_{resolution}', geometry=geometry,
                              distance=10, fov=fov, direction=30, resolution=resolution))
for radius in [1, .1, .01, .001, .0001]:
    for fov in [90, 360]:
        cases.append(dict(name=f'small_radius_{radius}_{fov}', geometry='empty',
                          distance=radius, fov=fov, direction=0, resolution=64))
for fov in [0, .001, .01, .1, 1]:
    cases.append(dict(name=f'narrow_fov_{fov}', geometry='grouped',
                      distance=10, fov=fov, direction=0, resolution=64))
for geometry in ['near_point', 'near_polygon']:
    cases.append(dict(name=f'degenerate_partial_{geometry}', geometry=geometry,
                      distance=.01, fov=90, direction=0, resolution=64))
cases.append(dict(name='degenerate_two_point_near_polygon', geometry='near_polygon',
                  distance=10, fov=.001, direction=0, resolution=64))
for radius in [.2, .3, .5, 1]:
    cases.append(dict(name=f'near_full_{radius}', geometry='empty', distance=radius,
                      fov=360, direction=0, resolution=64))
    cases.append(dict(name=f'near_partial_polygon_{radius}', geometry='near_polygon',
                      distance=radius, fov=90, direction=0, resolution=64))
for fov in [1, 2, 5, 10]:
    cases.append(dict(name=f'near_narrow_polygon_{fov}', geometry='near_polygon',
                      distance=10, fov=fov, direction=0, resolution=64))
for origin in [[5,-2], [1000000000000,1000000000000], [-2,3]]:
    cases.append(dict(name='translated_empty_' + str(origin[0]), geometry='empty',
                      distance=10, fov=270, direction=-45, resolution=16, origin=origin))
cases.append(dict(name='tree_ordered_points', geometry='many_points', distance=10,
                  fov=360, direction=0, resolution=64))
for geometry in ['closed_polygon', 'reversed_polygon', 'inside_attraction', 'world_grouped']:
    cases.append(dict(name=geometry, geometry=geometry, distance=10, fov=270,
                      direction=30, resolution=8))
cases.append(dict(name='grouped_other_origin', geometry='grouped', distance=10,
                  fov=180, direction=-90, resolution=32, origin=[5,-2]))
cases.append(dict(name='degenerate_partial_straddling_points', geometry='straddling_points',
                  distance=.01, fov=90, direction=0, resolution=64))
cases.append(dict(name='safe_partial_straddling_points', geometry='straddling_points',
                  distance=1, fov=90, direction=0, resolution=64))

# Full-circle singleton reaches polygon processing only when edges are queued.
for name, geometry, radius in [
    ('degenerate_full_near_polygon', 'near_polygon', .01),
    ('safe_full_near_polygon', 'near_polygon', .02),
    ('safe_full_singleton_empty', 'empty', .01),
    ('safe_full_singleton_inside', 'inside_attraction', .01)]:
    cases.append(dict(name=name, geometry=geometry, distance=radius,
                      fov=360, direction=0, resolution=3))

def run(case):
    geometry = pst.IsovistContextGeometry()
    if case['geometry'] in ['grouped', 'world_grouped']:
        polygons(geometry.obstaclePolygons, [[rectangle(2,-1,2)], [], [rectangle(-4,1,1)]])
        geometry.attractionPoints.pointCountPerGroup = array.array('I', [3,0,2])
        geometry.attractionPoints.coords = array.array('d', [1,0, 5,0, -1,0, 0,2, 20,20])
        polygons(geometry.attractionPolygons, [[rectangle(0,3,1)], [], [rectangle(-2,-2,1)]])
    elif case['geometry'] == 'empty_groups':
        polygons(geometry.obstaclePolygons, [[], []])
        geometry.attractionPoints.pointCountPerGroup = array.array('I', [0,0])
        geometry.attractionPoints.coords = array.array('d')
        polygons(geometry.attractionPolygons, [[], []])
    elif case['geometry'] == 'inside_obstacle':
        polygons(geometry.obstaclePolygons, [[rectangle(-1,-1,2)]])
    elif case['geometry'] == 'near_point':
        geometry.attractionPoints.pointCountPerGroup = array.array('I', [1])
        geometry.attractionPoints.coords = array.array('d', [0,0])
    elif case['geometry'] == 'straddling_points':
        geometry.attractionPoints.pointCountPerGroup = array.array('I', [3])
        geometry.attractionPoints.coords = array.array('d', [0,0, -1,-1, 1,1])
    elif case['geometry'] == 'near_polygon':
        polygons(geometry.attractionPolygons, [[rectangle(.001,-.001,.002)]])
    elif case['geometry'] == 'many_points':
        geometry.attractionPoints.pointCountPerGroup = array.array('I', [80,0,20])
        geometry.attractionPoints.coords = array.array('d', [v for i in range(100)
            for v in [(i % 10)-5, (i // 10)-5]])
    elif case['geometry'] in ['closed_polygon', 'reversed_polygon']:
        ring = rectangle(2,-1,2)
        ring = ring + [ring[0]] if case['geometry'] == 'closed_polygon' else ring[::-1]
        polygons(geometry.obstaclePolygons, [[ring]])
    elif case['geometry'] == 'inside_attraction':
        polygons(geometry.attractionPolygons, [[rectangle(-1,-1,2)]])
    offset = 1e12 if case['geometry'] == 'world_grouped' else 0
    if offset:
        for objects in [geometry.obstaclePolygons, geometry.attractionPoints, geometry.attractionPolygons]:
            objects.coords = array.array('d', [v + offset for v in objects.coords])
    context = pst.CreateIsovistContext(geometry)
    try:
        results = []
        # Reuse the context with fresh zero-initialized descriptors as the official
        # caller does. Visibility ObjectCount is an accumulator, not overwritten.
        for repetition in range(2):
            n, points, handle, area, obstacles, apoints, apolygons = pst.CalculateIsovist(
                context, *[v+offset for v in case.get('origin',[0,0])], case['distance'], case['fov'], case['direction'], case['resolution'])
            if not handle:
                return dict(success=False)
            try:
                def visible(x):
                    return dict(count=x.ObjectCount, groups=list(x.CountPerGroup[:x.GroupCount]),
                                indices=list(x.Indices[:x.ObjectCount]))
                results.append(dict(success=True, points=[list(points[2*i:2*i+2]) for i in range(n)],
                                    area=area, obstacles=visible(obstacles),
                                    attraction_points=visible(apoints), attraction_polygons=visible(apolygons)))
            finally:
                pst.Free(handle)
        assert results[0] == results[1], 'Context reuse changed results'
        return results[0]
    finally:
        pst.Free(context)

if len(sys.argv) > 4:
    resource.setrlimit(resource.RLIMIT_CORE, (0,0))
    print(json.dumps(run(cases[int(sys.argv[4])]), allow_nan=False))
else:
    sys.path.insert(0, root + '/pstalgo/test')
    suite = unittest.defaultTestLoader.loadTestsFromName('tests.testcalculateisovists')
    if not unittest.TextTestRunner().run(suite).wasSuccessful():
        raise SystemExit('Pinned upstream tests failed')
    observed = []
    for i, case in enumerate(cases):
        child = subprocess.run([sys.executable, __file__, root, libr, dll, str(i)],
                               text=True, capture_output=True, timeout=10)
        item = dict(case=case, returncode=child.returncode, stderr=child.stderr.strip())
        if child.returncode == 0:
            item['native'] = json.loads(child.stdout)
        else:
            item['stdout'] = child.stdout.strip()
        observed.append(item)
    print(json.dumps(dict(pst_commit=manifest['pin'], verified_blobs=len(manifest['blobs']),
                          cases=observed), indent=2, allow_nan=False))
