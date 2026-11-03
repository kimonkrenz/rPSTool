# Raster comparison, inspection and polygon results

Computed by PST v3.3.2 (commit `63df80a2cf3dd289be95ea3d91667c3490719b75`).
PST's normalisation calls an unqualified `abs` on native float extrema, which resolves to an integer overload on some toolchains;
rPSTool uses the floating absolute value (`std::abs`) on every toolchain, which is the only arithmetic change to PST's raster code.

## Public interface and native computation

| R interface | Pinned export | Storage / ownership |
| --- | --- | --- |
| `compare_line_results()` | `PSTACompareResults`, descriptor v4 | Persistent comparison owner; the raster belongs to it |
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
blur, extrema scan, reciprocal and multiplication. The change is `std::max(abs(min), abs(max))` →
`std::max(std::abs(min), std::abs(max))`. Reported extrema precede
normalization. Zero floating denominators are not special-cased. All-zero scores produce min/max zero
and native NaN pixels. Equal nonzero scores can retain float accumulation
residuals. Zero blur with explicit positive resolution retains native NaN kernel
results and initialized extreme min/max values. Large scores and floating
overflow retain native floating behavior.

Relative Percent remains `100 * (max(after, M) / max(before, M) - 1)` after
independent native blurs. Nonpositive M is allowed; zeros, signed scores and
native nonfinite results are preserved.

Polygon ranges use native float limits, minimum inclusive and maximum exclusive.
Infinite limits are allowed; equal/reversed, overlapping, duplicate and empty
ranges retain native results and order. Each polygon contains its outer ring
then holes in PST order; rings are not artificially closed. PST's out-of-grid
interpolation uses zero and can yield nonfinite coordinates in boundary ranges.
Those vertices are copied as PST wrote them, without repair or orientation change; there is no NA substitution.

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

## Limits and errors

`compare_line_results()` requires positive finite resolution, non-negative blur radius, finite float-representable coordinates and
scores, and matching score and line counts. Zero-area extents are rejected. A grid with more than UINT32_MAX / 4 pixels (about 1.07
billion, float storage above 4 GiB) is rejected; below that limit the allocation is attempted, so a very small `resolution` can exhaust
memory. Polygon counts and ring sizes are checked against the grid; native metadata, not mutable R attributes, governs interpretation.

The comparison handle owns its raster and is released by `raster_free()` (idempotent; later use of an alias is an error). Dead,
deserialised or wrong-family pointers are errors. Returned R values remain valid after release.

Reference fixtures and checks: [`tools/reference/README.md`](../../tools/reference/README.md). Build adaptations of PST's raster code
(allocation overflow checks, bounded kernel storage, worker cap, exception propagation) change no successful result; see
[patch provenance](../../inst/upstream/PATCHES.md).
