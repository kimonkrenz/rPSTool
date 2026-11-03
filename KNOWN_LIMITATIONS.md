# Known limitations

Restrictions of rPSTool that affect functionality, supported inputs, interpretation or practical use.

## Analyses

### Angular Choice: network depth

**Affects:** `angular_choice()`, and to a lesser extent `angular_integration()`.

PST's Angular Choice (and, to a lesser extent, Angular Integration) follows shortest-path chains recursively on worker threads, with no
depth bound. A very long chain of shortest-path steps can exhaust a worker thread's stack, which terminates the R process. How deep the
chain gets depends on the network's topology and on the radius, not on its size; the point at which the stack runs out depends on the
platform and build. A radius restriction reduces the risk: a `steps` radius bounds the depth roughly by the step limit, and walking and
straight limits shrink the reachable area, while an angular limit does not bound runs of near-collinear segments. rPSTool does not
change PST's computation and has no guard.

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

PST's experimental Fast Segment Betweenness and its Visual Connectivity stub are not provided, and neither is PST's native logging
callback. There is no API for user-defined progress callbacks, and a running analysis cannot be cancelled; it completes unless the R process
is terminated. Which functions show a console progress line is described in [`docs/progress.md`](docs/progress.md).

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

## Platforms and comparison with PST for QGIS

rPSTool targets Linux, macOS and Windows; see [build and platforms](docs/build-and-platforms.md).

rPSTool's inputs and defaults were checked against the code of the PST for QGIS plugin, but its results have not been compared with real
runs of the plugin. Intentional differences are listed in [QGIS differences](docs/compatibility/qgis-differences.md).

## Example data

The Barnsbury example data (Hillier and Iida, 2005) were georeferenced and spatially transformed, so the coordinates are not the original
coordinates. They are included with the authors' permission and remain attributable to them; see [example data](docs/example-data.md).

## Reporting problems

Please report bugs at <https://github.com/kimonkrenz/rPSTool/issues>.
