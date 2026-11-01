#!/usr/bin/env python3
"""Development-only direct PST reproduction; no R analysis calls.
Usage: check-output-writes.py PINNED_PST_ROOT LIBR_PATH PST_DLL
Run vendor verification and repository checks before loading the built DLL.
Print deterministic JSON to stdout; verification/upstream tests go to stderr.
"""
import array
import ctypes
import hashlib
import json
import math
import pathlib
import platform
import sys
import unittest

PIN = "63df80a2cf3dd289be95ea3d91667c3490719b75"
# Independently verified against GitHub's recursive tree for PIN.
BLOBS = {
  "pstalgo/include/pstalgo/analyses/CreateGraph.h": "ab0eda724c0df4bd20e3ed42506cd3dbad0aaa75",
  "pstalgo/include/pstalgo/analyses/SegmentGrouping.h": "26eea3469c720a8223337a23b16ccfa067c05ee7",
  "pstalgo/include/pstalgo/analyses/SegmentGroupIntegration.h": "d1b8dea2ae3c64da04aeac3f94261a06a6102be6",
  "pstalgo/src/analyses/CreateGraph.cpp": "d0e6a7ac4858465d4e938ab65c6c491b0ac5c798",
  "pstalgo/src/analyses/SegmentGrouping.cpp": "62cfacbf0520b9db8cfc870043bb4396faeec04a",
  "pstalgo/src/analyses/SegmentGroupIntegration.cpp": "2687814b6d50ec09b90b7d1caed03feda976363d",
  "pstalgo/src/analyses/NetworkIntegration.cpp": "abfb44f778b0eba71c914a93072eb698dc86de46",
  "pstalgo/include/pstalgo/graph/SegmentGroupGraph.h": "ea3059d00b1769923c6a2eb112e7af7907f3b979",
  "pstalgo/src/graph/SegmentGroupGraph.cpp": "ab83e462136401fa6fa1ab653e25fc31e06f65d0",
  "pstalgo/python/pstalgo/common.py": "a2877a666f7242ac56e6125a487c7334f35b1bad",
  "pstalgo/python/pstalgo/creategraph.py": "7ddeeb5acaad804d1ba07c4b7d04496a45194ec8",
  "pstalgo/python/pstalgo/segmentgrouping.py": "8833c4538b3c21d393c5e608fd0282107ebf63be",
  "pstalgo/python/pstalgo/segmentgroupintegration.py": "b51a7486efc33ad62254bf522179448c12d26191",
  "pstalgo/test/tests/testsegmentgrouping.py": "5287a796a053431a66e8aeeccfa339492513ee42",
  "pstalgo/test/tests/testsegmentgroupintegration.py": "69a0f45af56b056e66085a6825bc4d4dbe1dd04e",
  "pstalgo/test/tests/graphs.py": "30337ddfc24f80e425a41029839c7d1c2e08d997",
  "pstalgo/test/tests/common.py": "5012bc7a7f907f63c30def1278e079889ec768bb",
  "pstqgis/src/pst/analyses/segmentgroupintegrationanalysis.py": "0c2b754c494287ff5ebcbf1f040d154eb16ba833",
  "pstqgis/src/pst/analyses/memory.py": "84ecc7c401b9c8c9bc12f06cb3ed3233072b318c"
}

