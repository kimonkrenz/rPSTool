#!/usr/bin/env python3
"""Compare direct pinned controls with checked/approved guarded module outputs.
Usage: check-safety-variants.py BASELINE_JSON CHECKED_JSON GUARDED_JSON
"""
import json,pathlib,signal,sys
baseline,checked,guarded=[json.loads(pathlib.Path(p).read_text()) for p in sys.argv[1:4]]
for observed in [baseline,checked,guarded]:
    assert observed['pst_commit']=='63df80a2cf3dd289be95ea3d91667c3490719b75'
    assert observed['verified_blobs']==132
    assert len(observed['cases'])==85
crashes={f'small_radius_{r}_360' for r in [.1,.01,.001,.0001]}
undefined={'degenerate_partial_near_polygon','degenerate_two_point_near_polygon',
           'degenerate_partial_straddling_points'}
controls=0
for original,diagnosed,proposed in zip(baseline['cases'],checked['cases'],guarded['cases']):
    assert original['case']==diagnosed['case']==proposed['case']
    name=original['case']['name']
    if name == 'degenerate_full_near_polygon':
        # PST's custom span bypasses libstdc++ assertions; the focused trace
        # independently proves index=1,size=1 before the unchecked read.
        assert original['returncode']==diagnosed['returncode']==0
        assert proposed['returncode']==0 and proposed['native']==dict(success=False)
    elif name in crashes|undefined:
        assert original['returncode']==(-signal.SIGSEGV if name in crashes else 0)
        assert diagnosed['returncode']==-signal.SIGABRT and 'Assertion' in diagnosed['stderr']
        assert proposed['returncode']==0 and proposed['native']==dict(success=False)
    else:
        assert original['returncode']==diagnosed['returncode']==proposed['returncode']==0
        assert original['native']==diagnosed['native']==proposed['native'],name
        assert original['native']['success'];controls+=1
assert controls==77
print('77 exact unaffected controls (all previous 74 retained); eight unsafe probes fail closed')
