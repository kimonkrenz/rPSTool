# Axial file input — `axial_graph(<path>)`

`axial_graph(<path>)` builds an axial graph from one GeoParquet or FlatGeobuf file through an axial builder that is shared with the
matrix route (extracted, not copied). This document records what the code does and how it is tested. It extends the file contracts of
[GeoParquet](geoparquet-input.md) and [FlatGeobuf](flatgeobuf-input.md) to the axial graph family without changing either decoder.
Nothing here changes any PST algorithm, the `segment_graph()` routes, or the matrix/indexed-matrix/sf behaviour of `axial_graph()`.

## 1. Public API

```r
axial_graph(x, line_indices = NULL, unlinks = NULL, points = NULL,
          points_per_polygon = NULL, polygon_point_interval = NULL)
# x: numeric matrix | sf/sfc | ONE character path to a GeoParquet or FlatGeobuf file
```

* A character vector without a `dim` attribute is the file route (a character *matrix* still takes the unchanged
  matrix path and error). The format is identified from the file's **content** (shared with `segment_graph()`:
  `R/file-input.R`); there is no `format=` argument and no extension dispatch.
* `x` is the only file-backed input. `unlinks`, `points`, `points_per_polygon` and `polygon_point_interval` keep their
  established matrix or sf forms and their established validation.
* `line_indices` **must be `NULL`** with a path: `line_indices must be NULL when x is a file path`. A LineString
  file defines its lines directly; indexed coordinate tables are unchanged for matrices and POINT sf input.
* The result is the ordinary `pst_graph` (class, fields, tag, finaliser, counters), built by the same
  `.pst_axial_graph_object()` helper as the matrix route; its `crs` attribute is the file's CRS.

## 2. File contract (inherited unchanged)

Per-format rules are those of docs 33/35: single non-null XY LineString features with exactly two finite vertices,
GeoParquet 1.0/1.1 WKB or FlatGeobuf major version 3, geographic CRS rejected, no splitting/snapping/repair/
reprojection, no IDs or attributes, at least one line. The axial route reuses the decoders; only the diagnostic
wording that names the calling API differs (`an axial graph needs at least one line`, `Too many lines for the PST
graph descriptor`, and the optional-package messages name `axial_graph()`).

## 3. Ordering (important for axial graphs)

Lines are used in the file's **physical order**, with no reordering. For axial graphs the order matters beyond
numbering: it fixes line IDs and the order of every per-line result, the order of crossings, and — because an unlink
removes the nearest eligible pairwise crossing and eligibility is decided on the first line of the pair
([19](../compatibility/axial-inputs-junctions.md)) — *which crossing an unlink removes*. A spatially indexed FlatGeobuf is stored in
Hilbert order, so the same data written with and without an index can give different unlink results and crossing/
line numbering. Compare a file graph only with a matrix or sf graph built in the **same physical order** (the tests
use GDAL's own read order as the independent oracle). Write files without a spatial index (GDAL: `SPATIAL_INDEX=NO`)
when writer order must be preserved.

## 4. CRS

The file's CRS (GeoParquet `crs`, FlatGeobuf `Crs` table, option Q) becomes the reference of
`.pst_sf_crs(unlinks, points, reference = <file CRS>)`: sf `unlinks`/`points` must have an equal CRS; a known CRS
cannot be mixed with an unknown one in either direction; geographic CRS is rejected. Matrix auxiliaries carry no CRS
and are used on the caller's responsibility (their coordinates must already be in the file's frame). Reconciliation
and sf-to-matrix conversion happen after the file's header/metadata is read and before any native pointer exists.

## 5. Native data flow and ownership

```
path ─ R: validate, identify format, read header/metadata, CRS, reconcile with sf aux, stage matrices
     ─ R: empty axial pointer (tag rPST::HPSTAGraph/v1, finaliser registered)
     ─ native: stage_axial_auxiliary()  (R errors only; views into protected .Call arguments)
     ─ native: decode (unchanged FlatGeobuf/Arrow decoders) → ONE transient std::vector<double2> (2 per line)
     ─ native: rpst::axial_graph_build() → axial_build_core() → PSTACreateGraph
     ─ native: C++ owners unwind, THEN Rf_error (if any)
```

