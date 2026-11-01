# U1 audit: axial-graph network analyses (Network Integration, Network Reach, Network Betweenness, axial_graph)

Pinned upstream: PST v3.3.2, commit 63df80a2cf3dd289be95ea3d91667c3490719b75 (read-only clone `scratchpad/up/pst`). rPST: branch audit/pst-interface-parity. CSV: `scratchpad/audit/U1-axial.csv` (84 rows: AX 15, NB 31, NI 19, NR 19). Classification counts: C 5, D 40, E 4, F 6, G 29.

Evidence labels: S static source; N direct native execution (via rPST fixtures built from the unchanged ctypes wrappers); E my own small R executions of installed rPST (tiny synthetic graphs, bounded). No QGIS run (no Q level). No Barnsbury or walking-performance run was executed here (see W report).

## 1. Headline findings

1. **Network Integration radius restriction is an application change, not an engine limit (NI-004..NI-008).** The wizard offers only a steps radius (`ui/wizards/networkintegrationwiz.py:34`) and the analysis hard-codes `Radii(steps=...)` with the `RadiiFromSettings(...).split()` line left as a comment (`analyses/networkintegrationanalysis.py:45-48`). Introduced by `5f3f70f` (2024-10-17, martin-fitger) *"pstqgis: networkintegration: Only allow axial network and only support step radius."*, first contained in tag **v3.3.1** (also in v3.3.2); a follow-up `dac509f` (2024-11-01) only changed the label to "Axial (topological) steps". No issue reference, changelog entry or comment explains why: *no explanation found*. Native `PSTANetworkIntegration` passes all five radii through `LimitsFromSPSTARadii` (`NetworkIntegration.cpp:154`) and the pinned upstream test covers straight, walking, steps and angular (`pstalgo/test/tests/testnetworkintegration.py:48-57`). Classification of the restriction: C (Python/UI-only). rPST exposes all radii: D for straight/angular/axmeter, **E for walking** (accepted; performance evidence incomplete, see W report).
2. **Network Betweenness wizard drops angular distance and Turner/NACH normalisers, again by an application commit (NB-004, NB-022, NB-023).** `1c166e8` (2021-03-02) *"New analysis \"Angular Betweenness\" and distinction between road network types in \"Create Segment Map\""* (first in v3.2.2) removed `dist_angular`, `norm_normalization` and `norm_syntax` from the wizard and from `networkbetweennessanalysis.py`. The original code (a808c54, tags v3.1.3-v3.2.1) called `pstalgo.BetweennessNormalize(scores, total_counts, ...)` and `pstalgo.BetweennessSyntaxNormalize(scores, total_depths, ...)`; rPST uses exactly those buffers (scores+node counts for Freeman, scores+total depths for syntax) over the written rows. Attraction Betweenness still offers angular and still accepts the axial engine path. No explanation for the removal beyond the coincidence with the new analysis.
3. **Junction scores are 2 x the mean, not the mean (NI-012).** `NetworkIntegration.cpp:185` adds `line_score / crossing.nLines`, but `nLines` is the number of pair records (`AxialGraph.cpp:359-376` region; `updateLinesPerCrossingCount` is defined at :391 and never called). Executed: three concurrent lines (3.4902, 1.7451, 1.1634) give 4.26583 = 2 x mean; a two-line join gives the sum. The wizard label says "average"; in the plugin the whole feature crashes (`column_base_name` undefined, `networkintegrationanalysis.py:128`). rPST docs say "not a conventional distinct-line mean" but do not state the 2 x mean relation (D, documentation improvement).
4. **A zero `polygon_point_interval` hangs the native sampler** (`RegionPoints.cpp:59`, `t += interval`), neither guarded by native code nor the ctypes wrapper; rPST rejects it (AX-006, D). `PSTACreateGraph` also ignores `m_Version` (AX-009).
5. **Three different meanings of "straight radius" exist inside the engine** (NR-009): mid-point distance for straight-only Reach (`<=` for line origins, `<` for point origins, area = pi r^2), crossing-point distance in the BFS (Network Integration, Reach with any additional limit), and target mid-point distance in Betweenness. Adding a second limit to a straight Reach silently changes the rule (executed: 1 vs 2 lines reached). Preserved engine behaviour (G), but worth a documented warning.
6. **Python splits radii by type (one run per ticked type; none ticked = nothing runs) whereas rPST applies combined radii in one run (NR-007/008, NB-013/014, NI-008).** Documented in `qgis-differences.md:28`; combined radii are covered by the 60-case direct-native fixture (all five radii together, all four betweenness distances). Multi-valued radii for NI/Reach/Betweenness are rejected by rPST (deferred convenience, F, low).
7. **Unlink semantics (AX-003)**: nearest crossing at any distance (no tolerance), and eligibility depends on the lower-index line crossing in its interior (a T-junction can be unlinked or not depending on row order). Executed. Documented in roxygen.
8. **Skipped weighted origins (NB-019)**: native leaves node count / total depth unwritten when the origin weight is not > 0; the plugin reuses buffers (stale values), rPST reports NA. Intentional and tested.

No row was classified A (confirmed rPST implementation error) or B (unsupported native combination exposed). Gaps are all E/F-level or documentation items.

## 2. Radius type x analysis matrix (evidence: native / wizard / Python / rPST)

| analysis | straight | walking | steps | angular | axmeter |
|---|---|---|---|---|---|
| Network Integration | native yes (BFS crossing rule); wizard no; Python no; rPST yes (NI-005) | native yes; wizard no; Python no; rPST yes, perf caveat (NI-004) | native yes; wizard yes (only type); Python yes; rPST yes (NI-002) | native yes; wizard no; rPST yes (NI-006) | native yes; wizard no; rPST yes (NI-007) |
| Network Reach (lines/points) | native yes (two rules); wizard yes; Python yes (one type per run); rPST yes (NR-002) | yes/yes/yes/yes, perf caveat (NR-003) | yes/yes/yes/yes (NR-004) | yes/yes/yes/yes (NR-005) | yes/yes/yes/yes (NR-006) |
| Network Betweenness (walking, steps, angular, axmeter distances) | yes (NB-008) | yes (NB-009) | yes (NB-010) | yes (NB-011) | yes (NB-012) |
| Attraction Betweenness (via network_betweenness(attraction_points)) | same engine rows; wizard offers the 4 distances including angular | | | | |

Combinations: every analysis accepts all five fields together natively (`Limits.cpp:36-46`; `SegmentBetweenness.cpp:263-282`); only rPST (and Angular Integration/Choice in the plugin) applies them together. Exposure through multi-valued vectors: rejected by rPST for these three analyses (NI-009, NR-010, NB-015).

## 3. Distance x radius x weights x normalisation (Network Betweenness)

| axis | native (`SegmentBetweenness.cpp`) | Network Betweenness wizard | Attraction Betweenness wizard | rPST |
|---|---|---|---|---|
| distance | walking, steps, angular, axmeter accepted; straight/weights return false (:604-614) | walking (default ticked), steps, axmeter | walking, steps, angular, axmeter | the four native modes, exact names, default `steps` |
| radius | five fields, any combination | five types, one per run | five types, one per run | five fields combined; scalar only |
| weights | per segment (m_Weights) or per attraction point; origin skipped when not > 0 (:207) | none / length / data columns | none (unit) / data column | NULL or one numeric vector (per line, or per attraction point) |
| normalisation | `PSTAStandardNormalize(scores)`, `PSTABetweennessNormalize(scores, node_counts)`, `PSTABetweennessSyntaxNormalize(scores, total_depths)` | none, standard | none, standard | none, standard, freeman, syntax |
| diagnostics | node_count (incl. origin), total_depth (angular in syntax units, :570) | N, TD, MD optional, first weight mode only | none | node_count, total_depth always; NA for skipped origins |

## 4. Restriction history (git evidence in the pinned clone)

| restriction | introduced | message | first tag | explanation |
|---|---|---|---|---|
| Network Integration: axial lines only, steps radius only | `5f3f70f` 2024-10-17 martin-fitger | "pstqgis: networkintegration: Only allow axial network and only support step radius." (touches `networkintegrationanalysis.py`, `radiuspage.py`, `networkinputpage.py`, wizards) | v3.3.1 (contained in v3.3.2) | none found (no body, no issue reference, no changelog; the old split line is kept as a comment) |
| NI label "Axial (topological) steps" | `dac509f` 2024-11-01 | "pstqgis: network integration:: Changed text for step radius." | v3.3.1 | text only |
| Network Betweenness: no angular distance, no Turner/NACH normalisation | `1c166e8` 2021-03-02 | "New analysis \"Angular Betweenness\" and distinction between road network types in \"Create Segment Map\"" | v3.2.2 | none found beyond coincidence with the new segment-graph Angular Betweenness (which offers `AngularChoiceNormalize`/`AngularChoiceSyntaxNormalize`, `angularbetweennessanalysis.py:116-127`) |
| Wizard polygon edge sampling absent for Attraction Betweenness | present since a808c54 | n/a | v3.1.3 | `dest_poly_edge_point_interval_enabled` is read only in `ReadAttractionPoints` (attractiondistanceanalysis.py:258) and registered only by the Attraction Reach/Distance entry-points page |

## 5. Defaults compared (native / Python / rPST)

| parameter | native | Python | rPST |
|---|---|---|---|
| NI radius | unlimited | steps unchecked (value 2) -> unlimited | `steps = NULL` unlimited |
| Reach radius | unlimited | none ticked -> split() empty -> nothing runs | `analysis_radius()` unlimited |
| Betweenness distance | Steps (`SegmentBetweenness.h:150`) | walking ticked | "steps" |
| Betweenness normalisation | n/a | none | "none" |
| Betweenness weights | nullptr | none | NULL |
| junctions | null | off | FALSE |
| polygon interval | 0 (hangs if used) | 0 means "points" | required > 0 |
| Radii struct | zeroed by constructor (`Common.cpp:32-35`) | zeroed in `Radii.__init__` | `SPSTARadii` default constructed then Set* |

## 6. Struct fields left at defaults

`SPSTANetworkIntegrationDesc` has a user constructor (zeroes pointers, `NetworkIntegration.cpp:118-129`), so `desc{}` is fully initialised; `SPSTAReachDesc` and `SPSTASegmentBetweennessDesc` use default member initialisers. rPST leaves progress callback and user pointer null (Python sets a wrapper); all other fields are set explicitly. No field is uninitialised. One native hazard: the Python wrapper's junction score buffer is not zeroed whereas the engine accumulates with `+=`; rPST zero-seeds (`pst-graph.cpp:735`).

## 7. Per-row evidence prose

### NI-001  [G]  network_integration / graph (HPSTAGraph axial)

- native_support: accepted (axial HPSTAGraph; CAxialGraph cast, no tag check)
- python_exposure: available
- rpst_exposure: accepted (live axial pst_graph only)
- defaults (native / python / rpst): none (required) / required (built by BuildAxialGraph) / required
- evidence: pstalgo/src/analyses/NetworkIntegration.cpp:139,153; analyses/networkintegrationanalysis.py:68-76; R/integration.R:88; src/pst-graph.cpp:683
- discrepancy: None. rPST validates tag/liveness before native access; native performs an unchecked cast.
- test_coverage: tests/testthat/test-network-integration.R:97-129,148
- risk: none; recommendation: preserve

