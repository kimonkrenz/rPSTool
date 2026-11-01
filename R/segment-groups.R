.pst_group_pointer <- function(graph, class) {
  if (!inherits(graph, class) || !is.list(graph) || is.null(graph$ptr))
    stop("graph must be a live ", class, " created by ", sub("^pst_", "", class), "().", call. = FALSE)
  graph$ptr
}

#' Group segments using PST's angular continuity
#'
#' Calls `PSTASegmentGrouping` on an endpoint-connected segment graph. PST
#' selects pairs by angular deviation at shared endpoints; no R grouping
#' algorithm, snapping or interior crossing detection is performed.
#' `split_at_junctions` restricts continuations to degree-two intersections.
#' Thresholds narrow to native float. Values above 90 degrees are supported by
#' the pinned implementation and upstream tests, and values above 180 are allowed
#' and compared directly against PST deviations (which are at most 180 degrees).
#' IDs and colors are converted from native zero-based indices to one-based R IDs
#' without reordering.
#'
#' @param graph A live graph from [segment_graph()].
#' @param angle_threshold One finite non-negative native float value in degrees.
#'   Nonzero float underflow is rejected. Thresholds above 90 are supported.
#' @param split_at_junctions `TRUE` or `FALSE`; when `TRUE`, restrict
#'   continuations to degree-two intersections.
#' @param output_file NULL (default) or one file path. When given, the grouping runs once and its result is written
#'   directly to a Parquet file (zstd) without building an R data frame; see [print.pst_result_file()]. Needs the
#'   optional package arrow (>= 25.0.0). The file has the same columns, order, one-based `group_id`/`color` values and
#'   int32 types as the data frame; the two scalar attributes are stored as the Parquet schema metadata keys
#'   `rpst:n_groups` and `rpst:n_colors` (decimal strings), next to the usual `rpst:*` provenance keys. Result files are written through POSIX calls on Unix-alikes and through the Win32 API on Windows. The Windows implementation passed the development test suite on Windows; validation of the final release candidate on Windows is still outstanding.
#' @param overwrite `TRUE` or `FALSE` (default). Whether an existing `output_file` may be replaced (by a single rename; the old file is untouched if anything fails; see [pst_result_file] for the platform differences).
#' @return With `output_file = NULL`, a data frame in original segment order with
#'   integer `segment_id`, `group_id` and `color`, and integer `n_groups` and
#'   `n_colors` attributes recording native counts. IDs and colors are native
#'   indices plus one; colors are graph-coloring labels, not RGB values. The data
#'   frame retains no graph ownership and no inputs. With `output_file`, an
#'   invisible `pst_result_file` descriptor is returned instead.
#' @export
#' @examples
#' s <- segment_graph(rbind(c(0, 0, 3, 0), c(3, 0, 6, 0)))
#' segment_grouping(s)
segment_grouping <- function(graph, angle_threshold = 1,
                                 split_at_junctions = FALSE, output_file = NULL, overwrite = FALSE) {
  ptr <- .pst_group_pointer(graph, "pst_segment_graph")
  overwrite <- .pst_flag(overwrite, "overwrite")
  if (!is.null(output_file)) {
    columns <- c("segment_id", "group_id", "color")
    rows <- .Call(C_rpst_segment_graph_info, ptr)
    parameters <- list(angle_threshold = angle_threshold, split_at_junctions = split_at_junctions)
    metadata <- .pst_result_metadata("segment_grouping", parameters, "segment", rows, graph,
                                     "native segment order (source feature order); one-based segment_id, group_id and color; no external feature identifiers",
                                     float_columns = FALSE)
    return(invisible(.pst_write_result_file(
      output_file, overwrite, columns = columns, expected_rows = rows,
      export = function(stream, batch_rows)
        .Call(C_rpst_segment_grouping_stream, ptr, angle_threshold, split_at_junctions, stream, columns,
              names(metadata), unname(metadata), batch_rows))))
  }
  out <- .Call(C_rpst_segment_grouping, ptr, angle_threshold, split_at_junctions)
  result <- data.frame(segment_id = seq_along(out[[1L]]),
                       group_id = out[[1L]], color = out[[2L]])
  attr(result, "n_groups") <- out[[3L]]
  attr(result, "n_colors") <- out[[4L]]
  result
}

