# Isovist

Computed by PST v3.3.2 (commit `63df80a2cf3dd289be95ea3d91667c3490719b75`) using the singular exported isovist API. The context uses
native matrix geometry; optional [sf adapters](../spatial-io/sf-adapters.md#isovist-adapters) convert to it.

## Public interface and native semantics

- `isovist_context(obstacles, attraction_points, attraction_polygons)` creates
  reusable native state. Polygon families are lists of groups, each a list of
  numeric two-column vertex matrices. Point families are lists of numeric
  two-column point matrices. Empty contexts/groups are supported. Geometry is
  copied into PST; no R input matrices are retained by the owner.
- `isovist(context, origin, max_distance, field_of_view=360, direction=0,
  perimeter_segments=64)` calls PST synchronously with null callbacks. Origin is
  `c(x,y)`; distances are planar native units, direction is counterclockwise
  from positive x and ignored for full-circle views. Native float controls and
  local world-center conversion remain computational authority.
- `isovist_context_free(context)` explicitly invalidates all aliases; repeated
  release is safe. Dead/deserialized and wrong-family pointers are rejected.

Polygon vertices are not closed, repaired, reordered, deduplicated, snapped or
rewound. PST expects Cartesian clockwise rings. Vertex counts must be positive;
empty **groups** remain valid. Counts partition coordinates exactly. All inputs
receive native storage/count/float/distance validation before native calls.
Visibility packing permits at most 256 combined groups and 2^24 objects per group.
The native signed edge/vertex limits are enforced, including perimeter edges.

Radius is nonnegative; view angles range from 0 to 360, including native-written
zero-angle controls. Perimeter resolution is at least three, as required for a
finite area-corrected circle radius. Finite zero-area, singleton and two-vertex
results remain valid whenever their executed native paths are safe. The perimeter
radius is area-corrected by PST, while attraction-point filtering uses the
requested radius. An origin inside an obstacle skips that obstacle. Geometry
computes in local floats; returned world doubles retain any native narrowing or
loss of resolution, including distant-origin controls.

Results contain `polygon` (double x,y matrix in native order, no added closure),
`area` (native float widened exactly), and `visible_obstacles`,
`visible_attraction_points`, `visible_attraction_polygons`. Each visibility
component is a list of integer vectors, one per input group including empty
ones. Object indices are one-based **within their original group**. No global
IDs, sorting or aggregation is introduced. Vector lengths preserve native group
counts; total length preserves native object count. Tree rearrangement does not
change the original within-group associations.

## Optional sf adapters

sf is optional; the native matrix representation and matrix output remain the
authority and default. Each context group may instead be an XY sf/sfc layer:
POLYGON layers (obstacles, attraction polygons) with exactly one ring per feature,
or POINT layers. Holes, empty polygons, MULTIPOLYGON, Z/M and nonfinite
coordinates are rejected. sf's mandatory structural closing coordinate is
removed; all other vertices, order and winding are preserved (never rewound).
CRS is checked across nested layers and kept only as the context `"crs"`
attribute. `isovist(..., output="sf")` replaces only `polygon` with a
length-one POLYGON sfc from the copied native vertices (first vertex appended
only if not already closed; error for fewer than three vertices, nonfinite
coordinates or fewer than four ring coordinates). Details:
[sf adapters](../spatial-io/sf-adapters.md#isovist-adapters).

An sf ring cannot distinguish a repeated terminal vertex from its structural closure, so matrix input that deliberately repeats a vertex
should stay in matrix form. Open rings and rings with a repeated terminal vertex give identical native results.

## Lifetime and errors

`isovist_context()` returns an external pointer that owns the native context; it cannot be saved, serialised or transferred to another R
process. Use `isovist_context_free()` to release it explicitly. A dead, deserialised or wrong-family pointer is an error. Results are
copied into R and remain valid after the context is released.

PST can fail to produce a result for some unusual geometries; rPSTool then raises an R error instead of returning a partial result or
crashing. This happens when the calculated polygon has no vertex, or too few vertices for a non-empty attraction queue: fewer than two
for partial-view attraction points or full-circle attraction polygons, fewer than three for partial-view attraction polygons. Singleton
results with empty queues are valid. No polygon, zero area or NA is substituted.

## Floating point

Polygon coordinates are computed in local floats, and system `sinf` rounding can move a polygon coordinate by one binary32 ULP between
platforms; see [floating-point policy](floating-point-policy.md).

Reference fixtures: [`tools/reference/README.md`](../../tools/reference/README.md).