Native casts desc->m_Graph to CAxialGraph without any check (NetworkIntegration.cpp:139,153); a segment handle would be reinterpreted. rPST's graph_handle() checks tag and liveness first (pst-graph.cpp:683). Python builds the graph via BuildAxialGraph (utils.py:103-184).

### NI-002  [G]  network_integration / steps radius (scalar, topological)

- native_support: accepted (LimitsFromSPSTARadii -> MASK_TURNS; upstream test testnetworkintegration.py:54-56)
- python_exposure: available (only radius type in wizard; checkbox default unchecked, default value 2)
- rpst_exposure: accepted (steps=, positional 2nd arg; or radius=analysis_radius(steps=))
- defaults (native / python / rpst): none (mask 0 = unlimited) / unchecked -> rad_steps_enabled False -> Radii() unlimited; UI value 2 / NULL (unlimited)
- evidence: pstalgo/src/Limits.cpp:41-42,50; pstalgo/src/BFS.cpp:329-330; pstalgo/test/tests/testnetworkintegration.py:54-56; analyses/networkintegrationanalysis.py:46-48; ui/wizards/networkintegrationwiz.py:34; ui/pages/radiuspage.py:56-57; R/integration.R:78,89; R/radius.R:135-141; src/pst-graph.cpp:158-205
- discrepancy: None for the value domain. Python converts with int(value) and a c_uint field with no range check; rPST requires a non-negative whole number <= INT_MAX.
- test_coverage: tests/testthat/test-network-integration.R:12-65; test-core-network-analyses.R:123-137; fixtures core-network-direct (integration steps 1)
- risk: none; recommendation: preserve

This is the only radius the application wizard offers. Steps counts line changes, collinear endpoint joins included (BFS.cpp:270 ++turns per crossing traversal). Python Radii.setSteps does int(value) into an unsigned ctypes field (common.py:165-167, :103), so a negative UI value would wrap; the native field is signed int (Common.h:284). rPST stricter (radius.R:135-141; pst-graph.cpp:187-190).

### NI-003  [G]  network_integration / radius unrestricted (no limit)

- native_support: accepted (mask 0 => infinity)
- python_exposure: available (leave 'steps' unticked)
- rpst_exposure: accepted (default)
- defaults (native / python / rpst): unlimited / unlimited / unlimited
- evidence: pstalgo/src/analyses/Common.cpp:32-35; analyses/networkintegrationanalysis.py:47; R/integration.R:78; tests/testthat/test-network-integration.R:12
- discrepancy: None.
- test_coverage: tests/testthat/test-network-integration.R:12-65; test-core-network-analyses.R:123-137
- risk: none; recommendation: preserve

Both interfaces default to an unrestricted search; verified by execution that network_integration(g) on a 5-line chain returns node_count 5 for every line.

### NI-004  [E]  network_integration / walking radius

- native_support: accepted (upstream test testnetworkintegration.py:51-53; BFS testLimit walking)
- python_exposure: disabled (not offered; Python hard-codes steps-only: RadiiFromSettings call commented out)
- rpst_exposure: accepted via radius=analysis_radius(walking=)
- defaults (native / python / rpst): unlimited / n/a (cannot be set) / unlimited
- evidence: pstalgo/test/tests/testnetworkintegration.py:51-53; pstalgo/src/BFS.cpp:327-328,353-360; analyses/networkintegrationanalysis.py:45-48; ui/wizards/networkintegrationwiz.py:34; R/integration.R:89; docs/compatibility/qgis-differences.md:28; git 5f3f70f
- discrepancy: QGIS restriction is Python/UI-only (C); native accepts and has a pinned numerical test. rPST exposes it with a documented performance warning: Barnsbury 400 m walking had not finished in 60 s (see W report).
- test_coverage: tests/testthat/test-core-network-analyses.R:244-276 + fixtures/core-network-direct-v3.3.2.R (60 direct-native cases) (integration walking 3); tests only on tiny graphs
- risk: performance (BFS checkpoint revisit grows with walking radius on large graphs; see W report); recommendation: investigate

Restriction history: 5f3f70f (2024-10-17, martin-fitger) 'pstqgis: networkintegration: Only allow axial network and only support step radius.' first in tag v3.3.1 (not 3.3.2); dac509f (2024-11-01) 'Changed text for step radius.'. The commit message gives the intent (axial only, steps only) but no reason; no issue reference, no changelog, no code comment found: no explanation found. It also left the old line as a comment (networkintegrationanalysis.py:45). Because the same commit dates after 3.2.x where all five radii were offered (git show 5f3f70f^: RadiiFromSettings(...).split()), the restriction is a deliberate application change, not a native limit. Native evidence: NetworkIntegration.cpp:154 passes the full radii via LimitsFromSPSTARadii; BFS.cpp:327-328 tests walking in testLimit; upstream test lines 51-53 cover walking 0/1/3 on a 5-chain. Performance of the walking BFS on real networks is outside this report: see W report. rPST row classified E (accepted, performance evidence insufficient) rather than D.

### NI-005  [D]  network_integration / straight radius

- native_support: accepted (testnetworkintegration.py:48-50; BFS.cpp:199,338-345)
- python_exposure: disabled (not offered)
- rpst_exposure: accepted via radius=
- defaults (native / python / rpst): unlimited / n/a / unlimited
- evidence: pstalgo/test/tests/testnetworkintegration.py:48-50; pstalgo/src/BFS.cpp:198-200,338-345; R/integration.R:89; git 5f3f70f
- discrepancy: Python/UI-only restriction (C). Semantics: in the BFS the straight limit is tested on crossing points relative to the origin line mid-point, not on target-line mid-points (differs from Reach straight-only and Betweenness).
- test_coverage: tests/testthat/test-core-network-analyses.R:244-276 + fixtures/core-network-direct-v3.3.2.R (60 direct-native cases) (integration straight 3)
- risk: none; recommendation: preserve

Verified by execution: on a line of length 10 crossed by a vertical line at x=6, NI with straight=3 reaches the crossing line (node_count 2 for the long line, 1 for the other since its far crossing is outside), i.e. crossing-based. See NR-009 for the three straight semantics.

### NI-006  [D]  network_integration / angular radius

- native_support: accepted (testnetworkintegration.py:57; BFS.cpp:331-332)
- python_exposure: disabled (not offered)
- rpst_exposure: accepted via radius=
- defaults (native / python / rpst): unlimited / n/a / unlimited
- evidence: pstalgo/test/tests/testnetworkintegration.py:57; pstalgo/src/BFS.cpp:331-332,371-377; R/integration.R:89
- discrepancy: Python/UI-only restriction (C). Native accepts; angle accumulates in BFS.cpp:144-150.
- test_coverage: tests/testthat/test-core-network-analyses.R:244-276 + fixtures/core-network-direct-v3.3.2.R (60 direct-native cases) (integration angular 100)
- risk: none; recommendation: preserve

Executed: collinear 5-chain with angular=0 returns the unrestricted result (all joins have zero deflection), consistent with BFS angle accumulation.

### NI-007  [D]  network_integration / axmeter radius

- native_support: accepted (BFS.cpp:333-334; no pinned upstream NI test with axmeter)
- python_exposure: disabled (not offered)
- rpst_exposure: accepted via radius=
- defaults (native / python / rpst): unlimited / n/a / unlimited
- evidence: pstalgo/src/BFS.cpp:211,219,333-334,379-384; R/integration.R:89
- discrepancy: Python/UI-only restriction (C). No upstream numerical test for axmeter in NI; rPST fixture compares against direct native execution.
- test_coverage: tests/testthat/test-core-network-analyses.R:244-276 + fixtures/core-network-direct-v3.3.2.R (60 direct-native cases) (integration axmeter 10)
- risk: none; recommendation: preserve

Native axmeter uses (steps+1)*length accumulation (BFS.cpp:211). rPST evidence is direct pinned-engine execution (fixture), level N.

### NI-008  [D]  network_integration / combined radii (several limit types in one run)

- native_support: accepted (mask bits OR-ed; testLimit applies all)
- python_exposure: disabled (Python never combines; even where the split is active it runs one type per run)
- rpst_exposure: accepted (e.g. steps=2 + walking=7)
- defaults (native / python / rpst): unlimited / n/a / unlimited
- evidence: pstalgo/src/Limits.cpp:36-46; pstalgo/src/BFS.cpp:325-336; docs/compatibility/qgis-differences.md:28; R/radius.R:31-37
- discrepancy: Native supports combined limits; plugin does not.
- test_coverage: tests/testthat/test-core-network-analyses.R:244-276 + fixtures/core-network-direct-v3.3.2.R (60 direct-native cases) (integration 'all five radii' case)
- risk: performance (walking combined with steps does not prune revisits; see W report); recommendation: preserve

Executed: steps=2 + walking=7 on a 5-line chain of length-3 lines is accepted and returns finite scores (node_count 3,4,5,4,3). Documented as a deliberate departure in qgis-differences.md:28.

### NI-009  [F]  network_integration / multi-valued radius (vector)

- native_support: n/a (single scalar per field)
- python_exposure: disabled (Python would have split by type, but NI does not split)
- rpst_exposure: rejected (explicit error before native work)
- defaults (native / python / rpst): n/a / n/a / error
- evidence: R/radius.R:43-55; docs/compatibility/multi-radius.md:§9; src/pst-graph.cpp:158-205
- discrepancy: rPST convenience not provided for NI (documented as deferred); user can loop. No native reason.
- test_coverage: tests/testthat/test-multi-radius.R
- risk: usability; recommendation: preserve

Executed: network_integration(g, radius=analysis_radius(steps=c(1,2))) -> 'supported only by angular_choice() and angular_integration()'. Documented as deferred in multi-radius.md section 9 ('per-radius table assembly is analysis-specific'). Low impact: loop over scalar radii.

### NI-010  [D]  network_integration / steps + radius supplied together

- native_support: n/a
- python_exposure: n/a
- rpst_exposure: rejected ('Supply either steps or radius, not both')
- defaults (native / python / rpst): n/a / n/a / error
- evidence: R/radius.R:142-148; tests/testthat/test-core-network-analyses.R:130
- discrepancy: rPST API design; avoids silent precedence.
- test_coverage: tests/testthat/test-network-integration.R:12-65; test-core-network-analyses.R:123-137
- risk: none; recommendation: preserve

Executed (error text confirmed). Positional `steps` plus additive `radius` keep legacy calls identical.

### NI-011  [D]  network_integration / steps value domain (NA, fractional, negative, > INT_MAX, vector)

- native_support: accepted: signed int field; negative would give 'no steps' semantics = reach nothing (turns > negative)
- python_exposure: accepted unvalidated (float -> int() -> c_uint)
- rpst_exposure: rejected (non-negative whole number <= 2147483647, scalar)
- defaults (native / python / rpst): n/a / n/a / n/a
- evidence: pstalgo/include/pstalgo/analyses/Common.h:284; pstalgo/python/pstalgo/common.py:103,165-167; R/radius.R:135-141; src/pst-graph.cpp:187-190
- discrepancy: rPST stricter than both layers, aligned with the signed native field.
- test_coverage: tests/testthat/test-network-integration.R:97-129
- risk: none; recommendation: preserve

Executed: 1.5, -1, NA, 'a', 2^31, c(1,2) all rejected with the single steps message; 2147483647 accepted. Python's c_uint field would wrap a negative value to 4294967295 which the signed native int reads as -1.

### NI-012  [D]  network_integration / junction output (output_at_junctions / junctions=TRUE)

