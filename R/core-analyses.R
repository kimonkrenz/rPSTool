#' Calculate PST Reach on an axial graph
#'
#' Calls PSTAReach on every input line or supplied point origin. Line-origin
#' counts include the origin and length
#' includes whole reached lines. Area is the convex hull of reached endpoints,
#' except straight-only radius mode, where PST returns pi times radius squared.
#' Length/area follow coordinate units; no rescaling occurs. Straight-only point
#' Reach includes line midpoints strictly inside the radius; line-origin Reach
#' uses an inclusive boundary. Other point modes use PST's closest-line/BFS
#' traversal and include the point in the area hull. The graph is unchanged.
#' The call is synchronous and creates no workers; point input is not retained.
#'
#' Optional sf/sfc inputs require XY geometry and compatible CRS metadata with
#' the graph when retained, including known versus unknown CRS. Known
#' geographic CRS is rejected; transform explicitly. Matrix-only graphs have no
#' CRS to compare: the numerical frame remains the caller's responsibility. No
#' reprojection, unit conversion or attribute interpretation occurs; inputs are
#' not retained.
#' @param graph A live axial graph created by [axial_graph()].
#' @param radius Independent limits created by [analysis_radius()].
#' @param origins NULL (line origins), or an integer/double matrix with at least
#'   one row and exactly two columns in x, y order. Coordinates must be finite
#'   and fit PST's world/local coordinate and distance representation. Also
#'   accepts sf/sfc XY POINT features in exact feature order; empty collections
#'   remain rejected by native validation.
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
#'   file path; `overwrite` applies to this file only, never to the source. The source file must not be modified or reordered after the graph is built. Returns an invisible [pst_result_file] descriptor. Only with `origins = NULL` (one result per network line). See <https://github.com/kimonkrenz/rPSTool/blob/main/docs/spatial-io/spatial-output.md>.
#' @return Data frame in input line or origin order: line_id or origin_id,
#'   reached_count (integer),
#'   reached_length and reached_area (double, widened from native float). With `output_file` or `spatial_output_file`, the result is written to a file instead and an invisible `pst_result_file` descriptor (`path`, `rows`, `columns`, `format`) is returned; see [pst_result_file].
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
      graph, ptr, c(if (is.null(origins)) "line_id" else "origin_id", "reached_count", "reached_length", "reached_area"),
      if (is.null(origins)) "native line order (source feature order); no external feature identifiers"
      else "supplied origin row order; one-based row positions, no external identifiers",
      function(stream, columns, metadata_names, metadata_values, batch_rows) .Call(C_rpst_reach_points_stream, ptr, radius, origins, stream, columns, metadata_names, metadata_values, batch_rows),
      spatial_output_file = spatial_output_file))
  out <- .Call(C_rpst_reach_points, ptr, radius, origins)
  result <- data.frame(line_id = seq_along(out[[1L]]), reached_count = out[[1L]],
             reached_length = out[[2L]], reached_area = out[[3L]])
  if (!is.null(origins)) names(result)[1L] <- "origin_id"
  result
}