#' Construct a distinct PST segment-group graph
#'
#' Calls `PSTACreateSegmentGroupGraph` on the endpoint-connected source graph.
#' This distinct native family is incompatible with axial and segment analysis
#' handles. Supply one-based group IDs from `segment_grouping()` or an explicit
#' numeric vector; caller-supplied IDs are used in their given order and are not
#' relabeled. PST stores group nodes and distances by value; the result retains
#' neither the source segment graph nor the ID vector. No geometry, grouping or
#' topology is computed in R.
#'
#' The external pointer owns the native handle; last-owner collection calls
#' `PSTAFreeSegmentGroupGraph` exactly once. Copies share ownership. Native
#' pointers cannot be persisted: reconstruct after serialization or process
#' transfer. PST may create groups without native nodes, e.g. a single grouped
#' chain; these are valid graphs. See [segment_group_integration()] for outputs.
#'
#' A source graph that contains a zero-length segment (both endpoints
#' identical) is rejected before PST is called: PST's group-graph construction
#' does not terminate on such segments (`SegmentGroupGraph.cpp`, guarded only by
#' assertions that are compiled out of release builds). [segment_graph()],
#' [segment_grouping()] and the angular analyses accept the same graph.
#'
#' @param graph A live graph from [segment_graph()].
#' @param group_id Integer or double vector with exactly one whole ID per native
#'   segment, with values in `1..n_segments`. Group count is `max(group_id)`; gaps
#'   define empty native groups. Supply `grouping$group_id` or explicit IDs.
#' @return An S3 `pst_segment_group_graph` list with `ptr` (owned external
#'   pointer), `type` (`"segment_group"`), `n_groups` (integer) and `pst_version`
#'   (`"3.3.2"`). Treat fields as read-only. Printing uses the authoritative
#'   native owner size, not editable metadata.
#' @export
#' @examples
#' s <- segment_graph(cbind(0:4, 0, 1:5, 0))
#' ids <- segment_grouping(s)$group_id
#' g <- segment_group_graph(s, ids)
#' print(g)
segment_group_graph <- function(graph, group_id) {
  ptr <- .Call(C_rpst_segment_group_graph_create,
               .pst_group_pointer(graph, "pst_segment_graph"), group_id)
  structure(list(ptr = ptr, type = "segment_group",
                 n_groups = .Call(C_rpst_segment_group_graph_info, ptr),
                 pst_version = "3.3.2"), class = "pst_segment_group_graph")
}

#' @rdname segment_group_graph
#' @param x A `pst_segment_group_graph`.
#' @param ... Unused additional arguments.
#' @export
print.pst_segment_group_graph <- function(x, ...) {
  ptr <- .pst_group_pointer(x, "pst_segment_group_graph")
  n <- .Call(C_rpst_segment_group_graph_info, ptr)
  cat(sprintf("<pst_segment_group_graph> PST 3.3.2: %d groups\n", n))
  invisible(x)
}