- native_support: accepted; accumulates line score / crossing.nLines into caller buffer (+=, must be zero-seeded)
- python_exposure: available but BROKEN in application (NameError: column_base_name undefined at l.128); buffer not zeroed
- rpst_exposure: accepted (zero-seeded buffer, native coordinates)
- defaults (native / python / rpst): off / False (checkbox)  / FALSE
- evidence: pstalgo/src/analyses/NetworkIntegration.cpp:160-189 (185: += score / crossing.nLines); pstalgo/src/graph/AxialGraph.cpp:338,342,391-404 (updateLinesPerCrossingCount defined, never called); analyses/networkintegrationanalysis.py:84-86,125-136 (128 undefined name); ui/wizards/networkintegrationwiz.py:59; R/integration.R:78-110; src/pst-graph.cpp:731-736
- discrepancy: Application defect not copied (documented, qgis-differences.md:33). Engine quirk preserved: crossing.nLines counts pairwise crossing records (k(k-1)/2 for k concurrent lines), so the score at a crossing equals 2 x mean (2-line join = sum). Wizard label says 'average'.
- test_coverage: tests/testthat/test-axial-inputs.R:49-93
- risk: correctness (label 'average' misleads; value = 2 x mean of line scores); recommendation: preserve

Executed: three concurrent lines (scores 3.4902, 1.7451, 1.1634): junction(0,0) = 4.26583 = 2 x mean (2.1329) and = sum x 2/3; a two-line chain join gives 1.05598 = 0.35199 + 0.70399 (sum). Native comment/UI promise an average but findCrossings sets nLines per pair record (AxialGraph.cpp:338,342, incremented once per cross_map entry) and updateLinesPerCrossingCount is never called (grep). rPST documents it ('not a conventional distinct-line mean', integration.R) but not the exact 2 x mean relation; consider adding.

### NI-013  [D]  network_integration / junction_output = 'sf' (POINT sf)

- native_support: n/a (R-side wrapper)
- python_exposure: absent
- rpst_exposure: accepted (requires junctions=TRUE and sf)
- defaults (native / python / rpst): n/a / n/a / 'native'
- evidence: R/integration.R:78-110; tests/testthat/test-sf-betweenness-integration.R
- discrepancy: rPST interface extension (intentional).
- test_coverage: tests/testthat/test-sf-betweenness-integration.R
- risk: none; recommendation: preserve

Geometry built solely from native junction coordinates; no extra native call.

### NI-014  [C]  network_integration / output columns N, TD, MD (node count, total depth, mean depth)

- native_support: N and TD written when buffers non-null; MD not computed natively
- python_exposure: available as three checkboxes (default all True); MD = TD/(N-1) computed in Python, 0.0 when N<=1 (MeanDepthGen)
- rpst_exposure: node_count and total_depth always; mean depth not provided
- defaults (native / python / rpst): not written / N,TD,MD True / node_count,total_depth always
- evidence: pstalgo/src/analyses/NetworkIntegration.cpp:95-99; analyses/networkintegrationanalysis.py:80-81,116-121; analyses/utils.py:242-245; ui/wizards/networkintegrationwiz.py:55-57; R/integration.R:78
- discrepancy: Python-only post-processing (C): mean depth. rPST always returns N and TD; users compute MD = total_depth/(node_count-1) themselves.
- test_coverage: tests/testthat/test-network-integration.R:12
- risk: none; recommendation: preserve

Python computes TD/(N-1) with 0.0 for N<=1; rPST preserves raw native N and TD. No numerical risk; documented as available derivation only implicitly (no mention in qgis-differences.md).

### NI-015  [G]  network_integration / normalisation

- native_support: no exported normaliser; score computed internally by CalculateIntegrationScore (RRA-based)
- python_exposure: absent
- rpst_exposure: absent
- defaults (native / python / rpst): n/a / n/a / n/a
- evidence: pstalgo/src/analyses/NetworkIntegration.cpp:32-41; docs/compatibility/core-network-analyses.md (Distance, settings and normalization)
- discrepancy: None. N/A for the internal engineering rules, section 3 buffer mapping: integration is computed inside the engine.
- test_coverage: tests/testthat/test-network-integration.R:12
- risk: none; recommendation: preserve

Returned -1 (N<2), NaN (N=2) and Inf (RA=0) are native sentinels preserved by both layers (executed: chain steps=1 gives NaN at ends, Inf in the middle).

### NI-016  [G]  network_integration / distance type

- native_support: fixed topological (DIST_LINES); no parameter
- python_exposure: absent (fixed)
- rpst_exposure: absent (fixed)
- defaults (native / python / rpst): steps / steps / steps
- evidence: pstalgo/src/analyses/NetworkIntegration.cpp:69; pstalgo/include/pstalgo/analyses/NetworkIntegration.h:28-55
- discrepancy: None.
- test_coverage: none found
- risk: none; recommendation: preserve

CNetworkIntegrationAlgo::Run initialises the BFS with DIST_LINES and TARGET_LINES; total depth sums dist.turns (NetworkIntegration.cpp:113).

### NI-017  [D]  network_integration / progress callback / cancellation

- native_support: accepted; BFS cancel flag exists but is never set by NI
- python_exposure: Python passes a progress wrapper
- rpst_exposure: null callback (no progress, no R call from native)
- defaults (native / python / rpst): null / wrapper / null
- evidence: pstalgo/src/analyses/NetworkIntegration.cpp:80,151; analyses/networkintegrationanalysis.py:104; src/pst-graph.cpp:737-746
- discrepancy: rPST intentional: no R callback from native.
- test_coverage: none found
- risk: usability; recommendation: preserve

Struct fields m_ProgressCallback(User) stay at the constructor's nullptr (NetworkIntegration.cpp:118-129); documented in the internal engineering rules, section 7.

### NI-018  [G]  network_integration / struct fields left at defaults

- native_support: constructor zero-initialises all optional pointers
- python_exposure: Python sets m_Version=1, callbacks, outputs
- rpst_exposure: rPST uses SPSTANetworkIntegrationDesc desc{} then sets version, graph, radius, outputs
- defaults (native / python / rpst): nullptr / set / set
- evidence: pstalgo/src/analyses/NetworkIntegration.cpp:118-129; pstalgo/python/pstalgo/networkintegration.py:52-79; src/pst-graph.cpp:737-746
- discrepancy: No uninitialised fields. rPST always supplies all three line outputs; junction count passed equals graph crossing count (else native zero-fills and logs, NetworkIntegration.cpp:160-167).
- test_coverage: tests/testthat/test-network-integration.R
- risk: none; recommendation: preserve

A user-provided constructor makes desc{} value-initialise correctly; verified from source.

### NI-019  [D]  network_integration / output_file / spatial_output_file

- native_support: n/a
- python_exposure: absent
- rpst_exposure: accepted (line results only, junctions=FALSE)
- defaults (native / python / rpst): n/a / n/a / NULL
- evidence: R/integration.R:78-110; src/pst-graph.cpp:680-700
- discrepancy: rPST extension (intentional).
- test_coverage: tests/testthat/test-result-axial.R; test-spatial-output.R
- risk: none; recommendation: preserve

Not a PST parameter; written from the native arrays without R vectors.

### NR-001  [G]  network_reach / graph (HPSTAGraph axial)

- native_support: accepted (cast; no check)
- python_exposure: available
- rpst_exposure: accepted (live axial pst_graph)
- defaults (native / python / rpst): required / required / required
- evidence: pstalgo/src/analyses/Reach.cpp:278; analyses/reachanalysis.py:67-75; R/core-analyses.R:46,48; src/pst-graph.cpp:1231
- discrepancy: None.
- test_coverage: tests/testthat/test-core-network-analyses.R:140-167
- risk: none; recommendation: preserve

### NR-002  [D]  network_reach / straight radius

- native_support: accepted (Reach.cpp:107-126,151-176 straight-only mid-point rule; BFS.cpp:198-200 combined crossing rule; pinned test testreach.py:38-40)
- python_exposure: available (checkbox, default 1000 m, unchecked)
- rpst_exposure: accepted via radius=analysis_radius(straight=)
- defaults (native / python / rpst): unlimited / unlimited unless ticked / unlimited
- evidence: pstalgo/src/analyses/Reach.cpp:107-126,151-176,214-219; pstalgo/src/BFS.cpp:198-200,338-345; pstalgo/test/tests/testreach.py:38-40; analyses/utils.py:218-224; ui/pages/radiuspage.py:51-61; R/radius.R:31-37
- discrepancy: Semantics differ between straight-only and combined use (NR-009).
- test_coverage: tests/testthat/test-core-network-analyses.R:244-276 + fixtures/core-network-direct-v3.3.2.R (60 direct-native cases) (reach straight)
- risk: correctness; recommendation: preserve

Python offers every radius type to Reach but runs one type per run (RadiiFromSettings(...).split(), reachanalysis.py:44; common.py:177-189); rPST takes the same single type per call or any combination (NR-008). Executed: straight=3 on a length-10 line crossed by a long line at x=6: straight-only counts 1 line (mid-point of the long line is far), straight=3 + steps=100 counts 2.

### NR-003  [E]  network_reach / walking radius

- native_support: accepted (BFS.cpp:327-328; pinned test testreach.py:41-43)
- python_exposure: available (checkbox, default 1000 m, unchecked)
- rpst_exposure: accepted via radius=analysis_radius(walking=)
- defaults (native / python / rpst): unlimited / unlimited unless ticked / unlimited
- evidence: pstalgo/src/BFS.cpp:96-98,327-328,353-360; pstalgo/test/tests/testreach.py:41-43; analyses/utils.py:218-224; ui/pages/radiuspage.py:51-61; R/radius.R:31-37
- discrepancy: None for values; BFS cost on large graphs not established here: see W report.
- test_coverage: tests/testthat/test-core-network-analyses.R:244-276 + fixtures/core-network-direct-v3.3.2.R (60 direct-native cases) (reach walking)
- risk: performance; recommendation: investigate

Python offers every radius type to Reach but runs one type per run (RadiiFromSettings(...).split(), reachanalysis.py:44; common.py:177-189); rPST takes the same single type per call or any combination (NR-008). Same BFS as NI. The walking limit includes the distance from a point origin to its closest line (BFS.cpp:96-98). Performance evidence is W's remit.

### NR-004  [G]  network_reach / steps radius

- native_support: accepted (BFS.cpp:329-330; pinned test testreach.py:44-46)
- python_exposure: available (checkbox, default 2, unchecked)
- rpst_exposure: accepted via radius=analysis_radius(steps=)
- defaults (native / python / rpst): unlimited / unlimited unless ticked / unlimited
- evidence: pstalgo/src/BFS.cpp:329-330; pstalgo/test/tests/testreach.py:44-46; analyses/utils.py:218-224; ui/pages/radiuspage.py:51-61; R/radius.R:31-37
- discrepancy: None.
- test_coverage: tests/testthat/test-core-network-analyses.R:244-276 + fixtures/core-network-direct-v3.3.2.R (60 direct-native cases) (reach steps)
- risk: none; recommendation: preserve

Python offers every radius type to Reach but runs one type per run (RadiiFromSettings(...).split(), reachanalysis.py:44; common.py:177-189); rPST takes the same single type per call or any combination (NR-008).

### NR-005  [G]  network_reach / angular radius

