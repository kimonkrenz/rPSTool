#' Calculate PST Network Integration on an axial graph
#'
#' Calls PST v3.3.2 `PSTANetworkIntegration` on the axial graph owned by
#' [axial_graph()]. PST computes each line's integration score, reached-line
#' count (including the origin line), and total topological depth. No scores
#' or normalisation are computed in R. The graph remains alive and reusable.
#'
#' `steps = NULL` leaves the radius unrestricted. A step limit sets only PST's
#' topological step radius; it does not set a walking, straight, angular or
#' axmeter radius. Changing between two lines counts as one step, including
#' at collinear endpoint joins. A limit of zero reaches only the origin line.
#' The radius argument accepts a [analysis_radius()] object that sets only `steps`.
#' With `junctions = TRUE`, PST also returns native junction coordinates and
#' scores. PST accumulates incident line scores divided by native
#' pairwise crossing multiplicity into a fresh zeroed buffer on each call, so
#' repeated calls produce independent results. This is not a conventional
#' distinct-line mean: two lines both scoring -1 yield a junction score of -2.
#' Coincident crossings and unlink ordering retain pinned PST behaviour. rPSTool
#' does not calculate junction scores; `NaN`/`Inf` are preserved.
#'
#' PST returns `-1` when fewer than two lines are reached. Its integration
#' formula can return `NaN` or `Inf` for small or zero-relative-asymmetry
#' neighbourhoods. These values are returned unchanged, not replaced with
#' missing values or recalculated. PST's float outputs are widened to R doubles.
#'
#' Only a topological step radius (or no radius) is accepted. The official PST
#' v3.3.2 Python/QGIS Network Integration offers only steps (the wizard shows only
#' a step radius and the Python execution code builds a steps-only radius), so
#' straight, walking, angular and axmeter limits, alone or mixed with steps, are
#' rejected before any native calculation. The native engine would accept them,
#' but they are outside the supported interface; for those metrics use
#' [angular_integration()] on a segment graph or [network_reach()].
#'
#' @param graph A live axial `pst_graph` created by [axial_graph()].
#' @param steps `NULL` for unrestricted radius, or one non-negative whole number
#'   no greater than `2147483647`, the pinned native signed step-limit maximum.
#' @param radius Optional [analysis_radius()] object that sets only `steps`; any
#'   other limit is an error. Supply either radius or a non-NULL steps argument.
#' @param junctions Logical scalar. If TRUE, return a list containing `lines`
#'   (the usual result) and `junctions` (a data frame with one-based `junction_id`,
#'   world `x, y` coordinates and native `integration` scores).
#' @param junction_output `"native"` (default) or `"sf"`; appended argument that
#'   applies only to the junction component and requires `junctions = TRUE` and
#'   the optional sf package. With `"sf"`, `junctions` is POINT sf with columns
#'   `junction_id` and `integration` plus geometry made solely from the returned
#'   native `x, y` (the `x`/`y` columns are then carried by the geometry). Native
#'   order is kept, CRS is the graph's retained sf CRS (unknown if none), and a
#'   zero-junction result has zero features. `lines` stays an ordinary data
#'   frame; no line geometry is reconstructed and no extra native call is made.
#' @param output_file `NULL` (default) returns the data frame. A path writes the line results directly to one
#'   Parquet file from PST's native result arrays and returns an invisible `pst_result_file` descriptor, without
#'   building R result vectors; it requires `junctions = FALSE` and the optional package `arrow (>= 25.0.0)`.
#'   Columns, order and values are those of the data frame (`line_id` and `node_count` int32, `integration` and
#'   `total_depth` float32; reading them back in R gives the identical doubles). Windows: see [pst_result_file].
#' @param overwrite `TRUE` or `FALSE` (default). With `output_file` or `spatial_output_file`, whether an existing file may be replaced. Replacement is a single rename and the old file is untouched if anything fails; see [pst_result_file] for the platform differences, notably on Windows.
#' @param spatial_output_file `NULL` (default) or one file path. When given, the analysis runs once and a NEW spatial dataset
#'   is written: the original geometry and attributes of the file the graph was built from, plus this analysis' result
#'   columns, matched to the source features by position (no spatial join). The output format equals the source format
#'   (GeoParquet or FlatGeobuf) and the CRS and geometry are unchanged; a result column named like a source column
#'   replaces it, other result columns are appended. The destination must end in `.fgb` (FlatGeobuf source) or `.parquet` (GeoParquet source), in any letter case. Mutually exclusive with `output_file`; needs a graph built from a
#'   file path; `overwrite` applies to this file only, never to the source. The source file must not be modified or reordered after the graph is built. Returns an invisible [pst_result_file] descriptor. Only with `junctions = FALSE`. See <https://github.com/kimonkrenz/rPSTool/blob/main/docs/spatial-io/spatial-output.md>.
#' @return With `junctions = FALSE`, a data frame with one row per input line,
#'   in the original line-row order: `line_id` (one-based integer row index), `integration` (PST's score),
#'   `node_count` (integer reached-line count, including the origin), and
#'   `total_depth` (PST's sum of topological steps to reached lines). With `junctions = TRUE`, a list containing
#'   `lines` (that data frame) and `junctions` (a data frame with one-based integer `junction_id`, world double
#'   `x, y` and native double `integration`; a POINT sf object if `junction_output = "sf"`). Zero crossings
#'   produce a zero-row junction data frame. With `output_file` or `spatial_output_file`, the line results is written to a file instead and an invisible `pst_result_file` descriptor (`path`, `rows`, `columns`, `format`) is returned; see [pst_result_file].
#' @export
#' @examples
#' lines <- cbind(x1 = c(0, 3, 6, 9, 12), y1 = 0,
#'                x2 = c(3, 6, 9, 12, 15), y2 = 0)
#' g <- axial_graph(lines)
#' network_integration(g)
#' network_integration(g, steps = 2)
#' network_integration(g, junctions = TRUE)
network_integration <- function(graph, steps = NULL, radius = NULL, junctions = FALSE,
                            junction_output = c("native", "sf"), output_file = NULL, overwrite = FALSE,
                            spatial_output_file = NULL) {
  resolved <- .pst_resolve_radius(steps, radius, FALSE)
  .pst_integration_steps_only(resolved)
  .pst_network_integration_run(graph, steps, radius, junctions, junction_output, output_file, overwrite,
                               spatial_output_file)
}