* `src/pst-axial-build.h` mirrors `pst-segment-build.h`: `axial_graph_new_pointer`, `axial_graph_require_empty`,
  `stage_axial_auxiliary`, `axial_graph_build`. `axial_build_core()` is the original in-line body of
  `create_axial_graph()` **extracted, not copied**: the matrix, indexed-matrix and file routes all call it, so the
  origin/extent/float-representability/polygon-bound logic exists once. Polygon-partition staging is likewise one
  helper (`stage_polygons`). The indexed-coordinate origin semantics (unused coordinates still set the world origin)
  are preserved; the file route is always non-indexed.
* Auxiliary views are validated before any C++ owner exists; extents of unlinks/points are checked against the
  decoded lines inside the core, exactly as for matrices.
* Builder failures leave the empty pointer unpublished (`created` is not incremented; the finaliser ignores a NULL
  address). No partially constructed graph is ever published.

## 6. Memory (measured, not a streaming claim)

PST needs the complete line set in memory. The file route removes the **input** representation, not PST's own graph.
Measured on Linux x86-64 (~0.98 M-line lattice, R matrix input): peak RSS 351 MiB for the axial graph (248 MiB for a
segment graph) against a 57 MiB package baseline; the 30 MiB input matrix is a minor share. For reference, an
`sf` LINESTRING layer costs about 624 B per feature versus 32 B per line for the transient coordinate array, so the
saving is large against `sf` and modest against a bare matrix. The file route holds the 32 B/line transient array
only while the graph is built; it does not additionally hold an R matrix copy.

## 7. Tests

`tests/testthat/test-axial-file-input.R` (helpers in `helper-axial-file.R`; fixtures in
`tests/testthat/fixtures/axial-files/`, generated by `tools/make-axial-file-fixtures.R` and
`tools/make-axial-parquet-fixtures.py`, hashes in `MANIFEST.tsv`):

* the line geometry of every non-indexed direct-pinned-PST axial reference case (24 cases: crossings, T junctions
  with order-dependent unlinks, coincident crossings, degenerate lines, points, polygon-generated point groups,
  separators, empty groups) is written as FlatGeobuf and GeoParquet and the file-built graphs are checked against the
  **direct PST values** (lengths, crossings, retained point state and groups, Network Integration lines and
  junctions across all radius settings);
* file vs matrix vs sf equivalence (bit-identical) on the same coordinates in file order;
* physical-order tests on a spatially indexed FlatGeobuf (GDAL's read order as oracle; the unlink result provably
  differs from writer order);
* CRS retention and every reconciliation branch (match, different known, unknown vs known both ways, geographic);
* argument contract (`line_indices` rejected, auxiliary validation, directories/NA/multiple paths, character matrix
  unchanged) with no native graph created on any failure;
* malformed/unsupported files for both formats, 150 random single-byte corruptions, extent/overflow against the
  file's lines and the auxiliary inputs, polygon sampling bounds, accurate API naming in messages;
* lifecycle: counters, explicit/repeated release, aliasing, outputs outliving the graph, serialisation, GC
  finalisation, exact-tag rejection of segment pointers, non-reusable pointers.

The existing `test-axial-inputs.R` direct-PST suite, `test-pst-graph.R`, `test-sf-graphs.R` and the GeoParquet/
FlatGeobuf/segment suites run unchanged. Valgrind over a script exercising both file routes (success paths with
unlinks/points/polygons, extent/polygon-bound failures, empty files and the `line_indices` error) reports 0 bytes
definitely lost, no invalid reads or writes and no frame in `rPSTool.so`; its single report is libarrow's mimalloc
start-up (third party), as for the segment-graph file routes.

## 8. Platforms and limitations

The axial file route passed the complete local validation (`tools/ci/check-local.R`) on Linux x86-64 and native macOS Apple Silicon when it
was added, and the later full validation on Windows 11 x64 covered it, including the Windows-specific FlatGeobuf paths (`_wfopen`,
`_fseeki64`, Rtools generation of the `base.h` build copy) that `axial_graph()` shares with `segment_graph()`. The route adds no translation
unit, vendored file or build rule. The final release state still needs the clean three-platform run in the
[release checklist](../release-checklist.md).

Not implemented: file-backed `unlinks`/`points`, indexed coordinate tables from files, external IDs, geometry-column selection,
directories/multi-file input, GeoArrow encodings and GeoParquet 2.0.