- native_support: accepted (BFS.cpp:331-332; pinned tests testreach.py:47,60-63)
- python_exposure: available (checkbox, default 180, unchecked)
- rpst_exposure: accepted via radius=analysis_radius(angular=)
- defaults (native / python / rpst): unlimited / unlimited unless ticked / unlimited
- evidence: pstalgo/src/BFS.cpp:331-332; pstalgo/test/tests/testreach.py:47,60-63; analyses/utils.py:218-224; ui/pages/radiuspage.py:51-61; R/radius.R:31-37
- discrepancy: None.
- test_coverage: tests/testthat/test-core-network-analyses.R:244-276 + fixtures/core-network-direct-v3.3.2.R (60 direct-native cases) (reach angular)
- risk: none; recommendation: preserve

Python offers every radius type to Reach but runs one type per run (RadiiFromSettings(...).split(), reachanalysis.py:44; common.py:177-189); rPST takes the same single type per call or any combination (NR-008).

### NR-006  [D]  network_reach / axmeter radius

- native_support: accepted (BFS.cpp:333-334; no pinned upstream Reach test for axmeter)
- python_exposure: available (checkbox, default 2000, unchecked)
- rpst_exposure: accepted via radius=analysis_radius(axmeter=)
- defaults (native / python / rpst): unlimited / unlimited unless ticked / unlimited
- evidence: pstalgo/src/BFS.cpp:211,333-334; analyses/utils.py:218-224; ui/pages/radiuspage.py:51-61; R/radius.R:31-37
- discrepancy: No pinned upstream test; rPST checked against direct native execution only (fixture, level N).
- test_coverage: tests/testthat/test-core-network-analyses.R:244-276 + fixtures/core-network-direct-v3.3.2.R (60 direct-native cases) (reach axmeter)
- risk: none; recommendation: preserve

Python offers every radius type to Reach but runs one type per run (RadiiFromSettings(...).split(), reachanalysis.py:44; common.py:177-189); rPST takes the same single type per call or any combination (NR-008).

### NR-007  [D]  network_reach / no radius supplied (default)

- native_support: accepted (mask 0 -> whole network)
- python_exposure: no type ticked -> split() returns [] -> analysis_count 0 -> nothing is computed or written (silent no-op; no validation in RadiusPage)
- rpst_exposure: analysis_radius() default -> unrestricted
- defaults (native / python / rpst): unlimited / no-op / unlimited
- evidence: pstalgo/python/pstalgo/common.py:177-189; analyses/reachanalysis.py:44,46,96; ui/pages/radiuspage.py:69-84 (no validatePage); R/core-analyses.R:46
- discrepancy: Application quirk (no-op with all radius boxes unticked); rPST returns the unrestricted result, equal to the pinned test Radii() case.
- test_coverage: tests/testthat/test-core-network-analyses.R:21
- risk: none; recommendation: preserve

Application behaviour derived from code: radii_list empty -> loop body never runs (reachanalysis.py:96) but the wizard still reports done. Not an engine property.

### NR-008  [D]  network_reach / combined radii

- native_support: accepted
- python_exposure: disabled (split)
- rpst_exposure: accepted
- defaults (native / python / rpst): unlimited / n/a / unlimited
- evidence: pstalgo/src/analyses/Reach.cpp:107,151,214 (MASK_STRAIGHT == mask exact test); R/radius.R:31-37; docs/compatibility/qgis-differences.md:28
- discrepancy: Intentional departure documented.
- test_coverage: tests/testthat/test-core-network-analyses.R:244-276 + fixtures/core-network-direct-v3.3.2.R (60 direct-native cases) (reach 'all five' case)
- risk: correctness (semantic switch of straight rule, see NR-009); recommendation: preserve

Any combination containing straight plus another limit takes the BFS path and the convex-hull area, not the pi r^2 area.

### NR-009  [G]  network_reach / straight-only vs straight-plus-other semantics

- native_support: accepted (three different rules inside the engine)
- python_exposure: straight-only only (split)
- rpst_exposure: both reachable
- defaults (native / python / rpst): n/a / n/a / n/a
- evidence: pstalgo/src/analyses/Reach.cpp:107-126 (points, strict <), :151-176 (lines, <= on mid-point distance), :214-219 (pi*r^2 area), pstalgo/src/BFS.cpp:198-200,338-345 (crossing rule); pstalgo/src/analyses/SegmentBetweenness.cpp:279-281,406-408 (target mid-point rule)
- discrepancy: Same nominal 'straight radius' means: mid-point distance (Reach straight-only), crossing-point distance (BFS: NI, combined Reach), target mid-point (Betweenness). Preserved engine behaviour; user-visible.
- test_coverage: tests/testthat/test-origin-attraction-modes.R:108-130; test-core-network-analyses.R:21-31
- risk: correctness (surprise when adding a second limit); recommendation: preserve

Executed on lines (0,0)-(10,0) and (6,0)-(6,100): Reach straight=3 -> counts 1,1, lengths 10,100, area 28.274 (pi*9); straight=3 + steps=100 -> origin line 1 reaches 2 lines (length 110), hull area 500. Documented per branch in R docs of network_reach ('Straight-only ...'), not as a warning about combinations. Recommend a one-line note.

### NR-010  [F]  network_reach / multi-valued radius

- native_support: n/a
- python_exposure: enabled via split() (one run per type, but across types, not values)
- rpst_exposure: rejected
- defaults (native / python / rpst): n/a / n/a / error
- evidence: R/radius.R:43-55; docs/compatibility/multi-radius.md:§9
- discrepancy: Deferred convenience; no native reason.
- test_coverage: tests/testthat/test-multi-radius.R
- risk: usability; recommendation: preserve

Workaround: loop over scalar radii.

### NR-011  [C]  network_reach / origins (point origins)

- native_support: accepted (origin_points double2; closest-line snapping, no distance cap)
- python_exposure: available (checkbox 'Origin points'; any geometry -> centroid; null geometry skipped)
- rpst_exposure: accepted (numeric 2-col matrix or sf POINT; finite; >=1 row)
- defaults (native / python / rpst): NULL -> lines / False / NULL (lines)
- evidence: pstalgo/src/analyses/Reach.cpp:82-89,101-145; pstalgo/src/BFS.cpp:82-100; pstalgo/src/graph/AxialGraph.cpp:118-163; analyses/reachanalysis.py:78-85; pstqgis/src/pst/model/model.py:259-273; ui/pages/networkinputpage.py:58-65; R/core-analyses.R:46; src/pst-graph.cpp:85-128
- discrepancy: Python converts non-point geometries to centroids silently; rPST requires points. Native snaps an origin to the closest line at any distance (executed: origin (1e6,1e6) with unlimited radius reaches 2 of 2 lines).
- test_coverage: tests/testthat/test-origin-attraction-modes.R:108-130,131-189; test-sf-analysis-inputs.R
- risk: correctness (far origins silently snapped when radius is unrestricted); recommendation: preserve

With a walking/straight/axmeter radius the snap distance counts in the limit (BFS.cpp:96-98), so far origins reach nothing; unrestricted or steps/angular radii ignore the distance. rPST rejects 0-row and non-finite origins (executed).

### NR-012  [F]  network_reach / output count / length / area switches (calc_count, calc_length, calc_area)

- native_support: outputs optional (null pointer skips; area skips hull)
- python_exposure: available (3 checkboxes, default True)
- rpst_exposure: absent: all three always requested
- defaults (native / python / rpst): null / True / all three
- evidence: pstalgo/src/analyses/Reach.cpp:70-81,205-208,140-144; analyses/reachanalysis.py:89-91; src/pst-graph.cpp:1259-1268
- discrepancy: rPST cannot opt out of the area computation, which is per-origin sorting plus hull over all reached end points.
- test_coverage: tests/testthat/test-core-network-analyses.R:18-48
- risk: performance (extra O(R log R) per origin on large reach); recommendation: investigate

Not measured here. Native supports skipping by passing null pointers (Reach.cpp:78-80).

### NR-013  [C]  network_reach / area unit (m2 / km2 / ha)

- native_support: area in squared coordinate units
- python_exposure: available (default 'm2'; float32 multiply after native call)
- rpst_exposure: absent (native units only)
- defaults (native / python / rpst): m2 (coord units) / m2 / coordinate units
- evidence: analyses/reachanalysis.py:111-118,148-155; ui/wizards/reachwiz.py:67-80; R/core-analyses.R:46
- discrepancy: Python-only post-processing (C); documented in qgis-differences.md:29.
- test_coverage: none found
- risk: usability; recommendation: preserve

Factors 1e-6 and 1e-4 assume metric coordinates; rPST states no unit conversion occurs.

### NR-014  [G]  network_reach / area semantic (hull vs pi r^2) and degenerate hulls

- native_support: accepted
- python_exposure: passes through
- rpst_exposure: passes through
- defaults (native / python / rpst): n/a / n/a / n/a
- evidence: pstalgo/src/analyses/Reach.cpp:212-256
- discrepancy: None. Fewer than 3 distinct end points give area 0; straight-only gives exact pi*r^2 regardless of network.
- test_coverage: tests/testthat/test-core-network-analyses.R:21-31
- risk: none; recommendation: preserve

Executed: unconnected line gives area 0; far origin gives hull 5.2e7 including the origin point.

### NR-015  [G]  network_reach / line-origin boundary inclusivity

- native_support: straight-only: line origins <=, point origins <
- python_exposure: passes through
- rpst_exposure: passes through (documented)
- defaults (native / python / rpst): n/a / n/a / n/a
- evidence: pstalgo/src/analyses/Reach.cpp:113 (<), :162 (<=)
- discrepancy: Engine asymmetry preserved and documented in R/core-analyses.R roxygen.
- test_coverage: tests/testthat/test-origin-attraction-modes.R:108-130
- risk: none; recommendation: preserve

### NR-016  [G]  network_reach / distance type

- native_support: none (DIST_NONE passed to BFS)
- python_exposure: absent
- rpst_exposure: absent
- defaults (native / python / rpst): n/a / n/a / n/a
- evidence: pstalgo/src/analyses/Reach.cpp:65
- discrepancy: None. updateCheckPoint therefore keys only on the radius mask (BFS.cpp:353-385).
- test_coverage: none found
- risk: none; recommendation: preserve

### NR-017  [G]  network_reach / unlinks / graph points

- native_support: unlinks change crossings and hence reach; graph points ignored by Reach
- python_exposure: unlinks supported (in_unlinks_enabled); points not passed
- rpst_exposure: via axial_graph(unlinks=); graph points accepted but unused
- defaults (native / python / rpst): n/a / n/a / n/a
- evidence: analyses/reachanalysis.py:72; pstalgo/src/graph/AxialGraph.cpp:204-300; R/graph.R:111
- discrepancy: See AX rows.
- test_coverage: tests/testthat/test-axial-inputs.R
- risk: none; recommendation: preserve

Executed: results identical with and without graph points (Reach, Betweenness walking, point-origin Reach).

### NR-018  [G]  network_reach / struct fields left at defaults

- native_support: default member initialisers (all nullptr/0); m_Radius via ctor
- python_exposure: Python sets all
- rpst_exposure: desc{} then sets graph, radius, origin pointers, count and three outputs
- defaults (native / python / rpst): nullptr / set / set
- evidence: pstalgo/include/pstalgo/analyses/Reach.h:86-111; pstalgo/python/pstalgo/reach.py:56-78; src/pst-graph.cpp:1259-1268
- discrepancy: None. m_OriginCount is set to points.count (0 for line origins) with m_OriginCoords nullptr.
- test_coverage: tests/testthat/test-origin-attraction-modes.R:190-214
- risk: none; recommendation: preserve

