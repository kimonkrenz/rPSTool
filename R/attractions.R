#' Attraction Reach and Attraction Distance
#'
#' `attraction_reach()` measures how much attraction (for example shops or stations) can be reached from each
#' origin within a radius, with optional decay. `attraction_distance()` measures the distance from each origin to
#' the nearest attraction. Both use the attraction points or polygons stored in an axial graph.
#'
#' @details
#' **Origins and attractions.** Origins are lines, junctions, or the graph's retained points or point groups
#' (`origin`). Attractions are the points or polygon point groups supplied to [axial_graph()]; polygons are
#' sampled by PST. Results follow PST's origin order.
#'
#' **Attraction Reach** accepts `"straight"`, `"walking"`, `"steps"`, `"angular"`, `"axmeter"` and `"none"`
#' distances (`"none"` uses zero cost). Non-positive attraction values are skipped. Each point group collects its
#' native point prefix, and a finite straight-radius line reach applies decay at the radius.
#'
#' **Attraction Distance** accepts `"straight"`, `"walking"`, `"steps"`, `"angular"` and `"weights"` (custom
#' weights; see `line_weights` and `point_edge_weight`). Axmeter radii are rejected. The `"straight"` distance
#' requires no radius or a straight-only radius and rejects point-group origins, because PST leaves those outputs
#' unwritten. A straight radius is ignored (not rejected) for network distances, which PST does not limit by
#' straight distance.
#'
#' **Destination indices.** `attraction_distance()` can return the index of the nearest attraction, exactly as PST
#' writes it: zero-based, with `-1` for unreachable origins. Unreachable distances are also `-1`. For finite
#' straight distances the index identifies the last eligible attraction. Polygon indices identify generated samples
#' in straight mode and group network mode, and polygons in non-group network mode. Written `NaN`, `Inf` and other
#' scores are returned unchanged; no missing-value policy is applied.
#'
#' **Decay.** `decay_constant = NULL` selects 0 for `"constant"` decay and 1 for `"power"`, `"curve"` and
#' `"divide"` (the default of the PST for QGIS wizard). Any value you supply, including 0, is passed to PST
#' unchanged. Power and curve decay scale by the selected distance's radius. A decay that does not match the radius
#' metric yields no decay.
#'
#' **Coordinate reference systems.** `sf` inputs need XY geometry and a CRS compatible with the graph's (known versus
#' unknown included). A known geographic CRS is rejected. Nothing is reprojected or converted.
#'
#' **Threads.** PST uses several worker threads; see [network_betweenness()] for how to cap them.
#'
#' @section Limitations:
#' In `attraction_reach()` a distance that does not match the radius metrics, such as the default `"steps"` with a
#' walking radius, makes PST search steps and walking together, which can be extremely slow and memory-hungry on dense
#' networks. Results are not affected. Use `distance = "none"` or the matching distance, or add a `steps` radius.
#'
#' @param graph An axial graph created by [axial_graph()].
#' @param attraction_points Numeric matrix with zero or more rows and two columns (`x`, `y`), or an XY POINT or
#'   POLYGON `sf`/`sfc` object. For polygons in a matrix, `NaN`/`NaN` rows separate rings, and `NA` and unmatched `NaN`
#'   are rejected. Polygon rings lose only their explicit closing vertex; order, winding and holes are preserved,
#'   and each feature becomes one group (an empty polygon is a zero-count group). Empty collections, multipart, mixed,
#'   Z/M and empty POINT features are rejected.
#' @param radius Distance limits created by [analysis_radius()].
#' @param weight_name Required whenever `attraction_values` (`attraction_reach()`) or `line_weights`
#'   (`attraction_distance()`) is supplied, and an error otherwise: a descriptive name for the weights (for example
#'   `"population"`) used in the result column names (`..._wpopulation`). It is lower-cased, spaces become `_`, and only
#'   the letters a-z, digits and `_` are allowed; anything else is an error. The original is kept in the result metadata.
#'   It is a label only: it does not check that the same name always means the same values.
#' @param origin `"lines"`, `"junctions"`, `"points"` or `"point_groups"`. Points and point groups are those retained
#'   when the graph was built, not newly supplied origins.
#' @param distance The distance used, default `"steps"`. For `attraction_reach()`: `"straight"`, `"walking"`, `"steps"`,
#'   `"angular"`, `"axmeter"` or `"none"`. For `attraction_distance()`: `"straight"`, `"walking"`, `"steps"`,
#'   `"angular"` or `"weights"`.
#' @param points_per_polygon `NULL` for point attractions, or non-negative whole numbers summing to the number of
#'   attraction rows, one per polygon. Must be `NULL` for `sf` input, where polygons are derived from the geometry.
#' @param polygon_point_interval Positive, finite sampling interval in coordinate units. Required with polygons.
#' @param attraction_values `attraction_reach()` only. `NULL` for unit values, or one finite value per attraction
#'   point or polygon. Zero and negative values are skipped by PST.
#' @param decay `attraction_reach()` only. `"constant"` (default), `"power"`, `"curve"` or `"divide"`.
#' @param decay_constant A finite number passed to PST, or `NULL` for the default described in Details.
#' @param distribution `attraction_reach()` only. How polygon values are distributed: `"divide"` (default) or `"copy"`.
#' @param collection `attraction_reach()` only. How point-group values are collected: `"mean"` (default), `"sum"`,
#'   `"min"` or `"max"`.
#' @param line_weights `attraction_distance()` only. `NULL`, or for `distance = "weights"` one non-negative finite
#'   weight per graph line.
#' @param point_edge_weight `attraction_distance()` only. Non-negative finite cost per coordinate unit on point
#'   edges for custom weighted distance (default 0).
#' @param destination_indices `attraction_distance()` only. `TRUE` to also return the destination index, `FALSE` to
#'   omit it.
#' @param output_file,overwrite,spatial_output_file Write the results to a file instead of returning them; see
#'   [pst_result_file]. `spatial_output_file` is available only with `origin = "lines"`.
#' @return A data frame with one-based `origin_id` and `ar_...` (attraction reach) or `ad_...` (attraction distance)
#'   (doubles widened from PST's single precision), named as described in [result_column_names] (for example
#'   `ar_w_rw800`). `attraction_distance()` also returns the integer destination index `di_...` unless
#'   `destination_indices = FALSE`. With `output_file` or `spatial_output_file` the results are written to a file and an
#'   invisible [pst_result_file] descriptor is returned.
#' @seealso [axial_graph()], [network_reach()], [analysis_radius()]
#' @export
#' @examples
#' g <- axial_graph(rbind(c(0, 0, 3, 0), c(3, 0, 6, 0)))
#' a <- rbind(c(1, 1), c(5, 1))
#' attraction_reach(g, a, radius = analysis_radius(steps = 1))
#' attraction_distance(g, a, distance = "walking")
attraction_reach <- function(graph, attraction_points, radius = analysis_radius(),
    origin = "lines", distance = "steps", points_per_polygon = NULL,
    polygon_point_interval = NULL, attraction_values = NULL, decay = "constant",
    decay_constant = NULL, distribution = "divide", collection = "mean",
    output_file = NULL, overwrite = FALSE, spatial_output_file = NULL, weight_name = NULL) {
  ptr <- .pst_analysis_graph(graph)
  .pst_validate_radius(radius)
  origin <- .pst_mode(origin, c("lines", "junctions", "points", "point_groups"), "origin")
  .pst_spatial_request(output_file, spatial_output_file, origin == "lines", paste0("attraction_reach with origin = \"", origin, "\""))
  distance <- .pst_mode(distance, c("straight", "walking", "steps", "angular", "axmeter", "none"), "distance")
  decay <- .pst_mode(decay, c("constant", "power", "curve", "divide"), "decay")
  if (is.null(decay_constant)) decay_constant <- if (identical(decay, "constant")) 0 else 1
  distribution <- .pst_mode(distribution, c("copy", "divide"), "distribution")
  collection <- .pst_mode(collection, c("mean", "sum", "min", "max"), "collection")
  .pst_sf_analysis_crs(graph, attraction_points)
  converted <- .pst_sf_graph_points(attraction_points, points_per_polygon, "attraction_points")
  attraction_points <- converted$points
  points_per_polygon <- converted$counts
  overwrite <- .pst_flag(overwrite, "overwrite")
  weight <- .pst_nm_user_weight(!is.null(attraction_values), weight_name, "weight_name", "w", "attraction_values")
  cols <- .pst_nm_attraction_reach(radius, origin, distance, weight, decay, decay_constant, distribution, collection,
                                   polygon_point_interval)
  .pst_nm_names(cols)   # generated names are validated before any native work
  if (!is.null(output_file) || !is.null(spatial_output_file))
    return(.pst_axial_result_file(
      output_file, overwrite, "attraction_reach",
      c(.pst_attraction_parameters(radius, origin, distance, attraction_points, points_per_polygon,
                                   polygon_point_interval),
        list(attraction_values = .pst_count_or_null(attraction_values), weight_name = weight_name, decay = decay,
             decay_constant = decay_constant, distribution = distribution, collection = collection)),
      graph, ptr, c("origin_id", .pst_nm_names(cols)), .pst_attraction_order(origin),
      function(stream, columns, metadata_names, metadata_values, batch_rows) .Call(C_rpst_attraction_reach_stream, ptr, radius, origin, distance,
        attraction_points, points_per_polygon, polygon_point_interval, attraction_values,
        decay, decay_constant, distribution, collection, stream, columns, metadata_names, metadata_values, batch_rows),
      spatial_output_file = spatial_output_file, cols = cols))
  out <- .Call(C_rpst_attraction_reach, ptr, radius, origin, distance,
    attraction_points, points_per_polygon, polygon_point_interval, attraction_values,
    decay, decay_constant, distribution, collection)
  structure(data.frame(origin_id = seq_along(out), attraction_reach = out), names = c("origin_id", .pst_nm_names(cols)))
}

