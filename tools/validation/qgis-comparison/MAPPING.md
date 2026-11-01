# PST for QGIS v3.3.2  →  rPSTool mapping

Source: `pstqgis/src/pst/**` of the pinned PST checkout (commit `63df80a2cf3dd289be95ea3d91667c3490719b75`, tag v3.3.2; `metadata.txt: version=3.3.2`)
read file by file; rPSTool signatures from `R/*.R`. Cells were checked against the plugin source (S) and, in an earlier audit, by running the
plugin's Python analysis classes against the pinned engine outside QGIS (E). **Nothing here was observed in a real QGIS (Q): no Q-level validation has been performed.**
It is the reference for choosing equivalent settings in a manual comparison; it does not
generate expectations. The comparison evidence is the QGIS export that the maintainer produces (see `GUI-PROCEDURE.md`).

Notation: `P` = the plugin `props` dict (the keys the wizards set); "dtype" = type string the plugin passes to `writeColumns`
(`float` → QGIS *Double* field, `integer` → *Integer* field; values are float32 results widened to Python floats, i.e. exactly representable doubles).

## 0. How the plugin reads and writes data (applies to every analysis)

| Topic | Plugin behaviour (file) | rPSTool / consequence |
|---|---|---|
| Row identity | Results are written back by QGIS **feature id** (`feature.id()`, = `fid` for GeoPackage, 0-based row for shapefile) via `dataProvider.changeAttributeValues` (`model.py:writeColumns`). The plugin has no notion of a user id field. | rPSTool returns native `1..N` indices in file order. The comparison joins on an integer attribute (`seg_id`, `pt_id`, …) that both sides read from the same file; it never trusts `fid` or row order. |
| Lines | `readLines`: features whose geometry is not a line are **silently skipped**; a line with **>2 vertices raises** ("polyline geometry … not supported"); a MultiLineString with exactly one part is accepted, with more than one raises. Coordinates are taken as stored, in the layer CRS, **CRS is never inspected** (geographic CRS accepted). | rPSTool accepts only 2-vertex single-part LineStrings and rejects geographic CRS. Test data satisfies both. |
| Points | `readPoints`: `geometry.centroid()` of every feature with a geometry (features without geometry skipped). | rPSTool: `st_coordinates` of POINT features. Identical for point layers. |
| Polygons | `readPolygons`: **outer ring only** (holes ignored), closing vertex dropped; a MultiPolygon with ≠1 part raises. | rPSTool with sf POLYGON input samples EVERY ring (holes included, NaN-separated) - decision 4: rPSTool keeps all rings. Equivalence is established on the geometry actually submitted to PST: cases AD04, AD05, AR02, AR03 replay the plugin's outer-ring arrays through rPSTool (identical), and assert in addition what changes when the hole ring is submitted. The plugin's `readPolygons`/`readPoints` also take polygon centroids from QGIS (`g.centroid()`), which the in-memory model approximates for rectangles only. Non-line features, features with fewer than 2 vertices and null geometries are skipped silently by `readLines` (0.2e). |
| Float narrowing | Output vectors are `c_float`; radii are `c_float` (steps `c_uint`); weights/attraction values are `c_float`. | Same native narrowing happens inside PST/rPSTool. |
| Coordinates | No origin shift, no unit conversion, no snapping, no splitting happen in Python. PST centres coordinates internally (same in rPSTool). | – |
| Output fields | New field per `(name, dtype)` if the name does not exist, otherwise **silently overwritten**. Field *length* limits of the format apply (shapefile: 10 chars → plugin raises "column name was probably cut… save as tab file"). | Use GeoPackage. |
| Radii | `RadiiFromSettings` builds ONE combined `Radii` (all ticked types at once) – used unsplit by Angular Integration, Angular Choice, Attraction Distance; `.split()` (one analysis per ticked type, in the order straight, walking, steps, angular, axmeter) by Reach, Network Betweenness, Attraction Betweenness, OD Betweenness, Segment Group Integration and - in non-weight mode - Attraction Reach (0.8c); Angular Betweenness also uses the unsplit radii; Network Integration builds its own steps-only `Radii`. **If nothing is ticked, `.split()` is empty and those analyses silently do nothing.** | `analysis_radius(...)` with several fields set = one combined radius (same as plugin "combined"); the tool calls rPSTool once per split radius. |
| Name building | `GenColName` (`columnnaming.py`): `analysis + dist + radii + decay + weight + norm + extra + unit`; radius text `l<straight>` `w<walking>` `s<steps>` `a<angular>` `am<axmeter>`; value rendered by `int()` (**fraction truncated**), multiples of 1000 become `k` (1000 → `1k`). Distance codes `sl w s a am dw`. Names do **not** encode angle threshold/precision, unlink layer, weight column set or destination layer. | Reimplemented in `lib/plan.R` (`col_name`, unit-tested). |

