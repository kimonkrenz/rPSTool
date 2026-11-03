# PST coverage and relation to PST for QGIS

Pinned PST: v3.3.2, commit `63df80a2cf3dd289be95ea3d91667c3490719b75`. This page lists which PST exports rPSTool binds, how
they relate to the official PST for QGIS plugin, and what is not exposed. Per-family contracts are in [compatibility](compatibility/); file input and
output is described in [spatial I/O](spatial-io/README.md).

## How the three layers relate

* **Native engine.** The pinned PST engine (`pstalgo`) defines what each routine computes: algorithms, outputs written or left
  unwritten, radius and weighting semantics, exported normalisers and descriptor layout.
* **PST for QGIS.** The plugin (`pstqgis`) defines what the official application does with the engine: which buffers feed which
  normaliser, flags, defaults and branch structure. Combinations the plugin does not offer are listed below.
* **rPSTool.** Binds a subset of the engine, mostly matching the plugin, with intentional differences
  ([QGIS differences](compatibility/qgis-differences.md)) and a few capabilities the plugin hides. Suspected plugin defects are not reproduced.

A capability is listed as available only when the pinned `.cpp` implementation reads and acts on it; a header declaration, enum
value or descriptor field alone does not count. Source anchors below use these paths: `QG` = `pstqgis/src/pst/` of the pinned PST
checkout; `PY` = `pstalgo/python/pstalgo/`; `V` = `src/vendor/pstalgo/`. Equivalence with the plugin has not been confirmed by a
run inside QGIS; a manual procedure is in [`tools/validation/qgis-comparison/`](../tools/validation/qgis-comparison/README.md).

## What rPSTool provides

- Axial/crossing-aware `HPSTAGraph`: creation, metadata, Network Integration line outputs, Reach with line or supplied point
  origins, Segment Betweenness with all four exposed primary distances and unweighted/weighted/attraction modes; standard,
  Freeman and syntax normalisation ([core analyses](compatibility/core-network-analyses.md)).
- Endpoint-connected `HPSTASegmentGraph`: creation, Angular Integration (unweighted or length weighted; Turner, syntax and
  Hillier), Angular Choice (unweighted or length weighted; standard, Turner and syntax normalisation), shared radii and the central
  worker cap.

### Further native families

