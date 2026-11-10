# Public R API

The 33 exported functions are listed below with the PST routine each binds; the palette functions and the example-data loader
do not use the engine. Names are idiomatic R names that retain PST terminology; arguments are documented in the help pages
(`?angular_choice`, ...). An analysis accepts only the graph family of its PST descriptor.

| Group | Function | PST routine | Graph |
| --- | --- | --- | --- |
| Graphs | `axial_graph()` | `PSTACreateGraph` | creates `pst_graph` |
| | `segment_graph()` | `PSTACreateSegmentGraph` | creates `pst_segment_graph` |
| | `segment_group_graph()` | `PSTACreateSegmentGroupGraph` | creates `pst_segment_group_graph` from a segment graph and group ids |
| | `axial_line_lengths()`, `axial_crossing_coords()` | `PSTAGetGraphLineLengths`, `PSTAGetGraphCrossingCoords` | axial |
| Radius | `analysis_radius()` | `SPSTARadii` | any |
| Axial analyses | `network_integration()` | `PSTANetworkIntegration` | axial |
| | `network_reach()` | `PSTAReach` | axial |
| | `network_betweenness()` | `PSTASegmentBetweenness` (+ exported normalisers) | axial |
| | `attraction_reach()`, `attraction_distance()` | `PSTAAttractionReach`, `PSTAAttractionDistance` | axial |
| | `od_betweenness()` | `PSTAODBetweenness` | axial |
| Segment analyses | `angular_integration()` | `PSTAAngularIntegration` (+ exported normalisers) | segment |
| | `angular_choice()` | `PSTAAngularChoice` (+ exported normalisers) | segment |
| | `segment_grouping()` | `PSTASegmentGrouping` | segment |
| | `segment_group_integration()` | `PSTASegmentGroupIntegration` | segment group |
| Network construction | `create_junctions()`, `create_segment_map()` | `PSTACreateJunctions`, `PSTACreateSegmentMap` | none |
| Isovists | `isovist_context()`, `isovist()`, `isovist_context_free()` | `PSTACreateIsovistContext`, `PSTACalculateIsovist` | context |
| Raster comparison | `compare_line_results()`, `raster_data()`, `raster_to_polygons()`, `raster_free()` | `PSTACompareResults`, `PSTAGetRasterData`, `PSTARasterToPolygons` | comparison owner |
| Palettes (R only) | `colour_palettes()`, `colour_palette()`, `colour_map()` | none | none; see [palettes](palettes.md) |
| | `scale_colour_rpst_c()`, `scale_fill_rpst_c()`, `scale_colour_rpst_b()`, `scale_fill_rpst_b()` | none (optional ggplot2) | none |
| Example data (R only) | `load_example_data()` | none | none; see [example data](example-data.md) |

The S3 classes are `pst_graph`, `pst_segment_graph`, `pst_segment_group_graph`, `pst_radius`, `pst_isovist_context`,
`pst_raster` and `pst_result_file` (the invisible value of file-writing calls); `print` methods exist for the graphs and result
files. Compatibility contracts per family are in [compatibility](compatibility/).

## Radius and distance semantics

`analysis_radius()` has five independent fields: `straight`, `walking`, `steps`, `angular` and `axmeter`.

```r
analysis_radius(walking = 800, steps = NULL, angular = NULL)
```

`NULL` leaves a native limit absent; zero is a real limit. Which fields an analysis accepts, and the source-grounded bounds,
are in the [core contract](compatibility/core-network-analyses.md). For `network_reach()`, `network_betweenness()`, `angular_choice()` and
`angular_integration()` a field may be a vector, and `normalization` may name several methods for `network_betweenness()`, `angular_choice()` and `angular_integration()`; see [multi-radius](compatibility/multi-radius.md).

## Inputs and outputs

* Coordinates are plain numeric matrices (`x1 y1 x2 y2` per line or segment); `sf`/`sfc` inputs and `output = "sf"` options are
  optional adapters ([sf adapters](spatial-io/sf-adapters.md)); `segment_graph()` and `axial_graph()` also accept one
  GeoParquet or FlatGeobuf path ([spatial I/O](spatial-io/README.md)).
* Results are data frames or lists in input row order with column names from the naming scheme (`?result_column_names`); raw scores are kept and normalised scores are
  appended on request through the exported PST normalisers.
* Analyses that support it accept `output_file`/`overwrite` and `spatial_output_file`.
* No silent reordering, snapping, splitting, merging, unit conversion, deduplication, imputation, reprojection or clamping.
  Geographic CRS is rejected when known; mixed `sf` inputs must share a CRS.
* Validation problems and native failures become informative R errors naming the offending input. The exception is the network-depth limitation of `angular_choice()` (see [angular controls](compatibility/angular-controls.md)); other limitations are in [KNOWN_LIMITATIONS.md](../KNOWN_LIMITATIONS.md).

## Example

```r
library(rPSTool)
s <- segment_graph(cbind(0:4 * 3, 0, 1:5 * 3, 0))            # five collinear segments
angular_choice(s, radius = analysis_radius(walking = 8))      # raw choice, node count, depths

a <- axial_graph(rbind(c(0, 0, 2, 0), c(1, -1, 1, 1)))        # two crossing lines
network_integration(a, junctions = TRUE)
```
