# sf adapter contract and geometry inventory

`sf` is an optional `Suggests` dependency. R-level adapters construct the existing
matrix/list representations and call the same pinned PST core. There is no new
numerical implementation, graph family, topology inference or native storage.
Normal installations and matrix/native calls work without sf. Adapter calls check
availability explicitly. No attributes supply weights, parameters or identifiers.

## Native graphs and crossing output

- `axial_graph(x, ...)` accepts sf/sfc XY LINESTRINGs with **exactly two vertices**
  per feature. With `line_indices`, x instead accepts XY POINTs in coordinate-row
  order, including unused coordinates affecting the native center. Indices remain
  explicit one-based matrix indices; sf attributes are ignored.
- `segment_graph(x)` accepts the same two-vertex XY LINESTRING representation,
  feeding the endpoint-connected builder, never the crossing-aware builder.
- Axial `unlinks` accepts XY POINTs. `points` accepts XY POINTs or POLYGONs.
  POLYGON feature counts are derived; `points_per_polygon` must be NULL and
  `polygon_point_interval` remains explicit. Each feature is a native point
  group; all ring boundaries, including hole boundaries, are sampled by PST.
- `axial_crossing_coords(graph, output="sf")` derives independent XY POINTs
  solely from the native coordinate matrix, with one-based `crossing_id` in
  native crossing order and the retained CRS. Empty results have zero features.
  Default `output="native"` preserves the matrix exactly.

Feature, part, vertex and endpoint order remain unchanged. No snapping,
reprojection, unit conversion, simplification, repair, dissolution, splitting,
merging or deduplication occurs in the adapter. The graph constructors retain
only the native pointer and existing metadata plus a `crs` attribute when sf
participated, never the input sf object, attributes or duplicate graph geometry.
`attr(graph, "crs")` inspects that metadata; graphs are not themselves sf objects.

Empty POINT/LINESTRING features, nonfinite coordinates, wrong geometry families,
mixed collections, MULTIPOINT, MULTILINESTRING, MULTIPOLYGON and Z/M are rejected.
Even a collinear third LINESTRING vertex is rejected: the endpoint-row core cannot
retain it. Empty POLYGON features (no rings) represent existing zero-count groups;
empty rings inside a polygon are rejected. An empty polygon feature collection
is rejected because the native polygon-count vector must be nonempty. Empty point
collections remain valid where the matrix API allows zero rows. Empty networks
remain rejected by the established native validation.

sf explicitly closes polygon rings. Remove exactly the final coordinate when it
equals the first, preserving every other vertex (even repetitions), ring order
and winding; reject unclosed rings. Insert exactly one NaN/NaN row between rings.
This is a representation conversion, not repair. `CreateGraph.cpp` calls
`GeneratePointsAlongRegionEdge` in `geometry/RegionPoints.cpp`, which iterates
separator-delimited rings and closes each using its first point. All rings feed
one region's native point group. MULTIPOLYGON features have no established
one-feature/one-region boundary contract here and are not flattened implicitly.

## Supplied analysis geometry

`network_reach(origins=...)` and `od_betweenness(origins=...)` accept sf/sfc XY
POINT features in exact feature order, using the shared coordinate-matrix
converter before existing native validation. Reach still requires at least one
origin; OD permits an empty collection. On/off-network assignment, strict Reach
boundaries, weights, radii and missing-output behavior remain native.

`attraction_reach()` and `attraction_distance()` accept XY POINT or
POLYGON attractions. They reuse the graph-point converter above: remove only
explicit ring closure, insert NaN/NaN ring separators, and derive one count per
feature. Keep `points_per_polygon=NULL` for sf inputs and supply
`polygon_point_interval` explicitly for POLYGONs. Both native analyses call
`GeneratePointsAlongRegionEdge` (`AttractionReach.cpp`, `NextAttractionPolygon`;
`AttractionDistance.cpp`, polygon sampling loops), the same sampler as graph
construction. Holes are additional sampled boundaries within the same native
attraction polygon, not separate attractions. Empty features are zero-count
groups; empty polygon collections remain rejected. MULTIPOLYGON is rejected.

