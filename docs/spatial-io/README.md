# Spatial file input and output

rPSTool builds PST graphs from numeric matrices, optionally from `sf` objects, and optionally directly from GeoParquet or
FlatGeobuf files; it can write results to Parquet or to a new GeoParquet/FlatGeobuf file. PST holds the whole graph in memory:
file input and output do not make the computation streaming.

| Topic | Document |
| --- | --- |
| `sf`/`sfc` inputs and outputs, CRS policy, geometry inventory | [sf adapters](sf-adapters.md) |
| `segment_graph(<GeoParquet path>)` | [GeoParquet input](geoparquet-input.md) |
| `segment_graph(<FlatGeobuf path>)` | [FlatGeobuf input](flatgeobuf-input.md) |
| `axial_graph(<path>)` for both formats | [axial file input](axial-file-input.md) |
| `output_file`: attribute-only Parquet result files | [result files](result-files.md) |
| `spatial_output_file`: new GeoParquet/FlatGeobuf with geometry, attributes and results | [spatial output](spatial-output.md) |

## Input

Matrix input is the canonical interface and does not require `sf`.

* **No silent repair.** rPSTool never silently reorders input, snaps geometry, splits or merges lines, changes coordinate units,
  deduplicates observations, imputes missing values, transforms CRS or clamps parameters. Segment and axial file input accepts only
  features with exactly two finite vertices; polylines are not split, and any preprocessing is explicit.
* **CRS.** A known geographic CRS is rejected; an unknown CRS remains the user's responsibility; a projected CRS is propagated in
  its native units; no reprojection occurs (details: [CRS policy](sf-adapters.md#crs-policy)).
* **Row order.** File order is the segment order; physical file order is significant for axial graphs (unlink eligibility,
  crossing order). Source identifiers are not read or retained; results are positional (row `i` is source feature `i`).
* **GeoParquet** is the preferred durable format. Reading needs the suggested packages `arrow` (>= 25.0.0), `jsonlite` and `sf`;
  FlatGeobuf needs only `sf` (for CRS parsing) and no GDAL at run time. `output_file` needs `arrow` (>= 25.0.0).

## Output

Results are R vectors/data frames by default. For very large results, `output_file` writes them directly from the native result
arrays to Parquet through the Arrow C stream, and `spatial_output_file` writes a new GeoParquet/FlatGeobuf file carrying the source
geometry and attributes plus the result columns. This reduces the retained R result; it does not change PST's own working
memory. Publication guarantees (no-clobber, atomic replacement
where the platform provides it) and what is not guaranteed are in [result files](result-files.md) §3.

## Status matrix

### File input (graph construction from one file path)

| Capability | Status |
| --- | --- |
| `segment_graph(<GeoParquet path>)` | implemented ([details](geoparquet-input.md)) |
| `segment_graph(<FlatGeobuf path>)` | implemented ([details](flatgeobuf-input.md)) |
| `axial_graph(<path>)`, both formats (`unlinks`/`points` stay in memory) | implemented ([details](axial-file-input.md)) |
| File-backed `unlinks`/`points`, explicit geometry-column selection, native GeoArrow encodings, GeoParquet 2.0, directories / multi-file datasets, external-ID retention, other formats | **not implemented** |

### Result output (rows are positional native order; `output_file` is attribute-only Parquet)

| Analysis | `output_file` | `spatial_output_file` (new GeoParquet/FlatGeobuf with geometry and attributes; same format as the source) |
| --- | --- | --- |
| `angular_integration`, `angular_choice` | yes | yes |
| `network_integration(junctions = FALSE)`, `od_betweenness` | yes | yes |
| `network_reach` | yes | `origins = NULL` only |
| `attraction_reach`, `attraction_distance` | yes (every origin kind) | `origin = "lines"` only |
| `network_betweenness` | yes (nullable columns) | yes |
| `segment_group_integration` | yes (nullable columns) | not offered (rows are groups, not source features) |
| `segment_grouping` | yes (one-based ids, `rpst:n_groups`/`rpst:n_colors` metadata) | not offered (`n_groups`/`n_colors` cannot be carried into the spatial file) |
| `network_integration(junctions = TRUE)` | **not offered**: it returns two tables, which a single result file cannot hold ([result files](result-files.md) §8) | not applicable (junction rows are not source features) |
| Other families (construction, isovist, raster, graph inspection) | not persisted | not applicable |

Deliberately unsupported: cross-format output, reprojection, indexed FlatGeobuf output, external
feature IDs, GeoPackage/Shapefile output, Arrow IPC/Feather.

**Windows.** File publication has the same contract as on POSIX, except that a replacement fails (old file intact) while another
process holds the destination open without sharing it for deletion ([result files](result-files.md) §3).