### NR-019  [D]  network_reach / output_file / spatial_output_file

- native_support: n/a
- python_exposure: absent
- rpst_exposure: accepted (spatial only with line origins)
- defaults (native / python / rpst): n/a / n/a / NULL
- evidence: R/core-analyses.R:46-70
- discrepancy: rPST extension.
- test_coverage: tests/testthat/test-result-axial.R
- risk: none; recommendation: preserve

### NB-001  [G]  network_betweenness / graph (HPSTAGraph axial)

- native_support: accepted (cast, no check)
- python_exposure: available
- rpst_exposure: accepted (live axial pst_graph)
- defaults (native / python / rpst): required / required / required
- evidence: pstalgo/src/analyses/SegmentBetweenness.cpp:714; analyses/networkbetweennessanalysis.py:93-100; R/core-analyses.R:138,144; src/pst-graph.cpp:1313
- discrepancy: None.
- test_coverage: tests/testthat/test-core-network-analyses.R:140-167
- risk: none; recommendation: preserve

### NB-002  [D]  network_betweenness / distance = walking

- native_support: accepted (SegmentBetweenness.cpp:605-610,285)
- python_exposure: available (checkbox, default ticked)
- rpst_exposure: accepted
- defaults (native / python / rpst): Steps (struct default) / walking ticked / steps
- evidence: pstalgo/src/analyses/SegmentBetweenness.cpp:285; pstalgo/include/pstalgo/analyses/SegmentBetweenness.h:150; ui/wizards/networkbetweennesswiz.py:51; R/core-analyses.R:138,146
- discrepancy: Default distance differs: wizard pre-ticks walking, rPST and native default to steps. rPST default is the native one and documented in roxygen; not recorded in qgis-differences.md.
- test_coverage: tests/testthat/test-core-network-analyses.R:244-276 + fixtures/core-network-direct-v3.3.2.R (60 direct-native cases) (betweenness walking x 8 radii)
- risk: usability; recommendation: preserve

the internal engineering rules, section 3 says application defaults are followed unless the departure is intentional and recorded in qgis-differences.md; this default choice is documented in roxygen and core-network-analyses.md only. Recommend adding a line to qgis-differences.md.

### NB-003  [G]  network_betweenness / distance = steps

- native_support: accepted
- python_exposure: available (checkbox, default unticked)
- rpst_exposure: accepted (default)
- defaults (native / python / rpst): Steps / unticked / steps
- evidence: pstalgo/src/analyses/SegmentBetweenness.cpp:286; ui/wizards/networkbetweennesswiz.py:52
- discrepancy: None.
- test_coverage: tests/testthat/test-core-network-analyses.R:244-276 + fixtures/core-network-direct-v3.3.2.R (60 direct-native cases)
- risk: none; recommendation: preserve

### NB-004  [D]  network_betweenness / distance = angular

- native_support: accepted on an axial graph (bidirectional states, 2 x line count; pinned test testsegmentbetweenness.py:41-60 uses ANGULAR via CreateGraph)
- python_exposure: disabled in Network Betweenness wizard; available in Attraction Betweenness wizard (Python accepts dist_angular via DistanceTypesFromSettings)
- rpst_exposure: accepted
- defaults (native / python / rpst): Steps / n/a / unticked / n/a
- evidence: pstalgo/src/analyses/SegmentBetweenness.cpp:149,223-228,287; pstalgo/test/tests/testsegmentbetweenness.py:41-60; analyses/utils.py:226-240; ui/wizards/networkbetweennesswiz.py:50-54; ui/wizards/attractionbetweennesswiz.py:50-55; R/core-analyses.R:145-146
- discrepancy: Python/UI-only restriction in Network Betweenness (C), absent restriction in Attraction Betweenness; native accepts. 1c166e8 (2021-03-02, martin-fitger) 'New analysis "Angular Betweenness" and distinction between road network types in "Create Segment Map"' (first in tag v3.2.2) removed dist_angular, Turner (norm_normalization) and NACH (norm_syntax) from the Network Betweenness wizard and analysis; the original a808c54 (2019-11-18, tags v3.1.3..) offered them.
- test_coverage: tests/testthat/test-core-network-analyses.R:244-276 + fixtures/core-network-direct-v3.3.2.R (60 direct-native cases) (betweenness angular x 8 radii)
- risk: none; recommendation: preserve

Restriction history: 1c166e8 (2021-03-02, martin-fitger) 'New analysis "Angular Betweenness" and distinction between road network types in "Create Segment Map"' (first in tag v3.2.2) removed dist_angular, Turner (norm_normalization) and NACH (norm_syntax) from the Network Betweenness wizard and analysis; the original a808c54 (2019-11-18, tags v3.1.3..) offered them. The commit message names only the new analysis; the removal of angular from Network Betweenness coincides with Angular Betweenness (segment-graph based, angularbetweennessanalysis.py) taking over angular centrality. No explanation found for the removal itself. Attraction Betweenness, unchanged since a808c54, still offers angular on the axial graph, so the engine path is exercised by the application.

### NB-005  [G]  network_betweenness / distance = axmeter

- native_support: accepted (SegmentBetweenness.cpp:288)
- python_exposure: available (checkbox, default unticked)
- rpst_exposure: accepted
- defaults (native / python / rpst): Steps / unticked / steps
- evidence: pstalgo/src/analyses/SegmentBetweenness.cpp:259-260,288; ui/wizards/networkbetweennesswiz.py:53
- discrepancy: None.
- test_coverage: tests/testthat/test-core-network-analyses.R:244-276 + fixtures/core-network-direct-v3.3.2.R (60 direct-native cases)
- risk: none; recommendation: preserve

### NB-006  [G]  network_betweenness / distance = straight / weights

- native_support: rejected (LOG_ERROR 'Unsupported distance type', returns false)
- python_exposure: absent in both wizards (Python helper would map dist_straight/dist_weights if props existed)
- rpst_exposure: rejected by exact name list
- defaults (native / python / rpst): Steps / n/a / error
- evidence: pstalgo/src/analyses/SegmentBetweenness.cpp:604-614; pstalgo/include/pstalgo/analyses/Common.h:221-232; analyses/utils.py:226-240; R/core-analyses.R:145-146; src/pst-graph.cpp:1316-1320
- discrepancy: None: B-type exposure is avoided; names are matched exactly (case-sensitive).
- test_coverage: tests/testthat/test-core-network-analyses.R:206
- risk: none; recommendation: preserve

Executed: 'straight', 'weights', 'Walking' and vectors are rejected with 'distance must be one of: walking, steps, angular, axmeter.'

### NB-007  [F]  network_betweenness / distance vector (several modes per run)

- native_support: n/a
- python_exposure: enabled: any ticked subset, one run per mode
- rpst_exposure: rejected (scalar only)
- defaults (native / python / rpst): n/a / walking / steps
- evidence: analyses/networkbetweennessanalysis.py:47,142; R/core-analyses.R:145-146
- discrepancy: Convenience of the wizard; loop in R.
- test_coverage: none found
- risk: usability; recommendation: preserve

### NB-008  [D]  network_betweenness / straight radius (all four distance modes)

- native_support: accepted (honoured in both seed expansion and traversal)
- python_exposure: available (one type per run via split(); wizard RadiusPage offers all five)
- rpst_exposure: accepted via radius=analysis_radius(straight=) with each of walking/steps/angular/axmeter
- defaults (native / python / rpst): unlimited / unticked (no run if none ticked) / unlimited
- evidence: pstalgo/src/analyses/SegmentBetweenness.cpp:279-281,406-408; analyses/networkbetweennessanalysis.py:44; ui/pages/radiuspage.py:51-61; R/core-analyses.R:138; src/pst-graph.cpp:1313-1320
- discrepancy: Target mid-point within straight distance of origin mid-point (applied to each expansion); another straight semantic (NR-009). Python never combines radius types with distance modes beyond looping them (networkbetweennessanalysis.py:140-142).
- test_coverage: tests/testthat/test-core-network-analyses.R:244-276 + fixtures/core-network-direct-v3.3.2.R (60 direct-native cases) (4 distances x each radius; straight)
- risk: none; recommendation: preserve

Matrix cell radius=straight x distance in {walking,steps,angular,axmeter}: all 4 accepted natively, in the wizard (radius page is shared) and in rPST; fixture lists 60 direct-native cases, 28 of them betweenness (7 radius sets x 4 distances).

### NB-009  [D]  network_betweenness / walking radius (all four distance modes)

- native_support: accepted (honoured in both seed expansion and traversal)
- python_exposure: available (one type per run via split(); wizard RadiusPage offers all five)
- rpst_exposure: accepted via radius=analysis_radius(walking=) with each of walking/steps/angular/axmeter
- defaults (native / python / rpst): unlimited / unticked (no run if none ticked) / unlimited
- evidence: pstalgo/src/analyses/SegmentBetweenness.cpp:263-266,390-393; analyses/networkbetweennessanalysis.py:44; ui/pages/radiuspage.py:51-61; R/core-analyses.R:138; src/pst-graph.cpp:1313-1320
- discrepancy: Walking accumulates mid-to-mid half-lengths ((len_a+len_b)/2 per hop). Python never combines radius types with distance modes beyond looping them (networkbetweennessanalysis.py:140-142).
- test_coverage: tests/testthat/test-core-network-analyses.R:244-276 + fixtures/core-network-direct-v3.3.2.R (60 direct-native cases) (4 distances x each radius; walking)
- risk: none; recommendation: preserve

Matrix cell radius=walking x distance in {walking,steps,angular,axmeter}: all 4 accepted natively, in the wizard (radius page is shared) and in rPST; fixture lists 60 direct-native cases, 28 of them betweenness (7 radius sets x 4 distances).

### NB-010  [D]  network_betweenness / steps radius (all four distance modes)

- native_support: accepted (honoured in both seed expansion and traversal)
- python_exposure: available (one type per run via split(); wizard RadiusPage offers all five)
- rpst_exposure: accepted via radius=analysis_radius(steps=) with each of walking/steps/angular/axmeter
- defaults (native / python / rpst): unlimited / unticked (no run if none ticked) / unlimited
- evidence: pstalgo/src/analyses/SegmentBetweenness.cpp:267-270,394-397; analyses/networkbetweennessanalysis.py:44; ui/pages/radiuspage.py:51-61; R/core-analyses.R:138; src/pst-graph.cpp:1313-1320
- discrepancy: Compared as (int)turns > m_Steps. Python never combines radius types with distance modes beyond looping them (networkbetweennessanalysis.py:140-142).
- test_coverage: tests/testthat/test-core-network-analyses.R:244-276 + fixtures/core-network-direct-v3.3.2.R (60 direct-native cases) (4 distances x each radius; steps)
- risk: none; recommendation: preserve

Matrix cell radius=steps x distance in {walking,steps,angular,axmeter}: all 4 accepted natively, in the wizard (radius page is shared) and in rPST; fixture lists 60 direct-native cases, 28 of them betweenness (7 radius sets x 4 distances).

### NB-011  [D]  network_betweenness / angular radius (all four distance modes)

