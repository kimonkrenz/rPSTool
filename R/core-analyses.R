#' Network Reach of an axial graph
#'
#' Counts, for every line (or for supplied points), how many lines can be reached within a radius, and
#' reports the total length and the area they cover. Use it to measure how much of the network lies within a
#' given walking distance, number of direction changes or straight-line distance.
#'
#' @details
#' **What is reported.** For a line origin, `reached_count` includes the origin line and `reached_length` is
#' the full length of every reached line. `reached_area` is the area of the convex hull of the reached line
#' endpoints, except when only a straight radius is set, where PST returns pi times the radius squared.
#' Lengths and areas are in the units of the input coordinates; no rescaling takes place.
#'
#' **Point origins.** With `origins`, results are calculated for the supplied points instead of the lines. With a
#' straight-only radius a line counts as reached when its midpoint lies strictly inside the radius, whereas for line origins the
#' boundary is inclusive. For every other radius PST finds the closest line to the point and traverses
#' the network from there, and the point itself is included in the area hull. Points are not retained.
#'
#' **Coordinate reference systems.** `sf` points need XY geometry and a CRS compatible with the graph's
#' (known versus unknown included). A known geographic CRS is rejected; transform it explicitly. A matrix
#' graph has no CRS to compare, so the numerical frame is your responsibility. Nothing is reprojected or
#' converted.
#'
#' @section Limitations:
#' Combining a walking, angular or axmeter limit with another independently compared limit (for
#' example `walking` with `axmeter`) and no `steps` limit can make PST's search very slow or exhaust memory on dense
#' networks. Results are not affected. Adding a `steps` limit avoids the problem.
#'
#' @param graph An axial graph created by [axial_graph()].
#' @param radius Distance limits created by [analysis_radius()].
#' @param origins `NULL` (default) to use every line as an origin, or a numeric matrix with at least one
#'   row and exactly two columns (`x`, `y`), or an XY POINT `sf`/`sfc` object whose features are used in
#'   order. Coordinates must be finite and within PST's coordinate range.
#' @param output_file,overwrite,spatial_output_file Write the results to a file instead of returning them;
#'   see [pst_result_file]. `spatial_output_file` is available only with `origins = NULL`.
#' @return A data frame with one row per origin, in line order (or in the order of `origins`):
#'   * `line_id` (or `origin_id` for point origins): one-based identifier,
#'   * `rc_<radius>`: integer number of lines reached,
#'   * `rln_<radius>`: total length reached, and
#'   * `rca_<radius>`: area covered (see Details).
#'
#'   Column names follow [result_column_names]; for example `rc_rw400` for a walking radius of 400.
#'
#'   Lengths and areas are doubles widened from PST's single precision. With `output_file` or
#'   `spatial_output_file` the results are written to a file and an invisible [pst_result_file] descriptor is
#'   returned.
#' @seealso [network_integration()], [network_betweenness()], [analysis_radius()]
#' @export
#' @examples
#' g <- axial_graph(rbind(c(0, 0, 3, 0), c(3, 0, 6, 0)))
#' network_reach(g, analysis_radius(steps = 1))
#' network_reach(g, origins = rbind(c(1, 0), c(5, 1)))
network_reach <- function(graph, radius = analysis_radius(), origins = NULL, output_file = NULL, overwrite = FALSE,
                      spatial_output_file = NULL) {
  ptr <- .pst_analysis_graph(graph)
  .pst_spatial_request(output_file, spatial_output_file, is.null(origins), "network_reach with origins (one result per origin point)")
  .pst_validate_radius(radius)
  .pst_sf_analysis_crs(graph, origins)
  origins <- .pst_sf_points(origins, "origins")
  overwrite <- .pst_flag(overwrite, "overwrite")
  if (!is.null(output_file) || !is.null(spatial_output_file))
    return(.pst_axial_result_file(
      output_file, overwrite, "network_reach",
      list(radius = .pst_radius_parameters(radius), origins = if (is.null(origins)) "lines" else NROW(origins)),
      graph, ptr, c(if (is.null(origins)) "line_id" else "origin_id", .pst_nm_names(.pst_nm_network_reach(radius))),
      if (is.null(origins)) "native line order (source feature order); no external feature identifiers"
      else "supplied origin row order; one-based row positions, no external identifiers",
      function(stream, columns, metadata_names, metadata_values, batch_rows) .Call(C_rpst_reach_points_stream, ptr, radius, origins, stream, columns, metadata_names, metadata_values, batch_rows),
      spatial_output_file = spatial_output_file, cols = .pst_nm_network_reach(radius)))
  out <- .Call(C_rpst_reach_points, ptr, radius, origins)
  result <- data.frame(line_id = seq_along(out[[1L]]), reached_count = out[[1L]],
             reached_length = out[[2L]], reached_area = out[[3L]])
  if (!is.null(origins)) names(result)[1L] <- "origin_id"
  names(result)[-1L] <- .pst_nm_names(.pst_nm_network_reach(radius))
  result
}

