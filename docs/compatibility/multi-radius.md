# Multi-radius and multi-normalisation (Angular Choice and Angular Integration)

Status: implemented. Scope: `angular_choice()` and
`angular_integration()` only. See §9 for the inventory of the other radius-bearing analyses.

The principle is unchanged: rPSTool wraps PST. One PST calculation runs per radius; PST's exported normalisers are applied to
that calculation's finished native arrays; nothing is computed in R and no PST algorithm is touched.

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

* Choice: `"none"` in a vector is accepted and contributes no column (the raw `choice` is always retained, once per radius; it is still listed in `rpst:normalizations` as requested).
* Integration: its `normalization` selects which PST normaliser turns the count/depth (or weight/depth-weight) diagnostics into
  `integration`; there is no raw-only mode. Each requested normaliser gives one `integration_<norm>` column per radius.

### 1.3 Which schema?

A call is **scalar** when the radius expands to one configuration and `normalization` has length one. Scalar calls take
the unchanged code path and return exactly the schema they always did (columns, names, types, metadata, `rpst:schema` = "1").
Anything else is a **multi-result** call (schema "2", below).

## 2. One calculation per radius

For each radius the native PST analysis runs once (`PSTAAngularChoice` / `PSTAAngularIntegration`). Normalisation reuses that
run's arrays:

| | PST run writes | normaliser input | per-norm output |
|---|---|---|---|
| Choice | raw `choice`, `node_count`, `total_depth`, (`total_depth_weight` if weighted) | `standard`: choice; `turner`: choice, node_count; `syntax`: choice, **unweighted** total_depth (also when weighted) | one `float32` array |
| Integration | `node_count`, `total_depth`, (`total_weight`, `total_depth_weight` when weighted or `weight_outputs`) | unweighted: node_count, total_depth; weighted: total_weight, total_depth_weight (the `...LengthWeight` normalisers) | one `float32` array |

A test-only counter (`rpst_angular_call_counts`) records PST runs and normaliser calls and the tests assert runs = radii.

## 3. Column schema (multi-result)

### 3.1 Radius tag

The tag identifies the radius of a column: `<code><value>` for the varying dimension, no tag when no dimension varies.

| dimension | code | | dimension | code |
|---|---|---|---|---|
| straight | `s` | | angular | `a` |
| walking | `w` | | axmeter | `x` (not used by the angular engines) |
| steps | `n` | | | |

`<value>` is the shortest decimal (1 to 9 significant digits) that reads back to the same **native float** as the supplied
number, written in plain fixed notation with `.` replaced by `p` (never an exponent, never a sign; `-0` is `0`). Steps are
exact integers. Examples: `500`→`w500`, `0.5`→`w0p5`, `0.1+0.2`→`w0p3`, `1e20`→`w100000000000000000000`, steps `3`→`n3`.
Values that collapse to one native float (or `0`/`-0`) are rejected earlier (§1.1), so tags are unique within a table
(verified by an internal check on all names). The tag is a convenience; the authoritative mapping is the `rpst:columns`
manifest (§4), which matters for downstream tools that truncate or recode column names (for example 10-character
Shapefile fields).

Fixed restrictions do not appear in the names (they are identical for every column); they are recorded in the metadata.

### 3.2 Names and order

`segment_id` first (once; one-based native segment position, as in the scalar schema). Then radius-major, in the requested
radius order; within a radius, in this order:

Angular Choice (`<t>` = `_<tag>` or empty):

1. `choice<t>` — raw
2. `node_count<t>`, `total_depth<t>`
3. `total_depth_weight<t>` — only if `weigh_by_length`
4. `choice_<norm><t>` for each requested normalisation except `none`, in the requested order

Angular Integration:

1. `integration_<norm><t>` for each requested normalisation, in the requested order
2. `node_count<t>`, `total_depth<t>`
3. `total_weight<t>`, `total_depth_weight<t>` — only if `weigh_by_length` or `weight_outputs`

Shared diagnostics appear once per radius, never once per normalisation. Types are the scalar types (counts int32, results
float32 in files / double in data frames).

