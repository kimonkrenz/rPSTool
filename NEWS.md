# rPSTool 0.1.0

First release.

## Result column names

* Every analysis names its result columns with one scheme that identifies the analysis, distance, radius, weighting,
  normalisation and non-default analytical parameters: for example `ai_a_rw3000_t` (Angular Integration, angular distance,
  walking radius 3000, Turner normalisation), `ac_a_rw3000_n` (raw Angular Choice) and `nc_a_rw3000` (node count). Scalar and
  multi-radius calls name a calculation identically. These replace the generic names `integration`, `choice`, `node_count`,
  `total_depth`, `normalized`, `betweenness`, `reached_count` and so on. See `?result_column_names` and `docs/output-naming.md`.
* Custom weights are named after the R expression passed to `weights` (`network_betweenness()`), `attraction_values`
  (`attraction_reach()`), `line_weights` (`attraction_distance()`) and `origin_weights` / `destination_weights`
  (`od_betweenness()`, inferred independently): an object name (`weights = population`) or a literal data-frame column
  (`data$population`, `data[["population"]]`). Anonymous vectors and calculated expressions are errors raised before any
  calculation; assign them to a named object first. Names are normalised automatically (lower case, runs of other characters
  become one `_`, outer underscores removed: `Jobs-2021` gives `jobs_2021`); the original is kept in the metadata.
* Existing result columns in a spatial-output source are detected before the native calculation starts: a clash needs
  `overwrite = TRUE` (replacing the column in the new file only), and a clash differing only by letter case is always an error.
* The metadata of every result file carries a `rpst:columns` manifest describing each column.

## Engine

* Native R interface to the pinned PST engine (`pstalgo` v3.3.2, commit `63df80a2cf3dd289be95ea3d91667c3490719b75`), compiled into the
  package: no separate PST, Python or QGIS installation is needed. The vendored engine source is byte-pinned and verified; every
  build adaptation is applied to a checksum-verified generated copy and recorded in `inst/upstream/PATCHES.md`.
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
* `analysis_radius()` keeps PST's straight, walking, steps, angular and axmeter limits distinct. Normalised scores are computed by PST's
  exported normalisers; raw scores are always kept.
* `analysis_radius()` accepts a vector in one field, and `normalization` accepts several methods, for `angular_choice()` and
  `angular_integration()`: PST runs once per radius and one combined result is returned or written.

## Palettes and example data

* `colour_palettes()`, `colour_palette()` and `colour_map()` provide eleven palettes in three groups: seven colour modes reproduced from depthmapX v0.9.1
  (Equal Ranges 3-Colour, 3-Colour Hue Only, Blue-Red, Purple-Orange, Greyscale, Monochrome and depthmapX Classic) with their historical
  band and Classic mappings; two white-background adaptations (Axmanesque White and depthmapX Classic White) that reuse some depthmapX
  colours; and two palettes designed for rPSTool (Coral Night and Coral Day). The four non-historical palettes have nested 3/5/9 colour
  variants. The Blue-Red and Purple-Orange values coincide with the 7-class ColorBrewer RdYlBu and PuOr schemes; ColorBrewer's licence
  terms were not verified. `scale_colour_rpst_c()`, `scale_fill_rpst_c()`, `scale_colour_rpst_b()` and `scale_fill_rpst_b()`
  are optional ggplot2 scales; binned scales take user-supplied class boundaries and show the exact class colours in the legend. No
  classification is provided and none is required (`classInt` is only used in optional examples).
* `load_example_data()` loads the only bundled example data, the Barnsbury axial map, unlinks and gate observations from Hillier and
  Iida (2005); the movement observations were originally used in Penn et al. (1998), and the geometry was georeferenced and spatially
  transformed by Kimon Krenz, so the coordinates are not the original ones (`?hillier_iida`).

## Numerical behaviour

* Direct-PST reference fixtures, generated through the official ctypes wrappers against the pinned engine, are compared with the
  package results; the build uses `-ffp-contract=off` and a fixed set of float overloads for reproducible floating-point evaluation.
* Length-weighted `angular_choice(normalization = "syntax")` normalises with the length-weighted total depth (`total_depth_weight`), as the
  original PST for QGIS plugin does; unweighted runs and the `"standard"` and `"turner"` normalisations use `total_depth`.
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
  (<https://github.com/kimonkrenz/rPSTool/blob/main/docs/spatial-io/README.md>). Result files are published safely: an exclusive
  temporary file in the destination directory, no-clobber publication (or a single replacing rename with `overwrite = TRUE`), and
  refusal to overwrite the source network through any alias, on POSIX systems and on Windows (Win32 API). On Windows a replacement
  fails, leaving the old file intact, while another process holds the destination open without sharing it for deletion. Result files
  are written through POSIX calls on Unix-alikes and through the Win32 API on Windows. The full development test suite and `R CMD check` passed on Windows x86-64 at commit `4119f2b` (R 4.6.2, Rtools GCC 14.3.0).

## Known limitations

* Angular Choice inherits a recursion-depth limit from PST: a very long chain of shortest-path steps can exhaust a worker thread's stack.
* Fast Segment Betweenness, Visual Connectivity and progress/log callbacks are not exposed.
* Persistence of `network_integration(junctions = TRUE)` is not offered.

## Licence

LGPL (>= 3). Attribution of the bundled third-party code is recorded in `inst/COPYRIGHTS`.
