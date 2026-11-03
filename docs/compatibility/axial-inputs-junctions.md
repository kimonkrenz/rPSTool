# Axial inputs and graph/junction outputs

This page covers the axial graph (`HPSTAGraph`): indexed line coordinates, unlinks, retained graph points, polygon-generated point
groups, line lengths and crossing coordinates, and the optional Network Integration junction output. Graphs are built by PST v3.3.2
(commit `63df80a2cf3dd289be95ea3d91667c3490719b75`). The matrix interface does no geometry preprocessing. Optional sf graph input and
crossing POINT output are described in the [adapter contract](../spatial-io/sf-adapters.md).

## Construction

`axial_graph(x, line_indices = NULL, unlinks = NULL, points = NULL, points_per_polygon = NULL, polygon_point_interval = NULL)`. Without
indices, `x` has four columns (line endpoints). With indices, `x` has two coordinate columns and `line_indices` has two columns of whole
one-based coordinate IDs; index rows define the line IDs, and endpoint direction, duplicates and ordering are kept. Only referenced
coordinates become lines, but all supplied coordinates determine PST's double-precision world origin (the bounding box is centred in
doubles, then stored as local floats).

PST's crossing construction keeps a 0.01 crossing-length threshold on float squared lengths; short and degenerate lines are not
filtered or rescaled.

**Unlinks.** Each unlink row removes the nearest remaining eligible pairwise crossing, at any distance (no tolerance). A crossing is
eligible when the first line of the pair has an interior intersection, so endpoint-only joins remain and the order of the two lines in a T
junction can change eligibility; line order in the input therefore matters (see [axial file input](../spatial-io/axial-file-input.md)
for file order). Repeated unlinks can remove different pairs. At coincident crossings one unlink removes one pair, not every connection
at that coordinate.

**Graph points** (`points`) keep source order and are assigned to their nearest line (line ID, position along the line, off-network
distance); ties and endpoints follow PST. They differ from the origin points of Reach, which do not change the graph.

**Polygon point groups.** `points_per_polygon` partitions the rows of `points` into ordered regions. Counts are non-negative whole numbers
summing to the number of rows, separator rows included; zero-size regions give empty groups. A row of `NaN/NaN` separates rings within a
region (NA or a one-sided NaN is rejected). rPSTool passes the rings on without inferring holes, orientation or validity. PST closes each
ring, starts at its first corner, carries `polygon_point_interval` across edges and adjusts the closing gap to between 0.5 and 1.5 of the
interval; the generated samples, not the corners, are assigned to lines. Do not repeat the closing corner (repeated corners are passed
on unchanged). `polygon_point_interval` must be positive and finite (zero would make PST loop forever); a perimeter/interval ratio that
would overflow the sample count is rejected. Degenerate rings (one or two corners) and empty groups give PST's own structural results.

`rpst_graph_info` reports the actual number of point groups, which PST's own `PSTAGetGraphInfo` always reports as zero.

**Inspection.** `axial_line_lengths()` returns the native float line lengths as doubles in input order. `axial_crossing_coords()` returns an
x/y matrix of world coordinates in native crossing order (a typed 0 x 2 matrix when there are no crossings).

## Junction output

`network_integration(..., junctions = FALSE)` returns the line data frame. With `TRUE` it returns `list(lines = ..., junctions = ...)`;
junction rows have one-based integer IDs, world x/y doubles and PST's Integration score; no crossings give a zero-row data frame.

`junction_output = "sf"` (requires `junctions = TRUE` and sf) replaces only the `junctions` component with POINT sf (`junction_id`,
`integration`, geometry from the native x/y), in the graph's CRS (unknown if none); `lines` stays a data frame. See the
[sf contract](../spatial-io/sf-adapters.md#betweenness-attraction-points-and-integration-junction-output).

**Junction scores are accumulated.** Network Integration visits line-crossing records and adds each line's score divided by the number
of crossing records at that junction. The result is not a mean over distinct incident lines: two lines scoring -1 give -2 at their
junction. NaN, Inf and coincident or unlinked multiplicities are returned unchanged.

## Input checks

Matrices must be numeric with valid column counts, whole in-range indices, finite values and positive float intervals. Coordinates,
retained points and unlink distances must keep local coordinates and squared distances within float range; a graph handle of the wrong
type (segment, point group) is an error. Results are copied into independent R storage and remain valid after the graph is released.
