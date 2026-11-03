.pst_group_pointer <- function(graph, class) {
  if (!inherits(graph, class) || !is.list(graph) || is.null(graph$ptr))
    stop("graph must be a live ", class, " created by ", sub("^pst_", "", class), "().", call. = FALSE)
  graph$ptr
}

#' Group segments by angular continuity
#'
#' Groups the segments of a segment graph into continuous routes by joining pairs of segments that meet at a
#' shared endpoint with a small angular deviation. The grouping can be passed to [segment_group_graph()] to
#' analyse the network at the level of whole streets or routes.
#'
#' @details
#' At each shared endpoint PST selects pairs of segments by angular deviation, using `angle_threshold`.
#' `split_at_junctions = TRUE` restricts continuations to intersections where exactly two segments meet
#' (degree two). The threshold is in degrees; values above 90 are supported, and values above 180 are
#' allowed and compared directly with PST's deviations (which never exceed 180 degrees). Groups and colours are
#' numbered from one in PST's order.
#'
#' @param graph A segment graph created by [segment_graph()].
#' @param angle_threshold One finite, non-negative number of degrees. A non-zero value that underflows single
#'   precision is rejected.
#' @param split_at_junctions `TRUE` or `FALSE`. If `TRUE`, continuations are restricted to degree-two
#'   intersections.
#' @param output_file,overwrite Write the result to a Parquet file instead of returning a data frame; see
#'   [pst_result_file]. The two scalar attributes are stored as the schema metadata keys `rpst:n_groups` and
#'   `rpst:n_colors`.
#' @return A data frame in segment order with integer columns `segment_id`, `group_id` and `color`, and integer
#'   attributes `n_groups` and `n_colors`. Groups and colours are numbered from one; a colour is a
#'   graph-colouring label (adjacent groups differ), not an RGB value. With `output_file`, an invisible
#'   [pst_result_file] descriptor is returned instead.
#' @seealso [segment_group_graph()], [segment_group_integration()], [segment_graph()]
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

#' Build a graph of segment groups
#'
#' Creates a segment-group graph from a segment graph and an assignment of its segments to groups, for example the
#' output of [segment_grouping()]. The result is analysed with [segment_group_integration()].
#'
#' @details
#' Supply `group_id` from [segment_grouping()] or as your own vector of group identifiers. Identifiers are used
#' in the order given and are not relabelled. Groups with no connecting nodes (for example a single grouped chain)
#' are valid. The resulting graph does not keep the source segment graph or the identifier vector. A segment-group
#' graph is a different object from segment and axial graphs and only [segment_group_integration()] accepts it.
#' Like other graphs it is held in native memory, cannot be saved with `saveRDS()` or sent to another R process,
#' and must be rebuilt from the segment graph and the identifiers.
#'
#' @section Limitations:
#' A source graph containing a zero-length segment (both endpoints identical) is rejected before PST is called,
#' because PST's group-graph construction does not terminate on such segments. [segment_graph()],
#' [segment_grouping()] and the angular analyses accept the same graph. Remove or repair zero-length segments
#' first.
#'
#' @param graph A segment graph created by [segment_graph()].
#' @param group_id Integer or double vector with exactly one whole identifier per segment, with values in
#'   `1..n_segments`. The number of groups is `max(group_id)`; gaps define empty groups.
#' @return An object of class `pst_segment_group_graph`: a list with `type` (`"segment_group"`), `n_groups` and
#'   `pst_version`, plus the native handle `ptr`. Treat these fields as read-only.
#' @seealso [segment_grouping()], [segment_group_integration()], [segment_graph()]
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

#' Segment Group Integration
#'
#' Calculates integration for each group of a segment-group graph, where depth counts the number of transitions
#' between groups. Use it to analyse the accessibility of whole routes or streets rather than individual segments.
#'
#' @details
#' Only `walking` and `steps` radii are accepted; straight, angular and axmeter limits are rejected. Depth counts
#' transitions between groups, not walking length. A walking limit constrains the traversal without rescaling the
#' coordinate units. PST computes the integration itself; rPSTool applies no normalisation. Node counts include the
#' origin for groups with connecting nodes. An isolated group in a graph that contains nodes receives PST's written
#' integration of `-1`, a count of zero and a depth of zero.
#'
#' If the whole graph has no connecting nodes (for example a chain grouped into one group), PST writes no
#' outputs, and rPSTool reports integration, count and depth as `NA`. Written values of `-1`, `0`, `NaN` and `Inf` are returned unchanged;
#' they are never treated as missing.
#'
#' PST uses several worker threads; see [network_betweenness()] for how to cap them. Invalid explicit caps are
#' rejected even for graphs without nodes.
#'
#' @param graph A segment-group graph created by [segment_group_graph()].
#' @param radius Walking and/or steps limits created by [analysis_radius()].
#' @param output_file,overwrite Write the result to a Parquet file instead of returning a data frame; see
#'   [pst_result_file]. `gi_...`, `nc_...` and `td_...` are stored as nullable columns: a row is
#'   null in all three exactly when PST wrote neither its count nor its depth, which is when the data frame
#'   holds `NA`.
#' @return A data frame in group order with `group_id` (integer), `gi_<radius>` (integration, double), `nc_<radius>`
#'   (node count, integer) and `td_<radius>` (total depth, double); see [result_column_names]. Outputs PST did not write are `NA`. With `output_file` an invisible
#'   [pst_result_file] descriptor is returned instead.
#' @seealso [segment_group_graph()], [segment_grouping()], [analysis_radius()]
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
  cols <- .pst_nm_segment_group_integration(radius)
  result_label <- .pst_nm_names(cols)[[1L]]   # generated names are validated before any native work
  .pst_progress_scope(result_label)
  if (!is.null(output_file))
    return(.pst_axial_result_file(
      output_file, overwrite, "segment_group_integration", list(radius = .pst_radius_parameters(radius)), graph, ptr,
      c("group_id", .pst_nm_names(cols)),
      "group id order (one-based, ascending); no external identifiers",
      function(stream, columns, metadata_names, metadata_values, batch_rows)
        .Call(C_rpst_segment_group_integration_stream, ptr, radius, stream, columns, metadata_names, metadata_values,
              batch_rows),
      graph_type = "segment_group", rows = .Call(C_rpst_segment_group_graph_info, ptr), cols = cols))
  out <- .Call(C_rpst_segment_group_integration, ptr, radius)
  structure(data.frame(group_id = seq_along(out[[1L]]), integration = out[[1L]],
             node_count = out[[2L]], total_depth = out[[3L]]), names = c("group_id", .pst_nm_names(cols)))
}
