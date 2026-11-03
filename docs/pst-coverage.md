# PST coverage and relation to PST for QGIS

Pinned PST: v3.3.2, commit `63df80a2cf3dd289be95ea3d91667c3490719b75`. This page lists which PST exports rPSTool binds, how
they relate to the official PST for QGIS plugin, and what is not exposed. Per-family contracts are in [compatibility](compatibility/); file input and
output is described in [spatial I/O](spatial-io/README.md).

## 0. Classification and evidence

| Category | Meaning | rPSTool treatment |
| --- | --- | --- |
| 1 | PST functionality exposed by QGIS | Reproduce the intended computation; document R interface differences |
| 2 | PST-native functionality hidden or restricted by QGIS | Exposed when implemented, functional, clearly specified, numerically verified and safe; labelled **native extension beyond QGIS** |
| 3 | Incomplete, unsafe or unverified | Not exposed; documented below |

A capability is listed as exposed only when the pinned `.cpp` implementation reads and acts on it and, where feasible, it has
been executed; a header declaration, enum value or descriptor field alone does not count.

**Two authorities.** The pinned PST engine is the authority for what a native routine computes (algorithms, outputs written or
left unwritten, radius and weighting semantics, exported normalisers, descriptor layout). The pinned PST for QGIS (`pstqgis`)
source is the authority for what the official application does with the engine (which buffers feed which normaliser, flags,
defaults and branch structure). Equivalence with PST for QGIS holds only for combinations covered by a source trace or a
recorded comparison, at the evidence level listed below. Intentional differences are in
[QGIS differences](compatibility/qgis-differences.md); suspected application defects are not reproduced.

Evidence labels: **S** static reading of the pinned source; **N** direct execution of the pinned native C API (official ctypes wrapper, or the rPSTool bridge compared with it); **E** genuine `pstqgis` analysis classes run outside QGIS against the
pinned engine; **Q** real QGIS run. **No Q-level evidence exists**; the manual procedure is in
[`tools/validation/qgis-comparison/`](../tools/validation/qgis-comparison/README.md).

Paths: `QG` = `pstqgis/src/pst/` of the pinned PST checkout; `PY` = `pstalgo/python/pstalgo/`; `V` = `src/vendor/pstalgo/`.

## Core analyses

- Axial/crossing-aware `HPSTAGraph`: creation, metadata, Network Integration line outputs, Reach with line or supplied point
  origins, Segment Betweenness with all four exposed primary distances and unweighted/weighted/attraction modes; standard,
  Freeman and syntax normalisation ([core analyses](compatibility/core-network-analyses.md)).
- Endpoint-connected `HPSTASegmentGraph`: creation, Angular Integration (unweighted or length weighted; Turner, syntax and
  Hillier), Angular Choice (unweighted or length weighted; standard, Turner and syntax normalisation), shared radii and the central
  worker cap.

## Further native families