A result column that has the name of a source attribute replaces it, and other result columns are appended, exactly as for
the scalar spatial output (existing preflight, including the FlatGeobuf case-insensitivity rule, unchanged).

## 4. Metadata (`rpst:*`, Parquet key/value or FlatGeobuf header)

Existing keys keep their meaning and are written as before (`rpst:version`, `rpst:pst_version`, `rpst:pst_commit`,
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
* `rpst:columns` — JSON array of `{"name","role","radius","normalization"}` objects, one per result column in table order
  (`radius` is the 1-based index into `rpst:radius_configurations`; `normalization` is `null` for diagnostics/raw).
  Roles: `choice`, `normalized`, `integration`, `node_count`, `total_depth`, `total_depth_weight`, `total_weight`.

`rpst:schema` is the only discriminator between the layouts. Schema 1 files are unchanged and carry no `rpst:columns`. The
manifest lists only this run's columns: a source attribute that happens to share a name is replaced (reported in
`replaced`), while columns of an earlier run with other radii remain ordinary attributes; nothing is dropped silently.

Weighting and angle controls (`weigh_by_length`, `angle_threshold`, `angle_precision`, `weight_outputs`), the PST
version/commit, graph type, source order and the row-order convention are carried by the existing keys.

## 5. In-memory result

A wide `data.frame` with `segment_id` and the same columns in the same order and with the same names; values widened exactly
from float to double. It carries an attribute `rpst_manifest` (list with the column data frame `columns` and the list of
`radii`) holding the same information as `rpst:columns` / `rpst:radius_configurations`.

## 6. Writing strategy

Selected: **accumulate natively, publish once** (see §8 for the measurements). A single rPSTool-owned `ResultTable` collects every
radius' finished columns (each radius' PST scratch is released before the next radius runs), is exported as one Arrow C stream
and written by the existing single writer: one temporary file, one publication (a single rename; see [result files](../spatial-io/result-files.md) §5). Source geometry and attributes are
written once. Failure of any radius, normaliser or the writer returns before anything is published; an existing destination is
untouched; native owners unwind before the R error; the graph stays usable.

## 7. Failure and validation order

1. All R-side validation (graph, radius plan, normalisation, flags, destination, capabilities) runs first.
2. All radius configurations are validated and converted to native `SPSTARadii` before the first PST call.
3. Then radii run in order; any failure aborts the whole request.

## 8. Performance findings and test evidence

### 8.1 Measurements (Linux, 4 cores, FlatGeobuf source, 38,920 segments; development-only benchmark, not retained)

Walking radii 100, 200, ...; one fresh process per row. `compute` = one scalar call per radius (PST work only);
`multi_*` = one multi call; `scalar_fgb` = one scalar FlatGeobuf per radius.

| radii | norms | mode | elapsed s | peak RSS MB | output MB |
|---|---|---|---|---|---|
| 4 | 1 | compute / multi_memory / multi_fgb / scalar_fgb | 45.3 / 45.5 / 46.4 / 45.6 | 199 / 198 / 198 / 198 | - / - / 7.4 / 19.0 |
| 4 | 3 | compute / multi_memory / multi_fgb / scalar_fgb | 45.0 / 46.0 / 42.9 / 43.0 | 199 / 201 / 198 / 198 | - / - / 9.2 / 19.0 |
| 8 | 3 | compute / multi_memory / multi_fgb / scalar_fgb | 252.6 / 252.5 / 249.9 / 248.7 | 215 / 218 / 212 / 208 | - / - / 14.6 / 38.0 |

Findings and limits (stated plainly):

* PST computation is >99% of the elapsed time; normalisation (cheap O(n) PST routines) and the native writer are within run-to-run
  noise. One combined file is 2.6x smaller (4 radii) than one file per radius because geometry and attributes are stored once.
