# U3 audit: point/attraction/OD analyses, network construction, isovist, raster

Scope: attraction_reach (AR), attraction_distance (AD), od_betweenness (OD), create_junctions / create_segment_map (NC), isovist_context / isovist / isovist_context_free (IS), compare_line_results / raster_data / raster_to_polygons / raster_free (RS), result-file and spatial-output options (IO).
Upstream pinned at 63df80a (v3.3.2), read-only clone. rPST branch audit/pst-interface-parity. Companion CSV: U3-points-misc.csv (one row per row_id below).

## Method
Read QGIS wizards/analyses, ctypes wrappers, native headers and implementations, rPST R and C++ bridge code; verified docs/compatibility/{attractions,od-betweenness,network-construction,qgis-differences}.md against source before reuse. Ran small bounded synthetic R checks (fresh process, `ulimit -v 3500000; timeout 60`, installed rPST, graphs of <= 400 lines). Scripts are in scratchpad/u3/*.R. No repo or upstream modification.

Restriction kinds used: UI-only, Python-validation, native-API-validation, native-algorithmic-limit, documented-recommendation.

## Classification counts

- A: 0
- B: 1
- C: 1
- D: 24
- E: 6
- F: 1
- G: 58
- total rows: 91

## Summary matrix (distance / radius support by layer)

| Analysis | Native | QGIS UI/Python | rPST |
|---|---|---|---|
| attraction_reach | all 6 distance types x all radius types; CPSTBFS for the BFS path; straight+line-origin fast path | weight mode exposes one metric per Radii | all accepted (executed 6x7 matrix) |
| attraction_distance | walking, steps, angular (+weights) only via BuildDirectedMultiDistanceGraph (DirectedMultiDistanceGraph.cpp:114-117); straight/axmeter throw -> false; straight-only fast path leaves point-group outputs unwritten | wizard limits | straight radius with network distance accepted and silently ignored (AD-008, B); axmeter and straight-distance mixes rejected |
| od_betweenness | walking and angular distance; axmeter radius not tested by IsWithinRadius | wizard limits | axmeter rejected; steps/straight/walking/angular radii accepted |
| create_junctions | LineCount0 == 0 returns true without result | QGIS passes only line sets | empty first layer rejected |
| create_segment_map | unlinks only for axial/segment (CreateSegmentMap.cpp:189) | QGIS forces extrude = trim_snap | wrapper default extrude 0 (documented departure) |
| isovist | <= 256 groups, < 2^24 objects/group, ring-orientation-dependent edge test | perimeter fixed 64; wizard fov 360/dir 0 | perimeter >= 3, fov 0..360, direction any finite |
| raster / compare | NORMALIZED hard-coded in QGIS; native supports relative percent | UI removed (c0fb690) | both modes exposed (D) |

## CPSTBFS users and the multi-metric blow-up
CPSTBFS (pstalgo/src/BFS.cpp, updateCheckPoint at 348-400) tracks walking, turns, angle and axmeter checkpoints. When a new state improves one tracked metric but worsens another, it returns true without updating the checkpoint, so states are re-queued; with one metric effectively unbounded the state count explodes.

| Native analysis | Uses CPSTBFS | Distance settings |
|---|---|---|
| Reach | yes (Reach.cpp:65) | DIST_NONE with any radius mix |
| NetworkIntegration | yes (NetworkIntegration.cpp:69) | DIST_LINES plus any other radius (agent W) |
| AttractionReach (BFS path, AttractionReach.cpp:215) | yes | any distance type with any radii (except straight-only line-origin fast path) |
| AttractionDistance | no (Dijkstra, ShortestPathTraversal.cpp) | n/a |
| OD Betweenness | no (priority queue on primary cost) | n/a |
| SegmentGroupIntegration | no (BFSTraversal.h) | n/a |

Executed (attraction_reach, 150 random axial lines of 300 m in a 1000 m square, seed 7, walking radius 800): distance=steps + walking radius -> bad_alloc after ~28 s; distance=angular + walking radius -> 60 s timeout (bad_alloc at n=200); distance=axmeter + axmeter radius 4000 -> bad_alloc ~25 s; steps + straight 600 + walking 800 -> bad_alloc ~16 s. Fast (~0.01 s): none/walking distance with walking radius, straight distance with walking radius, walking distance with steps(6)/angular(400)/straight radius. AttractionDistance and OD on 400 lines with the same mixed radii: <= 0.21 s. Rule: blow-up when a second tracked metric is effectively unbounded. See AR-005, AR-008.

## Restriction history
- SUPPORTED_DISTANCE_TYPES_MASK in AttractionDistance: present since initial import 866cf3a (2019-11-20); no explanation found.
- Attraction Distance line weights: 85d9e1c (2025-03-07); point-edge weight 905d588 (2025-03-19); destination indices c1dde9f (2025-06-12).
- Isovist perimeter-resolution UI control commented out: 25c96d4 (2023-11-08) "Batching feature"; no explanation found.
- Compare results relative-percent UI removed: c0fb690 (2024-10-03).
- Other restrictions: no explanation found.

## Key findings

- AD-008 [B] radius straight with network distance (walking/steps/angular/weights): Native-algorithmic limit: the option is ignored. rPST exposes it without warning, while rPST REJECTS the analogous ignored axmeter limit in OD Betweenness (docs/compatibility/od-betweenness.md:89-94). Inconsistent policy; a user supplying a straight cap gets an unrestricted result.
- AR-005 [E] distance = axmeter (radius axmeter): QGIS-reachable. EXECUTED: 150 random 300 m axial lines, distance=axmeter, radius axmeter=4000 -> std::bad_alloc after 25 s under a 3.5 GB cap, while the same network with distance=none/walking radius=800 runs in 0.01 s. See BFS section of the MD (blow-up family). rPST surfaces the failure as an R error (worker exception propagated, PATCHES 0005) rather than crashing.
- AR-007 [E] default distance ('steps' in rPST vs UNDEFINED in QGIS unweighted): rPST follows the native struct / ctypes wrapper default (steps), not the application's unweighted behaviour (UNDEFINED). With constant decay and a walking, angular or straight+walking radius the default therefore adds a turns metric that the application never tracks: EXECUTED attraction_reach(g, pts, radius=analysis_radius(walking=800)) with the DEFAULT distance on 150 random axial lines -> std::bad_alloc after ~28 s; distance='none' -> 0.01 s with identical reached sets on small cases. Default call plus a single non-steps radius is the most likely user path to the blow-up.
- AR-008 [E] distance != radius metric (e.g. steps/angular distance with walking radius; walking distance with angular radius): Native-valid, never exercised by the application, so no application oracle exists. EXECUTED on 150 random lines (walking radius 800 covering the network): steps+walking -> bad_alloc (28 s); angular+walking -> killed by 60 s timeout (n=150) / bad_alloc (n=200); steps+(straight 600 + walking 800) -> bad_alloc (16 s); walking+steps(6), walking+angular(400), steps+angular, steps+straight all 0.00-0.01 s (second metric bounded). Rule: runtime explodes when one tracked metric is effectively unbounded while another is tracked (updateCheckPoint returns 'improved' without updating the checkpoint when the new state is better in one metric and worse in another, BFS.cpp:387-397).
- AR-016 [E] decay scale when radius of the distance metric is absent/mismatched: EXECUTED: decay power/curve, distance='walking' with only a steps radius, or no radius, or distance='none' -> weight 1 everywhere (x/inf = 0). Silent absence of decay. divide is unaffected (does not use the radius). Documented only as 'Power/curve use the selected distance's radius for scaling' (R/attractions.R:77).
- IS-004 [E] polygon ring orientation: Obstacle visibility depends on winding (back-facing edges are the ones kept). rPST documents 'PST expects Cartesian clockwise rings' but neither validates nor warns; a CCW polygon silently gives a different isovist. the internal engineering rules forbids reordering, so a warning/validation option is the only safe mitigation.
- RS-007 [E] raster dimensions and memory: Only an arithmetic-overflow guard exists; a request just under 4 GiB (x2 for relative_percent, plus blur buffers) would be attempted. No tests at that scale.
- NC-013 [F] cyclic detail reduction: Approved conservative policy: narrower `count<=2` guard evaluated and declined. rPST rejects some inputs the application would process (to a degenerate output). Classified F because the over-rejection of valid native results is explicit, though approved.

## Per-row evidence

### AR-001 (G) attraction_reach / graph (HPSTAGraph family)

- native (PSTAAttractionReach): accepted (casts to CAxialGraph without a tag check); QGIS (AttractionReachAnalysis + AttractionReachWiz): available (BuildAxialGraph from lines); rPST: accepted (exact-tagged axial pst_graph only)
- defaults native/python/rPST: none (required) / required / required
- evidence: pstalgo/src/analyses/AttractionReach.cpp:45; pstqgis/src/pst/analyses/attractionreachanalysis.py:124-132; R/attractions.R:99-101; src/pst-graph.cpp:2493-2500
- finding: rPST checks the exact HPSTAGraph tag; native has no check. Matches the internal engineering rules, section 5.
- tests: test-attractions.R; fixtures/attractions-direct-v3.3.2.R (537 direct cases per docs/compatibility/attractions.md:99-104); risk: safety (tag check prevents mis-cast); recommendation: preserve

### AR-002 (G) attraction_reach / origin = lines|junctions|points|point_groups

- native (PSTAAttractionReach): accepted (all four; switch at AttractionReach.cpp:186-201, output count 219); QGIS (AttractionReachAnalysis + AttractionReachWiz): available (points/lines/junctions; point_groups only when origin layer is polygons AND an edge interval is set, attractiondistanceanalysis.py:240-250); rPST: accepted (all four, exact names)
- defaults native/python/rPST: Lines (header AttractionReach.h:66) / lines (UI); points when origin layer is a point layer / lines
- evidence: pstalgo/src/analyses/AttractionReach.cpp:184-201,219-224; pstalgo/include/pstalgo/analyses/AttractionReach.h:66; pstqgis/src/pst/analyses/attractiondistanceanalysis.py:240-250; R/attractions.R:102; src/pst-graph.cpp:2468-2477
- finding: Origin sets match native. QGIS selects point_groups through polygon origin layers; rPST selects it explicitly (graph must have retained point groups). QGIS junction output builds a point layer with crossing coordinates (attractionreachanalysis.py:216-224); rPST returns origin_id + score only, coordinates come from axial_crossing_coords() (R/graph.R:194).
- tests: test-attractions.R; fixtures/attractions-direct-v3.3.2.R (537 direct cases per docs/compatibility/attractions.md:99-104); risk: none; recommendation: preserve

### AR-003 (G) attraction_reach / distance = straight (with straight-only radius or none)

- native (PSTAAttractionReach): accepted (finite-radius line origins use getLinesFromPoint fast path AttractionReach.cpp:465-514; no BFS); QGIS (AttractionReachAnalysis + AttractionReachWiz): available (weight mode, Radii(straight=..), attractionreachanalysis.py:54-55); rPST: accepted
- defaults native/python/rPST: Steps (AttractionReach.h:69) / STEPS (wrapper attractionreach.py:110); UI weight mode: none checked by default (attractionreachwiz.py:55) / steps
- evidence: pstalgo/src/analyses/AttractionReach.cpp:465-514; pstqgis/src/pst/analyses/attractionreachanalysis.py:54-55; R/attractions.R:104
- finding: Fast path matches QGIS weight-mode use. Quirk: for TARGET_LINES with a finite straight radius the weight is evaluated at the RADIUS not the distance (AttractionReach.cpp:497); without radius it uses the true nearest-line distance (510). Preserved and documented (docs/compatibility/attractions.md:49-52).
- tests: test-attractions.R; fixtures/attractions-direct-v3.3.2.R (537 direct cases per docs/compatibility/attractions.md:99-104) (fast and BFS branches); risk: correctness (see AR-015); recommendation: preserve

### AR-004 (G) attraction_reach / distance = walking|steps|angular with a radius of the SAME metric

- native (PSTAAttractionReach): accepted (single-metric BFS); QGIS (AttractionReachAnalysis + AttractionReachWiz): available (weight mode, one distance mode per Radii, attractionreachanalysis.py:56-61); rPST: accepted
- defaults native/python/rPST: Steps / as QGIS weight mode / steps
- evidence: pstalgo/src/analyses/AttractionReach.cpp:215; pstalgo/src/BFS.cpp:353-385; pstqgis/src/pst/analyses/attractionreachanalysis.py:56-61
- finding: The only combination QGIS exercises with decay; single tracked metric, cheap.
- tests: test-attractions.R; fixtures/attractions-direct-v3.3.2.R (537 direct cases per docs/compatibility/attractions.md:99-104); risk: none; recommendation: preserve

### AR-005 (E) attraction_reach / distance = axmeter (radius axmeter)

- native (PSTAAttractionReach): accepted but intrinsically multi-metric (BFS tracks walking+turns+axmeter whenever DIST_AXMETER, BFS.cpp:353-385); QGIS (AttractionReachAnalysis + AttractionReachWiz): available (weight mode, attractionreachanalysis.py:62-63; default 2000 steps*m attractionreachwiz.py:59); rPST: accepted
- defaults native/python/rPST: Steps / UI default radius 2000 / steps
- evidence: pstalgo/src/BFS.cpp:353-385; pstalgo/src/analyses/AttractionReach.cpp:52-54; pstqgis/src/pst/ui/wizards/attractionreachwiz.py:59; pstqgis/src/pst/analyses/attractionreachanalysis.py:62-63
- finding: QGIS-reachable. EXECUTED: 150 random 300 m axial lines, distance=axmeter, radius axmeter=4000 -> std::bad_alloc after 25 s under a 3.5 GB cap, while the same network with distance=none/walking radius=800 runs in 0.01 s. See BFS section of the MD (blow-up family). rPST surfaces the failure as an R error (worker exception propagated, PATCHES 0005) rather than crashing.
- tests: none found for a multi-metric axmeter case at stress scale (fixtures are tiny); risk: performance/safety (memory exhaustion on moderate networks); recommendation: investigate (coordinate with agent W's BFS findings; consider documenting or bounding)

### AR-006 (G) attraction_reach / distance = none (EPSTADistanceType_Undefined -> DIST_NONE)

- native (PSTAAttractionReach): accepted (DistanceTypeFromEPSTADistanceType, Limits.cpp:174-187; radius lookup Get(Undefined)=inf so decay scale is infinite); QGIS (AttractionReachAnalysis + AttractionReachWiz): available: this is what QGIS passes for the unweighted analysis, one run per radius type (attractionreachanalysis.py:187-208); rPST: accepted ('none')
- defaults native/python/rPST: n/a / UNDEFINED in non-weight mode / steps (default distance is NOT none)
- evidence: pstalgo/src/Limits.cpp:174-187; pstalgo/src/analyses/Common.cpp:34-51; pstqgis/src/pst/analyses/attractionreachanalysis.py:187-208; R/attractions.R:104; src/pst-graph.cpp:2501-2503
- finding: rPST exposes the QGIS unweighted mode as distance='none'. With constant decay the result does not depend on the distance type (EXECUTED matrix: identical outputs for all 6 distances x 7 radii on a 4x4 grid), so a user wanting the QGIS result should pass 'none'.
- tests: test-attractions.R; fixtures/attractions-direct-v3.3.2.R (537 direct cases per docs/compatibility/attractions.md:99-104); risk: performance (see AR-007); recommendation: preserve

### AR-007 (E) attraction_reach / default distance ('steps' in rPST vs UNDEFINED in QGIS unweighted)

- native (PSTAAttractionReach): accepted; QGIS (AttractionReachAnalysis + AttractionReachWiz): available (non-weight mode always passes UNDEFINED, attractionreachanalysis.py:195); rPST: accepted
- defaults native/python/rPST: Steps (AttractionReach.h:69; Python wrapper attractionreach.py:110) / UNDEFINED (non-weight) / chosen mode (weight mode) / steps
- evidence: pstqgis/src/pst/analyses/attractionreachanalysis.py:192-204; pstalgo/python/pstalgo/attractionreach.py:107-121; pstalgo/include/pstalgo/analyses/AttractionReach.h:69; R/attractions.R:90-92
- finding: rPST follows the native struct / ctypes wrapper default (steps), not the application's unweighted behaviour (UNDEFINED). With constant decay and a walking, angular or straight+walking radius the default therefore adds a turns metric that the application never tracks: EXECUTED attraction_reach(g, pts, radius=analysis_radius(walking=800)) with the DEFAULT distance on 150 random axial lines -> std::bad_alloc after ~28 s; distance='none' -> 0.01 s with identical reached sets on small cases. Default call plus a single non-steps radius is the most likely user path to the blow-up.
- tests: test-attraction-decay-default.R covers decay default only; no default-distance performance test; risk: performance/safety (default argument, unbounded memory); recommendation: investigate (candidate A: application fidelity says default should behave as 'none'; needs a human decision because it changes a public default)

### AR-008 (E) attraction_reach / distance != radius metric (e.g. steps/angular distance with walking radius; walking distance with angular radius)

- native (PSTAAttractionReach): accepted (BFS tracks the union of distance-type metric and every radius metric); QGIS (AttractionReachAnalysis + AttractionReachWiz): absent: QGIS weight mode builds Radii of the same type as the distance (attractionreachanalysis.py:54-63); non-weight mode uses UNDEFINED + one radius (50,187-208); rPST: accepted
- defaults native/python/rPST: n/a / n/a / n/a
- evidence: pstalgo/src/BFS.cpp:353-385; pstqgis/src/pst/analyses/attractionreachanalysis.py:50,54-63; docs/compatibility/qgis-differences.md:28
- finding: Native-valid, never exercised by the application, so no application oracle exists. EXECUTED on 150 random lines (walking radius 800 covering the network): steps+walking -> bad_alloc (28 s); angular+walking -> killed by 60 s timeout (n=150) / bad_alloc (n=200); steps+(straight 600 + walking 800) -> bad_alloc (16 s); walking+steps(6), walking+angular(400), steps+angular, steps+straight all 0.00-0.01 s (second metric bounded). Rule: runtime explodes when one tracked metric is effectively unbounded while another is tracked (updateCheckPoint returns 'improved' without updating the checkpoint when the new state is better in one metric and worse in another, BFS.cpp:387-397).
- tests: none found at stress scale; tiny equal-metric fixtures only; risk: performance/safety; recommendation: investigate (document the unsafe class or add a bound; do not change vendored BFS)

### AR-009 (D) attraction_reach / radius with several fields set at once (e.g. walking + steps)

- native (PSTAAttractionReach): accepted (LIMITS mask is a union); QGIS (AttractionReachAnalysis + AttractionReachWiz): available only split: Radii.split() runs one analysis per radius type (attractionreachanalysis.py:50,188-206); rPST: accepted (all limits apply together)
- defaults native/python/rPST: empty mask = no limit / one run per ticked radius type / empty (no limit)
- evidence: pstqgis/src/pst/analyses/attractionreachanalysis.py:50,188-206; pstalgo/python/pstalgo/common.py:177-189; docs/compatibility/qgis-differences.md:28; pstalgo/src/Limits.cpp:32-55
- finding: Intentional, documented departure (qgis-differences.md:28); combined limits are native-valid. Multi-metric cost applies only when one of the limits is loose (see AR-008).
- tests: test-attractions.R; fixtures/attractions-direct-v3.3.2.R (537 direct cases per docs/compatibility/attractions.md:99-104) (mixed and finite radii); risk: performance (see AR-008); recommendation: preserve

### AR-010 (G) attraction_reach / radius vector (several values of one field)

- native (PSTAAttractionReach): n/a (single Radii per call); QGIS (AttractionReachAnalysis + AttractionReachWiz): available (split yields several columns); rPST: rejected (only angular_choice/angular_integration accept multi-radius)
- defaults native/python/rPST: n/a / n/a / n/a
- evidence: R/radius.R:17-22,50-55; R/attractions.R:101; pstqgis/src/pst/analyses/attractionreachanalysis.py:188-206
- finding: Convenience gap only: a loop over radii reproduces QGIS output columns. Not a native capability, so not F.
- tests: test-multi-radius.R (rejection); risk: usability; recommendation: preserve

### AR-011 (D) attraction_reach / radius straight with network distance

- native (PSTAAttractionReach): accepted (testStraightLineLimit in BFS, BFS.cpp:198-200,338-345); QGIS (AttractionReachAnalysis + AttractionReachWiz): available (any combo is possible in the UI weight mode only with matching types, so only distance=straight pairs with straight); rPST: accepted
- defaults native/python/rPST: n/a / n/a / n/a
- evidence: pstalgo/src/BFS.cpp:198-200,287-288,338-345; R/attractions.R:101
- finding: Native-valid; straight limit is not a checkpoint metric (does not enlarge the state space). EXECUTED: steps/walking/angular distance with straight radius 600 ran in 0.00 s.
- tests: test-attractions.R; fixtures/attractions-direct-v3.3.2.R (537 direct cases per docs/compatibility/attractions.md:99-104); risk: none; recommendation: preserve

### AR-012 (D) attraction_reach / decay = constant|power|curve|divide

- native (PSTAAttractionReach): accepted (EWeightFunc, AttractionReach.h:30-36; GetWeightValue 336-353); QGIS (AttractionReachAnalysis + AttractionReachWiz): available: UI weight function combo offers only pow/curve/divide, default pow (attractionreachwiz.py:84); constant is implicit in non-weight mode (attractionreachanalysis.py:99,192-204); rPST: accepted
- defaults native/python/rPST: Constant / pow in weight mode (UI); constant otherwise (wrapper attractionreach.py:112) / constant
- evidence: pstalgo/include/pstalgo/analyses/AttractionReach.h:30-36; pstalgo/src/analyses/AttractionReach.cpp:336-353; pstqgis/src/pst/ui/wizards/attractionreachwiz.py:84; docs/compatibility/qgis-differences.md:22
- finding: Default decay differs from the wizard default (pow) by documented choice; user must state decay='power' to reproduce.
- tests: test-attraction-decay-default.R; test-attractions.R; fixtures/attractions-direct-v3.3.2.R (537 direct cases per docs/compatibility/attractions.md:99-104); risk: usability; recommendation: preserve

### AR-013 (G) attraction_reach / decay_constant default

- native (PSTAAttractionReach): accepted (any float); QGIS (AttractionReachAnalysis + AttractionReachWiz): available (UI numeric C default 1, 2 decimals, attractionreachwiz.py:85; non-weight: wrapper default 0); rPST: accepted (NULL -> 0 for constant, 1 otherwise; explicit value passed unchanged)
- defaults native/python/rPST: 0 (AttractionReach.h:76) / 1 (UI weight mode) / 0 (non-weight) / NULL = 0 constant / 1 otherwise
- evidence: R/attractions.R:106; pstalgo/include/pstalgo/analyses/AttractionReach.h:76; pstqgis/src/pst/ui/wizards/attractionreachwiz.py:85; pstalgo/python/pstalgo/attractionreach.py:113
- finding: Aligned with the application (qgis-differences.md:22). Verified by execution: constant C=0 and C=5 both give 1 for all targets; power/curve C=1 default used.
- tests: test-attraction-decay-default.R (direct-engine fixture proving the default is discriminated); risk: none; recommendation: preserve

### AR-014 (G) attraction_reach / decay_constant validation (sign, magnitude)

- native (PSTAAttractionReach): accepted (no validation); QGIS (AttractionReachAnalysis + AttractionReachWiz): available (UI numeric edit, no range); rPST: accepted: finite representable native float, any sign
- defaults native/python/rPST: none / none / finite float
- evidence: src/pst-graph.cpp:2371-2383; R/attractions.R:106
- finding: EXECUTED decay='power', decay_constant=-2, steps radius 3: output -Inf,-8,-1.25,0. Native writes negative/Inf scores; rPST preserves (documented, attractions.md:55-56). NaN input rejected.
- tests: test-attractions.R; fixtures/attractions-direct-v3.3.2.R (537 direct cases per docs/compatibility/attractions.md:99-104); risk: correctness (user-supplied); recommendation: preserve

### AR-015 (G) attraction_reach / decay power/curve with finite STRAIGHT radius on line origins

- native (PSTAAttractionReach): accepted (weight evaluated at the radius, AttractionReach.cpp:497); QGIS (AttractionReachAnalysis + AttractionReachWiz): available and DEFAULT in UI weight mode (pow + straight 1000 m, attractionreachwiz.py:55,84); rPST: accepted
- defaults native/python/rPST: n/a / pow + straight enabled by user / n/a
- evidence: pstalgo/src/analyses/AttractionReach.cpp:497; pstqgis/src/pst/ui/wizards/attractionreachwiz.py:55,84; docs/compatibility/attractions.md:49-52
- finding: EXECUTED: power and curve with distance='straight', radius straight=15 on lines returns 0 for every line (1 - (r/r)^C); divide returns the constant (r+1)^-C. Native/application quirk (the wizard default pow+straight yields all-zero line scores) is preserved, not corrected.
- tests: fixtures cover the branch (attractions.md:49-52); risk: correctness (surprising all-zero scores; QGIS has the same behaviour); recommendation: preserve (add a vignette warning; do not alter numerics)

### AR-016 (E) attraction_reach / decay scale when radius of the distance metric is absent/mismatched

- native (PSTAAttractionReach): accepted (WeightFuncMaxX = Radius.Get(distance); infinite when that limit is unset, AttractionReach.cpp:52); QGIS (AttractionReachAnalysis + AttractionReachWiz): absent (weight mode always sets the matching radius); rPST: accepted
- defaults native/python/rPST: n/a / n/a / n/a
- evidence: pstalgo/src/analyses/AttractionReach.cpp:52-54,336-353; pstalgo/src/analyses/Common.cpp:34-51
- finding: EXECUTED: decay power/curve, distance='walking' with only a steps radius, or no radius, or distance='none' -> weight 1 everywhere (x/inf = 0). Silent absence of decay. divide is unaffected (does not use the radius). Documented only as 'Power/curve use the selected distance's radius for scaling' (R/attractions.R:77).
- tests: none found for the no-decay-on-mismatch outcome; risk: usability/correctness (silently no decay); recommendation: investigate (add error or warning; behaviour is engine-defined so do not change numerics)

### AR-017 (G) attraction_reach / axmeter distance decay scale (+1 quirk)

- native (PSTAAttractionReach): accepted (mask/enum collision: EPSTADistanceTypeMask_Steps == m_DistanceType is true for AXMETER because Mask_Steps = 1<<2 = 4 = EPSTADistanceType_Axmeter); QGIS (AttractionReachAnalysis + AttractionReachWiz): available (weight mode axmeter); rPST: accepted
- defaults native/python/rPST: n/a / n/a / n/a
- evidence: pstalgo/src/analyses/AttractionReach.cpp:53-54; pstalgo/include/pstalgo/analyses/Common.h:48-50,57,63; docs/compatibility/attractions.md:53-54
- finding: VERIFIED by source and execution: steps radius 3 power decay gives 1, .667, .333, 0 (scale x/3, no +1) while axmeter radius 100 gives 0.995 at 0.5 m (x/101). Upstream defect (comparison of a mask with an enum); preserved as contract. The adjacent accessors WeightFuncMaxX()/WeightFuncConstant() are swapped (AttractionReach.cpp:71-72) but unused.
- tests: fixtures (attractions.md:53-54); risk: correctness (upstream quirk); recommendation: preserve

### AR-018 (G) attraction_reach / attraction_points / points_per_polygon / polygon_point_interval

- native (PSTAAttractionReach): accepted (IsAttractionPolygons needs non-null counts AND interval > 0, AttractionReach.cpp:61; points sum checked at 250-254); QGIS (AttractionReachAnalysis + AttractionReachWiz): available (ReadAttractionPoints; polygons only when layer is polygons AND interval enabled, attractiondistanceanalysis.py:252-266); rPST: accepted; sampling count/loop bounds checked; interval required with polygons, rejected without
- defaults native/python/rPST: interval 0 (header 91) / 10 m (UI default entry-point interval, entrypointspage.py:50) / NULL (no default interval)
- evidence: pstalgo/src/analyses/AttractionReach.cpp:61,250-254,302-329; pstqgis/src/pst/ui/pages/entrypointspage.py:50; pstqgis/src/pst/analyses/attractiondistanceanalysis.py:252-266; src/pst-graph.cpp:2390-2467
- finding: EXECUTED: polygon without interval -> error; interval without polygons -> error. Native would silently treat a polygon list with interval 0 as points; rPST makes the interval mandatory (safe). Default 10 m of the UI is not replicated (explicit value required).
- tests: test-attractions.R; fixtures/attractions-direct-v3.3.2.R (537 direct cases per docs/compatibility/attractions.md:99-104); risk: none; recommendation: preserve

### AR-019 (D) attraction_reach / polygon rings / holes (NaN separators)

- native (PSTAAttractionReach): accepted (RegionPoints.cpp:28 treats NaN as ring separator); QGIS (AttractionReachAnalysis + AttractionReachWiz): restricted: only the first part's OUTER ring is read (model.py:351-355); rPST: accepted (all rings incl. holes; sf POLYGON)
- defaults native/python/rPST: n/a / outer ring only / all rings
- evidence: pstalgo/src/geometry/RegionPoints.cpp:28; pstqgis/src/pst/model/model.py:346-358; docs/compatibility/qgis-differences.md:30; R/sf.R:78-105
- finding: Python/QGIS-only restriction (C); rPST documented departure. History for the QGIS restriction: none found (inline comment only).
- tests: test-sf-analysis-inputs.R; risk: correctness (differs from application geometry for polygons with holes); recommendation: preserve

### AR-020 (G) attraction_reach / attraction_values

- native (PSTAAttractionReach): accepted (per polygon if polygons else per point; value <= 0 skipped, AttractionReach.cpp:295,313-321); QGIS (AttractionReachAnalysis + AttractionReachWiz): available (data columns; NULL->0 via AttractionValueGen attractiondistanceanalysis.py:268-275); rPST: accepted (NULL = unit; finite native floats; zero/negative preserved and skipped by PST)
- defaults native/python/rPST: NULL = 1 / 1 if no column / NULL
- evidence: pstalgo/src/analyses/AttractionReach.cpp:294-295,313-321; pstqgis/src/pst/analyses/attractiondistanceanalysis.py:268-275; R/attractions.R:81-83
- finding: Matches. EXECUTED values=0 and -1 give all-zero scores.
- tests: test-attractions.R; fixtures/attractions-direct-v3.3.2.R (537 direct cases per docs/compatibility/attractions.md:99-104); risk: none; recommendation: preserve

### AR-021 (G) attraction_reach / distribution = copy|divide

- native (PSTAAttractionReach): accepted (polygons only; AttractionReach.cpp:371-441); QGIS (AttractionReachAnalysis + AttractionReachWiz): available when polygons (EntryPointsPage combo, default divide, entrypointspage.py:52); rPST: accepted
- defaults native/python/rPST: Divide (header 98) / divide / divide
- evidence: pstalgo/src/analyses/AttractionReach.cpp:371-441; pstqgis/src/pst/ui/pages/entrypointspage.py:52; pstalgo/include/pstalgo/analyses/AttractionReach.h:98
- finding: Matches; copy takes max over sampled points per polygon per target. EXECUTED both on a polygon: outputs equal on that geometry.
- tests: test-attractions.R; fixtures/attractions-direct-v3.3.2.R (537 direct cases per docs/compatibility/attractions.md:99-104); risk: none; recommendation: preserve

### AR-022 (G) attraction_reach / collection = mean|sum|min|max (point-group origins)

- native (PSTAAttractionReach): accepted (CollectPointGroupScores 124-175; negative per-point score skipped at 139-140; empty group -> -1); QGIS (AttractionReachAnalysis + AttractionReachWiz): available when origin is point groups (combo, default 'avarage', entrypointspage.py:41); rPST: accepted
- defaults native/python/rPST: Avarage (header 101) / avarage / mean
- evidence: pstalgo/src/analyses/AttractionReach.cpp:124-175; pstqgis/src/pst/ui/pages/entrypointspage.py:41; docs/compatibility/attractions.md:44-46
- finding: Matches; upstream quirk (group collector reads each worker's point prefix rather than the group's offset) preserved and exercised.
- tests: test-attractions.R; fixtures/attractions-direct-v3.3.2.R (537 direct cases per docs/compatibility/attractions.md:99-104); risk: correctness (upstream quirk); recommendation: preserve

### AR-023 (G) attraction_reach / origin 'points'/'point_groups' on a graph without retained points

- native (PSTAAttractionReach): accepted (zero targets); QGIS (AttractionReachAnalysis + AttractionReachWiz): n/a (graph built from the origin layer); rPST: accepted (zero-length result)
- defaults native/python/rPST: n/a / n/a / n/a
- evidence: pstalgo/src/analyses/AttractionReach.cpp:218-224; R/attractions.R:98-100
- finding: Behaviour is by design; output count = retained points/groups. (EXECUTED analogous attraction_distance(origin='points') returned 0 rows.)
- tests: test-attractions.R; fixtures/attractions-direct-v3.3.2.R (537 direct cases per docs/compatibility/attractions.md:99-104); risk: none; recommendation: preserve

### AD-001 (G) attraction_distance / origin = lines|junctions|points|point_groups

- native (PSTAAttractionDistance): accepted (switch AttractionDistance.cpp:273-282); QGIS (AttractionDistanceAnalysis + AttractionDistanceWiz): available (as AR-002); rPST: accepted
- defaults native/python/rPST: Lines / lines/points / lines
- evidence: pstalgo/src/analyses/AttractionDistance.cpp:271-282,290-305,394-417; pstqgis/src/pst/analyses/attractiondistanceanalysis.py:240-250; R/attractions.R:140
- finding: Matches native. Point-group results are computed per generated point then reduced to the group minimum (394-417).
- tests: test-attractions.R; fixtures/attractions-direct-v3.3.2.R; risk: none; recommendation: preserve

### AD-002 (G) attraction_distance / origin = point_groups with straight-only distance

- native (PSTAAttractionDistance): rejected? NO: accepted but outputs LEFT UNWRITTEN (straight fast path writes into the point-sized buffer `results` and the group reduction at 394-417 is inside the network branch only); QGIS (AttractionDistanceAnalysis + AttractionDistanceWiz): available (UI offers straight + point groups); rPST: rejected (R and native boundary) before the call
- defaults native/python/rPST: n/a / would return uninitialised group outputs / error
- evidence: pstalgo/src/analyses/AttractionDistance.cpp:290-305,341-349,394-417; R/attractions.R:143-146; src/pst-graph.cpp:2576-2578; docs/compatibility/attractions.md:14-22
- finding: Native-algorithmic limit (fast path ignores point groups). rPST rejection is evidenced by a 50-case reproduction (tools/reference/attractions/check-unwritten-group-distance.py) and is the safe choice. NOT B for rPST because rPST does not expose it.
- tests: test-attractions.R; fixtures/attractions-direct-v3.3.2.R (test-attractions.R:60-64); risk: correctness; recommendation: preserve

### AD-003 (G) attraction_distance / distance = straight (no radius or straight-only radius)

- native (PSTAAttractionDistance): accepted (special case CalcStraightLineMinDistances AttractionDistance.cpp:341-349, uses element midpoints for lines); QGIS (AttractionDistanceAnalysis + AttractionDistanceWiz): available; rPST: accepted
- defaults native/python/rPST: Steps / walking default checkbox only (attractiondistancewiz.py:54) / steps
- evidence: pstalgo/src/analyses/AttractionDistance.cpp:341-349; pstqgis/src/pst/ui/wizards/attractiondistancewiz.py:52-59
- finding: Matches. Finite straight radius updates the destination index for each eligible attraction even if not minimum (documented).
- tests: test-attractions.R; fixtures/attractions-direct-v3.3.2.R; risk: none; recommendation: preserve

### AD-004 (G) attraction_distance / distance = straight with any non-straight radius

- native (PSTAAttractionDistance): rejected (ResolveDistanceTypes pushes Straight; BuildDirectedMultiDistanceGraph throws 'Unsupported distance type', DirectedMultiDistanceGraph.cpp:114-118; PSTAAttractionDistance catch returns false, AttractionDistance.cpp:424-428); QGIS (AttractionDistanceAnalysis + AttractionDistanceWiz): available in UI (RadiusPage offers all radii for any distance mode) -> Python raises 'PSTAAttractionDistance failed'; rPST: rejected before native call
- defaults native/python/rPST: n/a / n/a / n/a
- evidence: pstalgo/src/experimental/DirectedMultiDistanceGraph.cpp:110-118; pstalgo/src/analyses/AttractionDistance.cpp:241-259,353-366,424-428; R/attractions.R (rPST message in src/pst-graph.cpp:2579-2580); EXECUTED matrix straight x {walk,steps,ang,axm,steps_walk} -> REJ
- finding: Native-API-validation reject; QGIS UI lets the user choose it and fails late. rPST correct.
- tests: test-attractions.R; fixtures/attractions-direct-v3.3.2.R; risk: none; recommendation: preserve

### AD-005 (G) attraction_distance / distance = walking|steps|angular

- native (PSTAAttractionDistance): accepted (multi-distance Dijkstra, ShortestPathTraversal.cpp); QGIS (AttractionDistanceAnalysis + AttractionDistanceWiz): available; rPST: accepted
- defaults native/python/rPST: Steps / walking / steps
- evidence: pstalgo/src/analyses/AttractionDistance.cpp:353-372; pstalgo/src/experimental/ShortestPathTraversal.cpp:81-205; pstqgis/src/pst/ui/wizards/attractiondistancewiz.py:52-59
- finding: Matches. Several distance modes in one QGIS run share one radii set (attractiondistanceanalysis.py:47,155-178); rPST takes one distance per call.
- tests: test-attractions.R; fixtures/attractions-direct-v3.3.2.R; risk: none; recommendation: preserve

### AD-006 (G) attraction_distance / distance = axmeter

- native (PSTAAttractionDistance): rejected (Axmeter not in SUPPORTED_DISTANCE_TYPES_MASK, DirectedMultiDistanceGraph.cpp:114-117); QGIS (AttractionDistanceAnalysis + AttractionDistanceWiz): available in UI (attractiondistancewiz.py:57) -> late failure; rPST: absent (not an accepted distance name)
- defaults native/python/rPST: n/a / n/a / n/a
- evidence: pstalgo/src/experimental/DirectedMultiDistanceGraph.cpp:114-118; pstqgis/src/pst/ui/wizards/attractiondistancewiz.py:57; pstqgis/src/pst/analyses/utils.py:236-237; R/attractions.R:142
- finding: UI exposes a mode the native engine rejects; rPST correctly omits it. Restriction history: mask present since the initial import 866cf3a (2019-11-20), no explanation found.
- tests: distance error test (test-attractions.R:78,146); risk: none; recommendation: preserve

### AD-007 (G) attraction_distance / radius axmeter (with network distance)

- native (PSTAAttractionDistance): rejected (ResolveDistanceTypes adds Axmeter to the type list -> unsupported-type throw); QGIS (AttractionDistanceAnalysis + AttractionDistanceWiz): available in UI (RadiusPage always offers axmeter); rPST: rejected
- defaults native/python/rPST: n/a / n/a / n/a
- evidence: pstalgo/src/analyses/AttractionDistance.cpp:252-258; pstalgo/src/experimental/DirectedMultiDistanceGraph.cpp:114-118; src/pst-graph.cpp:2581-2582; pstqgis/src/pst/ui/pages/radiuspage.py:60-61; EXECUTED walking/steps/angular/weights x axm -> REJ
- finding: Native-API-validation reject; rPST rejects early. Correct.
- tests: test-attractions.R; fixtures/attractions-direct-v3.3.2.R (test-attractions.R:78); risk: none; recommendation: preserve

### AD-008 (B) attraction_distance / radius straight with network distance (walking/steps/angular/weights)

- native (PSTAAttractionDistance): accepted but IGNORED: straight limit is resolved then discarded (psta::CalculateMinimumDistances(..., infinity) AttractionDistance.cpp:370); QGIS (AttractionDistanceAnalysis + AttractionDistanceWiz): available in UI (offered with every mode); rPST: accepted silently
- defaults native/python/rPST: n/a / n/a / n/a
- evidence: pstalgo/src/analyses/AttractionDistance.cpp:241-259,370; docs/compatibility/attractions.md:47-48; EXECUTED walking+straight20 gives the same distances as walking+no radius
- finding: Native-algorithmic limit: the option is ignored. rPST exposes it without warning, while rPST REJECTS the analogous ignored axmeter limit in OD Betweenness (docs/compatibility/od-betweenness.md:89-94). Inconsistent policy; a user supplying a straight cap gets an unrestricted result.
- tests: test-attractions.R; fixtures/attractions-direct-v3.3.2.R (fixture with straight radius zero); risk: correctness (silently unrestricted result); recommendation: restrict (reject or warn, consistent with the OD axmeter decision; needs human sign-off)

### AD-009 (G) attraction_distance / distance = weights, line_weights, point_edge_weight

- native (PSTAAttractionDistance): accepted (size must equal line count when Weights requested, DirectedMultiDistanceGraph.cpp:120-122; point edge cost per metre); QGIS (AttractionDistanceAnalysis + AttractionDistanceWiz): available (UI 'Attribute-based cost'; field must be numeric; spin 0..99999, attractiondistancewiz.py:108-111,123-135); rPST: accepted: one finite non-negative native float per line; point_edge_weight >= 0 finite
- defaults native/python/rPST: m_WeightPerMeterForPointEdges = 0 / 0 / 0
- evidence: pstalgo/include/pstalgo/analyses/AttractionDistance.h:38-41; pstalgo/src/experimental/DirectedMultiDistanceGraph.cpp:120-122,204,238; pstqgis/src/pst/ui/wizards/attractiondistancewiz.py:100-136; src/pst-graph.cpp:2584-2592
- finding: Feature added upstream in 85d9e1c (2025-03-07 'Support for line weights as distance') and 905d588 ('weight-per-meter factor for edges that connect points to network'). Negative weights: UI validates (min_value < 0, wiz:132) and rPST rejects (Dijkstra needs non-negative edges); native does not check. EXECUTED: negative -> error; weights+point cost 10 -> distances 32,34,36.
- tests: test-attractions.R; fixtures/attractions-direct-v3.3.2.R; risk: none; recommendation: preserve

### AD-010 (G) attraction_distance / mixed distance + radius types (e.g. steps distance + walking/angular radius, multi-distance Dijkstra)

- native (PSTAAttractionDistance): accepted (up to 5 metrics; primary metric orders the heap); QGIS (AttractionDistanceAnalysis + AttractionDistanceWiz): available (shared Radii across all distance modes); rPST: accepted
- defaults native/python/rPST: n/a / n/a / n/a
- evidence: pstalgo/src/analyses/AttractionDistance.cpp:241-259; pstalgo/src/experimental/ShortestPathTraversal.cpp:81-205; EXECUTED n=400 random lines: steps/walk, angular/walk, walking/steps, walking/ang, steps/(walk+steps+ang) all <= 0.21 s
- finding: No blow-up (priority-queue search, unlike CPSTBFS). Note ShortestPathTraversal.cpp:187 prunes with HasImprovement(s.m_Distances) i.e. the PARENT state's distances, not new_state's; whether this over- or under-prunes is unverified (native behaviour, not an rPST fault).
- tests: test-attractions.R; fixtures/attractions-direct-v3.3.2.R; risk: correctness (native pruning unverified); recommendation: preserve (investigate native pruning only if numerical doubt arises)

### AD-011 (D) attraction_distance / destination_indices (append raw destination index)

- native (PSTAAttractionDistance): accepted (m_OutDestinationIndices optional; -1 when unreachable); QGIS (AttractionDistanceAnalysis + AttractionDistanceWiz): available only when 'copy destination attributes' is ticked (attractiondistanceanalysis.py:158,183-191); rPST: accepted (default TRUE)
- defaults native/python/rPST: NULL (not requested) / only when attribute copy enabled / TRUE
- evidence: pstalgo/src/analyses/AttractionDistance.cpp:299-305,374-392,413-415; pstqgis/src/pst/analyses/attractiondistanceanalysis.py:158,183-191; R/attractions.R:131-133
- finding: rPST returns the raw index; QGIS maps it through the attribute list. Index semantics are mode-dependent (polygon vs generated sample) and preserved, documented (attractions.md:56-62).
- tests: test-attractions.R; fixtures/attractions-direct-v3.3.2.R; risk: usability; recommendation: preserve

### AD-012 (G) attraction_distance / attraction filtering by value / attribute copy (Python-only)

- native (PSTAAttractionDistance): n/a (Python pre-processing); QGIS (AttractionDistanceAnalysis + AttractionDistanceWiz): available: FilterZeroAttractions drops destinations with value <= 0 before the native call (attractiondistanceanalysis.py:283-311); rPST: absent (no attraction_values for Distance; caller filters)
- defaults native/python/rPST: n/a / filter value > 0 / none
- evidence: pstqgis/src/pst/analyses/attractiondistanceanalysis.py:145-152,283-311
- finding: Python-only feature with no native counterpart; rPST leaves it to the caller. Destination indices then refer to the caller's filtered list, as in QGIS.
- tests: none; risk: usability; recommendation: preserve

### AD-013 (G) attraction_distance / unreachable value and -1 convention

- native (PSTAAttractionDistance): accepted (infinity replaced by -1, AttractionDistance.cpp:420-422); QGIS (AttractionDistanceAnalysis + AttractionDistanceWiz): same; rPST: preserved (-1)
- defaults native/python/rPST: n/a / -1 / -1
- evidence: pstalgo/src/analyses/AttractionDistance.cpp:420-422; docs/compatibility/attractions.md:36-40
- finding: Matches; no NA substitution.
- tests: test-attractions.R; fixtures/attractions-direct-v3.3.2.R; risk: none; recommendation: preserve

### AD-014 (G) attraction_distance / default distance ('steps')

- native (PSTAAttractionDistance): accepted; QGIS (AttractionDistanceAnalysis + AttractionDistanceWiz): walking is the only pre-ticked mode (attractiondistancewiz.py:54); rPST: steps
- defaults native/python/rPST: Steps (AttractionDistance.h:21) / walking (wizard) / steps
- evidence: pstalgo/include/pstalgo/analyses/AttractionDistance.h:21; pstqgis/src/pst/ui/wizards/attractiondistancewiz.py:54; R/attractions.R:90
- finding: Default follows the native struct, differs from the wizard preselection; cheap (Dijkstra) so no safety issue.
- tests: test-attractions.R; fixtures/attractions-direct-v3.3.2.R; risk: usability; recommendation: preserve

### OD-001 (G) od_betweenness / distance = walking|angular

- native (PSTAODBetweenness): accepted (UpdateShortestCrossingDist handles only these two; others hit ASSERT(false) that is compiled out and then return true, ODBetweenness.cpp:465-486; UpdateDistModeDist ASSERT 449); QGIS (ODBetweennessAnalysis + ODBetweennessWiz + ODBetweennessAlgorithm (processing)): available (route choice combo: walking default, angular; odbetweennesswiz.py:131-134,155-159); rPST: accepted (exact names)
- defaults native/python/rPST: Walking (header 54) / walking / walking
- evidence: pstalgo/src/analyses/ODBetweenness.cpp:449-451,465-486; pstalgo/include/pstalgo/analyses/ODBetweenness.h:54; pstqgis/src/pst/ui/wizards/odbetweennesswiz.py:131-134; pstqgis/src/pst/analyses/odbetweennessanalysis.py:51-54; R/od-betweenness.R:72
- finding: Matches.
- tests: test-od-betweenness.R; fixtures/od-direct-v3.3.2.R (2,110 direct cases per docs/compatibility/od-betweenness.md:57-65); helper-od-axmeter.R; risk: none; recommendation: preserve

### OD-002 (G) od_betweenness / distance = straight|steps|axmeter (enum values passed to the descriptor)

- native (PSTAODBetweenness): rejected in effect: no pruning branch (undefined in release builds: default case returns true so crossings are never pruned); QGIS (ODBetweennessAnalysis + ODBetweennessWiz + ODBetweennessAlgorithm (processing)): absent; rPST: rejected (exact names walking|angular)
- defaults native/python/rPST: n/a / n/a / n/a
- evidence: pstalgo/src/analyses/ODBetweenness.cpp:449-451,465-486; R/od-betweenness.R:72; test-od-betweenness.R:126
- finding: Native-algorithmic limit (B class) that rPST does not expose. Correct.
- tests: test-od-betweenness.R; fixtures/od-direct-v3.3.2.R (2,110 direct cases per docs/compatibility/od-betweenness.md:57-65); helper-od-axmeter.R; risk: none; recommendation: preserve

### OD-003 (G) od_betweenness / destination_mode = all|closest

- native (PSTAODBetweenness): accepted (closest breaks at first popped destination, ODBetweenness.cpp:296-300); QGIS (ODBetweennessAnalysis + ODBetweennessWiz + ODBetweennessAlgorithm (processing)): available (combo, wiz:126-129, algorithm 97-100); rPST: accepted
- defaults native/python/rPST: AllReachableDestinations (header 51) / all / all
- evidence: pstalgo/src/analyses/ODBetweenness.cpp:296-300; pstalgo/include/pstalgo/analyses/ODBetweenness.h:46-51; pstqgis/src/pst/ui/wizards/odbetweennesswiz.py:126-129; R/od-betweenness.R:73
- finding: Matches; ties follow native priority queue order.
- tests: test-od-betweenness.R; fixtures/od-direct-v3.3.2.R (2,110 direct cases per docs/compatibility/od-betweenness.md:57-65); helper-od-axmeter.R; risk: none; recommendation: preserve

### OD-004 (G) od_betweenness / radius straight / walking / angular

- native (PSTAODBetweenness): accepted (IsWithinRadius 488-494; straight 496-499; first step 257); QGIS (ODBetweennessAnalysis + ODBetweennessWiz + ODBetweennessAlgorithm (processing)): available (RADIUS_TYPES = straight, walking, angular, wiz:136; processing algorithm 175-197); rPST: accepted
- defaults native/python/rPST: empty = unbounded / none (processing requires >= 1, algorithm 207-213) / empty
- evidence: pstalgo/src/analyses/ODBetweenness.cpp:244,257,337,385-390,488-499; pstqgis/src/pst/ui/wizards/odbetweennesswiz.py:136,163; pstqgis/src/pst/processing/odbetweenness_algorithm.py:175-213; R/od-betweenness.R:67-69
- finding: Matches. 'No radius' is rejected only by the processing algorithm (UI-only/Python), native and rPST accept it (unbounded).
- tests: test-od-betweenness.R; fixtures/od-direct-v3.3.2.R (2,110 direct cases per docs/compatibility/od-betweenness.md:57-65); helper-od-axmeter.R; risk: none; recommendation: preserve

### OD-005 (D) od_betweenness / radius steps

- native (PSTAODBetweenness): accepted (m_Steps <= Radius().Steps(), ODBetweenness.cpp:488-494); QGIS (ODBetweennessAnalysis + ODBetweennessWiz + ODBetweennessAlgorithm (processing)): absent (RADIUS_TYPES excludes steps); rPST: accepted
- defaults native/python/rPST: n/a / n/a / n/a
- evidence: pstalgo/src/analyses/ODBetweenness.cpp:341-345,488-494; pstqgis/src/pst/ui/wizards/odbetweennesswiz.py:136; R/od-betweenness.R:67-69
- finding: PST-native extension beyond QGIS (not offered by UI or processing); implemented and fixture-covered.
- tests: test-od-betweenness.R; fixtures/od-direct-v3.3.2.R (2,110 direct cases per docs/compatibility/od-betweenness.md:57-65); helper-od-axmeter.R; risk: none; recommendation: preserve

### OD-006 (G) od_betweenness / radius axmeter

- native (PSTAODBetweenness): accepted but IGNORED (no axmeter test in IsWithinRadius); QGIS (ODBetweennessAnalysis + ODBetweennessWiz + ODBetweennessAlgorithm (processing)): absent in UI; rPST: rejected (maintainer decision)
- defaults native/python/rPST: n/a / n/a / n/a
- evidence: pstalgo/src/analyses/ODBetweenness.cpp:488-494; R/od-betweenness.R:70-71; docs/compatibility/od-betweenness.md:87-94; EXECUTED walking/angular x axm -> REJ
- finding: Reject-because-ignored policy. Contrast AD-008 (ignored straight limit accepted).
- tests: helper-od-axmeter.R; test-od-betweenness.R; risk: usability; recommendation: preserve

### OD-007 (D) od_betweenness / several radius fields at once

- native (PSTAODBetweenness): accepted (all checked independently); QGIS (ODBetweennessAnalysis + ODBetweennessWiz + ODBetweennessAlgorithm (processing)): available only split: one run per ticked radius (odbetweennessanalysis.py:57,134-148); rPST: accepted (all apply together)
- defaults native/python/rPST: n/a / one run per radius / single call
- evidence: pstalgo/src/analyses/ODBetweenness.cpp:488-494; pstqgis/src/pst/analyses/odbetweennessanalysis.py:57,134-148; docs/compatibility/qgis-differences.md:28
- finding: Documented departure. Search is a Dijkstra on the primary cost only (UpdateShortestCrossingDist prunes on the primary cost, 465-486), so extra limits cannot enlarge the state space: EXECUTED n=400 random lines walking/steps, walking/angular, angular/walking, angular/none, walking/(walk+steps+angular) all <= 0.04 s. OD is not a CPSTBFS analysis.
- tests: test-od-betweenness.R; fixtures/od-direct-v3.3.2.R (2,110 direct cases per docs/compatibility/od-betweenness.md:57-65); helper-od-axmeter.R; risk: none; recommendation: preserve

### OD-008 (G) od_betweenness / origin_weights

- native (PSTAODBetweenness): accepted (per origin; unit if NULL); QGIS (ODBetweennessAnalysis + ODBetweennessWiz + ODBetweennessAlgorithm (processing)): required column (nulls -> 0, odbetweennessanalysis.py:102-105); rPST: accepted (NULL = unit, finite signed floats)
- defaults native/python/rPST: NULL = 1 / column required / NULL
- evidence: pstalgo/src/analyses/ODBetweenness.cpp:98; pstqgis/src/pst/analyses/odbetweennessanalysis.py:101-105; R/od-betweenness.R:41-43
- finding: Superset of QGIS (optional); semantics identical.
- tests: test-od-betweenness.R; fixtures/od-direct-v3.3.2.R (2,110 direct cases per docs/compatibility/od-betweenness.md:57-65); helper-od-axmeter.R; risk: none; recommendation: preserve

### OD-009 (G) od_betweenness / destination_weights

- native (PSTAODBetweenness): accepted (per retained native point; <= 0 excluded, ODBetweenness.cpp:382); QGIS (ODBetweennessAnalysis + ODBetweennessWiz + ODBetweennessAlgorithm (processing)): available (optional column; one per destination point, wiz:88-92); rPST: accepted (length = graph point count, not polygon count)
- defaults native/python/rPST: NULL = 1 / optional / NULL
- evidence: pstalgo/src/analyses/ODBetweenness.cpp:68-69,382; pstqgis/src/pst/analyses/odbetweennessanalysis.py:119-126; R/od-betweenness.R:44-46
- finding: Matches.
- tests: test-od-betweenness.R; fixtures/od-direct-v3.3.2.R (2,110 direct cases per docs/compatibility/od-betweenness.md:57-65); helper-od-axmeter.R; risk: none; recommendation: preserve

### OD-010 (G) od_betweenness / angular primary + walking radius, destination leg

- native (PSTAODBetweenness): accepted (final destination leg added to walking only when distance == Walking, ODBetweenness.cpp:394-395); QGIS (ODBetweennessAnalysis + ODBetweennessWiz + ODBetweennessAlgorithm (processing)): same; rPST: preserved
- defaults native/python/rPST: n/a / n/a / n/a
- evidence: pstalgo/src/analyses/ODBetweenness.cpp:392-396; R/od-betweenness.R:13-15
- finding: Documented native quirk (walking radius differs between walking-primary and angular-primary). Preserved and tested.
- tests: test-od-betweenness.R; fixtures/od-direct-v3.3.2.R (2,110 direct cases per docs/compatibility/od-betweenness.md:57-65); helper-od-axmeter.R; risk: correctness (native quirk); recommendation: preserve

### OD-011 (G) od_betweenness / worker count

- native (PSTAODBetweenness): accepted (multi-core disabled: `//#define USE_MULTIPLE_CORES`, ODBetweenness.cpp:35); QGIS (ODBetweennessAnalysis + ODBetweennessWiz + ODBetweennessAlgorithm (processing)): n/a; rPST: single worker retained
- defaults native/python/rPST: 1 / 1 / 1
- evidence: pstalgo/src/analyses/ODBetweenness.cpp:35,511-517; R/od-betweenness.R:21-24
- finding: Native choice (no explanation found). rPST does not enable what the engine disables.
- tests: test-workers.R; risk: performance; recommendation: preserve

### OD-012 (G) od_betweenness / origins (matrix / sf POINT)

- native (PSTAODBetweenness): accepted (world doubles; closest line found per origin); QGIS (ODBetweennessAnalysis + ODBetweennessWiz + ODBetweennessAlgorithm (processing)): available (layer points); rPST: accepted (finite, native bounds); sf POINT
- defaults native/python/rPST: n/a / n/a / n/a
- evidence: pstalgo/src/analyses/ODBetweenness.cpp:90-101,238-243; src/pst-graph.cpp:2654-2665; R/od-betweenness.R:74-76
- finding: rPST adds bounds checks beyond native; sf adapter is an extension.
- tests: test-od-betweenness.R; test-sf-analysis-inputs.R; risk: none; recommendation: preserve

### NC-001 (G) create_junctions / x (first layer) / y (second layer)

- native (PSTACreateJunctions): accepted (single table mode keeps repeated pairs with .02 tail rule; two-table mode keeps unique inter-layer points, CreateJunctions.cpp:58-70,160-165,224); QGIS (CreateJunctionsAnalysis + CreateJunctionsWiz): available ('One table' | 'Two tables', createjunctionswiz.py:35-52; analysis 54-75); rPST: accepted (explicitly empty y keeps two-layer mode)
- defaults native/python/rPST: n/a / one table / one layer
- evidence: pstalgo/src/analyses/CreateJunctions.cpp:58-70,160-170,224-225; pstqgis/src/pst/analyses/createjunctionsanalysis.py:62-75; pstqgis/src/pst/ui/wizards/createjunctionswiz.py:35-52; R/construction.R:44-52
- finding: Matches.
- tests: test-network-construction.R; fixtures/network-construction-direct-v3.3.2.R (124 direct cases); risk: none; recommendation: preserve

### NC-002 (D) create_junctions / line_indices / line_indices_y (indexed layers)

- native (PSTACreateJunctions): accepted (m_Lines0/m_Lines1; bbox uses prefix through max index, CreateJunctions.cpp:46); QGIS (CreateJunctionsAnalysis + CreateJunctionsWiz): absent (QGIS passes None, createjunctionsanalysis.py:87-91); rPST: accepted
- defaults native/python/rPST: NULL / None / NULL
- evidence: pstalgo/src/analyses/CreateJunctions.cpp:46,86-98; pstqgis/src/pst/analyses/createjunctionsanalysis.py:87-91; R/construction.R:38-40
- finding: PST-native extension beyond QGIS, covered by indexed fixtures.
- tests: test-network-construction.R; fixtures/network-construction-direct-v3.3.2.R (124 direct cases); risk: none; recommendation: preserve

### NC-003 (G) create_junctions / empty first layer

- native (PSTACreateJunctions): accepted but result fields NOT written (early `return true`, CreateJunctions.cpp:43-44); QGIS (CreateJunctionsAnalysis + CreateJunctionsWiz): would read uninitialised result; rPST: rejected
- defaults native/python/rPST: n/a / n/a / error
- evidence: pstalgo/src/analyses/CreateJunctions.cpp:43-44; R/construction.R:45-50; src/pst-construction.cpp:201-215
- finding: Native-algorithmic hazard avoided; policy documented (network-construction.md:36-40).
- tests: test-network-construction.R; fixtures/network-construction-direct-v3.3.2.R (124 direct cases); risk: safety; recommendation: preserve

### NC-004 (D) create_junctions / unlinks

- native (PSTACreateJunctions): accepted (nearest-junction removal, no tolerance; compaction quirk discards leading survivors because n only advances when i != n, CreateJunctions.cpp:226-262); QGIS (CreateJunctionsAnalysis + CreateJunctionsWiz): present in UI but BROKEN: undefined name `point_table` (createjunctionsanalysis.py:83) -> NameError when unlinks are ticked; rPST: accepted
- defaults native/python/rPST: none / None / NULL
- evidence: pstalgo/src/analyses/CreateJunctions.cpp:76-80,226-262; pstqgis/src/pst/analyses/createjunctionsanalysis.py:79-83; docs/compatibility/qgis-differences.md:35
- finding: Upstream application defect not reproduced; rPST provides working unlinks and preserves the native compaction quirk (documented, R/construction.R:6-9).
- tests: test-network-construction.R; fixtures/network-construction-direct-v3.3.2.R (124 direct cases); risk: correctness (native quirk preserved); recommendation: preserve

### NC-005 (D) create_junctions / output = native|sf

- native (PSTACreateJunctions): n/a; QGIS (CreateJunctionsAnalysis + CreateJunctionsWiz): QGIS writes a point layer + id column (createjunctionsanalysis.py:99-114); rPST: accepted
- defaults native/python/rPST: n/a / n/a / native
- evidence: pstqgis/src/pst/analyses/createjunctionsanalysis.py:99-114; R/construction.R:53-54
- finding: Interface extension; geometry copied from native output only.
- tests: test-sf-construction.R; risk: none; recommendation: preserve

### NC-006 (G) create_segment_map / network_type = axial_or_segment|road_center_lines

- native (PSTACreateSegmentMap): accepted (both; centre-lines emits cuts as unlinks and clears cuts, CreateSegmentMap.cpp:195-205); QGIS (CreateSegmentMapAnalysis + CreateSegmentMapWiz): available (combo, createsegmentmapwiz.py:67-73); rPST: accepted
- defaults native/python/rPST: n/a / first entry (axial/segment) / axial_or_segment
- evidence: pstalgo/src/analyses/CreateSegmentMap.cpp:182-205; pstqgis/src/pst/ui/wizards/createsegmentmapwiz.py:67-73; R/construction.R:134-139
- finding: Matches.
- tests: test-network-construction.R; fixtures/network-construction-direct-v3.3.2.R (124 direct cases); risk: none; recommendation: preserve

### NC-007 (G) create_segment_map / snap

- native (PSTACreateSegmentMap): accepted (float; negative not validated natively); QGIS (CreateSegmentMapAnalysis + CreateSegmentMapWiz): available (default 1, 1 decimal, no min, wiz:118); rPST: accepted: finite non-negative native float, squared must be representable
- defaults native/python/rPST: none in struct / 1 / 1
- evidence: pstalgo/src/analyses/CreateSegmentMap.cpp:222; pstqgis/src/pst/ui/wizards/createsegmentmapwiz.py:118; pstalgo/python/pstalgo/createsegmentmap.py:76; R/construction.R:137; src/pst-construction.cpp:252-312
- finding: Matches default; rPST adds sanity limits (negative meaningless).
- tests: test-network-construction.R; fixtures/network-construction-direct-v3.3.2.R (124 direct cases) (test-network-construction.R:110); risk: none; recommendation: preserve

### NC-008 (G) create_segment_map / tail

- native (PSTACreateSegmentMap): accepted; QGIS (CreateSegmentMapAnalysis + CreateSegmentMapWiz): available (default 10, wiz:125); rPST: accepted (non-negative)
- defaults native/python/rPST: DEFAULT_MIN_TAIL = 10 (class constant, unused) / 10 / 10
- evidence: pstalgo/src/analyses/CreateSegmentMap.cpp:40-42; pstqgis/src/pst/ui/wizards/createsegmentmapwiz.py:125; pstalgo/python/pstalgo/createsegmentmap.py:76
- finding: Matches.
- tests: test-network-construction.R; fixtures/network-construction-direct-v3.3.2.R (124 direct cases); risk: none; recommendation: preserve

### NC-009 (G) create_segment_map / deviation

- native (PSTACreateSegmentMap): accepted; QGIS (CreateSegmentMapAnalysis + CreateSegmentMapWiz): available (default 1, wiz:132); rPST: accepted (non-negative, squared representable)
- defaults native/python/rPST: 1 (constant unused) / 1 / 1
- evidence: pstalgo/src/analyses/CreateSegmentMap.cpp:40-42; pstqgis/src/pst/ui/wizards/createsegmentmapwiz.py:132; pstalgo/python/pstalgo/createsegmentmap.py:76
- finding: Matches.
- tests: test-network-construction.R; fixtures/network-construction-direct-v3.3.2.R (124 direct cases); risk: none; recommendation: preserve

### NC-010 (D) create_segment_map / extrude

- native (PSTACreateSegmentMap): accepted (independent float, CreateSegmentMap.cpp:130-135 FindCuts extrude_len); QGIS (CreateSegmentMapAnalysis + CreateSegmentMapWiz): extrude is NOT a control: analysis forces extrude = trim_snap (createsegmentmapanalysis.py:85); wrapper default 0; rPST: accepted, independent, default 0
- defaults native/python/rPST: none in struct / = snap (1) / 0
- evidence: pstqgis/src/pst/analyses/createsegmentmapanalysis.py:61-64,85; pstalgo/python/pstalgo/createsegmentmap.py:76; R/construction.R:137; docs/compatibility/qgis-differences.md:26; EXECUTED: T-junction with a 0.5 gap, snap 1 -> 2 segments with extrude 0 vs 3 with extrude 1
- finding: Documented, executed departure: default rPST output differs from the application for gap-closing. Qgis-differences says every departure is covered by a test asserting it; the only extrude tests are the validation loop (test-network-construction.R:110) and direct fixture variants, no test asserts the default-versus-application difference.
- tests: test-network-construction.R; fixtures/network-construction-direct-v3.3.2.R (124 direct cases); no test asserting default extrude=0 vs QGIS extrude=snap; risk: correctness (application equivalence needs explicit extrude=snap); recommendation: preserve (add the missing departure test)

### NC-011 (G) create_segment_map / unlinks

- native (PSTACreateSegmentMap): accepted only for axial/segment (throws otherwise, CreateSegmentMap.cpp:187-190); cut-matching radius fixed 100 (432); QGIS (CreateSegmentMapAnalysis + CreateSegmentMapWiz): available only for axial/segment (hidden otherwise, wiz:95-99; analysis 47); rPST: accepted only axial_or_segment, nonempty
- defaults native/python/rPST: none / none / NULL
- evidence: pstalgo/src/analyses/CreateSegmentMap.cpp:186-190,432,481-486; pstqgis/src/pst/analyses/createsegmentmapanalysis.py:47; pstqgis/src/pst/ui/wizards/createsegmentmapwiz.py:95-99; src/pst-construction.cpp:252-312
- finding: rPST and QGIS both mirror the native check (native-API-validation).
- tests: test-network-construction.R; fixtures/network-construction-direct-v3.3.2.R (124 direct cases); risk: none; recommendation: preserve

### NC-012 (D) create_segment_map / coords + sections (signed section lengths)

- native (PSTACreateSegmentMap): accepted (negative = continuation, QGIS multipart 'not supported' for lines in readLines); QGIS (CreateSegmentMapAnalysis + CreateSegmentMapWiz): available (single-part polylines; multipart rejected, model.py:283-305); rPST: accepted (matrix+sections or sf LINESTRING/MULTILINESTRING)
- defaults native/python/rPST: n/a / n/a / n/a
- evidence: pstalgo/src/analyses/CreateSegmentMap.cpp:104-125; pstqgis/src/pst/model/model.py:283-305; R/construction.R:59-75
- finding: rPST accepts native multipart encoding that QGIS refuses (extension).
- tests: test-sf-construction.R; test-network-construction.R; fixtures/network-construction-direct-v3.3.2.R (124 direct cases); risk: none; recommendation: preserve

### NC-013 (F) create_segment_map / cyclic detail reduction

- native (PSTACreateSegmentMap): accepted by pristine PST (zero-length self-loop or memory-unsafe state for degree-two rings); QGIS (CreateSegmentMapAnalysis + CreateSegmentMapWiz): same (crash possible); rPST: rejected by a generated-copy guard that also rejects closures at degree >= 3 junctions that pristine PST completes
- defaults native/python/rPST: n/a / n/a / error
- evidence: docs/compatibility/network-construction.md:52-74; inst/upstream/PATCHES.md:266-280; R/construction.R:20-31
- finding: Approved conservative policy: narrower `count<=2` guard evaluated and declined. rPST rejects some inputs the application would process (to a degenerate output). Classified F because the over-rejection of valid native results is explicit, though approved.
- tests: test-network-construction.R; fixtures/network-construction-direct-v3.3.2.R (124 direct cases) (three formerly crashing cycles); risk: usability (over-rejection); recommendation: preserve (approved policy; revisit if real networks hit it)

### NC-014 (G) create_segment_map / copy column / source_id association

- native (PSTACreateSegmentMap): n/a (base index per segment); QGIS (CreateSegmentMapAnalysis + CreateSegmentMapWiz): Python-only copy-column feature (analysis 74-95); rPST: source_id vector returned
- defaults native/python/rPST: n/a / n/a / n/a
- evidence: pstqgis/src/pst/analyses/createsegmentmapanalysis.py:74-95; R/construction.R:116-122
- finding: Equivalent information returned (source_id).
- tests: test-network-construction.R; fixtures/network-construction-direct-v3.3.2.R (124 direct cases); risk: none; recommendation: preserve

### IS-001 (G) isovist_context / obstacles (groups of polygons)

- native (PSTACreateIsovistContext + PSTACalculateIsovist): accepted (SPolygons: group counts, polygon counts, point counts); QGIS (IsovistAnalysis + IsovistWiz + isovist map tool): available (obstacle layers = groups; outer ring only, common.py:111-126); rPST: accepted (matrix groups or sf POLYGON layer, one ring per feature)
- defaults native/python/rPST: n/a / n/a / empty list
- evidence: pstalgo/src/analyses/CalculateIsovists.cpp:104-116,270-298; pstqgis/src/pst/maptools/isovist/common.py:111-137; R/isovist.R:51-62
- finding: Matches; sf adapter is an extension.
- tests: test-isovist.R; helper-isovist.R; fixtures/isovist-direct-v3.3.2.R; test-isovist-ulp-allowance.R; risk: none; recommendation: preserve

### IS-002 (G) isovist_context / attraction_points / attraction_polygons

- native (PSTACreateIsovistContext + PSTACalculateIsovist): accepted; QGIS (IsovistAnalysis + IsovistWiz + isovist map tool): available (point and polygon attraction layers); rPST: accepted
- defaults native/python/rPST: n/a / n/a / empty list
- evidence: pstalgo/src/analyses/CalculateIsovists.cpp:316-366; pstqgis/src/pst/maptools/isovist/common.py:90-137
- finding: Matches.
- tests: test-isovist.R; helper-isovist.R; fixtures/isovist-direct-v3.3.2.R; test-isovist-ulp-allowance.R; risk: none; recommendation: preserve

### IS-003 (G) isovist_context / group count and per-group object limits

- native (PSTACreateIsovistContext + PSTACalculateIsovist): limited (visible object index packs group<<24 | index&0xFFFFFF, CalculateIsovists.cpp:547; attraction point Group:8 bitfield 216): <= 256 combined groups, < 2^24 objects per group; QGIS (IsovistAnalysis + IsovistWiz + isovist map tool): absent (no check; QGIS layers practically < 256); rPST: enforced (<= 256 combined groups, counts <= 2^24)
- defaults native/python/rPST: n/a / none / 256 / 2^24
- evidence: pstalgo/src/analyses/CalculateIsovists.cpp:216,547; src/pst-isovist.cpp:144-186; R/isovist.R:19-21; EXECUTED 256 ok, 257 -> error
- finding: Native-algorithmic limit; rPST guard is correct.
- tests: test-isovist.R; helper-isovist.R; fixtures/isovist-direct-v3.3.2.R; test-isovist-ulp-allowance.R; risk: safety; recommendation: preserve

### IS-004 (E) isovist_context / polygon ring orientation

- native (PSTACreateIsovistContext + PSTACalculateIsovist): accepted (edge test crp(pt_prev, pt_next) >= 0 keeps one orientation only, CalculateIsovists.cpp:452); QGIS (IsovistAnalysis + IsovistWiz + isovist map tool): QGIS passes the stored ring unchanged (model.py:355-360); rPST: accepted, orientation unchanged and unchecked
- defaults native/python/rPST: n/a / n/a / n/a
- evidence: pstalgo/src/analyses/CalculateIsovists.cpp:452-470; pstqgis/src/pst/model/model.py:355-360; R/isovist.R:5-6; EXECUTED same square: clockwise area 269.80 vs counter-clockwise 271.80
- finding: Obstacle visibility depends on winding (back-facing edges are the ones kept). rPST documents 'PST expects Cartesian clockwise rings' but neither validates nor warns; a CCW polygon silently gives a different isovist. the internal engineering rules forbids reordering, so a warning/validation option is the only safe mitigation.
- tests: fixtures use consistent winding; no CCW test; risk: correctness (silent wrong result for CCW input); recommendation: investigate (consider an opt-in orientation check; do not reorder silently)

### IS-005 (G) isovist / origin

- native (PSTACreateIsovistContext + PSTACalculateIsovist): accepted (world doubles); QGIS (IsovistAnalysis + IsovistWiz + isovist map tool): available (one run per origin point, isovistanalysis.py:72); rPST: accepted (length-2 numeric, finite, bounds checked)
- defaults native/python/rPST: n/a / n/a / required
- evidence: pstalgo/src/analyses/CalculateIsovists.cpp:394-410; pstqgis/src/pst/analyses/isovistanalysis.py:72-81; src/pst-isovist.cpp:192-200
- finding: Single origin per call in rPST; loop to batch (QGIS batches inside the analysis).
- tests: test-isovist.R; helper-isovist.R; fixtures/isovist-direct-v3.3.2.R; test-isovist-ulp-allowance.R; risk: usability; recommendation: preserve

### IS-006 (G) isovist / max_distance

- native (PSTACreateIsovistContext + PSTACalculateIsovist): accepted (float); QGIS (IsovistAnalysis + IsovistWiz + isovist map tool): available (wizard default 500, isovistwiz.py:120); rPST: accepted: 0 <= d <= sqrt(FLT_MAX); max_distance=0 errors ('no result was published')
- defaults native/python/rPST: none / 500 / required (no default)
- evidence: pstalgo/src/analyses/CalculateIsovists.cpp:402; pstqgis/src/pst/ui/wizards/isovistwiz.py:117-123; src/pst-isovist.cpp:201; EXECUTED max_distance=0 -> REJ
- finding: Zero distance triggers a native invalid-access state caught by a generated-copy guard (R/isovist.R:67-72). Message is generic.
- tests: test-isovist.R; helper-isovist.R; fixtures/isovist-direct-v3.3.2.R; test-isovist-ulp-allowance.R; risk: usability; recommendation: preserve

### IS-007 (C) isovist / field_of_view

- native (PSTACreateIsovistContext + PSTACalculateIsovist): accepted (clamped to 0..360 for the arc only, CalculateIsovists.cpp:78; every other test compares `< 360` on the UNCLAMPED value); QGIS (IsovistAnalysis + IsovistWiz + isovist map tool): map tool clamps 0..360 (isovisttoolwindow.py:460); wizard fixed 360 (isovistanalysis.py:78); rPST: accepted 0..360 (default 360); outside -> error
- defaults native/python/rPST: none / 360 / 360
- evidence: pstalgo/src/analyses/CalculateIsovists.cpp:78,399,425-426; pstqgis/src/pst/maptools/isovist/isovisttoolwindow.py:459-461; pstqgis/src/pst/analyses/isovistanalysis.py:75-81; src/pst-isovist.cpp:202; EXECUTED 400,-1 -> REJ; 0 and 0.001 -> area 0
- finding: rPST range equals the UI clamp (UI-only restriction adopted); native tolerates >360 (treated as full circle by the `<360` tests) but that was not exercised.
- tests: test-isovist.R:172; risk: none; recommendation: preserve

### IS-008 (G) isovist / direction

- native (PSTACreateIsovistContext + PSTACalculateIsovist): accepted (any float; ignored when fov >= 360, line 399); QGIS (IsovistAnalysis + IsovistWiz + isovist map tool): map tool clamps 0..360 (isovisttoolwindow.py:464); wizard fixed 0; rPST: accepted (any finite float, default 0)
- defaults native/python/rPST: none / 0 / 0
- evidence: pstalgo/src/analyses/CalculateIsovists.cpp:399; pstqgis/src/pst/maptools/isovist/isovisttoolwindow.py:463-465; R/isovist.R:101-103; EXECUTED direction 720 and -90 accepted
- finding: rPST is wider than the UI clamp; native-valid.
- tests: test-isovist.R; helper-isovist.R; fixtures/isovist-direct-v3.3.2.R; test-isovist-ulp-allowance.R; risk: none; recommendation: preserve

### IS-009 (D) isovist / perimeter_segments

- native (PSTACreateIsovistContext + PSTACalculateIsovist): accepted (uint; 0 gives PI/0 in CalcRadForSegmentedCircle, CalculateIsovists.cpp:370-374,401-402); QGIS (IsovistAnalysis + IsovistWiz + isovist map tool): hidden: constant 64 (common.py:33); wizard control commented out (isovistwiz.py:82-88); added in the batching commit 25c96d4 (2023-11-08) 'Batching feature for set of predefined view points', no explanation found; rPST: accepted: whole >= 3, default 64
- defaults native/python/rPST: none / 64 / 64
- evidence: pstalgo/src/analyses/CalculateIsovists.cpp:370-374,401-402; pstqgis/src/pst/maptools/isovist/common.py:33; pstqgis/src/pst/ui/wizards/isovistwiz.py:82-88; src/pst-isovist.cpp:205-207; EXECUTED 2 -> REJ, 3 -> ok
- finding: PST-native extension beyond QGIS; the minimum 3 is an rPST safety choice (native meaningless for 0..2). Default equals the application constant.
- tests: test-isovist.R; helper-isovist.R; fixtures/isovist-direct-v3.3.2.R; test-isovist-ulp-allowance.R; risk: none; recommendation: preserve

### IS-010 (D) isovist / visibility outputs (indices per group)

- native (PSTACreateIsovistContext + PSTACalculateIsovist): accepted (CountPerGroup / Indices per obstacle, point and polygon group); QGIS (IsovistAnalysis + IsovistWiz + isovist map tool): QGIS keeps only counts per layer (isovistanalysis.py:84-87); rPST: accepted (index vectors, one-based)
- defaults native/python/rPST: n/a / counts only / index vectors
- evidence: pstalgo/src/analyses/CalculateIsovists.cpp:480-526,860-880; pstqgis/src/pst/analyses/isovistanalysis.py:83-87; R/isovist.R:105-113
- finding: Extension: indices are native outputs unused by the wizard.
- tests: test-isovist.R; helper-isovist.R; fixtures/isovist-direct-v3.3.2.R; test-isovist-ulp-allowance.R; risk: none; recommendation: preserve

### IS-011 (G) isovist / guards for upstream invalid-access states

- native (PSTACreateIsovistContext + PSTACalculateIsovist): upstream reads/writes out of range for empty vertex arrays and for partial-view attraction processing; QGIS (IsovistAnalysis + IsovistWiz + isovist map tool): absent; rPST: controlled R error when PST publishes no handle
- defaults native/python/rPST: n/a / n/a / error
- evidence: R/isovist.R:67-76; src/pst-isovist.cpp:200-252
- finding: Safety guards live in verified generated copies; documented.
- tests: test-isovist.R; helper-isovist.R; fixtures/isovist-direct-v3.3.2.R; test-isovist-ulp-allowance.R; risk: safety; recommendation: preserve

### IS-012 (G) isovist_context_free / context lifecycle

- native (PSTACreateIsovistContext + PSTACalculateIsovist): accepted (PSTAFree); QGIS (IsovistAnalysis + IsovistWiz + isovist map tool): pstalgo.Free in finally (isovistanalysis.py:121-124); rPST: accepted (idempotent; dead pointers rejected)
- defaults native/python/rPST: n/a / n/a / n/a
- evidence: pstqgis/src/pst/analyses/isovistanalysis.py:121-124; src/pst-isovist.cpp:144-186
- finding: Matches.
- tests: test-isovist.R; helper-isovist.R; fixtures/isovist-direct-v3.3.2.R; test-isovist-ulp-allowance.R; risk: safety; recommendation: preserve

### RS-001 (D) compare_line_results / mode = normalized|relative_percent

- native (PSTACompareResults): accepted (Normalized 238-281; RelativePercent 282-337); QGIS (CompareResultsAnalysis + CompareResultsWiz): only normalized: UI radios removed in c0fb690 (2024-10-03) 'Removed calculation option ... Now normalized is used implicitly'; analysis hard-codes NORMALIZED (compareresultsanalysis.py:100); rPST: accepted (both)
- defaults native/python/rPST: Normalized (0) / normalized / normalized
- evidence: pstalgo/src/analyses/CreateBufferPolygons.cpp:238-337; pstqgis/src/pst/analyses/compareresultsanalysis.py:100; pstqgis/src/pst/ui/wizards/compareresultswiz.py:71-94 (commented); pstalgo/python/pstalgo/createbufferpolygons.py:65
- finding: Python/UI-only restriction (C) with history; relative_percent is a PST-native extension, fixture-covered.
- tests: test-raster.R; fixtures/raster-direct-v3.3.2.R (normalized and relative_percent cases); test-sf-raster.R; risk: none; recommendation: preserve

### RS-002 (D) compare_line_results / m (relative-percent floor M)

- native (PSTACompareResults): accepted (only for RelativePercent, header 'M'); QGIS (CompareResultsAnalysis + CompareResultsWiz): hidden (wizard edit commented out, default 1.00, compareresultswiz.py:89-91); rPST: accepted finite native float (default 0)
- defaults native/python/rPST: 0 (struct) / 1 (hidden control) / wrapper M=0 / 0
- evidence: pstalgo/include/pstalgo/analyses/CreateBufferPolygons.h:41; pstalgo/src/analyses/CreateBufferPolygons.cpp:325; pstqgis/src/pst/ui/wizards/compareresultswiz.py:89-91; pstalgo/python/pstalgo/createbufferpolygons.py:65
- finding: Default equals the wrapper default.
- tests: test-raster.R; fixtures/raster-direct-v3.3.2.R (normalized and relative_percent cases); test-sf-raster.R; risk: correctness (M=0 allows division by zero -> Inf/NaN, preserved); recommendation: preserve

### RS-003 (D) compare_line_results / blur_radius (Gaussian sigma)

- native (PSTACompareResults): accepted (BlurRadius, SIGMA_RANGE 3 inflates bbox, CreateBufferPolygons.cpp:207,219); QGIS (CompareResultsAnalysis + CompareResultsWiz): automatic = pixel size * 7, or custom integer >= 1 (compareresultsanalysis.py:145-146; UI validator 0..999999); rPST: accepted >= 0, default 1
- defaults native/python/rPST: none / 70 m with pixel 10 (UI defaults) / 1
- evidence: pstalgo/src/analyses/CreateBufferPolygons.cpp:207,219,247; pstqgis/src/pst/analyses/compareresultsanalysis.py:145-146; pstqgis/src/pst/ui/wizards/compareresultswiz.py:116-130; R/raster.R:79-80
- finding: Application defaults (10 m pixel, 70 m blur) are not reproduced; rPST uses the wrapper defaults (blur 1, resolution = blur). QGIS truncates both to integers >= 1 (UI-only).
- tests: test-raster.R; fixtures/raster-direct-v3.3.2.R (normalized and relative_percent cases); test-sf-raster.R; risk: usability; recommendation: preserve

### RS-004 (G) compare_line_results / resolution (pixel size)

- native (PSTACompareResults): accepted > 0 (division by Resolution, CreateBufferPolygons.cpp:210-211); QGIS (CompareResultsAnalysis + CompareResultsWiz): integer >= 1, default 10 (compareresultsanalysis.py:145; wizard 104); rPST: accepted > 0; default = blur_radius; blur 0 requires explicit resolution
- defaults native/python/rPST: none / 10 / = blur_radius
- evidence: pstalgo/src/analyses/CreateBufferPolygons.cpp:209-211; pstalgo/python/pstalgo/createbufferpolygons.py:81; pstqgis/src/pst/analyses/compareresultsanalysis.py:145; R/raster.R:23-33; EXECUTED blur 0 without resolution -> REJ, with resolution 1 -> 20x20
- finding: Wrapper silently substitutes blur when resolution <= 0; rPST rejects (documented).
- tests: test-raster.R; fixtures/raster-direct-v3.3.2.R (normalized and relative_percent cases); test-sf-raster.R; risk: usability; recommendation: preserve

### RS-005 (G) compare_line_results / y (second layer) / same-layer values

- native (PSTACompareResults): accepted (LineCoords2 NULL uses LineCoords1 with Values2, CreateBufferPolygons.cpp:253-262); QGIS (CompareResultsAnalysis + CompareResultsWiz): available (same table -> second layer None, compareresultsanalysis.py:78,108-116); rPST: accepted
- defaults native/python/rPST: n/a / n/a / NULL
- evidence: pstalgo/src/analyses/CreateBufferPolygons.cpp:253-262,297-306; pstqgis/src/pst/analyses/compareresultsanalysis.py:78,108-116; R/raster.R:70-78
- finding: Matches.
- tests: test-raster.R; fixtures/raster-direct-v3.3.2.R (normalized and relative_percent cases); test-sf-raster.R; risk: none; recommendation: preserve

### RS-006 (G) compare_line_results / lines with exactly two vertices

- native (PSTACompareResults): accepted (LineCoords are endpoint pairs); QGIS (CompareResultsAnalysis + CompareResultsWiz): polylines with > 2 vertices rejected (model.py:304-305); rPST: accepted (matrix rows or two-vertex sf)
- defaults native/python/rPST: n/a / n/a / n/a
- evidence: pstqgis/src/pst/model/model.py:283-305; R/raster.R:5-11
- finding: Matches (rPST also never reduces longer lines).
- tests: test-sf-raster.R; risk: none; recommendation: preserve

### RS-007 (E) compare_line_results / raster dimensions and memory

- native (PSTACompareResults): accepted without bound: width/height from bbox/resolution, malloc(pitch*height) in uint32 (Raster.cpp:37-40; relative_percent allocates a second raster, CreateBufferPolygons.cpp:285-290); QGIS (CompareResultsAnalysis + CompareResultsWiz): UI integer pixel size >= 0..999999 (zero is clamped to 1) -- no cap on raster size; rPST: accepted up to 4 GiB of float pixels (UINT32_MAX/4 pixels); larger rejected
- defaults native/python/rPST: none / none / uint32 byte limit
- evidence: pstalgo/src/Raster.cpp:37-40; pstalgo/src/analyses/CreateBufferPolygons.cpp:225-229,285-290; src/pst-raster.cpp:178-207; R/raster.R:30; EXECUTED resolution 1e-5 -> REJ (overflow guard only)
- finding: Only an arithmetic-overflow guard exists; a request just under 4 GiB (x2 for relative_percent, plus blur buffers) would be attempted. No tests at that scale.
- tests: tiny rasters only; risk: performance/safety (memory); recommendation: investigate (consider a documented size warning; no change to vendor)

### RS-008 (G) compare_line_results / normalised range and zero difference

- native (PSTACompareResults): accepted (division by max abs, inv = 1/max_range = Inf when 0, CreateBufferPolygons.cpp:274-278 -> NaN); QGIS (CompareResultsAnalysis + CompareResultsWiz): same; rPST: preserved (NaN)
- defaults native/python/rPST: n/a / n/a / n/a
- evidence: pstalgo/src/analyses/CreateBufferPolygons.cpp:263-280; R/raster.R:34-40; EXECUTED zero values -> NaN pixels
- finding: Documented upstream quirk preserved without NA policy.
- tests: test-raster.R; fixtures/raster-direct-v3.3.2.R (normalized and relative_percent cases); test-sf-raster.R; risk: correctness (upstream quirk); recommendation: preserve

### RS-009 (D) raster_data / copy of native raster (bbox, dims, pitch, format, min, max, values)

- native (PSTAGetRasterData): accepted; QGIS (CompareResultsAnalysis + CompareResultsWiz): CreateRasterFromPstaHandle -> GDAL raster layer + shader (utils.py:254-); rPST: accepted (R matrix, rows from maximum y)
- defaults native/python/rPST: n/a / n/a / n/a
- evidence: pstalgo/src/Raster.cpp:48-62; pstqgis/src/pst/analyses/utils.py:254-262; R/raster.R:97-110
- finding: Interface extension replaces QGIS raster layer.
- tests: test-raster.R; fixtures/raster-direct-v3.3.2.R (normalized and relative_percent cases); test-sf-raster.R; risk: none; recommendation: preserve

### RS-010 (D) raster_to_polygons / ranges

- native (PSTARasterToPolygons): accepted (arbitrary float ranges, lower-inclusive); QGIS (CompareResultsAnalysis + CompareResultsWiz): fixed 8 ranges derived from RANGES (compareresultsanalysis.py:145-147); rPST: accepted (any matrix of native-float limits, Inf allowed)
- defaults native/python/rPST: n/a / 8 fixed ranges / user supplied
- evidence: pstalgo/include/pstalgo/analyses/RasterToPolygons.h:34-41; pstqgis/src/pst/analyses/compareresultsanalysis.py:12-14,145-147; R/raster.R:127-135
- finding: Extension; QGIS ranges reproducible by passing them.
- tests: test-raster.R; fixtures/raster-direct-v3.3.2.R (normalized and relative_percent cases); test-sf-raster.R; risk: none; recommendation: preserve

### RS-011 (G) raster_free / lifecycle / ownership

- native (PSTACompareResults): accepted (PSTAFree of CCompareResults owning the raster); QGIS (CompareResultsAnalysis + CompareResultsWiz): pstalgo.Free(result1/result2) in finally (compareresultsanalysis.py:210-215); rPST: accepted (idempotent; dead pointer rejected)
- defaults native/python/rPST: n/a / n/a / n/a
- evidence: pstalgo/src/analyses/CreateBufferPolygons.cpp:225-229,342-346; pstqgis/src/pst/analyses/compareresultsanalysis.py:210-215; src/pst-raster.cpp:178-207
- finding: Matches.
- tests: test-raster.R; fixtures/raster-direct-v3.3.2.R (normalized and relative_percent cases); test-sf-raster.R; risk: safety; recommendation: preserve

### IO-001 (D) attraction_reach / attraction_distance / od_betweenness / output_file (Parquet result file, optional arrow >= 25)

- native ((none)): n/a; QGIS (model.writeColumns / createTable): n/a (QGIS writes columns into the layer); rPST: accepted (NULL default)
- defaults native/python/rPST: n/a / n/a / NULL
- evidence: R/attractions.R:94-98,111-119; R/od-betweenness.R:58-66; R/result-file.R
- finding: No QGIS counterpart: extension. Not executed (arrow is not installed in the audit environment).
- tests: test-result-file.R; test-result-axial.R; risk: none; recommendation: preserve

### IO-002 (D) attraction_reach / attraction_distance / od_betweenness / overwrite

- native ((none)): n/a; QGIS ((none)): n/a; rPST: accepted (FALSE default)
- defaults native/python/rPST: n/a / n/a / FALSE
- evidence: R/attractions.R:97-98; R/result-file.R
- finding: Extension.
- tests: test-result-file.R; risk: none; recommendation: preserve

### IO-003 (D) attraction_reach / attraction_distance / spatial_output_file (graph built from FGB/GeoParquet; origin = lines only)

- native ((none)): n/a; QGIS (model.writeColumns(in_network ...) / createTable(*_junctions)): QGIS writes the junction/point/line layers per origin type; rPST: accepted for origin='lines' only; other origins error
- defaults native/python/rPST: n/a / n/a / NULL
- evidence: R/spatial-output.R:83-92; R/attractions.R:103,141; pstqgis/src/pst/analyses/attractionreachanalysis.py:210-225
- finding: Restriction is structural (rows must be 1:1 with source features): points/junction/group origins use output_file.
- tests: test-spatial-output.R; risk: none; recommendation: preserve

### IO-004 (D) od_betweenness / spatial_output_file

- native ((none)): n/a; QGIS (model.writeColumns(network_table ...)): QGIS writes columns into the network layer; rPST: accepted (one result per line, any radius)
- defaults native/python/rPST: n/a / n/a / NULL
- evidence: R/od-betweenness.R:68; R/spatial-output.R:83-92
- finding: Output is per network line so always eligible.
- tests: test-spatial-output.R; risk: none; recommendation: preserve

### IO-005 (D) attraction_reach / attraction_distance / od_betweenness / sf / GeoParquet / FlatGeobuf input controls for attraction_points / origins

- native ((none)): n/a; QGIS ((none)): QGIS reads layers via model.readPoints/readPolygons; rPST: accepted: sf XY POINT/POLYGON; known geographic CRS rejected; CRS compatibility with the graph
- defaults native/python/rPST: n/a / n/a / n/a
- evidence: R/sf.R:78-105; src/pst-graph.cpp:2384-2467; pstqgis/src/pst/model/model.py:340-358
- finding: Extension; polygons keep holes (see AR-019); no reprojection.
- tests: test-sf-analysis-inputs.R; test-sf-graphs.R; risk: none; recommendation: preserve

## Uncertainties
- ShortestPathTraversal.cpp:187 pruning with the parent state's distances was read but not tested.
- Some evidence line ranges for src/pst-isovist.cpp and src/pst-raster.cpp are function-level ranges.
- Blow-up timings depend on random network density; only bounded synthetic networks were run.
- Raster allocation limits (RS-007) were not exercised beyond the uint32 overflow guard.