#' Calculate PST Segment Group Integration
#'
#' Calls `PSTASegmentGroupIntegration` directly. Only walking and steps radii are
#' supported. Depth counts group transitions, not walking length; walking limits
#' constrain traversal without rescaling coordinate units. PST computes
#' Integration directly; no R normalization or recomputation occurs. Written
#' node counts include the origin for groups with native nodes. An isolated group
#' in a graph containing nodes receives PST's written -1 integration, zero count
#' and zero depth; it is not assigned origin count one.
#'
#' A wholly no-node group graph (e.g. a chain grouped into one group) makes PST
#' return success without writing outputs. rPSTool detects paired count/depth writes
#' and reports all three unwritten values as typed NA. Written -1, 0, NaN and Inf
#' remain unchanged; scores are never used as missing-value sentinels. Mismatched
#' count/depth write masks error.
#'
#' The graph is reusable; the source graph and ID vector are not needed for
#' analysis. Calls are synchronous; workers never call R.
#' `RPST_NUM_THREADS` caps workers; without it native hardware concurrency is
#' used; an active `_R_CHECK_LIMIT_CORES_` (non-empty, not false,
#' case-insensitive) limits workers to two. Invalid explicit caps error,
#' including on no-node graphs.
#'
#' @param graph A live graph from [segment_group_graph()].
#' @param radius Independent walking/steps limits from [analysis_radius()].
#'   Straight, angular and axmeter limits are unsupported and rejected.
#' @return With `output_file = NULL`, a data frame in group-ID order: `group_id`
#'   (integer), `integration` (double), `node_count` (integer) and `total_depth`
#'   (double, widened from native float). Genuinely unwritten outputs are
#'   `NA_real_`, `NA_integer_` and `NA_real_`. With `output_file`, an invisible
#'   `pst_result_file` descriptor is returned instead.
#' @param output_file `NULL` (default) returns the data frame. A path writes the same table directly to one Parquet
#'   file from PST's native result arrays and returns an invisible `pst_result_file` descriptor, without building R
#'   result vectors. Requires the optional package `arrow (>= 25.0.0)`. Result files are written through POSIX calls on Unix-alikes and through the Win32 API on Windows. The Windows implementation passed the development test suite on Windows; validation of the final release candidate on Windows is still outstanding. Columns, order and values are those
#'   of the data frame (`group_id` and `node_count` int32, `integration` and `total_depth` float32). `integration`,
#'   `node_count` and `total_depth` are declared nullable; a row is null in all three exactly when PST wrote neither its
#'   count nor its depth (the `NA`s of the data frame), and a written `NaN`, infinity, `-1` or `0` is an ordinary value.
#'   Further detail (a repository link, not shipped in the installed package):
#'   <https://github.com/kimonkrenz/rPSTool/blob/main/docs/spatial-io/result-files.md>.
#' @param overwrite With `output_file`, whether an existing file may be replaced (by a single rename; the old file is untouched if anything fails; see [pst_result_file] for the platform differences, notably on Windows) (default `FALSE`).
#' @export
#' @examples
#' s <- segment_graph(cbind(0:4 * 3, 0, 1:5 * 3, 0))
#' grouping <- segment_grouping(s)
#' g <- segment_group_graph(s, grouping$group_id)
#' segment_group_integration(g) # unwritten native outputs become NA
#' g <- segment_group_graph(s, seq_len(s$n_segments))
#' segment_group_integration(g, analysis_radius(steps = 1))
segment_group_integration <- function(graph, radius = analysis_radius(), output_file = NULL, overwrite = FALSE) {
  ptr <- .pst_group_pointer(graph, "pst_segment_group_graph")
  overwrite <- .pst_flag(overwrite, "overwrite")
  if (!is.null(output_file))
    return(.pst_axial_result_file(
      output_file, overwrite, "segment_group_integration", list(radius = .pst_radius_parameters(radius)), graph, ptr,
      c("group_id", "integration", "node_count", "total_depth"),
      "group id order (one-based, ascending); no external identifiers",
      function(stream, columns, metadata_names, metadata_values, batch_rows)
        .Call(C_rpst_segment_group_integration_stream, ptr, radius, stream, columns, metadata_names, metadata_values,
              batch_rows),
      graph_type = "segment_group", rows = .Call(C_rpst_segment_group_graph_info, ptr)))
  out <- .Call(C_rpst_segment_group_integration, ptr, radius)
  data.frame(group_id = seq_along(out[[1L]]), integration = out[[1L]],
             node_count = out[[2L]], total_depth = out[[3L]])
}
