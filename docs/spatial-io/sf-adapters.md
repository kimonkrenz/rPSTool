# sf adapters

`sf` is an optional (`Suggests`) dependency. sf/sfc inputs are converted in R to the matrix and list representations of the
matrix interface and passed to the same PST core; matrix calls work without sf, and an adapter call checks that sf is available.
sf attributes never supply weights, parameters or identifiers: weights and values are always passed explicitly, aligned with
feature order.

No snapping, reprojection, unit conversion, simplification, repair, dissolution, splitting, merging or deduplication occurs in
the adapters. Feature, part, vertex and endpoint order are unchanged. Graphs keep only the native pointer, existing metadata and
a `crs` attribute when sf participated (`attr(graph, "crs")`), not the input geometry; graphs are not sf objects.

Rejected for every input: empty POINT/LINESTRING features, non-finite coordinates, geometry collections, Z/M coordinates,
MULTIPOINT and MULTIPOLYGON. MULTILINESTRING is rejected except in `create_segment_map()`.

## Native graphs and crossing output

- `axial_graph(x, ...)` accepts XY LINESTRING features with **exactly two vertices** each. A longer LINESTRING is rejected, even
  with a collinear third vertex, because the endpoint-row core cannot retain it. With `line_indices`, `x` instead accepts XY
  POINTs in coordinate-row order (including unused coordinates, which affect the native centre); the indices stay explicit
  one-based matrix indices.
- `segment_graph(x)` accepts the same two-vertex XY LINESTRINGs and uses the endpoint-connected builder.
- Axial `unlinks` accepts XY POINTs. `points` accepts XY POINTs or POLYGONs. Each feature is one native point group; the
  number of points per polygon is derived, so `points_per_polygon` must be `NULL` and `polygon_point_interval` must be given
  explicitly. All ring boundaries, including holes, are sampled. An empty POLYGON (no rings) is a zero-count group; an empty
  ring inside a polygon is rejected; an empty polygon collection is rejected.
- `axial_crossing_coords(graph, output = "sf")` returns independent XY POINTs from the native coordinate matrix, with a
  one-based `crossing_id` in native crossing order and the graph CRS. An empty result has zero features. The default
  `output = "native"` returns the matrix.

**Polygon rings.** sf closes polygon rings explicitly. The adapter removes exactly the final coordinate when it equals the first,
keeps every other vertex (including repetitions), ring order and winding, rejects unclosed rings, and inserts one `NaN`/`NaN` row
between rings. This is a representation conversion, not a repair.

## Supplied analysis geometry

- `network_reach(origins = )` and `od_betweenness(origins = )` accept XY POINTs in feature order. Reach needs at least one origin;
  OD permits an empty collection.
- `attraction_reach()` and `attraction_distance()` accept XY POINT or POLYGON attractions, converted as described above.
  Holes are additional sampled boundaries of the same attraction polygon, not separate attractions. Empty features are
  zero-count groups; empty polygon collections are rejected. All mode restrictions of the matrix interface remain. Native
  destination indices may refer to samples or polygons depending on the mode, not to sf features.
- Explicit `attraction_values` align with feature order, including empty groups. `origin_weights` of OD betweenness align with the
  supplied origins, `destination_weights` with the retained native graph samples, and `line_weights` of Attraction Distance
  with the graph lines.

Results are ordinary data frames without geometry.

## Raster comparison adapters

`compare_line_results(x, values1, values2, y = NULL, ...)` accepts XY LINESTRINGs for `x` and `y`: one feature is one
`x1,y1,x2,y2` row with exactly two finite vertices, in feature order and endpoint direction. Longer LINESTRINGs, empty features,
MULTILINESTRING, collections, non-finite coordinates and Z/M are rejected, never reduced to endpoints. `values1` and `values2`
are explicit vectors: with `y = NULL` both address `x`; otherwise `values1` addresses `x` and `values2` addresses `y`. The CRS
policy below applies across `x` and `y`; only the CRS is kept, as `attr(raster, "crs")`.

`raster_data()` is unchanged: it returns an ordinary list (bounding box, dimensions, pitch, format, extrema, pixels), not sf, stars
or terra objects.

`raster_to_polygons(raster, ranges, output = c("native", "sf"))` returns the native result by default. With `"sf"` the result is a
list in range-row order whose elements are `sfc_POLYGON` objects: one POLYGON per native polygon in native order, the first ring
the outer ring and later rings the holes in order. An empty range is a zero-feature `sfc_POLYGON`; zero ranges give an empty list;
the CRS is the raster's (unknown if none). No `range_id`, `polygon_id` or threshold attributes are added.

Ring conversion keeps every native coordinate, its order and winding. The first coordinate is appended only when the ring is not
already closed, repeated vertices are kept, and no area, distinctness or `st_is_valid()` check is applied. If a ring cannot become
an sf ring by that single closure, the whole call fails and names the range, polygon and ring: fewer than three rows (including
empty and one-row `NaN`/`Inf` output and two-vertex rings), non-finite coordinates, or an already-closed ring with fewer than four
rows. Nothing is dropped or repaired; use the native output for such rasters. The raster and its data are unaffected by a failure.

## Betweenness attraction points and Integration junction output