## 1. Summary

| QGIS menu (Vector ▸ PST ▸) | Plugin class | pstalgo call(s) | rPSTool function | Graph family | Comparison status |
|---|---|---|---|---|---|
| Network Integration | `NetworkIntegrationAnalysis` | `NetworkIntegration` | `network_integration(g, steps)` | axial `pst_graph` | compared (R01, R02) |
| Reach | `ReachAnalysis` | `Reach` | `network_reach(g, radius, origins)` | axial | compared (R01–R03) |
| Network Betweenness | `NetworkBetweennessAnalysis` | `SegmentBetweenness`, `StandardNormalize`, `GetGraphLineLengths` | `network_betweenness(g, radius, distance, normalization, weights)`, `axial_line_lengths(g)` | axial | compared (R01, R02) |
| Angular Integration | `AngularIntegrationAnalysis` | `AngularIntegration` + `AngularIntegration[Syntax\|Hillier]Normalize[LengthWeight]` | `angular_integration(sg, radius, weigh_by_length, normalization, angle_threshold, angle_precision)` | segment `pst_segment_graph` | compared (R06, R07) |
| Angular Choice | `AngularChoiceAnalysis` | `AngularChoice`, `AngularChoiceNormalize`, `AngularChoiceSyntaxNormalize`, `StandardNormalize` | `angular_choice(sg, radius, weigh_by_length, normalization, angle_threshold, angle_precision)` | segment | compared (R06, R07) – **one expected difference (ACwl…C)** |
| Angular Betweenness (an ordinary, ungated menu action, `main.py:130`) | `AngularBetweennessAnalysis` | `FastSegmentBetweenness` (+ Angular Choice normalisers) | **none** (Fast Segment Betweenness deferred in rPSTool: docs/10, docs/16) | segment | cannot be compared |
| Attraction Distance | `AttractionDistanceAnalysis` | `AttractionDistance` | `attraction_distance(g, attraction_points, radius, origin, distance, line_weights, point_edge_weight, destination_indices)` | axial (+ retained origin points) | compared (R03–R05) |
| Attraction Reach | `AttractionReachAnalysis` | `AttractionReach` | `attraction_reach(g, attraction_points, radius, origin, distance, decay, decay_constant, attraction_values, distribution, collection)` | axial (+ retained origin points) | compared (R03–R05) |
| Attraction Betweenness | `AttractionBetweennessAnalysis` | `SegmentBetweenness` (with attraction points) | `network_betweenness(…, weights, attraction_points)` | axial | compared (R04) |
| Origin-Destination Betweenness | `ODBetweennessAnalysis` | `ODBetweenness` | `od_betweenness(g, origins, radius, distance, destination_mode, origin_weights, destination_weights)` | axial with destinations as retained points | compared (R04) |
| Segment Grouping (class exists, experimental label; **no menu or Processing entry in v3.3.2**: `main.py:155-161` appends to `ACTIONS` after the loop that builds the menu, so it is dead code; reachable only programmatically) | `SegmentGroupingAnalysis` | `SegmentGrouping` | `segment_grouping(sg, angle_threshold, split_at_junctions)` | segment | covered by cases SG01-SG03 (programmatic driver only) |
| Segment Group Integration (same: **no menu entry**, `main.py:155-161` dead code; the wizard `segmentgroupintegrationwiz.py` forces at least one radius, so the silent no-op below is GUI-unreachable) | `SegmentGroupIntegrationAnalysis` | `SegmentGrouping`, `CreateSegmentGroupGraph`, `SegmentGroupIntegration` | `segment_grouping` → `pst_segment_group_graph` → `segment_group_integration` | segment → group graph | covered by cases SGI01-SGI02 (programmatic driver only) |
| Create Junctions | `CreateJunctionsAnalysis` | `CreateJunctions` | `create_junctions(x, y, unlinks)` | – | compared (R09, R10) |
| Create Segment Map | `CreateSegmentMapAnalysis` | `CreateSegmentMap` | `create_segment_map(coords, sections, network_type, snap, tail, deviation, extrude, unlinks)` | – | compared (R11, R12) |
| Compare Results | `CompareResultsAnalysis` | `CompareResults` (+ raster/polygon creation) | `compare_line_results`, `pst_raster_*` | – | **not compared** (raster/polygon output; see §3) |
| Isovist (no menu entry, map tool disabled in v3.3.2) | `IsovistAnalysis` | `CreateIsovistContext`, `CalculateIsovist` | `pst_isovist_context`, `isovist`, `isovist_context_free` | – | compared only via PyQGIS (R13) |
| Split Polylines (menu entry commented out) | `SplitPolylinesAnalysis` | none (pure QGIS) | none (rPSTool never splits lines) | – | not applicable |

