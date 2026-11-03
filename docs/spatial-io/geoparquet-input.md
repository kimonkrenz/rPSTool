# GeoParquet path input

`segment_graph(<GeoParquet path>)` builds a segment graph directly from a GeoParquet file, without an `sf` object or an R
coordinate matrix. The axial route is described in [axial file input](axial-file-input.md).

## 1. Public API

```r
segment_graph(x)     # x: numeric matrix | sf/sfc | ONE character path to a GeoParquet or FlatGeobuf file
```

A character vector without a `dim` attribute is the file route; a character matrix still takes the matrix path and its usual
error. The route is chosen by type and file content, not by file extension; there is no `format=` argument. The returned object is
the ordinary `pst_segment_graph`; only the CRS is retained. File row order is the graph segment order. No identifiers are read or
retained, and other columns are never read.

## 2. Optional dependencies

Reading needs the suggested packages `arrow (>= 25.0.0)` and `jsonlite`, plus `sf` (for CRS interpretation). rPSTool uses
arrow's undocumented `RecordBatchReader$export_to_c()` and checks that it exists; if a required package, version or function is
missing, the call fails with an error before any graph is created. The
Arrow C declarations used are recorded in [`src/arrow-c-abi/PROVENANCE.md`](../../src/arrow-c-abi/PROVENANCE.md).

## 3. File contract

| Item | Behaviour |
| --- | --- |
| Path | one non-`NA`, non-empty local path to a regular file (directories, FIFOs and devices are errors); the bytes `PAR1` must be at both the beginning and the end of the file |
| Rows | the footer row count must be at least 1 |
| `geo` metadata | required; valid JSON object; `version` matching `^1\.[01]\.[0-9]+$` (GeoParquet 1.0 and 1.1 families); GeoParquet 2.0 and pre-release versions are rejected |
| Geometry column | `primary_column` must be described in `columns`, have `encoding` exactly `"WKB"` and exist in the file. Other geometry columns are ignored. `geometry_types` is not trusted |
| `edges` | absent or exactly `"planar"`; anything else (including `"spherical"`) is rejected |
| `crs` key absent | the GeoParquet default OGC:CRS84 (geographic) applies, so the file is rejected |
| `"crs": null` | unknown CRS: accepted; the graph's `crs` attribute is `sf::st_crs(NA)`, as for an `sf` object with unknown CRS |
| `crs` object | interpreted by `sf::st_crs()` from the PROJJSON; unparseable or `NA` is rejected; a geographic CRS (`sf::st_is_longlat()`) is rejected; otherwise retained unchanged (no transformation, no override) |
| Geometry rows | every row must be a non-null, 2D `LineString` with exactly two finite vertices (WKB, either byte order per row). Null, empty, Z, M, ZM, multipart (including one-part), any other type, EWKB flags or SRID, and non-finite coordinates are errors that name the first offending one-based row. Polylines are never split |

The WKB of every row is validated before use. Any failure (metadata, stream or geometry) publishes no graph. The decoder cannot
detect storage corruption beyond what the Parquet reader detects.

## 4. Memory

PST's graph construction dominates memory. The path route avoids an `sf` object and an R matrix. Arrow's own memory depends on the
row-group size and on the allocator, and is not bounded by a scanner batch size.

## 5. Limitations

* Only pre-segmented two-vertex networks are supported; real polyline networks must be split by the user beforehand.
* The decode cannot be interrupted.
* Not supported: `geometry=` or `format=` arguments, external identifiers, GeoParquet 2.0, native GeoArrow encodings, directories,
  multi-file or cloud paths, snapping, reprojection and CRS override.
