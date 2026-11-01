# Axial inputs and graph/junction outputs

This contract covers the existing `HPSTAGraph` family as a whole: indexed line
coordinates, unlinks, retained graph points, polygon-generated point groups,
native lengths/crossing inspection, and optional Network Integration junction
outputs. The runtime remains R → registered `.Call` → pinned PST v3.3.2 at
`63df80a2cf3dd289be95ea3d91667c3490719b75`. The matrix interface performs no implicit geometry preprocessing. Attraction and
OD analyses reuse retained native points. Optional sf graph input and explicit
crossing POINT output now feed this same contract; see the [adapter contract](../spatial-io/sf-adapters.md)
for conversion rules, CRS policy and the geometry inventory.

## Pinned authority and public contracts

The exact `CreateGraph.h` descriptor/exports, `CreateGraph.cpp`, `AxialGraph.h`
and `AxialGraph.cpp` establish construction, copying, assignment and inspection.
`RegionPoints.{h,cpp}`, `Rect.h` and `Vec2.h` establish polygon sampling and
world/local coordinate conversion. `NetworkIntegration.{h,cpp}`, `BFS.{h,cpp}`
and Common radii establish line and junction computation. The official ctypes
wrappers, unchanged `testcreategraph.py` / `testnetworkintegration.py`, QGIS
`analyses/utils.py`, `networkintegrationanalysis.py` and `model/model.py` were
also inspected. The direct generator verifies 133 independently pinned Git blobs,
including the entire 121-file pristine core and the relevant wrappers/tests/
callers, before loading native code or compiling the structural accessor.

`axial_graph(x, line_indices=NULL, unlinks=NULL, points=NULL,
points_per_polygon=NULL, polygon_point_interval=NULL)` preserves the original
four-column endpoint-row call. With indices, `x` has two coordinate columns and
indices have two columns with whole one-based coordinate IDs. Index rows define
line IDs; endpoint direction, duplicates, unreferenced coordinates and ordering
are retained. All supplied line coordinates determine PST's double world origin,
including unused indexed coordinates. Only referenced coordinates become lines.
Unused coordinates are not artificially required to have float-distance extents:
fixtures include symmetric unused ±1e100 coordinates with a valid small network.

Axial construction centres the bounding box in doubles, then stores local floats. Native crossing construction and float squared lengths retain PST's 0.01 crossing-length threshold; short and degenerate input lines are not filtered or rescaled.

Unlink rows map to PST's native float local coordinates. Each removes the nearest
remaining **eligible pairwise crossing**, with no distance tolerance. Eligibility
checks the first line of the pair for an interior intersection. Endpoint-only
joins remain; reversing which line comes first in a T junction can change
eligibility. Repeated unlinks can remove different pairs. At coincident crossings,
a single unlink removes one pair, not every connection at that coordinate. These
are source-confirmed behaviours, not repaired or reinterpreted by rPSTool.

Regular graph points retain source order, world/local rounding, nearest-line ID,
line position and off-network distance in PST's graph. Assignment tie-breaking
and endpoint behaviour remain native. Inputs are copied synchronously; the R
owner retains no coordinate/index/point vectors or wrapper-side assignments.
Graph points differ from the independently supplied origin points of
Reach; the latter do not mutate retained graph state.

Polygon counts partition the supplied point matrix into ordered regions. Counts
are non-negative whole numbers and must sum to its rows, including separator
rows. Native zero-sized regions retain empty groups. `NaN/NaN` rows separate
rings within a region; R NA or one-sided NaN is rejected. This is the exact
RegionPoints separator mechanism; QGIS itself only supplies outer rings. rPSTool
passes ordered rings without inferring holes, orientation or geometry validity.
Native generation closes each ring, starts at its first corner, carries spacing
across successive edges and adjusts the closing gap to the commented
0.5–1.5 interval range. Native generated samples, not corners, are assigned to
lines. Do not repeat a closing corner; supplied repeated corners are passed
unchanged, as the regression fixture confirms. Degenerate one-/two-corner rings,
separator-only regions and empty groups retain actual PST structural results.

`PSTAGetGraphInfo` hardcodes `m_PointGroupCount=0`, even after successful polygon
construction. `rpst_graph_info` reads the actual count with the exact pinned
`CAxialGraph::getPointGroupCount()` inline getter instead. No group count is
inferred from editable R metadata. This exposes retained native storage, without
changing the export or vendor bytes. Other info fields continue to come from the
exported API.

`axial_line_lengths()` calls `PSTAGetGraphLineLengths`, queries its native
count, and copies floats to a double vector in input line order.
`axial_crossing_coords()` calls `PSTAGetGraphCrossingCoords`, queries its
count, and copies world doubles to an x/y matrix in native crossing order.
No crossings yields a typed double 0×2 matrix. Output storage is independent
from graph storage.

`network_integration(..., junctions=FALSE)` preserves its existing line data frame.
With TRUE, it returns `list(lines=..., junctions=...)`; junction rows contain
one-based integer IDs, world x/y doubles and native Integration scores. The
radius and line results remain unchanged. Zero crossings gives a typed zero-row
junction data frame. The bridge supplies the authoritative native crossing count,
so the export's malformed-count error path is never used as an allocation check.