## 2. Per-analysis detail: options → arguments → output columns

`{r}` = radius text of §0, `{u}` = `m`/`k`/`ha`. "Order" = order of columns in the table (= order of writing). Plugin-side arithmetic is marked ⚙ and listed in §3.

### Network Integration (axial) — `networkintegrationanalysis.py`
* Options (wizard): lines table, unlinks (optional), **only a steps radius** (`rad_steps`), output flags N / TD / MD, "store average score at junctions".
* rPSTool: `g <- axial_graph(lines, unlinks = unlink_xy)`; `network_integration(g, steps = if (rad_steps_enabled) trunc(rad_steps))`.
* Columns, order: `I{r}` (`integration`, float) · `I{r}N` (`node_count`, integer; written if N **or MD** ticked) · `I{r}D` (`total_depth`, float; written if TD **or MD**) · `I{r}M` (⚙ MD, float). `{r}` = `s<steps>` or empty.
* ⚙ MD = `TD / (N-1)` computed in Python double, `0.0` if `N-1 <= 0`. rPSTool has no mean depth.
* "Store average score at junctions": plugin code references an undefined `column_base_name` → `NameError` after the line columns are written (demonstrated by run R14). Not testable.

### Reach — `reachanalysis.py`
* Options: optional origin point layer, lines, unlinks, three calc tick-boxes, area unit, five radius types (one analysis per ticked type).
* rPSTool: `network_reach(g, radius = analysis_radius(<one type>), origins = point_xy or NULL)`; `g` is built from lines (+ unlinks) only (origins are **not** graph points here).
* Columns per radius type, order: `R{r}N` (`reached_count`, integer) · `R{r}L` (`reached_length`, float) · `R{r}a{u}` (`reached_area`, float). Result table = origin layer if origins ticked (ids `pt_id`), else the line layer.
* ⚙ Area unit: `km2` ×0.000001, `ha` ×0.0001 applied in Python to the float32 (stored back as float32). `m2` = native value (CRS units², no conversion).
* PST/rPSTool quirks that apply unchanged: area is convex hull of reached endpoints, straight-only radius gives π·r².

