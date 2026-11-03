# Axial file input: `axial_graph(<path>)`

`axial_graph(<path>)` builds an axial graph from one GeoParquet or FlatGeobuf file. The file contracts of
[GeoParquet](geoparquet-input.md) and [FlatGeobuf](flatgeobuf-input.md) apply unchanged.

## 1. Public API

```r
axial_graph(x, line_indices = NULL, unlinks = NULL, points = NULL,
            points_per_polygon = NULL, polygon_point_interval = NULL)
# x: numeric matrix | sf/sfc | ONE character path to a GeoParquet or FlatGeobuf file
```

* A character vector without a `dim` attribute is the file route (a character matrix still takes the matrix path and its usual
  error). The format is identified from the file content; there is no `format=` argument.
* `x` is the only file-backed input. `unlinks`, `points`, `points_per_polygon` and `polygon_point_interval` keep their matrix or
  `sf` forms and validation.
* `line_indices` must be `NULL` with a path, otherwise the call fails with `line_indices must be NULL when x is a file path`.
* The result is the ordinary `pst_graph`; its `crs` attribute is the file's CRS.

## 2. File contract

Each feature must be a non-null XY LineString with exactly two finite vertices, in a GeoParquet 1.0/1.1 file with WKB geometry or a
FlatGeobuf file of major version 3. A geographic CRS is rejected. There is no splitting, snapping, repair or reprojection, no
identifier or attribute retention, and at least one line is required. Errors name `axial_graph()` where the caller is mentioned.

## 3. Ordering

Lines are used in the physical order of the file, without reordering. For axial graphs the order matters beyond numbering: it fixes
line IDs, the order of every per-line result, the order of crossings and which crossing an unlink removes (an unlink removes the
nearest eligible pairwise crossing, and eligibility is decided on the first line of the pair; see
[axial inputs](../compatibility/axial-inputs-junctions.md)). A spatially indexed FlatGeobuf is stored in Hilbert order, so the same
data written with and without an index can give different unlink results and different crossing and line numbering. Write files
without a spatial index when the writer's order must be preserved (GDAL: `SPATIAL_INDEX=NO`), and compare a file graph only with
a matrix or `sf` graph built in the same physical order.

## 4. CRS

The file's CRS (GeoParquet `crs`, FlatGeobuf `Crs` table) is the reference for `unlinks` and `points`. `sf` `unlinks` and
`points` must have an equal CRS; a known CRS cannot be mixed with an unknown one in either direction; a geographic CRS is rejected.
Matrix `unlinks` and `points` carry no CRS: their coordinates must already be in the file's coordinate frame, which is the
caller's responsibility. See the [CRS policy](sf-adapters.md#crs-policy).

## 5. Memory

PST needs the complete line set in memory. The file route removes the input representation but not PST's own graph, and it does
not hold an extra R matrix copy, so the saving is largest compared with an `sf` LINESTRING layer.

## 6. Not supported

File-backed `unlinks` and `points`, indexed coordinate tables from files, external identifiers, geometry-column selection,
directories and multi-file input, GeoArrow encodings, GeoParquet 2.0.
