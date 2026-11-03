# Explicit network construction

`create_junctions()` and `create_segment_map()` call PST v3.3.2 (commit `63df80a2cf3dd289be95ea3d91667c3490719b75`) once and return
its results; no R calculation reconstructs cuts, merges, snaps or trims.

## Public contracts

`create_junctions(x, line_indices = NULL, y = NULL, line_indices_y = NULL, unlinks = NULL, output = "native")` returns a double `x, y`
matrix. Each layer is given as packed endpoint rows, or as coordinate rows plus one-based index pairs. With two layers the unique
inter-layer intersections are returned; with one layer, repeated pairwise points are retained using PST's 0.02 interior-tail rule, so a
shared endpoint of two lines need not qualify. Unlinks remove the nearest intersection point as in PST. An explicitly empty second layer
keeps two-layer mode.

`create_segment_map(coords, sections = NULL, network_type, snap, tail, deviation, extrude, unlinks, output = "native")` returns
`segments` (double endpoint rows), `source_id` (one-based IDs of the input objects, repeated or skipped as PST produces them) and `unlinks`
(double coordinate rows). Segment order, direction and duplicate unlinks are PST's.

`sections` are signed counts: a negative `-(n + 1)` continues the same source object, a non-negative `n` advances its ID. Empty and
one-point sections are valid alongside real edges, and a final negative section is accepted. Both network types are available: axial/segment
mode splits at cuts and supports unlinks with PST's strict 100-unit radius; centre-line mode emits cuts as unlinks and clears them before
splitting. `snap`, `tail`, `deviation` and `extrude` are all explicit; `extrude` defaults to 0, whereas the QGIS plugin always uses
`extrude = snap` (see [QGIS differences](qgis-differences.md)). No graph is built implicitly; pass the endpoint rows to the graph
constructor.

## Rejected inputs

- An empty first junction layer is rejected, because PST does not write its output fields. Non-empty inputs that give zero rows return
  typed double matrices.
- A segment map whose detail reduction (`deviation`) would merge a segment onto its own start is rejected with an error (this occurs only
  for closed loops and typically needs a large `deviation`). Unmodified PST would either fail with a memory error or complete with a
  zero-length self-loop segment, which angular analyses would count as an extra node; rPSTool does not publish such segments. The
  guard can therefore reject an input that unmodified PST completes, but it never changes a result: accepted inputs give PST's own
  output. See [patch provenance](../../inst/upstream/PATCHES.md#0008--network-construction-safety).
- Intersection loops and junction, cut and point counts that would overflow PST's signed indices are rejected.
- Coordinates must be finite, indices one-based, sections consistent with the coordinate rows, and local float and squared values
  representable. Thresholds are finite non-negative floats whose squares are representable. At least one edge is required for a segment
  map. Unlinks are accepted only in axial mode.

Results are copied to independent R storage; no native handle escapes. No Python, QGIS or sf is needed for the matrix API. Reference
fixtures: [`tools/reference/README.md`](../../tools/reference/README.md).

## Optional sf representation

The [construction contract](../spatial-io/sf-adapters.md#explicit-construction-adapters) defines sf/sfc inputs and `output = "sf"`.
Junction inputs reuse the shared LINESTRING/POINT converters. For a segment map, a LINESTRING supplies every vertex; a MULTILINESTRING
supplies ordered parts (negative earlier counts, non-negative final count) with no edge between parts. Empty and singleton features or
parts still advance the source ID; at least one edge is required. With sf coordinates, `sections` must be NULL.

Junction sf output is POINT geometry with a one-based `junction_id`. Segment-map sf output is a three-component list: LINESTRING sf
`segments` with `source_id`, the `source_id` vector, and geometry-only POINT sf `unlinks`. The CRS is that of the supplied sf input;
matrix input gives unknown CRS.
