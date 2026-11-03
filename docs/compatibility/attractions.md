# Attraction Reach and Attraction Distance — PST v3.3.2 compatibility

Optional sf/sfc XY POINT/POLYGON attractions now feed the unchanged native
matrix/count path. Polygon closure removal and NaN ring separators reuse graph
point-group conversion; explicit values and all Distance exclusions remain.
See the [adapter contract](../spatial-io/sf-adapters.md) for graph-versus-analysis CRS checks.
No numerical fixtures or native algorithms changed.

Authority: `63df80a2cf3dd289be95ea3d91667c3490719b75`.
Exports: `PSTAAttractionReach` (descriptor v1), `PSTAAttractionDistance` (v4).
Public R: `attraction_reach()` and `attraction_distance()`, implemented
as one coherent family with shared native graph/origin/attraction validation.

## Resolved limitation and retained supported surface

The 50-case reproduction of the unwritten group outputs
(`tools/reference/attractions/check-unwritten-group-distance.py`, results in
`unwritten-group-distance-results.json`) is the evidence for the adopted policy, which rejects only straight-only
Attraction Distance with point-group origins. The public wrapper and registered
native boundary both raise an R error **before PSTAAttractionDistance** for this
combination, with no radius or only straight radius, with or without indices.
No NA/missing-output policy, recomputation or group aggregation is added.
PST remains the computational authority for all written modes.

| Control | Reach | Distance |
| --- | --- | --- |
| Graph | Exact live `HPSTAGraph` axial owner; no segment/group-owner casts | Same |
| Origins | Lines, junctions, retained graph points, retained point groups | Same; documented straight-only group rejection only |
| Primary distance | Straight, walking, steps, angular, axmeter, none (`Undefined` / native zero cost) | Straight-only fast path, walking, steps, angular, weights |
| Independent radius | Shared five native limits | Network path supports walking/steps/angular, with straight accepted but natively ignored; axmeter unsupported by builder. Straight primary with another radius is natively unsupported, rejected explicitly. |
| Attractions | Double world points or automatically closed region edges; ring separators NaN/NaN | Same input; sampling occurs in local floats rather than Reach's world doubles |
| Values / weights | Optional native floats per point/polygon; omitted = native units; nonpositive values skipped | Custom distance requires one finite non-negative native float per line; zero weights valid; point-edge cost per coordinate unit is explicit |
| Decay | Constant, power, curve, divide; finite native float constant (default `NULL`: 0 for constant decay, 1 for power, curve and divide, the original PST for QGIS wizard default `C = 1`; an explicit constant, including 0, is passed unchanged); no invented positivity/radius requirement | Native minima only |
| Polygons / groups | Copy/divide distribution; mean/sum/min/max collection | Native minimum aggregation in supported network group modes; never rPSTool aggregation |
| Outputs | Origin-row ID and native score widened to double | Origin-row ID, widened native distance, optional **raw native** integer destination index |

Origins follow native graph order and count, obtained from exact tagged storage;
mutable R metadata is never authoritative. Origin IDs are one-based R row IDs.
Destination indices retain native zero-based values and native unreachable `-1`,
without substituting NA or pretending every mode indexes the same objects.
Distance scores retain native unreachable `-1`. All written finite, negative,
zero, NaN and Inf scores are widened without numerical reinterpretation.

## Source-confirmed quirks preserved and exercised

- Reach's group collector tracks the group offset but reads each worker's point
  prefix. Nonuniform groups/attractions exercise this upstream behaviour;
  native zero-size groups return -1. No correction is made.
- Finite straight line Reach queries nearest line distance but applies decay
  at the **radius**. Unrestricted straight line Reach uses actual line distance;
  straight Distance uses line midpoints. Point/junction straight Reach uses
  native point locations. Controls cover both fast and BFS branches.
- Reach's steps-mask comparison matches the axmeter enum, adding one to its
  decay scale. BFS limits/distances remain native, including independent limits.
