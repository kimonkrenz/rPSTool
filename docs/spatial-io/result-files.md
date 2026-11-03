# Result files: direct Parquet output

`output_file` writes an analysis result directly from the native result arrays to one Parquet file, without building an R data
frame. It is available for `angular_integration()`, `angular_choice()` (§1, §2), the axial analyses without missing values (§11),
`network_betweenness()` and `segment_group_integration()`, which have nullable columns (§13), and `segment_grouping()` (§13.6).
`network_integration(junctions = TRUE)` is not offered (§14). To write a new GeoParquet or FlatGeobuf file that carries the source
geometry, use `spatial_output_file` ([spatial output](spatial-output.md)). The status of every analysis is in [spatial I/O](README.md).

Section numbers are stable identifiers; sections that no longer exist are not renumbered.

## 1. Public API

```r
angular_integration(graph, steps = NULL, radius = NULL, weigh_by_length = FALSE, normalization = "turner",
                    angle_threshold = 0, angle_precision = 1, weight_outputs = FALSE,
                    output_file = NULL, overwrite = FALSE)
angular_choice(graph, radius = analysis_radius(), weigh_by_length = FALSE, normalization = "none",
               angle_threshold = 0, angle_precision = 1, output_file = NULL, overwrite = FALSE)
```

`output_file` and `overwrite` are appended after the existing arguments; the other arguments keep their position and meaning.

* `output_file = NULL` (default): the function returns its data frame as usual.
* `output_file = "<path>"`: the analysis runs once and its result is written to one Parquet file (zstd). The function returns
  an invisible `pst_result_file` descriptor with `path` (absolute), `rows`, `columns` (in file order) and `format`
  (`"parquet"`). No R result vectors or data frames are built.
* `overwrite = FALSE` (default) never replaces anything that exists at `output_file`; `TRUE` replaces the file by a single
  rename, and the old file is untouched if anything fails (see §5).
* `output_file` requires the suggested package `arrow (>= 25.0.0)`, including zstd support. rPSTool uses arrow's
  undocumented `RecordBatchReader$import_from_c()`; it checks at run time that this function exists and fails with an
  error before computing anything if it does not. arrow 25.0.0 is the version this has been tested with.

## 2. File contents and metadata

The file has exactly the columns, order and rows of the in-memory data frame for the same call, including the conditional
`total_weight`/`total_depth_weight` columns of Angular Integration and `total_depth_weight`/`normalized` of Angular Choice.
Column names are described in [output naming](../output-naming.md).

| Column | Parquet type | Content |
| --- | --- | --- |
| `segment_id` | int32 | one-based position in native graph order; no external identifiers |
| float results | **float32** | PST's native `float`, stored unchanged; reading into R widens it exactly to the doubles of the data frame |
| `node_count` | int32 | PST's native `unsigned int`; the call fails if a value exceeds `INT32_MAX` |

All columns of the angular and mask-free axial analyses are non-nullable. Native Inf, NaN, `-0` and any other float bit pattern
are stored bit for bit.

**Metadata.** The Parquet key/value metadata contains these keys:

| Key | Value |
| --- | --- |
| `rpst:schema` | `1` for a single-result table; `2` for a multi-result table ([multi-radius](../compatibility/multi-radius.md)) |
| `rpst:version`, `rpst:pst_version`, `rpst:pst_commit` | rPSTool version; pinned PST version and commit |
| `rpst:function` | public function name, for example `angular_choice` |
| `rpst:parameters` | compact JSON of the resolved radius and every analysis argument; large inputs (attraction points, weights, origin rows) are recorded by size only |
| `rpst:graph_type` | `segment`, `axial` or `segment_group` |
| `rpst:graph_rows` | native row count of the graph (segments, lines or groups), taken from the native graph |
| `rpst:crs_wkt` | CRS of the graph as WKT; empty if unknown |
| `rpst:id_base` | `1` |
| `rpst:order` | row convention: native segment or line order; supplied origin order for `network_reach(origins =)`; native point/junction/line/point-group order for attraction origin kinds; group id order for group integration |
| `rpst:float_columns` | present when the table has float32 columns |
| `rpst:naming`, `rpst:columns` | column manifest ([output naming](../output-naming.md)) |
| `rpst:n_groups`, `rpst:n_colors` | `segment_grouping()` only (§13.6) |
| `rpst:radius_varying`, `rpst:radius_fixed`, `rpst:radius_configurations`, `rpst:normalizations` | multi-result tables only |

