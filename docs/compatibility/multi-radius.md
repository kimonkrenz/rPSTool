# Multi-radius and multi-normalisation

Scope: `angular_choice()`, `angular_integration()`, `network_reach()`, `network_betweenness()`, `network_integration()` (§10, §11), `attraction_reach()`, `attraction_distance()` and `od_betweenness()` (§12), and `segment_group_integration()` (§13); every other analysis rejects a multi-valued radius (§9).

rPSTool runs one PST calculation per radius and applies PST's exported normalisers to that calculation's finished native arrays;
nothing is computed in R.

## 1. Public API

### 1.1 `analysis_radius()`

Each of the five fields accepts `NULL` (unrestricted), one valid scalar (unchanged behaviour), or a vector of valid values.

* At most **one** field may have more than one value (the *varying dimension*). Any other field may hold a scalar
  restriction (a *fixed restriction*) that applies to every configuration. There is no Cartesian product; a second
  vector field is an error.
* The supplied order is preserved. `NA`, non-finite, negative, out-of-range, non-numeric values and zero-length vectors are
  rejected; so are duplicates, including values that are distinct as doubles but identical once narrowed to the native
  `float` (steps are native integers and compared exactly). Zero is accepted wherever the scalar API accepts it.
* The vector is **expanded in R into independent scalar `pst_radius` configurations**; every configuration is validated by the
  unchanged scalar path (R rules and `rpst_radius_validate`, which shares `analysis_radii` with the analyses). The native
  analysis entry points still only ever consume scalar fields (a vector field reaching `analysis_radii` is rejected as before).
* Every analysis outside the list in §9 rejects a multi-valued `pst_radius` with an explicit error
  before any native work.

`analysis_radius(walking = c(500, 1000, 1500), angular = 180)` therefore means three calculations (walking 500, 1000, 1500, each also
limited to 180 degrees), not six.

### 1.2 `normalization`

A character vector of distinct, valid, non-missing names from the analysis' **existing** choices:
Angular Choice `none`, `standard`, `turner`, `syntax`; Angular Integration `turner`, `syntax`, `hillier`. Duplicates and
unknown names are errors. Order is preserved.

* Choice: `"none"` in a vector is accepted and contributes no column (the raw score `ac_a_<radius>[_wl]_n` is always retained, once per radius; it is still listed in `rpst:normalizations` as requested).
* Integration: its `normalization` selects which PST normaliser turns the count/depth (or weight/depth-weight) diagnostics into
  the integration columns (`ai_...`); there is no raw-only mode. Each requested normaliser gives one `ai_a_<radius>[_wl]_<norm>` column per radius.

### 1.3 Which schema?

A call is **scalar** when the radius expands to one configuration and `normalization` has length one. Scalar calls take
the single-result code path and return the single-result schema (columns, names, types, metadata, `rpst:schema` = "1").
Anything else is a **multi-result** call (schema "2", below).

## 2. One calculation per radius

For each radius the native PST analysis runs once (`PSTAAngularChoice` / `PSTAAngularIntegration`). Normalisation reuses that
run's arrays:

| | PST run writes | normaliser input | per-norm output |
|---|---|---|---|
| Choice | raw `choice`, `node_count`, `total_depth`, (`total_depth_weight` if weighted) | `standard`: choice; `turner`: choice, node_count; `syntax`: choice, **unweighted** total_depth (also when weighted) | one `float32` array |
| Integration | `node_count`, `total_depth`, (`total_weight`, `total_depth_weight` when weighted or `weight_outputs`) | unweighted: node_count, total_depth; weighted: total_weight, total_depth_weight (the `...LengthWeight` normalisers) | one `float32` array |

## 3. Column schema (multi-result)

### 3.1 Radius component

