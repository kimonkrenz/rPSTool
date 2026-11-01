#' Calculate PST Angular Integration on a segment graph
#'
#' Calls PSTAAngularIntegration and its exported Turner, syntax (NAIN) or Hillier
#' normalizer. Defaults retain the unweighted Turner score and existing columns.
#' Length weighting selects the matching native length-weighted normalizer, using
#' total_weight and total_depth_weight; no R score formula is evaluated.
#'
#' Node counts include the origin; native total_weight excludes it. In unweighted
#' mode total_weight counts other reached segments; in weighted mode it sums their
#' lengths. Total depth and depth-weight sums use syntax angle units (90 degrees is
#' one unit). Weighted results include both weight columns. Set weight_outputs to
#' TRUE to also request them in unweighted mode.
#'
#' Turns strictly below angle_threshold degrees become zero. Negative thresholds
#' have no effect; thresholds above 180 zero every turn. PST rounds each remaining
#' turn to angle_precision degree units for shortest-path queue priorities. Reported
#' depths and angular limits use unrounded thresholded angles. Coarse precision can
#' change path ties. Neither control changes geometry or connectivity.
#'
#' The graph must have exact endpoint connectivity and at most 32 endpoint incidences
#' per coordinate. Axmeter is unsupported. Worker caps follow network_betweenness;
#' workers never call R and failures propagate after workers join. Outputs own
#' independent R storage and the graph remains reusable. Written native NaN/Inf
#' values remain unchanged.
#'
#' **Multi-radius and multi-normalisation.** A call with one radius and one normalisation behaves, and is named, exactly as
#' before. If `radius` varies one field or `normalization` has several entries, PST's analysis runs once per radius and every
#' requested normaliser (length-weighted or unweighted, per `weigh_by_length`) is applied to that run's diagnostics. The result
#' has `segment_id` once, then radius by radius: `integration_<norm><tag>` for each normalisation, `node_count<tag>`,
#' `total_depth<tag>` and, when weighted or `weight_outputs`, `total_weight<tag>` and `total_depth_weight<tag>`. `<tag>` is `_`
#' plus a dimension code (`s` straight, `w` walking, `n` steps, `a` angular) and the radius written exactly (`.` as `p`), empty when
#' no field varies. Fixed restrictions are recorded in the metadata (`rpst:*`, `rpst_manifest` attribute), which is authoritative.
#' See <https://github.com/kimonkrenz/rPSTool/blob/main/docs/compatibility/multi-radius.md>.
#'
#' @param graph A live graph created by segment_graph().
#' @param steps NULL or one non-negative whole number no greater than 2147483647, setting the native step limit.
#' @param radius Optional independent limits created by analysis_radius(). Supply either radius or non-NULL steps. One field may hold
#'   several values (multi-radius): the native analysis then runs once per radius; see Details.
#' @param weigh_by_length TRUE or FALSE (default). Native length weighting of reached segments.
#' @param normalization Exact name: "turner" (default), "syntax", or "hillier"; or a character vector of distinct names
#'   (each PST normaliser is applied to the same native run).
#' @param angle_threshold One finite number fitting a native float without nonzero underflow; degrees, default zero.
#' @param angle_precision One whole number from 1 through 4294967295; degrees, default one. Zero is unsafe for the native queue and is rejected.
#' @param weight_outputs TRUE or FALSE (default). Include native total_weight and total_depth_weight even when unweighted; weighted mode always includes them.
#' @param output_file NULL (default) or one file path. When given, the analysis runs once and its result is written
#'   directly to a Parquet file (zstd) without building an R data frame; see [pst_result_file]. Needs the optional
#'   package arrow (>= 25.0.0). The file has the same columns, order and row identity as the data frame, with PST's
#'   native float values stored as float32 (reading them back in R gives the identical doubles).
#' @param overwrite `TRUE` or `FALSE` (default). With `output_file` or `spatial_output_file`, whether an existing file may be replaced. Replacement is a single rename and the old file is untouched if anything fails; see [pst_result_file] for the platform differences, notably on Windows.
#' @param spatial_output_file `NULL` (default) or one file path. When given, the analysis runs once and a NEW spatial dataset
#'   is written: the original geometry and the original attributes of the file the graph was built from, plus this
#'   analysis' result columns, matched to the source features by position (no spatial join). The output format always
#'   equals the source format (GeoParquet to GeoParquet, FlatGeobuf to FlatGeobuf) and the CRS and geometry are carried
#'   over unchanged. A result column whose name equals a source column replaces that column; other result columns are
#'   appended. The destination must end in `.fgb` (FlatGeobuf source) or `.parquet` (GeoParquet source), in any letter case. Mutually exclusive with `output_file`; needs a graph built from a file path; `overwrite` applies to this
#'   file only, never to the source. The source file must not be modified or reordered after the graph is built. Returns
#'   an invisible [pst_result_file] descriptor. See <https://github.com/kimonkrenz/rPSTool/blob/main/docs/spatial-io/spatial-output.md>.
#' @return With output_file = NULL, a data frame in input segment order: one-based segment_id, integration, integer node_count and total_depth. Weighted mode or weight_outputs adds total_weight and total_depth_weight. Float outputs are widened to double. With several radii or normalisations the columns follow the multi-result schema described in Details. With `output_file` or `spatial_output_file`, the result is written to a file instead and an invisible `pst_result_file` descriptor (`path`, `rows`, `columns`, `format`) is returned; see [pst_result_file].
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