### Network Betweenness (axial) — `networkbetweennessanalysis.py`
* Options: distance modes (walking, steps, axmeter), weight modes (none, length, one or more *data columns*), normalisation (none, standard), radii (split), output N/TD/MD.
* Loop nesting: **weight mode → radius → distance mode.** Per iteration: `network_betweenness(g, radius, distance, normalization = "standard", weights = NULL | axial_line_lengths(g) | layer column)`.
* Columns, order per iteration: `B{dist}{r}{weight}` (`betweenness`, float; weight text: none → empty, length → `wl`, data → the *column name*) · `…S` (`normalized`, float; "standard") · then **only for the first weight mode**: `B{dist}{r}N` (`node_count`) · `…D` (`total_depth`) · `…M` (⚙ MD).
* Data weights: NULL weights crash the plugin (`ctypes` float assignment); the "Data name" typed in the wizard is required but ignored.
* rPSTool's Freeman/syntax normalisations have no plugin counterpart (plugin offers none/standard only).

### Angular Integration (segment) — `angularintegrationanalysis.py`
* Options: weight modes (none / length), normalisations (Turner, NAIN, Hillier), angle precision/threshold, combined radius (all ticked types), output N/TD/MD.
* One PST call per weight mode (length-weighted first, then unweighted), then one exported normaliser per ticked normalisation. rPSTool: `angular_integration(sg, radius, weigh_by_length, normalization = "turner"|"syntax"|"hillier", angle_threshold, angle_precision)` – the tool calls it once per normalisation and uses `integration`, `node_count`, `total_depth`.
* Columns, order: weighted block `AI{r}wl` (Turner; `A`… suffix = NAIN, `H` = Hillier: `AI{r}wlA`, `AI{r}wlH`), then N/TD/MD **once** (`AI{r}N`, `AI{r}D`, ⚙ `AI{r}M`) – emitted in the first block that runs – then unweighted block `AI{r}`, `AI{r}A`, `AI{r}H`.
* Angle threshold/precision are passed to both runs.