Column names follow the scheme of [output naming](../output-naming.md). The radius component of a column name encodes the complete
five-field configuration of its radius: every active restriction in the order straight, walking, steps, angular, axmeter
(`rl`, `rw`, `rs`, `ra`, `ram` followed by the value), or `rg` when none is set. A value is the shortest decimal (1 to 9
significant digits) that reads back to the same **native float** as the supplied number, written in plain fixed notation with `.`
replaced by `p` (never an exponent, never a sign; `-0` is `0`); steps are exact integers. Examples: walking `500` gives `rw500`,
`0.5` gives `rw0p5`, `0.1+0.2` gives `rw0p3`, steps `3` gives `rs3`, walking `12` with a fixed angular limit of `180` gives
`rw12_ra180`.

Fixed restrictions therefore appear in every column name as well as in the metadata, and the names of two radii differ only in the
varying field. Values that collapse to one native float (or `0`/`-0`) are rejected earlier (§1.1), so the names are unique within a
table. The names are labels; the authoritative mapping is the `rpst:columns` manifest (§4), which matters for downstream tools that
truncate or recode column names (for example 10-character Shapefile fields).

### 3.2 Names and order

`segment_id` first (once; one-based native segment position, as in the scalar schema). Then radius-major, in the requested
radius order; within a radius, in this order:

Angular Choice (`<radius>` = the radius component of 3.1):

1. `ac_a_<radius>[_wl]_n` — raw score
2. `nc_a_<radius>`, `td_a_<radius>`
3. `tdw_a_<radius>_wl` — only if `weigh_by_length`
4. `ac_a_<radius>[_wl]_<norm>` for each requested normalisation except `none`, in the requested order

Angular Integration:

1. `ai_a_<radius>[_wl]_<norm>` for each requested normalisation, in the requested order
2. `nc_a_<radius>`, `td_a_<radius>`
3. `tw_a_<radius>[_wl]`, `tdw_a_<radius>[_wl]` — only if `weigh_by_length` or `weight_outputs`

Shared diagnostics appear once per radius, never once per normalisation. Types are the scalar types (counts int32, results
float32 in files / double in data frames).

A result column that has the name of a source attribute replaces it, and other result columns are appended, as for
the scalar spatial output (including the FlatGeobuf case-insensitivity rule).

## 4. Metadata (`rpst:*`, Parquet key/value or FlatGeobuf header)

Common keys (`rpst:version`, `rpst:pst_version`, `rpst:pst_commit`,
`rpst:function`, `rpst:parameters`, `rpst:graph_type`, `rpst:graph_rows`, `rpst:crs_wkt`, `rpst:id_base`, `rpst:order`,
`rpst:float_columns`). For multi-result tables:

* `rpst:schema` = `"2"` (scalar tables stay `"1"`).
* `rpst:parameters` — the same JSON object as before; in schema 2 the varying `radius` field and `normalization` are
  **always** JSON arrays (also when `normalization` has one entry), fixed fields stay scalars. It is informational:
  `rpst:radius_configurations` and `rpst:columns` are authoritative.
* `rpst:radius_varying` — the varying dimension name, or `""`.
* `rpst:radius_fixed` — JSON object of the non-NULL fixed restrictions.
* `rpst:radius_configurations` — JSON array, in order, of the full five-field scalar configuration of each radius.
* `rpst:normalizations` — JSON array of the requested names in requested order.
* `rpst:columns` — JSON array with one object per result column in table order. Each object has `name`, `role`, `radius` (the
  1-based index into `rpst:radius_configurations`) and `radius_tag` (the radius component of the name), `normalization`
  (`null` for diagnostics and raw scores), and, where they apply, `code`, `distance`, `weight` and `parameters`.
  Roles: `choice`, `normalized`, `integration`, `node_count`, `total_depth`, `total_depth_weight`, `total_weight`.

`rpst:schema` distinguishes the layouts. Schema 1 tables also carry `rpst:naming` and `rpst:columns`; their entries hold the same
components, with the radius component itself in `radius` and empty components omitted. The manifest lists only this run's columns: a source attribute that happens to share a name is replaced (reported in
`replaced`), while columns of an earlier run with other radii remain ordinary attributes; nothing is dropped silently.