Explicit `attraction_values` align with POINT/POLYGON feature order, including
empty groups. OD `origin_weights` align with supplied POINT order;
`destination_weights` still align with retained native graph samples. Distance
`line_weights` still align with graph lines. Attributes never provide these
values. All mode restrictions remain, especially the narrow straight-only
point-group Distance rejection, straight-mode radius limits and network axmeter
exclusion. Native destination-index conventions are unchanged: indices may refer
to samples or polygons depending on mode, not universally to sf features.

Results remain independent ordinary data frames without geometry, sf attributes
or retained inputs. No native ownership/extent/float/count validation changed.

## Raster comparison adapters

`compare_line_results(x, values1, values2, y = NULL, ...)` accepts XY LINESTRING
sf/sfc for `x` and `y` through the shared `.pst_sf_lines()` converter: one feature
is one `x1,y1,x2,y2` row with exactly two finite vertices, in feature order and
endpoint direction. Longer LINESTRINGs, empty features, MULTILINESTRING,
collections, nonfinite coordinates and Z/M are rejected, never reduced to
endpoints; zero-length two-vertex lines follow the matrix/native contract.
`values1`/`values2` stay explicit (with `y = NULL` both address `x`; otherwise
`values1` addresses `x` and `values2` addresses `y`); attributes are ignored.
CRS follows the shared policy across `x` and `y` (geographic rejected; two sf
inputs must be compatible, known versus unknown included; a matrix is assumed to
share the frame and is never assigned a CRS; projected units untouched). Only the
CRS is retained, as `attr(raster, "crs")`, when sf takes part. Matrix-only rasters
are unchanged and source sf objects are not retained.

`raster_data()` is deliberately unchanged: bbox, dimensions, pitch, format,
extrema and pixels are raster data, not vector geometry, and no raster/sf
dependency is added.

`raster_to_polygons(raster, ranges, output = c("native", "sf"))` keeps the
native result as authority and default. With `"sf"` the result is an ordinary
list in range-row order whose elements are `sfc_POLYGON` objects: one POLYGON per
native polygon (native order), first ring the native outer ring and later rings
the native holes in order. An empty range is a zero-feature `sfc_POLYGON`; zero
ranges give an empty list; CRS comes from the raster owner (unknown if none).
No `range_id`/`polygon_id`, threshold attributes or flattened table are added.

Ring conversion is strictly representational: every native coordinate and its
order and winding are kept, the first coordinate is appended only when the ring is
not already closed (never a second closure), repeated vertices are kept, and no
area, distinctness or `st_is_valid()` policy is applied. A ring that cannot become
an sf ring by that one closure fails the whole call with its range, polygon and
ring position: fewer than three rows (including empty and one-row `NaN`/`Inf`
output and two-vertex rings), nonfinite coordinates, or an already-closed ring
with fewer than four rows. Nothing is dropped, repaired or replaced, and native
output remains available. Conversion runs in R on the already copied native
result, after the transient native polygon owner has been freed, so a failure
leaves the persistent raster and its data untouched. The shared output-ring helper
also serves the isovist output, whose messages are unchanged.

Against the 79 direct fixture cases: all 79 inputs run through sf lines with
identical rasters, pixels and polygons. For polygon output, 32 whole case outputs
are representable and 47 contain at least one unrepresentable ring (error). Of
438 ranges, 291 are empty, 81 are non-empty and representable (33 with holes) and
66 are non-empty but unrepresentable.

## Betweenness attraction points and Integration junction output

`network_betweenness(attraction_points=)` accepts XY POINT sf/sfc in exact feature
order through the shared POINT converter and `.pst_sf_analysis_crs()` before the
unchanged native call. Empty, nonfinite, multipart, mixed and Z/M geometry is
rejected; an empty collection reaches the native at-least-one-row validation.
`weights` stays the only weight source (one per supplied point; zero and negative
values as in the matrix API) and sf attributes are ignored. Known geographic CRS
is rejected; sf CRS must equal any CRS retained by the graph (known versus
unknown included); matrix points on a CRS-bearing graph need no sf; a matrix-only
graph leaves the numerical frame to the caller. The sf object is not retained.
Distances, normalisation, signed weights, missing-output handling and workers are
unchanged native behaviour.