* Peak RSS is **not informative** here: the high-water mark is set while the benchmark builds its own source with `sf`, before any
  analysis. It cannot discriminate accumulate-versus-stage. Use the analytical bound instead: the native table holds
  `rows x 4 B x columns` (columns = radii x (3 + weighted + non-"none" norms) for Choice), i.e. the same per-column cost as a scalar
  call; e.g. 5 million segments, 10 radii, 2 normalisations, unweighted = 5e6 x 4 x 50 = 1.0 GB. PST's per-run scratch is released
  before the next radius.
* **Parquet and GeoParquet were not measured**: `arrow` could not be installed in the development sandbox. Those writers are the
  unchanged single-table writers, so only the column count differs.
* No five-million-segment run was made.

Decision: **accumulate natively, write once**. The staged alternative (completing each radius into temporary storage and assembling
the final table at the end) was **neither implemented nor benchmarked**, and this document does **not** claim that it is slower;
it might well lower peak memory for very many radii on very large networks. Accumulation was chosen because it reuses the existing
single table, single Arrow stream and single publication step unchanged, whereas staging needs a second persistence path
(temporary columnar files, a re-reader feeding the Arrow stream, cleanup under interrupt and failure) and the measurements above
do not show that the writer is a cost worth that complexity. The memory of accumulation is linear and predictable (formula above).
If a user needs a bounded footprint on a very large network, the supported route today is several calls with different radii.
A staged writer remains a possible future extension; any threshold for it must be grounded in Parquet measurements on the target
machine (Parquet and GeoParquet were not benchmarked here).

### 8.2 Test evidence

* Every multi column equals the corresponding scalar call (`test-multi-radius.R`), and the scalar calls themselves are checked
  against the direct pinned-PST fixtures (`test-angular-controls.R`).
* **Direct pinned-PST oracle for the multi route** (`test-multi-radius-direct.R`): `fixtures/angular-multi-radius-direct-v3.3.2.R` holds
  120 families (graph x routine x weighted x angle threshold/precision x one varying radius field with fixed restrictions on others)
  produced by `tools/reference/angular/generate-multi-radius-reference.py`, which calls the pinned exported C API once per radius and the
  exported normalisers and verifies the 145 pinned source blobs first. It was run twice when the fixture was created and the two outputs
  compared equal with `cmp`; no gate re-runs the generator, so regeneration is a manual check (usage in `tools/reference/README.md`). It covers weighted Choice with
  syntax normalisation (`total_depth_weight` for the weighted runs, `total_depth` for the unweighted ones), Integration with `weight_outputs` and no weighting, varied `angle_threshold` and
  `angle_precision`, fixed straight/steps/angular/walking restrictions, zero radii, and genuine native NaN/Inf (weighted Hillier on the
  4e18-coordinate star), which the FlatGeobuf and GeoParquet writers store unchanged.
* File routes (`test-multi-radius.R`, `test-multi-radius-parquet.R`): schema 2 metadata and manifest, exact round trip, geometry/CRS/
  attributes/row groups, column replacement, overwrite and no-clobber, and failures after earlier radii completed (nothing published,
  existing destination untouched, no temporary left). The Parquet tests need `arrow` (>= 25.0.0) and skip where it is not installed.

## 9. Inventory of other radius-bearing analyses

| analysis | native shape | multi-radius reuse |
|---|---|---|
| Network Integration | `steps`/radius, line results (+optional junction output) | deferred: per-radius table assembly is analysis-specific (junction output) |
| Reach | radius, point or line origins | deferred: origin-kind specific columns |
| Segment Betweenness | radius + distance + normalisation + weights/attractions | deferred: nullable diagnostics, weights/attractions |
| OD Betweenness | origins/destinations | deferred |
| Attraction Reach / Distance | attraction points | deferred |
| Segment Group Integration | grouping, int32 columns | deferred |

All of them reject a multi-valued `analysis_radius()` explicitly. The expansion/validation/naming layer (`.pst_radius_plan`,
`.pst_radius_tag`, manifest) is analysis-independent and is the reusable part; each future family needs its own native
accumulate-into-`ResultTable` entry, which is more than a small change, so none is added here.