Weighting and angle controls (`weigh_by_length`, `angle_threshold`, `angle_precision`, `weight_outputs`), the PST
version/commit, graph type, source order and the row-order convention are carried by the existing keys.

## 5. In-memory result

A wide `data.frame` with `segment_id` and the same columns in the same order and with the same names; values widened exactly
from float to double. It carries an attribute `rpst_manifest` (list with the column data frame `columns` and the list of
`radii`) holding the same information as `rpst:columns` / `rpst:radius_configurations`.

## 6. Writing strategy

A single rPSTool-owned `ResultTable` collects every
radius' finished columns (each radius' PST scratch is released before the next radius runs), is exported as one Arrow C stream
and written by the existing single writer: one temporary file, one publication (a single rename; see [result files](../spatial-io/result-files.md) §3). Source geometry and attributes are
written once. Failure of any radius, normaliser or the writer returns before anything is published; an existing destination is
untouched; native owners unwind before the R error; the graph stays usable.

## 7. Failure and validation order

1. All R-side validation (graph, radius plan, normalisation, flags, destination, capabilities) runs first.
2. All radius configurations are validated and converted to native `SPSTARadii` before the first PST call.
3. Then radii run in order; any failure aborts the whole request.

## 8. Memory and run time

Each radius is a separate native PST calculation, so the number of PST runs equals the number of radii; normalisation reuses a run's arrays. The native table holds `rows x 4 B x columns` (columns = radii x (3 + weighted + number of normalisations other
than `none`) for Choice), the same per-column cost as a scalar call; for example 5 million segments, 10 radii and 2 normalisations,
unweighted, need about 1.0 GB. PST's per-run scratch memory is released before the next radius. For a bounded footprint on a very large
network, make several calls with different radii. A combined file stores geometry and attributes once rather than once per radius. Parquet and GeoParquet output uses the same single-table writers as scalar calls; it needs `arrow` (>= 25.0.0).

## 9. Other radius-bearing analyses

Only the analyses listed in §10 to §13 (with Angular Choice and Angular Integration) accept a vector in one radius field; this is every
analysis that takes an `analysis_radius()`. Any other function, or a multi-valued radius passed outside the registered analyses, is rejected with an
explicit error before any native work.

## 10. Network Reach and Segment Betweenness (axial graphs)

`network_reach()` and `network_betweenness()` follow the same design: R expands the radius vector into validated scalar configurations
(all of them before the first native call, with the unchanged scalar rules and every function-specific restriction), PST runs once
per radius, and each requested exported normaliser is applied to that run's finished arrays. Nothing is computed in R. The
identifier column comes first (`line_id`, or `origin_id` for `network_reach()` with `origins`), then the columns of each radius in
the requested order, named exactly as in a scalar call with that radius.

* **Network Reach** per radius: `rc_`, `rln_`, `rca_` (reached count, length, area). All five `analysis_radius()` fields are accepted
  as before; one may vary. With `origins` the table has one row per origin.
* **Segment Betweenness** per radius: the raw score (`nb_..._n`, or `at_..._n` with `attraction_points`), the node count and the total
  depth (once per radius, however many normalisations are requested), then one column per requested normalisation other than `"none"`,
  in the requested order. `normalization` is a character vector of distinct names from `"none"`, `"standard"`, `"freeman"` and
  `"syntax"`; `"none"` adds no column because the raw score is always returned and never duplicated. As for Angular Choice, a call with
  one radius and one normalisation keeps the scalar schema (`rpst:schema` 1); anything else is a multi-result call (schema 2).
* **Skipped origins.** Weights and attraction points keep their scalar meaning in every radius. Where PST skips an origin the node count
  and total depth are `NA` (null in a file), and so are the Freeman and syntax values, in every radius.
