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
  junctions <- .pst_flag(junctions, "junctions")   # a non-flag is an error, never silently FALSE; checked before anything else
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

# ---- Attraction Reach, Attraction Distance and OD Betweenness ----------------------------------------------------------------------
# The native entry points run PST once per radius with the scalar descriptor; R only plans, names and describes. The identifier column
# and row order are those of the scalar functions (`origin_id` in PST's origin order for the attraction analyses, `line_id` for OD
# Betweenness), and the file routes use the same native result storage and Arrow stream.

.pst_attraction_reach_multi <- function(graph, ptr, plan, origin, distance, attraction_points, points_per_polygon,
                                        polygon_point_interval, attraction_values, weight, decay, decay_constant, distribution,
                                        collection, output_file, overwrite, spatial_output_file) {
  spec <- .pst_multi_spec_from(plan, function(config)
    .pst_nm_attraction_reach(config, origin, distance, weight, decay, decay_constant, distribution, collection,
                             polygon_point_interval), id_col = "origin_id")
  parameters <- c(.pst_attraction_parameters(NULL, origin, distance, attraction_points, points_per_polygon, polygon_point_interval),
                  list(attraction_values = .pst_count_or_null(attraction_values), weight_name = weight$name, decay = decay,
                       decay_constant = decay_constant, distribution = distribution, collection = collection))
  .pst_multi_run(graph, ptr, "attraction_reach", plan, NULL, spec, parameters, output_file, overwrite, spatial_output_file,
                 function() .Call(C_rpst_attraction_reach_multi, ptr, plan$configs, origin, distance, attraction_points,
                                  points_per_polygon, polygon_point_interval, attraction_values, decay, decay_constant,
                                  distribution, collection),
                 function(stream, columns, md_names, md_values, batch_rows)
                   .Call(C_rpst_attraction_reach_multi_stream, ptr, plan$configs, origin, distance, attraction_points,
                         points_per_polygon, polygon_point_interval, attraction_values, decay, decay_constant, distribution,
                         collection, stream, columns, md_names, md_values, batch_rows),
                 id_col = "origin_id", rows = .Call(C_rpst_graph_info, ptr)[[1L]], graph_type = "axial",
                 order = .pst_attraction_order(origin), float_columns = TRUE)
}

.pst_attraction_distance_multi <- function(graph, ptr, plan, origin, distance, attraction_points, points_per_polygon,
                                           polygon_point_interval, line_weights, weight, point_edge_weight, destination_indices,
                                           output_file, overwrite, spatial_output_file) {
  destination_indices <- .pst_flag(destination_indices, "destination_indices")
  spec <- .pst_multi_spec_from(plan, function(config)
    .pst_nm_attraction_distance(config, origin, distance, weight, point_edge_weight, polygon_point_interval,
                                destination_indices), id_col = "origin_id")
  parameters <- c(.pst_attraction_parameters(NULL, origin, distance, attraction_points, points_per_polygon, polygon_point_interval),
                  list(line_weights = .pst_count_or_null(line_weights), weight_name = weight$name,
                       point_edge_weight = point_edge_weight, destination_indices = destination_indices))
  .pst_multi_run(graph, ptr, "attraction_distance", plan, NULL, spec, parameters, output_file, overwrite, spatial_output_file,
                 function() .Call(C_rpst_attraction_distance_multi, ptr, plan$configs, origin, distance, attraction_points,
                                  points_per_polygon, polygon_point_interval, line_weights, point_edge_weight,
                                  destination_indices),
                 function(stream, columns, md_names, md_values, batch_rows)
                   .Call(C_rpst_attraction_distance_multi_stream, ptr, plan$configs, origin, distance, attraction_points,
                         points_per_polygon, polygon_point_interval, line_weights, point_edge_weight, destination_indices,
                         stream, columns, md_names, md_values, batch_rows),
                 id_col = "origin_id", rows = .Call(C_rpst_graph_info, ptr)[[1L]], graph_type = "axial",
                 order = .pst_attraction_order(origin))
}

.pst_od_betweenness_multi <- function(graph, ptr, plan, origins, distance, destination_mode, origin_weights, destination_weights,
                                      origin_weight, destination_weight, output_file, overwrite, spatial_output_file) {
  spec <- .pst_multi_spec_from(plan, function(config)
    .pst_nm_od_betweenness(config, distance, destination_mode, origin_weight, destination_weight), id_col = "line_id")
  parameters <- list(radius = NULL, distance = distance, destination_mode = destination_mode, origins = NROW(origins),
                     origin_weights = .pst_count_or_null(origin_weights), origin_weight_name = origin_weight$name,
                     destination_weights = .pst_count_or_null(destination_weights),
                     destination_weight_name = destination_weight$name)
  .pst_multi_run(graph, ptr, "od_betweenness", plan, NULL, spec, parameters, output_file, overwrite, spatial_output_file,
                 function() .Call(C_rpst_od_betweenness_multi, ptr, origins, plan$configs, distance, destination_mode,
                                  origin_weights, destination_weights),
                 function(stream, columns, md_names, md_values, batch_rows)
                   .Call(C_rpst_od_betweenness_multi_stream, ptr, origins, plan$configs, distance, destination_mode,
                         origin_weights, destination_weights, stream, columns, md_names, md_values, batch_rows),
                 id_col = "line_id", rows = .Call(C_rpst_graph_info, ptr)[[1L]], graph_type = "axial",
                 order = .pst_axial_line_order)
}