| Family | Pinned exports or descriptor functionality | Native interface / dependency | Status and scope |
| --- | --- | --- | --- |
| 1. Segment groups | `PSTASegmentGrouping`; `PSTACreateSegmentGroupGraph` / `PSTAFreeSegmentGroupGraph`; `PSTASegmentGroupIntegration` | Segment graph → per-segment group/color arrays → group graph → per-group integration/count/depth arrays; walking/steps radii | **Implemented** with the diagnostic-mask/NA policy; see [compatibility](compatibility/segment-groups.md). |
| 2. Axial graph inputs and graph/junction outputs | `PSTACreateGraph` optional unlinks, points, polygon-generated point groups and indexed coordinates; `PSTAGetGraphLineLengths`, `PSTAGetGraphCrossingCoords`; `PSTANetworkIntegration` optional junction coordinates/scores | Existing axial owner, retained native point assignments, caller-owned output arrays | **Implemented.** Indexed endpoints, unlinks, retained points/groups, lengths/crossings and native junction Integration are available; see [axial compatibility](compatibility/axial-inputs-junctions.md). |
| 3. Attraction analyses | `PSTAAttractionReach`, `PSTAAttractionDistance` | Axial graph; line/junction/graph-point/group origins, supplied attractions/polygons; Reach values/decay/distribution/collection; Distance minima/destination indices and custom weighted distances | **Implemented.** Both analyses expose their supported origin, distance, polygon and weighting controls. Only the straight-only Distance + point-group path is rejected (item 3.6); group Reach and network Distance remain available. See [compatibility](compatibility/attractions.md). |
| 4. OD analyses | `PSTAODBetweenness` | Axial graph with destination points; supplied origin coordinates/weights and native destination weights; all-reachable/closest modes | **Implemented**, reusing point/weight validation from family 3. Walking/angular costs, both destination modes, weights and independent limits preserve native semantics; see [OD compatibility](compatibility/od-betweenness.md). |
| 5. Remaining core angular controls | `PSTAAngularIntegration` length weighting and weight/depth-weight outputs; `PSTAAngularIntegrationNormalizeLengthWeight`, `PSTAAngularIntegrationSyntaxNormalize`, `PSTAAngularIntegrationSyntaxNormalizeLengthWeight`, `PSTAAngularIntegrationHillierNormalize`, `PSTAAngularIntegrationHillierNormalizeLengthWeight`; Integration/Choice angle threshold/precision descriptor controls | Existing segment owner and existing analysis/normalization patterns | **Implemented.** Length weighting, native weight/depth-weight outputs, all six Integration normalizers and both analyses' angle controls retain existing defaults; see [compatibility](compatibility/angular-controls.md). |
| 6. Explicit network construction | `PSTACreateJunctions`, `PSTACreateSegmentMap`, `PSTAFree` | Coordinate/index or polyline-section arrays; explicit unlinks and construction thresholds; result arrays owned by returned `IPSTAlgo` handle | **Implemented.** Empty first junction layers are rejected, and a conservative guard rejects detail reduction that would close a segment onto its own start (including some inputs that unmodified PST would process); accepted inputs give the unmodified PST result. See [compatibility](compatibility/network-construction.md). |
| 7. Isovist context/results | `PSTACreateIsovistContext`, `PSTACalculateIsovist`, `PSTAFree` | Grouped obstacle/attraction polygon/point arrays; distinct reusable context and result handles, visibility arrays | **Implemented** with a reusable context and guards that turn unsafe calculated cardinalities into controlled failures. Optional sf group inputs and `output="sf"` are available (see [sf adapters](spatial-io/sf-adapters.md#isovist-adapters)). See [compatibility](compatibility/isovist.md). |
| 8. Raster comparison/geometry results | `PSTACompareResults`, `PSTAGetRasterData`, `PSTARasterToPolygons`, `PSTAFree` | Comparison owns raster state; pitch/format-aware raster inspection; range/ring polygon arrays with native result owners | **Implemented.** The normalised comparison uses the floating absolute value of the extrema consistently across toolchains; genuine zero denominators and native floating behaviour are unchanged. See [compatibility](compatibility/raster.md). |

## Relation to PST for QGIS

### 1. Available in both PST for QGIS and rPSTool (category 1)

| # | Capability | QGIS anchor | rPSTool | Ev |
| --- | --- | --- | --- | --- |
| 1.1 | Network Integration (line outputs I, N, TD; QGIS offers a `steps` radius only) | `QG/analyses/networkintegrationanalysis.py:45-48,101-119` | `network_integration()` | E, N |
| 1.2 | Network Integration junction scores | `networkintegrationanalysis.py:84-86,125-136` (feature fails in QGIS: undefined `column_base_name`; score buffer not zeroed) | `network_integration(junctions = TRUE)`; zero-seeded buffer | E  |
| 1.3 | Reach, line origins and supplied point origins; count, length, area | `reachanalysis.py:44,85,106`; wizard `point_src_available=True` | `network_reach()` | E  |
| 1.4 | Network Betweenness: walking / steps / axmeter; none, length or data weights; none + Standard normalisation | `networkbetweennessanalysis.py:44,119-132,165-171` | `network_betweenness()` | E  |
| 1.5 | Attraction Betweenness (attraction points, weights; walking / steps / angular / axmeter; none + Standard) | `attractionbetweennessanalysis.py:44`; wizard `DIST_MODES` | `network_betweenness(attraction_points=, weights=)` | E  |
| 1.6 | Angular Integration (Turner / syntax / Hillier; unweighted and length-weighted) | `angularintegrationanalysis.py:81-157` | `angular_integration()` | E: 598/598 mappable columns identical |
| 1.7 | Angular Choice (none / Turner / Standard / NACH; unweighted and length-weighted) | `angularchoiceanalysis.py:103-189` | `angular_choice()` | E  |
| 1.8 | Attraction Reach: line / junction / point / point-group origins; polygons; values; decay pow / curve / divide; distribution; collection; non-weight mode = native `Undefined` distance (rPSTool `distance = "none"`) | `attractionreachanalysis.py:45-85,150-205` (non-weight call passes `DistanceType.UNDEFINED`) | `attraction_reach()` | E, N: 61/63 bit-identical, 1 at 1.2e-7 thread noise, 1 intended default difference |
| 1.9 | Attraction Distance: minimum distance for straight / walking / steps / angular / custom weights; point-connection cost | `attractiondistanceanalysis.py:47,148-191`; wizard offers weights via "Attribute-based cost" | `attraction_distance()` | E  |
| 1.10 | Origin-Destination Betweenness: walking / angular route, all / closest destination, origin and destination weights, straight / walking / angular radii | `odbetweennessanalysis.py:40-75`; `odbetweennesswiz.py:136` | `od_betweenness()` | E  |
| 1.11 | Create Segment Map (axial-or-segment, road-centre-lines incl. unlink output) | `createsegmentmapanalysis.py:64-85,139` | `create_segment_map()` | E  |
| 1.12 | Create Junctions (+ unlinks) | `createjunctionsanalysis.py:77-90` (plugin unlink option reported broken) | `create_junctions()` | E  |
| 1.13 | Compare Results (normalised mode) and ranges to polygons | `compareresultsanalysis.py:100,146-175` | `compare_line_results()`, `raster_data()`, `raster_to_polygons()` (`R/raster.R`) | E, N ([raster](compatibility/raster.md)) |
| 1.14 | Graph services used internally by QGIS: axial graph, segment graph, line lengths, crossing coordinates, `StandardNormalize` | `analyses/utils.py:103-216` | `axial_graph()`, `segment_graph()`, `axial_line_lengths()`, `axial_crossing_coords()` | E  |

**Intentional rPSTool differences within Category 1** (computation is the same engine; the interface or a defect differs):

| Difference | QGIS | rPSTool |
| --- | --- | --- |
| Unweighted Angular Choice angle controls | `angularchoiceanalysis.py:154-161` forgets to forward `angle_threshold` / `angle_precision` (weighted branch forwards, `:107-108`) | forwards both (N: threshold 10 changes 83/91 values) |
| Create Segment Map `extrude` | `extrude = snap` (`createsegmentmapanalysis.py:85`) | default `0` |
| Polygon attractions with holes | outer ring only (`model.py:340-366`) | all rings (see `?attraction_reach`) (N: distance 1 vs 3) |
| Attraction Reach nonconstant decay constant | wizard default 1 | `decay_constant = NULL` means 1 for `"power"`, `"curve"`, `"divide"` (0 for `"constant"`); explicit values are passed unchanged |
| Unusable input | silently skipped features; free-text radii; any CRS | error naming the offender; strict radius / precision validation; known geographic CRS rejected ([sf adapters](spatial-io/sf-adapters.md)) |
| Unwritten / garbage outputs | uninitialised stack memory shown for zero-weight Betweenness origins, point-group straight Distance | `NA` (Betweenness diagnostics) or error |
| Safety guards | no guard for >32 segments at one point (engine mis-counts: 40-segment star gives N=33) | rejects |
| Conveniences computed in Python only | mean depth `TD/(N-1)`, Reach area units, "length weights" switch, attribute filtering (`value > 0`) | not provided; user recipe |
| Defaults | wizard defaults walking (Betweenness, Attraction Distance) | `distance = "steps"` |
| Batch orchestration | loops over radii x distances x weights x columns | one weight mode / distance per call; several radii in one call only for the angular analyses ([multi-radius](compatibility/multi-radius.md)) |

Figures marked N (for example 83 of 91 values) come from comparing rPSTool with direct calls of the pinned native C API on small test networks; figures marked E (598/598 columns, 61/63 values) come from running the `pstqgis` analysis classes outside QGIS against the same engine.

### 2. Native extensions beyond PST for QGIS (category 2)

| # | Capability | How QGIS restricts it | rPSTool surface | Ev |
| --- | --- | --- | --- | --- |
| 2.1 | **Combined (AND) radius objects** for Reach, Network / Attraction Betweenness, OD, Attraction Reach (non-weight) | `RadiiFromSettings(...).split()` runs each ticked radius type separately (`reachanalysis.py:44`, `networkbetweennessanalysis.py:44`, `attractionbetweennessanalysis.py:44`, `odbetweennessanalysis.py:57`, `attractionreachanalysis.py:50`). Angular analyses and Attraction Distance are not restricted. Example: Reach counts differ by up to 20 of 23 lines between "w100 + s2" columns and one combined run | `analysis_radius(walking=, steps=, ...)` in one call | N (Reach, Integration, Betweenness combined bit-identical to native), E |
| 2.2 | Network Integration with walking / straight / angular / axmeter radii and combined radii | wizard `RadiusType.STEPS` only (`networkintegrationwiz.py:34`) | `network_integration(radius=)` restricted to steps (rejects the other limits, as the official interface does) | S, E |
| 2.3 | Network Betweenness with **angular** distance | wizard `DIST_MODES` walking / steps / axmeter only (`networkbetweennesswiz.py:50-54`; angular exists only in Attraction Betweenness) | `network_betweenness(distance = "angular")` | N: bit-identical |
| 2.4 | **Freeman** (`PSTABetweennessNormalize`) and **syntax** (`PSTABetweennessSyntaxNormalize`) betweenness normalisers | QGIS offers none + Standard only (`networkbetweennesswiz.py:55-58`); the two exports are never called by the plugin | `network_betweenness(normalization = "freeman" / "syntax")` | N (Freeman). Weighted runs are normalised with the only (unweighted) N / TD PST supplies (`V/src/analyses/SegmentBetweenness.cpp:570`) |
| 2.5 | Unrestricted (no-radius) Reach / Betweenness | empty radius list = zero analyses, silent no-op | `analysis_radius()` default | E |
| 2.6 | OD Betweenness `steps` radius | wizard offers straight / walking / angular only | `analysis_radius(steps=)` | N: result changes with `steps = 1` |
| 2.7 | Diagnostic outputs: Betweenness / Choice / Integration `node_count`, `total_depth`, `total_depth_weight`, `total_weight` (`weight_outputs`); Reach always count + length + area | written per user tick, some only for the first weight mode | always returned (`R/core-analyses.R`, `R/angular-integration.R:64`) | N (probe: column sets listed from rPSTool), E |
| 2.8 | Attraction Distance **destination indices** | read internally only to copy an attribute, never written (`attractiondistanceanalysis.py:128-191`) | raw zero-based `destination_index` (-1 = none) | E |
| 2.9 | Segment Grouping, Segment Group Integration | wizards and analyses exist; menu entries are appended to `ACTIONS` after the action list is built (`QG/main.py:155-160`), so they appear unreachable (S only; Q not run) | `segment_grouping()`, `segment_group_graph()`, `segment_group_integration()` (`R/segment-groups.R`) | E |
| 2.10 | Isovist: context, field of view, direction, perimeter segments, visible-object indices, area | wizard commented out (`QG/main.py:137`), map tool disabled (`ENABLE_MAP_TOOLS = False`, `:40`) | `isovist_context()`, `isovist()` (`R/isovist.R`) | E, N ([isovist](compatibility/isovist.md)) |
| 2.11 | Compare Results **relative-percent** mode, `M`, arbitrary ranges | hard-coded `NORMALIZED` (`compareresultsanalysis.py:100`, other mode commented out) | `compare_line_results(mode = "relative_percent", m=)` | N ([raster](compatibility/raster.md): 41 relative-percent controls) |
| 2.12 | Graph-retained points / polygon point groups usable as origins and OD destinations; indexed line input; unlinks on graph and junction creation | QGIS builds points per analysis | `axial_graph(points=, points_per_polygon=, unlinks=, line_indices=)` | E |
| 2.13 | Angular Choice / Integration length-weighted extra arrays (`total_depth_weight`, `total_weight`) | internal use only | returned | E |

### 3. Not exposed (category 3)

Incomplete, unsafe or unverified PST functionality, and PST for QGIS features that are not PST engine capabilities:

| # | Item | Evidence | rPSTool behaviour |
| --- | --- | --- | --- |
| 3.1 | **Fast Segment Betweenness** (QGIS menu "Angular Betweenness", `QG/main.py:130`, `angularbetweennessanalysis.py:101`) | S: the header (`V/include/pstalgo/experimental/FastSegmentBetweenness.h:33-48`) says angular distance only, walking radius only, weighting / count / depth "NOT YET SUPPORTED"; the `.cpp` ignores `m_DistanceType`, reads only `Walking()`, writes count / depth / weights, rounds angles to integers, and spawns `hardware_concurrency()` workers (outside the rPSTool worker cap). N: on a 60-segment network `steps=1` and `angular=10` change nothing; `walking=25` changes choice by up to 209 units; it disagrees with Angular Choice even unrestricted (max abs 233, up to 50 % relative). The routine is experimental, its header, implementation and results disagree, and it is sensitive to segment ordering and worker count | not exposed; use `angular_choice()` |
| 3.2 | Visual Connectivity (`PSTAVisualConnectivity`) | S: validates descriptor then `return nullptr` (`V/src/analyses/VisualConnectivity.cpp:27-35`); no upstream test | not exposed |
| 3.3 | Deprecated `PSTACalculateIsovists` (plural) | S: declaration and implementation are commented out (`CalculateIsovists.h:117-159`, `CalculateIsovists.cpp:1020-1042`); no active export | not exposed |
| 3.4 | `axmeter` radius in Angular Integration / Choice | S: `AngularChoiceAlgo.cpp:449-452` reads straight, walking, angular and steps only. E: plugin result with `axmeter = 20` equals `0.001`, i.e. unrestricted | rejected |
| 3.5 | `axmeter` distance / radius in Attraction Distance | S: supported mask is walking / steps / angular / weights (`V/src/experimental/DirectedMultiDistanceGraph.cpp:112-117`); E: QGIS option always fails | rejected |
| 3.6 | Attraction Distance, straight-only, point-group origins | S: group outputs never written on the special path (`AttractionDistance.cpp:341-350`); E: QGIS shows junk | rejected |
| 3.7 | `m_ScoreAccumulationMode` (Sum / Max) in Attraction Reach | S: marked `DEPRECATED: TODO: Remove`; `m_ScoreAccumulationMode` is never read in `V/src` (grep). Wrapper hard-codes SUM (`PY/attractionreach.py:135`) | not exposed |
| 3.8 | Segment Group Integration straight / angular / axmeter radii | S: only walking and steps are tested (`SegmentGroupIntegration.cpp:46-47,82`). N: rPSTool rejects | rejected |
| 3.9 | Segment Betweenness `straight` / `weights` distances | S: whitelist is walking / steps / angular / axmeter (`SegmentBetweenness.cpp:606-612`) | rejected at R level |
| 3.10 | **OD Betweenness `axmeter` radius** | S: `ODBetweenness.cpp` never reads it. N: result with `axmeter = 0.001` is identical to no radius | **Rejected**: `od_betweenness()` raises an error for an axmeter radius because the pinned algorithm ignores it ([OD Betweenness](compatibility/od-betweenness.md)). |
| 3.11 | Segment graph with more than 32 segments at one coordinate | S: only `ASSERT(index < 32)` (`AngularChoiceAlgo.cpp:98-99`). E: wrong N | rejected |
| 3.12 | Segment-map detail reduction that closes a segment onto its own start | [network construction](compatibility/network-construction.md) | conservative guard |
| 3.13 | Split Polylines | S: `QG/analyses/splitpolylinesanalysis.py` uses QGIS geometry only, no `pstalgo` call; menu entry commented out | not a PST engine capability |

#### Not provided: callbacks and Python-side conveniences

* **User-defined progress callbacks and cancellation** are not exposed, and the **native log callback**
  (`PSTARegisterLogCallback`) is not bound. rPSTool uses PST's progress callback only for the console line described in
  [progress display](progress.md) (see also [architecture](architecture.md#threading-and-progress)). Errors surface as R errors.
* **QGIS-side conveniences** computed in Python only (mean depth `TD/(N-1)`, Reach area units, "length weights" switch,
  attribute filtering) are not provided: they are one-line R computations on the returned columns, not PST computations.
  Area differs from the plugin only by float32 rounding.