* **Files.** `output_file` (Parquet) and `spatial_output_file` use the same native result table as the in-memory route; the metadata is
  schema 2 (`rpst:graph_type` `axial`, `rpst:graph_rows` the number of lines, `rpst:columns` with the radius index of every column). The
  atomic publication, overwrite, collision and clean-up guarantees are those of the scalar routes. Network Reach with `origins` keeps its
  restriction that `spatial_output_file` is unavailable.
* **Memory.** Each PST run's scratch memory is released before the next radius, but the finished columns of all radii are retained
  until the result is returned or the file is written, so result storage grows with the number of radii. The file route does not
  build R data frames; it is not constant-memory.

## 11. Network Integration (axial graphs)

`network_integration()` keeps its supported boundary: only a topological steps radius (the official PST for QGIS plugin offers only
steps). That is a restriction on the radius type, not on the number of values, so `radius = analysis_radius(steps = c(1, 2, 3))` is
accepted. The `steps` argument stays a single value; a vector in any other `analysis_radius()` field, or a fixed non-steps limit next to a
steps vector, is rejected before any native work with the existing steps-only error. A one-element steps vector is a scalar call.

PST runs once per radius. The table is `line_id`, then per radius `ni_s_<radius>`, `nc_s_<radius>` and `td_s_<radius>` (integration,
node count, total depth), named exactly as in a scalar call, in the supplied order; there are no normalisation columns.

* **Junctions.** With `junctions = TRUE` the result is `list(lines, junctions)`. `lines` is the multi table. `junctions` has
  `junction_id`, `x` and `y` once, then one `nj_s_<radius>` score column per radius. PST returns the same junction coordinates for every
  radius; the native layer checks this and fails the call otherwise. `junction_output = "sf"` returns the same table as POINT features
  with the graph's CRS. A graph without crossings gives a zero-row junction table.
* **Files.** `output_file` and `spatial_output_file` write the line table (schema 2, `rpst:graph_type` `axial`). Result files cannot hold
  junction results, as for a scalar call; `junctions = TRUE` with a file is still an error.
* **Memory.** As in §10: each run's scratch memory is released, but the finished columns of all radii are retained until the result is
  returned or written. The in-memory junction table keeps one score vector per radius.

## 12. Attraction Reach, Attraction Distance and OD Betweenness (axial graphs)

These three follow §10: R expands the radius vector into validated scalar configurations, PST runs once per radius with the descriptor a
scalar call would fill, and nothing is computed in R. Every option keeps its scalar meaning in every radius: `origin`, `distance`,
polygon attractions and `points_per_polygon`, `attraction_values`, decay and `decay_constant`, `distribution`, `collection`,
`line_weights`, `point_edge_weight`, `destination_indices`, `origins`, `origin_weights`, `destination_weights` and `destination_mode`. A call
with one radius is a scalar call (schema 1); several radii give schema 2. There is no normalisation choice.

* **Identifier and order.** `origin_id` in PST's origin order for the two attraction analyses (lines, junctions, retained points or point
  groups), `line_id` for OD Betweenness; then the columns of each radius, in the supplied order, named exactly as in a scalar call.
