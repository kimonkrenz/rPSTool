# rPSTool 0.1.0

First release.

## Progress display

* Long analyses show a single in-place progress line once an operation has run for two seconds. It is on in interactive sessions, off
  elsewhere, and controlled by `options(rPSTool.progress = TRUE/FALSE)`. See `docs/progress.md`.

## Result column names

* Network-analysis measures and diagnostics use a consistent result-column naming scheme identifying the analysis, distance, radius,
  weighting, normalisation and non-default analytical parameters: for example `ai_a_rw3000_t` (Angular Integration, angular distance,
  walking radius 3000, Turner normalisation), `ac_a_rw3000_n` (raw Angular Choice) and `nc_a_rw3000` (node count).
  Scalar and multi-radius calls name a calculation identically. See `?result_column_names` and `docs/output-naming.md`.
* Custom weights are named after the R object or literal data-frame column passed (`weights = population`, `weights = data$population`);
  anonymous vectors and calculations are errors raised before any calculation. See `?result_column_names`.
* Result-column collisions with existing spatial-output source columns are checked before calculation. An exact-name collision requires
  `overwrite = TRUE`, which replaces the column in the new file only. A source column differing from a result column only by letter case
  is always rejected, regardless of `overwrite`. FlatGeobuf sources with existing column names that differ only by case are also rejected
  because readers match fields case-insensitively.
* Parquet and GeoParquet outputs for analyses using the generated result-column naming scheme include an `rpst:columns` metadata manifest.
  FlatGeobuf outputs include it when the source has no header metadata or contains a flat, string-valued JSON metadata object with existing
  `rpst:*` keys. In the latter case, previous `rpst:*` entries are replaced while unrelated metadata is retained. Other source metadata is
  preserved unchanged, without adding a manifest.

## Engine

* Native R interface to the pinned PST engine (`pstalgo` v3.3.2, commit `63df80a2cf3dd289be95ea3d91667c3490719b75`), compiled into the
  package: no separate PST, Python or QGIS installation is needed. Build adaptations are recorded in `inst/upstream/PATCHES.md`.
* Graphs are built once in native memory and reused across analyses: axial (crossing-aware line) graphs with `axial_graph()`,
  endpoint-connected segment graphs with `segment_graph()` and segment-group graphs with `segment_group_graph()`. Graph families are
  exact native types and are never converted into one another.
* PST worker threads are capped centrally (`RPST_NUM_THREADS`; at most two workers under R's check core limit).

## Analyses

* Axial graphs: `network_integration()`, `network_reach()`, `network_betweenness()` (unweighted, weighted and attraction modes),
  `attraction_reach()`, `attraction_distance()` and `od_betweenness()`, with `axial_line_lengths()` and `axial_crossing_coords()`.
* Segment graphs: `angular_integration()`, `angular_choice()` and `segment_grouping()`; `segment_group_integration()` on a segment-group
  graph.
* Network construction (`create_junctions()`, `create_segment_map()`), isovists (`isovist_context()`, `isovist()`,
  `isovist_context_free()`) and raster comparison (`compare_line_results()`, `raster_data()`, `raster_to_polygons()`, `raster_free()`).
* `analysis_radius()` keeps PST's straight, walking, steps, angular and axmeter limits distinct. Normalisation uses PST's exported routines;
  analyses with a separate raw score retain it alongside normalised outputs.
* `analysis_radius()` accepts a vector in one field, and `normalization` accepts several methods, for `angular_choice()` and
  `angular_integration()`: PST runs once per radius and one combined result is returned or written.

## Palettes and example data

* `colour_palettes()`, `colour_palette()` and `colour_map()` provide eleven palettes in three groups: seven historical colour modes
  (Equal Ranges 3-Colour, 3-Colour Hue Only, Blue-Red, Purple-Orange, Greyscale, Monochrome and depthmapX Classic) with their historical
  band and Classic mappings; two white-background adaptations (Axmanesque White and depthmapX Classic White) that reuse some of the historical
  colours; and two palettes designed for rPSTool (Coral Night and Coral Day). The four non-historical palettes have nested 3/5/9 colour
  variants. The Blue-Red and Purple-Orange values coincide with the 7-class ColorBrewer RdYlBu and PuOr schemes (see `?colour_palettes`). `scale_colour_rpst_c()`, `scale_fill_rpst_c()`, `scale_colour_rpst_b()` and `scale_fill_rpst_b()`
  are optional ggplot2 scales; binned scales take user-supplied class boundaries and show the exact class colours in the legend. No
  classification is provided and none is required (`classInt` is only used in optional examples).
* `load_example_data()` loads the only bundled example data, the Barnsbury axial map, unlinks and gate observations from Hillier and
  Iida (2005); the movement observations were originally used in Penn et al. (1998), and the geometry was georeferenced and spatially
  transformed by Kimon Krenz, so the coordinates are not the original ones (`?hillier_iida`).

## Numerical behaviour

* The build uses `-ffp-contract=off` and a fixed set of float overloads for reproducible floating-point evaluation.
* Length-weighted `angular_choice(normalization = "syntax")` normalises with the length-weighted total depth (`tdw_..._wl`), as the
  original PST for QGIS plugin does; unweighted runs and the `"standard"` and `"turner"` normalisations use the total depth (`td_...`).
* `attraction_reach()`: when a nonconstant `decay` (`"power"`, `"curve"`, `"divide"`) is selected and `decay_constant` is not supplied, the
  effective constant is 1, matching the original PST for QGIS wizard; `decay = "constant"` defaults to 0 and any explicit constant, including
  0, is passed to PST unchanged.
* `od_betweenness()` rejects an `axmeter` radius with an error: the pinned algorithm ignores it, so it would never restrict anything.
* Where PST leaves outputs unwritten, rPSTool reports them as typed `NA` under a documented policy (Segment Betweenness diagnostics, Segment
  Group Integration); Attraction Distance with straight-only radius and point-group origins is rejected because PST never writes its group
  outputs on that path.
* Intentional differences from PST for QGIS are listed in the repository file `docs/compatibility/qgis-differences.md`
  (<https://github.com/kimonkrenz/rPSTool/blob/main/docs/compatibility/qgis-differences.md>).

## Input and output

* Optional `sf` adapters for geometry inputs and, with `output = "sf"`, geometry results; known geographic CRS is rejected and nothing is
  reprojected, snapped, split or repaired.
* `segment_graph()` and `axial_graph()` accept one GeoParquet or FlatGeobuf file path (suggested packages `arrow` (>= 25.0.0), `jsonlite` and
  `sf`; FlatGeobuf needs only `sf`).
* `output_file` writes analysis results directly to Parquet, and `spatial_output_file` writes a new GeoParquet or FlatGeobuf file with the
  source geometry and attributes plus the results, for the analyses listed in the repository file `docs/spatial-io/README.md`
  (<https://github.com/kimonkrenz/rPSTool/blob/main/docs/spatial-io/README.md>). Existing files are not replaced unless `overwrite = TRUE`, and the source network is never overwritten. On Windows a
  replacement fails, leaving the old file intact, while another process holds the destination open without sharing it for deletion.

## Known limitations

See `KNOWN_LIMITATIONS.md` in the repository.

* Angular Choice inherits a recursion-depth limit from PST: a very long chain of shortest-path steps can exhaust a worker thread's stack.
* Fast Segment Betweenness and Visual Connectivity are not exposed; there is no API for user-defined progress callbacks or cancellation.
* Persistence of `network_integration(junctions = TRUE)` is not offered.

## Licence

LGPL (>= 3). Attribution of the bundled third-party code is recorded in `inst/COPYRIGHTS`.
