#!/usr/bin/env python3
"""Development-only direct PST bounds probe; never changes package or vendor inputs.

Usage: PINNED_ROOT LIBR_PATH PACKAGE_DLL WORK_DIRECTORY
Uses the verified official Python API and builds a locally bound pinned module.
Only diagnostic logging and a bounds assertion are added to its scratch source.
"""
import hashlib
import json
import pathlib
import resource
import subprocess
import sys

repo = pathlib.Path(__file__).resolve().parents[3]
root, libr, dll, output = [str(pathlib.Path(p).resolve()) for p in sys.argv[1:5]]
out = pathlib.Path(output)
assert out.is_relative_to(repo / 'work')
# Reuse the manifest verification and official pinned API loader, not rPSTool's R API.
loader = (repo / 'tools/reference/isovist/native-cases.py').read_text().split('cases = []')[0]
exec(compile(loader, str(repo / 'tools/reference/isovist/native-cases.py'), 'exec'))

if len(sys.argv) > 5:
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    kind = sys.argv[5]
    geometry = pst.IsovistContextGeometry()
    if kind == 'near':
        polygons(geometry.attractionPolygons, [[rectangle(.001, -.001, .002)]])
    elif kind == 'inside':
        polygons(geometry.attractionPolygons, [[rectangle(-.001, -.001, .002)]])
    context = pst.CreateIsovistContext(geometry)
    try:
        results = []
        for repetition in range(2):
            n, points, handle, area, obstacles, apoints, apolygons = pst.CalculateIsovist(
                context, 0, 0, .01, 360, 0, 3)
            if not handle:
                print(json.dumps(dict(success=False)))
                sys.exit(0)
            try:
                results.append(dict(vertices=n, coordinates=list(points[:2*n]), area=area,
                                    attraction_polygons=apolygons.ObjectCount))
            finally:
                pst.Free(handle)
        assert results[0] == results[1]
        print(json.dumps(results))
    finally:
        pst.Free(context)
    sys.exit(0)

raw = (repo / 'src/vendor/pstalgo/src/analyses/CalculateIsovists.cpp').read_bytes()
assert hashlib.md5(raw).hexdigest() == '42c16aa243ccc11e2b2e95692407ebb7'
source = raw.decode().replace('\t\tResult& Result() { return m_Result; }',
                            '\t\tCIsovistContext::Result& Result() { return m_Result; }')
assert hashlib.md5(source.encode()).hexdigest() == 'a98b22b9a2f066e734ffc8a51fe35974'
source = '#include <cstdio>\n#include <cstdlib>\n' + source
needle = '\t\t\tif (!m_TempAttrEdgeQueue.empty())\n\t\t\t{'
assert source.count(needle) == 1
source = source.replace(needle, needle + '\n\t\t\t\tstd::fprintf(stderr, "polygon queue: vertices=%zu edges=%zu fov=%g\\n", isovist_obj_points.size(), m_TempAttrEdgeQueue.size(), double(desc.m_FieldOfViewDegrees));')
needle = '\t\t\t\t\t\tthis->P1 = m_Points[m_At];'
assert source.count(needle) == 1
source = source.replace(needle, '\t\t\t\t\t\tif (m_At >= m_Points.size()) { std::fprintf(stderr, "iterator bounds: index=%zu size=%zu lap=%u\\n", m_At, m_Points.size(), unsigned(m_LapIndex)); std::abort(); }\n' + needle)
out.mkdir(parents=True, exist_ok=True)
cpp = out / 'trace.cpp'
cpp.write_text(source)
trace = out / 'trace.so'
subprocess.run(['g++', '-std=c++17', '-shared', '-fPIC', '-O0', '-g', '-D_GLIBCXX_ASSERTIONS',
                '-I' + str(repo / 'src/compat'), '-I' + str(repo / 'src/vendor/pstalgo/include'),
                '-I' + str(repo / 'src/vendor/pstalgo/src/analyses'), '-include', str(repo / 'src/rpst-compat.h'),
                str(cpp), dll, '-Wl,-Bsymbolic', '-o', str(trace)], check=True)
observed = []
for module in [dll, str(trace)]:
    for kind in ['empty', 'inside', 'near']:
        child = subprocess.run([sys.executable, __file__, root, libr, module, output, kind],
                               capture_output=True, text=True, timeout=10)
        observed.append(dict(module='dependency' if module == dll else 'trace', geometry=kind,
                             returncode=child.returncode, stdout=child.stdout.strip(), stderr=child.stderr.strip()))
print(json.dumps(dict(pin=manifest['pin'], verified_blobs=len(manifest['blobs']),
                      pristine_md5=hashlib.md5(raw).hexdigest(),
                      diagnostic_source_sha256=hashlib.sha256(cpp.read_bytes()).hexdigest(),
                      cases=observed), indent=2))
assert observed[-1]['returncode'] == -6
assert 'polygon queue: vertices=1 edges=1 fov=360' in observed[-1]['stderr']
assert 'iterator bounds: index=1 size=1 lap=1' in observed[-1]['stderr']
for i in [0, 1]:
    assert observed[i]['returncode'] == observed[i+3]['returncode'] == 0
    assert observed[i]['stdout'] == observed[i+3]['stdout']
