# Public R API

All 33 exported functions are listed below; the first 25 call a PST routine (given), the palette functions and the example-data loader
at the end do not touch the engine. Names are idiomatic R names that retain PST
terminology; arguments are documented in the help pages (`?angular_choice`, ...). New optional arguments are appended to
signatures, never inserted. Native graph families are exact: an analysis accepts only the graph family of its PST descriptor.

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

The exported S3 classes are `pst_graph`, `pst_segment_graph`, `pst_segment_group_graph`, `pst_radius`, `pst_isovist_context`,
`pst_raster` and `pst_result_file` (the invisible value of file-writing calls); `print` methods exist for the graphs and result
files. Compatibility contracts per family are in [compatibility](compatibility/).

## Radius and distance semantics

PST has several distinct distance concepts (straight, walking, steps, angular, axmeter, and weights where applicable); rPSTool does
not collapse them into one generic radius. `analysis_radius()` keeps all five independent fields:

```r
analysis_radius(walking = 800, steps = NULL, angular = NULL)
```

`NULL` leaves a native limit absent; zero is a real limit. Which fields an analysis accepts, and the source-grounded bounds,
are in the [core contract](compatibility/core-network-analyses.md). For `angular_choice()` and `angular_integration()` a field may
be a vector and `normalization` may name several methods; see [multi-radius](compatibility/multi-radius.md).

## Inputs and outputs

* Coordinates are plain numeric matrices (`x1 y1 x2 y2` per line or segment); `sf`/`sfc` inputs and `output = "sf"` options are
  optional adapters ([sf adapters](spatial-io/sf-adapters.md)); `segment_graph()` and `axial_graph()` also accept one
  GeoParquet or FlatGeobuf path ([spatial I/O](spatial-io/README.md)).
* Results are data frames or lists in input row order with the native column names; raw scores are kept and normalised scores are
  appended on request through the exported PST normalisers.
* Analyses that support it accept `output_file`/`overwrite` and `spatial_output_file`.
* No silent reordering, snapping, splitting, merging, unit conversion, deduplication, imputation, reprojection or clamping.
  Geographic CRS is rejected when known; mixed `sf` inputs must share a CRS.
* Native failures and validation problems become informative R errors naming the offending input; they never crash R.

## Scope

rPSTool is not a generic graph library: it adds no generic routing, igraph replacement, custom centralities or unrelated GIS
preprocessing beyond what is needed to expose PST faithfully or to prepare explicitly valid PST input.

## Example

```r
library(rPSTool)
s <- segment_graph(cbind(0:4 * 3, 0, 1:5 * 3, 0))            # five collinear segments
angular_choice(s, radius = analysis_radius(walking = 8))      # raw choice, node count, depths

a <- axial_graph(rbind(c(0, 0, 2, 0), c(1, -1, 1, 1)))        # two crossing lines
network_integration(a, junctions = TRUE)
```