## 5. Publication guarantees

1. The destination is validated first (one non-empty string, existing parent directory, not a directory, not existing unless
   `overwrite = TRUE`) and the arrow requirements are checked. The analysis then runs, and nothing is created on disk until it
   has succeeded.
2. The result is written to a hidden temporary file `.rpst-<random>.partial` in the destination directory, so it is on the
   same filesystem. The temporary file is created exclusively and never reuses an existing file or follows a symbolic link. The
   row count and a non-empty size are verified before publication; on failure or interrupt the temporary file is removed.
3. `overwrite = FALSE`: the file is published by a hard link that the operating system refuses if the target exists, also when
   another process created it after validation. An existing file is therefore never replaced. A filesystem without hard-link
   support produces an error; there is no check-then-rename fallback.
4. `overwrite = TRUE`: the file is published by a single rename. On POSIX this is atomic on one filesystem: observers see the
   old or the new complete file, and if the rename fails the old destination is untouched. A symbolic-link destination is
   replaced by a regular file (the link is replaced, not its target).
5. **Not guaranteed:**
   * durability after a crash or power loss (no `fsync` is issued; the file may then be absent or empty);
   * correct results with concurrent writers to one path (with `overwrite = TRUE` the last rename wins);
   * cleanup after `SIGKILL` (a hidden `.rpst-*.partial` file can remain);
   * interruption of a running PST analysis (PST cannot be interrupted; the R-level write can).
6. **Windows** follows the same contract through the Win32 API: exclusive temporary file (symbolic links and reparse points are
   never followed), no-clobber publication by `MoveFileExW` without `MOVEFILE_REPLACE_EXISTING`, replacement by `MoveFileExW`
   with `MOVEFILE_REPLACE_EXISTING` (one rename call, on the same volume), Unicode paths. Differences:
   * Whether replacement is atomic on NTFS, and what observers see during it, is not specified by Microsoft's documentation and
     is not guaranteed here.
   * A replacement fails, with the old file intact, while another process holds the destination open without sharing it for
     deletion; the error says the file is in use or access is denied. Transient sharing violations (virus scanners, indexers)
     are retried for up to half a second.
   * Apache Arrow opens local files without delete sharing, and a reader such as `ParquetFileReader$create(<path>)` keeps the
     file open until it is garbage collected. Close or release Arrow readers of a result file before overwriting or deleting it.
     rPSTool itself closes the Parquet sources it reads before publishing and never holds the destination open.
   * The source-file identity check used by `spatial_output_file` is a check at one moment, not a lock, on every platform.

## 9. Memory and limitations

* PST fills complete result arrays, so the native result is fully resident until the file is written. `output_file` is not a
  streaming or bounded-memory computation, and it is not faster than computing and then writing with arrow.
* Writing from the native arrays avoids building the R data frame and arrow's input copy. On a Linux x86-64 machine with four
  cores this lowered the peak memory above the graph by about 12-25 % at 1-2 million rows, but not at several million rows,
  where PST's own working memory dominates (about 660 MiB above the graph at 3.9 million segments, 859 MiB at 5 million).
  Memory retained by R after the call was lower (46 MiB against 174-252 MiB at 5 million segments). These are single-machine
  observations, not guarantees.
* Row identity is positional; external feature identifiers are not retained.

## 10. Not supported

`network_integration(junctions = TRUE)` (§14), graph inspection outputs, Arrow IPC/Feather, a choice of compression, external
identifiers.

## 11. Axial-graph analyses without missing values

`output_file = NULL, overwrite = FALSE` are appended to:

| Function | File route | Columns (after the int32 positional id, in data-frame order) |
| --- | --- | --- |
| `network_integration()` | `junctions = FALSE` only (`junctions = TRUE` is rejected before anything runs) | `line_id`, `integration` f32, `node_count` i32, `total_depth` f32 |
| `network_reach()` | lines and supplied origins | `line_id` or `origin_id`, `reached_count` i32, `reached_length` f32, `reached_area` f32 |
| `od_betweenness()` | all | `line_id`, `od_betweenness` f32 |
| `attraction_reach()` | every origin kind and mode | `origin_id`, `attraction_reach` f32 |
| `attraction_distance()` | every origin kind and mode, with or without `destination_indices` | `origin_id`, `attraction_distance` f32, optional `destination_index` signed i32 |

