# Multi-radius and multi-normalisation (Angular Choice and Angular Integration)

Scope: `angular_choice()` and `angular_integration()` only; every other analysis rejects a multi-valued radius (§9).

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
* Every analysis other than Angular Choice and Angular Integration rejects a multi-valued `pst_radius` with an explicit error
  before any native work (§9).

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

Only `angular_choice()` and `angular_integration()` accept a vector in one radius field. All other analyses (Network Integration,
Reach, Network Betweenness, OD Betweenness, Attraction Reach and Distance, Segment Group Integration) reject a multi-valued
`analysis_radius()` with an explicit error before any native work.
