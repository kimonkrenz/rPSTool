#' Calculate PST Origin-Destination Betweenness
#'
#' Calls PSTAODBetweenness on a live axial graph. Destinations are the graph's
#' retained native points, including individually generated polygon samples.
#' PST assigns supplied origins to their closest lines, chooses routes and
#' distributes each origin's weight across reached positive-weight destinations.
#' The closest mode uses the first destination reached by PST's native queue;
#' no alternative tie ordering or equal-path splitting is imposed.
#'
#' Walking and angular are the supported primary costs. Straight, walking, steps
#' and angular limits retain PST's independent checks. An axmeter limit is
#' rejected with an error before OD Betweenness calculation, because the pinned algorithm
#' ignores it and the axmeter restriction would have no effect. Angular mode does not charge the final destination leg to walking
#' depth, so a walking radius can differ from walking-primary mode. Destination
#' weights <= 0 are excluded. Nonpositive origin weights produce no positive
#' trace contributions. Written native zeros/Inf/NaN are preserved without an NA
#' policy, rescaling or replacement computation.
#'
#' Pinned PST uses one asynchronous worker, even with higher worker caps. rPSTool
#' validates the existing worker-cap environment and preserves that single-worker
#' execution. Calls wait for completion, propagate worker failures and never use
#' R callbacks. The graph is reusable and results own independent R storage.
#'
#' Optional sf/sfc inputs require XY geometry and compatible CRS metadata with
#' the graph when retained, including known versus unknown CRS. Known
#' geographic CRS is rejected; transform explicitly. Matrix-only graphs have no
#' CRS to compare: the numerical frame remains the caller's responsibility. No
#' reprojection, unit conversion or attribute interpretation occurs; inputs are
#' not retained.
#' @param graph A live axial graph created by [axial_graph()].
#' @param origins Integer/double matrix with zero or more rows and exactly two
#'   columns x,y. Coordinates must be finite and fit native world/local and
#'   origin/destination distance bounds. Origin order is preserved. Also accepts
#'   sf/sfc XY POINT features, including zero-feature collections.
#' @param radius Independent limits from [analysis_radius()].
#' @param distance Exact name: walking (default) or angular.
#' @param destination_mode Exact name: all (default) or closest.
#' @param origin_weights NULL for unit weights, or finite native-float values,
#'   one per supplied origin. Zero and negative values are passed unchanged.
#' @param destination_weights NULL for unit weights, or finite native-float
#'   values, one per retained native graph point, not per polygon or point group.
#'   Zero and negative values are passed unchanged and excluded by PST.
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
#'   file path; `overwrite` applies to this file only, never to the source. The source file must not be modified or reordered after the graph is built. Returns an invisible [pst_result_file] descriptor. See <https://github.com/kimonkrenz/rPSTool/blob/main/docs/spatial-io/spatial-output.md>.
#' @return Data frame in input line order with one-based line_id and
#'   od_betweenness, native float scores widened to double. Empty origin or
#'   destination sets yield PST's written zero scores. With `output_file` or `spatial_output_file`, the result is written to a file instead and an invisible `pst_result_file` descriptor (`path`, `rows`, `columns`, `format`) is returned; see [pst_result_file].
#' @export
#' @examples
#' g <- axial_graph(cbind(0:2, 0, 1:3, 0), points = rbind(c(1.5, 0.5), c(3.5, 0)))
#' od_betweenness(g, rbind(c(-0.5, 0)))
#' od_betweenness(g, rbind(c(-0.5, 0)), destination_mode = "closest")
od_betweenness <- function(graph, origins, radius = analysis_radius(),
    distance = "walking", destination_mode = "all", origin_weights = NULL,
    destination_weights = NULL, output_file = NULL, overwrite = FALSE,
    spatial_output_file = NULL) {
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
  if (!is.null(output_file) || !is.null(spatial_output_file))
    return(.pst_axial_result_file(
      output_file, overwrite, "od_betweenness",
      list(radius = .pst_radius_parameters(radius), distance = distance, destination_mode = destination_mode,
           origins = NROW(origins), origin_weights = .pst_count_or_null(origin_weights),
           destination_weights = .pst_count_or_null(destination_weights)),
      graph, ptr, c("line_id", "od_betweenness"),
      "native line order (source feature order); no external feature identifiers",
      function(stream, columns, metadata_names, metadata_values, batch_rows) .Call(C_rpst_od_betweenness_stream, ptr, origins, radius, distance,
        destination_mode, origin_weights, destination_weights, stream, columns, metadata_names, metadata_values, batch_rows),
      spatial_output_file = spatial_output_file))
  out <- .Call(C_rpst_od_betweenness, ptr, origins, radius, distance,
               destination_mode, origin_weights, destination_weights)
  data.frame(line_id = seq_along(out), od_betweenness = out)
}
