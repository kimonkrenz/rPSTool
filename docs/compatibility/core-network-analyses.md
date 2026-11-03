# Core network analyses and parameters (PST v3.3.2)

Computed by PST v3.3.2 (commit `63df80a2cf3dd289be95ea3d91667c3490719b75`); rPSTool adds argument validation, result naming and the
missing-output policy described below.

| R routine / exported call | Required native graph | Radius fields consumed | Distance | Output in input row order | Execution |
| --- | --- | --- | --- | --- | --- |
| `network_integration` / `PSTANetworkIntegration` | `HPSTAGraph` | rPSTool accepts only `steps` (see [QGIS differences](qgis-differences.md)) | fixed topological steps | integration, node count, total step depth | synchronous |
| `network_reach` / `PSTAReach` | `HPSTAGraph` | all five | none | reached count, full reached-line length, area | synchronous |
| `network_betweenness` / `PSTASegmentBetweenness` | `HPSTAGraph` | all five | walking, steps (default), angular, axmeter | raw betweenness, node count, total depth; optional normalized score | worker threads |
| `angular_integration` / `PSTAAngularIntegration` | `HPSTASegmentGraph` | straight, walking, steps, angular | fixed angular | selected integration, node count, total angular depth; optional weight diagnostics | worker threads |
| `angular_choice` / `PSTAAngularChoice` | `HPSTASegmentGraph` | straight, walking, steps, angular | fixed angular | raw choice, node count, total angular depth, depth weighted by length; optional normalized score | worker threads |

Each routine requires the graph type of its descriptor (axial or segment); the wrong type is an error. Angular analyses share a
maximum of 32 endpoint incidences per coordinate (`AngularChoiceAlgo` uses a 32-bit outgoing-path mask).

## Shared radius contract

`analysis_radius(straight=NULL, walking=NULL, steps=NULL, angular=NULL, axmeter=NULL)` represents the five independent fields of PST's
`SPSTARadii`. NULL means absent (unlimited); zero is a real limit. Several limits may be combined and PST applies them together. There is
no unit conversion or rescaling: straight and walking use coordinate length units, angular uses degrees. Axmeter is PST's accumulated
length with topological weighting, not another spelling of walking.

All specified fields must be finite non-negative numeric scalars. Steps are whole numbers at most 2147483647 (a signed `int` in
PST). Other fields are narrowed to native float; values that overflow or underflow to zero are rejected, and the straight radius must also
have a finite float square. Fields an analysis does not support are errors, in particular `axmeter` in the angular analyses, where PST
would silently ignore it. The additive `radius=` argument of the two integration routines conflicts with a non-NULL `steps` argument.

## Distance, settings and normalization

`network_betweenness` accepts the distances `"walking"`, `"steps"`, `"angular"` and `"axmeter"` (exact names). Straight and weights exist
in PST's enum but are rejected by its implementation. Angular total depth is expressed in syntax angle units (90 degrees = 1); other total
depths follow the chosen distance. All node counts include the origin.

Reach length counts whole lines, not clipped portions. Straight-only Reach tests the line midpoint and reports pi times the squared
radius as area; other Reach modes report the convex hull area of the reached endpoints.

Angular Choice accepts `weigh_by_length` (default `FALSE`), `angle_threshold` (default 0) and `angle_precision` (default 1 degree). Weighted choice
includes origin and destination contributions; it is not the unweighted score multiplied afterwards. The length-weighted depth is
returned only in weighted mode. See [angular controls](angular-controls.md).

`normalization` is `"none"` (default), `"standard"`, `"turner"` (choice) or `"freeman"` (betweenness), or `"syntax"`; the result gets an additional
`normalized` column and raw scores are always kept. Syntax normalization uses `total_depth`, and `total_depth_weight` for length-weighted
Angular Choice (see [QGIS differences](qgis-differences.md)). Network Integration computes its score internally and has no separate
normalizer.

Network Integration returns `-1` for fewer than two reached lines, NaN for the two-line formula and positive infinity for zero relative
asymmetry. Depth sums topological transitions, including collinear endpoint joins.

## Threading

Network Integration and Reach run on the calling thread. Network Betweenness and the angular analyses use worker threads whose number
is the hardware concurrency, capped by `RPST_NUM_THREADS` when set (a positive integer, never above hardware concurrency; an invalid
value is an error). When R CMD check limits cores (`_R_CHECK_LIMIT_CORES_` set and not `false`), at most two workers are used. On
Windows, assigning an empty string removes the variable and selects the default; on POSIX an empty value is invalid. Results do not
depend on the number of workers. Console progress is shown only when active (see [progress display](../progress.md)).

## Exclusions

Fast Segment Betweenness is experimental in PST v3.3.2 and not exposed; `angular_choice()` provides angular centrality.

## Point origins and weighted/attraction modes

Optional sf/sfc XY POINT Reach origins and Betweenness attraction points are converted to the x/y matrix form; feature order is kept. See
the [adapter contract](../spatial-io/sf-adapters.md) for graph-versus-analysis CRS checks.

### Public API and missing-output policy

`network_reach(graph, radius = analysis_radius(), origins = NULL)` accepts optional finite x/y matrix origins with at least one row. With
`origins = NULL` the origins are the lines and the result has `line_id`; supplied points produce `origin_id` in input row order.

`network_betweenness(graph, radius = analysis_radius(), distance = "steps", normalization = "none", weights = NULL,
attraction_points = NULL)`: `weights` has one finite value per line, or one per attraction point when attraction points are supplied. Zero
and negative weights are accepted; values that overflow float or underflow to zero are rejected. Attraction coordinates use the same x/y
matrix convention as Reach; sf/sfc XY POINT input is accepted in feature order, weights stay explicit and attributes are ignored
([sf contract](../spatial-io/sf-adapters.md#betweenness-attraction-points-and-integration-junction-output)).

Where PST does not write a diagnostic (for example for origins it skips), the corresponding `node_count` and `total_depth` entries are
integer/double `NA`, and `normalized` is `NA` for undefined rows. Written values, including non-finite ones, are returned as PST
produced them; raw scores are never altered. In files (`output_file`) these `NA` values are Arrow nulls in `node_count`, `total_depth` and
(Freeman/syntax) `normalized`; `betweenness` and the standard normalization are never null. See [result files](../spatial-io/result-files.md).

### Other semantics

- Reach accepts double x/y origin pairs; the result keeps point order.
- Straight-only point Reach tests the squared midpoint distance with strict `<`; line Reach uses `<=`. Both return `straightSqr * 3.1415927f`
  as area, even when no line is reached. A point at zero straight radius reaches no midpoint, unlike a line origin.
- Other point Reach modes assign the origin to the closest line. Initial walking and axmeter distances include the offset from the
  network, and walking inclusion adds the distance along the line to its midpoint. Walking, steps, angular and axmeter limits are
  inclusive. Combined straight limits constrain crossings instead of using the straight-only midpoint rule. The convex hull area includes the
  origin point.
- Without attraction points, weights apply per line. With them, PST converts each world point to float local coordinates, assigns it to
  the closest line and sums the weight (or 1) on that line in input order. Ties between equally close lines follow PST's internal
  search order, and float accumulation need not be invariant under permutation of the points.
- Weighted betweenness includes endpoint and self contributions, so unit weights do not generally reproduce unweighted betweenness.
  Origins with non-positive weight are skipped; negative destination weights enter the accumulation with their sign. Attraction values
  that are null become zero.
- World coordinates are converted by subtracting the graph's double-precision origin and narrowing to float; coordinates whose local
  value or square overflows are rejected.