#' Calculate PST Segment Betweenness on an axial graph
#'
#' Calls PSTASegmentBetweenness using its required HPSTAGraph. Supported
#' distances are walking, steps, angular and axmeter. Straight and weights are
#' not supported distance modes. Optional weights are passed to PST as native
#' floats, including zero and negative values. With attraction points, PST
#' assigns each to its closest line and accumulates weights there; omitted
#' attraction weights mean unit weights. Weighted scores include PST's endpoint
#' and self contributions, so unit weights need not equal unweighted scores.
#' Written counts include the origin. Angular depths use syntax angle units (90 degrees
#' is one unit); other depths use the selected native distance.
#'
#' Raw scores are retained. Optional normalization calls PST's exported
#' Standard, Betweenness (Freeman), or BetweennessSyntax routines directly.
#' PST skips origins with nonpositive effective line weight, leaving count and
#' depth unwritten. rPSTool reports these as NA, with NA Freeman/syntax normalization
#' for those rows. Standard normalization still uses all genuine raw scores.
#' Optional sf/sfc attraction points are converted only to the same two-column
#' matrix before the unchanged native call. Empty, nonfinite, multipart, mixed
#' and Z/M geometry is rejected. Attributes are ignored: `weights` remains the
#' only source of weights and must contain one value per supplied point. A
#' known geographic CRS is rejected; sf CRS metadata must match any CRS retained
#' by the graph (known versus unknown included). Matrix points and matrix-only
#' graphs involve no metadata, so the numerical frame remains the user's
#' responsibility. Nothing is reprojected and the sf object is not retained.
#'
#' PST creates workers and waits before returning; workers never call R.
#' RPST_NUM_THREADS sets a positive integer worker cap; otherwise PST uses hardware
#' concurrency. An active _R_CHECK_LIMIT_CORES_ (any non-empty value other than false, case-insensitive,
#' e.g. true/TRUE/warn) limits workers to two even above a larger RPST_NUM_THREADS. Invalid explicit caps fail before workers start.
#'
#' @param graph A live axial graph created by [axial_graph()].
#' @param radius Independent limits created by [analysis_radius()].
#' @param distance Exact name: "steps" (default), "walking", "angular", "axmeter".
#' @param normalization Exact name: "none", "standard", "freeman", "syntax".
#' @param weights NULL, or finite integer/double weights fitting native float
#'   storage (nonzero values must not underflow to zero). Supply exactly one per
#'   graph line without attractions, or one per supplied attraction point.
#' @param attraction_points NULL, or a finite integer/double matrix with at least
#'   one row and exactly two columns in x, y order, fitting PST's world/local
#'   coordinate and distance representation, or an XY POINT sf/sfc whose features
#'   are used in exact order (see below). PST performs closest-line assignment.
#' @param output_file `NULL` (default) returns the data frame. A path writes the same table directly to one Parquet
#'   file from PST's native result arrays and returns an invisible `pst_result_file` descriptor, without building R
#'   result vectors. Requires the optional package `arrow (>= 25.0.0)` (platform notes, including Windows, are in [pst_result_file]; validation of the final release candidate on Windows is still outstanding). Columns, order and values are those
#'   of the data frame (`line_id` and `node_count` int32, the rest float32). The values that are `NA` in the data frame
#'   (diagnostics PST did not write for skipped weighted origins) are Arrow nulls in `node_count`, `total_depth` and,
#'   for `"freeman"`/`"syntax"`, `normalized`; these columns are declared nullable for every call of that kind. The raw
#'   `betweenness` and the `"standard"` normalisation are never null, and a written `NaN` or infinity is an ordinary
#'   value, not a null. See <https://github.com/kimonkrenz/rPSTool/blob/main/docs/spatial-io/result-files.md>.
#' @param overwrite `TRUE` or `FALSE` (default). With `output_file` or `spatial_output_file`, whether an existing file may be replaced. Replacement is a single rename and the old file is untouched if anything fails; see [pst_result_file] for the platform differences, notably on Windows.
#' @param spatial_output_file `NULL` (default) or one file path. When given, the analysis runs once and a NEW spatial dataset
#'   is written: the original geometry and attributes of the file the graph was built from, plus this analysis' result
#'   columns, matched to the source features by position (no spatial join). The output format equals the source format
#'   (GeoParquet or FlatGeobuf) and the CRS and geometry are unchanged; a result column named like a source column
#'   replaces it, other result columns are appended. The destination must end in `.fgb` (FlatGeobuf source) or `.parquet` (GeoParquet source), in any letter case. Mutually exclusive with `output_file`; needs a graph built from a
#'   file path; `overwrite` applies to this file only, never to the source. The source file must not be modified or reordered after the graph is built. Returns an invisible [pst_result_file] descriptor. See <https://github.com/kimonkrenz/rPSTool/blob/main/docs/spatial-io/spatial-output.md>.
#' @return Data frame in input line order: `line_id`, raw `betweenness`, integer
#'   `node_count`, `total_depth`; `normalized` is appended when requested. Raw `betweenness` and
#'   `"standard"` normalization are never `NA`. `node_count` and `total_depth` are `NA` for origins that PST skipped in
#'   weighted calls (nonpositive effective line weight; it writes neither value), and `normalized` is `NA` for those rows when
#'   `normalization` is `"freeman"` or `"syntax"`. Native `NaN`/`Inf` values are returned unchanged. With `output_file` or `spatial_output_file`, the result is written to a file instead and an invisible `pst_result_file` descriptor (`path`, `rows`, `columns`, `format`) is returned; see [pst_result_file].
#' @export
#' @examples
#' g <- axial_graph(cbind(0:4, 0, 1:5, 0))
#' network_betweenness(g, normalization = "freeman")
#' network_betweenness(g, weights = c(1, 0, 2, 3, 1))
#' network_betweenness(g, attraction_points = rbind(c(0.5, 0), c(4.5, 1)))
network_betweenness <- function(graph, radius = analysis_radius(), distance = "steps",
                            normalization = "none", weights = NULL,
                            attraction_points = NULL, output_file = NULL, overwrite = FALSE,
                            spatial_output_file = NULL) {
  ptr <- .pst_analysis_graph(graph)
  .pst_spatial_request(output_file, spatial_output_file)
  .pst_validate_radius(radius)
  distance <- .pst_mode(distance, c("walking", "steps", "angular", "axmeter"), "distance")
  normalization <- .pst_mode(normalization, c("none", "standard", "freeman", "syntax"), "normalization")
  .pst_sf_analysis_crs(graph, attraction_points)
  attraction_points <- .pst_sf_points(attraction_points, "attraction_points")
  overwrite <- .pst_flag(overwrite, "overwrite")
  if (!is.null(output_file) || !is.null(spatial_output_file))
    return(.pst_axial_result_file(
      output_file, overwrite, "network_betweenness",
      list(radius = .pst_radius_parameters(radius), distance = distance, normalization = normalization,
           weights = .pst_count_or_null(weights),
           attraction_points = if (is.null(attraction_points)) NULL else NROW(attraction_points)),
      graph, ptr, c("line_id", "betweenness", "node_count", "total_depth", if (normalization != "none") "normalized"),
      "native line order (source feature order); no external feature identifiers",
      function(stream, columns, metadata_names, metadata_values, batch_rows)
        .Call(C_rpst_betweenness_weighted_stream, ptr, radius, distance, normalization, weights, attraction_points,
              stream, columns, metadata_names, metadata_values, batch_rows),
      spatial_output_file = spatial_output_file))
  out <- .Call(C_rpst_betweenness_weighted, ptr, radius, distance, normalization,
               weights, attraction_points)
  result <- data.frame(line_id = seq_along(out[[1L]]), betweenness = out[[1L]],
                       node_count = out[[2L]], total_depth = out[[3L]])
  if (normalization != "none") result$normalized <- out[[4L]]
  result
}