# PST v3.3.2's Python/QGIS Network Integration supports only a topological step radius
# (pstqgis networkintegrationwiz.py RadiusPage(radius_types=[RadiusType.STEPS]); networkintegrationanalysis.py builds
# Radii(steps=...) only; upstream commit 5f3f70f). The native engine accepts more, but that is not the supported boundary.
.pst_integration_steps_only <- function(radius) {
  if (!inherits(radius, "pst_radius")) return(invisible(radius))
  other <- c("straight", "walking", "angular", "axmeter")
  used <- other[!vapply(unclass(radius)[other], is.null, NA)]
  if (length(used))
    stop("network_integration() supports only a topological steps radius (or no radius): the official PST v3.3.2 ",
         "Python/QGIS Network Integration offers only steps. Unsupported radius limit(s) supplied: ",
         paste(used, collapse = ", "), ".", call. = FALSE)
  invisible(radius)
}

# Unrestricted implementation (any radius accepted by the native engine). Not exported; used by the public wrapper
# and by native-oracle regression tests that exercise the engine with every radius field.
.pst_network_integration_run <- function(graph, steps = NULL, radius = NULL, junctions = FALSE,
                            junction_output = c("native", "sf"), output_file = NULL, overwrite = FALSE,
                            spatial_output_file = NULL) {
  junction_output <- match.arg(junction_output)
  if (junction_output == "sf") {
    if (!isTRUE(junctions))
      stop("junction_output = \"sf\" requires junctions = TRUE.", call. = FALSE)
    .pst_require_sf()
  }
  ptr <- .pst_analysis_graph(graph, FALSE)
  steps <- .pst_resolve_radius(steps, radius, FALSE)
  overwrite <- .pst_flag(overwrite, "overwrite")
  .pst_spatial_request(output_file, spatial_output_file, !isTRUE(junctions), "network_integration with junctions = TRUE (one result per junction)")
  if (!is.null(output_file) || !is.null(spatial_output_file)) {
    if (isTRUE(junctions))
      stop("output_file cannot hold junction results; use junctions = FALSE to write the line results.",
           call. = FALSE)
    return(.pst_axial_result_file(
      output_file, overwrite, "network_integration", list(radius = .pst_radius_parameters(steps)), graph, ptr,
      c("line_id", "integration", "node_count", "total_depth"), "native line order (source feature order); no external feature identifiers",
      function(stream, columns, metadata_names, metadata_values, batch_rows) .Call(C_rpst_network_integration_stream, ptr, steps, stream, columns, metadata_names, metadata_values, batch_rows),
      spatial_output_file = spatial_output_file))
  }
  out <- .Call(C_rpst_network_integration_outputs, ptr, steps, junctions)
  lines <- data.frame(line_id = seq_along(out[[1L]]), integration = out[[1L]],
             node_count = out[[2L]], total_depth = out[[3L]])
  if (!junctions) return(lines)
  if (junction_output == "sf")
    return(list(lines = lines,
                junctions = .pst_sf_point_output(
                  out[[4L]], attr(graph, "crs", exact = TRUE),
                  data.frame(junction_id = seq_along(out[[5L]]), integration = out[[5L]]))))
  list(lines = lines,
       junctions = data.frame(junction_id = seq_along(out[[5L]]),
                              x = out[[4L]][, 1L], y = out[[4L]][, 2L],
                              integration = out[[5L]]))
}