`network_integration(..., junctions=TRUE, junction_output="sf")` replaces only the
`junctions` component with POINT sf: `junction_id`, `integration` and geometry
from the already returned native x/y (the x/y columns are carried by the
geometry). `junction_output` is appended after `junctions`, defaults to
`"native"`, and requires `junctions=TRUE` and sf (otherwise a clean error before
any native call). Native order, score values (including NaN/Inf and
multiplicity-dependent results), and zero-junction results (zero features) are
preserved; the CRS is the graph's retained CRS, unknown for matrix-only graphs.
`lines` remains an ordinary data frame; there is no line geometry
reconstruction, attribute join, extra native call or numerical change.

## Explicit construction adapters

`create_junctions()` accepts the graph adapters' exactly-two-vertex XY
LINESTRING packed layers, XY POINT coordinate rows with explicit index matrices,
and XY POINT unlinks. Explicit empty second layers keep two-layer mode; empty
first layers still fail under the established unwritten-result policy.
`output="sf"` returns POINT sf with one-based `junction_id` in native order;
the default remains the copied coordinate matrix.

`create_segment_map(coords, sections=NULL, ..., output="native")` accepts
sf/sfc XY LINESTRING and MULTILINESTRING features in coords. Matrix coords still
require explicit sections. For sf coords, sections must be NULL: each feature
is one native source object; every LINESTRING vertex becomes one coordinate row
and its section is its point count. MULTILINESTRING parts stay in order as
separate sections, with earlier parts encoded `-(point_count + 1)` and the final
part encoded as its nonnegative point count. No edge connects separate parts.
Mixed LINESTRING/MULTILINESTRING feature sequences are accepted without changing
feature order. Empty LINESTRINGs and multipart features without parts encode
one zero section, advancing the source ID. Empty and singleton multipart parts
encode their exact counts (earlier empty parts are -1; earlier singletons -2).
At least one actual edge is still required by the native contract. All coordinates
are preserved, including repeated vertices, unused singleton coordinates and
closed lines. A trailing negative matrix section has no sf equivalent encoding
as a final section: sf finalizes the same source with the nonnegative count;
its outputs retain exactly the same native source association.

Collections, POINT/MULTIPOINT/POLYGON/MULTIPOLYGON coords, Z/M, nonfinite or
malformed part matrices are rejected; no geometry is flattened, repaired,
reordered or transformed. Construction unlinks accept XY POINTs, with the
existing native mode exclusions unchanged. Successful safe closed shapes and
all three guarded cycle failures follow precisely the matrix/section path.

With `output="sf"`, segment-map results keep the existing three-component list:
`segments` is two-vertex LINESTRING sf with the existing one-based `source_id`
column, `source_id` remains the unchanged integer vector, and `unlinks` is POINT
sf with only geometry. Zero-row results have zero features. All output geometry
comes solely from the already copied native arrays. There are no input attribute
joins, persistent identifiers or implicit graph construction. Output CRS comes
only from compatible supplied sf metadata (including unlink or second-layer
metadata); matrix-only sf output has unknown CRS. All existing positional calls
retain their argument positions; output is appended to both functions.

## Isovist adapters

`isovist_context()` accepts, per group, an sf/sfc layer instead of a matrix
(or matrix list). Obstacle/attraction polygon layers are XY POLYGONs with exactly
one ring per feature; each ring has only its structural closing coordinate
removed (order and winding are untouched; PST expects Cartesian clockwise and
rings are never rewound). Point layers are XY POINTs. Holes, empty polygon
features, MULTIPOLYGON, Z/M and nonfinite coordinates are rejected because a PST
obstacle polygon is one ring. An empty layer is an empty group. CRS is checked
across all nested layers (matrix groups contribute none) and kept only as the
context `"crs"` attribute when sf participated; public context fields are unchanged.

