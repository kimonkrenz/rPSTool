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
vendored engine with R's own C++17 toolchain (`src/Makevars`, `src/Makevars.win`) and never downloads anything.

## Design principles

* Preserve PST semantics and terminology; bind exported PST C functions rather than reimplementing algorithms.
* Build a native graph once and reuse it across compatible analyses.
* Keep large geometry out of R when unnecessary; do not store duplicate geometry in the R graph wrapper.
* Make provenance explicit; treat algorithm changes as upstream work, not routine rPSTool work.
* Separate three concepts: the theoretical spatial representation, the PST native graph/container type, and the analysis
  distance/radius semantics. Analyses expose them independently, as PST does.

## Pinned upstream source

* Repository `https://github.com/SMoG-Chalmers/PST`, release `v3.3.2`, annotated tag object
  `517bd88ba12a67558cbd8db2d6472e84bb54d7b0`, commit `63df80a2cf3dd289be95ea3d91667c3490719b75`. Never `master`.
* The complete C++ core (`include/` and `src/`, plus upstream build metadata) is vendored under `src/vendor/pstalgo/`; the
  Python binding and QGIS plugin layers are not part of the package. The vendoring helper `tools/vendor-pstalgo.R` is a
  development tool only.
* The vendored tree is **pristine**: its bytes are verified against `inst/upstream/FILES.md5` by `tools/verify-vendor.R`.
  Platform-compatibility and safety adaptations are applied only to generated, checksum-verified build copies under
  `src/.rpst-build/` (outside Git and the source tarball) by fail-closed transformations in `src/portability/`. Each
  transformation verifies its exact input, fails on drift, modifies only the intended lines and is covered by
  mutation/rejection tests. `inst/upstream/PATCHES.md` records every adaptation; `inst/upstream/PROVENANCE.md` records the
  pin. Preserved exact inputs of transformed files are under `inst/upstream/build-inputs/`.
* A downstream change that would alter PST's numerical or algorithmic behaviour is not made. Upstream fixes, if desirable,
  are prepared as reproductions or patches inside this repository for human review and are never written to the upstream
  repository.
* Adopting a later PST release requires a deliberate change that replaces the vendored source, reviews upstream API changes,
  re-derives the build-copy transformations, re-runs every reference test and the platform checks, and updates
  `inst/upstream/PST_VERSION` and the provenance files.

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

Native graph families are never cast, reinterpreted or converted into one another, and an analysis' graph family is that of its
descriptor, not inferred from its name. Each graph is held by an exactly tagged external pointer with a finaliser; aliases share
ownership, serialisation restores a dead pointer, and a dead or foreign pointer is rejected before any native storage is read.

`SPSTAGraphInfo` has a declared but undefined pinned constructor; the bridge provides descriptor-version-1 zero initialisation
and obtains counts from PST rather than from R metadata. Segment owners retain only the genuine handle, the verified segment
count and the maximum endpoint incidence (PST exports no segment-count getter). Exact double endpoint equality establishes
connectivity before conversion to local floats; near endpoints, interior crossings and endpoint-on-interior contacts are not
connected. Row order, zero-length and short lines are retained. Local float extents, double endpoint sums/centres and lengths
are validated without rescaling. Construction accepts high-degree graphs; angular analyses alone reject more than 32 endpoint
incidences because the native path mask is 32-bit.

Optional `sf` support, file input and file output are adapters around this same core ([spatial I/O](spatial-io/README.md)).

## Bridge, ownership and exceptions

The bridge is a small registered base `.Call` interface with forced-symbol lookup. R errors perform non-local jumps, so:

1. R-facing storage and types are validated, and ALTREP data materialised, before any owning C++ temporary exists;
2. R output objects are allocated before native owning buffers where practical;
3. native work runs in a C++ scope that captures failures into ordinary state or error buffers and never lets an exception
   cross into R;
4. all C++ temporaries unwind, and only then is an R error raised.

Finalisers clear the pointer before the matching free call, so release is safe to repeat. Input storage is not retained after a
synchronous call, and result vectors are independent R copies that outlive the native owners. Verified constructor RAII protects
unpublished handles on early return and exceptions.

Transient native results (junction and segment-map outputs, isovist results, raster polygons) are owned by handles that are
freed by `R_UnwindProtect` cleanup after the arrays are copied, on success and on a non-local R error; no result handle escapes.
Isovist contexts and raster comparisons are the only persistent owners besides graphs.

## Threading

PST worker threads never call the R API. The boundary is: R main thread → PST call → C++ workers → workers join → R main
thread. Progress and cancellation callbacks are not bound; synchronous calls pass null callbacks.

The central worker policy (`src/rpst-workers.cpp`, applied to the exposed asynchronous engines through verified build copies)
resolves the worker count as follows. `RPST_NUM_THREADS` is an explicit positive integer cap; an invalid value fails before
workers start (on Windows an empty value removes the variable and selects the fallback). The fallback is native hardware
concurrency with a floor of one. The check cap follows R's own convention (`parallel:::.check_ncores`):
`_R_CHECK_LIMIT_CORES_` is active when set to any non-empty value other than `false`, compared case-insensitively, and is then a
**ceiling of two**: a stricter explicit cap still applies, a larger one cannot lift it. Caps never exceed hardware concurrency.
OD Betweenness keeps exactly one asynchronous worker, as upstream does. No traversal, weighting, depth, accumulation or
normalisation equation changes.

## Registered entry points

`src/init.c` registers 90 routines; 59 are reached from the 25 exports through `R/`. The remaining 31 are reachable only as
`rPSTool:::C_<name>` or through `getDLLRegisteredRoutines()`:

* **Test and fault-injection hooks**, shipped on purpose (including `rpst_output_remove_entry`, which removes a file or symbolic link without following it, used by tests because R's `unlink()` cannot remove symbolic links on Windows): angular run counters with a one-shot failure countdown, the result
  and Arrow test producers/consumers, the addressable-limit hook, and the segment-group output test routines. The package tests
  run against the installed binary, so a compile-time switch would make the shipped binary differ from the tested one. The hooks
  validate their arguments, are one-shot or read-only, use atomic counters, and no behaviour reachable from the exported API
  depends on them.
* **Read-only lifecycle and diagnostic routines** used by `tools/test-build-lifecycle.R` and the tests (native smoke probe,
  worker count, result counters, stream liveness/release, per-owner lifecycle counters and release routines, retained point
  state).
* **Earlier native entry points** with narrower signatures (`rpst_graph_create`, `rpst_network_integration`, `rpst_reach`,
  `rpst_betweenness`, `rpst_angular_integration`, `rpst_angular_choice`), kept for the regression tests.

Hiding the roughly 381 exported shared-library symbols with `-fvisibility=hidden` was measured to work on Linux (48 remain)
but changes `Makevars`/`Makevars.win` and needs Windows verification; it is an optional item in the
[release checklist](release-checklist.md).

## Source grounding for each binding

Before a binding is added, the pinned header, implementation and, where useful, the Python ctypes wrapper and upstream tests are
inspected: descriptor version, pointer types, array lengths, optional outputs, callback expectations and free/lifecycle
routines. Signatures are never inferred from function names. A declaration in a header is not evidence that functionality works;
see [PST coverage](pst-coverage.md) for what is exposed and what is not, and [compatibility](compatibility/) for the exact
contract of every family.