### Angular Choice (segment) — `angularchoiceanalysis.py`
* Options: normalisations (none, Turner `T`, standard `S`, syntax/NACH `C`), weights (none, length), angle precision/threshold, combined radius, output N/TD/MD.
* rPSTool: `angular_choice(sg, radius, weigh_by_length, normalization = "none"|"turner"|"standard"|"syntax", angle_threshold, angle_precision)`.
* Columns, order: weighted block (`AC{r}wl`, `AC{r}wlT`, `AC{r}wlS`, `AC{r}wlC`), then N/TD/MD once (`AC{r}N`, `AC{r}D`, ⚙ `AC{r}M`, emitted after the first block's scores), then unweighted block (`AC{r}`, `AC{r}T`, `AC{r}S`, `AC{r}C`).
* **Plugin quirk A:** the *unweighted* run is called **without** `angle_threshold`/`angle_precision` (defaults 0/1). With non-default angle controls the unweighted columns therefore differ from rPSTool called with the same controls; the tool compares against rPSTool with 0/1 for that block (run R07 exercises this).
* **Difference B (resolved):** in the length-weighted run the plugin feeds **`total_depth_weights`** to `PSTAAngularChoiceSyntaxNormalize` (`angularchoiceanalysis.py:128`), in the unweighted run `total_depths` (:177). rPSTool follows the plugin. An earlier audit confirmed the buffer pairing by running the plugin code (case C01 below checks it in a real QGIS run)., the package test asserts it, and every case that exercises it carries a sensitivity alternative proving that the other buffer gives a different column.
* **Quirk A is NOT reproduced (decision 2):** rPSTool honours explicitly supplied `angle_threshold` / `angle_precision` in both modes. To reproduce the plugin's unweighted result pass the plugin's effective settings (threshold 0, precision 1); the audit confirmed this by running the plugin code (case C03 compares against those effective settings)...` shows it.

### Angular Betweenness (an ordinary menu action, not experimental) — `angularbetweennessanalysis.py`
* `FastSegmentBetweenness` (angular distance). **No rPSTool function.** Columns it would write: `AB{r}wl|…`, `T`, `S`, `C`, `N/D/M`. Not compared; do not run it in the comparison.

### Attraction Distance — `attractiondistanceanalysis.py`
* Origins: `points` (retained in the graph: `axial_graph(…, points = origin_xy)` → `origin = "points"`), `lines` (`origin = "lines"`), `junctions` (`origin = "junctions"`; result in new layer `<network>_junctions`, order = `axial_crossing_coords(g)`).
* Distance modes (checkboxes) straight, walking, steps, angle, axmeter, attribute-cost (`weights`); combined radius from the radius page. rPSTool `distance = "straight"|"walking"|"steps"|"angular"|"weights"`; **axmeter has no rPSTool AD equivalent** (not exercised).
* Cost mode: `line_weights = layer[dw_attribute]`, `point_edge_weight = point_connection_weight`.
* Destinations: all points, or per ticked data column ⚙ **only points with value > 0 are passed to PST (NULL counts as 0)** – rPSTool callers must filter themselves; the destination index then refers to the filtered list.
* Column: `AD{dist}{r}{title}`, `title` = ⚙ first two characters of the lower-cased custom name / data column name / layer name; plus (if ticked) ⚙ `…_{suffix}` = attribute of the nearest destination (via `destination_index`; NULL when −1). Order: for each data column → for each distance mode: distance, attribute copy.

### Attraction Reach — `attractionreachanalysis.py`
* **Non-weight mode** (default): radii come from the *Radius page* (`rad_*`, `.split()` - one analysis per ticked type; `attractionreachanalysis.py:50`), `distance = "none"`: `attraction_reach(g, dest, radius = single, origin, distance = "none", attraction_values, distribution, collection)`; column `AR{r}{title}`.
* **Weight mode** ("Enable distance weight mode"): one analysis per ticked `dist_*` with its own radius; `decay` (`pow`→`"power"`, `curve`, `divide`), `decay_constant = C`; column `AR{r}f{title}` (`f` = decay marker).
* `attraction_values` = data column (⚙ NULL→0; zero/negative skipped by PST). `distribution` default **divide**, `collection` default **avarage → "mean"**.
* ⚙ weight-mode scores accumulate across worker threads: last float32 bit varies between runs (≈1e-7, measured) → compared with `--accum-rtol`.

### Attraction Betweenness — `attractionbetweennessanalysis.py`
* `network_betweenness(g, radius, distance, normalization = "standard", weights = values, attraction_points = dest_xy)` (all destination points, no filtering). Loop: data column → radius → distance. Columns `AT{dist}{r}{title}` (`betweenness`) and `…S` (`normalized`). No N/TD/MD.

### Origin-Destination Betweenness — `odbetweennessanalysis.py`
* `g <- axial_graph(lines, unlinks, points = destination_xy)`; `od_betweenness(g, origins = origin_xy, radius = split radius (straight/walking/angular), distance = "walking"|"angular", destination_mode = "all"|"closest", origin_weights, destination_weights)`. ⚙ NULL weights → 0. Column `OD{w|a}{r}[_{suffix}]` on the network layer.
* The Processing-toolbox algorithm `pst:odbetweenness` calls the same class but reads radii with `parameterAsInt` (fractions truncated) and has a leftover class `PstProcessingAlgorithmBase` (unused).

### Segment Grouping (no menu entry in v3.3.2) — `segmentgroupinganalysis.py`
* `segment_grouping(sg, angle_threshold, split_at_junctions)`. Columns `seggrp_id_{int(angle)}[_split]` (**native 0-based id**; rPSTool `group_id − 1`) and, if "generate colors", `seggrp_color_…` (0-based; rPSTool `color − 1`). "Apply colors" (thematic renderer, fixed 10-colour palette) is GUI only.

### Segment Group Integration (no menu entry in v3.3.2) — `segmentgroupintegrationanalysis.py`
* `gr <- segment_grouping(sg, thr, split)`; `gg <- segment_group_graph(sg, gr$group_id)`; per split radius (walking, steps) `segment_group_integration(gg, radius)`; ⚙ group values mapped to segments with the segment's group id (`MapGroupValues`).
* Columns `GI_{round(thr)}[_sp]{r}` (`integration`), `…N`, `…D`, ⚙ `…M` (same rules as Network Integration for N/TD/MD).

### Create Junctions — `createjunctionsanalysis.py`
* `create_junctions(lines1, y = lines2 or NULL)` → new point layer `<lines1>_junctions`, ids `1..n` (`id`), PST native order. **With unlinks ticked the plugin raises `NameError: point_table`** (R14) – rPSTool supports unlinks but there is nothing to compare.

### Create Segment Map — `createsegmentmapanalysis.py`
* `create_segment_map(coords, sections = vertex counts per polyline, network_type = "axial_or_segment"|"road_center_lines", snap, tail, deviation = trim_coldev, extrude = snap, unlinks)`. ⚙ **The plugin passes `extrude = snap`** (rPSTool's default is 0; decision 3, default kept): matched native arguments (`extrude = <snap>`) reproduce the plugin exactly (case CSM01), the rPSTool default differs (asserted). With `extrude = 0` the 3 m near miss in the test data is not bridged. Also: the copy-column repeat logic assumes output segments come grouped by source polyline; `res.m_UnlinkCoords != None` (:139) is always true for a ctypes pointer, so Road Centre Lines always creates a (possibly empty) `_unlinks` table (CSM.2). Multipart parts are separate polylines. Output layer `<network>_segments`: `id` (1..n), optional copied column (⚙ value of the source polyline, via `source_id`); in "Road Centre Lines" mode also layer `<network>_unlinks` (points from `unlinks`).

### Compare Results — `compareresultsanalysis.py`
* Plugin: reads two line layers + value columns (float32), `pixel_size` ⚙`int()` ≥1, blur radius = custom or 7×pixel size, `mode = NORMALIZED` always, creates a GeoTIFF + polygons. rPSTool: `compare_line_results(x, values1, values2, y, mode, blur_radius, resolution, m)`, `raster_data`, `raster_to_polygons`. Raster outputs are outside the tabular comparison; compare `raster min/max` and a few pixel values manually if required.

### Isovist — `isovistanalysis.py` (not in the GUI of v3.3.2)
* Constants: field of view 360, direction 0, perimeter resolution 64. Creates memory layer `isovists` (`x,y,max_dist,fov_angle,direction,area` + one integer counter per input layer, lower-case layer name). rPSTool: `isovist_context(obstacles, attraction_points, attraction_polygons)` + `isovist(ctx, origin, max_distance, 360, 0, 64)`. Compared: all those columns, positional.

## 3. Plugin-side computations that rPSTool will **not** replicate (a difference here is not an rPSTool defect)

| # | Where | What the plugin does in Python | rPSTool |
|---|---|---|---|
| P1 | `MeanDepthGen` (NI, NB, AI, AC, Group integration) | `M = TD/(N-1)` in double, `0.0` when `N-1 <= 0` | not provided; compute from `node_count`, `total_depth` |
| P2 | Reach | area × 1e-6 / 1e-4 for km²/ha, float32 rounding | areas in CRS units² |
| P3 | Group Integration | group result copied to every member segment | rPSTool returns one row per group |
| P4 | Attraction Distance | removes destinations with value ≤ 0 or NULL before PST; destination attribute copy | caller filters / indexes |
| P5 | all attraction analyses | NULL attribute → 0. (An earlier version of this file said several data columns are summed: **wrong**. Every caller passes a one-element list, `AttractionValueGen`'s multi-column branch `sum(values)` is dead code; several ticked data columns produce SEPARATE columns.) | caller |
| P6 | column naming | `GenColName`, 2-letter attraction title, `k` suffix, truncated radii, weight-column name, `_split`/`_sp`, `seggrp_…`, `GI_…` | rPSTool uses fixed names (`integration`, `node_count`, …) |
| P7 | AC unweighted run | silently ignores angle threshold/precision | honours them |
| P8 | AC/AI N/TD/MD | emitted once, from the first block that runs; NI writes N/TD whenever MD is ticked | all outputs returned always |
| P9 | NB/AT/OD/Reach/Group Integr. | silent no-op without a ticked radius | explicit unrestricted `analysis_radius()` |
| P10 | Segment Grouping | 0-based ids/colours; colour palette/thematic style | 1-based |
| P11 | Create Segment Map | `extrude = snap`; ids 1..n; copy column | `extrude` default 0; `source_id` |
| P12 | model I/O | skips non-line features, centroid of any geometry, outer ring of polygons, accepts geographic CRS, QGIS `fid` as identity | stricter validation; positional ids |
| P13 | Processing algorithm `pst:odbetweenness` | radii via `parameterAsInt` | double |
| P14 | Compare Results | `int()` pixel size, 7× blur default, GeoTIFF/polygon styling | native raster API |
| P15 | Isovist | fixed 360°/0°/64, layer-name counters | explicit arguments |
| P16 | GUI | colour ramps, selection of layers/columns, progress/cancel, QMessageBox log callback | none |
| P17 | known plugin bugs | NI "average score at junctions" (NameError), Create Junctions with unlinks (NameError) | n/a |

## 4. Corrections and additions from the audit (tool.md items)

| Id | Statement | Source |
|---|---|---|
| AI.4 | `axmeter` is selectable on the Angular Integration / Angular Choice radius page (`ui/pages/radiuspage.py:70`). The plugin accepts it and PST ignores it: the result equals the unrestricted analysis and the column is named `AIam…`/`ACam…`. rPSTool **rejects** axmeter for angular analyses (decision 6). Case AI04 records the plugin result, asserts the rejection and asserts that rPSTool without the limit reproduces the plugin values. | audit REPRO/axmeter; `src/pst-graph.cpp` |
| AD.1 | Attraction Distance origins `points` + `origin_is_regions` + `origin_poly_edge_point_interval_enabled` select `POINT_GROUPS` (polygon origins, `attractiondistanceanalysis.py:243-244`), with edge points sampled along the OUTER RING only. Case AD05 executes it. | S, E |
| AD.3 | Attraction Distance with an axmeter distance raises "PSTAAttractionDistance failed" in the plugin; rPSTool rejects it as well. | E |
| OD.2 | With the column suffix enabled but empty, the plugin appends a bare `_` (`odbetweennessanalysis.py:67-68`). Case OD02 records the column `ODa…_`. The Processing algorithm reads radii with `parameterAsInt`, and radius 0 means disabled (`odbetweenness_algorithm.py:249-254`). | S, E |
| CSM.2 | see Create Segment Map above (`m_UnlinkCoords != None` always true). | E |
| 0.2e | `readLines` skips features with fewer than two vertices silently (neither the `== 2` nor the `> 2` branch fires). | S |
| 0.8c | Attraction Reach in non-weight mode also uses `.split()`. | S |
| 1.6 | rPSTool signature note: `angular_integration(graph, steps = NULL, radius = NULL, ...)` - `steps` is the SECOND formal argument; callers must name `radius=`. | `R/angular-integration.R` |
| NI.4/CJ.1 | Network Integration junction output and Create Junctions with unlinks raise `NameError` in the plugin (`networkintegrationanalysis.py:128`, `createjunctionsanalysis.py:83`). rPSTool computes the results instead. | S, E |
| AI.5 | In Angular Integration with both weight modes ticked, the N/TD/MD column iterators of the weighted block are lazy (`Vector.values()`) and the columns are written only after BOTH analyses ran, so they read the buffers as overwritten by the UNWEIGHTED run (audit run of the plugin code). The values equal the weighted run's (node counts and angular total depth do not depend on length weighting), so no numerical effect, but "N/TD/MD come from the first block" is only true for Angular Choice, which writes per block. | E (manifest) |