| Family | Pinned exports or descriptor functionality | Native interface / dependency | Scope |
| --- | --- | --- | --- |
| 1. Segment groups | `PSTASegmentGrouping`; `PSTACreateSegmentGroupGraph` / `PSTAFreeSegmentGroupGraph`; `PSTASegmentGroupIntegration` | Segment graph → per-segment group/color arrays → group graph → per-group integration/count/depth arrays; walking/steps radii | Includes the diagnostic-mask/NA policy; see [compatibility](compatibility/segment-groups.md). |
| 2. Axial graph inputs and graph/junction outputs | `PSTACreateGraph` optional unlinks, points, polygon-generated point groups and indexed coordinates; `PSTAGetGraphLineLengths`, `PSTAGetGraphCrossingCoords`; `PSTANetworkIntegration` optional junction coordinates/scores | Existing axial owner, retained native point assignments, caller-owned output arrays | Indexed endpoints, unlinks, retained points/groups, lengths/crossings and native junction Integration are available; see [axial compatibility](compatibility/axial-inputs-junctions.md). |
| 3. Attraction analyses | `PSTAAttractionReach`, `PSTAAttractionDistance` | Axial graph; line/junction/graph-point/group origins, supplied attractions/polygons; Reach values/decay/distribution/collection; Distance minima/destination indices and custom weighted distances | Both analyses expose their supported origin, distance, polygon and weighting controls. Attraction Distance rejects a few combinations before the native call (listed in the compatibility page); group Reach and network Distance remain available. See [compatibility](compatibility/attractions.md). |
| 4. OD analyses | `PSTAODBetweenness` | Axial graph with destination points; supplied origin coordinates/weights and native destination weights; all-reachable/closest modes | Reuses point/weight validation from family 3. Walking/angular costs, both destination modes, weights and independent limits preserve native semantics; see [OD compatibility](compatibility/od-betweenness.md). |
| 5. Remaining core angular controls | `PSTAAngularIntegration` length weighting and weight/depth-weight outputs; `PSTAAngularIntegrationNormalizeLengthWeight`, `PSTAAngularIntegrationSyntaxNormalize`, `PSTAAngularIntegrationSyntaxNormalizeLengthWeight`, `PSTAAngularIntegrationHillierNormalize`, `PSTAAngularIntegrationHillierNormalizeLengthWeight`; Integration/Choice angle threshold/precision descriptor controls | Existing segment owner and existing analysis/normalization patterns | Length weighting, native weight/depth-weight outputs, all six Integration normalizers and both analyses' angle controls retain existing defaults; see [compatibility](compatibility/angular-controls.md). |
| 6. Explicit network construction | `PSTACreateJunctions`, `PSTACreateSegmentMap`, `PSTAFree` | Coordinate/index or polyline-section arrays; explicit unlinks and construction thresholds; result arrays owned by returned `IPSTAlgo` handle | Empty first junction layers are rejected, and a conservative guard rejects detail reduction that would close a segment onto its own start (including some inputs that unmodified PST would process); accepted inputs give the unmodified PST result. See [compatibility](compatibility/network-construction.md). |
| 7. Isovist context/results | `PSTACreateIsovistContext`, `PSTACalculateIsovist`, `PSTAFree` | Grouped obstacle/attraction polygon/point arrays; distinct reusable context and result handles, visibility arrays | Provides a reusable context and guards that turn unsafe calculated cardinalities into controlled failures. Optional sf group inputs and `output="sf"` are available (see [sf adapters](spatial-io/sf-adapters.md#isovist-adapters)). See [compatibility](compatibility/isovist.md). |
| 8. Raster comparison/geometry results | `PSTACompareResults`, `PSTAGetRasterData`, `PSTARasterToPolygons`, `PSTAFree` | Comparison owns raster state; pitch/format-aware raster inspection; range/ring polygon arrays with native result owners | The normalised comparison uses the floating absolute value of the extrema consistently across toolchains; genuine zero denominators and native floating behaviour are unchanged. See [compatibility](compatibility/raster.md). |

## Available in both PST for QGIS and rPSTool

| # | Capability | QGIS anchor | rPSTool |
| --- | --- | --- | --- |
| 1.1 | Network Integration (line outputs I, N, TD; QGIS offers a `steps` radius only) | `QG/analyses/networkintegrationanalysis.py:45-48,101-119` | `network_integration()` |
| 1.2 | Network Integration junction scores | `networkintegrationanalysis.py:84-86,125-136` (feature fails in QGIS: undefined `column_base_name`; score buffer not zeroed) | `network_integration(junctions = TRUE)`; zero-seeded buffer |
| 1.3 | Reach, line origins and supplied point origins; count, length, area | `reachanalysis.py:44,85,106`; wizard `point_src_available=True` | `network_reach()` |
| 1.4 | Network Betweenness: walking / steps / axmeter; none, length or data weights; none + Standard normalisation | `networkbetweennessanalysis.py:44,119-132,165-171` | `network_betweenness()` |
| 1.5 | Attraction Betweenness (attraction points, weights; walking / steps / angular / axmeter; none + Standard) | `attractionbetweennessanalysis.py:44`; wizard `DIST_MODES` | `network_betweenness(attraction_points=, weights=)` |
| 1.6 | Angular Integration (Turner / syntax / Hillier; unweighted and length-weighted) | `angularintegrationanalysis.py:81-157` | `angular_integration()` |
| 1.7 | Angular Choice (none / Turner / Standard / NACH; unweighted and length-weighted) | `angularchoiceanalysis.py:103-189` | `angular_choice()` |
| 1.8 | Attraction Reach: line / junction / point / point-group origins; polygons; values; decay pow / curve / divide; distribution; collection; non-weight mode = native `Undefined` distance (rPSTool `distance = "none"`) | `attractionreachanalysis.py:45-85,150-205` (non-weight call passes `DistanceType.UNDEFINED`) | `attraction_reach()` |
| 1.9 | Attraction Distance: minimum distance for straight / walking / steps / angular / custom weights; point-connection cost | `attractiondistanceanalysis.py:47,148-191`; wizard offers weights via "Attribute-based cost" | `attraction_distance()` |
| 1.10 | Origin-Destination Betweenness: walking / angular route, all / closest destination, origin and destination weights, straight / walking / angular radii | `odbetweennessanalysis.py:40-75`; `odbetweennesswiz.py:136` | `od_betweenness()` |
| 1.11 | Create Segment Map (axial-or-segment, road-centre-lines incl. unlink output) | `createsegmentmapanalysis.py:64-85,139` | `create_segment_map()` |
| 1.12 | Create Junctions (+ unlinks) | `createjunctionsanalysis.py:77-90` (plugin unlink option reported broken) | `create_junctions()` |
| 1.13 | Compare Results (normalised mode) and ranges to polygons | `compareresultsanalysis.py:100,146-175` | `compare_line_results()`, `raster_data()`, `raster_to_polygons()` (`R/raster.R`) |
| 1.14 | Graph services used internally by QGIS: axial graph, segment graph, line lengths, crossing coordinates, `StandardNormalize` | `analyses/utils.py:103-216` | `axial_graph()`, `segment_graph()`, `axial_line_lengths()`, `axial_crossing_coords()` |

### Intentional differences

The computation is the same engine; the interface or a plugin defect differs.

| Difference | QGIS | rPSTool |
| --- | --- | --- |
| Unweighted Angular Choice angle controls | `angularchoiceanalysis.py:154-161` forgets to forward `angle_threshold` / `angle_precision` (weighted branch forwards, `:107-108`) | forwards both, so a threshold changes the result |
| Create Segment Map `extrude` | `extrude = snap` (`createsegmentmapanalysis.py:85`) | default `0` |
| Polygon attractions with holes | outer ring only (`model.py:340-366`) | all rings (see `?attraction_reach`) |
| Attraction Reach nonconstant decay constant | wizard default 1 | `decay_constant = NULL` means 1 for `"power"`, `"curve"`, `"divide"` (0 for `"constant"`); explicit values are passed unchanged |
| Unusable input | silently skipped features; free-text radii; any CRS | error naming the offender; strict radius / precision validation; known geographic CRS rejected ([sf adapters](spatial-io/sf-adapters.md)) |
| Unwritten / garbage outputs | uninitialised stack memory shown for zero-weight Betweenness origins, point-group straight Distance | `NA` (Betweenness diagnostics) or error |
| Safety guards | no guard for more than 32 segments at one point (the engine mis-counts) | rejects |
| Conveniences computed in Python only | mean depth `TD/(N-1)`, Reach area units, "length weights" switch, attribute filtering (`value > 0`) | not provided; user recipe |
| Defaults | wizard defaults walking (Betweenness, Attraction Distance) | `distance = "steps"` |
| Batch orchestration | loops over radii x distances x weights x columns | one weight mode / distance per call; several radii in one call only for the angular analyses ([multi-radius](compatibility/multi-radius.md)) |


## Available in rPSTool but hidden or restricted in PST for QGIS

The plugin hides or restricts the following engine capabilities; each is available in rPSTool unless noted. Network Integration with metric radii is not among them (see the next section).

| # | Capability | How QGIS restricts it | rPSTool surface |
| --- | --- | --- | --- |
| 2.1 | **Combined (AND) radius objects** for Reach, Network / Attraction Betweenness, OD, Attraction Reach (non-weight) | `RadiiFromSettings(...).split()` runs each ticked radius type as a separate analysis (`reachanalysis.py:44`, `networkbetweennessanalysis.py:44`, `attractionbetweennessanalysis.py:44`, `odbetweennessanalysis.py:57`, `attractionreachanalysis.py:50`). Angular analyses and Attraction Distance are not restricted | `analysis_radius(walking=, steps=, ...)` applies all its limits together in one call. Not available for Network Integration (steps only) |
| 2.2 | Network Betweenness with **angular** distance | wizard `DIST_MODES` walking / steps / axmeter only (`networkbetweennesswiz.py:50-54`; angular exists only in Attraction Betweenness) | `network_betweenness(distance = "angular")` |
| 2.3 | **Freeman** (`PSTABetweennessNormalize`) and **syntax** (`PSTABetweennessSyntaxNormalize`) betweenness normalisers | QGIS offers none + Standard only (`networkbetweennesswiz.py:55-58`); the two exports are never called by the plugin | `network_betweenness(normalization = "freeman" / "syntax")` |
| 2.4 | Unrestricted (no-radius) Reach / Betweenness | empty radius list = zero analyses, silent no-op | `analysis_radius()` default |
| 2.5 | OD Betweenness `steps` radius | wizard offers straight / walking / angular only | `analysis_radius(steps=)` |
| 2.6 | Diagnostic outputs: node count, total depth and, for the angular analyses, the length-weighted depth and weight arrays (`weight_outputs`); Reach always count + length + area | written per user tick, some only for the first weight mode | always returned as the generated `nc_`, `td_`, `tdw_` and `tw_` columns ([output naming](output-naming.md)) |
| 2.7 | Attraction Distance **destination indices** | read internally only to copy an attribute, never written (`attractiondistanceanalysis.py:128-191`) | raw zero-based destination index (`di_...`, -1 = none) |
| 2.8 | Segment Grouping, Segment Group Integration | wizards and analyses exist; menu entries are appended to `ACTIONS` after the action list is built (`QG/main.py:155-160`), so they appear unreachable (source reading only; not run in QGIS) | `segment_grouping()`, `segment_group_graph()`, `segment_group_integration()` (`R/segment-groups.R`) |
| 2.9 | Isovist: context, field of view, direction, perimeter segments, visible-object indices, area | wizard commented out (`QG/main.py:137`), map tool disabled (`ENABLE_MAP_TOOLS = False`, `:40`) | `isovist_context()`, `isovist()` (`R/isovist.R`) |
| 2.10 | Compare Results **relative-percent** mode, `M`, arbitrary ranges | hard-coded `NORMALIZED` (`compareresultsanalysis.py:100`, other mode commented out) | `compare_line_results(mode = "relative_percent", m=)` |
| 2.11 | Graph-retained points / polygon point groups usable as origins and OD destinations; indexed line input; unlinks on graph and junction creation | QGIS builds points per analysis | `axial_graph(points=, points_per_polygon=, unlinks=, line_indices=)` |

## Not exposed or restricted in rPSTool

Engine functionality that is incomplete or unsafe, engine functionality that neither PST for QGIS nor rPSTool offers, and
plugin features that are not engine capabilities:

| Item | Reason | rPSTool behaviour |
| --- | --- | --- |
| **Network Integration with walking, straight, angular or axmeter radii, or combined radii** | The engine accepts them, but PST for QGIS offers a steps radius only (`networkintegrationwiz.py:34`) and rPSTool follows the plugin: `network_integration()` takes `steps` or no radius. | Other limits rejected before any calculation. For metric radii use `angular_integration()` on a segment graph. |
| **Fast Segment Betweenness** (QGIS menu "Angular Betweenness", `QG/main.py:130`, `angularbetweennessanalysis.py:101`) | Experimental in PST: the header (`V/include/pstalgo/experimental/FastSegmentBetweenness.h:33-48`) says angular distance only, walking radius only, weighting / count / depth "NOT YET SUPPORTED"; the `.cpp` ignores `m_DistanceType`, reads only `Walking()`, rounds angles to integers and spawns `hardware_concurrency()` workers (outside the rPSTool worker cap). Header, implementation and results disagree, and results depend on segment order and worker count. | Not exposed; use `angular_choice()`. |
| Visual Connectivity (`PSTAVisualConnectivity`) | The routine validates its descriptor and then returns `nullptr` (`V/src/analyses/VisualConnectivity.cpp:27-35`). | Not exposed. |
| Deprecated `PSTACalculateIsovists` (plural) | Declaration and implementation are commented out (`CalculateIsovists.h:117-159`, `CalculateIsovists.cpp:1020-1042`); there is no active export. | Not exposed. |
| `axmeter` radius in Angular Integration / Choice | `AngularChoiceAlgo.cpp:449-452` reads straight, walking, angular and steps limits only, so an axmeter limit would be silently ignored. | Rejected. |
| `axmeter` distance or radius in Attraction Distance | The supported mask is walking / steps / angular / weights (`V/src/experimental/DirectedMultiDistanceGraph.cpp:112-117`). | Rejected ([attractions](compatibility/attractions.md)). |
| Attraction Distance with straight distance and point-group origins | Group outputs are never written on the straight-only path (`AttractionDistance.cpp:341-350`). | Rejected ([attractions](compatibility/attractions.md)). |
| `m_ScoreAccumulationMode` (Sum / Max) in Attraction Reach | Marked `DEPRECATED: TODO: Remove` and never read in `V/src`; the Python wrapper hard-codes SUM (`PY/attractionreach.py:135`). | Not exposed. |
| Segment Group Integration straight / angular / axmeter radii | Only walking and steps are handled (`SegmentGroupIntegration.cpp:46-47,82`). | Rejected. |
| Segment Betweenness `straight` / `weights` distances | The whitelist is walking / steps / angular / axmeter (`SegmentBetweenness.cpp:606-612`). | Rejected at R level. |
| OD Betweenness `axmeter` radius | `ODBetweenness.cpp` never reads it, so the limit would have no effect. | Rejected ([OD Betweenness](compatibility/od-betweenness.md)). |
| Segment graph with more than 32 segments at one coordinate | The engine only has `ASSERT(index < 32)` (`AngularChoiceAlgo.cpp:98-99`) and would mis-count. | Rejected. |
| Segment-map detail reduction that closes a segment onto its own start | See [network construction](compatibility/network-construction.md). | Conservative guard. |
| Split Polylines | `QG/analyses/splitpolylinesanalysis.py` uses QGIS geometry only and makes no `pstalgo` call; its menu entry is commented out. | Not a PST engine capability. |

## Not provided: callbacks and Python-side conveniences

* **User-defined progress callbacks and cancellation** are not exposed, and the **native log callback**
  (`PSTARegisterLogCallback`) is not bound. rPSTool uses PST's progress callback only for the console line described in
  [progress display](progress.md) (see also [architecture](architecture.md#threading-and-progress)). Errors surface as R errors.
* **QGIS-side conveniences** computed in Python only (mean depth `TD/(N-1)`, Reach area units, "length weights" switch,
  attribute filtering) are not provided: they are one-line R computations on the returned columns, not PST computations.
  Area differs from the plugin only by float32 rounding.