`junction_output = "sf"` (appended; requires `junctions=TRUE` and sf) replaces only
the `junctions` component with POINT sf: `junction_id`, `integration` and geometry
made solely from the native x/y. Order, scores (including NaN/Inf and
multiplicity-dependent values) and the zero-junction case are preserved, the
CRS is the graph's retained sf CRS (unknown otherwise), and `lines` stays an
ordinary data frame. No extra native call or line geometry is involved; see the
[sf contract](../spatial-io/sf-adapters.md#betweenness-attraction-points-and-integration-junction-output).

Junction scores are **accumulated**, not overwritten, by the export. Each call
supplies a freshly zero-initialised float buffer. rPSTool copies scores without
calculating them. The source's `CROSSING::nLines` is initially the pairwise
crossing-record count; `updateLinesPerCrossingCount()` is defined but never called
by this core. Network Integration iterates line-crossing records and divides each
line contribution by that native multiplicity. Consequently this is not a
conventional mean over distinct incident lines: two lines scoring -1 yield -2
at their junction. NaN/Inf and coincident/unlinked multiplicities remain intact.
There is no unwritten-output policy extension or numerical correction here.

File-backed construction (`axial_graph(<path>)`) feeds this same contract through an extracted shared builder;
see [axial file input](../spatial-io/axial-file-input.md), including the consequences of physical file order for unlinks.

## Validation and lifetime boundaries

Exact axial tags and live addresses precede native access; segment and group
handles are rejected. Legacy one-argument constructor and two-argument
Integration private registrations are preserved. New public choices are appended
to existing signatures. All counts and output lengths use native state.

Numeric matrices, column counts, index ranges/whole values, polygon partitions,
finite values and positive float intervals are checked before native acquisition.
ALTREP storage is materialised once before C++ buffers. Bounds protect PST's
signed point counts, unsigned descriptors, double centring, native local floats
and squared float distances, including float bounding-box midpoint additions
used by SphereTree and nearest-line queries. All retained points share the constructor's bounding
box, so their combined extent is validated. Each unlink's distance extent is
checked against network lines. A conservative closed-ring perimeter/interval
bound plus vertices/groups prevents signed generated-count overflow and avoids
non-progressing interval-addition loops. This is validation only: PST generates
all actual samples and group sizes.

The empty tagged owner and finalizer are registered before any native acquisition.
R output storage is allocated/protected before owning native temporary buffers.
No R allocation or error occurs inside those buffer scopes; caught exceptions become
R errors only after C++ destruction. The previously verified constructor RAII
build adaptation already protects the polygon-failure path; no further
build transformation is needed. Finalisation clears the pointer before matching free.
Aliases retain the same owner; explicit repeated release is safe; deserialised
owners are rejected. Result copies survive graph disposal. No worker callbacks
or new worker engines are introduced; Network Integration remains synchronous.

A private registered `rpst_graph_point_state` getter copies retained point
coordinates, one-based native line assignments (zero means native -1), off-line
distance, line position and group sizes solely for structural/lifetime tests.
It is not a public inspection API or duplicated storage in graph wrappers.

## Direct PST and production regressions

`tools/reference/axial/generate-reference.py` invokes the pinned official ctypes
wrappers and exported C API, never rPSTool `.Call`. The tiny development-only
`tools/reference/axial/axial-point-state.cpp` accessor compiles against independently verified pristine
headers and reads retained native structures for handles returned by the C API.
It supplies no algorithm or replacement graph. The Linux generator uses the
native C++ compiler with the checked engine’s C++ ABI and a temporary shared
accessor inside rPSTool scratch storage;
installed fixtures/tests require neither Python nor that compiler invocation.

Four unchanged upstream tests pass. Fixtures cover 28 graphs and eight radius
settings each (224 Integration settings), including all five radius families and
combined limits. Each setting is repeated with distinct line-score/count/depth/
coordinate seeds while its junction buffer is zeroed, and independently checked
against PST's junction-only descriptor path. Cases cover expanded/indexed inputs,
unused coordinates, source row/endpoint ordering, translation, isolated and
zero-crossing graphs, endpoint and order-dependent T unlinks, distant/repeated
unlinks, coincident crossings, points including ties and duplicates, empty optional
matrices, multiple polygon intervals, ring separators, empty groups, repeated
corners and degenerate rings.

`tests/testthat/test-axial-inputs.R` compares lengths, crossings, retained point
state, native group sizes/counts, line diagnostics and junction coordinates/scores
against these fixtures. Non-finite output classes/values are checked exactly;
finite float-dependent arithmetic allows 1e-7 relative tolerance across compilers.
Repeated radius switching verifies fresh junction buffers. Malformed inputs,
float/distance/point-count overflow, ALTREP, forged metadata, wrong graph tags,
dead/deserialised owners, input mutation/collection, output lifetime, repeated
explicit/GC release and an R error after acquisition exercise safety boundaries.
