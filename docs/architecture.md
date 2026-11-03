# Architecture and native integration

rPSTool is a language binding and R workflow layer around the `pstalgo` engine of the Place Syntax Tool (PST). It is not a
new implementation of space-syntax or network algorithms.

```text
R
 ↓
small registered .Call bridge (src/init.c, src/pst-*.cpp)
 ↓
pinned PST exported C API
 ↓
vendored pstalgo C++ (src/vendor/pstalgo/)
```

No Python, `reticulate`, QGIS, Rcpp or separately installed PST is needed at build or run time. The package compiles the
vendored engine with R's own C++17 toolchain (`src/Makevars`, `src/Makevars.win`) and never downloads anything. Build
and platform details are in [build and platforms](build-and-platforms.md).

## Pinned upstream source

* Repository `https://github.com/SMoG-Chalmers/PST`, release `v3.3.2`, annotated tag object
  `517bd88ba12a67558cbd8db2d6472e84bb54d7b0`, commit `63df80a2cf3dd289be95ea3d91667c3490719b75`. The pin is recorded in
  `inst/upstream/PST_VERSION` and `inst/upstream/PROVENANCE.md`.
* The complete C++ core (`include/` and `src/`, plus upstream build metadata) is vendored under `src/vendor/pstalgo/`; the
  Python binding and QGIS plugin layers are not part of the package.
* The vendored tree is byte-identical to upstream: it is verified against `inst/upstream/FILES.md5` by `tools/verify-vendor.R`.
  Platform-compatibility and safety adaptations are applied only to generated, checksum-verified build copies under
  `src/.rpst-build/` (outside Git and the source tarball) by transformations in `src/portability/`. Each transformation
  verifies its exact input and fails if the input differs. `inst/upstream/PATCHES.md` lists every adaptation, and the
  preserved exact inputs of transformed files are under `inst/upstream/build-inputs/`.
* Algorithms are not modified: rPSTool results are those of the pinned PST. Intentional differences from PST for QGIS are in
  [QGIS differences](compatibility/qgis-differences.md).

## Native object model

* **Axial / crossing-aware line graph** (`HPSTAGraph`, created by `PSTACreateGraph`, `axial_graph()`; class `pst_graph`):
  used by Network Integration, Reach, Segment Betweenness, Attraction Reach/Distance and OD Betweenness. Despite its name,
  Segment Betweenness uses this graph.
* **Endpoint-connected segment graph** (`HPSTASegmentGraph`, `PSTACreateSegmentGraph`, `segment_graph()`; class
  `pst_segment_graph`): used by Angular Integration, Angular Choice and Segment Grouping. It does not detect interior crossings.
* **Segment-group graph** (`HPSTASegmentGroupGraph`, `segment_group_graph()`; class `pst_segment_group_graph`): a distinct
  owner for Segment Group Integration.
* Isovist contexts and raster comparisons have their own owners; transient construction and polygon results are copied and
  freed before the call returns.

Graph families are never converted into one another, and an analysis' graph family is that of its descriptor, not inferred
from its name. Each graph is held by an external pointer with a finaliser. A serialised graph restores as a dead pointer, and
a dead or foreign pointer is rejected before any native storage is read.

Segment connectivity is established by exact double equality of endpoints: near endpoints, interior crossings and
endpoint-on-interior contacts are not connected. Row order, zero-length and short lines are retained. Construction accepts
high-degree graphs; angular analyses alone reject more than 32 endpoint incidences at one point because the native path mask
is 32-bit.

Optional `sf` support, file input and file output are adapters around this same core ([spatial I/O](spatial-io/README.md)).

## Bridge and errors

The bridge is a small registered base `.Call` interface. No C++ exception crosses into R: native failures are captured and
raised as ordinary R errors after all native temporaries are released. Input storage is not retained after a synchronous
call, and result vectors are independent R copies that outlive the native objects.

## Threading and progress

PST worker threads never call the R API. PST's native progress reports drive the console progress line ([progress
display](progress.md)); PST calls the callback on the thread that made the call (the R main thread), and the callback is
installed only while console progress is active. There is no public API for user-defined progress callbacks, progress cannot
cancel an analysis, and the native log callback is not bound.

The worker count is resolved as follows. `RPST_NUM_THREADS` is an explicit positive integer cap; an invalid value fails before
workers start (on Windows an empty value removes the variable and selects the fallback). The fallback is native hardware
concurrency with a floor of one. Following R's own convention (`parallel:::.check_ncores`), `_R_CHECK_LIMIT_CORES_`, when set
to any non-empty value other than `false` (case-insensitive), is a **ceiling of two**: a stricter explicit cap still applies, a
larger one cannot lift it. Caps never exceed hardware concurrency. OD Betweenness uses exactly one asynchronous worker, as
upstream does. The worker count does not change any traversal, weighting, depth, accumulation or normalisation equation.

## Test hooks

The shared library contains a few test-only routines (angular run counters with a one-shot failure countdown, result-file and
Arrow test producers and consumers, an address-limit hook, and read-only lifecycle diagnostics). They are not exported to R
users and are reachable only as `rPSTool:::C_<name>`. They ship in the installed library so that the tests, including those
run in CRAN mode, exercise the same binary users receive. They validate their arguments, are one-shot or read-only, and no
behaviour reachable from the exported API depends on them.

See [PST coverage](pst-coverage.md) for what is exposed and what is not, and [compatibility](compatibility/) for the exact
contract of every family.
