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
