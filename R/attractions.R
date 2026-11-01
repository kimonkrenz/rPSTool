#' Calculate PST Attraction Reach and Attraction Distance
#'
#' These analyses reuse an axial graph and its retained points or polygon point
#' groups. PST performs all sampling, assignment, traversal, collection and
#' decay. Outputs follow native origin order and own independent R storage.
#' Reach supports straight, walking, steps, angular, axmeter and none distances;
#' none uses native zero cost. Distance supports straight, walking, steps,
#' angular and custom weights. Distance's straight mode requires no radius or
#' a straight-only radius, and rejects point-group origins before computation:
#' pinned PST leaves those group outputs unwritten. Network Distance rejects
#' axmeter radii. No missing-output policy or replacement aggregation is applied.
#'
#' Native quirks are retained: Reach skips nonpositive attraction values and
#' collects each group's native point prefix; finite straight line Reach applies
#' decay at the radius. Distance's network path ignores a straight radius.
#' Finite straight destination indices can identify the last eligible attraction.
#' Polygon indices identify generated samples in straight mode and group network
#' mode, and polygons in non-group network mode. Indices are returned exactly as
#' PST writes them (zero-based, with -1 for unreachable). Native unreachable
#' distances are -1. Written NaN/Inf and other scores are preserved.
#'
#' Calls wait for internal workers and use no R callbacks. Worker caps follow
#' [network_betweenness()]. Graphs remain reusable; finite straight line Reach's shared
#' native scratch query is protected in generated build copies.
#'
#' Optional sf/sfc inputs require XY geometry and compatible CRS metadata with
#' the graph when retained, including known versus unknown CRS. Known
#' geographic CRS is rejected; transform explicitly. Matrix-only graphs have no
#' CRS to compare: the numerical frame remains the caller's responsibility. No
#' reprojection, unit conversion or attribute interpretation occurs; inputs are
#' not retained.
#' @param graph A live axial graph from [axial_graph()].
#' @param attraction_points Integer/double matrix with zero or more rows and two
#'   columns x,y. Native world/local coordinates and distances must fit. For
#'   polygons, NaN/NaN separates rings; NA and unmatched NaN are rejected. Also
#'   accepts sf/sfc XY POINT or POLYGON features. POLYGON rings lose only their
#'   explicit final closure and use NaN/NaN separators; order, winding and holes
#'   are preserved. PST samples all ring boundaries in one group per feature.
#'   Empty POLYGON features represent zero-count groups; empty polygon
#'   collections, multipart, mixed, Z/M and empty POINT features are rejected.
#' @param radius Independent limits from [analysis_radius()].
#' @param origin Exact name: lines, junctions, points, or point_groups. Points and
#'   point groups are those retained by graph construction, not supplied origins.
#' @param distance Exact name of the native distance (default `"steps"`). The accepted values differ between the two
#'   functions. `attraction_reach()`: `"straight"`, `"walking"`, `"steps"`, `"angular"`, `"axmeter"` or `"none"`
#'   (`"none"` uses native zero cost). `attraction_distance()`: `"straight"`, `"walking"`, `"steps"`, `"angular"` or
#'   `"weights"` (custom weights, see `line_weights` and `point_edge_weight`); it has no `"axmeter"` or `"none"`
#'   distance and rejects an axmeter radius. The `"straight"` radius of
#'   `attraction_distance()` is not applied by PST to the network distances it
#'   computes (it is ignored, not rejected). In `attraction_reach()`, a distance
#'   that does not match the radius metrics (the default `"steps"` with a
#'   walking radius) can be extremely slow and memory hungry, since PST then
#'   searches steps and walking together; use `"none"` or the matching distance.
#' @param points_per_polygon NULL for point attractions, or non-negative whole
#'   counts summing to the attraction row count, one per polygon. Native polygons
#'   close automatically; avoid repeating the first vertex. Must be NULL for
#'   sf input: POLYGON counts are derived from geometry.
#' @param polygon_point_interval Positive finite native float spacing, required
#'   with polygons. Sampling count and loop-progress bounds are checked.
#' @param attraction_values Reach only. NULL for native unit values, or finite native float
#'   values per attraction point/polygon. Zero and negative values are preserved
#'   as inputs and skipped by PST.
#' @param decay Reach only. Decay: `"constant"` (default), `"power"`, `"curve"` or `"divide"`.
#' @param decay_constant Finite native float parameter passed unchanged to PST.
#'   `NULL` (default) selects an effective value from `decay`: 0 for `"constant"`
#'   (the long-standing default) and 1 for `"power"`, `"curve"` and `"divide"`,
#'   the default of the original PST for QGIS wizard (`C = 1`). Any explicitly
#'   supplied value, including 0, is passed unchanged and keeps its native
#'   meaning. Power/curve use the selected distance's radius for scaling.
#' @param distribution Reach only. Polygon distribution: `"divide"` (default) or `"copy"`.
#' @param collection Reach only. Point-group collection: `"mean"` (default), `"sum"`, `"min"` or `"max"`.
#' @param line_weights Distance only. NULL for other distances; otherwise one non-negative finite
#'   native float per graph line; used with distance = weights.
#' @param point_edge_weight Distance only. Non-negative finite native float cost per coordinate
#'   unit on point edges, used by custom weighted Distance (default zero).
#' @param destination_indices Distance only. TRUE to append raw native destination_index,
#'   FALSE to omit indices and use PST's distance-only path.
#' @param output_file `NULL` (default) returns the data frame. A path writes the same table directly to one
#'   Parquet file from PST's native result arrays and returns an invisible `pst_result_file` descriptor, without
#'   building R result vectors. Requires the optional package `arrow (>= 25.0.0)` (platform notes, including Windows, are in [pst_result_file]; validation of the final release candidate on Windows is still outstanding). Columns, order and
#'   values are those of the data frame (ids and counts int32, results float32 as PST computed them; no missing
#'   values are introduced). See <https://github.com/kimonkrenz/rPSTool/blob/main/docs/spatial-io/result-files.md>.
#' @param overwrite `TRUE` or `FALSE` (default). With `output_file` or `spatial_output_file`, whether an existing file may be replaced. Replacement is a single rename and the old file is untouched if anything fails; see [pst_result_file] for the platform differences, notably on Windows.
#' @param spatial_output_file `NULL` (default) or one file path. When given, the analysis runs once and a NEW spatial dataset
#'   is written: the original geometry and attributes of the file the graph was built from, plus this analysis' result
#'   columns, matched to the source features by position (no spatial join). The output format equals the source format
#'   (GeoParquet or FlatGeobuf) and the CRS and geometry are unchanged; a result column named like a source column
#'   replaces it, other result columns are appended. The destination must end in `.fgb` (FlatGeobuf source) or `.parquet` (GeoParquet source), in any letter case. Mutually exclusive with `output_file`; needs a graph built from a
#'   file path; `overwrite` applies to this file only, never to the source. The source file must not be modified or reordered after the graph is built. Returns an invisible [pst_result_file] descriptor. Only with `origin = "lines"` (one result per network line). See <https://github.com/kimonkrenz/rPSTool/blob/main/docs/spatial-io/spatial-output.md>.
#' @return Data frame with `origin_id` (one-based) and `attraction_reach` or
#'   `attraction_distance` (native floats widened to doubles). `attraction_distance()` also includes
#'   integer `destination_index` unless `destination_indices = FALSE`, in the native index convention above
#'   (zero-based, `-1` for unreachable). With `output_file` or `spatial_output_file`, the result is written to a file instead and an invisible `pst_result_file` descriptor (`path`, `rows`, `columns`, `format`) is returned; see [pst_result_file].
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
    output_file = NULL, overwrite = FALSE, spatial_output_file = NULL) {
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
  if (!is.null(output_file) || !is.null(spatial_output_file))
    return(.pst_axial_result_file(
      output_file, overwrite, "attraction_reach",
      c(.pst_attraction_parameters(radius, origin, distance, attraction_points, points_per_polygon,
                                   polygon_point_interval),
        list(attraction_values = .pst_count_or_null(attraction_values), decay = decay,
             decay_constant = decay_constant, distribution = distribution, collection = collection)),
      graph, ptr, c("origin_id", "attraction_reach"), .pst_attraction_order(origin),
      function(stream, columns, metadata_names, metadata_values, batch_rows) .Call(C_rpst_attraction_reach_stream, ptr, radius, origin, distance,
        attraction_points, points_per_polygon, polygon_point_interval, attraction_values,
        decay, decay_constant, distribution, collection, stream, columns, metadata_names, metadata_values, batch_rows),
      spatial_output_file = spatial_output_file))
  out <- .Call(C_rpst_attraction_reach, ptr, radius, origin, distance,
    attraction_points, points_per_polygon, polygon_point_interval, attraction_values,
    decay, decay_constant, distribution, collection)
  data.frame(origin_id = seq_along(out), attraction_reach = out)
}