* **Columns per radius.** Attraction Reach: `ar_...`. Attraction Distance: `ad_...` and, unless `destination_indices = FALSE`, `di_...`
  (PST's zero-based index, `-1` for none, a signed integer in memory and in files). OD Betweenness: `od_...`.
* **Validation before the first run.** Every configuration is checked first: the scalar radius rules and, for Attraction Distance, the
  distance rules of the scalar function (straight distance only with no radius or straight-only radii, so a `walking` vector with
  `distance = "straight"` is rejected as a whole; axmeter rejected; point groups with a straight-only radius unsupported) and its weight
  rules; for OD Betweenness, the axmeter rejection. A set in which any radius is invalid is rejected without a PST run.
* **Manifest.** Schema-2 metadata and the in-memory `rpst_manifest` list every column with its radius index; weighted columns carry
  `weight_name` (for OD Betweenness `origin: <name>; destination: <name>`), as in a scalar manifest.
* **Files.** `output_file` and `spatial_output_file` use the shared native result table and Arrow stream and the §10 publication
  guarantees. `spatial_output_file` stays limited to Attraction Reach/Distance with `origin = "lines"` (OD Betweenness rows are lines).
* **Memory.** As in §10: per-run scratch is released, the finished columns of all radii are retained, so storage grows with the number of
  radii; the attraction and origin inputs are copied once per run because PST receives them through writable pointers.
* **Reproducibility of PST scores.** Every score is bit for bit reproducible on one worker (`RPST_NUM_THREADS=1`) and, on several, for Attraction
  Distance, OD Betweenness, constant-decay unit-value Attraction Reach and straight line Attraction Reach. The one measured exception is Attraction
  Reach with attraction values or a non-constant decay: workers add partial scores in a nondeterministic order, which moves the last float bits
  (25 repeats per case: at most 3.5e-7 relative deviation, about three float epsilons). The tests therefore compare multi-radius columns with
  the scalar calls exactly, and use a 1e-6 relative tolerance only for that case on several workers. Straight line Attraction Reach
  (`origin = "lines"`, `distance = "straight"`, finite straight radius) was not reproducible in the pinned engine before patch 0012
  (`SphereTree::GetCloseLines` returned a stale count; see `inst/upstream/PATCHES.md`); it is now exact and checked against an independent geometric
  count. A separate, unchanged PST property: the finite straight query does not return zero-length lines.

## 13. Segment Group Integration (segment-group graphs)

`segment_group_integration()` follows §10: R expands the radius vector into validated scalar configurations and PST runs once per radius with
the descriptor a scalar call fills; nothing is computed in R and no normalisation is applied (PST's own integration is returned). A call with one
radius is a scalar call (schema 1, scalar native entry points); several radii give schema 2.

* **Supported fields.** `walking` and `steps` only, as in the scalar function. The vector may be in either field; the other may be a fixed
  restriction. A vector, or a fixed value, in `straight`, `angular` or `axmeter` is rejected as a whole, before the first PST run.
* **Identifier and order.** `group_id` (one-based, ascending, as in a scalar call), then for each radius in the supplied order `gi_...`
  (integration, double), `nc_...` (node count, integer) and `td_...` (total depth, double), named exactly as in a scalar call.
* **Missing results.** The scalar contract applies to every radius separately: a row is `NA` (null in a file) in all three columns of a radius exactly
  when PST wrote neither its count nor its depth for that radius, decided from PST's write masks and never from the integration value. A graph
  with no connecting nodes is `NA` in every radius. Written `-1` (isolated group), `0`, `NaN` and `Inf` are returned unchanged.
* **Manifest.** Schema-2 metadata and the in-memory `rpst_manifest` list every column with its radius index; `rpst:function` is
  `segment_group_integration` and `rpst:graph_type` is `segment_group`.
* **Files.** `output_file` (Parquet) uses the shared native result table and Arrow stream and the publication, overwrite, collision and cleanup
  guarantees of §6 and §10; the nullable `gi_`, `nc_`, `td_` columns carry one validity mask per radius. Segment-group graphs have no spatial output.
* **Validation and failure.** All configurations are validated before the first run, `RPST_NUM_THREADS` is validated once up front (also for graphs
  without nodes), and a failure in a later radius aborts the call and writes nothing. The graph stays usable.
* **Memory.** As in §10: per-run scratch is released, the finished columns of all radii are retained, so storage grows with the number of radii.
* **Reproducibility.** The scalar function is deterministic across worker caps, and so is every multi-radius column; the tests compare each
  multi-radius column exactly (values, types and NA pattern) with the scalar call for the same radius.
