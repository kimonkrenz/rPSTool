# Spatial file input and output

rPSTool builds native PST graphs from numeric matrices, optionally from `sf` objects, and optionally directly from GeoParquet or
FlatGeobuf files; it can persist results to Parquet and write a new spatial file with results. All of this is an adapter around
the same native core: PST itself remains an in-memory graph engine, and the adapters only reduce R-side copies and
materialisation.

| Topic | Document |
| --- | --- |
| `sf`/`sfc` inputs and outputs, CRS policy, geometry inventory | [sf adapters](sf-adapters.md) |
| `segment_graph(<GeoParquet path>)` | [GeoParquet input](geoparquet-input.md) |
| `segment_graph(<FlatGeobuf path>)` | [FlatGeobuf input](flatgeobuf-input.md) |
| `axial_graph(<path>)` for both formats | [axial file input](axial-file-input.md) |
| `output_file`: attribute-only Parquet result files | [result files](result-files.md) |
| `spatial_output_file`: new GeoParquet/FlatGeobuf with geometry, attributes and results | [spatial output](spatial-output.md) |

## Input

For simple segment input the native representation is one contiguous `double[4N]` buffer (`x1 y1 x2 y2` per segment). Matrix input
is the canonical interface and does not require `sf`.

```text
sf    → faithful coordinate extraction → contiguous native buffer → PST graph
file  → optional R arrow (Arrow C stream) or vendored FlatGeobuf reader → native WKB decoding → contiguous native buffer → PST graph
```

* **No silent repair.** rPSTool never silently reorders input, snaps geometry, splits or merges lines, changes coordinate units,
  deduplicates observations, imputes missing values, transforms CRS or clamps parameters. Complex polylines are not split; any
  preprocessing is explicit.
* **CRS.** Known geographic CRS is rejected; an unknown CRS remains the user's responsibility; a projected CRS is propagated in its
  native units; no reprojection ever occurs.
* **Row order.** File order is the segment order; physical file order is significant for axial graphs (unlink eligibility,
  crossing order). Stable external segment identifiers are kept conceptually separate from PST's internal `0..N-1` indexing and are
  not retained.
* **GeoParquet** is the preferred durable format. Reading needs the suggested packages `arrow` (>= 25.0.0), `jsonlite` and `sf`;
  FlatGeobuf needs only `sf` (for CRS parsing) and no GDAL at run time.

## Output

Results are R vectors/data frames by default. For very large results, `output_file` persists them directly from native buffers to
Parquet through the Arrow C stream, and `spatial_output_file` writes a new GeoParquet/FlatGeobuf file carrying the source geometry
and attributes plus the result columns. The measured benefit is the smaller retained R result and faster read-back, not a lower
peak memory at large scale (PST's own working memory dominates).

## Status matrix

This is the one place that holds current file-I/O status; other documents link here.

### File input (graph construction from one file path)

| Capability | Status |
| --- | --- |
| `segment_graph(<GeoParquet path>)` | implemented ([record](geoparquet-input.md)) |
| `segment_graph(<FlatGeobuf path>)` | implemented ([record](flatgeobuf-input.md)) |
| `axial_graph(<path>)`, both formats (`unlinks`/`points` stay in memory) | implemented ([record](axial-file-input.md)) |
| File-backed `unlinks`/`points`, explicit geometry-column selection, native GeoArrow encodings, GeoParquet 2.0, directories / multi-file datasets, external-ID retention, other formats | **not implemented** (each needs its own design decision) |

### Result output (rows are positional native order; `output_file` is attribute-only Parquet)

| Analysis | `output_file` | `spatial_output_file` (new GeoParquet/FlatGeobuf with geometry and attributes; same format as the source) |
| --- | --- | --- |
| `angular_integration`, `angular_choice` | yes | yes |
| `network_integration(junctions = FALSE)`, `od_betweenness` | yes | yes |
| `network_reach` | yes | `origins = NULL` only |
| `attraction_reach`, `attraction_distance` | yes (every origin kind) | `origin = "lines"` only |
| `network_betweenness` | yes (nullable columns) | yes |
| `segment_group_integration` | yes (nullable columns) | not offered (rows are groups, not source features) |
| `segment_grouping` | yes (one-based ids, `rpst:n_groups`/`rpst:n_colors` metadata) | not offered (the late native metadata keys would be dropped by the spatial writers) |
| `network_integration(junctions = TRUE)` | **not offered**: two tables, and independently published files could be left inconsistent by an interrupted overwrite ([result files](result-files.md)) | not applicable (junction rows are not source features) |
| Other families (construction, isovist, raster, graph inspection) | not persisted | not applicable |

Deliberately unsupported: cross-format output, reprojection, indexed FlatGeobuf output, external
feature IDs, GeoPackage/Shapefile output, Arrow IPC/Feather.

**Windows.** File publication is implemented through the Win32 API ([result files](result-files.md) §5 item 6) with the same
contract as POSIX (exclusive temporary, no-clobber publication, replacement that preserves the old file on failure, source-file
identity protection, Unicode paths), except that a replacement fails while another process holds the destination open without
sharing it for deletion. The development test suite has passed on Windows; validation of the final release candidate on Windows is still outstanding (`tools/validation/windows/README.md`, [release checklist](../release-checklist.md) item 10).
