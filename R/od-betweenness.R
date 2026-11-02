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
#' Custom weights are named in the result columns (`..._wo<name>_wd<name>`; the two vectors are named independently) after the R expression you
#' supply, so no extra argument is needed: an object name (`origin_weights = population`) or a literal data-frame column (`destination_weights = data$jobs`
#' or `destination_weights = data[["jobs"]]`). An anonymous vector (`c(1, 2, 3)`) or a calculation (`data$population / 1000`) has
#' no name and is an error raised before any computation: assign it to a named object first. The name is lower-cased, every
#' run of characters outside `a-z`, `0-9` and `_` becomes one `_`, and leading and trailing underscores are dropped
#' (`Jobs-2021` gives `jobs_2021`); a name with no letter or digit left is an error. The original name is kept in the result
#' metadata. Names are read from the call, never from values or element names; weights forwarded through a wrapper function
#' are named by the wrapper's variable, and `do.call()` with values cannot be named (pass named objects instead). The name
#' is a label only: it does not check that the same name always means the same values.
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
  .pst_validate_radius(radius)
  if (!is.null(radius[["axmeter"]]))
    stop("An axmeter radius is not supported by od_betweenness(): the pinned PST OD Betweenness algorithm ignores it, so the axmeter restriction would have no effect. Use straight, walking, steps or angular limits.", call. = FALSE)
  distance <- .pst_mode(distance, c("walking", "angular"), "distance")
  destination_mode <- .pst_mode(destination_mode, c("all", "closest"), "destination_mode")
  .pst_sf_analysis_crs(graph, origins)
  origins <- .pst_sf_points(origins, "origins")
  overwrite <- .pst_flag(overwrite, "overwrite")
  origin_weight <- .pst_nm_user_weight(!is.null(origin_weights), origin_expr, "origin_weights", "wo")
  destination_weight <- .pst_nm_user_weight(!is.null(destination_weights), destination_expr, "destination_weights", "wd")
  cols <- .pst_nm_od_betweenness(radius, distance, destination_mode, origin_weight, destination_weight)
  .pst_nm_names(cols)   # generated names are validated before any native work
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
