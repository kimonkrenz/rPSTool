# Raster comparison, inspection and polygon results

Authority: PST v3.3.2 `63df80a2cf3dd289be95ea3d91667c3490719b75`.
The pinned normalisation calls an unqualified `abs` on native float extrema, which resolves to an integer overload on some toolchains
(a 75-case comparison of the integer and floating results, `tools/reference/raster/check-abs-overloads.py`, established the ambiguity).
Floating absolute values are the adopted public numerical contract on every toolchain; the contract does not preserve the earlier Linux
integer-overload result.

## Public interface and native computation

| R interface | Pinned export | Storage / ownership |
| --- | --- | --- |
| `compare_line_results()` | `PSTACompareResults`, descriptor v4 | Exact-tagged persistent comparison owner; raster is borrowed from it |
| `raster_data()` | `PSTAGetRasterData`, descriptor v1 | Copies bbox, dimensions, pitch, format, comparison extrema and pixels |
| `raster_to_polygons()` | `PSTARasterToPolygons`, descriptor v1 | Copies range → polygon → ring matrices; transient result freed immediately |
| `raster_free()` | `PSTAFree` | Idempotent release of comparison, invalidating aliases |

Four-column line matrices contain x1/y1/x2/y2. With no second geometry layer,
both score vectors address the first layer; otherwise their lengths match their
respective layers. Coordinates stay double and intensities/parameters narrow to
native float. Both modes retain signed intensities and the native zero-length
line behavior. Extents include both layers, inflate by three blur radii and snap
to resolution. Pixel centers lie half a pixel inside the extent. The result is
flipped vertically by PST: matrix rows descend from maximum y and columns ascend
from minimum x. No input geometry snapping or CRS conversion occurs.

Normalized mode retains PST's rasterization, difference accumulation, Gaussian
blur, extrema scan, reciprocal and multiplication. The **sole arithmetic source
adaptation** is `std::max(abs(min), abs(max))` →
`std::max(std::abs(min), std::abs(max))`. Float extrema select the floating
overload consistently across supported toolchains. Reported extrema precede
normalization. There is no reimplementation, clamp, substitute result or special
handling for zero floating denominators. All-zero scores produce min/max zero
and native NaN pixels. Equal nonzero scores can retain float accumulation
residuals. Zero blur with explicit positive resolution retains native NaN kernel
results and initialized extreme min/max values. Large scores and floating
overflow retain native floating behavior.

Relative Percent remains `100 * (max(after, M) / max(before, M) - 1)` after
independent native blurs. Nonpositive M is allowed; zeros, signed scores and
native nonfinite results are preserved. None of this mode's arithmetic changes.

Polygon ranges use native float limits, minimum inclusive and maximum exclusive.
Infinite limits are allowed; equal/reversed, overlapping, duplicate and empty
ranges retain native results and order. Each polygon contains its outer ring
then holes in PST order; rings are not artificially closed. PST's out-of-grid
interpolation uses zero and can yield nonfinite coordinates in boundary ranges.
Those vertices are copied without repair, substitution, orientation changes or
`sf` materialization. No missing-output/typed-NA policy applies to these written
native floating values.

## Optional sf adapters