#' Segment Betweenness of an axial graph
#'
#' Counts how often each line lies on the shortest routes between other lines, optionally weighting the
#' routes by line or attraction weights. Use it to identify through-movement potential in an axial map.
#'
#' @details
#' **Distance.** Routes are chosen by one of four distances: `"steps"` (default), `"walking"`, `"angular"` or
#' `"axmeter"`. Straight-line distance is not available. Angular depths are in syntax angle units (90 degrees
#' is one unit); other depths use the selected distance.
#'
#' **Weights.** `weights` are passed to PST as single-precision values, including zero and negative values.
#' Without `attraction_points`, supply one weight per line. With attraction points, PST assigns each point to
#' its closest line and accumulates the weights there; supply one weight per point (omitted weights mean unit
#' weights). Weighted scores include PST's endpoint and self contributions, so unit weights need not equal
#' the unweighted scores. `node_count` includes the origin.
#'
#' **Normalisation.** The raw score `betweenness` is always returned. `normalization` adds PST's
#' `"standard"`, `"freeman"` (Freeman betweenness) or `"syntax"` normalisation as the column
#' `normalized`.
#'
#' **Skipped origins.** PST skips origins whose effective line weight is not positive and writes neither their
#' `node_count` nor their `total_depth`. rPSTool reports these as `NA`, with `NA` Freeman or syntax
#' normalised values for those rows. Standard normalisation still uses all genuine raw scores.
#'
#' **Attraction points.** Points may be a matrix or an XY POINT `sf`/`sfc` object (features used in order). Empty, non-finite,
#' multipart, mixed and Z/M geometry is rejected. Attributes are ignored: `weights` is the only source of
#' weights. A known geographic CRS is rejected, and `sf` CRS metadata must match the graph's (known versus
#' unknown included). Nothing is reprojected.
#'
#' **Threads.** PST uses several worker threads. Set the environment variable `RPST_NUM_THREADS` to a
#' positive integer to cap their number. When R's `_R_CHECK_LIMIT_CORES_` is set (to any non-empty value other
#' than `false`), at most two are used. Invalid explicit caps are rejected before any work starts.
#'
#' @param graph An axial graph created by [axial_graph()].
#' @param radius Distance limits created by [analysis_radius()].
#' @param distance `"steps"` (default), `"walking"`, `"angular"` or `"axmeter"`.
#' @param normalization `"none"`, `"standard"`, `"freeman"` or `"syntax"`.
#' @param weights `NULL`, or finite numeric weights that fit single precision (non-zero values must not
#'   underflow to zero). Supply one per line, or one per attraction point when `attraction_points` is given.
#' @param attraction_points `NULL`, or a finite numeric matrix with at least one row and exactly two columns
#'   (`x`, `y`), or an XY POINT `sf`/`sfc` object.
#' @param output_file,overwrite,spatial_output_file Write the results to a file instead of returning them;
#'   see [pst_result_file]. In a result file, the `NA` values described below are stored as nulls.
#' @param weight_name `NULL`, or a short name for `weights` (for example `"population"`) used in the result column
#'   names (`..._wpopulation_...`). Without it, user weights are labelled `wv`. The name is lower-cased and every
#'   other character than letters, digits and `_` becomes `_`; the original is kept in the result metadata. It is a
#'   label only: it does not check that the same name always means the same values.
#' @return A data frame in line order with `line_id`, the raw betweenness (`nb_<d>_<radius>_n`, or `at_...` with
#'   `attraction_points`), integer node count (`nc_...`) and total depth (`td_...`), plus the normalised score
#'   (`..._s`, `..._f` or `..._y`) when requested; see [result_column_names]. The raw score and `"standard"`
#'   normalisation are never `NA`. The node count and total depth are `NA` for origins PST skipped in weighted calls,
#'   and the normalised score is `NA` for those rows with `"freeman"` or `"syntax"`. `NaN` and `Inf` values written by PST are returned
#'   unchanged. With `output_file` or `spatial_output_file` the results are written to a file and an invisible
#'   [pst_result_file] descriptor is returned (`line_id` and `node_count` are stored as int32, the other
#'   columns as float32).
#' @seealso [angular_choice()] for segment graphs, [od_betweenness()], [analysis_radius()]
#' @export
#' @examples
#' g <- axial_graph(cbind(0:4, 0, 1:5, 0))
#' network_betweenness(g, normalization = "freeman")
#' network_betweenness(g, weights = c(1, 0, 2, 3, 1))
#' network_betweenness(g, attraction_points = rbind(c(0.5, 0), c(4.5, 1)))
network_betweenness <- function(graph, radius = analysis_radius(), distance = "steps",
                            normalization = "none", weights = NULL,
                            attraction_points = NULL, output_file = NULL, overwrite = FALSE,
                            spatial_output_file = NULL, weight_name = NULL) {
  ptr <- .pst_analysis_graph(graph)
  .pst_spatial_request(output_file, spatial_output_file)
  .pst_validate_radius(radius)
  distance <- .pst_mode(distance, c("walking", "steps", "angular", "axmeter"), "distance")
  normalization <- .pst_mode(normalization, c("none", "standard", "freeman", "syntax"), "normalization")
  .pst_sf_analysis_crs(graph, attraction_points)
  attraction_points <- .pst_sf_points(attraction_points, "attraction_points")
  overwrite <- .pst_flag(overwrite, "overwrite")
  weight <- .pst_nm_user_weight(!is.null(weights), weight_name, "weight_name")
  cols <- .pst_nm_network_betweenness(radius, distance, normalization, weight, !is.null(attraction_points))
  if (!is.null(output_file) || !is.null(spatial_output_file))
    return(.pst_axial_result_file(
      output_file, overwrite, "network_betweenness",
      list(radius = .pst_radius_parameters(radius), distance = distance, normalization = normalization,
           weights = .pst_count_or_null(weights), weight_name = weight_name,
           attraction_points = if (is.null(attraction_points)) NULL else NROW(attraction_points)),
      graph, ptr, c("line_id", .pst_nm_names(cols)),
      "native line order (source feature order); no external feature identifiers",
      function(stream, columns, metadata_names, metadata_values, batch_rows)
        .Call(C_rpst_betweenness_weighted_stream, ptr, radius, distance, normalization, weights, attraction_points,
              stream, columns, metadata_names, metadata_values, batch_rows),
      spatial_output_file = spatial_output_file, cols = cols))
  out <- .Call(C_rpst_betweenness_weighted, ptr, radius, distance, normalization,
               weights, attraction_points)
  result <- data.frame(line_id = seq_along(out[[1L]]), betweenness = out[[1L]],
                       node_count = out[[2L]], total_depth = out[[3L]])
  if (normalization != "none") result$normalized <- out[[4L]]
  names(result) <- c("line_id", .pst_nm_names(cols))
  result
}