def main():
    root, libr, dll = sys.argv[1:]
    root = pathlib.Path(root)
    for path, expected in BLOBS.items():
        raw = (root / path).read_bytes()
        actual = hashlib.sha1(("blob " + str(len(raw)) + "\0").encode() + raw).hexdigest()
        if actual != expected:
            raise SystemExit("Pinned reference drift: " + path)
    print("Verified 19 pinned header/source/wrapper/test/caller blobs", file=sys.stderr)
    ctypes.CDLL(libr, mode=ctypes.RTLD_GLOBAL)
    engine = ctypes.CDLL(dll)
    loader, system = ctypes.cdll.LoadLibrary, platform.system
    try:
        ctypes.cdll.LoadLibrary = lambda path: engine
        platform.system = lambda: "Darwin"
        sys.path.insert(0, str(root / "pstalgo/python"))
        import pstalgo as pst
    finally:
        ctypes.cdll.LoadLibrary, platform.system = loader, system
    sys.path.insert(0, str(root / "pstalgo/test"))
    suite = unittest.defaultTestLoader.loadTestsFromNames([
        "tests.testsegmentgrouping", "tests.testsegmentgroupintegration"])
    if not unittest.TextTestRunner(stream=sys.stderr).run(suite).wasSuccessful():
        raise SystemExit("Pinned upstream tests failed")

    from pstalgo.segmentgroupintegration import SPSTASegmentGroupIntegration
    from pstalgo.common import UnpackArray
    native = engine.PSTASegmentGroupIntegration
    native.argtypes = [ctypes.POINTER(SPSTASegmentGroupIntegration)]
    native.restype = ctypes.c_bool
    chain = [0,0,1,0, 1,0,2,0, 2,0,3,0]
    cases = [
        ("isolated", [0,0,1,0], 1, False, None, 1, True),
        ("merged_chain", chain, 1, False, None, 1, True),
        ("merged_chain_split", chain, 1, True, None, 1, True),
        ("disconnected", [0,0,1,0, 5,0,6,0], 1, False, None, 2, True),
        ("merged_loop", [0,0,1,0, 1,0,1,1, 1,1,0,1, 0,1,0,0], 90, False, None, 1, True),
        ("singleton_chain_control", chain, 0, False, [0,1,2], 3, False),
        ("mixed_isolated_control", chain + [10,0,11,0], 0, False, [0,1,2,3], 4, False),
    ]
    def values(a):
        return [x if math.isfinite(x) else ("NaN" if math.isnan(x) else "Inf" if x > 0 else "-Inf") for x in a]

    observed = []
    for name, coords, angle, split, explicit, expected_groups, unwritten in cases:
        n = len(coords) // 4
        segment = pst.CreateSegmentGraph(array.array('d',coords), None, None)
        assert segment
        group = None
        try:
            ids, colors = array.array('I',[0]*n), array.array('I',[0]*n)
            ng, nc = pst.SegmentGrouping(segment, angle, split, ids, colors)
            grouping = dict(ids=list(ids), colors=list(colors), group_count=ng, color_count=nc)
            if explicit is not None:
                ids = array.array('I',explicit)
                ng = expected_groups
            assert ng == expected_groups
            group = pst.CreateSegmentGroupGraph(segment, ids, ng)
            assert group
            # Create copies independent of segment graph; source stores values.
            pst.FreeSegmentGraph(segment)
            segment = None
            for radius_name, radii in [("unlimited",pst.Radii()), ("steps_zero",pst.Radii(steps=0)),
                                       ("walking_zero",pst.Radii(walking=0))]:
                runs = []
                for seed in [17,29]:
                    scores, counts, depths = array.array('f',[seed]*ng), array.array('I',[seed]*ng), array.array('f',[seed]*ng)
                    desc = SPSTASegmentGroupIntegration()
                    desc.m_Graph = group
                    desc.m_Radius = radii
                    desc.m_OutIntegration = UnpackArray(scores,'f')[0]
                    desc.m_OutNodeCount = UnpackArray(counts,'I')[0]
                    desc.m_OutTotalDepth = UnpackArray(depths,'f')[0]
                    ok = native(ctypes.byref(desc))
                    assert ok
                    runs.append(dict(seed=seed, success=ok, integration=values(scores),
                                     node_count=list(counts), total_depth=values(depths)))
                    if unwritten:
                        assert list(scores) == list(depths) == [seed]*ng
                        assert list(counts) == [seed]*ng
                    else:
                        assert all(c <= ng for c in counts)
                if not unwritten:
                    for key in ['integration','node_count','total_depth']:
                        assert runs[0][key] == runs[1][key], (name,key,runs)
                if name == "mixed_isolated_control":
                    assert runs[0]['node_count'][-1] == 0
                    assert runs[0]['total_depth'][-1] == 0
                    assert runs[0]['integration'][-1] == -1
                observed.append(dict(case=name, coords=coords, angle=angle, split=split,
                                     grouping=grouping, analysis_ids=list(ids),
                                     radius=radius_name, outputs_unwritten=unwritten, runs=runs))
        finally:
            if group:
                pst.FreeSegmentGroupGraph(group)
            if segment:
                pst.FreeSegmentGraph(segment)
    print(json.dumps(dict(pin=PIN, cases=observed), indent=2, allow_nan=False))

if __name__ == '__main__':
    main()