#' Calculate PST Angular Choice on a segment graph
#'
#' Calls PSTAAngularChoice with upstream defaults: no length weighting,
#' threshold zero and precision one degree. Length weighting uses PST's own
#' origin/destination contributions. Turns strictly below angle_threshold become
#' zero; rounded angle_precision units determine queue costs, while depths and
#' angular limits use unrounded thresholded angles. Negative thresholds have no
#' effect; thresholds above 180 zero all turns. Counts include the
#' origin and depths use syntax angle units (90 degrees is one unit).
#' Axmeter radii are rejected. The shared angular engine rejects graphs with
#' more than 32 endpoint incidences at a coordinate, as does Angular Integration.
#'
#' Optional normalization calls PST's exported Standard, AngularChoice (Turner),
#' or AngularChoiceSyntax (NACH) routines. Syntax normalization reads the run's
#' total depth: with `weigh_by_length = TRUE` the length-weighted total depth
#' (`total_depth_weight`, as the original PST for QGIS plugin passes to the
#' exported routine), otherwise `total_depth`. Raw choice is always retained.
#' The call waits for internal workers; no workers call R. Worker caps follow
#' [network_betweenness()]. Results own independent R storage and graphs are reusable.
#'
#' **Known limitation (inherited from PST): very deep chains of shortest-path steps.** PST collects choice scores with a
#' recursive traversal (`CollectScores`) of the shortest-path steps recorded from each origin, on a worker thread with the
#' operating system's default thread stack, and has no depth bound. The recursion depth is bounded by the longest chain of
#' consecutive shortest-path steps (in PST's discretised angular cost, equal-cost ties included) that is reachable within the
#' radius, not by the number of segments in the network. A very long, nearly straight sequence of short segments analysed with
#' an unrestricted or large radius can exhaust the worker-thread stack and terminate the R process (confirmed for an
#' unrestricted 8,000-segment chain on macOS ARM64; Linux with an 8 MB stack survives tens of thousands of segments; it has only been
#' reproduced on synthetic chains and no realistic network is known to reach such depths). The
#' usable depth depends on the platform, compiler and flags. A `steps` radius bounds the depth by its value; `walking` and
#' `straight` radii bound it by the segments that fit inside them; an `angular` radius does not bound straight runs. Angular
#' Integration shares part of this recursion (`ClearProcessedFlags`) with a larger tolerance. rPSTool does not change PST's
#' traversal; see <https://github.com/kimonkrenz/rPSTool/blob/main/docs/compatibility/angular-controls.md>.
#'
#' **Multi-radius and multi-normalisation.** A call with one radius and one normalisation behaves, and is named,
#' exactly as before. If `radius` varies one field (for example `analysis_radius(walking = c(500, 1000))`) or `normalization`
#' has several entries, PST's analysis runs exactly once per radius and every requested PST normaliser is applied to that run's
#' arrays. The result has `segment_id` once, then, radius by radius: `choice<tag>`, `node_count<tag>`, `total_depth<tag>`,
#' `total_depth_weight<tag>` (weighted only) and `choice_<norm><tag>` for each normalisation other than `"none"`
#' (the raw `choice` is always kept, so `"none"` adds no column). `<tag>` is `_` plus a dimension code (`s` straight, `w`
#' walking, `n` steps, `a` angular) and the radius, written exactly (`.` as `p`): `choice_w500`, `choice_turner_w0p5`;
#' it is empty when no field varies. Fixed restrictions apply to every radius and are recorded in the metadata
#' (`rpst:*`, `rpst_manifest` attribute), which is authoritative. The same result goes to `output_file` or
#' `spatial_output_file` as one table, published once after everything succeeded.
#'
#' @param graph A live graph created by [segment_graph()].
#' @param radius Independent limits created by [analysis_radius()]. One field of `analysis_radius()` may hold several values (a
#'   multi-radius): PST then runs once per radius, in the supplied order, and one combined result is returned or written.
#'   See Details and <https://github.com/kimonkrenz/rPSTool/blob/main/docs/compatibility/multi-radius.md>.
#' @param weigh_by_length TRUE or FALSE (default).
#' @param normalization Exact name: "none", "standard", "turner", "syntax"; or a character vector of distinct names.
#'   With several names (or a multi-radius) the call returns the multi-result schema described in Details.
#' @param angle_threshold One finite native-float number without nonzero underflow;
#'   degrees, default zero.
#' @param angle_precision One whole number from 1 through 4294967295; degrees,
#'   default one. Zero is unsafe for the native queue and is rejected.
#' @param output_file NULL (default) or one file path. When given, the analysis runs once and its result is written
#'   directly to a Parquet file (zstd) without building an R data frame; see [pst_result_file]. Needs the optional
#'   package arrow (>= 25.0.0). The file has the same columns, order and row identity as the data frame, with PST's
#'   native float values stored as float32 (reading them back in R gives the identical doubles).
#' @param overwrite `TRUE` or `FALSE` (default). With `output_file` or `spatial_output_file`, whether an existing file may be replaced. Replacement is a single rename and the old file is untouched if anything fails; see [pst_result_file] for the platform differences, notably on Windows.
#' @param spatial_output_file `NULL` (default) or one file path. When given, the analysis runs once and a NEW spatial dataset
#'   is written: the original geometry and attributes of the file the graph was built from, plus this analysis' result
#'   columns, matched to the source features by position (no spatial join). The output format equals the source format
#'   (GeoParquet or FlatGeobuf) and the CRS and geometry are unchanged; a result column named like a source column
#'   replaces it, other result columns are appended. The destination must end in `.fgb` (FlatGeobuf source) or `.parquet` (GeoParquet source), in any letter case. Mutually exclusive with `output_file`; needs a graph built from a
#'   file path; `overwrite` applies to this file only, never to the source. The source file must not be modified or reordered after the graph is built. Returns an invisible [pst_result_file] descriptor. See <https://github.com/kimonkrenz/rPSTool/blob/main/docs/spatial-io/spatial-output.md>.
#' @return With output_file = NULL, a data frame in input segment order: segment_id, raw choice, integer
#'   node_count, total_depth; total_depth_weight in weighted mode, and normalized
#'   when requested. Numeric outputs widen PST float values to double. With several normalisations or a multi-radius
#'   the columns follow the multi-result schema described in Details. With `output_file` or `spatial_output_file`, the result is written to a file instead and an invisible `pst_result_file` descriptor (`path`, `rows`, `columns`, `format`) is returned; see [pst_result_file].
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
    columns <- .pst_angular_choice_names(weigh_by_length, normalization)
    rows <- .Call(C_rpst_segment_graph_info, ptr)
    parameters <- list(radius = .pst_radius_parameters(radius), weigh_by_length = weigh_by_length,
                       normalization = normalization, angle_threshold = angle_threshold,
                       angle_precision = angle_precision)
    metadata <- .pst_result_metadata("angular_choice", parameters, "segment", rows, graph)
    return(invisible(.pst_write_result_file(
      output_file, overwrite, columns = columns, expected_rows = rows,
      export = function(stream, batch_rows)
        .Call(C_rpst_angular_choice_stream, ptr, radius, weigh_by_length, normalization, angle_threshold,
              angle_precision, stream, columns, names(metadata), unname(metadata), batch_rows),
      spatial_output_file = spatial_output_file, graph = graph, metadata = metadata)))
  }
  out <- .Call(C_rpst_angular_choice_controls, ptr, radius, weigh_by_length, normalization,
               angle_threshold, angle_precision)
  result <- data.frame(segment_id = seq_along(out[[1L]]), choice = out[[1L]],
                       node_count = out[[2L]], total_depth = out[[3L]])
  if (weigh_by_length) result$total_depth_weight <- out[[4L]]
  if (normalization != "none") result$normalized <- out[[5L]]
  result
}
