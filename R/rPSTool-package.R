#' rPSTool: Space Syntax and Spatial Network Analysis in R
#'
#' rPSTool brings the analysis engine of the Place Syntax Tool (PST) to R. It builds street-network graphs from line geometry
#' and runs PST analyses such as network integration, reach, betweenness and angular choice, returning ordinary R data frames.
#' The engine ('pstalgo', PST v3.3.2) is compiled into the package, so no separate PST, Python or QGIS installation is needed.
#' rPSTool does not reimplement or alter PST's algorithms, and it is not the PST plugin for QGIS. It is not affiliated with or
#' endorsed by the PST authors.
#'
#' @details
#' A graph is built once and reused by any number of analyses. There are three graph families, and each analysis accepts
#' only the family it was written for.
#'
#' **Axial (crossing-aware line) graphs** are created by [axial_graph()] and analysed by [network_integration()],
#' [network_reach()], [network_betweenness()], [od_betweenness()], [attraction_reach()] and [attraction_distance()].
#' [axial_line_lengths()] and [axial_crossing_coords()] inspect them.
#'
#' **Endpoint-connected segment graphs** are created by [segment_graph()] and analysed by [angular_integration()] and
#' [angular_choice()].
#'
#' **Segment-group graphs** are created by [segment_group_graph()] from a segment graph and a grouping of its segments
#' ([segment_grouping()]), and analysed by [segment_group_integration()].
#'
#' Distance limits are set with [analysis_radius()]. Network preparation is provided by [create_junctions()] and
#' [create_segment_map()]. Visibility and raster utilities are [isovist_context()], [isovist()], [compare_line_results()],
#' [raster_data()] and [raster_to_polygons()], with the release functions [isovist_context_free()] and [raster_free()].
#'
#' **Colour palettes.** [colour_palettes()] lists the bundled palettes, [colour_palette()] returns their colours and
#' [colour_map()] maps values to colours; optional 'ggplot2' scales are [scale_colour_rpst_c()], [scale_fill_rpst_c()],
#' [scale_colour_rpst_b()] and [scale_fill_rpst_b()].
#'
#' **Example data.** [load_example_data()] returns the Barnsbury (London) axial map, unlinks and gate observations of Hillier
#' and Iida (2005); the layout is described in [hillier_iida].
#'
#' **Optional packages.** The suggested packages 'sf', 'arrow' (>= 25.0.0) and 'jsonlite' add 'sf' adapters, GeoParquet and
#' FlatGeobuf input, and result files ([pst_result_file]).
#'
#' **Vignettes.** `vignette("getting-started", package = "rPSTool")` is a worked example with the Barnsbury data, and
#' `vignette("pst-capabilities", package = "rPSTool")` describes what the PST engine offers and how rPSTool relates to the PST
#' plugin for QGIS.
#'
#' **Citation.** Run `citation("rPSTool")` for the suggested references: the rPSTool package and, if your analysis relies on the
#' engine, PST itself. Citation is voluntary guidance and separate from the legal notices.
#'
#' @author Maintainer and author: Kimon Krenz. The bundled PST engine is by its original authors; copyright and licence notices
#'   are in the installed `COPYRIGHTS` file (see `system.file("COPYRIGHTS", package = "rPSTool")`).
#' @seealso [axial_graph()], [segment_graph()], [analysis_radius()], [colour_palettes()], [load_example_data()]; the project page
#'   <https://github.com/kimonkrenz/rPSTool> and the PST repository <https://github.com/SMoG-Chalmers/PST>.
#' @keywords package
"_PACKAGE"