- native_support: accepted (honoured in both seed expansion and traversal)
- python_exposure: available (one type per run via split(); wizard RadiusPage offers all five)
- rpst_exposure: accepted via radius=analysis_radius(angular=) with each of walking/steps/angular/axmeter
- defaults (native / python / rpst): unlimited / unticked (no run if none ticked) / unlimited
- evidence: pstalgo/src/analyses/SegmentBetweenness.cpp:271-274,398-401; analyses/networkbetweennessanalysis.py:44; ui/pages/radiuspage.py:51-61; R/core-analyses.R:138; src/pst-graph.cpp:1313-1320
- discrepancy: Angle accumulates per hop. Python never combines radius types with distance modes beyond looping them (networkbetweennessanalysis.py:140-142).
- test_coverage: tests/testthat/test-core-network-analyses.R:244-276 + fixtures/core-network-direct-v3.3.2.R (60 direct-native cases) (4 distances x each radius; angular)
- risk: none; recommendation: preserve

Matrix cell radius=angular x distance in {walking,steps,angular,axmeter}: all 4 accepted natively, in the wizard (radius page is shared) and in rPST; fixture lists 60 direct-native cases, 28 of them betweenness (7 radius sets x 4 distances).

### NB-012  [D]  network_betweenness / axmeter radius (all four distance modes)

- native_support: accepted (honoured in both seed expansion and traversal)
- python_exposure: available (one type per run via split(); wizard RadiusPage offers all five)
- rpst_exposure: accepted via radius=analysis_radius(axmeter=) with each of walking/steps/angular/axmeter
- defaults (native / python / rpst): unlimited / unticked (no run if none ticked) / unlimited
- evidence: pstalgo/src/analyses/SegmentBetweenness.cpp:275-278,386-388,402-405; analyses/networkbetweennessanalysis.py:44; ui/pages/radiuspage.py:51-61; R/core-analyses.R:138; src/pst-graph.cpp:1313-1320
- discrepancy: Uses a different axmeter recurrence than the NI/Reach BFS (half-length weights, SegmentBetweenness.cpp:386-387 vs BFS.cpp:211): values are not comparable across analyses. Python never combines radius types with distance modes beyond looping them (networkbetweennessanalysis.py:140-142).
- test_coverage: tests/testthat/test-core-network-analyses.R:244-276 + fixtures/core-network-direct-v3.3.2.R (60 direct-native cases) (4 distances x each radius; axmeter)
- risk: none; recommendation: preserve

Matrix cell radius=axmeter x distance in {walking,steps,angular,axmeter}: all 4 accepted natively, in the wizard (radius page is shared) and in rPST; fixture lists 60 direct-native cases, 28 of them betweenness (7 radius sets x 4 distances).

### NB-013  [D]  network_betweenness / combined radii

- native_support: accepted (all mask bits tested independently)
- python_exposure: disabled (split)
- rpst_exposure: accepted
- defaults (native / python / rpst): unlimited / n/a / unlimited
- evidence: pstalgo/src/analyses/SegmentBetweenness.cpp:263-282; docs/compatibility/qgis-differences.md:28
- discrepancy: Intentional departure documented.
- test_coverage: tests/testthat/test-core-network-analyses.R:244-276 + fixtures/core-network-direct-v3.3.2.R (60 direct-native cases) (betweenness 'all five' case, all 4 distances)
- risk: none; recommendation: preserve

### NB-014  [D]  network_betweenness / no radius (default)

- native_support: accepted
- python_exposure: no type ticked -> nothing computed (as NR-007)
- rpst_exposure: unrestricted
- defaults (native / python / rpst): unlimited / no-op / unlimited
- evidence: analyses/networkbetweennessanalysis.py:44,75,116-142; R/core-analyses.R:138
- discrepancy: Application quirk; rPST gives pinned-test result.
- test_coverage: tests/testthat/test-core-network-analyses.R:50-67
- risk: none; recommendation: preserve

### NB-015  [F]  network_betweenness / multi-valued radius

- native_support: n/a
- python_exposure: per-type split only
- rpst_exposure: rejected
- defaults (native / python / rpst): n/a / n/a / error
- evidence: R/radius.R:43-55; docs/compatibility/multi-radius.md:§9
- discrepancy: Deferred convenience.
- test_coverage: tests/testthat/test-multi-radius.R
- risk: usability; recommendation: preserve

Executed: error confirmed.

### NB-016  [G]  network_betweenness / weights = none

- native_support: accepted (m_Weights nullptr, no attractions)
- python_exposure: available ('No weight', default ticked)
- rpst_exposure: accepted (NULL, default)
- defaults (native / python / rpst): nullptr / ticked / NULL
- evidence: pstalgo/src/analyses/SegmentBetweenness.cpp:84,735; analyses/networkbetweennessanalysis.py:54-55,155
- discrepancy: None.
- test_coverage: tests/testthat/test-core-network-analyses.R:244-276 + fixtures/core-network-direct-v3.3.2.R (60 direct-native cases)
- risk: none; recommendation: preserve

### NB-017  [E]  network_betweenness / weights = line length

- native_support: accepted (per-segment float array)
- python_exposure: available ('Weigh by segment length', unticked): weights = PSTAGetGraphLineLengths
- rpst_exposure: no dedicated option: pass weights = axial_line_lengths(graph)
- defaults (native / python / rpst): nullptr / unticked / NULL
- evidence: analyses/networkbetweennessanalysis.py:56-57,121-125; pstalgo/src/analyses/SegmentBetweenness.cpp:735; R/graph.R:188
- discrepancy: User must supply the same vector; value equality holds by construction (rPST widens the same native floats). Executed: chain gives 2.25,5.25,6.25,5.25,2.25.
- test_coverage: none found for weights=axial_line_lengths(g) specifically (weights tests use arbitrary vectors)
- risk: correctness (no end-to-end equality test with Python length weighting); recommendation: investigate

Add a test that network_betweenness(g, weights = axial_line_lengths(g)) equals the direct native call with PSTAGetGraphLineLengths output.

### NB-018  [D]  network_betweenness / weights = data column(s)

- native_support: accepted (float per segment; skip origins with !(w>0))
- python_exposure: available ('Weigh by segment data' with several columns -> several runs; name field mandatory but unused)
- rpst_exposure: accepted (one numeric vector per call; finite, float-representable)
- defaults (native / python / rpst): nullptr / unticked / NULL
- evidence: pstalgo/src/analyses/SegmentBetweenness.cpp:207-208,490-565; analyses/networkbetweennessanalysis.py:58-60,126-132; ui/wizards/networkbetweennesswiz.py:118-151 (weight_data_name validated, never read); src/pst-graph.cpp:130-146
- discrepancy: Python: weight_data_name required but unused (UI defect). Native weights can be zero/negative.
- test_coverage: tests/testthat/test-origin-attraction-modes.R:47-89
- risk: none; recommendation: preserve

### NB-019  [D]  network_betweenness / zero / negative weights (skipped origins)

- native_support: accepted; origin skipped, node count and total depth NOT written; raw score still accumulates other origins
- python_exposure: application writes stale/uninitialised N and TD for those rows (buffers reused, zero-skipped rows retain previous values)
- rpst_exposure: accepted; rPST reports NA for node_count/total_depth (and NA Freeman/syntax)
- defaults (native / python / rpst): n/a / stale / NA
- evidence: pstalgo/src/analyses/SegmentBetweenness.cpp:207-208,569-570; analyses/networkbetweennessanalysis.py:105-108,159-160,173-180; R/core-analyses.R:138; src/pst-graph.cpp:1366-1397,1420-1470
- discrepancy: Application defect not copied (documented); rPST NA convention is an intentional policy.
- test_coverage: tests/testthat/test-origin-attraction-modes.R:47-89
- risk: none; recommendation: preserve

Executed: weights=c(0,1,1,1,1) gives NA node_count/total_depth for line 1 only; negative weights likewise; wrong length, NA and non-finite weights rejected with explicit errors.

### NB-020  [C]  network_betweenness / attraction_points (+ optional weights)

- native_support: accepted; each point snaps to its closest line at any distance, weights accumulate per segment (unit weight when m_Weights null)
- python_exposure: available in Attraction Betweenness wizard only (points or polygons -> centroids; no edge sampling UI)
- rpst_exposure: accepted (matrix or sf POINT; weights one per point)
- defaults (native / python / rpst): nullptr / none / NULL
- evidence: pstalgo/src/analyses/SegmentBetweenness.cpp:719-733; analyses/attractionbetweennessanalysis.py:76,95-122; analyses/attractiondistanceanalysis.py:252-266; pstqgis/src/pst/model/model.py:259-273; ui/pages/graphinputpage.py:66-71; R/core-analyses.R:138; src/pst-graph.cpp:85-128
- discrepancy: Application converts polygon destinations to centroids silently (dest_poly_edge_point_interval_enabled is never set by the Attraction Betweenness wizard); rPST accepts points only.
- test_coverage: tests/testthat/test-origin-attraction-modes.R:13-130 + fixtures/reach-betweenness-direct-v3.3.2.R (sampled every 40th case)
- risk: correctness (far points snap to nearest line regardless of distance); recommendation: preserve

Executed: attraction_points with weights c(2,3) concentrates scores on the two nearest lines; lines holding no attraction have weight 0 and are skipped (NA diagnostics), as in the unit-weight run.

### NB-021  [G]  network_betweenness / normalization = none / standard

- native_support: PSTAStandardNormalize(scores, count)
- python_exposure: available (none default ticked, standard)
- rpst_exposure: accepted ('none' default, 'standard')
- defaults (native / python / rpst): n/a / none / none
- evidence: pstalgo/src/analyses/Common.cpp:63-91; analyses/networkbetweennessanalysis.py:106,166-171; src/pst-graph.cpp:1390-1392
- discrepancy: None: both feed the raw betweenness array of the same run, over all rows.
- test_coverage: tests/testthat/test-origin-attraction-modes.R:13-130 + fixtures/reach-betweenness-direct-v3.3.2.R (sampled every 40th case)
- risk: none; recommendation: preserve

### NB-022  [D]  network_betweenness / normalization = freeman (PSTABetweennessNormalize)

- native_support: accepted (in_values, node_counts incl. origin)
- python_exposure: absent at v3.3.2; PRESENT in v3.1.3-v3.2.1 network betweenness (BetweennessNormalize(scores, total_counts)); removed by 1c166e8
- rpst_exposure: accepted (compacted over written rows; scores and node counts)
- defaults (native / python / rpst): n/a / n/a (not offered) / none
- evidence: pstalgo/src/analyses/SegmentBetweenness.cpp:689-699; git show 1c166e8^:pstqgis/src/pst/analyses/networkbetweennessanalysis.py (pstalgo.BetweennessNormalize(scores, total_counts, scores.size(), scores_norm)); src/pst-graph.cpp:1396-1420; docs/pst-coverage.md:96
- discrepancy: Not in the pinned application, but the removed historical call used exactly the buffers rPST uses (scores, node counts). rPST skips unwritten rows rather than feeding sentinels. Engine-only at the pin.
- test_coverage: tests/testthat/test-origin-attraction-modes.R:13-130 + fixtures/reach-betweenness-direct-v3.3.2.R (sampled every 40th case); test-core-network-analyses.R:103-122
- risk: none; recommendation: preserve

