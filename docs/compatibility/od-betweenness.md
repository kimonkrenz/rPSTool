# OD Betweenness

Computed by PST v3.3.2 (commit `63df80a2cf3dd289be95ea3d91667c3490719b75`). Optional sf/sfc XY POINT origins are converted to the x/y matrix
form in feature order; origin weights are per feature and destination weights per retained native point, including polygon samples.
See the [adapter contract](../spatial-io/sf-adapters.md) for graph-versus-analysis CRS checks.

## Public API

`od_betweenness(graph, origins, radius = analysis_radius(), distance = "walking",
destination_mode = "all", origin_weights = NULL, destination_weights = NULL)`
calls exported `PSTAODBetweenness`, descriptor `SPSTAODBetweenness` version 1.
It requires an axial graph; segment and group graphs are rejected. Supplied x/y origin rows remain ordered. Destinations
are retained native graph points: polygon-generated samples each require their
own weight, not one weight per polygon/group.

The result is independent R storage: one-based `line_id` and native float
`od_betweenness` widened to double, in native input-line order. Results survive release of the graph and inputs.
Empty origin/destination sets return native written zeros. Every score is written, so there are no NA results.

| Choice | PST behaviour |
| --- | --- |
| Primary cost | Walking or angular only; other costs are not supported. |
| All destinations | Native flow uses positive reached destination weights and their sum. |
| Closest | Stops at the first destination reached by the native priority queue; ties follow that queue, with no equal-path redistribution guarantee. |
| Origin weights | NULL means unit; finite native-float signed values are passed unchanged. Nonpositive traces contribute no positive score under the native filter. |
| Destination weights | NULL means unit; nonpositive values are excluded by PST before queueing. |
| Limits | Straight, walking, steps and angular checks remain independent of primary cost. Axmeter is ignored by PST and rejected by rPSTool (below). |
| Walking depth | Walking primary includes off-network origin/destination legs. Angular primary omits the final destination leg from walking-depth checks. |
| Extreme values | Valid finite weights may overflow intermediate native float operations, producing Inf or filtered zero scores. Written values are returned unchanged. |
| Normalization | Raw scores only. |
| Workers | OD betweenness always runs with one worker thread, whatever `RPST_NUM_THREADS` says. |

Inputs must be numeric with finite coordinates, native-float weights (no overflow or non-zero underflow) and counts matching the graph's
native points; modes and radii are validated again natively. Errors are raised after native buffers are released. Build adaptations
of PST's OD code (initialising an ignored flag, exception propagation, trace-index guard, worker cap) change no result; see
[patch provenance](../../inst/upstream/PATCHES.md). Reference fixtures: [`tools/reference/README.md`](../../tools/reference/README.md).

## Radius types

`od_betweenness()` raises an error for any `analysis_radius(axmeter = )`, on the in-memory, `output_file` and `spatial_output_file` paths
alike. PST never reads the axmeter limit, so the result would be identical to the same call without it. Straight, walking, steps and angular
limits apply. `analysis_radius()` itself still accepts axmeter, and other analyses that honour it are unaffected.
