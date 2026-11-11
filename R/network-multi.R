# Multi-radius layer of Network Reach and Segment Betweenness (docs/compatibility/multi-radius.md), built on the shared helpers of
# R/angular-multi.R. R only plans: it expands analysis_radius() into validated scalar configurations (all of them before the first
# native call), names the result columns and builds the metadata. The native entry points (rpst_reach_multi[_stream],
# rpst_betweenness_multi[_stream]) run PST once per radius and apply PST's exported normalisers to that run; no number is computed
# here. The finished columns of all radii are retained by the native result (preallocated R vectors, or one rPSTool-owned table
# for a file), so result storage grows with the number of radii.

.pst_axial_line_order <- "native line order (source feature order); no external feature identifiers"

.pst_network_reach_multi <- function(graph, ptr, plan, origins, output_file, overwrite, spatial_output_file) {
  id <- if (is.null(origins)) "line_id" else "origin_id"
  spec <- .pst_multi_spec_from(plan, .pst_nm_network_reach, id_col = id)
  parameters <- list(radius = NULL, origins = if (is.null(origins)) "lines" else NROW(origins))
  .pst_multi_run(graph, ptr, "network_reach", plan, NULL, spec, parameters, output_file, overwrite, spatial_output_file,
                 function() .Call(C_rpst_reach_multi, ptr, plan$configs, origins),
                 function(stream, columns, md_names, md_values, batch_rows)
                   .Call(C_rpst_reach_multi_stream, ptr, plan$configs, origins, stream, columns, md_names, md_values,
                         batch_rows),
                 id_col = id, rows = .Call(C_rpst_graph_info, ptr)[[1L]], graph_type = "axial",
                 order = if (is.null(origins)) .pst_axial_line_order
                         else "supplied origin row order; one-based row positions, no external identifiers")
}

.pst_network_betweenness_multi <- function(graph, ptr, plan, distance, norms, weights, weight, attraction_points,
                                           output_file, overwrite, spatial_output_file) {
  spec <- .pst_multi_spec_from(plan, function(config)
    .pst_nm_network_betweenness(config, distance, norms, weight, !is.null(attraction_points)), id_col = "line_id")
  native <- setdiff(norms, "none")   # the raw score is always returned, once per radius
  parameters <- list(radius = NULL, distance = distance, normalization = NULL, weights = .pst_count_or_null(weights),
                     weight_name = weight$name,
                     attraction_points = if (is.null(attraction_points)) NULL else NROW(attraction_points))
  .pst_multi_run(graph, ptr, "network_betweenness", plan, norms, spec, parameters, output_file, overwrite,
                 spatial_output_file,
                 function() .Call(C_rpst_betweenness_multi, ptr, plan$configs, distance, native, weights, attraction_points),
                 function(stream, columns, md_names, md_values, batch_rows)
                   .Call(C_rpst_betweenness_multi_stream, ptr, plan$configs, distance, native, weights, attraction_points,
                         stream, columns, md_names, md_values, batch_rows),
                 id_col = "line_id", rows = .Call(C_rpst_graph_info, ptr)[[1L]], graph_type = "axial",
                 order = .pst_axial_line_order)
}

# Network Integration with several steps radii. The supported-field rule of the scalar function (steps only, as in the official PST for
# QGIS plugin) is unchanged and has already been applied by the caller, so a vector can only be a steps vector. The checks below run in
# the order of .pst_network_integration_run(); the scalar and junction-output contracts are the same.
.pst_network_integration_multi <- function(graph, resolved, junctions, junction_output = c("native", "sf"), output_file = NULL,
                                           overwrite = FALSE, spatial_output_file = NULL) {
  junction_output <- match.arg(junction_output)
  if (junction_output == "sf") {
    if (!isTRUE(junctions))
      stop("junction_output = \"sf\" requires junctions = TRUE.", call. = FALSE)
    .pst_require_sf()
  }
  ptr <- .pst_analysis_graph(graph, FALSE)
  plan <- .pst_radius_plan(resolved, FALSE)
  overwrite <- .pst_flag(overwrite, "overwrite")
  spec <- .pst_multi_spec_from(plan, .pst_nm_network_integration, id_col = "line_id", normalized_roles = character())
  .pst_spatial_request(output_file, spatial_output_file, !isTRUE(junctions), "network_integration with junctions = TRUE (one result per junction)")
  if (!is.null(output_file) || !is.null(spatial_output_file)) {
    if (isTRUE(junctions))
      stop("output_file cannot hold junction results; use junctions = FALSE to write the line results.", call. = FALSE)
  }
  if (!isTRUE(junctions))
    return(.pst_multi_run(graph, ptr, "network_integration", plan, NULL, spec, list(radius = NULL), output_file, overwrite,
                          spatial_output_file,
                          function() .Call(C_rpst_network_integration_multi, ptr, plan$configs, FALSE)[[1L]],
                          function(stream, columns, md_names, md_values, batch_rows)
                            .Call(C_rpst_network_integration_multi_stream, ptr, plan$configs, stream, columns, md_names, md_values,
                                  batch_rows),
                          id_col = "line_id", rows = .Call(C_rpst_graph_info, ptr)[[1L]], graph_type = "axial",
                          order = .pst_axial_line_order))
  .pst_progress_scope(vapply(seq_along(plan$configs), function(i) spec$name[spec$radius == i][[1L]], ""))
  out <- .Call(C_rpst_network_integration_multi, ptr, plan$configs, TRUE)
  lines <- .pst_multi_frame(out[[1L]], spec, plan, "line_id")
  scores <- out[[3L]]
  names(scores) <- unlist(lapply(plan$configs, function(config) .pst_nm_names(.pst_nm_junction(config))))
  junction_id <- seq_len(nrow(out[[2L]]))
  junction_table <- if (junction_output == "sf")
    .pst_sf_point_output(out[[2L]], attr(graph, "crs", exact = TRUE), structure(c(list(junction_id = junction_id), scores),
                                                                           class = "data.frame", row.names = junction_id))
  else structure(c(list(junction_id = junction_id, x = out[[2L]][, 1L], y = out[[2L]][, 2L]), scores),
                 class = "data.frame", row.names = junction_id)
  list(lines = lines, junctions = junction_table)
}
