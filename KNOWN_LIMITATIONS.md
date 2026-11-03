# Known limitations

This page lists the verified restrictions of rPSTool that affect functionality, supported inputs, interpretation or
practical use. Each entry names the affected functions, the restriction, its practical consequence and any workaround.
The function help pages describe the same points where they apply.

## Analyses

### Angular Choice: network depth

**Affects:** `angular_choice()`, and to a lesser extent `angular_integration()`.

Angular Choice may encounter computational limitations in exceptionally deep network configurations, particularly with unrestricted analysis radii. This has only been observed in artificially constructed networks with thousands of consecutively connected segments, not in real-world street networks. Restricting the analysis radius avoids the observed limitation.

### Combined radius limits can be very slow

**Affects:** `network_reach()`, `attraction_reach()` and other analyses that accept several limits at once.

Combining a walking, angular or axmeter limit with another independently compared limit, without a `steps` limit, can make
PST's search very slow or exhaust memory on dense networks. Examples are `walking` with `axmeter` in `network_reach()`, and
`attraction_reach()` with its default `distance = "steps"` and a walking radius. Results are not affected. Add a `steps` limit,
or in `attraction_reach()` use `distance = "none"` or the distance that matches the radius.

### Network Integration accepts only step radii

**Affects:** `network_integration()`.

Only unrestricted analysis or a `steps` radius is accepted, as in the official PST for QGIS plugin; other limits are rejected
before any calculation. For walking, straight or angular integration use `angular_integration()` on a segment graph, or
`network_reach()`.

### Axmeter radii

`axmeter` radii are rejected by `angular_integration()`, `angular_choice()`, `od_betweenness()` and `attraction_distance()`
because PST ignores or cannot evaluate them. `segment_group_integration()` accepts only `walking` and `steps` radii.

### Multi-radius calls are limited to the angular analyses

Only `angular_choice()` and `angular_integration()` accept an `analysis_radius()` with several values in one field. Every other
analysis rejects it before doing any work; call it once per radius instead.

### Graph and construction restrictions

* **Segment graphs:** endpoint connectivity must be exact, with at most 32 segment endpoints at any one coordinate, otherwise
  the angular analyses reject the graph.
* **Segment groups:** `segment_group_graph()` rejects a segment graph containing a zero-length segment, because PST's
  construction does not terminate on one. Remove or repair such segments first.
* **Segment maps:** `create_segment_map()` rejects inputs where PST's detail reduction would merge a chain of segments back onto
  its own starting point. This includes closed rings with no junction (which crash unmodified PST) and loops attached at a single
  junction of degree three or more. The check never alters a result, but it can reject inputs that unmodified PST would
  process. A smaller `deviation`, or breaking the cycle, may avoid the error.
* **Isovists:** at most 256 groups in total and 2^24 objects per group.

### Analyses and routines not available

PST's experimental Fast Segment Betweenness and its Visual Connectivity stub are not provided, and neither is PST's native
logging callback. rPSTool uses PST's native progress reports internally for its console progress line, for the analyses and
construction functions listed in [`docs/progress.md`](docs/progress.md); it does not estimate percentages and shows no progress
for functions whose PST routine reports none. It offers no public API for user-defined progress callbacks, and a running
analysis cannot be cancelled through the progress callback: it completes unless the R process is terminated.

## Inputs and outputs

* **Coordinates and units.** rPSTool never reprojects, snaps, splits or reorders geometry. A known geographic CRS (degrees) is
  rejected, so transform to a projected CRS first; radii are in the units of the coordinates. An unknown CRS is allowed on your
  responsibility, and a coordinate matrix has no CRS at all.
* **Precision.** PST stores coordinates relative to a centre point in single precision, so lengths, positions and results carry
  single-precision rounding.
* **Geometry types.** The graph constructors accept two-vertex lines only (matrices, or `sf` LINESTRINGs with exactly two vertices).
  Polylines are never split automatically; use `create_segment_map()` to prepare a network.
* **File input.** GeoParquet (1.0/1.1, WKB) and FlatGeobuf (major version 3) files with two-vertex LineStrings are read in their
  physical file order, and external identifiers are not retained. A spatially indexed FlatGeobuf is stored in Hilbert order, so
  the segment order differs from the original; write with `SPATIAL_INDEX=NO` to keep the order. GeoParquet 2.0, native GeoArrow
  encodings, directories, several files and cloud paths are unsupported. Peak memory when reading GeoParquet depends on the
  Parquet row-group size.
* **Result files.** `output_file` and `spatial_output_file` need the suggested package 'arrow' (>= 25.0.0). On Windows, replacing an
  existing file fails, leaving the old file intact, while another process holds it open without sharing it for deletion.
* **Graphs cannot be saved.** Graphs, isovist contexts and rasters live in native memory and cannot be written with `saveRDS()`
  or sent to another R process; rebuild them from the coordinates.
* **Threads.** PST creates worker threads. rPSTool caps them with the environment variable `RPST_NUM_THREADS`, and uses at most two
  while R's `_R_CHECK_LIMIT_CORES_` is set. `od_betweenness()` always runs on a single worker thread.

## Platform validation

The full development test suite and `R CMD check` passed at commit
[`4119f2b`](https://github.com/kimonkrenz/rPSTool/commit/4119f2b847bafedff84f6d6fbf357196aed77add) on Linux x86-64 (GCC 15.2.0),
macOS ARM64 (Apple clang 17.0.0) and Windows x86-64 (GCC 14.3.0), all with R 4.6.2. This is the extent of platform testing. The
Windows run recorded 160,759 test expectations against 160,814 on the other two platforms; the difference has not been
independently explained.

The output-naming and progress changes were later validated locally by the maintainer on the tree of `96a1547` (reported identical
to the rebase-merged `c6c4ed9`): macOS ARM64 with 161,539 expectations and `Status: OK`, and Windows x86-64 with 161,484
expectations, four approved skips and `Status: OK`. Linux, CRAN incoming checks and a release tarball have not been validated at
that tree.

rPSTool's inputs and defaults were checked against the code of the PST for QGIS plugin, but its results have not been compared
with real runs of the plugin. Intentional differences are listed in
[QGIS differences](docs/compatibility/qgis-differences.md).

## Example data

The Barnsbury example data are derived from Hillier and Iida (2005) and include the axial network, unlinks and observed movement
gate counts. The geometries were georeferenced and spatially transformed by Kimon Krenz, so the coordinates are not the original
coordinates and the data were not originally supplied in British National Grid. The data are included and redistributed with
permission from the authors, and the original research and data remain attributable to them. See
[example data](docs/example-data.md).

## Reporting problems

Please report bugs at <https://github.com/kimonkrenz/rPSTool/issues>.
