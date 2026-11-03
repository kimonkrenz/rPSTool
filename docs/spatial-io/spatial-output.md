# Spatial output: a new GeoParquet or FlatGeobuf file with geometry, attributes and results

`spatial_output_file` writes a new file that carries the source geometry and attributes plus the result columns. It is available
for analyses whose result has exactly one row per source feature. `output_file` is the attribute-only Parquet route
([result files](result-files.md)). Spatial output is supported on POSIX systems and Windows.

## 1. Public API

```r
g <- segment_graph("roads.fgb")                  # or "roads.parquet" (GeoParquet); axial_graph(path) for axial analyses
angular_choice(g, radius = analysis_radius(steps = 3), spatial_output_file = "roads_choice.fgb")
```

`spatial_output_file = NULL` is appended after `overwrite` in `angular_integration()`, `angular_choice()`,
`network_integration()`, `network_reach()`, `network_betweenness()`, `od_betweenness()`, `attraction_reach()` and
`attraction_distance()`. Earlier arguments keep their position, default and meaning.

* The analysis runs once. A new file is written and an invisible `pst_result_file` is returned with `path`, `rows`, `columns`
  (the non-geometry columns in file order), `format` (`"flatgeobuf"` or `"geoparquet"`), `spatial = TRUE`, `source`,
  `geometry_column`, `replaced` and `appended`.
* `output_file` and `spatial_output_file` are mutually exclusive.
* `overwrite` applies to the destination file and to result columns that already exist in the source (replaced only in the new
  file). The source file is never written, replaced or modified.
* The graph must have been built from a file path. A graph built from a matrix or an `sf` object has no source file and gives an
  error.
* The output format equals the source format, and the destination must end in `.parquet` (GeoParquet source) or `.fgb`
  (FlatGeobuf source), in any letter case. A missing, other or mismatched extension is rejected before anything is computed or
  created. The CRS is carried over unchanged; there is no reprojection or CRS inference.
* Eligible: both angular analyses, and on an axial graph `network_integration(junctions = FALSE)`,
  `network_reach(origins = NULL)`, `network_betweenness()`, `od_betweenness()`, and `attraction_reach()` /
  `attraction_distance()` with `origin = "lines"`. Rejected before anything is computed: `network_reach(origins = )`, junction
  results and other attraction origins. `segment_group_integration()` (rows are groups) and `segment_grouping()` (its group
  counts cannot be written to the spatial file, see [result files](result-files.md) §7.3) have no `spatial_output_file`.

## 2. Source-to-result association

Result row `i` is source feature `i`, in the physical record order the graph reader used: file order for GeoParquet and
FlatGeobuf (for a Hilbert-indexed FlatGeobuf, the on-disk record order, not the order of the program that wrote it; see
[axial file input](axial-file-input.md)). There is no spatial join, geometry matching or identifier lookup. The positional
id column (`segment_id`, `line_id`, ...) is not written: position is the correspondence, and the source keeps its own identifiers.

**The source must not be modified or reordered between graph construction and completion of the spatial output.** File-built
graphs record the normalised path, format, row count, size, modification time and file identity (`attr(graph, "source")`). These
are re-checked before the analysis and before publication. They detect an obviously changed file but do not prove content
identity: a rewrite with the same size and modification time would pass. The writer re-validates every source record with the
graph reader's rules and fails without output if a record no longer matches.

## 3. Column semantics

* A result column with the same name as a source column is a collision. With `overwrite = FALSE` (default) the call stops
  before the analysis, naming the columns, and nothing is written. With `overwrite = TRUE` the source column is replaced in
  place in the new file (same position, new type and nullability).
* Other result columns are appended in result order. Source columns, types, nulls and values are preserved. Re-running an
  analysis on its own output needs `overwrite = TRUE`. Result names identify the calculation ([output naming](../output-naming.md)),
  so analyses with different radii or measures accumulate in one file without collisions.
* Rejected, with nothing written: duplicate source column names; a result name equal to the GeoParquet geometry column;
  duplicate result names; for FlatGeobuf, names that differ only by ASCII letter case (GDAL looks fields up case-insensitively);
  a source column of unknown FlatGeobuf type; more than 65,535 columns.

## 4. Writers and header metadata

* **FlatGeobuf** is written natively in one sequential pass. Geometry, header (CRS, name, title, description, envelope) and the
  property bytes of unchanged columns are copied unchanged. A null result is an omitted property (the FlatGeobuf convention);
  native NaN, Inf, `-0` and `-1` are ordinary values. The file has no spatial index (a packed Hilbert R-tree would reorder
  features and break the row correspondence).
* **GeoParquet** is written with arrow (>= 25.0.0, optional), one row group per source row group, with zstd compression. The
  geometry column and the `geo` metadata pass through unchanged. Result nulls follow the nullability of the result fields. An
  empty source row group is dropped, and a group larger than 1,048,576 rows is split.

Header metadata. GeoParquet keeps the source schema metadata and adds or replaces the `rpst:*` keys of
[result files](result-files.md) §2. FlatGeobuf has one free-form header metadata string, handled in three cases:

1. The source has none: rPSTool's provenance object (`rpst:*` keys) is written.
2. The source metadata is a flat JSON object of string values that already holds `rpst:*` keys (an earlier rPSTool analysis wrote
   it): all other pairs are kept byte for byte, the old `rpst:*` pairs are dropped and the current ones appended.
3. Anything else (non-JSON text, arrays, nested or non-string JSON, an object without `rpst:*` keys) is preserved unchanged and
   no provenance is added. The returned descriptor and the data columns still describe the new calculation.

## 5. Safety and publication

Publication follows [result files](result-files.md) §3: validation before anything is computed, an exclusive hidden temporary
file in the destination directory, no-clobber or single-rename publication, removal of the temporary file on error or
interrupt, and an existing valid output untouched by a failed write. The same guarantees and non-guarantees apply.

The destination may not be the source: the same path, or a symbolic or hard link to it, is rejected even with
`overwrite = TRUE`. A bind mount with a different device number is not detected. The native FlatGeobuf reader verifies the header
and every record, with 64 MiB size bounds.

## 6. Memory and speed

* FlatGeobuf output memory is dominated by PST's own arrays.
* GeoParquet is written by row group, so arrow does not need to hold the whole table at once.
* GeoParquet uses zstd, like `output_file`.

## 7. Not supported

Cross-format output, reprojection or CRS inference, indexed FlatGeobuf output, writing back to the source, GeoPackage or
Shapefile output, projecting group-level results onto segments.