PST writes every output element of these analyses (the one unwritten attraction combination is rejected before the call, see
[attractions](../compatibility/attractions.md)), so they have no missing-value policy. Native `-1` (unreachable distance, fewer
than two lines reached), `NaN` and `Inf` are ordinary values and are stored as such. `destination_index` is a signed int32 whose
`-1` means "no destination".

Metadata: `rpst:graph_type = axial`; `rpst:graph_rows` is the native line count.

Memory: as in §9. For a 2 million line axial lattice, `network_integration(steps = 3)` peaked about 127 MiB above the graph
with `output_file` against 158 MiB for computing and then writing with arrow (single Linux machine); PST's own working memory
is unchanged.

## 13. Nullable columns: Segment Betweenness and Segment Group Integration

`output_file = NULL, overwrite = FALSE` are appended to `network_betweenness()` and `segment_group_integration()`. Their
in-memory results are unchanged.

### 13.1 Nullable-column contract

A column is nullable or not by function and parameters, never by whether a particular run happens to contain a missing value, so
all files of one analysis share one schema. A null means exactly "PST wrote no value for this slot". A written `NaN`, `Inf`,
`-Inf`, `-1` or `0` is an ordinary value; no numeric sentinel stands in for a null. In R, a null reads back as `NA`.

| Function / column | Parquet type | Nullable | A row is null exactly when |
| --- | --- | --- | --- |
| `network_betweenness` `line_id` | int32 | no | never |
| `betweenness` | float32 | no | never: PST writes the raw score of every line, including lines of skipped origins |
| `node_count` | int32 | yes | PST skipped the origin (weighted and attraction modes only) |
| `total_depth` | float32 | yes | same rows as `node_count` |
| `normalized`, `"standard"` | float32 | no | never |
| `normalized`, `"freeman"` or `"syntax"` | float32 | yes | the diagnostics of that row were not written; a written normaliser `NaN` stays a valid `NaN` |
| `normalized`, `"none"` | none | column absent | |
| `segment_group_integration` `group_id` | int32 | no | never (gaps are empty groups and are real rows) |
| `integration`, `node_count`, `total_depth` | float32, int32, float32 | yes | PST wrote no values for the group |

For group integration, PST writes all three outputs for every group or for none (a graph without native nodes), so a file has
columns that are all-null or all-valid. An isolated group in a graph with nodes holds the written values `-1, 0, 0`, which are
valid.

### 13.3 Metadata

As in §2. For betweenness, `rpst:graph_type = axial`, `rpst:graph_rows` is the native line count and `rpst:order` is native line
order. For group integration, `rpst:graph_type = segment_group`, `rpst:graph_rows` is the native group count and `rpst:order` is
group id order; a group graph retains no source CRS.

### 13.6 Segment Grouping

`segment_grouping(graph, angle_threshold = 1, split_at_junctions = FALSE, output_file = NULL, overwrite = FALSE)` appends the two
arguments; with `output_file = NULL` the data frame, including its `n_groups` and `n_colors` attributes, is unchanged.

With `output_file`, the file has the columns `segment_id`, `group_id` and `color`, all non-nullable int32, in native segment
order. `group_id` and `color` are one-based exactly as in the data frame. Nothing is compacted, reordered or relabelled.

The scalars `n_groups` and `n_colors` are stored as Parquet metadata `rpst:n_groups` and `rpst:n_colors` (decimal strings), in
addition to the keys of §2. They equal `max(group_id)` and `max(color)`.

`spatial_output_file` is not offered for this family: the spatial writers carry only the R-side provenance metadata, so
`rpst:n_groups` and `rpst:n_colors` could not be written to the spatial file.

## 14. Network Integration with junctions: not offered

`network_integration(junctions = TRUE)` returns two tables from one native call: the lines (`line_id`, `integration`,
`node_count`, `total_depth`) and the junctions (`junction_id`, `x`, `y`, `integration`). A result file holds one table, and
publishing two files by two renames is not atomic: an interruption could leave one new and one old or missing file. The
combination `junctions = TRUE` with `output_file` therefore fails with an explicit message. Use the in-memory result; with
`junction_output = "sf"` the junctions are POINT features in the graph CRS.