Restriction history: 1c166e8 (2021-03-02, martin-fitger) 'New analysis "Angular Betweenness" and distinction between road network types in "Create Segment Map"' (first in tag v3.2.2) removed dist_angular, Turner (norm_normalization) and NACH (norm_syntax) from the Network Betweenness wizard and analysis; the original a808c54 (2019-11-18, tags v3.1.3..) offered them. The call trace from the historical commit (S level) corroborates the buffer mapping required by the internal engineering rules, section 3. Engine behaviour: N>2 -> value / (0.5*(N-1)*(N-2)), else raw value (SegmentBetweenness.cpp:695-697).

### NB-023  [D]  network_betweenness / normalization = syntax (PSTABetweennessSyntaxNormalize)

- native_support: accepted (log10(v+1)/log10(2+TD))
- python_exposure: absent at v3.3.2; present in v3.1.3-v3.2.1 as BetweennessSyntaxNormalize(scores, total_depths)
- rpst_exposure: accepted (scores, total_depths of the same run)
- defaults (native / python / rpst): n/a / n/a / none
- evidence: pstalgo/src/analyses/SegmentBetweenness.cpp:701-707,570; git show 1c166e8^:pstqgis/src/pst/analyses/networkbetweennessanalysis.py (BetweennessSyntaxNormalize(scores, total_depths)); src/pst-graph.cpp:1396-1420
- discrepancy: Matches historical trace. For weighted/attraction runs total_depth is still the unweighted depth (engine), no application trace exists: engine-only, documented in pst-coverage.md:96.
- test_coverage: tests/testthat/test-origin-attraction-modes.R:13-130 + fixtures/reach-betweenness-direct-v3.3.2.R (sampled every 40th case)
- risk: correctness (syntax normalisation for weighted runs has no application precedent); recommendation: preserve

Angular depths are converted to syntax angle units by the engine (SegmentBetweenness.cpp:570); executed freeman values on the unit chain 0, 0.5, 0.667, 0.5, 0 and syntax 0, 0.631, 0.774, 0.631, 0 (finite, ordered).

### NB-024  [F]  network_betweenness / normalization vector / combination

- native_support: n/a
- python_exposure: several normalisations per run via norm_none+norm_standard
- rpst_exposure: rejected (single name)
- defaults (native / python / rpst): n/a / none / none
- evidence: analyses/networkbetweennessanalysis.py:164-171; R/core-analyses.R:138
- discrepancy: Convenience only.
- test_coverage: none found
- risk: usability; recommendation: preserve

Executed: c('none','standard') rejected.

### NB-025  [C]  network_betweenness / output node_count / total_depth / mean_depth

- native_support: written when pointers non-null; N includes origin; angular TD in syntax units
- python_exposure: N,TD,MD checkboxes (default True), only for the FIRST weight mode; MD = TD/(N-1)
- rpst_exposure: node_count, total_depth always; no mean depth
- defaults (native / python / rpst): not written / True / always
- evidence: pstalgo/src/analyses/SegmentBetweenness.cpp:569-570; analyses/networkbetweennessanalysis.py:110-112,134-138,172-180
- discrepancy: Python-only post-processing (C) for MD; rPST returns diagnostics for every call.
- test_coverage: tests/testthat/test-origin-attraction-modes.R:13-46
- risk: none; recommendation: preserve

### NB-026  [G]  network_betweenness / Attraction Betweenness outputs (no N/TD)

- native_support: N/TD optional
- python_exposure: raw and standard columns only
- rpst_exposure: node_count and total_depth always
- defaults (native / python / rpst): n/a / n/a / always
- evidence: analyses/attractionbetweennessanalysis.py:115-131
- discrepancy: Superset.
- test_coverage: tests/testthat/test-origin-attraction-modes.R:13-130 + fixtures/reach-betweenness-direct-v3.3.2.R (sampled every 40th case)
- risk: none; recommendation: preserve

### NB-027  [E]  network_betweenness / combination: weights x normalisation x distance x radius

- native_support: accepted
- python_exposure: Python: length/data weights x none/standard x 3 (NB) or 4 (AB) distances x per-type radii
- rpst_exposure: accepted: any weights/attractions x 4 normalisations x 4 distances x any radius set
- defaults (native / python / rpst): n/a / n/a / n/a
- evidence: pstalgo/src/analyses/SegmentBetweenness.cpp:204-571,689-743; tests/testthat/test-origin-attraction-modes.R:13-46
- discrepancy: Direct-native equality is established on a sampled subset only (every 40th case of the fixture).
- test_coverage: tests/testthat/test-origin-attraction-modes.R:13-130 + fixtures/reach-betweenness-direct-v3.3.2.R (sampled every 40th case)
- risk: correctness (unsampled combinations); recommendation: investigate

Standard normalisation uses all rows including skipped ones (raw 0.0); Freeman/syntax skip them. The fixture sampling is controlled by rpst_cases(every = 40L). Recommend running the full fixture at least once per release.

### NB-028  [G]  network_betweenness / struct fields left at defaults

- native_support: default member initialisers; m_Version=1
- python_exposure: Python sets all (version, distance, radius, weights, points, callbacks, outputs)
- rpst_exposure: desc{}; sets graph, radius, distance, weights, points, count, three outputs; progress null
- defaults (native / python / rpst): Steps / nullptr / set / set
- evidence: pstalgo/include/pstalgo/analyses/SegmentBetweenness.h:140-171; pstalgo/python/pstalgo/segmentbetweenness.py:61-88; src/pst-graph.cpp:1370-1385
- discrepancy: m_AttractionPointCount is set to points.count (0 when NULL) with nullptr coordinates; correct.
- test_coverage: tests/testthat/test-origin-attraction-modes.R:13-130 + fixtures/reach-betweenness-direct-v3.3.2.R (sampled every 40th case)
- risk: none; recommendation: preserve

### NB-029  [G]  network_betweenness / threads / cancellation / determinism

- native_support: hardware_concurrency workers; per-worker double accumulators merged by worker order; no cancel (TODO)
- python_exposure: n/a
- rpst_exposure: worker count substitution RPST_NUM_THREADS
- defaults (native / python / rpst): hw / hw / hw
- evidence: pstalgo/src/analyses/SegmentBetweenness.cpp:160-167,582-590,666-673; docs/compatibility/core-network-analyses.md (Threading)
- discrepancy: Result may differ at float ulp with thread count (double accumulation order); documented substitution only.
- test_coverage: tests/testthat/test-workers.R
- risk: none; recommendation: preserve

Not executed.

### NB-030  [D]  network_betweenness / line-count bound for angular

- native_support: angular allocates 2 x lines in int
- python_exposure: n/a
- rpst_exposure: rejected above INT_MAX/2
- defaults (native / python / rpst): n/a / n/a / error
- evidence: pstalgo/src/analyses/SegmentBetweenness.cpp:149; src/pst-graph.cpp:1325-1326
- discrepancy: Defensive; correct.
- test_coverage: none found
- risk: safety; recommendation: preserve

### NB-031  [D]  network_betweenness / output_file / spatial_output_file

- native_support: n/a
- python_exposure: absent
- rpst_exposure: accepted
- defaults (native / python / rpst): n/a / n/a / NULL
- evidence: R/core-analyses.R:138-165
- discrepancy: rPST extension.
- test_coverage: tests/testthat/test-result-masked-analyses.R
- risk: none; recommendation: preserve

Nullable columns for skipped weighted origins.

### AX-001  [D]  axial_graph / x (line coordinates, four columns x1 y1 x2 y2)

- native_support: accepted (m_Lines null -> consecutive coordinate pairs)
- python_exposure: available: layer lines; exactly 2 vertices; multipart with !=1 part and >2 vertices raise; non-line and null geometry silently skipped
- rpst_exposure: accepted: numeric matrix, finite, >=1 row; sf LINESTRING (2 vertices) or file path
- defaults (native / python / rpst): n/a / n/a / n/a
- evidence: pstalgo/src/analyses/CreateGraph.cpp:98-102; pstqgis/src/pst/model/model.py:283-309; analyses/utils.py:130-140; R/graph.R:111-130; src/pst-graph.cpp:407-450
- discrepancy: rPST rejects invalid input explicitly where the plugin skips (non-line features) or raises (polylines).
- test_coverage: tests/testthat/test-axial-inputs.R:23-200; test-network-construction.R:12-36; test-pst-graph.R
- risk: none; recommendation: preserve

Executed: 3-column, 0-row, NA, data.frame and vector inputs are all rejected with explicit messages; integer matrices accepted.

### AX-002  [D]  axial_graph / line_indices (indexed endpoints)

- native_support: accepted (m_Lines pairs; used by every pinned upstream test)
- python_exposure: absent (Python always passes line_indices=None)
- rpst_exposure: accepted: whole one-based indices within x
- defaults (native / python / rpst): nullptr / None / NULL
- evidence: pstalgo/src/analyses/CreateGraph.cpp:88-95; pstalgo/python/pstalgo/creategraph.py:82-91; analyses/utils.py:170-177; pstalgo/test/tests/testsegmentbetweenness.py:48-58; R/graph.R:111; src/pst-graph.cpp:296-330,408-420
- discrepancy: Native-supported option the application never uses; used by upstream tests, so the path is verified.
- test_coverage: tests/testthat/test-axial-inputs.R:23-200; test-network-construction.R:12-36; test-pst-graph.R
- risk: none; recommendation: preserve

Unused coordinates still affect the world origin (bounding box of all supplied coordinates, CreateGraph.cpp:80-83); rPST reproduces this (pst-graph.cpp:300-309). Executed: out-of-range, 0, fractional, NA indices rejected; sharing a vertex gives an endpoint join crossing.

### AX-003  [G]  axial_graph / unlinks (coordinates)

- native_support: accepted; each unlink removes the NEAREST crossing at any distance (no tolerance); only crossings where the lower-index line passes through its interior are eligible
- python_exposure: available (checkbox 'Unlink points', default off; non-point geometries -> centroid; error if table yields zero points)
- rpst_exposure: accepted (zero rows allowed)
- defaults (native / python / rpst): nullptr / off / NULL
- evidence: pstalgo/src/graph/AxialGraph.cpp:255-285 (275: only line0 tested for endpoint coincidence); pstalgo/src/analyses/CreateGraph.cpp:105-109; analyses/utils.py:159-166; ui/pages/networkinputpage.py:75-82; R/graph.R:79-81
- discrepancy: Engine semantics preserved and documented in roxygen; same behaviour in plugin.
- test_coverage: tests/testthat/test-axial-inputs.R:23-200; test-network-construction.R:12-36; test-pst-graph.R; test-network-construction.R
- risk: correctness (silent: far unlink still removes a crossing); recommendation: preserve

Executed: unlink at (1000,1000) on a single crossing removes it (n_crossings 1 -> 0); T-junction with the through-line first: unlink removes the crossing, with the stem first: crossing remains (order-dependent); an endpoint join cannot be unlinked; duplicated unlink on one crossing is harmless.

### AX-004  [D]  axial_graph / points (retained graph points)

- native_support: accepted; connects points to network; adds to bbox
- python_exposure: NOT passed by Network Integration, Reach, Network Betweenness, Attraction Betweenness (point_table None)
- rpst_exposure: accepted
- defaults (native / python / rpst): nullptr / None / NULL
- evidence: pstalgo/src/graph/AxialGraph.cpp:85-89,104-109; analyses/networkintegrationanalysis.py:68-75; analyses/reachanalysis.py:67-74; R/graph.R:82-85
- discrepancy: Irrelevant to NI/Reach/Betweenness results (executed: identical outputs with/without far-off points); used by attraction/OD analyses (other agents).
- test_coverage: tests/testthat/test-axial-inputs.R:23-200; test-network-construction.R:12-36; test-pst-graph.R
- risk: performance (point connection cost, bbox growth) ; recommendation: preserve

