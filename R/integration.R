#' Network Integration of an axial graph
#'
#' Calculates Network Integration for every line of an axial graph: how accessible each line is from every
#' other line, measured by topological depth (the number of direction changes). Use it for classic
#' axial-map integration analysis, optionally within a limited number of steps.
#'
#' @details
#' **Definition.** For each line PST counts the lines it reaches (including the line itself) and sums their
#' topological depths, then computes an integration score from these two quantities. Changing between two lines counts as one step,
#' including at collinear endpoint joins. The scores are computed by PST; rPSTool does not alter or
#' normalise them.
#'
#' **Radius.** `steps = NULL` leaves the radius unrestricted. A step limit restricts only the topological
#' radius: a limit of zero reaches only the line itself. Supply the limit with `steps` or with
#' `radius = analysis_radius(steps = ...)`, but not both. Only a steps radius (or none) is accepted, which
#' matches the Network Integration offered by the official PST for QGIS plugin; walking, straight, angular
#' and axmeter limits, alone or combined with steps, are rejected before any calculation. For those metrics
#' use [angular_integration()] on a segment graph or [network_reach()].
#'
#' **Special values.** PST returns `-1` when fewer than two lines are reached. For very small or
#' symmetric neighbourhoods the formula can give `NaN` or `Inf`. These values are returned unchanged and
#' are not replaced by `NA`.
#'
#' **Junctions.** With `junctions = TRUE`, PST also returns a score for every crossing. Each line's score is divided by the
#' number of crossings between the same pair of lines and accumulated at the crossing, so this is not the
#' mean of the distinct lines meeting there: two lines that both score -1 give a junction score of -2.
#' Coincident crossings and unlink ordering follow PST.
#'
#' @section Limitations:
#' Only steps radii are accepted (see Details).
#'
#' @param graph An axial graph created by [axial_graph()].
#' @param steps `NULL` (default, unrestricted) or one non-negative whole number no greater than
#'   2147483647.
#' @param radius Optional [analysis_radius()] object that sets only `steps`. Supply either `radius` or a
#'   non-`NULL` `steps`.
#' @param junctions `TRUE` or `FALSE` (default). If `TRUE`, also return junction scores (see Value).
#' @param junction_output `"native"` (default) or `"sf"`. Applies only to the junction table and requires
#'   `junctions = TRUE` and the suggested package 'sf'. With `"sf"` the junctions are POINT features with
#'   `junction_id` and `integration` columns, in PST's order and with the graph's CRS.
#' @param output_file,overwrite,spatial_output_file Write the results to a file instead of returning
#'   them; see [pst_result_file]. `output_file` and `spatial_output_file` require `junctions = FALSE`.
#' @return With `junctions = FALSE`, a data frame with one row per input line, in the order of the lines
#'   supplied to [axial_graph()]:
#'   * `line_id`: one-based row index of the line,
#'   * `ni_s_<radius>`: PST's integration score (for example `ni_s_rs3` within three steps, `ni_s_rg` unrestricted),
#'   * `nc_s_<radius>`: integer number of lines reached, including the line itself,
#'   * `td_s_<radius>`: the sum of the topological steps to the reached lines.
#'
#'   The names are described in [result_column_names].
#'
#'   With `junctions = TRUE`, a list with `lines` (that data frame) and `junctions`, a data frame with
#'   one-based `junction_id`, world coordinates `x` and `y` and the junction score `nj_s_<radius>` (a POINT `sf` object if
#'   `junction_output = "sf"`). A graph without crossings gives a zero-row junction table. With `output_file`
#'   or `spatial_output_file` the results are written to a file and an invisible [pst_result_file]
#'   descriptor is returned.
#' @seealso [angular_integration()] for segment graphs, [network_reach()], [analysis_radius()]
#' @references
#' Hillier, B. and Hanson, J. (1984). *The Social Logic of Space*. Cambridge University Press.
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
  .pst_nm_names(.pst_nm_network_integration(steps))   # generated names are validated before any native work
  .pst_spatial_request(output_file, spatial_output_file, !isTRUE(junctions), "network_integration with junctions = TRUE (one result per junction)")
  if (!is.null(output_file) || !is.null(spatial_output_file)) {
    if (isTRUE(junctions))
      stop("output_file cannot hold junction results; use junctions = FALSE to write the line results.",
           call. = FALSE)
    return(.pst_axial_result_file(
      output_file, overwrite, "network_integration", list(radius = .pst_radius_parameters(steps)), graph, ptr,
      c("line_id", .pst_nm_names(.pst_nm_network_integration(steps))), "native line order (source feature order); no external feature identifiers",
      function(stream, columns, metadata_names, metadata_values, batch_rows) .Call(C_rpst_network_integration_stream, ptr, steps, stream, columns, metadata_names, metadata_values, batch_rows),
      spatial_output_file = spatial_output_file, cols = .pst_nm_network_integration(steps)))
  }
  out <- .Call(C_rpst_network_integration_outputs, ptr, steps, junctions)
  lines <- data.frame(line_id = seq_along(out[[1L]]), integration = out[[1L]],
             node_count = out[[2L]], total_depth = out[[3L]])
  names(lines) <- c("line_id", .pst_nm_names(.pst_nm_network_integration(steps)))
  junction_name <- .pst_nm_names(.pst_nm_junction(steps))
  if (!junctions) return(lines)
  if (junction_output == "sf")
    return(list(lines = lines,
                junctions = .pst_sf_point_output(
                  out[[4L]], attr(graph, "crs", exact = TRUE),
                  structure(data.frame(junction_id = seq_along(out[[5L]]), integration = out[[5L]]),
                              names = c("junction_id", junction_name)))))
  list(lines = lines,
       junctions = structure(data.frame(junction_id = seq_along(out[[5L]]),
                              x = out[[4L]][, 1L], y = out[[4L]][, 2L],
                              integration = out[[5L]]), names = c("junction_id", "x", "y", junction_name)))
}
