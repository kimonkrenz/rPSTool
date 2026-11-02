#' Angular Integration of a segment graph
#'
#' Calculates Angular Integration for every segment of a segment graph: how close each segment is, in angular
#' cost, to all other segments within a radius. Use it for segment-based (angular) integration analysis of
#' street networks, optionally weighted by segment length and with different normalisations.
#'
#' @details
#' **Normalisation.** `normalization` selects PST's `"turner"` (default), `"syntax"` (normalised angular
#' integration, NAIN) or `"hillier"` normalisation; with `weigh_by_length = TRUE` the matching length-weighted
#' form is used. All scores are computed by PST.
#'
#' **Reached segments.** `node_count` includes the origin, whereas `total_weight` excludes it. Unweighted,
#' `total_weight` is the number of other reached segments; weighted, it is the sum of their lengths. Total depth
#' and depth-weight sums are in syntax angle units (90 degrees is one unit). Weighted calls always include
#' `total_weight` and `total_depth_weight`; `weight_outputs = TRUE` adds them to unweighted calls too.
#'
#' **Angle settings.** Turns strictly smaller than `angle_threshold` degrees count as zero (a negative
#' threshold has no effect, and a threshold above 180 zeroes every turn). PST rounds each remaining turn to
#' `angle_precision` degree units when ranking shortest paths, so a coarse precision can change ties.
#' Reported depths and angular limits use the unrounded, thresholded angles. Neither setting changes the
#' geometry or connectivity.
#'
#' **Several radii and normalisations.** One radius field of [analysis_radius()] may hold several values, and
#' `normalization` may hold several names. PST then runs once per radius and every requested normaliser is
#' applied to that run. The result has `segment_id` once, then radius by radius:
#' `integration_<norm><tag>` for each normalisation, `node_count<tag>`, `total_depth<tag>` and, when weighted
#' or `weight_outputs = TRUE`, `total_weight<tag>` and `total_depth_weight<tag>`. `<tag>` is an underscore
#' plus a dimension code (`s` straight, `w` walking, `n` steps, `a` angular) and the radius written exactly
#' with `.` as `p`, and is empty when no field varies. Fixed restrictions are recorded in the result's
#' metadata (`rpst:*` keys and the `rpst_manifest` attribute). See
#' <https://github.com/kimonkrenz/rPSTool/blob/main/docs/compatibility/multi-radius.md>.
#'
#' @section Limitations:
#' The graph must have exact endpoint connectivity with at most 32 endpoint incidences at any coordinate, and
#' axmeter radii are rejected. Angular Integration shares part of the deep recursion that limits
#' [angular_choice()], but with a larger tolerance; see the Limitations section of that page.
#'
#' @param graph A segment graph created by [segment_graph()].
#' @param steps `NULL` (default) or one non-negative whole number no greater than 2147483647: a step limit.
#'   Supply either `steps` or `radius`.
#' @param radius Optional distance limits created by [analysis_radius()]. One field may hold several values
#'   (see Details).
#' @param weigh_by_length `TRUE` or `FALSE` (default). Whether reached segments are weighted by length.
#' @param normalization `"turner"` (default), `"syntax"` or `"hillier"`, or a character vector of distinct names.
#' @param angle_threshold One finite number of degrees (default 0) that fits single precision without
#'   underflow.
#' @param angle_precision One whole number from 1 through 4294967295: the angular resolution in degrees used
#'   to rank paths (default 1). Zero is rejected.
#' @param weight_outputs `TRUE` or `FALSE` (default). Include `total_weight` and `total_depth_weight` even
#'   when unweighted.
#' @param output_file,overwrite,spatial_output_file Write the results to a file instead of returning them;
#'   see [pst_result_file].
#' @return With a single radius and normalisation, a data frame in segment order with:
#'   * `segment_id`: one-based identifier,
#'   * `integration`: the normalised score,
#'   * `node_count`: integer number of segments reached, including the origin,
#'   * `total_depth`: summed angular depth, and
#'   * `total_weight` and `total_depth_weight` in weighted calls or with `weight_outputs = TRUE`.
#'
#'   Numeric columns are doubles widened from PST's single precision. For several radii or normalisations the
#'   columns follow the naming scheme described in Details. With `output_file` or `spatial_output_file` the
#'   results are written to a file and an invisible [pst_result_file] descriptor is returned.
#' @seealso [angular_choice()], [network_integration()] for axial graphs, [segment_graph()], [analysis_radius()]
#' @references
#' Turner, A. (2007). From axial to road-centre lines: a new representation for space syntax and a new
#' model of route choice for transport network analysis. *Environment and Planning B: Planning and Design*,
#' 34(3), 539-555. \doi{10.1068/b32067}
#'
#' Hillier, B., Yang, T. and Turner, A. (2012). Normalising least angle choice in Depthmap and how it opens up
#' new perspectives on the global and local analysis of city space. *Journal of Space Syntax*, 3(2), 155-193.
#' @export
#' @examples
#' g <- segment_graph(rbind(c(0, 0, 3, 0), c(3, 0, 3, 3)))
#' angular_integration(g)
#' angular_integration(g, weigh_by_length = TRUE, normalization = "syntax")
#' angular_integration(g, radius = analysis_radius(steps = c(1, 2)))
angular_integration <- function(graph, steps = NULL, radius = NULL,
                                    weigh_by_length = FALSE, normalization = "turner",
                                    angle_threshold = 0, angle_precision = 1, weight_outputs = FALSE,
                                    output_file = NULL, overwrite = FALSE, spatial_output_file = NULL) {
  ptr <- .pst_analysis_graph(graph, TRUE)
  .pst_spatial_request(output_file, spatial_output_file)
  steps <- .pst_resolve_radius(steps, radius, TRUE, multi = TRUE)
  normalization <- .pst_modes(normalization, c("turner", "syntax", "hillier"), "normalization")
  overwrite <- .pst_flag(overwrite, "overwrite")
  plan <- .pst_radius_plan(if (inherits(steps, "pst_radius")) steps else analysis_radius(steps = steps), TRUE)  # re-validation is cheap and scalar
  if (!.pst_is_scalar_call(plan, normalization))
    return(.pst_angular_integration_multi(graph, ptr, plan, weigh_by_length, normalization, angle_threshold,
                                          angle_precision, weight_outputs, output_file, overwrite, spatial_output_file))
  if (!is.null(output_file) || !is.null(spatial_output_file)) {
    weights <- .pst_flag(weigh_by_length, "weigh_by_length") || .pst_flag(weight_outputs, "weight_outputs")
    columns <- .pst_angular_integration_names(weights)
    rows <- .Call(C_rpst_segment_graph_info, ptr)
    parameters <- list(radius = .pst_radius_parameters(steps), weigh_by_length = weigh_by_length,
                       normalization = normalization, angle_threshold = angle_threshold,
                       angle_precision = angle_precision, weight_outputs = weight_outputs)
    metadata <- .pst_result_metadata("angular_integration", parameters, "segment", rows, graph)
    return(invisible(.pst_write_result_file(
      output_file, overwrite, columns = columns, expected_rows = rows,
      export = function(stream, batch_rows)
        .Call(C_rpst_angular_integration_stream, ptr, steps, weigh_by_length, normalization, angle_threshold,
              angle_precision, weight_outputs, stream, columns, names(metadata), unname(metadata), batch_rows),
      spatial_output_file = spatial_output_file, graph = graph, metadata = metadata)))
  }
  out <- .Call(C_rpst_angular_integration_controls, ptr, steps, weigh_by_length,
               normalization, angle_threshold, angle_precision, weight_outputs)
  result <- data.frame(segment_id = seq_along(out[[1L]]), integration = out[[1L]],
             node_count = out[[2L]], total_depth = out[[3L]])
  if (weigh_by_length || weight_outputs) {
    result$total_weight <- out[[4L]]
    result$total_depth_weight <- out[[5L]]
  }
  result
}