`network_betweenness(attraction_points = )` accepts XY POINTs in feature order. `weights` is the only weight source (one per
supplied point; zero and negative values as in the matrix interface). An empty collection reaches the native
at-least-one-point validation. A known geographic CRS is rejected, and the sf CRS must equal any CRS retained by the graph; matrix
points on a CRS-bearing graph need no sf. Distances, normalisation, signed weights and missing-output handling are native PST
behaviour.

`network_integration(..., junctions = TRUE, junction_output = "sf")` replaces only the `junctions` component with POINT sf:
`junction_id`, the generated junction-integration column (`nj_s_<radius>`) and the geometry built from the native x/y (x/y are not repeated as columns). `junction_output`
follows `junctions` in the signature, defaults to `"native"`, and requires `junctions = TRUE` and sf; otherwise the call fails
before any native work. Native order and score values (including `NaN`/`Inf`) are preserved. A zero-junction result has zero
features. The CRS is the graph's retained CRS (unknown for matrix-only graphs). `lines` stays an ordinary data frame without line
geometry.

## Explicit construction adapters

`create_junctions()` accepts two-vertex XY LINESTRING layers, XY POINT coordinate rows with explicit index matrices, and XY POINT
unlinks. An explicitly empty second layer keeps two-layer mode; an empty first layer fails under the native unwritten-result
policy. `output = "sf"` returns POINT sf with a one-based `junction_id` in native order; the default is the coordinate matrix.

`create_segment_map(coords, sections = NULL, ..., output = "native")` accepts XY LINESTRING and MULTILINESTRING features as
`coords`. Matrix `coords` still need explicit `sections`; for sf `coords`, `sections` must be `NULL`. Each feature is one native
source object, and every vertex becomes one coordinate row. Sections are encoded as follows:

| Feature | Section encoding |
| --- | --- |
| LINESTRING | its point count |
| MULTILINESTRING | parts in order; every part but the last is `-(point_count + 1)`, the last part is its point count; no edge joins separate parts |
| Empty LINESTRING, or multipart without parts | one zero section (the source ID advances) |
| Empty or one-point part | its exact count (earlier empty parts `-1`, earlier singletons `-2`) |

Mixed LINESTRING and MULTILINESTRING sequences are accepted. All coordinates are kept, including repeated vertices, unused
singleton coordinates and closed lines. A trailing negative section of a matrix call has no sf equivalent; the sf form ends the
same source with a non-negative count. At least one real edge is required. Collections, other geometry types, Z/M and malformed
parts are rejected. Construction unlinks accept XY POINTs; the native mode exclusions are unchanged.

With `output = "sf"` the result keeps its three components: `segments` is two-vertex LINESTRING sf with the one-based `source_id`
column, `source_id` is unchanged, and `unlinks` is POINT sf with geometry only. Zero-row results have zero features. The output
CRS comes from the supplied sf inputs (including unlink or second-layer metadata); matrix-only input gives an unknown CRS.
`output` is appended to both functions' signatures.

## Isovist adapters

`isovist_context()` accepts, per group, an sf/sfc layer instead of a matrix or matrix list. Obstacle and attraction polygon
layers are XY POLYGONs with **exactly one ring per feature**: holes, empty polygons, MULTIPOLYGON, Z/M and non-finite
coordinates are rejected. Only the structural closing coordinate is removed; order and winding are untouched. PST expects
Cartesian clockwise rings, and rings are never rewound. Point layers are XY POINTs. An empty layer is an empty group. The CRS is
checked across all nested layers (matrix groups contribute none) and kept as the context `"crs"` attribute when sf took part.
Matrix groups keep any intentional repeated terminal vertex. See also the
[isovist compatibility record](../compatibility/isovist.md#optional-sf-adapters).

`isovist(..., output = "sf")` replaces only `polygon` with a length-one POLYGON sfc built from the native vertices; the first
vertex is appended only when the polygon is not already closed. A result with fewer than three vertices, non-finite coordinates, or
fewer than four ring coordinates after closure fails with an R error (the native default stays available). Distinct vertices,
positive area and `st_is_valid()` are not required, and nothing is repaired. The CRS comes from the context (unknown if none).
The origin of `isovist()` stays a numeric vector.

## CRS policy

| Input metadata | Behaviour |
| --- | --- |
| Known projected CRS | accepted; coordinates and native CRS units unchanged (feet are not assumed to be metres) |
| Known geographic (longitude/latitude) CRS | rejected; transform explicitly with `sf::st_transform()` to suitable planar coordinates |
| Unknown or `NA` CRS | accepted; the numerical frame is the user's responsibility; no CRS is assigned |
| Several sf inputs | CRS must be equal (`sf::st_crs()` equality); unknown with unknown is equal; known with unknown, or unequal known CRS, is an error |
| Matrix mixed with sf | matrix coordinates must already be in the same frame; only sf metadata can be checked; matrices are never assigned a CRS |
| sf analysis input with an sf-origin graph | must equal the graph's retained CRS, known versus unknown included |
| sf analysis input with a matrix-only graph | no graph CRS to compare; a geographic sf CRS is rejected; the numerical frame is the user's responsibility |
| Matrix analysis input with a CRS-bearing graph | not checked; sf need not be available |
| Matrix-only graph | no CRS; sf output has an unknown CRS |

sf output carries the available CRS and never transforms coordinates. Distances, thresholds and areas keep their native units and
semantics. File input and output are described in [spatial I/O](README.md).