- Power/curve can write NaN (e.g. zero primary radius); divide can write Inf.
  These are retained exactly and class masks are checked against direct PST.
- Distance network traversal passes an infinite straight constraint despite
  resolving the supplied straight radius. The fixture with straight radius zero
  demonstrates native omission rather than a wrapper filtering rule.
- Finite straight Distance updates the destination index for each eligible
  attraction even when it is not the minimum. Returned indices are native.
- Straight polygon Distance returns generated sample indices; network non-group
  Distance maps samples to polygon indices. Network group Distance performs its
  public-index mapping before copying private point minima, then returns sample
  indices. Public index buffers start at -1 to avoid the premature unchecked
  lookup. Every supported group path writes its final native outputs; seeds and
  distance-only paths are compared directly. No remapping is added in rPSTool.

These claims are grounded in both headers/implementations, Common/Limits/BFS,
DirectedMultiDistanceGraph/ShortestPathTraversal/StraightLineMinDistance,
RegionPoints, official wrappers/tests and QGIS callers. Enum presence alone is
not a supported-mode promise.

## Native safety and ownership

Registered bridges enforce exact pointer tags/liveness before any graph access.
Inputs require numeric storage, matching rows/counts, finite representable floats
and coordinate/distance extents. Polygon separators must be NaN/NaN, never NA;
counts may be zero but sum to the corner rows; empty attraction matrices
produce native zero Reach / unreachable Distance outputs; spacing is positive. Conservative
perimeter/count bounds prevent signed index overflow. Distance's float sampling
also checks that spacing advances at each native edge length, preventing a
non-progressing float addition loop. These are representation/safety bounds,
not a replacement sampling algorithm. PST generates all samples itself.
Negative custom distances are rejected for its non-negative shortest-path engine.

R outputs are allocated/protected and ALTREP storage materialized before owning
C++ temporaries. C++ exceptions are captured and all native buffers unwind before
R errors. Graph input is reused, not reconstructed or copied into R wrappers;
outputs own independent storage. Calls are synchronous; the progress callback is installed only while
console progress is active ([progress display](../progress.md)) and is otherwise null;
workers never call R. Release/GC/serialization/wrong-family regressions apply to
both analyses. Invalid worker caps fail safely, and graphs remain reusable.

[Build adaptation 0005](../../inst/upstream/PATCHES.md) documents exact reversible
worker caps, protection of Reach's explicitly non-thread-safe query scratch and
future exception propagation. Only generated copies change. The scratch lock
covers retrieval through consumption under the existing algorithm mutex; PST's
scoring/traversal operations remain unchanged. `future.get()` exposes worker
failures after waiting; remaining futures join before owners are destroyed.

## Oracles and validation

`tools/reference/attractions/generate-reference.py` verifies 139 exact Git blobs before
DLL loading and runs all nine unchanged upstream tests. It calls official ctypes
wrappers / exported C API directly, never rPSTool `.Call` or replacement computation.
The checked-in fixture has 537 supported cases: all origin/distance modes, all
Reach decays/collections/distributions, mixed and finite radii, values/weights,
polygon/ring inputs, zero native origins, empty groups, index/no-index paths,
finite/unreachable/NaN/Inf outputs. Distance seed checks verify writes independently
of initial distance contents, with safely negative index seeds in group polygons.
Generator cap one gives repeatable native float accumulation; package tests compare
both caps one/two with exact class/index masks and finite float tolerance.

Production regressions also prove the adopted rejection occurs before attraction
validation/native computation, safe repeated reuse/release/GC/deserialization,
metadata independence, malformed native storage/counts/underflow/overflow, sampling
loop safety and concurrent shared scratch use. Development-only
`tools/reference/attractions/check-worker-safety.py` injects failures into verified generated copies
inside rPSTool scratch; both actual PST worker paths propagate failure rather than
returning partial results. No runtime fault-injection API or Python dependency is
installed. The probe's ELF linking is Linux-only development tooling; production
recipes retain Unix/Windows portability and preserved exact inputs.