#' @rdname attraction_reach
#' @export
attraction_distance <- function(graph, attraction_points, radius = analysis_radius(),
    origin = "lines", distance = "steps", points_per_polygon = NULL,
    polygon_point_interval = NULL, line_weights = NULL, point_edge_weight = 0,
    destination_indices = TRUE, output_file = NULL, overwrite = FALSE, spatial_output_file = NULL,
    weight_name = NULL) {
  ptr <- .pst_analysis_graph(graph)
  .pst_validate_radius(radius)
  origin <- .pst_mode(origin, c("lines", "junctions", "points", "point_groups"), "origin")
  .pst_spatial_request(output_file, spatial_output_file, origin == "lines", paste0("attraction_distance with origin = \"", origin, "\""))
  distance <- .pst_mode(distance, c("straight", "walking", "steps", "angular", "weights"), "distance")
  if (origin == "point_groups" && distance == "straight" &&
      all(vapply(radius[c("walking", "steps", "angular", "axmeter")], is.null, logical(1))))
    stop("Pinned PST leaves straight-only Attraction Distance point-group outputs unwritten; this combination is unsupported.", call. = FALSE)
  .pst_sf_analysis_crs(graph, attraction_points)
  converted <- .pst_sf_graph_points(attraction_points, points_per_polygon, "attraction_points")
  attraction_points <- converted$points
  points_per_polygon <- converted$counts
  overwrite <- .pst_flag(overwrite, "overwrite")
  weight <- .pst_nm_user_weight(!is.null(line_weights), weight_name, "weight_name", "w", "line_weights")
  cols <- .pst_nm_attraction_distance(radius, origin, distance, weight, point_edge_weight, polygon_point_interval,
                                      isTRUE(destination_indices))
  .pst_nm_names(cols)   # generated names are validated before any native work
  if (!is.null(output_file) || !is.null(spatial_output_file))
    return(.pst_axial_result_file(
      output_file, overwrite, "attraction_distance",
      c(.pst_attraction_parameters(radius, origin, distance, attraction_points, points_per_polygon,
                                   polygon_point_interval),
        list(line_weights = .pst_count_or_null(line_weights), weight_name = weight_name, point_edge_weight = point_edge_weight,
             destination_indices = destination_indices)),
      graph, ptr, c("origin_id", .pst_nm_names(cols)),
      .pst_attraction_order(origin),
      function(stream, columns, metadata_names, metadata_values, batch_rows) .Call(C_rpst_attraction_distance_stream, ptr, radius, origin, distance,
        attraction_points, points_per_polygon, polygon_point_interval, line_weights,
        point_edge_weight, destination_indices, stream, columns, metadata_names, metadata_values, batch_rows),
      spatial_output_file = spatial_output_file, cols = cols))
  out <- .Call(C_rpst_attraction_distance, ptr, radius, origin, distance,
    attraction_points, points_per_polygon, polygon_point_interval, line_weights,
    point_edge_weight, destination_indices)
  result <- data.frame(origin_id = seq_along(out[[1L]]), attraction_distance = out[[1L]])
  if (destination_indices) result$destination_index <- out[[2L]]
  names(result) <- c("origin_id", .pst_nm_names(cols))
  result
}

# Metadata helpers of the attraction file routes. Inputs are described by size only, never copied into the file.
.pst_attraction_parameters <- function(radius, origin, distance, points, groups, interval)
  list(radius = .pst_radius_parameters(radius), origin = origin, distance = distance,
       attraction_points = NROW(points), points_per_polygon = .pst_count_or_null(groups),
       polygon_point_interval = interval)
.pst_attraction_order <- function(origin)
  paste0("native ", sub("s$", "", sub("_", " ", origin)), " order of the graph; one-based positions, no external identifiers")