#' Angular Choice of a segment graph
#'
#' Calculates Angular Choice (angular betweenness) for every segment of a segment graph: how often each
#' segment lies on the angularly shortest routes between other segments. Use it to identify the segments that
#' carry through-movement in a street network, optionally within a radius and with different normalisations.
#'
#' @details
#' **Definition.** Routes are the shortest paths in angular cost. Turns smaller than `angle_threshold`
#' degrees count as zero, and turn costs are rounded to `angle_precision` degree units when PST chooses
#' between paths. Reported depths and angular radii use the unrounded, thresholded angles, in syntax angle
#' units (90 degrees is one unit). A negative threshold has no effect and a threshold above 180 zeroes every
#' turn. `node_count` includes the origin. Length weighting (`weigh_by_length = TRUE`) uses PST's own
#' origin and destination contributions. Axmeter radii are rejected, and so are graphs with more than 32
#' endpoint incidences at one coordinate (as for [angular_integration()]).
#'
#' **Normalisation.** The raw choice score is always returned. `normalization` adds PST's `"standard"`,
#' `"turner"` (Angular Choice) or `"syntax"` (normalised angular choice, NACH) normalisation. Syntax normalisation uses the run's total depth:
#' the length-weighted total depth when `weigh_by_length = TRUE` (as the PST for QGIS plugin does), otherwise
#' `total_depth`.
#'
#' **Several radii and normalisations.** One radius field of [analysis_radius()] may hold several values,
#' and `normalization` may hold several names. PST then runs once per radius and each requested
#' normaliser is applied to that run. The result has `segment_id` once, then radius by radius the same columns a
#' single call with that radius would give, named identically (see Value and [result_column_names]). Fixed
#' restrictions apply to every radius and are recorded in the result's metadata (`rpst:*` keys and the
#' `rpst_manifest` attribute). The same table goes to `output_file` or `spatial_output_file`. See
#' <https://github.com/kimonkrenz/rPSTool/blob/main/docs/compatibility/multi-radius.md>.
#'
#' **Threads.** PST uses several worker threads; see [network_betweenness()] for how to cap them.
#'
#' @section Limitations:
#' **Network depth.** Angular Choice may encounter computational limitations in exceptionally deep network
#' configurations, particularly with unrestricted analysis radii. This has only been observed in artificially
#' constructed networks with thousands of consecutively connected segments, not in real-world street networks.
#' Restricting the analysis radius avoids the observed limitation.
#' [angular_integration()] shares part of this behaviour with a larger tolerance. See `KNOWN_LIMITATIONS.md` in the
#' repository.
#'
#' @param graph A segment graph created by [segment_graph()].
#' @param radius Distance limits created by [analysis_radius()]. One field may hold several values (see Details).
#' @param weigh_by_length `TRUE` or `FALSE` (default). Whether reached segments are weighted by length.
#' @param normalization One or more of `"none"` (default), `"standard"`, `"turner"` and `"syntax"`.
#' @param angle_threshold One finite number of degrees (default 0) that fits single precision without
#'   underflow. Turns below it count as zero.
#' @param angle_precision One whole number from 1 through 4294967295: the angular resolution in degrees
#'   used to rank paths (default 1). Zero is rejected.
#' @param output_file,overwrite,spatial_output_file Write the results to a file instead of returning them;
#'   see [pst_result_file].
#' @return With a single radius and normalisation, a data frame in segment order with:
#'   * `segment_id`: one-based identifier,
#'   * `ac_a_<radius>[_wl]_n[...]`: the raw choice score,
#'   * `nc_...` and `td_...`: reached segments (including the origin) and their summed angular depth,
#'   * `tdw_...` (weighted calls only), and
#'   * `ac_..._t`, `ac_..._s` or `ac_..._c`: the Turner, standard or NACH normalisation when requested.
#'
#'   For example `ac_a_rw3000_n`, `nc_a_rw3000` and `td_a_rw3000` for a walking radius of 3000. The names are
#'   described in [result_column_names].
#'
#'   Numeric columns are doubles widened from PST's single precision. For several radii or normalisations the
#'   columns repeat this scheme radius by radius, named exactly as in a single call. With `output_file` or `spatial_output_file` the
#'   results are written to a file and an invisible [pst_result_file] descriptor is returned.
#' @seealso [angular_integration()], [segment_graph()], [analysis_radius()], [network_betweenness()]
#' @references
#' Turner, A. (2007). From axial to road-centre lines: a new representation for space syntax and a new
#' model of route choice for transport network analysis. *Environment and Planning B: Planning and Design*,
#' 34(3), 539-555. \doi{10.1068/b32067}
#'
#' Hillier, B., Yang, T. and Turner, A. (2012). Normalising least angle choice in Depthmap and how it opens up
#' new perspectives on the global and local analysis of city space. *Journal of Space Syntax*, 3(2), 155-193.
#' @export
#' @examples
#' g <- segment_graph(cbind(0:4 * 3, 0, 1:5 * 3, 0))
#' angular_choice(g)
#' angular_choice(g, radius = analysis_radius(steps = c(1, 2)),
#'                normalization = c("standard", "turner"))
angular_choice <- function(graph, radius = analysis_radius(), weigh_by_length = FALSE,
                               normalization = "none", angle_threshold = 0, angle_precision = 1,
                               output_file = NULL, overwrite = FALSE, spatial_output_file = NULL) {
  ptr <- .pst_analysis_graph(graph, TRUE)
  .pst_spatial_request(output_file, spatial_output_file)
  plan <- .pst_radius_plan(radius, TRUE)
  if (!is.logical(weigh_by_length) || length(weigh_by_length) != 1L || is.na(weigh_by_length))
    stop("weigh_by_length must be TRUE or FALSE.", call. = FALSE)
  normalization <- .pst_modes(normalization, c("none", "standard", "turner", "syntax"), "normalization")
  overwrite <- .pst_flag(overwrite, "overwrite")
  if (!.pst_is_scalar_call(plan, normalization))
    return(.pst_angular_choice_multi(graph, ptr, plan, weigh_by_length, normalization, angle_threshold, angle_precision,
                                     output_file, overwrite, spatial_output_file))
  if (!is.null(output_file) || !is.null(spatial_output_file)) {
    cols <- .pst_nm_angular_choice(radius, weigh_by_length, normalization, angle_threshold, angle_precision)
    columns <- c("segment_id", .pst_nm_names(cols))
    rows <- .Call(C_rpst_segment_graph_info, ptr)
    parameters <- list(radius = .pst_radius_parameters(radius), weigh_by_length = weigh_by_length,
                       normalization = normalization, angle_threshold = angle_threshold,
                       angle_precision = angle_precision)
    metadata <- .pst_result_metadata("angular_choice", parameters, "segment", rows, graph, cols = cols)
    return(invisible(.pst_write_result_file(
      output_file, overwrite, columns = columns, expected_rows = rows,
      export = function(stream, batch_rows)
        .Call(C_rpst_angular_choice_stream, ptr, radius, weigh_by_length, normalization, angle_threshold,
              angle_precision, stream, columns, names(metadata), unname(metadata), batch_rows),
      spatial_output_file = spatial_output_file, graph = graph, metadata = metadata)))
  }
  out <- .Call(C_rpst_angular_choice_controls, ptr, radius, weigh_by_length, normalization,
               angle_threshold, angle_precision)
  cols <- .pst_nm_angular_choice(radius, weigh_by_length, normalization, angle_threshold, angle_precision)
  result <- data.frame(segment_id = seq_along(out[[1L]]), choice = out[[1L]],
                       node_count = out[[2L]], total_depth = out[[3L]])
  if (weigh_by_length) result$total_depth_weight <- out[[4L]]
  if (normalization != "none") result$normalized <- out[[5L]]
  names(result) <- c("segment_id", .pst_nm_names(cols))
  result
}
