# U2 audit: segment-graph analyses (AI, AC, SG, SGR, FSB)

Pinned upstream: PST v3.3.2 `63df80a2cf3dd289be95ea3d91667c3490719b75` (read-only clone `scratchpad/up/pst`). rPST: branch `audit/pst-interface-parity` (PR #70 head e813552). CSV: `scratchpad/audit/U2-segment.csv` (78 rows, schema per COMMON2.md).

Path note. The pinned clone has no `V/` or `QG/` directories (those are the labels used in rPST's docs). Real paths: engine headers `pstalgo/include/pstalgo/...`, engine sources `pstalgo/src/...`, ctypes wrapper `pstalgo/python/pstalgo/...`, QGIS plugin `pstqgis/src/pst/{analyses,ui/wizards,ui/pages,model}/...`. There are no Processing algorithms for these analyses (`pstqgis/src/pst/processing/` holds only OD Betweenness). The vendored copy `src/vendor/pstalgo` is byte-identical (`cmp`) to the pinned clone for every header/source in this role.

## Classification counts

| class | rows |
|---|---|
| A | 1 |
| D | 29 |
| E | 4 |
| F | 1 |
| G | 43 |

## Headline findings

1. **Hang in `segment_group_graph()` (SGR-011, class E).** A segment whose two endpoints coincide (zero-length) sharing its coordinate with another segment makes `PSTACreateSegmentGroupGraph` loop forever (CPU-bound, flat memory, not interruptible from R). Reproduced with `segment_group_graph(segment_graph(rbind(c(0,0,0,0), c(0,0,1,0))), 1:2)`, also via the normal `segment_grouping()` route. Upstream already knew the underlying data-structure oddity (commit e8816d4 message) but only hardened FastSegmentBetweenness. `segment_grouping`, `angular_choice`, `angular_integration` are unaffected on the same inputs. No rPST test covers it.
2. **Radius rejections are not overly restrictive (AI-006, AC-005, SGR-010).** Native `AngularChoiceAlgo::Run` never reads axmeter and `SegmentGroupIntegration` never reads straight/angular/axmeter; neither validates. They are native-algorithmic no-ops, not native rejections (so not class B for the opposite direction), and rejecting them blocks nothing (class F rejected). The Python side is the odd one: the Angular Integration/Choice wizards offer Axialmeter (default `RadiusPage` list) and silently compute the unrestricted result; the Segment Group Integration wizard disables straight/angular/axmeter (UI-only).
3. **No exposed combination found that native documents as unsupported.** All four radius fields, combined limits, angle settings (including negative thresholds, >180, precision 361 and UINT_MAX), length weighting and the six native normalisers map correctly to the same buffers the plugin uses. Precision 0 (native integer division by zero) is rejected by rPST; the Python layer would crash on it.
4. **Plugin inconsistency that rPST deliberately does not copy (AC-010).** Unweighted Angular Choice never forwards the user's angle threshold/precision (`angularchoiceanalysis.py:154-161`, unchanged since the initial upload a808c54); weighted Choice and both Angular Integration branches do.
5. **Defaults.** Python vs rPST differences: none found for AI/AC/segment grouping. Native descriptor default for the grouping threshold is 0, whereas wrapper, wizard and rPST use 1 (SGR-001).
6. **Fast Segment Betweenness (FSB-001..008).** Not exposed (documented decision). Upstream facts: header limits (angular only, walking radius only, weighting/count/depth "NOT YET SUPPORTED") are contradicted by the implementation (ignores `m_DistanceType`; weights nodes; writes counts and depths) and by the Python test (passes steps/angular radii); the header comments were stale from the commit that added the code (1c166e8).
7. **Minor.** SG-005 (class F, minor): single-part MULTILINESTRING that the plugin accepts is rejected by the sf adapter. SGR-018 (class A, cosmetic): error messages name `pst_segment_graph()` / `pst_segment_group_graph()` instead of the constructors.
8. **Recursion-depth crash (AI-018, AC-017, document only).** Re-read at `AngularChoiceAlgo.cpp:345` (CollectScores) and `:396` (ClearProcessedFlags); not executed.

## Radius type x analysis (UI vs Python vs native vs rPST)

| analysis | straight | walking | steps | angular | axmeter |
|---|---|---|---|---|---|
| Angular Integration / Angular Choice, native | consumed (squared centre test) | consumed | consumed | consumed | **ignored** (never read, no validation) |
| ... QGIS UI / Python | offered | offered | offered | offered | offered (inert) |
| ... rPST | accepted | accepted | accepted | accepted | **rejected** |
| Segment Group Integration, native | ignored | consumed | consumed | ignored | ignored |
| ... QGIS UI / Python | disabled (UI-only) | offered | offered | disabled | disabled |
| ... rPST | rejected | accepted | accepted | rejected | rejected |
| Fast Segment Betweenness, native | ignored | consumed (only) | ignored | ignored | ignored |
| ... QGIS UI | absent | offered | absent | absent | absent |
| ... rPST | not exposed | | | | |

Combinations: AI/AC accept any set of the four consumed fields together in one run (plugin: one combined `Radii`, never split). rPST multi-radius (vector in exactly one field, one native run per value) exists only for AI/AC. Segment Group Integration: native accepts walking+steps together (upstream test), plugin splits per ticked type, rPST runs them combined and rejects vectors.

## Weights x normalisation (which buffer feeds which normaliser)

| analysis | normaliser | unweighted run | length-weighted run | plugin identical? |
|---|---|---|---|---|
| AI | Turner / syntax NAIN / Hillier | node_count, total_depth | total_weight, total_depth_weight (`*LengthWeight` exports) | yes |
| AC | Turner | raw score, node_count | same | yes |
| AC | standard | raw score only | same | yes |
| AC | syntax NACH | total_depth | total_depth_weight | yes (changed in rPST to match; docs/compatibility/qgis-differences.md) |
| FSB (plugin) | syntax | total_depths | total_depths (no depth_weight exists) | n/a (not exposed) |


## Angular Integration (AI)

### AI-001  [D]  graph (segment graph handle)

- **rPST**: `angular_integration` | **native**: `PSTAAngularIntegration` | **QGIS/Python**: pstqgis/src/pst/analyses/angularintegrationanalysis.py + ui/wizards/angularintegrationwiz.py
- native: accepted (unchecked cast of void* to CSegmentGraph, no null/tag check)
- Python/QGIS: available (NetworkInputPage SEGMENT only)
- rPST: accepted (live tagged pst_segment_graph only)
- defaults native / Python / rPST: none / none / none (required)
- evidence: pstalgo/src/analyses/AngularIntegration.cpp:33; pstqgis/src/pst/ui/wizards/angularintegrationwiz.py:208; R/angular-integration.R:69; src/pst-graph.cpp:1172-1177
- discrepancy: rPST validates handle family/liveness before any native access; native and Python do not.
- tests: tests/testthat/test-angular-integration.R:57,78 (forged, wrong-family, dead pointers) | risk: safety (improved) | recommendation: preserve

Native dereferences the void* directly (AngularIntegration.cpp:33). The wizard restricts the layer picker to segment-type input (NetworkTypeFlags.SEGMENT) but does not verify topology. rPST checks the external-pointer tag and live owner (pst-graph.cpp:1172) and the R class/type (R/angular-integration.R:69). Verified by run: axial and group graphs are rejected with 'graph must be a live pst_segment_graph created by segment_graph()'.

### AI-002  [G]  radius$straight x angular_integration

- **rPST**: `angular_integration` | **native**: `PSTAAngularIntegration` | **QGIS/Python**: pstqgis/src/pst/analyses/angularintegrationanalysis.py + ui/wizards/angularintegrationwiz.py
- native: accepted: squared straight distance tested against the origin segment centre for next intersection and next segment centre
- Python/QGIS: available (RadiusPage default list, unchecked by default; 1000 m / 1000 m / 2 steps / 180 deg when ticked)
- rPST: accepted
- defaults native / Python / rPST: unlimited (+inf / UINT_MAX) / unticked => unlimited / NULL => unlimited
- evidence: pstalgo/src/analyses/AngularChoiceAlgo.cpp:166-169,279,290,449; pstalgo/test/tests/testangularintegration.py:36-38; pstqgis/src/pst/ui/pages/radiuspage.py:323-332,341; pstqgis/src/pst/analyses/utils.py:218-224; R/radius.R:96-107; src/pst-graph.cpp:158-205
- discrepancy: none for the field itself; rPST additionally narrows to float and rejects overflow/underflow (see AI-009).
- tests: tests/testthat/test-core-network-analyses.R; fixtures/angular-controls-direct-v3.3.2.R (radii straight=0, straight=9) | risk: none | recommendation: preserve

Native reads this field in AngularChoiceAlgo::Run (449-452) and the shared traversal. Verified by run on a 5-segment chain (side 3): straight radius = 4 gives node counts per the upstream test shape. All four are covered by upstream python tests and by rPST direct-native fixtures.

### AI-003  [G]  radius$walking x angular_integration

- **rPST**: `angular_integration` | **native**: `PSTAAngularIntegration` | **QGIS/Python**: pstqgis/src/pst/analyses/angularintegrationanalysis.py + ui/wizards/angularintegrationwiz.py
- native: accepted: accumulates (len+next len)/2 per step
- Python/QGIS: available (RadiusPage default list, unchecked by default; 1000 m / 1000 m / 2 steps / 180 deg when ticked)
- rPST: accepted
- defaults native / Python / rPST: unlimited (+inf / UINT_MAX) / unticked => unlimited / NULL => unlimited
- evidence: pstalgo/src/analyses/AngularChoiceAlgo.cpp:293-295,450; pstalgo/test/tests/testangularintegration.py:39-41; pstqgis/src/pst/ui/pages/radiuspage.py:323-332,341; pstqgis/src/pst/analyses/utils.py:218-224; R/radius.R:96-107; src/pst-graph.cpp:158-205
- discrepancy: none for the field itself; rPST additionally narrows to float and rejects overflow/underflow (see AI-009).
- tests: fixtures/angular-controls-direct-v3.3.2.R (walking=4); test-multi-radius.R | risk: none | recommendation: preserve

Native reads this field in AngularChoiceAlgo::Run (449-452) and the shared traversal. Verified by run on a 5-segment chain (side 3): walking radius = 4 gives node counts per the upstream test shape. All four are covered by upstream python tests and by rPST direct-native fixtures.

### AI-004  [G]  radius$steps x angular_integration

- **rPST**: `angular_integration` | **native**: `PSTAAngularIntegration` | **QGIS/Python**: pstqgis/src/pst/analyses/angularintegrationanalysis.py + ui/wizards/angularintegrationwiz.py
- native: accepted: AccSteps < limit gate on expansion
- Python/QGIS: available (RadiusPage default list, unchecked by default; 1000 m / 1000 m / 2 steps / 180 deg when ticked)
- rPST: accepted
- defaults native / Python / rPST: unlimited (+inf / UINT_MAX) / unticked => unlimited / NULL => unlimited
- evidence: pstalgo/src/analyses/AngularChoiceAlgo.cpp:275,452; pstalgo/test/tests/testangularintegration.py:42-44; pstqgis/src/pst/ui/pages/radiuspage.py:323-332,341; pstqgis/src/pst/analyses/utils.py:218-224; R/radius.R:96-107; src/pst-graph.cpp:158-205
- discrepancy: none for the field itself; rPST additionally narrows to float and rejects overflow/underflow (see AI-009).
- tests: fixtures/angular-controls-direct-v3.3.2.R (steps=1); test-angular-integration.R:13 | risk: none | recommendation: preserve

Native reads this field in AngularChoiceAlgo::Run (449-452) and the shared traversal. Verified by run on a 5-segment chain (side 3): steps radius = 4 gives node counts per the upstream test shape. All four are covered by upstream python tests and by rPST direct-native fixtures.

### AI-005  [G]  radius$angular x angular_integration

- **rPST**: `angular_integration` | **native**: `PSTAAngularIntegration` | **QGIS/Python**: pstqgis/src/pst/analyses/angularintegrationanalysis.py + ui/wizards/angularintegrationwiz.py
- native: accepted: accumulated unrounded turning degrees compared with limit
- Python/QGIS: available (RadiusPage default list, unchecked by default; 1000 m / 1000 m / 2 steps / 180 deg when ticked)
- rPST: accepted
- defaults native / Python / rPST: unlimited (+inf / UINT_MAX) / unticked => unlimited / NULL => unlimited
- evidence: pstalgo/src/analyses/AngularChoiceAlgo.cpp:303-305,451; pstalgo/test/tests/testangularintegration.py:45,54-55; pstqgis/src/pst/ui/pages/radiuspage.py:323-332,341; pstqgis/src/pst/analyses/utils.py:218-224; R/radius.R:96-107; src/pst-graph.cpp:158-205
- discrepancy: none for the field itself; rPST additionally narrows to float and rejects overflow/underflow (see AI-009).
- tests: fixtures/angular-controls-direct-v3.3.2.R (angular=90) | risk: none | recommendation: preserve

Native reads this field in AngularChoiceAlgo::Run (449-452) and the shared traversal. Verified by run on a 5-segment chain (side 3): angular radius = 4 gives node counts per the upstream test shape. All four are covered by upstream python tests and by rPST direct-native fixtures.

### AI-006  [D]  radius$axmeter x angular_integration

- **rPST**: `angular_integration` | **native**: `PSTAAngularIntegration` | **QGIS/Python**: pstqgis/src/pst/analyses/angularintegrationanalysis.py + ui/wizards/angularintegrationwiz.py
- native: accepted but IGNORED (field never read; Run does no validation and returns true)
- Python/QGIS: available (default RadiusPage list includes 'Axialmeter', steps*m) and forwarded by RadiiFromSettings
- rPST: rejected (any value, including 0 and in a multi-radius vector)
- defaults native / Python / rPST: unlimited / unticked / NULL
- evidence: pstalgo/src/analyses/AngularChoiceAlgo.cpp:449-452 (only Straight, Walking, Angular, Steps read); pstalgo/src/analyses/AngularChoiceAlgo.cpp:429-526 (no radius validation); pstqgis/src/pst/ui/pages/radiuspage.py:331-332,341; pstqgis/src/pst/analyses/utils.py:224; src/pst-graph.cpp:195-196; R/radius.R:103-104; docs/pst-coverage.md 3.4
- discrepancy: QGIS lets the user tick axmeter and silently computes the unrestricted result; rPST errors.
- tests: tests/testthat/test-angular-controls.R:89; test-core-network-analyses.R:201-203; test-multi-radius.R:40-41 | risk: none | recommendation: preserve (rejection prevents a silent no-op; the plugin result is reproduced by omitting the field)

Source: the radius setup in Run copies straight, walking, angular and steps into m_Radius; axmeter is not read anywhere in the algorithm (grep of AngularChoiceAlgo.cpp). So the native layer ACCEPTS the field (no validation, returns true) and ignores it; this is a native-algorithmic limit, NOT a native rejection (so not class B). The Python layer actively offers the control (RadiusPage default radius_types contains AXMETER) and passes it through (RadiiFromSettings), so the restriction is entirely rPST's. Class F was considered and rejected: accepting the field would not unlock any supported native functionality; the only observable effect would be a silent identical-to-unrestricted result, which the maintainers documented as undesirable (qgis-differences.md 'Unsupported axmeter in angular analyses'). Verified by run: radius axmeter=4 and axmeter=0 both error with 'axmeter radius is unsupported by the pinned angular engine.' Restriction history: git blame shows src/pst-graph.cpp:195-196 introduced at the grafted root 4768003 (2026-10-08); git log -S shows d623298 (2026-10-09 'Correct current architecture, native contracts and roadmap documentation') carrying the R-level twin. No commit message explains it; rationale is only in docs/pst-coverage.md row 3.4 (evidence S + E: plugin axmeter=20 equals 0.001 equals unrestricted).

### AI-007  [D]  steps (legacy positional) vs radius

- **rPST**: `angular_integration` | **native**: `PSTAAngularIntegration` | **QGIS/Python**: pstqgis/src/pst/analyses/angularintegrationanalysis.py + ui/wizards/angularintegrationwiz.py
- native: n/a (R-API only)
- Python/QGIS: absent
- rPST: accepted (steps xor radius; both => error)
- defaults native / Python / rPST: n/a / n/a / steps=NULL, radius=NULL
- evidence: R/angular-integration.R:36-37,65,71; R/radius.R:142-148; tests/testthat/test-angular-controls.R:88
- discrepancy: Only angular_integration has a steps argument; angular_choice does not (asymmetric API); positional step calls kept for backward compatibility.
- tests: test-angular-controls.R:88 ('either'); test-angular-integration.R:84-88 | risk: usability | recommendation: preserve

Verified by run: angular_integration(g, steps=1, radius=analysis_radius(steps=1)) => 'Supply either steps or radius, not both.'; steps=c(1,2) and steps='1' are rejected (steps must be one whole number); multi-steps must go through analysis_radius(steps=c(1,2)). Native radius is the single SPSTARadii; the legacy argument is only an R convenience. angular_choice(radius=) has no steps shortcut.

### AI-008  [G]  radius: several fields at once (combined limits)

- **rPST**: `angular_integration` | **native**: `PSTAAngularIntegration` | **QGIS/Python**: pstqgis/src/pst/analyses/angularintegrationanalysis.py + ui/wizards/angularintegrationwiz.py
- native: accepted (all four consumed together; upstream tests only exercise single fields)
- Python/QGIS: available (one combined Radii; NOT split, unlike Reach/Betweenness)
- rPST: accepted (any combination of non-varying fields)
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: pstqgis/src/pst/analyses/angularintegrationanalysis.py:81,92-102,127-137; pstalgo/src/analyses/AngularChoiceAlgo.cpp:449-452; docs/compatibility/qgis-differences.md (Radius combinations); tests/testthat/fixtures/angular-controls-direct-v3.3.2.R
- discrepancy: none (rPST matches plugin: one combined run). Combination is oracle-tested only through rPST's own direct-native fixture, not an upstream test.
- tests: generate-reference.py:177 radius set includes straight=9,walking=9,steps=2,angular=180 | risk: none | recommendation: preserve

Python calls RadiiFromSettings once (line 81) and reuses it for both weight modes; no .split(). Verified by run: AI radius with walking+angular fixed and AC multi on a different field works (angular_choice(g, analysis_radius(walking=c(3,6), angular=180))).

### AI-009  [D]  radius value domain (finite, >=0, float narrowing, steps<=INT_MAX, straight^2 finite)

- **rPST**: `angular_integration` | **native**: `PSTAAngularIntegration` | **QGIS/Python**: pstqgis/src/pst/analyses/angularintegrationanalysis.py + ui/wizards/angularintegrationwiz.py
- native: accepted (no validation; float/uint fields; negative steps => huge unsigned)
- Python/QGIS: available (free-text QLineEdit; unparsable text silently falls back to default; no range check)
- rPST: accepted only within domain; Inf, NA, negative, >FLT_MAX, underflow-to-0, straight>~1.8e19 rejected
- defaults native / Python / rPST: n/a / 1000/1000/2/180 when ticked / n/a
- evidence: pstalgo/include/pstalgo/analyses/Common.h:76-110; pstalgo/python/pstalgo/common.py:103,165-168; pstqgis/src/pst/ui/wizard/wizard.py:108-124; src/pst-graph.cpp:158-205; R/radius.R:77-107
- discrepancy: rPST is stricter than both lower layers. Inf and huge straight (square overflows float) are rejected although native would treat them as unlimited; NULL expresses unlimited.
- tests: test-core-network-analyses.R:193-196; test-angular-integration.R:84-88 | risk: none | recommendation: preserve

Not class F: every rejected value has an accepted equivalent (NULL for unlimited, 0 for zero). Verified by run: walking=Inf, NA, 1e39, 1e-50 and straight=1e20 error; steps=2147483647 accepted, 2147483648 rejected. Note SPSTARadii::m_Steps is int (Common.h:107) while the Python field is c_uint (common.py:103): the signed/unsigned mismatch is the reason steps is capped at INT_MAX in rPST.

### AI-010  [D]  radius multi-value (multi-radius vectors, one varying field)

- **rPST**: `angular_integration` | **native**: `PSTAAngularIntegration` | **QGIS/Python**: pstqgis/src/pst/analyses/angularintegrationanalysis.py + ui/wizards/angularintegrationwiz.py
- native: n/a (one radius per native call; rPST loops native)
- Python/QGIS: absent for AI/AC (combined Radii only)
- rPST: accepted for straight, walking, steps, angular (axmeter rejected); two varying fields rejected; duplicates rejected
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: R/radius.R:31-60,77-90; R/angular-multi.R:108-122; docs/compatibility/multi-radius.md; src/pst-graph.cpp:1749-1760; tests/testthat/test-multi-radius.R:134-170
- discrepancy: rPST extension; each radius = one full native run (no cap on vector length).
- tests: test-multi-radius.R:134 (every column equals scalar call); test-multi-radius-direct.R; fixtures/angular-multi-radius-direct-v3.3.2.R | risk: performance (k radii => k native runs and n*k columns; unbounded k) | recommendation: preserve

Verified by run: analysis_radius(walking=c(3,6), steps=c(1,2)) => 'At most one analysis_radius() field may have several values ... Cartesian product'; duplicate values rejected; axmeter vector rejected even as a fixed field alongside a varying one; tags such as integration_turner_a90 and node_count_n1 appear. Correctness is oracle-tested against scalar calls and a direct-native multi fixture, so class D, with an unbounded-k performance caveat.

### AI-011  [G]  weigh_by_length

- **rPST**: `angular_integration` | **native**: `PSTAAngularIntegration (weigh_by_length)` | **QGIS/Python**: pstqgis/src/pst/analyses/angularintegrationanalysis.py + ui/wizards/angularintegrationwiz.py
- native: accepted (bool)
- Python/QGIS: available as two checkboxes calc_no_weight / calc_length_weight (at least one; runs the native analysis once per ticked mode)
- rPST: accepted (single logical per call; NA rejected)
- defaults native / Python / rPST: FALSE / no weights ON, length weight OFF / FALSE
- evidence: pstalgo/include/pstalgo/analyses/AngularIntegration.h:41; pstqgis/src/pst/ui/wizards/angularintegrationwiz.py:231-232,247-248; pstqgis/src/pst/analyses/angularintegrationanalysis.py:88,125; R/angular-integration.R:66; src/pst-graph.cpp:1080-1084
- discrepancy: Plugin can do both modes in one wizard run; rPST needs two calls (same two native runs).
- tests: test-angular-controls.R:9,57 | risk: none | recommendation: preserve

Equivalent behaviour. Verified: weigh_by_length=NA and =1 error ('must be TRUE or FALSE').

### AI-012  [G]  normalization names x weights (which buffer feeds which normaliser)

- **rPST**: `angular_integration` | **native**: `PSTAAngularIntegration*Normalize* (6 exports)` | **QGIS/Python**: pstqgis/src/pst/analyses/angularintegrationanalysis.py + ui/wizards/angularintegrationwiz.py
- native: accepted (6 exports: Normalize/SyntaxNormalize/HillierNormalize and *LengthWeight)
- Python/QGIS: available: Turner (default ON), Syntax NAIN, Hillier; >=1 required; no 'none'/'standard'
- rPST: accepted: 'turner' (default), 'syntax', 'hillier' or a vector; 'none','standard' and wrong case rejected
- defaults native / Python / rPST: n/a / Turner only / turner
- evidence: pstalgo/src/analyses/AngularIntegration.cpp:47-81 (unweighted: N,TD; LengthWeight: reached_length=total_weight, TDL=total_depth_weight); pstqgis/src/pst/analyses/angularintegrationanalysis.py:105,109,113 (weighted), 140,144,148 (unweighted); src/pst-graph.cpp:1145-1163; R/angular-integration.R:72; R/angular-multi.R:31
- discrepancy: none. Mapping identical: weighted run feeds (total_weight, total_depth_weight) to the *LengthWeight normalisers; unweighted feeds (node_count, total_depth).
- tests: test-angular-controls.R:9 (every case/normaliser vs direct native) | risk: none | recommendation: preserve

Verified by run on a 5-segment graph: weighted syntax gives total_weight=12, total_depth_weight=18 columns and integration 1.038 for segment 1; 'none', 'standard' and 'Turner' are rejected with 'normalization must be one of: turner, syntax, hillier'. The header comment says LengthWeight's first parameter is 'reached_length' (total_weight excludes the origin; docs/compatibility/angular-controls.md documents this).

### AI-013  [G]  angle_threshold

- **rPST**: `angular_integration` | **native**: `PSTAAngularIntegration` | **QGIS/Python**: pstqgis/src/pst/analyses/angularintegrationanalysis.py + ui/wizards/angularintegrationwiz.py
- native: accepted (float; turns strictly below it become 0; no validation)
- Python/QGIS: available (default 0, 2 decimals, forwarded in BOTH weight branches)
- rPST: accepted: one finite number fitting a float without nonzero underflow; negative and >180 accepted
- defaults native / Python / rPST: 0 / 0 / 0
- evidence: pstalgo/include/pstalgo/analyses/AngularIntegration.h:42; pstalgo/src/analyses/AngularChoiceAlgo.cpp:300-301; pstqgis/src/pst/ui/wizards/angularintegrationwiz.py:239; pstqgis/src/pst/analyses/angularintegrationanalysis.py:96,130; src/pst-graph.cpp:1064-1072
- discrepancy: none; rPST rejects NA/NaN/Inf/1e-50 which native would take as raw floats.
- tests: test-angular-controls.R:76-112; generate-reference.py:176 settings (0,20,90,90.00001,181,-1) | risk: none | recommendation: preserve

Verified by run: threshold -5 (finite negative) accepted and equals 0 behaviour; 200 zeroes every turn (total_depth all 0); NA and 1e-50 rejected. Semantics are strict '<' (AngularChoiceAlgo.cpp:300), unlike segment_grouping which is inclusive (see SGR-001).

### AI-014  [D]  angle_precision

- **rPST**: `angular_integration` | **native**: `PSTAAngularIntegration` | **QGIS/Python**: pstqgis/src/pst/analyses/angularintegrationanalysis.py + ui/wizards/angularintegrationwiz.py
- native: accepted for >=1; precision 0 => 360/0 integer division in queue init (undefined behaviour, SIGFPE on x86)
- Python/QGIS: available (default 1, 0 decimals, text field; wrapper int() truncates 1.5; 0 is not rejected)
- rPST: accepted: whole numbers 1..4294967295; 0, non-whole, NA, >UINT_MAX rejected
- defaults native / Python / rPST: 1 / 1 / 1
- evidence: pstalgo/include/pstalgo/analyses/AngularIntegration.h:43; pstalgo/src/analyses/AngularChoiceAlgo.cpp:54,161-164; pstalgo/include/pstalgo/utils/DiscretePrioQueue.h (circular buckets, range must exceed one step delta); pstalgo/python/pstalgo/angularintegration.py:67; pstqgis/src/pst/ui/wizards/angularintegrationwiz.py:238; src/pst-graph.cpp:1073-1079
- discrepancy: rPST rejects the value that crashes native; Python does not.
- tests: test-angular-controls.R:76-112 (0,-1,1.1,4294967296, NA); fixtures include precision 361 and UINT_MAX | risk: none | recommendation: preserve

Not an overly restrictive rejection: precision 0 is native undefined behaviour (queue Init(360/0+1)). I checked the large-precision acceptance for safety: the queue holds 360/p+1 buckets and a single step inserts at most (unsigned)(180/p+0.5) ahead; for every integer p >= 1 the bucket count exceeds that delta by at least one, so the circular queue's range assumption holds (hand analysis, plus fixtures at p=361 and UINT_MAX). Verified by run: 361 and 4294967295 accepted (identical results with each other, differing from p=1 because paths tie differently), 0, 1.5 and 4294967296 rejected.

### AI-015  [D]  weight_outputs (total_weight, total_depth_weight columns)

- **rPST**: `angular_integration` | **native**: `PSTAAngularIntegration` | **QGIS/Python**: pstqgis/src/pst/analyses/angularintegrationanalysis.py + ui/wizards/angularintegrationwiz.py
- native: accepted (optional output arrays m_OutTotalWeights / m_OutTotalDepthWeights, written for either weight mode)
- Python/QGIS: available only implicitly: arrays allocated and normalisers fed only in the length-weighted branch; never emitted as columns
- rPST: accepted (FALSE default; weighted mode always returns them)
- defaults native / Python / rPST: NULL pointers / unweighted: None / FALSE
- evidence: pstalgo/include/pstalgo/analyses/AngularIntegration.h:51-54; pstqgis/src/pst/analyses/angularintegrationanalysis.py:90-91,136-137; src/pst-graph.cpp:1116-1138; R/angular-integration.R:44,97-100
- discrepancy: rPST extension (unweighted total_weight = number of other reached segments, depth_weight = unweighted TD).
- tests: test-angular-controls.R:57 (origin-weight exclusion); direct fixtures cover every output | risk: none | recommendation: preserve

Verified by run: unweighted + weight_outputs=TRUE returns total_weight 4 (= reached-1) and total_depth_weight equal to the unit-weighted depth sum, consistent with the algorithm (lines 263-266). The argument does not exist on angular_choice.

### AI-016  [G]  output options (N, TD, MD)

- **rPST**: `angular_integration` | **native**: `PSTAAngularIntegration` | **QGIS/Python**: pstqgis/src/pst/analyses/angularintegrationanalysis.py + ui/wizards/angularintegrationwiz.py
- native: accepted (optional output arrays)
- Python/QGIS: available (OutputPage checkboxes, default all ON; MD = TD/(N-1), 0 if N<=1)
- rPST: N and TD always returned; MD not provided (one-line R computation)
- defaults native / Python / rPST: NULL / N,TD,MD ON / always N, TD
- evidence: pstqgis/src/pst/ui/wizards/angularintegrationwiz.py:266-268; pstqgis/src/pst/analyses/utils.py:242-245; pstqgis/src/pst/analyses/angularintegrationanalysis.py:115-122; R/angular-integration.R:95-101; docs/pst-coverage.md (Python-side conveniences)
- discrepancy: rPST cannot omit N/TD, provides no MD.
- tests: test-angular-integration.R:13 | risk: none | recommendation: preserve

Conveniences computed in Python only; documented as not provided.

### AI-017  [D]  segment graph with >32 segments at one coordinate

- **rPST**: `angular_integration` | **native**: `PSTAAngularIntegration` | **QGIS/Python**: pstqgis/src/pst/analyses/angularintegrationanalysis.py + ui/wizards/angularintegrationwiz.py
- native: accepted-but-undefined (only ASSERT(index<32); outgoing-path mask is 32 bits)
- Python/QGIS: available (no check)
- rPST: rejected (max_degree>32)
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: pstalgo/src/analyses/AngularChoiceAlgo.cpp:98-99; src/pst-graph.cpp:1176-1177,1606; docs/pst-coverage.md 3.11; tests/testthat/test-angular-integration.R:94-98
- discrepancy: rPST guard; native has release-mode UB for the mask.
- tests: test-angular-integration.R:94-98; test-core-network-analyses.R:162-165 | risk: correctness (prevents wrong N) | recommendation: preserve

Verified by run: a 33-spoke star errors for both angular_choice and angular_integration with '...at most 32 endpoint incidences...'. The guard counts incidences per exact coordinate (a zero-length segment contributes two). The guard is NOT applied to segment_grouping / segment_group_graph, which do not use the mask (a 33-spoke star groups fine; documented 40-incidence fixture in segment-groups.md).

### AI-018  [E]  recursion depth in ClearProcessedFlags (document only)

- **rPST**: `angular_integration` | **native**: `PSTAAngularIntegration` | **QGIS/Python**: pstqgis/src/pst/analyses/angularintegrationanalysis.py + ui/wizards/angularintegrationwiz.py
- native: accepted; recursion unbounded (one frame per shortest-path out-step along a chain)
- Python/QGIS: available (same engine, unrestricted radius by default)
- rPST: accepted (no guard; documented)
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: pstalgo/src/analyses/AngularChoiceAlgo.cpp:76,374-399 (recursive call at 396); docs/compatibility/angular-controls.md 'Known limitation'; R/core-analyses.R:190-200
- discrepancy: Inherited upstream stack-exhaustion risk on very long near-collinear chains with unrestricted or angular-only radius; process termination, not an R error.
- tests: none found (documented only; deliberately not stress-tested) | risk: safety (process crash on pathological chains; maintainer-confirmed macOS ARM64 8,000-segment collinear chain for Choice) | recommendation: investigate (documented limitation; AI shares only ClearProcessedFlags, higher tolerance: ~11,000 segments at 512 KB stack per docs)

Source facts re-read in the pinned file: ClearProcessedFlags(segment, forwards) recurses at line 396 for every out-segment bit; it runs for every origin in both analyses (Run, line 76). CollectNSCScores/CollectScores is Choice-only. I did NOT run any stress test (per instructions). Classified E because the combination (unrestricted radius on a long chain) is accepted without a guard and evidence is only synthetic-chain measurements recorded in docs; AI is much less exposed than AC (AC-017).

### AI-019  [D]  worker threads

- **rPST**: `angular_integration` | **native**: `PSTAAngularIntegration` | **QGIS/Python**: pstqgis/src/pst/analyses/angularintegrationanalysis.py + ui/wizards/angularintegrationwiz.py
- native: accepted (hardware_concurrency() workers via std::async)
- Python/QGIS: available (not configurable)
- rPST: accepted; build-time central cap RPST_NUM_THREADS / _R_CHECK_LIMIT_CORES_ on generated build copies
- defaults native / Python / rPST: hardware_concurrency / same / same unless capped
- evidence: pstalgo/src/analyses/AngularChoiceAlgo.cpp:416,466-499; src/portability/limit-workers.R:4-30; docs/compatibility/core-network-analyses.md (Threading)
- discrepancy: rPST adds a worker cap and future.get() error propagation via generated build copies; pristine vendor bytes unchanged (verified: vendored headers/sources identical to pinned clone by cmp).
- tests: tests/testthat/test-workers.R | risk: none | recommendation: preserve

Vendored files for all analyses in this role are byte-identical to the pinned clone (cmp). Patch mechanism documented in inst/upstream/PATCHES.md.

### AI-020  [G]  degenerate geometry: zero-length and duplicate segments

- **rPST**: `angular_integration` | **native**: `PSTAAngularIntegration` | **QGIS/Python**: pstqgis/src/pst/analyses/angularintegrationanalysis.py + ui/wizards/angularintegrationwiz.py
- native: accepted (CSegmentGraph::Create does not reject; a zero-length segment lists itself twice in its intersection)
- Python/QGIS: available
- rPST: accepted
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: pstalgo/src/graph/SegmentGraph.cpp:117-128; tools/reference/angular/generate-reference.py:173 (zero_length graph); tests/testthat/helper-spatial-output.R:7
- discrepancy: none for AI/AC (works); but see SGR-011 for a hang in segment_group_graph.
- tests: angular direct fixture 'zero_length' graph | risk: none for this function | recommendation: preserve

Verified by run: a zero-length segment in a 3-segment chain, a single segment, and (angular_choice only) exact duplicate segments return normal results; zero-length graphs were also run through angular_integration.

### AI-021  [D]  output_file / overwrite / spatial_output_file

- **rPST**: `angular_integration` | **native**: `PSTAAngularIntegration` | **QGIS/Python**: pstqgis/src/pst/analyses/angularintegrationanalysis.py + ui/wizards/angularintegrationwiz.py
- native: n/a
- Python/QGIS: absent (columns written to the QGIS layer)
- rPST: accepted (rPST extension)
- defaults native / Python / rPST: n/a / n/a / NULL/FALSE/NULL
- evidence: R/angular-integration.R:45-57,78-92; docs/spatial-io/result-files.md
- discrepancy: rPST-only I/O layer; out of scope for numeric parity.
- tests: tests/testthat/test-result-file.R; test-spatial-output.R; test-multi-radius-parquet.R | risk: none | recommendation: preserve

Not audited beyond confirming the same single native call feeds both routes (pst-graph.cpp:1592-1631).


## Angular Choice (AC)

### AC-001  [G]  radius$straight x angular_choice

- **rPST**: `angular_choice` | **native**: `PSTAAngularChoice` | **QGIS/Python**: pstqgis/src/pst/analyses/angularchoiceanalysis.py + ui/wizards/angularchoicewiz.py
- native: accepted (same Run as Angular Integration)
- Python/QGIS: available (RadiusPage default list)
- rPST: accepted
- defaults native / Python / rPST: unlimited / unticked => unlimited / analysis_radius() => unlimited
- evidence: pstalgo/src/analyses/AngularChoiceAlgo.cpp:449-452; pstalgo/test/tests/testangularchoice.py:35-37; pstqgis/src/pst/ui/wizards/angularchoicewiz.py:14; R/core-analyses.R:245; src/pst-graph.cpp:1535-1545
- discrepancy: none
- tests: fixtures/angular-controls-direct-v3.3.2.R; test-multi-radius.R:76 | risk: none | recommendation: preserve

Same engine and gating as AI-002. Upstream choice tests assert the straight radius against 5-line chain oracles. Verified by run (chain, radius=4): node counts identical to Angular Integration.

### AC-002  [G]  radius$walking x angular_choice

- **rPST**: `angular_choice` | **native**: `PSTAAngularChoice` | **QGIS/Python**: pstqgis/src/pst/analyses/angularchoiceanalysis.py + ui/wizards/angularchoicewiz.py
- native: accepted (same Run as Angular Integration)
- Python/QGIS: available (RadiusPage default list)
- rPST: accepted
- defaults native / Python / rPST: unlimited / unticked => unlimited / analysis_radius() => unlimited
- evidence: pstalgo/src/analyses/AngularChoiceAlgo.cpp:449-452; pstalgo/test/tests/testangularchoice.py:38-40; pstqgis/src/pst/ui/wizards/angularchoicewiz.py:14; R/core-analyses.R:245; src/pst-graph.cpp:1535-1545
- discrepancy: none
- tests: fixtures/angular-controls-direct-v3.3.2.R; test-multi-radius.R:76 | risk: none | recommendation: preserve

Same engine and gating as AI-003. Upstream choice tests assert the walking radius against 5-line chain oracles. Verified by run (chain, radius=4): node counts identical to Angular Integration.

### AC-003  [G]  radius$steps x angular_choice

- **rPST**: `angular_choice` | **native**: `PSTAAngularChoice` | **QGIS/Python**: pstqgis/src/pst/analyses/angularchoiceanalysis.py + ui/wizards/angularchoicewiz.py
- native: accepted (same Run as Angular Integration)
- Python/QGIS: available (RadiusPage default list)
- rPST: accepted
- defaults native / Python / rPST: unlimited / unticked => unlimited / analysis_radius() => unlimited
- evidence: pstalgo/src/analyses/AngularChoiceAlgo.cpp:449-452; pstalgo/test/tests/testangularchoice.py:41-43; pstqgis/src/pst/ui/wizards/angularchoicewiz.py:14; R/core-analyses.R:245; src/pst-graph.cpp:1535-1545
- discrepancy: none
- tests: fixtures/angular-controls-direct-v3.3.2.R; test-multi-radius.R:76 | risk: none | recommendation: preserve

Same engine and gating as AI-004. Upstream choice tests assert the steps radius against 5-line chain oracles. Verified by run (chain, radius=4): node counts identical to Angular Integration.

### AC-004  [G]  radius$angular x angular_choice

- **rPST**: `angular_choice` | **native**: `PSTAAngularChoice` | **QGIS/Python**: pstqgis/src/pst/analyses/angularchoiceanalysis.py + ui/wizards/angularchoicewiz.py
- native: accepted (same Run as Angular Integration)
- Python/QGIS: available (RadiusPage default list)
- rPST: accepted
- defaults native / Python / rPST: unlimited / unticked => unlimited / analysis_radius() => unlimited
- evidence: pstalgo/src/analyses/AngularChoiceAlgo.cpp:449-452; pstalgo/test/tests/testangularchoice.py:44,53-54; pstqgis/src/pst/ui/wizards/angularchoicewiz.py:14; R/core-analyses.R:245; src/pst-graph.cpp:1535-1545
- discrepancy: none
- tests: fixtures/angular-controls-direct-v3.3.2.R; test-multi-radius.R:76 | risk: none | recommendation: preserve

Same engine and gating as AI-005. Upstream choice tests assert the angular radius against 5-line chain oracles. Verified by run (chain, radius=4): node counts identical to Angular Integration.

### AC-005  [D]  radius$axmeter x angular_choice

- **rPST**: `angular_choice` | **native**: `PSTAAngularChoice` | **QGIS/Python**: pstqgis/src/pst/analyses/angularchoiceanalysis.py + ui/wizards/angularchoicewiz.py
- native: accepted but IGNORED (as AI-006)
- Python/QGIS: available (default RadiusPage list)
- rPST: rejected (also as a fixed field next to a varying one, and as a vector)
- defaults native / Python / rPST: unlimited / unticked / NULL
- evidence: pstalgo/src/analyses/AngularChoiceAlgo.cpp:449-452; pstqgis/src/pst/ui/wizards/angularchoicewiz.py:14; src/pst-graph.cpp:195-196,1541; R/radius.R:103-104
- discrepancy: as AI-006
- tests: test-multi-radius.R:40-41; test-core-network-analyses.R:202 | risk: none | recommendation: preserve

Verified by run: axmeter=5, walking=c(3,6)+axmeter=1, and axmeter=c(3,6) all error. Classification reasoning identical to AI-006 (not F, not B).

### AC-006  [D]  radius multi-value (multi-radius)

- **rPST**: `angular_choice` | **native**: `PSTAAngularChoice` | **QGIS/Python**: pstqgis/src/pst/analyses/angularchoiceanalysis.py + ui/wizards/angularchoicewiz.py
- native: n/a (looped over single native runs)
- Python/QGIS: absent (radii_list .split() existed at a808c54 but is dead code, removed in 1c166e8)
- rPST: accepted (as AI-010)
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: pstqgis/src/pst/analyses/angularchoiceanalysis.py:50 (single RadiiFromSettings); git show a808c54:...angularchoiceanalysis.py:43 (unused radii_list); git show 1c166e8 (removes it); R/angular-multi.R:94-106; src/pst-graph.cpp:1732-1745
- discrepancy: rPST extension; the pinned plugin never split Choice radii.
- tests: test-multi-radius.R:76-114 | risk: performance (unbounded k) | recommendation: preserve

History: the unused `radii_list = ... .split()` line existed in the first upload (a808c54, 2019-11-18) and was deleted in 1c166e8 (2021-03-02, 'New analysis Angular Betweenness ...') without comment; at no pinned revision does Choice actually run per split radius. Verified by run: names such as choice_w3, choice_turner_w3, node_count_w6.

### AC-007  [G]  weigh_by_length

- **rPST**: `angular_choice` | **native**: `PSTAAngularChoice (weigh_by_length)` | **QGIS/Python**: pstqgis/src/pst/analyses/angularchoiceanalysis.py + ui/wizards/angularchoicewiz.py
- native: accepted
- Python/QGIS: available (weight_none / weight_length checkboxes; both => two native runs)
- rPST: accepted (single logical)
- defaults native / Python / rPST: FALSE / no weight ON, length OFF / FALSE
- evidence: pstalgo/include/pstalgo/analyses/AngularChoice.h:43; pstalgo/src/analyses/AngularChoice.cpp:31; pstqgis/src/pst/ui/wizards/angularchoicewiz.py:35-38; pstqgis/src/pst/analyses/angularchoiceanalysis.py:96,127; R/core-analyses.R:245
- discrepancy: plugin handles both in one wizard run, rPST needs two calls
- tests: test-angular-controls.R:9,113 | risk: none | recommendation: preserve

Weighted choice semantics (origin gets half, destinations get half; AngularChoiceAlgo.cpp:208-219,365-370) are native and tested against upstream oracles.

### AC-008  [G]  normalization x weights: Turner / standard (buffer feeding)

- **rPST**: `angular_choice` | **native**: `PSTAAngularChoiceNormalize / SyntaxNormalize / PSTAStandardNormalize` | **QGIS/Python**: pstqgis/src/pst/analyses/angularchoiceanalysis.py + ui/wizards/angularchoicewiz.py
- native: accepted
- Python/QGIS: available (None, Turner, Standard, Syntax; at least one; default None)
- rPST: accepted ('none' default, 'standard', 'turner', 'syntax' or vector; 'hillier' rejected)
- defaults native / Python / rPST: n/a / No Normalization / none
- evidence: pstalgo/src/analyses/AngularChoice.cpp:61-72; pstqgis/src/pst/analyses/angularchoiceanalysis.py:119-122,149-150 (Turner uses total_counts), 125-126,152-153 (standard uses raw scores); src/pst-graph.cpp:1513-1523
- discrepancy: none; Turner always receives node_count, standard receives raw scores, in both weight modes (as plugin).
- tests: test-angular-controls.R:9 | risk: none | recommendation: preserve

Native Turner is score/((N-1)(N-2)) for N>2 else unchanged (line 64). Verified by run: normalization c('none','standard','turner','syntax') returns choice_standard, choice_turner, choice_syntax columns with the raw 'choice' always kept (the plugin may omit the raw column by unticking 'No Normalization').

### AC-009  [G]  normalization='syntax' x weigh_by_length (TD vs total_depth_weight)

- **rPST**: `angular_choice` | **native**: `PSTAAngularChoiceSyntaxNormalize` | **QGIS/Python**: pstqgis/src/pst/analyses/angularchoiceanalysis.py + ui/wizards/angularchoicewiz.py
- native: accepted (agnostic to which depth array is passed)
- Python/QGIS: available: weighted run passes total_depth_weights, unweighted passes total_depths
- rPST: accepted; same mapping
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: pstalgo/src/analyses/AngularChoice.cpp:67-72; pstqgis/src/pst/analyses/angularchoiceanalysis.py:128 (weighted), 177 (unweighted); src/pst-graph.cpp:1520; docs/compatibility/qgis-differences.md (Alignments); tests/testthat/test-angular-controls.R:113
- discrepancy: none now (earlier rPST development behaviour used total_depth in weighted mode; changed to match the plugin).
- tests: test-angular-controls.R:113,137 | risk: none | recommendation: preserve

Verified by run: weighted syntax on the 5-segment test graph returns total_depth_weight 18/15/12... and normalized 1.278032 for segment 1 = log10(45+1)/log10(2+18). Contrast: Angular Betweenness in the plugin uses total_depths even for weighted (angularbetweennessanalysis.py:123-127), see FSB-007.

### AC-010  [D]  angle_threshold x weigh_by_length

- **rPST**: `angular_choice` | **native**: `PSTAAngularChoice` | **QGIS/Python**: pstqgis/src/pst/analyses/angularchoiceanalysis.py + ui/wizards/angularchoicewiz.py
- native: accepted in both modes (same Run)
- Python/QGIS: PARTIAL: forwarded only in the weighted branch; unweighted call omits angle_threshold/angle_precision (engine defaults 0/1)
- rPST: accepted in both modes
- defaults native / Python / rPST: 0 / 0 (wizard), but ignored when unweighted / 0
- evidence: pstqgis/src/pst/analyses/angularchoiceanalysis.py:103-113 (forwarded) vs 154-161 (not forwarded); git blame: both a808c54 (initial upload, 2019-11-18); pstalgo/src/analyses/AngularChoice.cpp:46-58; R/core-analyses.R:245-246; docs/compatibility/qgis-differences.md (Deliberate departures)
- discrepancy: Plugin silently ignores the user's angle settings for unweighted Choice (Python-level inconsistency; the same wizard values ARE honoured by Angular Integration unweighted); rPST honours them.
- tests: generate-reference.py:176-193 (8 settings x 2 weightings vs direct native); test-angular-controls.R:9 | risk: usability (results differ from plugin for non-default settings unless angle_threshold=0, angle_precision=1 passed) | recommendation: preserve

Not class C: the restriction is not 'native rejects/accepts' but a plugin forwarding omission; rPST's behaviour is verified against direct native calls for both weightings, so it is a demonstrated-correct departure (D). No commit explains the omission: the line was in the initial upload a808c54 and never touched (git blame).

### AC-011  [D]  angle_precision / angle_threshold domain

- **rPST**: `angular_choice` | **native**: `PSTAAngularChoice` | **QGIS/Python**: pstqgis/src/pst/analyses/angularchoiceanalysis.py + ui/wizards/angularchoicewiz.py
- native: as AI-013/AI-014
- Python/QGIS: available (text fields)
- rPST: accepted within AI-013/AI-014 domain
- defaults native / Python / rPST: 0 / 1 / 0 / 1 / 0 / 1
- evidence: pstalgo/include/pstalgo/analyses/AngularChoice.h:44-45; pstalgo/src/analyses/AngularChoice.cpp:33-34; src/pst-graph.cpp:1064-1079; R/core-analyses.R:221-226
- discrepancy: none
- tests: test-angular-controls.R:76-112 | risk: none | recommendation: preserve

Verified by run: angle_precision=0 and NA_integer_ rejected; integer typed 5L accepted; angle_threshold string rejected.

### AC-012  [G]  total_depth_weight output / weight_outputs

- **rPST**: `angular_choice` | **native**: `PSTAAngularChoice` | **QGIS/Python**: pstqgis/src/pst/analyses/angularchoiceanalysis.py + ui/wizards/angularchoicewiz.py
- native: accepted (m_OutTotalDepthWeight; Choice has no total_weight output)
- Python/QGIS: allocated and used only when weigh_by_length
- rPST: total_depth_weight column only when weighted; no weight_outputs argument
- defaults native / Python / rPST: NULL / None unless weighted / absent unless weighted
- evidence: pstalgo/include/pstalgo/analyses/AngularChoice.h:53-56; pstalgo/src/analyses/AngularChoice.cpp:53-57; pstqgis/src/pst/analyses/angularchoiceanalysis.py:69; src/pst-graph.cpp:1486-1506; R/core-analyses.R:272-278
- discrepancy: none (AI has weight_outputs, AC does not; consistent with the plugin).
- tests: test-angular-controls.R:113 | risk: none | recommendation: preserve

Verified by run: angular_choice(g, weight_outputs=TRUE) => unused argument.

### AC-013  [G]  normalization values not applicable to choice ('hillier', 'freeman', invalid, duplicates, empty, NA)

- **rPST**: `angular_choice` | **native**: `PSTAAngularChoice` | **QGIS/Python**: pstqgis/src/pst/analyses/angularchoiceanalysis.py + ui/wizards/angularchoicewiz.py
- native: n/a
- Python/QGIS: absent
- rPST: rejected
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: R/angular-multi.R:8-14; R/core-analyses.R:253; src/pst-graph.cpp:1544; tests/testthat/test-core-network-analyses.R:208-212
- discrepancy: none
- tests: test-core-network-analyses.R:208-212; test-multi-radius.R:341 | risk: none | recommendation: preserve

Verified by run: 'hillier', c('turner','turner'), character(0), NA_character_ all error with 'normalization must be ...'.

### AC-014  [G]  output options (N, TD, MD)

- **rPST**: `angular_choice` | **native**: `PSTAAngularChoice` | **QGIS/Python**: pstqgis/src/pst/analyses/angularchoiceanalysis.py + ui/wizards/angularchoicewiz.py
- native: accepted (optional arrays)
- Python/QGIS: available (default ON, MD = TD/(N-1))
- rPST: N and TD always; MD not provided
- defaults native / Python / rPST: NULL / ON / always N, TD
- evidence: pstqgis/src/pst/ui/wizards/angularchoicewiz.py:88-90; pstqgis/src/pst/analyses/utils.py:242-245; R/core-analyses.R:272-278
- discrepancy: as AI-016
- tests: test-angular-controls.R:9 | risk: none | recommendation: preserve

As AI-016.

### AC-015  [D]  segment graph with >32 incidences

- **rPST**: `angular_choice` | **native**: `PSTAAngularChoice` | **QGIS/Python**: pstqgis/src/pst/analyses/angularchoiceanalysis.py + ui/wizards/angularchoicewiz.py
- native: accepted-but-undefined (ASSERT only)
- Python/QGIS: available (no check)
- rPST: rejected
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: pstalgo/src/analyses/AngularChoiceAlgo.cpp:98-99; src/pst-graph.cpp:1539-1540; tests/testthat/test-core-network-analyses.R:162-165
- discrepancy: as AI-017
- tests: test-core-network-analyses.R:162-165 | risk: correctness (prevents wrong N) | recommendation: preserve

As AI-017 (run-verified).

### AC-016  [G]  graph: zero-length segments, isolated, single segment

- **rPST**: `angular_choice` | **native**: `PSTAAngularChoice` | **QGIS/Python**: pstqgis/src/pst/analyses/angularchoiceanalysis.py + ui/wizards/angularchoicewiz.py
- native: accepted
- Python/QGIS: available
- rPST: accepted
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: tools/reference/angular/generate-reference.py:169-175
- discrepancy: none
- tests: angular direct fixture graphs (isolated, zero_length, large_star) | risk: none | recommendation: preserve

Verified by run: single segment returns choice 0, node_count 1; zero-length + chain returns finite values.

### AC-017  [E]  recursion depth in CollectScores / ClearProcessedFlags (document only)

- **rPST**: `angular_choice` | **native**: `PSTAAngularChoice` | **QGIS/Python**: pstqgis/src/pst/analyses/angularchoiceanalysis.py + ui/wizards/angularchoicewiz.py
- native: accepted; recursion unbounded
- Python/QGIS: available (same engine)
- rPST: accepted (no guard; documented in help and angular-controls.md)
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: pstalgo/src/analyses/AngularChoiceAlgo.cpp:73,201-220,325-372 (recursive call 345),374-399 (recursive call 396); docs/compatibility/angular-controls.md 'Known limitation'; R/core-analyses.R:190-200
- discrepancy: Inherited: very long chains of shortest-path out-steps can exhaust the worker-thread stack and kill the R process (maintainer-confirmed 8,000-segment unrestricted collinear chain on macOS ARM64).
- tests: none found (documented; deliberately not tested) | risk: safety (process termination, no R error) | recommendation: investigate (document only per scope; steps/walking/straight radii bound the depth, angular radius does not)

Re-read in the pinned file: CollectNSCScores (201) calls CollectScores for both directions of the origin (205-206); CollectScores (325) recurses at 345 for every out-segment bit not yet scored; ClearProcessedFlags recurses at 396. Depth equals the longest shortest-path out-step chain reachable inside the radius, independent of network size. Not executed. Interaction with this audit's radius matrix: a steps radius bounds depth by steps+1, walking/straight bound by segments inside the radius, angular does not bound straight runs, unrestricted default is unbounded.

### AC-018  [D]  multi-normalisation x multi-radius result schema

- **rPST**: `angular_choice` | **native**: `PSTAAngularChoice` | **QGIS/Python**: pstqgis/src/pst/analyses/angularchoiceanalysis.py + ui/wizards/angularchoicewiz.py
- native: n/a (R planning layer; PST once per radius, normalisers per run)
- Python/QGIS: absent
- rPST: accepted
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: R/angular-multi.R:17-44,94-106; src/pst-graph.cpp:1732-1745; docs/compatibility/multi-radius.md
- discrepancy: rPST extension
- tests: test-multi-radius.R:76-232; test-multi-radius-parquet.R | risk: none | recommendation: preserve

Each requested normaliser is applied to the same run's arrays (norms loop at pst-graph.cpp:1739); 'PST runs once per radius, never once per normalisation' is asserted by instrumentation (test-multi-radius.R:183).


## Segment graph construction (SG)

### SG-001  [G]  x: coordinates (n x 4 matrix x1,y1,x2,y2; int or double)

- **rPST**: `segment_graph` | **native**: `PSTACreateSegmentGraph` | **QGIS/Python**: pstqgis/src/pst/analyses/utils.py BuildSegmentGraph + model/model.py readLines
- native: accepted (double2 pairs; m_LineIndices optional)
- Python/QGIS: available (read from a QGIS line layer; None passed for indices)
- rPST: accepted (numeric matrix with >=1 row, exactly 4 columns; data.frame rejected)
- defaults native / Python / rPST: n/a / n/a / none (required)
- evidence: pstalgo/include/pstalgo/analyses/CreateGraph.h:107-122; pstalgo/src/analyses/CreateGraph.cpp:216-227; pstqgis/src/pst/analyses/utils.py:199-211; R/segment-graph.R:73-90; src/pst-graph.cpp:997-1030
- discrepancy: none; version field set to 1 by rPST (native does not check it for this export).
- tests: test-segment-graph.R:1-57 | risk: none | recommendation: preserve

Verified by run: 0-row, 3-column matrices and a data.frame are rejected; integer matrices accepted. Native PSTACreateSegmentGraph never validates m_Version (CreateGraph.cpp:216-227) and returns 0 only if CSegmentGraph::Create returns false, which it never does (SegmentGraph.cpp:134).

### SG-002  [G]  m_Lines indexed input (shared coordinate indices)

- **rPST**: `segment_graph` | **native**: `PSTACreateSegmentGraph` | **QGIS/Python**: pstalgo/python/pstalgo/creategraph.py:174-195
- native: accepted (SegmentGraph.cpp:58-65,113-114; test_sgrp_90plus uses it)
- Python/QGIS: available in the wrapper; the plugin always passes None
- rPST: absent (matrix only)
- defaults native / Python / rPST: NULL (sequential pairs) / None / n/a
- evidence: pstalgo/src/graph/SegmentGraph.cpp:39-135; pstalgo/python/pstalgo/creategraph.py:174-195; pstqgis/src/pst/analyses/utils.py:211; pstalgo/test/tests/testsegmentgrouping.py:60-70; src/pst-graph.cpp:966-973
- discrepancy: rPST cannot supply an index array. No functional loss: the engine merges identical coordinates either way (SegmentGraph.cpp:85,90) and the plugin never uses indices.
- tests: n/a | risk: none | recommendation: preserve

Not class F: index input only avoids duplicate coordinates in memory; connectivity is by exact double coordinate equality in both modes.

### SG-003  [G]  topology: connectivity rule

- **rPST**: `segment_graph` | **native**: `PSTACreateSegmentGraph` | **QGIS/Python**: pstqgis/src/pst/analyses/utils.py BuildSegmentGraph + model/model.py readLines
- native: accepted: exact double-equal endpoints connect; interior crossings and T-contacts do NOT
- Python/QGIS: available (no snapping in the angular wizards)
- rPST: accepted (no snapping, no tolerance)
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: pstalgo/src/graph/SegmentGraph.cpp:70-105; pstqgis/src/pst/ui/wizards/angularchoicewiz.py:12; R/segment-graph.R:1-8; tests/testthat/test-angular-integration.R:44
- discrepancy: none
- tests: test-angular-integration.R:44 (endpoint equality alone) | risk: usability (near-equal endpoints silently disconnect) | recommendation: preserve

Verified by run: endpoints 1 and 1.0000001 => node_count 1,1 (disconnected); exact => 2,2; reversed direction connects; T-interior contact and X crossing => 1 (not connected).

### SG-004  [G]  geometry: polylines with >2 vertices

- **rPST**: `segment_graph` | **native**: `PSTACreateSegmentGraph` | **QGIS/Python**: pstqgis/src/pst/model/model.py:283-309
- native: n/a (native only sees 2-point segments)
- Python/QGIS: rejected (raises 'polyline geometry, which is not supported')
- rPST: rejected
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: pstqgis/src/pst/model/model.py:304-305; R/sf.R:128; docs/spatial-io/sf-adapters.md:87
- discrepancy: none
- tests: tests/testthat/test-sf-graphs.R; test-sf-construction.R | risk: none | recommendation: preserve

Verified by run: a 3-vertex LINESTRING => 'requires exactly two finite XY vertices per LINESTRING'.

### SG-005  [F]  geometry: MULTILINESTRING with exactly one 2-vertex part

- **rPST**: `segment_graph` | **native**: `PSTACreateSegmentGraph` | **QGIS/Python**: pstqgis/src/pst/model/model.py:290-296
- native: n/a (geometry layer only)
- Python/QGIS: available (accepted: multipart with one part)
- rPST: rejected ('requires LINESTRING geometry; ... cannot be flattened')
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: pstqgis/src/pst/model/model.py:290-296; R/sf.R:128; docs/spatial-io/sf-adapters.md:34,87,133; src/pst-graph.cpp (not involved)
- discrepancy: rPST adapter rejects a lossless single-part multipart that the plugin accepts; native is unaffected. Workaround: sf::st_cast(x, 'LINESTRING').
- tests: test-sf-graphs.R (multipart rejection) | risk: usability (minor) | recommendation: investigate (optional relaxation: accept MULTILINESTRING whose single part has exactly two vertices; low value)

Verified by run on sf: st_sfc(st_multilinestring(list(rbind(c(0,0),c(1,0))))) => ERR; the same coordinates as LINESTRING => OK. This is a deliberate documented adapter policy (sf-adapters.md), but it blocks an input the plugin handles, so recorded as a minor F rather than G. Multipart with !=1 parts is rejected by the plugin too (model.py:292-293).

### SG-006  [D]  geometry: empty / null / non-line / 1-vertex features

- **rPST**: `segment_graph` | **native**: `PSTACreateSegmentGraph` | **QGIS/Python**: pstqgis/src/pst/model/model.py:288-306
- native: n/a
- Python/QGIS: silently skipped (row id not returned, no warning)
- rPST: rejected (names offending feature)
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: pstqgis/src/pst/model/model.py:288,297; R/sf.R:128-136; docs/spatial-io/sf-adapters.md:133
- discrepancy: plugin drops such features without error (and results are written back by row id); rPST requires clean input so segment order = feature order.
- tests: test-sf-graphs.R | risk: none | recommendation: preserve

Verified by run: an sfc containing an empty LINESTRING errors. Silent skipping in the plugin is tolerated because it tracks line_rows; rPST has no equivalent id mapping, so rejecting is the safe choice.

### SG-007  [D]  non-finite coordinates (NA/NaN/Inf) and float-extent overflow

- **rPST**: `segment_graph` | **native**: `PSTACreateSegmentGraph` | **QGIS/Python**: pstqgis/src/pst/analyses/utils.py BuildSegmentGraph + model/model.py readLines
- native: accepted-but-undefined (no validation; bounding box/centres go non-finite)
- Python/QGIS: available (no check)
- rPST: rejected (finite check and local-float/length/squared-extent representability)
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: pstalgo/src/graph/SegmentGraph.cpp:44-49,117-120; src/pst-graph.cpp:902-957,1013-1016; R/segment-graph.R:85-87
- discrepancy: rPST guard
- tests: test-segment-graph.R:30-57 | risk: safety (improved) | recommendation: preserve

Verified by run: NA coordinate => 'Coordinates must all be finite'. The extent guard prevents infinities in the float squared-distance tests used by the straight radius.

### SG-008  [D]  segment count bounds

- **rPST**: `segment_graph` | **native**: `PSTACreateSegmentGraph` | **QGIS/Python**: pstqgis/src/pst/analyses/utils.py BuildSegmentGraph + model/model.py readLines
- native: unsigned int counts; analyses use signed int in places
- Python/QGIS: available (no check)
- rPST: rejected beyond INT_MAX segments / UINT_MAX coordinates
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: src/pst-graph.cpp:910-915,1005-1009
- discrepancy: rPST guard
- tests: test-segment-graph.R | risk: none | recommendation: preserve

Static check only; no >2^31 input constructed.

### SG-009  [D]  CRS: geographic lon/lat input

- **rPST**: `segment_graph` | **native**: `PSTACreateSegmentGraph` | **QGIS/Python**: pstqgis/src/pst/analyses/utils.py BuildSegmentGraph + model/model.py readLines
- native: n/a
- Python/QGIS: available (no check; the wizard labels distances 'meters')
- rPST: rejected for sf/GeoParquet/FlatGeobuf with known geographic CRS; matrix and unknown CRS accepted
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: R/segment-graph.R:17-19,33-38; docs/spatial-io/sf-adapters.md
- discrepancy: rPST guard against degrees being read as metres
- tests: test-sf-graphs.R | risk: correctness (improved) | recommendation: preserve

Verified by run: st_sfc(l1, crs=4326) rejected with an st_transform hint; no-CRS accepted.

### SG-010  [E]  degenerate input: zero-length (coincident endpoints) and duplicate segments

- **rPST**: `segment_graph` | **native**: `PSTACreateSegmentGraph` | **QGIS/Python**: pstqgis/src/pst/analyses/utils.py BuildSegmentGraph + model/model.py readLines
- native: accepted (zero-length segment appears twice in its intersection's segment list; ASSERTs only)
- Python/QGIS: available
- rPST: accepted
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: pstalgo/src/graph/SegmentGraph.cpp:117-128; git show e8816d4 (upstream message: 'same segment appears in multiple entries in the list of segments of an intersection (which is odd in itself, and points to another potential bug in segment graph construction)'); tests/testthat/test-sf-raster.R:214
- discrepancy: Accepted at construction; consequences differ per consumer: fine for AI/AC/grouping, HANGS in segment_group_graph (SGR-011).
- tests: angular fixtures include zero_length; none for group graph | risk: safety (see SGR-011) | recommendation: restrict or guard where unsafe (see SGR-011)

The upstream maintainer already described this condition in commit e8816d4 (2021-05-06, 'Fix for crash bug in FastSegmentBetweenness') and called it a potential construction bug; only FastSegmentBetweenness was made tolerant. rPST accepts such segments in the constructor (documented as accepted in sf-raster tests), so the safety verdict depends on the consumer; recorded as E at the constructor level with the concrete failure in SGR-011.

### SG-011  [G]  minimum segments (empty input)

- **rPST**: `segment_graph` | **native**: `PSTACreateSegmentGraph` | **QGIS/Python**: pstqgis/src/pst/analyses/utils.py BuildSegmentGraph + model/model.py readLines
- native: accepted-but-undefined (bounding box of nothing)
- Python/QGIS: rejected ('No lines found in table')
- rPST: rejected
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: pstqgis/src/pst/analyses/utils.py:207-208; R/segment-graph.R:81-84; src/pst-graph.cpp:1003-1009
- discrepancy: none
- tests: test-segment-graph.R:30 | risk: none | recommendation: preserve

Verified by run: 0-row matrix rejected.

### SG-012  [D]  handle ownership / lifetime

- **rPST**: `segment_graph` | **native**: `PSTAFreeSegmentGraph` | **QGIS/Python**: pstalgo/python/pstalgo/creategraph.py:197-198
- native: raw delete of handle
- Python/QGIS: explicit FreeSegmentGraph in finally
- rPST: external pointer with tag, finaliser, exactly-once free, dead/deserialised detection
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: pstalgo/src/analyses/CreateGraph.cpp:229-233; pstqgis/src/pst/analyses/angularchoiceanalysis.py:176-180; src/pst-graph.cpp:853-895,2074-2095
- discrepancy: rPST ownership layer
- tests: test-segment-graph.R:58-110 | risk: none | recommendation: preserve

Covered by lifecycle counters tests.

### SG-013  [D]  file path input (GeoParquet / FlatGeobuf), spatial_output_file

- **rPST**: `segment_graph` | **native**: `PSTACreateSegmentGraph` | **QGIS/Python**: pstqgis/src/pst/analyses/utils.py BuildSegmentGraph + model/model.py readLines
- native: n/a
- Python/QGIS: absent
- rPST: accepted (rPST extension, same native builder)
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: R/segment-graph.R:22-54,74; src/pst-graph.cpp:899-995
- discrepancy: rPST extension
- tests: test-geoparquet.R; test-flatgeobuf.R | risk: none | recommendation: preserve

Not re-audited here beyond confirming it shares segment_graph_build (pst-graph.cpp:899).


## Segment grouping / group graph / group integration (SGR)

### SGR-001  [G]  angle_threshold (default and range)

- **rPST**: `segment_grouping` | **native**: `PSTASegmentGrouping` | **QGIS/Python**: pstqgis/src/pst/analyses/segmentgroupinganalysis.py + ui/wizards/segmentgroupingwiz.py
- native: accepted for any float; header comment says [0..90] but 100 and 180 are tested; compare is inclusive (deviation <= threshold)
- Python/QGIS: available (wizard default 1, 2 decimals, free text, no range check); wrapper default 1.0
- rPST: accepted: finite, >=0, float-narrowable; >90 and >180 accepted; negative rejected
- defaults native / Python / rPST: 0 (SPSTASegmentGroupingDesc ctor) / 1.0 (wrapper and wizard) / 1
- evidence: pstalgo/include/pstalgo/analyses/SegmentGrouping.h:40; pstalgo/src/analyses/SegmentGrouping.cpp:115,148; pstalgo/src/graph/SegmentGroupGraph.cpp:66,132; pstalgo/python/pstalgo/segmentgrouping.py:56; pstqgis/src/pst/ui/wizards/segmentgroupingwiz.py:33; pstalgo/test/tests/testsegmentgrouping.py:30-50; R/segment-groups.R:40-41; src/pst-graph.cpp:1950-1966
- discrepancy: Native descriptor default 0 differs from the Python wrapper/wizard/rPST default 1; header range [0..90] is stale vs tests/implementation. rPST matches the plugin.
- tests: test-segment-groups.R:16 (thresholds 89/90/100/180/181) | risk: usability | recommendation: preserve

Verified by run on the upstream 4-segment square: thresholds 0,1,89 => groups 1,2,3,4; 90,91,180,181,1000 => one group (matches testsegmentgrouping.py:30-34); NA, Inf, string and length-2 rejected. Contrast with Angular Integration/Choice angle_threshold, a different parameter (strict '<' turn zeroing, AI-013): the two share a name only.

### SGR-002  [G]  angle_threshold negative

- **rPST**: `segment_grouping` | **native**: `PSTASegmentGrouping` | **QGIS/Python**: pstqgis/src/pst/analyses/segmentgroupinganalysis.py + ui/wizards/segmentgroupingwiz.py
- native: accepted-but-degenerate (deviation d>=0 > negative => nothing grouped, unlike 0 which still groups straight continuations)
- Python/QGIS: available (text field; no check)
- rPST: rejected
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: pstalgo/src/graph/SegmentGroupGraph.cpp:66,132; pstalgo/include/pstalgo/analyses/SegmentGrouping.h:40; src/pst-graph.cpp:1950-1960
- discrepancy: rPST narrower than native, but outside the header's documented domain [0..90]
- tests: test-segment-groups.R:111 | risk: none | recommendation: preserve

Source-derived (not run natively): with threshold < 0, `d > threshold` is true for every deviation so no pair is merged; the result equals the 'no grouping' partition, obtainable from threshold small positive (e.g. 1e-30 does group exact collinear d=0, so not identical). Judged not F because negative is outside the documented range and has no meaningful use.

### SGR-003  [G]  split_at_junctions

- **rPST**: `segment_grouping` | **native**: `PSTASegmentGrouping` | **QGIS/Python**: pstqgis/src/pst/analyses/segmentgroupinganalysis.py + ui/wizards/segmentgroupingwiz.py
- native: accepted (bool; continuations only through degree-2 intersections)
- Python/QGIS: available (checkbox, default OFF)
- rPST: accepted (logical, NA rejected)
- defaults native / Python / rPST: false / False / FALSE
- evidence: pstalgo/src/analyses/SegmentGrouping.cpp:116; pstalgo/src/graph/SegmentGroupGraph.cpp:33-78; pstqgis/src/pst/ui/wizards/segmentgroupingwiz.py:34; R/segment-groups.R:41; src/pst-graph.cpp:1960-1962
- discrepancy: none
- tests: test-segment-groups.R:16 | risk: none | recommendation: preserve

Verified by run: square at 90 with split => one group; T-junction at 91 without split => groups 1,1,2 and with split => 1,2,3 (degree-3 junction is not continued).

### SGR-004  [D]  colour output (m_OutColorPerLine) always requested

- **rPST**: `segment_grouping` | **native**: `PSTASegmentGrouping` | **QGIS/Python**: pstqgis/src/pst/analyses/segmentgroupinganalysis.py + ui/wizards/segmentgroupingwiz.py
- native: accepted (optional; graph colouring runs only if requested)
- Python/QGIS: available: 'Generate minimal disjunct colors' default OFF; the Segment Group Integration wizard never requests colours
- rPST: always computed and returned (color column, n_colors)
- defaults native / Python / rPST: NULL / OFF / always ON (no switch)
- evidence: pstalgo/src/analyses/SegmentGrouping.cpp:150-157; pstqgis/src/pst/ui/wizards/segmentgroupingwiz.py:37,40; pstqgis/src/pst/analyses/segmentgroupintegrationanalysis.py:70-74; src/pst-graph.cpp:1974-1996
- discrepancy: rPST cannot skip the colouring pass
- tests: test-segment-groups.R:16; test-result-grouping.R | risk: performance (extra CreateSegmentGroupConnectionGraph + ColorGraph for large graphs) | recommendation: investigate (optional colors = FALSE argument; no correctness issue)

Colouring builds a group adjacency graph by BFS per group (SegmentGrouping.cpp:37-110) and colours it; cost is additional to the grouping. rPST's own validation requires color count >=1 (pst-graph.cpp:1987-1989). Not measured here.

### SGR-005  [D]  graph argument family and descriptor checks

- **rPST**: `segment_grouping` | **native**: `PSTASegmentGrouping` | **QGIS/Python**: pstqgis/src/pst/analyses/segmentgroupinganalysis.py + ui/wizards/segmentgroupingwiz.py
- native: accepted (ASSERT on null graph; checks only m_LineCount == segment count; ASSERT(m_OutGroupIdPerLine) but null handled with temp)
- Python/QGIS: segment network only (UI flag)
- rPST: accepted: live pst_segment_graph; axial/group graph rejected
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: pstalgo/src/analyses/SegmentGrouping.cpp:127-148; R/segment-groups.R:1-5,42; src/pst-graph.cpp:1968-1996
- discrepancy: rPST adds family checks; native has no version check for this export.
- tests: test-segment-groups.R:154 | risk: none | recommendation: preserve

Verified by run: grouping an axial graph and a group graph errors ('graph must be a live pst_segment_graph created by pst_segment_graph()'; the function name in this message is wrong, see SGR-018).

### SGR-006  [G]  segment grouping on graphs with >32 incidences, zero-length and duplicate segments

- **rPST**: `segment_grouping` | **native**: `PSTASegmentGrouping` | **QGIS/Python**: pstqgis/src/pst/analyses/segmentgroupinganalysis.py + ui/wizards/segmentgroupingwiz.py
- native: accepted (no 32-bit mask in this family)
- Python/QGIS: available
- rPST: accepted (the 32 guard is not applied)
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: pstalgo/src/graph/SegmentGroupGraph.cpp:31-170; docs/compatibility/segment-groups.md (40-incidence junction)
- discrepancy: none
- tests: test-segment-groups.R:16 (fixture with 40-incidence junction) | risk: none | recommendation: preserve

Verified by run: 33-spoke star groups without error; zero-length and duplicate segments with all combinations of thresholds {0,1,90,180} and split TRUE/FALSE complete (five tiny graphs, 8 s kill limit, no hang).

### SGR-007  [D]  group_id (+ group_count) input

- **rPST**: `segment_group_graph` | **native**: `PSTACreateSegmentGroupGraph` | **QGIS/Python**: pstqgis/src/pst/analyses/segmentgroupintegrationanalysis.py:64-78
- native: accepted when m_SegmentCount == graph segment count (else returns 0); group ids must be < m_GroupCount (unchecked)
- Python/QGIS: available only as the output of SegmentGrouping within the same analysis (ids dense 0..group_count-1)
- rPST: accepted: numeric vector of whole ids in 1..n_segments, one per segment; group_count = max(id); gaps = empty groups
- defaults native / Python / rPST: n/a / n/a / none (required)
- evidence: pstalgo/src/analyses/CreateGraph.cpp:250-266 (count check 255-259); pstalgo/src/graph/SegmentGroupGraph.cpp:179-258; pstqgis/src/pst/analyses/segmentgroupintegrationanalysis.py:69-78; R/segment-groups.R:95-101; src/pst-graph.cpp:2145-2190
- discrepancy: rPST extension: arbitrary user partitions, gaps allowed. Safety of arbitrary partitions was stress-checked: 300 random non-degenerate graphs (3-40 segments, duplicates included) x random ids x 3 radii completed without error.
- tests: test-segment-groups.R:111 (validation), :41 (empty groups) | risk: none for non-degenerate graphs (see SGR-011) | recommendation: preserve

Verified by run: 0, fractional, wrong length and group graph input are rejected; c(1,1,3,3,5) creates a 5-group graph and integration gives -1,0,0 for the two empty groups (native writes them since nodes exist). Bounded random check: scratchpad/u2/t8.R (300 trials, all OK).

### SGR-008  [G]  radius$walking

- **rPST**: `segment_group_integration` | **native**: `PSTASegmentGroupIntegration` | **QGIS/Python**: pstqgis/src/pst/analyses/segmentgroupintegrationanalysis.py + ui/wizards/segmentgroupintegrationwiz.py
- native: accepted (consumed: dist.m_Walking <= radius)
- Python/QGIS: available (MyRadiusPage: walking, steps only; one native run per ticked type via Radii.split)
- rPST: accepted (single value)
- defaults native / Python / rPST: unlimited / none ticked => validatePage forces >=1 / analysis_radius() => unlimited
- evidence: pstalgo/src/analyses/SegmentGroupIntegration.cpp:46,80-83; pstalgo/test/tests/testsegmentgroupintegration.py:34-37; pstqgis/src/pst/ui/wizards/segmentgroupintegrationwiz.py:97,104-109; pstqgis/src/pst/analyses/segmentgroupintegrationanalysis.py:44,91-105; src/pst-graph.cpp:2211-2216
- discrepancy: none for the field
- tests: test-segment-groups.R:16 (walking/steps zero and boundary limits) | risk: none | recommendation: preserve

Verified by run on a 5-group chain: walking=4 => node counts 3,4,5,4,3 (matches upstream Radii(walking=3)).

### SGR-009  [G]  radius$steps

- **rPST**: `segment_group_integration` | **native**: `PSTASegmentGroupIntegration` | **QGIS/Python**: pstqgis/src/pst/analyses/segmentgroupintegrationanalysis.py
- native: accepted (distance.m_Steps <= radius)
- Python/QGIS: available (MyRadiusPage)
- rPST: accepted
- defaults native / Python / rPST: unlimited / n/a / unlimited
- evidence: pstalgo/src/analyses/SegmentGroupIntegration.cpp:47,80-83; pstalgo/test/tests/testsegmentgroupintegration.py:38-40
- discrepancy: none
- tests: test-segment-groups.R:16 | risk: none | recommendation: preserve

Verified by run: steps=2 equals walking=4 on the chain (3,4,5,4,3).

### SGR-010  [D]  radius$straight / $angular / $axmeter x segment_group_integration

- **rPST**: `segment_group_integration` | **native**: `PSTASegmentGroupIntegration` | **QGIS/Python**: pstqgis/src/pst/ui/wizards/segmentgroupintegrationwiz.py:96-109
- native: accepted but IGNORED (only Walking() and Steps() are copied into the group radius; no validation)
- Python/QGIS: disabled (UI-only: MyRadiusPage.RADIUS_TYPES = [WALKING, STEPS])
- rPST: rejected ('Segment Group Integration supports only walking and steps radius limits.')
- defaults native / Python / rPST: unlimited / n/a / n/a
- evidence: pstalgo/src/analyses/SegmentGroupIntegration.cpp:46-47 (only Walking/Steps read); pstalgo/src/analyses/SegmentGroupIntegration.cpp:237-252 (no radius validation); pstqgis/src/pst/ui/wizards/segmentgroupintegrationwiz.py:97 (restriction present since initial upload a808c54: RadiusPage(radius_types=[WALKING,STEPS]); refactored into MyRadiusPage by 1c801b4 2020-02-07); src/pst-graph.cpp:2213-2216; docs/pst-coverage.md 3.8
- discrepancy: Python limits the UI to walking/steps; native silently ignores the others; rPST rejects them.
- tests: test-segment-groups.R:170-174 | risk: none | recommendation: preserve (rejection prevents a silent no-op)

This is the rPST rejection at src/pst-graph.cpp:2213-2216 named in the task. Layered facts: (1) UI-only: disabled control, no explanation; (2) NOT a native rejection: PSTASegmentGroupIntegration returns true and ignores the fields (so not class B); (3) rPST rejection is NOT overly restrictive (not F) because accepting a straight/angular/axmeter limit would not constrain traversal at all: the result would equal the unrestricted run, silently. The code comment records exactly this ('Do not silently accept other limits as though they restricted this engine'). Verified by run: straight=4, angular=4, axmeter=4 each error. Restriction history: blame src/pst-graph.cpp:2213-2216 -> ^4768003 (grafted root, 2026-10-08); git log -S shows d623298 (2026-10-09) as the first appearance; no explanatory commit message. UI restriction history upstream: the walking/steps-only page is in the initial upload a808c54 (2019-11-18, 'Add files via upload'); 1c801b4 (2020-02-07, 'Make sure at least one distance type is selected') only moved it into MyRadiusPage; native SegmentGroupIntegration.cpp:46-47 dates from 866cf3a (2019-11-20). No explanation found for the restriction.

### SGR-011  [E]  segment graph containing a zero-length segment (coincident endpoints) sharing a coordinate with another segment

- **rPST**: `segment_group_graph` | **native**: `PSTACreateSegmentGroupGraph / CSegmentGroupGraph::Create` | **QGIS/Python**: pstqgis/src/pst/analyses/segmentgroupintegrationanalysis.py:78
- native: accepted-but-HANGS (infinite loop; ASSERTs at lines 208 and 252 are the only guard and are compiled out in release)
- Python/QGIS: available (same hang in the plugin; QGIS reads such features and passes them)
- rPST: accepted (no guard in segment_graph or segment_group_graph)
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: pstalgo/src/graph/SegmentGroupGraph.cpp:203-216 (two entries for the same segment map to the same seg_end_idx; ASSERT line 208), 233-254 (INFINITE_LOOP; next segment chosen by `Segments[0]==segment_index ? Segments[1] : Segments[0]` stays on the same segment when both entries are that segment; ASSERT line 252); pstalgo/src/graph/SegmentGraph.cpp:122-128; upstream commit e8816d4 message; src/pst-graph.cpp:2145-2190; scratchpad/u2/t10.R
- discrepancy: Reproducible process hang (CPU-bound, memory flat, not interruptible from R) in an exposed rPST function on a plausible input; also via the normal route segment_grouping() -> segment_group_graph().
- tests: none found (no group-graph test with a zero-length segment) | risk: safety (hang requiring process kill) | recommendation: restrict (reject, before the native call, segment graphs in segment_group_graph that contain a segment whose two endpoints coincide) or document; do not modify PST. Class B arguable (native ASSERTs state the unsupported assumption) but no header documents it, so recorded E.

Reproduction (each killed at 6-10 s): g <- segment_graph(rbind(c(0,0,0,0), c(0,0,1,0))); segment_group_graph(g, 1:2) hangs; ids from segment_grouping(g)$group_id (1,2) hang as well; same-group ids (1,1) hang too. Not hanging: a lone zero-length segment, zero-length segment at the far end (rbind(c(0,0,1,0), c(1,0,1,0))), mid-chain, duplicates. So the condition depends on the order of the intersection's segment entries (std::sort order at SegmentGraph.cpp:70-75), not only on geometry; I did not characterise it fully. Mechanism, from reading: the zero-length segment is listed twice in its intersection; Create() assigns both entries to the same segment end, leaves the other end node-less, and the walk in the 'Connect nodes' phase then keeps selecting the same segment forever. Upstream knew of the data-structure oddity (e8816d4) but fixed only FastSegmentBetweenness. Segment grouping, Angular Integration and Angular Choice are NOT affected (verified by run on the same graphs). A bounded random stress (150 graphs with zero-length segments) found the hang at trial 8; 300 graphs without zero-length segments produced no failure.

### SGR-012  [D]  radius: walking + steps combined; multi-value vectors

- **rPST**: `segment_group_integration` | **native**: `PSTASegmentGroupIntegration` | **QGIS/Python**: pstqgis/src/pst/analyses/segmentgroupintegrationanalysis.py:44
- native: accepted combined (upstream tests Radii(walking=3,steps=0), (walking=0,steps=2))
- Python/QGIS: split: one native run per ticked type, columns per type
- rPST: combined accepted; vector of several values rejected
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: pstalgo/test/tests/testsegmentgroupintegration.py:44-45; pstqgis/src/pst/analyses/segmentgroupintegrationanalysis.py:44,90-129; R/radius.R:48-52; docs/compatibility/qgis-differences.md (Radius combinations)
- discrepancy: documented departure (rPST allows the natively-tested combined limit in one run; plugin splits)
- tests: test-segment-groups.R:16 | risk: none | recommendation: preserve

Verified by run: analysis_radius(walking=3, steps=2) accepted; analysis_radius(walking=c(3,6)) is constructible but segment_group_integration() then errors 'radius walking must be NULL or one finite non-negative native float value' (a multi-value vector reaches the scalar C check; the message does not say that multi-radius is supported only by the two angular analyses, unlike the message from .pst_radius_shape that other R-level analyses give). Minor wording point.

### SGR-013  [D]  outputs: integration, node_count, total_depth (+ MD); missing-output policy

- **rPST**: `segment_group_integration` | **native**: `PSTASegmentGroupIntegration` | **QGIS/Python**: pstqgis/src/pst/analyses/segmentgroupintegrationanalysis.py:81-127
- native: accepted (optional arrays; whole-graph early return leaves them unwritten; isolated/empty groups write -1,0,0)
- Python/QGIS: available (N, TD, MD checkboxes default ON; arrays uninitialised on the no-node path)
- rPST: always all three; unwritten => typed NA via UINT_MAX/-Inf pre-fill and paired masks
- defaults native / Python / rPST: NULL / ON / all
- evidence: pstalgo/src/analyses/SegmentGroupIntegration.cpp:134,136-141,150-151,249-251; src/pst-graph.cpp:2099-2143; docs/compatibility/segment-groups.md (Missing-output policy)
- discrepancy: rPST defines a deterministic NA policy; native returns true even when the inner run reports failure (lines 249-251)
- tests: test-segment-groups.R:41,72,95 | risk: none | recommendation: preserve

Verified by run: rep(1,5) group ids (no native nodes) => single group NA/NA/NA; mixed empty groups => -1,0,0 kept. Note line 134 tests the total node_count rather than the group's num_nodes, so empty groups in a graph with nodes still call CalculateIntegration with zero nodes (observed -1,0,0).

### SGR-014  [G]  mapping of group results to segments

- **rPST**: `segment_group_integration` | **native**: `PSTASegmentGroupIntegration` | **QGIS/Python**: pstqgis/src/pst/analyses/segmentgroupintegrationanalysis.py:105-113
- native: n/a (per group)
- Python/QGIS: available (MapGroupValues copies group values to each segment; columns per segment)
- rPST: per group (group_id order); user maps via group_id
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: pstqgis/src/pst/analyses/segmentgroupintegrationanalysis.py:107-113,144-147; R/segment-groups.R:175-177
- discrepancy: different output grain (documented)
- tests: test-segment-groups.R:16 | risk: usability | recommendation: preserve

rPST result has one row per group; join with segment_grouping()$group_id to reproduce the plugin's per-segment columns.

### SGR-015  [G]  angle_threshold (grouping) vs angle_threshold (angular analyses) - combination check

- **rPST**: `segment_grouping x angular analyses` | **native**: `n/a` | **QGIS/Python**: n/a
- native: distinct parameters in distinct descriptors
- Python/QGIS: separate wizards
- rPST: separate functions
- defaults native / Python / rPST: 0 / 0 / 1 / 0 / 1 / 0
- evidence: pstalgo/src/graph/SegmentGroupGraph.cpp:66; pstalgo/src/analyses/AngularChoiceAlgo.cpp:300
- discrepancy: inclusive vs strict comparison and different defaults (1 vs 0); not a defect
- tests: n/a | risk: usability | recommendation: preserve (documented in help)

Recorded because the task asks for angle_threshold x segment_grouping: grouping pairs segments whose deviation 180-angleDiff <= threshold (inclusive, line 66/132); angular analyses zero a turn if turn < threshold (strict, line 300).

### SGR-016  [D]  handle types, lifetime, worker cap

- **rPST**: `segment_group_graph / segment_group_integration` | **native**: `PSTAFreeSegmentGroupGraph` | **QGIS/Python**: segmentgroupintegrationanalysis.py:131-138
- native: raw void* casts
- Python/QGIS: free in finally
- rPST: tagged owner, dead/deserialised pointer rejection, RPST_NUM_THREADS cap including no-node graphs
- defaults native / Python / rPST: hardware_concurrency (SegmentGroupIntegration.cpp:173) / same / same unless capped
- evidence: src/pst-graph.cpp:2074-2108,2209-2240; src/portability/limit-workers.R:4-16; docs/compatibility/segment-groups.md
- discrepancy: rPST ownership/threads layer
- tests: test-segment-groups.R:154,191,227 | risk: none | recommendation: preserve

Static review; the constructor patch (scoped unpublished graph) is recorded in inst/upstream/PATCHES.md.

### SGR-017  [G]  plugin-only: 'Apply generated colors to map' (QGIS thematic renderer)

- **rPST**: `segment_grouping` | **native**: `PSTASegmentGrouping` | **QGIS/Python**: pstqgis/src/pst/analyses/segmentgroupinganalysis.py + ui/wizards/segmentgroupingwiz.py
- native: n/a
- Python/QGIS: available (UI)
- rPST: absent (not a PST engine feature)
- defaults native / Python / rPST: n/a / OFF / n/a
- evidence: pstqgis/src/pst/analyses/segmentgroupinganalysis.py:74-81
- discrepancy: QGIS styling only
- tests: n/a | risk: none | recommendation: preserve

Palette is a plugin constant; rPST returns colour labels.

### SGR-018  [A]  error text for wrong graph argument

- **rPST**: `segment_grouping / segment_group_graph / segment_group_integration` | **native**: `n/a` | **QGIS/Python**: n/a
- native: n/a
- Python/QGIS: n/a
- rPST: rejected with misleading function names
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: R/segment-groups.R:1-5; tests/testthat/test-segment-groups.R:165-168
- discrepancy: Message says 'created by pst_segment_graph()' / 'pst_segment_group_graph()' (class names) but the constructors are segment_graph() and segment_group_graph(); angular_* messages are correct.
- tests: test-segment-groups.R:165-168 asserts only the class-name substring | risk: usability (message text only) | recommendation: correct (use the constructor function name in .pst_group_pointer; keep the substring the tests match or update them)

Confirmed by run: segment_grouping(axial_graph(...)) => 'graph must be a live pst_segment_graph created by pst_segment_graph().'; segment_group_integration(segment graph) => '... pst_segment_group_graph created by pst_segment_group_graph().'. Cosmetic; no mapping or numeric consequence.


## Fast Segment Betweenness / 'Angular Betweenness' - not exposed (FSB)

### FSB-001  [G]  exposure decision

- **rPST**: `(not exposed)` | **native**: `PSTAFastSegmentBetweenness` | **QGIS/Python**: pstqgis/src/pst/analyses/angularbetweennessanalysis.py + ui/wizards/angularbetweennesswiz.py (menu 'Angular Betweenness', pstqgis/src/pst/main.py:130)
- native: exported (experimental/ header) and compiled into rPST (src/Makevars:48)
- Python/QGIS: available (ordinary, ungated menu action)
- rPST: absent
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: pstalgo/include/pstalgo/experimental/FastSegmentBetweenness.h:28-54; pstqgis/src/pst/main.py:130; src/Makevars:48; docs/design-decisions.md:64; docs/pst-coverage.md 3.1; NEWS.md:76; README.md:153
- discrepancy: QGIS offers the analysis; rPST deliberately does not expose it. The object file is built but unreachable from R (no .Call, no R function).
- tests: none (no R surface) | risk: none | recommendation: preserve decision (re-evaluate only if QGIS parity is required; Angular Choice is the supported angular centrality)

Decision recorded as documented (not re-decided here). Not classed F: the native contract is internally contradictory (FSB-002..FSB-006) so there is no single supported behaviour to expose.

### FSB-002  [G]  m_DistanceType

- **rPST**: `(not exposed)` | **native**: `PSTAFastSegmentBetweenness` | **QGIS/Python**: pstqgis/src/pst/analyses/angularbetweennessanalysis.py + ui/wizards/angularbetweennesswiz.py (menu 'Angular Betweenness', pstqgis/src/pst/main.py:130)
- native: header: 'only ANGULAR supported'; implementation never reads the field (no reference in the .cpp; export at 620-642)
- Python/QGIS: wrapper takes distance_type; plugin always passes ANGULAR (analysis:103); upstream test passes STEPS
- rPST: absent
- defaults native / Python / rPST: Angular (header initialiser) / ANGULAR / n/a
- evidence: pstalgo/include/pstalgo/experimental/FastSegmentBetweenness.h:37; pstalgo/src/experimental/FastSegmentBetweenness.cpp:620-642; pstqgis/src/pst/analyses/angularbetweennessanalysis.py:101-109; pstalgo/test/tests/testfastsegmentbetweenness.py:39 (DistanceType.STEPS)
- discrepancy: upstream header/impl/test disagree
- tests: none | risk: n/a | recommendation: n/a

Cross-checked by grep: 'DistanceType' does not occur in FastSegmentBetweenness.cpp. The impl's comment 'Assuming distance mode is ANGULAR' (line 529).

### FSB-003  [G]  radius types

- **rPST**: `(not exposed)` | **native**: `PSTAFastSegmentBetweenness` | **QGIS/Python**: pstqgis/src/pst/analyses/angularbetweennessanalysis.py + ui/wizards/angularbetweennesswiz.py (menu 'Angular Betweenness', pstqgis/src/pst/main.py:130)
- native: header: 'Only WALKING supported'; traversal tests only m_Limits.Walking() (line 433); steps/angular/straight/axmeter ignored
- Python/QGIS: UI: RadiusPage(radius_types=[WALKING]); radii forwarded unchanged
- rPST: absent
- defaults native / Python / rPST: unlimited / unticked / n/a
- evidence: pstalgo/include/pstalgo/experimental/FastSegmentBetweenness.h:41; pstalgo/src/experimental/FastSegmentBetweenness.cpp:433; pstqgis/src/pst/ui/wizards/angularbetweennesswiz.py:34; pstalgo/test/tests/testfastsegmentbetweenness.py:41,59 (steps=4 and angular=45 passed)
- discrepancy: UI restriction (walking only) matches the implementation; upstream tests pass radii that are silently ignored
- tests: none | risk: n/a | recommendation: n/a

The docs/pst-coverage.md row 3.1 also reports measured effects (steps=1 and angular=10 change nothing; walking=25 changes choice by up to 209): I did not re-run these (native engine not rebuilt for this audit).

### FSB-004  [G]  m_WeighByLength

- **rPST**: `(not exposed)` | **native**: `PSTAFastSegmentBetweenness` | **QGIS/Python**: pstqgis/src/pst/analyses/angularbetweennessanalysis.py + ui/wizards/angularbetweennesswiz.py (menu 'Angular Betweenness', pstqgis/src/pst/main.py:130)
- native: header: 'NOT YET SUPPORTED'; implementation uses it as node weight (line 105) and the upstream test expects length^2 scores
- Python/QGIS: available (weight checkboxes, both runs)
- rPST: absent
- defaults native / Python / rPST: false / none ON / n/a
- evidence: pstalgo/include/pstalgo/experimental/FastSegmentBetweenness.h:38; pstalgo/src/experimental/FastSegmentBetweenness.cpp:82,105; pstalgo/test/tests/testfastsegmentbetweenness.py:37-52; git blame h:38 -> 1c166e8 (2021-03-02)
- discrepancy: stale header comment: added in 1c166e8, the same commit that implemented weighting
- tests: none | risk: n/a | recommendation: n/a

History: 1c166e8 'New analysis Angular Betweenness ...' (martin-fitger, 2021-03-02) both wrote the 'NOT YET SUPPORTED' comments (h:38,50,51) and the code that writes node counts/depths and weights, so the comments were already wrong when written.

### FSB-005  [G]  m_OutNodeCount / m_OutTotalDepth

- **rPST**: `(not exposed)` | **native**: `PSTAFastSegmentBetweenness` | **QGIS/Python**: pstqgis/src/pst/analyses/angularbetweennessanalysis.py + ui/wizards/angularbetweennesswiz.py (menu 'Angular Betweenness', pstqgis/src/pst/main.py:130)
- native: header: 'NOT YET SUPPORTED'; implementation memsets and writes both (573-576, 182-186, 528-529); total depth is angular syntax units regardless of mode
- Python/QGIS: available (OutputPage, default OFF; MD; NACH uses total_depths even when length-weighted)
- rPST: absent
- defaults native / Python / rPST: NULL / OFF / n/a
- evidence: pstalgo/include/pstalgo/experimental/FastSegmentBetweenness.h:50-51; pstalgo/src/experimental/FastSegmentBetweenness.cpp:182-186,528-529,573-576; pstqgis/src/pst/analyses/angularbetweennessanalysis.py:123-128; pstqgis/src/pst/ui/wizards/angularbetweennesswiz.py:120-122
- discrepancy: header contradicts implementation
- tests: none | risk: n/a | recommendation: n/a

Python comment (analysis:123-125) states total_depth_weight is not computed, so Syntax (NACH) normalisation of weighted FSB uses unweighted total depths, unlike Angular Choice (AC-009).

### FSB-006  [G]  m_OutBetweenness NULL; threading; angle handling

- **rPST**: `(not exposed)` | **native**: `PSTAFastSegmentBetweenness` | **QGIS/Python**: pstqgis/src/pst/analyses/angularbetweennessanalysis.py + ui/wizards/angularbetweennesswiz.py (menu 'Angular Betweenness', pstqgis/src/pst/main.py:130)
- native: header says outputs may be NULL, but out_scores is memset/accumulated without a null check (601-609); hardware_concurrency workers outside any rPST cap (563); INTEGER_ANGULAR_DISTANCE rounds angles to integers (43,68) with no threshold/precision parameter
- Python/QGIS: plugin always supplies scores
- rPST: absent
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: pstalgo/src/experimental/FastSegmentBetweenness.cpp:43,68,563,601-609; pstalgo/include/pstalgo/experimental/FastSegmentBetweenness.h:47-48; docs/compatibility/core-network-analyses.md:117-125
- discrepancy: further upstream inconsistencies and safety concerns
- tests: none | risk: n/a | recommendation: n/a

Float accumulation order across workers (per-worker double scores summed in worker order into float) makes results depend on worker count. Not verified numerically here.

### FSB-007  [G]  normalisation buffers (Turner/standard/syntax) in the plugin

- **rPST**: `(not exposed)` | **native**: `PSTAFastSegmentBetweenness` | **QGIS/Python**: pstqgis/src/pst/analyses/angularbetweennessanalysis.py + ui/wizards/angularbetweennesswiz.py (menu 'Angular Betweenness', pstqgis/src/pst/main.py:130)
- native: uses Angular Choice exports
- Python/QGIS: available (none, Turner, standard, syntax; weight none/length)
- rPST: absent
- defaults native / Python / rPST: n/a / No Normalization / no weight / n/a
- evidence: pstqgis/src/pst/analyses/angularbetweennessanalysis.py:112-128; pstqgis/src/pst/ui/wizards/angularbetweennesswiz.py:49-58
- discrepancy: would need its own mapping decision if ever exposed
- tests: none | risk: n/a | recommendation: n/a

Turner uses total_counts (N), syntax uses total_depths for both weight modes.

### FSB-008  [G]  upstream maturity / history

- **rPST**: `(not exposed)` | **native**: `PSTAFastSegmentBetweenness` | **QGIS/Python**: pstqgis/src/pst/analyses/angularbetweennessanalysis.py + ui/wizards/angularbetweennesswiz.py (menu 'Angular Betweenness', pstqgis/src/pst/main.py:130)
- native: experimental; tests: 3 cases
- Python/QGIS: shipped in menu
- rPST: absent
- defaults native / Python / rPST: n/a / n/a / n/a
- evidence: git log (up/pst): 1c166e8 2021-03-02 'New analysis Angular Betweenness ...'; e8816d4 2021-05-06 'Fix for crash bug in FastSegmentBetweenness' (segment listed twice in an intersection); 4e22212 2021-05-08 'Mac OS compatibility fixes'; 51c276e 2023-02-07 'only call progress callback on calling thread'; a00dd23 2025-10-09 'NACH with No weight crashes'
- discrepancy: none for rPST
- tests: none | risk: n/a | recommendation: n/a

Later fixes show continued maintenance (a00dd23 on the Python side, 2025-10-09, is an ancestor of the pinned commit). No commit removes or updates the header limits.


## Restriction history (git evidence)

* rPST `src/pst-graph.cpp:195-196` (angular axmeter) and `:2213-2216` (group integration): `git blame` ends at the grafted root `4768003` (2026-10-08); `git log -S` first shows `d623298` (2026-10-09, "Correct current architecture, native contracts and roadmap documentation"). The rPST history before that is not available, and no commit message explains either rejection. Rationale exists only in `docs/pst-coverage.md` rows 3.4 and 3.8 and the code comment at `:2213-2214`.
* Upstream angular wizards offering axmeter: default `RadiusPage` radius list (`radiuspage.py:341`), part of the initial upload; no commit explains it, and the engine radius setup (`AngularChoiceAlgo.cpp:449-452`, `866cf3a` 2019-11-20) never read axmeter.
* Upstream Segment Group Integration walking/steps-only page: initial upload `a808c54`; `1c801b4` (2020-02-07, "Make sure at least one distance type is selected") moved it into `MyRadiusPage`. No explanation found. Native `SegmentGroupIntegration.cpp:46-47` from `866cf3a`.
* Unweighted Choice not forwarding angle settings: `a808c54` initial upload; never changed.
* Unused `radii_list = ... .split()` in Choice: present in `a808c54`, deleted by `1c166e8` (2021-03-02) without comment.
* FSB header limits and "NOT YET SUPPORTED" comments: `1c166e8` (2021-03-02), the same commit that added the implementation of weighting, counts and depths. Related: `e8816d4` (2021-05-06) crash fix for a segment appearing twice in an intersection list (the root cause of SGR-011).

## Executed versus only read

Executed (installed rPST from `scratchpad/p/lib`, fresh process per script, `ulimit -v 3500000`, `timeout`, tiny synthetic graphs; scripts `scratchpad/u2/t1.R` ... `t11.R`): accept/reject matrices for all radius types on AI, AC and SGI; defaults via `formals()`; angle threshold/precision domains; normalisation name validation; multi-radius shape rules and column names; 33-spoke star guard; segment-graph input validation (matrix, sf); segment_grouping threshold sweep on the upstream square and a T junction; group graph validation, gaps, empty groups, no-node graph; the SGR-011 hang (killed by `timeout -s KILL`, up to 10 s each; one 300-trial and one 150-trial random check on graphs of at most 40 segments). No native engine was built or run in this role; no stress test of the recursion depth was run.

Only read (source): everything upstream (headers, implementations, wrapper, tests, plugin), rPST R and C++ code, docs, git history. FSB behaviour claims taken from source; the numerical claims in `docs/pst-coverage.md` row 3.1 were not re-verified.

## Uncertainties

* SGR-011: the set of graphs that hang depends on the order of segment entries at the shared coordinate (std::sort ordering); I characterised several cases, not the full condition. The exact class (E vs B) is a judgement: native ASSERTs state the unsupported assumption but no header does.
* SGR-002 (negative grouping threshold) behaviour is derived from source, not run natively.
* The circular-queue capacity argument for large `angle_precision` (AI-014) is a hand analysis plus rPST's existing direct fixtures (precision 361, UINT_MAX), not an exhaustive proof.
* AC/AI rows with class D "demonstrated correct" rely on rPST's own direct-native fixtures (generated from the pinned ctypes wrapper); I did not regenerate them.
* Whether QGIS actually silently skips non-line features matters little here but was read, not run (no QGIS available; no Q-level evidence, consistent with rPST's own statement).