sf is optional; native matrix output remains the authority and default.
`compare_line_results()` accepts two-vertex XY LINESTRING sf/sfc for `x`/`y`
(values stay explicit; attributes ignored; CRS retained on the owner as
`attr(raster, "crs")`). `raster_data()` is deliberately not converted.
`raster_to_polygons(output = "sf")` returns a list of `sfc_POLYGON`, one per
range, one POLYGON per native polygon, native outer ring then holes, adding only
one structural closure when absent and failing explicitly (range/polygon/ring) for
rings that cannot be represented without inventing geometry (fewer than three
rows, nonfinite coordinates, closed rings with fewer than four rows). Full
contract and fixture counts: [sf adapters](../spatial-io/sf-adapters.md#raster-comparison-adapters).
No native raster computation, ownership or numerical policy is changed.

## Ownership and safety

The comparison handle exclusively owns its raster. Only that handle is freed;
the borrowed raster is never separately destroyed. Repeated data/polygon calls
reuse the owner. A polygon conversion acquires a distinct `IPSTAlgo` handle,
keeps the comparison protected while copying, and releases the result on success,
native failure, allocation failure or R non-local copy error. `R_UnwindProtect`
provides the R error cleanup; no owning C++ vector survives into that copy.
Native exceptions unwind before an R error is raised. Returned R values remain
usable after release, GC and input lifetime changes. Dead/deserialized pointers
and wrong exact native tags fail before access. Private counters and copy-fault
controls are registered test infrastructure, not public APIs.

Native validation independently checks storage, dimensions, count/score matching,
finite coordinates, float narrowing/underflow, positive resolution, nonnegative
blur, snapped extent dimensions, kernel/sample integer bounds, world/local
float conversions, squared-distance overflow and unsigned raster byte arithmetic.
Zero-area extents are rejected before unsafe grid accesses. Polygon counts/ring
sizes are checked against native grid traversal and R matrix bounds; native
metadata rather than mutable R fields governs interpretation.

Verified generated copies guard raster pitch/allocation overflow and malloc
failure, replace the Gaussian kernel's unbounded stack allocation with scoped
heap storage, apply the existing central worker cap, and use future `get()` to
propagate exceptions. A comparison-only generated `Arr2d.h` overlay guards
zero/single-row FlipY and checks its row-buffer allocation. None of these safety
edits changes successful PST arithmetic or row/partition ordering. No worker
calls R; progress callbacks stay null. See [patch provenance](../../inst/upstream/PATCHES.md).
Vendor and preserved reference bytes remain unchanged.

## Validation and reproduction

The oracle verifies 127 exact source blobs, including the complete core and
relevant exported descriptors, official ctypes wrapper, QGIS callers and test.
The unchanged upstream comparison smoke test runs; it has no numerical predicate,
so it is supplemented by 79 exact native cases. Coverage includes both modes,
multiple blur/resolution pairs, signed/equal/zero scores, separate geometries,
zero-length lines, translated coordinates, polygons with holes, all range forms,
zero blur, large scores, genuine zero floating denominator and floating overflow.

`tools/reference/raster/check-floating-normalization.py` builds an independent pinned TU
with only the approved std::abs substitution, a float-cast-overflow sanitized
variant, and the unchanged TU with standard floating math-header overloads.
All 79 pixel/metadata/polygon results match byte-for-byte with each other and the
package exported C API. All 41 Relative Percent cases match unchanged pinned
PST, including its extra overflow control. The compact `tools/reference/raster/floating-normalization-results.json` records the
source adaptation and all per-case result hashes. The 79-case offline R fixture
regenerates byte-for-byte and installed tests compare every field and vertex
exactly, twice per owner. Python remains development-only.

`tools/reference/raster/check-native-safety.py` exercises generated-source native
allocation overflow/failure, float/byte inspection, zero/single-row FlipY,
row-buffer failure before mutation, successful reversal and late worker failures
in both blur passes at caps 1/2/8. It has no installed hooks. Original overload
and sanitizer evidence remains reproducible with
`tools/reference/raster/check-abs-overloads.py`, which selects the original 75-case
inventory internally.

Example development commands (activate the configured R toolchain first):

```sh
python3 tools/reference/raster/check-floating-normalization.py PINNED_ROOT LIBR BASELINE_DLL PACKAGE_DLL work/raster-approved
python3 tools/reference/raster/write-r-fixture.py work/raster-approved/approved.json work/raster-regenerated.R
python3 tools/reference/raster/check-native-safety.py PINNED_ROOT LIBR PACKAGE_DLL work/raster-safety-probe
Rscript tools/ci/check-local.R
```

Portable source gates cover all four exact input/output checksums, unique patterns,
full inverse bytes, deterministic regeneration, output publication, vendor/path/
symlink rejection, generated drift, header dependency/selection and Unix/Windows
recipes. Clean-build lifecycle proves installed DLL operation after generated
state is removed. The full local suite includes all previous family regressions
and strict source-package checks. Native macOS and Windows execution is covered by the
platform runs described in [build and platforms](../build-and-platforms.md).