sf's mandatory structural closing coordinate is removed; every other vertex and
the winding are preserved. Scoped closure provenance is in the
[isovist compatibility record](../compatibility/isovist.md#optional-sf-adapters).
Matrix groups retain any intentional repeated terminal vertex.

`isovist(..., output="sf")` replaces only `polygon` with a length-one POLYGON
sfc built from the copied native vertices. The first vertex is appended only when
the native polygon is not already closed. Results with fewer than three vertices,
nonfinite coordinates, or fewer than four ring coordinates after closure (e.g. an
already-closed three-row result) raise an R error; the native default remains
available. Distinct vertices, positive area and `st_is_valid()` are not required
and nothing is repaired. CRS comes from the context (unknown if none).

## CRS policy

| Input metadata | Behavior |
| --- | --- |
| Known projected CRS | Accept unchanged numeric coordinates and native CRS units, including feet; do not assume metres |
| Known geographic longitude/latitude CRS | Reject; instruct explicit `sf::st_transform()` to suitable planar coordinates |
| Unknown/NA CRS | Accept with the matrix interface's user-responsibility semantics; do not assign a CRS |
| Multiple sf inputs | Require sf CRS equality, including unknown versus unknown; known versus unknown or unequal known CRS errors |
| Mixed matrix + sf | Matrix coordinates must already be in the same numerical frame; only sf metadata can be checked; do not assign metadata to matrices |
| sf analysis input + sf-origin graph | Require equality with retained graph CRS, including known/unknown incompatibility; only check when the supplied analysis input is sf |
| sf analysis input + matrix-only graph | No graph CRS exists to compare; reject geographic sf CRS but numerical frame remains user responsibility |
| Matrix analysis input + CRS-bearing graph | Leave matrix validation unchanged; numerical frame remains user responsibility; sf need not be available |
| Matrix-only graph | Existing fields/attributes unchanged; sf output has unknown CRS |

CRS equality uses `sf::st_crs()` equality, permitting equivalent metadata rather
than requiring identical text/EPSG spellings. sf output propagates available CRS
metadata without transforming native coordinates. Native distances, thresholds,
areas and PST float narrowing retain their existing units and semantics.

## Inventory of geometry-bearing public surfaces

Classes: **1** clean adapter; **2** explicit representation conversion needed;
**3** cannot faithfully use that sf form without changing semantics. Every row
is implemented or a deliberate native-form/out-of-scope retention.

| Surface | Class and faithful representation | Status |
| --- | --- | --- |
| `axial_graph()` endpoint rows | 1: two-vertex XY LINESTRING; 3: longer/multipart lines cannot retain all geometry | Implemented; unsupported forms explicitly rejected |
| `axial_graph()` indexed coords | 1: XY POINT coordinate rows plus existing explicit index matrix | Implemented |
| Graph unlinks/points | 1: XY POINT rows; 3: MULTIPOINT/collection attributes imply no native row mapping | Implemented |
| Graph polygon point groups | 2: POLYGON ring closure removal and NaN separators; 3: multipart feature grouping unestablished | Implemented POLYGON; MULTIPOLYGON rejected |
| `segment_graph()` | 1: two-vertex XY LINESTRING; 3: arbitrary polyline would change endpoint graph | Implemented |
| `axial_crossing_coords()` | 1: XY POINT output in native crossing order | Implemented explicit `output="sf"` |
| `network_integration(junctions=TRUE)` junction component | 1: existing junction x/y, junction_id and scores form POINT rows | Implemented as appended `junction_output="sf"`; junction component only, no line geometry |
| `network_reach(origins=...)` | 1: supplied XY POINT matrix rows | Implemented; shared POINT converter and graph CRS check |
| `attraction_reach()` / `attraction_distance()` attractions | 1: POINT; 2: POLYGON boundary sampling with existing closure/separators/counts | Implemented POINT/POLYGON; shared graph conversion and all mode exclusions preserved |
| `network_betweenness(attraction_points=...)` | 1: supplied XY POINT rows with explicit per-point weights | Implemented; shared POINT converter and graph CRS check |
| `od_betweenness(origins=...)` | 1: supplied XY POINT rows, not graph destinations or external IDs | Implemented; shared POINT converter and graph CRS check |
| `create_junctions()` x/y/indexed/unlinks and result | 1: same endpoint/POINT input rules and native POINT result | Implemented |
| `create_segment_map()` coords + sections | 2: LINESTRING and ordered MULTILINESTRING parts map to signed section encoding | Implemented; exact signed parts and empty/singleton source advancement |
| Constructed segments and unlinks | 1: native two-endpoint LINESTRING rows with source_id, and POINT unlinks | Implemented explicit sf list; no attribute joins |
| `isovist_context()` polygon groups | 2: explicit list of sf POLYGON layers can retain group/feature order, closure conversion; 3: holes cannot be encoded as polygon objects without changing visibility/obstacle semantics | Implemented: single-ring POLYGON layers only; holes, empty polygons and MULTIPOLYGON rejected; winding never rewound |
| Isovist attraction-point groups | 1: explicit list of POINT layers preserves groups | Implemented: POINT layers per group |
| `isovist()` origin | 3: vector x/y is not a point-coordinate matrix under the POINT rule | Intentionally keep numeric vector; context can supply output CRS |
| Isovist output polygon | 2: add required ring closure to native matrix; finite cardinality may be insufficient for POLYGON | Implemented `output="sf"`: length-one POLYGON sfc; fails explicitly for <3 vertices, nonfinite coordinates or <4 ring coordinates; native default unchanged |
| `compare_line_results()` x/y | 1: two-vertex XY LINESTRING inputs; values remain explicit vectors | Implemented: two-vertex XY LINESTRING for x and y via the shared line converter; values remain explicit; CRS retained on the raster owner |
| `raster_to_polygons()` range/polygon/ring result | 2: ordered polygon rings including holes, add closure; some native results contain nonfinite vertices | Implemented `output="sf"`: list of `sfc_POLYGON` per range; fails explicitly with range/polygon/ring position for unrepresentable native rings; native list authoritative; no repair/missing-value policy |
| `raster_data()` bbox/pixels | 3: pixel matrix/extent are raster data, not vector sf geometry | Deliberately unchanged ordinary R list: no sf, stars, terra, units or CRS-wrapped bbox; retain native raster result |
| Other core/angular/group analysis results and line lengths | 3: numeric/index rows lack returned line geometry | Out of scope for implicit geometry reconstruction or attribute joins; retain existing results |
| Owner release, radii, status helpers | No geometry input/output | Out of scope |

`CreateSegmentMap.cpp` (section loop in lines 159–177 of the pinned source) emits
edges in part order with current `base_count`; negative `-(point_count+1)` keeps
that source for the following section, and a final nonnegative section advances
the source ID. Thus earlier MULTILINESTRING parts can be negative, with the last
part nonnegative; no connecting edge is added between parts. Empty features/parts
need explicit zero-count encoding to preserve subsequent native source IDs.
Native outputs retain only existing one-based `source_id`, possibly repeated or
skipping IDs, never persistent/external identifiers or inferred attribute joins.
The adapter tests compare this mapping exactly against all 103 existing direct
segment-map fixtures, alongside all 21 junction fixtures. The fixtures remain
unchanged.

## Validation and remaining scope

New tests compare accepted sf input against the existing matrix interface
**exactly**, including native point state/group sizes and repeated analyses,
projected/unknown/mismatched/geographic CRS, holes and empty groups, indexed
coordinate order, integer/double matrices, large world translations, input GC,
mutated input, native owner release and independent output lifetime. Analysis
adapters additionally exercise existing direct-PST fixture inputs and every
Attraction Distance exclusion; the numerical fixture files remain untouched.
Optional
availability failure and unchanged matrix graph shape are tested separately.
The existing direct-PST fixtures remain numerical authority and are unchanged.
Construction adds exact conversion/default-output/sf-output comparisons for all
124 direct fixtures, empty/singleton multipart source advancement, both modes and
thresholds, empty junction layers, all three guarded cycle cases, CRS, unsupported
geometry, input mutation/GC and independent output lifetime. Matrix calls and
optional availability failures are tested without requiring sf.
Exact polygon Reach equivalence uses a single worker to fix native floating-point
reduction order; runtime multi-worker behavior is unchanged.

Additive sf/sfc geometry inputs and explicit `output="sf"`
exist wherever returned geometry has a faithful representation; defaults remain
native, and unrepresentable surfaces are retained in native form by decision. No
parallel numerical implementation exists. File input and output are described in [spatial I/O](README.md); external-ID contracts
are not part of the sf adapters.
