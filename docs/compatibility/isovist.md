# Isovist context/results compatibility

Computational authority: PST v3.3.2, commit
`63df80a2cf3dd289be95ea3d91667c3490719b75`. The complete context/calculation/release
family uses the singular active exported API; the commented plural API is excluded.
The failure evidence (`tools/reference/isovist/`) and the adopted safety policy are recorded below. The context uses native matrix geometry; optional [sf adapters](../spatial-io/sf-adapters.md#isovist-adapters) convert to it.

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

Provenance of the closure conversion: 45 direct combinations of obstacle/
attraction-polygon geometry, origins inside and outside, and full and partial
views gave identical native results for open rings and rings with a repeated
terminal vertex, consistent with `IsovistCalculator.cpp` skipping zero-length
edges. This is scoped evidence, not a general claim. The matrix
`closed_polygon` direct fixture, which intentionally repeats a vertex, stays
matrix-only because an sf ring cannot distinguish a repeated terminal vertex
from its structural closure.

## Ownership and failures

The exact-tagged `rPST::isovist-context/v1` external pointer owns a native context
plus immutable validation metadata. A finalizer frees it once. Native pointers
cannot survive serialization or transfer to another R process.

Each native result holds a reference to its context and returns pooled buffers
there on destruction. It therefore never becomes a public persistent pointer.
The bridge protects an exact-tagged transient result owner whose protected parent
is the context, transfers ownership immediately after publication, validates the
native shape, then copies coordinates, area, all group counts and indices into R
under `R_UnwindProtect`. Cleanup frees the result on success or an R allocation/
error jump. Results remain valid after both native result and context release.
Input temporaries unwind before any R error. Private counters and a copy-error
hook test this architecture; neither is a public analysis API.

`PSTACalculateIsovist` returns void and catches exceptions. The descriptor's point
count/pointer/result handle begin at zero/null/null, and visibility accumulators
begin at zero as in the official wrapper. A nonnull published result handle alone
establishes success. No area, count or partial field is used to infer success.
A null handle raises a controlled R error after C++ temporaries unwind.

The approved safety adaptation checks the **actual calculated state**:

1. Before accessing any final vertex, an empty calculated array fails safely.
2. Only when a partial-view attraction-point queue is nonempty, fewer than two
   calculated vertices fail before the second-vertex read.
3. Only when a partial-view attraction-polygon edge queue is nonempty, fewer
   than three calculated vertices fail before its unsafe indexed accesses.
4. Only when a full-circle attraction-polygon edge queue is nonempty, fewer
   than two calculated vertices fail before its loop iterator advances.

Borrowed local storage returns before throwing; already acquired results unwind
through native RAII. No result handle is published, and no polygon, zero area,
visibility, NA or substitute computation is fabricated. The guards do not use
radius/view/resolution heuristics. Every unaffected expression and algorithm
remains pinned PST. Vendor bytes remain pristine.

## Source provenance and direct oracles

The reference manifest verifies 132 exact pinned blobs against the independent
pinned GitHub tree: complete compiled core, official ctypes wrapper, upstream
isovist test and QGIS batch/tool/geometry/UI callers. Original reproductions remain
in `tools/reference/isovist/baseline-results.json` (58 cases). The expanded
`tools/reference/isovist/native-cases.py` suite has 85 cases; each context is reused for two calculations
with fresh native descriptors, freeing each result before the context. It calls native exports
through official ctypes declarations, never an rPSTool analysis binding.

All 77 unaffected controls, including all previous 74, agree **exactly** between
pristine qualified PST, an assertion-enabled source module and the approved
adapted installed package DLL. Comparison covers vertex order/coordinates, area,
visibility counts/indices, empty contexts/groups, obstacles, attraction points/
polygons, tree reordering, different origins, large world translations, winding,
explicit ring closure, views/resolutions/radii and nearby controls. The eight unsafe
probes produce null-handle failure instead of process termination or invalid
access. The unchanged upstream perimeter test passes in every oracle run.

Expected production values are static direct-pristine fixtures. The generator
uses hexadecimal R numeric literals to preserve complete native double bits;
ordinary default decimal `dput` precision is insufficient for exact comparisons.
Tests run without Python, QGIS, network or a separately installed PST DLL.
The guard's exact patterns, input/output checksums, reversibility, safe paths,
mutation rejection and deterministic regeneration have separate offline gates.

## Cardinality controls and regression guarantees

Partial-view point processing requires two calculated vertices only when its
native point queue is nonempty. Singleton results with empty queues remain valid.
Full-circle polygon processing requires two vertices only when its edge queue is
nonempty; partial-view polygon processing requires three. Origin-containing
polygon controls and safe singleton/full-circle results remain supported.
The reproductions of both additional cardinality cases are in `tools/reference/isovist/cardinality-results.json`. Regression tests exercise context reuse after failure,
no published result on failure, copy-error cleanup, aliases, GC, explicit release
and independent result lifetimes. The final direct suite contains 85 cases:
77 exact successful controls and eight controlled failures.
