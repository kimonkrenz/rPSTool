#' rPSTool: Space Syntax and Spatial Network Analysis in R
#'
#' rPSTool exposes the 'pstalgo' analysis engine of the Place Syntax Tool (PST) to R. The engine is compiled into the package, so no
#' separate PST, Python or QGIS installation is needed. rPSTool wraps the pinned engine (PST v3.3.2); it does not reimplement or alter
#' PST's algorithms, and it is not the PST plugin for QGIS. rPSTool is not affiliated with or endorsed by the PST authors.
#'
#' @details
#' A graph is built once, lives in native memory and is reused by any number of analyses. There are three graph families, and
#' analyses accept only the family they were written for.
#'
#' **Axial (crossing-aware line) graphs** are created by [axial_graph()] and analysed by [network_integration()],
#' [network_reach()], [network_betweenness()], [od_betweenness()], [attraction_reach()] and [attraction_distance()].
#' [axial_line_lengths()], [axial_crossing_coords()] and [compare_line_results()] are helpers for working with axial lines and
#' their results.
#'
#' **Endpoint-connected segment graphs** are created by [segment_graph()] and analysed by [angular_integration()] and
#' [angular_choice()].
#'
#' **Segment-group graphs** are created by [segment_group_graph()] from a segment graph and a grouping of its segments
#' ([segment_grouping()]), and analysed by [segment_group_integration()].
#'
#' Analysis limits are described with [analysis_radius()]. Network preparation is provided by [create_junctions()] and
#' [create_segment_map()]. Visibility and raster utilities are [isovist_context()], [isovist()], [raster_data()],
#' [raster_to_polygons()] and the explicit release functions [isovist_context_free()] and [raster_free()].
#'
#' **Colour palettes.** [colour_palettes()] lists the bundled palettes, [colour_palette()] returns their colours and
#' [colour_map()] maps values to colours; optional 'ggplot2' scales are [scale_colour_rpst_c()], [scale_fill_rpst_c()],
#' [scale_colour_rpst_b()] and [scale_fill_rpst_b()]. The palettes fall into three groups: seven reproduced 'depthmapX' v0.9.1
#' colour modes; two white-background adaptations (`axmanesque_white` and `depthmapx_classic_white`); and Coral Night and Coral Day
#' (`coral_night`, `coral_day`), designed for rPSTool.
#'
#' **Example data.** [load_example_data()] returns the Barnsbury (London) axial map, unlinks and gate observations of Hillier and
#' Iida (2005); the layout is described in [hillier_iida].
#'
#' **Optional packages.** The suggested packages 'sf', 'arrow' (>= 25.0.0) and 'jsonlite' add 'sf' adapters, GeoParquet and
#' FlatGeobuf input, and result files ([pst_result_file()]). Result files are written through POSIX calls on Unix-alikes and
#' through the Win32 API on Windows. The Windows implementation passed the development test suite on Windows; validation of the
#' final release candidate on Windows is still outstanding.
#'
#' **Vignettes.** `vignette("getting-started", package = "rPSTool")` is a first walk-through, and
#' `vignette("pst-capabilities", package = "rPSTool")` describes what the PST engine offers and how rPSTool relates to the PST plugin for
#' QGIS.
#'
#' **Citation.** Run `citation("rPSTool")` for the suggested references: the rPSTool package and, if your analysis relies on the engine,
#' PST itself. Citation is voluntary guidance and separate from the legal notices.
#'
#' @author Maintainer and author: Kimon Krenz. The bundled PST engine is by its original authors; copyright and licence notices
#'   are in the installed `COPYRIGHTS` file (see `system.file("COPYRIGHTS", package = "rPSTool")`).
#' @seealso [axial_graph()], [segment_graph()], [analysis_radius()], [colour_palettes()], [load_example_data()]; the project page
#'   <https://github.com/kimonkrenz/rPSTool> and the PST repository <https://github.com/SMoG-Chalmers/PST>.
#' @keywords package
"_PACKAGE"