Points enlarge the bounding box (AxialGraph.cpp:85-89) hence the SphereTree extents (:96-99) but results were identical in a small check (Reach walking, point-origin Reach, Betweenness walking).

### AX-005  [D]  axial_graph / points_per_polygon (polygon corner counts)

- native_support: accepted (regions -> generated edge points, one group per polygon)
- python_exposure: used only by Attraction Reach/Distance (BuildAxialGraph poly_edge_point_interval>0); outer ring only
- rpst_exposure: accepted: non-negative whole counts incl. NaN separator rows summing to nrow(points); zero counts keep empty groups
- defaults (native / python / rpst): nullptr / None / NULL
- evidence: pstalgo/src/analyses/CreateGraph.cpp:29-69,114-126; analyses/utils.py:145-157; pstqgis/src/pst/model/model.py:340-368; src/pst-graph.cpp:260-288; R/graph.R:86-88
- discrepancy: Holes: rPST samples all rings (documented in qgis-differences.md). Not used by NI/Reach/Betweenness.
- test_coverage: tests/testthat/test-axial-inputs.R:23-200; test-network-construction.R:12-36; test-pst-graph.R (polygon layouts)
- risk: none; recommendation: preserve

Executed: separators and holes produce 11 points for the test ring; a zero count retains an empty group (n_point_groups 2).

### AX-006  [D]  axial_graph / polygon_point_interval

- native_support: accepted but DANGEROUS when 0: loop for(;t<len;t+=interval) never terminates (memory growth)
- python_exposure: Python passes 0 meaning 'no polygons'; >0 only for region inputs
- rpst_exposure: required >0 finite float with polygons; forbidden without; overflow/underflow and point-count bounds checked
- defaults (native / python / rpst): 0 (struct default) / 0 (default arg) / NULL
- evidence: pstalgo/include/pstalgo/analyses/CreateGraph.h:70; pstalgo/src/geometry/RegionPoints.cpp:45,59; analyses/utils.py:103,145; pstalgo/python/pstalgo/creategraph.py:82,109; src/pst-graph.cpp:260-288,356-380
- discrepancy: rPST guard prevents a native hang that neither the native API nor the Python wrapper checks.
- test_coverage: tests/testthat/test-axial-inputs.R:23-200; test-network-construction.R:12-36; test-pst-graph.R (tests of bounded sampling)
- risk: safety; recommendation: preserve

Executed: 0, -1, NA, Inf, 1e-50, vector and string intervals are rejected; interval without polygons rejected; a 2e6-long edge at 1e-3 rejected by the signed-count bound.

### AX-007  [D]  axial_graph / coordinate validity, extent and float narrowing

- native_support: accepted without checks (float local coordinates around bbox centre)
- python_exposure: no checks
- rpst_exposure: finite required; local-float and squared-distance overflow rejected before native call
- defaults (native / python / rpst): n/a / n/a / error
- evidence: pstalgo/src/analyses/CreateGraph.cpp:80-83,92-93; R/graph.R:12-19; src/pst-graph.cpp:296-350
- discrepancy: Intentional hardening (the internal engineering rules, section 9).
- test_coverage: tests/testthat/test-axial-inputs.R:23-200; test-network-construction.R:12-36; test-pst-graph.R
- risk: safety; recommendation: preserve

Executed: 1e30 and 1e19 extents rejected; NA rejected.

### AX-008  [G]  axial_graph / minimum crossing line length (0.01) and degenerate lines

- native_support: lines shorter than MIN_LINE_LENGTH (0.01 local units) never form crossings; zero-length lines accepted
- python_exposure: no check
- rpst_exposure: no check (documented in axial-inputs-junctions.md:35)
- defaults (native / python / rpst): n/a / n/a / n/a
- evidence: pstalgo/src/graph/AxialGraph.cpp:33,223-224,239-240; docs/compatibility/axial-inputs-junctions.md:35
- discrepancy: Native-algorithmic limit: unit-dependent (e.g. lines in degrees or kilometres below 0.01 never cross).
- test_coverage: none found
- risk: correctness (silent unit dependence); recommendation: preserve

Executed: a 0.005-long line crossing a longer one yields 0 crossings; at 0.02 it yields 1. Zero-length line accepted and isolated.

### AX-009  [D]  axial_graph / PSTACreateGraph descriptor validation

- native_support: no version check (m_Version ignored), no count checks, 0 returned only if polygon counts mismatch
- python_exposure: no checks
- rpst_exposure: validated in R and C++ before the call
- defaults (native / python / rpst): n/a / n/a / n/a
- evidence: pstalgo/src/analyses/CreateGraph.cpp:75-149 (no VerifyStructVersion); src/pst-graph.cpp:406-450
- discrepancy: Hardening; no discrepancy of behaviour on valid input.
- test_coverage: tests/testthat/test-axial-inputs.R:23-200; test-network-construction.R:12-36; test-pst-graph.R
- risk: safety; recommendation: preserve

### AX-010  [D]  axial_graph / graph info (point groups)

- native_support: PSTAGetGraphInfo hardcodes m_PointGroupCount = 0
- python_exposure: used for crossing count only
- rpst_exposure: rPST reads the real count via CAxialGraph::getPointGroupCount
- defaults (native / python / rpst): 0 / n/a / real
- evidence: pstalgo/src/analyses/CreateGraph.cpp:157-173 (170); pstalgo/include/pstalgo/graph/AxialGraph.h:125; src/pst-graph.cpp:529-545
- discrepancy: rPST bypasses the exported info function using the vendored class header: a deliberate workaround of an engine omission.
- test_coverage: tests/testthat/test-axial-inputs.R
- risk: none; recommendation: preserve

Relies on the vendored class layout matching the compiled engine; both come from the same pinned source.

### AX-011  [G]  axial_graph / axial_line_lengths / axial_crossing_coords (inspection)

- native_support: PSTAGetGraphLineLengths / PSTAGetGraphCrossingCoords (count query with null pointer, size check)
- python_exposure: GetGraphLineLengths used as betweenness length weights; crossing count for junction output
- rpst_exposure: exposed; lengths widened float->double; crossings as native local floats converted to world
- defaults (native / python / rpst): n/a / n/a / n/a
- evidence: pstalgo/src/analyses/CreateGraph.cpp:175-211; analyses/networkbetweennessanalysis.py:125; analyses/networkintegrationanalysis.py:84; src/pst-graph.cpp:~700-730; R/graph.R:188-200
- discrepancy: None.
- test_coverage: tests/testthat/test-axial-inputs.R:23-200; test-network-construction.R:12-36; test-pst-graph.R
- risk: none; recommendation: preserve

Executed: 2 crossing lines give lengths 2,2 and crossing (1,0).

### AX-012  [D]  axial_graph / file path / sf inputs

- native_support: n/a (engine only sees arrays)
- python_exposure: absent
- rpst_exposure: accepted (GeoParquet/FlatGeobuf paths, sf LINESTRING/POINT/POLYGON); geographic CRS rejected
- defaults (native / python / rpst): n/a / n/a / n/a
- evidence: R/graph.R:30-63,113-120
- discrepancy: rPST I/O extension; the plugin reads QGIS layers.
- test_coverage: tests/testthat/test-axial-file-input.R; test-sf-graphs.R
- risk: none; recommendation: preserve

Outside the native question; listed for completeness.

### AX-013  [G]  axial_graph / combination: unlinks x NI junction output x points

- native_support: unlinks remove pair records, so crossing count, nLines and junction scores change; points do not
- python_exposure: unlinks -> crossing list for junctions
- rpst_exposure: accepted
- defaults (native / python / rpst): n/a / n/a / n/a
- evidence: pstalgo/src/graph/AxialGraph.cpp:255-295; pstalgo/src/analyses/NetworkIntegration.cpp:160-189
- discrepancy: Junction counts follow unlink handling; no interplay with points.
- test_coverage: tests/testthat/test-axial-inputs.R:23-200; test-network-construction.R:12-36; test-pst-graph.R; test-axial-inputs.R:49-93
- risk: correctness; recommendation: preserve

Executed: unlink at the single crossing reduces n_crossings 1 -> 0 and thus removes the junction row.

### AX-014  [G]  axial_graph / combination: indexed lines x unlinks eligibility

- native_support: pair order is by line index; eligibility rule uses the lower-index line
- python_exposure: n/a
- rpst_exposure: line_indices preserve user order, so the same drawing can be unlinkable or not depending on row order
- defaults (native / python / rpst): n/a / n/a / n/a
- evidence: pstalgo/src/graph/AxialGraph.cpp:206-217,273-278; R/graph.R:79-81
- discrepancy: Documented in roxygen ('first line of the pair').
- test_coverage: tests/testthat/test-network-construction.R
- risk: correctness; recommendation: preserve

See AX-003 execution.

### AX-015  [D]  axial_graph / pst_graph handle lifetime and ownership

- native_support: PSTAFreeGraph on delete
- python_exposure: FreeGraph in finally
- rpst_exposure: external pointer finalizer; copy shares ownership; no persistence
- defaults (native / python / rpst): n/a / n/a / n/a
- evidence: pstalgo/src/analyses/CreateGraph.cpp:151-155; analyses/utils.py:178-182; src/pst-graph.cpp:410-445,547-560
- discrepancy: rPST adds explicit lifetime tests.
- test_coverage: tests/testthat/test-axial-inputs.R:161-200
- risk: safety; recommendation: preserve

## 8. What was executed versus only read

Executed (fresh `Rscript` processes, `ulimit -v 3500000`, `timeout 60`, graphs of at most 6 lines): formals/defaults of the six functions; Network Integration with every single radius type, a combined radius, junction output, invalid steps values; Reach with straight/combined radii, point origins (valid, far, NA, wrong shape); Betweenness with all four distances, invalid distances/normalisations, weights (zero, negative, wrong length, NA), attraction points with/without weights, Freeman/syntax/standard values, axmeter and walking radii; `axial_graph` with indexed lines, unlinks (far, duplicate, endpoint, T-junction orders), points, polygons (intervals 0, negative, NA, Inf, tiny, vector; separators; zero counts; huge ring), short lines, invalid inputs. Scripts and logs: `scratchpad/u1/{a,b,c,d}.R`, `{a,b}.out`. Everything else (native source, Python wrapper, plugin code, git history, docs, test inventory) was only read.

## 9. Uncertainties

- `1c166e8` and `5f3f70f` give no rationale; any reading of intent is inference. The statement that Angular Betweenness took over angular centrality is based on adjacency in the same commit only.
- The Freeman/syntax mapping is corroborated by the removed historical call (v3.1.3-v3.2.1), not by the pinned plugin; for weighted/attraction runs there is no application trace at any revision (engine-only).
- Direct-native equality for betweenness with weights/attractions is verified on a sampled subset of the fixture (every 40th case, `test-origin-attraction-modes.R:17`); the full fixture was not run by me.
- Float-ulp dependence on worker count (NB-029) was reasoned from source, not executed.
- The walking-radius cost for NI/Reach (NI-004, NR-003) is deliberately not assessed (W owns it); the E classification there reflects missing evidence, not a demonstrated fault.
- Python behaviour (null/zero weights leaving stale buffers, unzeroed junction buffer) is derived from code reading (E-level of the plugin logic was not run outside QGIS here).
