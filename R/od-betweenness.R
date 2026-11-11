#' Origin-Destination Betweenness
#'
#' Counts how often each line lies on the routes from supplied origins to the destination points stored in the
#' graph, weighted by origin and destination weights. Use it to estimate the load on a network from known origins
#' (for example homes) to known destinations (for example shops).
#'
#' @details
#' Destinations are the points stored in the axial graph, including each generated polygon sample. PST assigns every
#' origin to its closest line, chooses the routes and divides each origin's weight across the reached destinations with
#' a positive weight. `destination_mode = "closest"` uses the first destination PST reaches; no other tie ordering and
#' no equal-path splitting is imposed.
#'
#' The primary cost is `"walking"` or `"angular"`. Straight, walking, steps and angular limits are checked
#' independently. In angular mode the final leg to the destination is not charged to the walking depth, so a walking
#' radius can give different results from walking-primary mode. An axmeter limit is rejected, because PST ignores it.
#' Destination weights of zero or below are excluded, and non-positive origin weights make no positive contribution.
#' Written zeros, `Inf` and `NaN` are returned unchanged.
#'
#' One [analysis_radius()] field may be a vector: PST runs once per radius and the result holds each radius' `od_...` column, named as a single call would name it. Every radius is validated (an axmeter limit is rejected) before the first run, and a single radius gives the unchanged single-result schema. `output_file` and `spatial_output_file` write the same table; native storage keeps the columns of all radii.
#'
#' PST runs this analysis on a single worker thread regardless of any thread cap. `sf` inputs need XY geometry and a CRS
#' compatible with the graph's (known versus unknown included); a known geographic CRS is rejected and nothing is
#' reprojected.
#'
#' @param graph An axial graph created by [axial_graph()].
#' @param origins Numeric matrix with zero or more rows and exactly two columns (`x`, `y`), or an XY POINT `sf`/`sfc`
#'   object (zero features allowed). Origin order is preserved.
#' @param radius Distance limits created by [analysis_radius()].
#' @param distance `"walking"` (default) or `"angular"`.
#' @section Naming custom weights:
#' Custom weights are named in the result columns (`..._wo<name>_wd<name>`; the two vectors are named independently) after
#' the R object or literal data-frame column you pass (`origin_weights = population`, `destination_weights = data$jobs`).
#' Anonymous vectors and calculations are an error; assign them to a named object first. See [result_column_names] for the
#' naming rules.
#' @param destination_mode `"all"` (default) or `"closest"`.
#' @param origin_weights `NULL` for unit weights, or one finite value per origin. Zero and negative values are
#'   passed unchanged.
#' @param destination_weights `NULL` for unit weights, or one finite value per point stored in the graph (not per
#'   polygon or point group). Zero and negative values are excluded by PST.
#' @param output_file,overwrite,spatial_output_file Write the results to a file instead of returning them; see
#'   [pst_result_file].
#' @return A data frame in line order with one-based `line_id` and `od_<d>_<radius>` (for example `od_w_rw800`; see [result_column_names]) (double, widened from single
#'   precision). Empty origin or destination sets give PST's written zero scores. With `output_file` or
#'   `spatial_output_file` the results are written to a file and an invisible [pst_result_file] descriptor is returned.
#' @seealso [network_betweenness()], [attraction_reach()], [axial_graph()]
#' @export
#' @examples
#' g <- axial_graph(cbind(0:2, 0, 1:3, 0), points = rbind(c(1.5, 0.5), c(3.5, 0)))
#' od_betweenness(g, rbind(c(-0.5, 0)))
#' od_betweenness(g, rbind(c(-0.5, 0)), destination_mode = "closest")
od_betweenness <- function(graph, origins, radius = analysis_radius(),
    distance = "walking", destination_mode = "all", origin_weights = NULL,
    destination_weights = NULL, output_file = NULL, overwrite = FALSE,
    spatial_output_file = NULL) {
  origin_expr <- substitute(origin_weights)
  destination_expr <- substitute(destination_weights)
  ptr <- .pst_analysis_graph(graph)
  .pst_spatial_request(output_file, spatial_output_file)
  plan <- .pst_radius_plan(radius, FALSE)   # a single radius is validated exactly as before; several are all checked here
  if (!is.null(radius[["axmeter"]]))
    stop("An axmeter radius is not supported by od_betweenness(): the pinned PST OD Betweenness algorithm ignores it, so the axmeter restriction would have no effect. Use straight, walking, steps or angular limits.", call. = FALSE)
  distance <- .pst_mode(distance, c("walking", "angular"), "distance")
  destination_mode <- .pst_mode(destination_mode, c("all", "closest"), "destination_mode")
  .pst_sf_analysis_crs(graph, origins)
  origins <- .pst_sf_points(origins, "origins")
  overwrite <- .pst_flag(overwrite, "overwrite")
  origin_weight <- .pst_nm_user_weight(!is.null(origin_weights), origin_expr, "origin_weights", "wo")
  destination_weight <- .pst_nm_user_weight(!is.null(destination_weights), destination_expr, "destination_weights", "wd")
  if (!.pst_is_scalar_call(plan, "none"))
    return(.pst_od_betweenness_multi(graph, ptr, plan, origins, distance, destination_mode, origin_weights, destination_weights,
                                     origin_weight, destination_weight, output_file, overwrite, spatial_output_file))
  cols <- .pst_nm_od_betweenness(radius, distance, destination_mode, origin_weight, destination_weight)
  result_label <- .pst_nm_names(cols)[[1L]]   # generated names are validated before any native work
  .pst_progress_scope(result_label)
  if (!is.null(output_file) || !is.null(spatial_output_file))
    return(.pst_axial_result_file(
      output_file, overwrite, "od_betweenness",
      list(radius = .pst_radius_parameters(radius), distance = distance, destination_mode = destination_mode,
           origins = NROW(origins), origin_weights = .pst_count_or_null(origin_weights),
           origin_weight_name = origin_weight$name,
           destination_weights = .pst_count_or_null(destination_weights),
           destination_weight_name = destination_weight$name),
      graph, ptr, c("line_id", .pst_nm_names(cols)),
      "native line order (source feature order); no external feature identifiers",
      function(stream, columns, metadata_names, metadata_values, batch_rows) .Call(C_rpst_od_betweenness_stream, ptr, origins, radius, distance,
        destination_mode, origin_weights, destination_weights, stream, columns, metadata_names, metadata_values, batch_rows),
      spatial_output_file = spatial_output_file, cols = cols))
  out <- .Call(C_rpst_od_betweenness, ptr, origins, radius, distance,
               destination_mode, origin_weights, destination_weights)
  structure(data.frame(line_id = seq_along(out), od_betweenness = out), names = c("line_id", .pst_nm_names(cols)))
}