#' @rdname attraction_reach
#' @export
attraction_distance <- function(graph, attraction_points, radius = analysis_radius(),
    origin = "lines", distance = "steps", points_per_polygon = NULL,
    polygon_point_interval = NULL, line_weights = NULL, point_edge_weight = 0,
    destination_indices = TRUE, output_file = NULL, overwrite = FALSE, spatial_output_file = NULL) {
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
  if (!is.null(output_file) || !is.null(spatial_output_file))
    return(.pst_axial_result_file(
      output_file, overwrite, "attraction_distance",
      c(.pst_attraction_parameters(radius, origin, distance, attraction_points, points_per_polygon,
                                   polygon_point_interval),
        list(line_weights = .pst_count_or_null(line_weights), point_edge_weight = point_edge_weight,
             destination_indices = destination_indices)),
      graph, ptr, c("origin_id", "attraction_distance", if (isTRUE(destination_indices)) "destination_index"),
      .pst_attraction_order(origin),
      function(stream, columns, metadata_names, metadata_values, batch_rows) .Call(C_rpst_attraction_distance_stream, ptr, radius, origin, distance,
        attraction_points, points_per_polygon, polygon_point_interval, line_weights,
        point_edge_weight, destination_indices, stream, columns, metadata_names, metadata_values, batch_rows),
      spatial_output_file = spatial_output_file))
  out <- .Call(C_rpst_attraction_distance, ptr, radius, origin, distance,
    attraction_points, points_per_polygon, polygon_point_interval, line_weights,
    point_edge_weight, destination_indices)
  result <- data.frame(origin_id = seq_along(out[[1L]]), attraction_distance = out[[1L]])
  if (destination_indices) result$destination_index <- out[[2L]]
  result
}

# Metadata helpers of the attraction file routes. Inputs are described by size only, never copied into the file.
.pst_attraction_parameters <- function(radius, origin, distance, points, groups, interval)
  list(radius = .pst_radius_parameters(radius), origin = origin, distance = distance,
       attraction_points = NROW(points), points_per_polygon = .pst_count_or_null(groups),
       polygon_point_interval = interval)
.pst_attraction_order <- function(origin)
  paste0("native ", sub("s$", "", sub("_", " ", origin)), " order of the graph; one-based positions, no external identifiers")
