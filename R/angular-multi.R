# Multi-radius / multi-normalisation layer for the two angular analyses (docs/compatibility/multi-radius.md).
#
# R only plans: it expands analysis_radius() into validated scalar configurations, names the result columns and builds the
# metadata. The native entry points (rpst_angular_*_multi[_stream]) run PST once per radius and apply PST's exported
# normalisers to that run's arrays; no number is computed here.

# Distinct, valid, non-missing names from `choices`, in the requested order.
.pst_modes <- function(value, choices, parameter) {
  if (length(value) <= 1L) return(.pst_mode(value, choices, parameter))   # scalar call: unchanged wording
  if (!is.character(value) || !length(value) || anyNA(value) || !all(value %in% choices))
    stop(parameter, " must be one or more of: ", paste(choices, collapse = ", "), ".", call. = FALSE)
  if (anyDuplicated(value)) stop(parameter, " must not contain duplicates.", call. = FALSE)
  value
}

# The ordered result columns of a multi-result call: name, role, radius index, normalisation (NA for raw/diagnostics).
.pst_multi_spec <- function(analysis, plan, norms, weighted, weight_outputs = FALSE) {
  rows <- list()
  add <- function(name, role, radius, norm = NA_character_)
    rows[[length(rows) + 1L]] <<- data.frame(name = name, role = role, radius = radius, normalization = norm,
                                             stringsAsFactors = FALSE)
  for (i in seq_along(plan$configs)) {
    t <- .pst_radius_tag(plan, i)
    if (analysis == "choice") {
      add(paste0("choice", t), "choice", i)
      add(paste0("node_count", t), "node_count", i)
      add(paste0("total_depth", t), "total_depth", i)
      if (weighted) add(paste0("total_depth_weight", t), "total_depth_weight", i)
      for (n in setdiff(norms, "none")) add(paste0("choice_", n, t), "normalized", i, n)
    } else {
      for (n in norms) add(paste0("integration_", n, t), "integration", i, n)
      add(paste0("node_count", t), "node_count", i)
      add(paste0("total_depth", t), "total_depth", i)
      if (weighted || weight_outputs) {
        add(paste0("total_weight", t), "total_weight", i)
        add(paste0("total_depth_weight", t), "total_depth_weight", i)
      }
    }
  }
  spec <- do.call(rbind, rows)
  if (anyDuplicated(tolower(c("segment_id", spec$name))))
    stop("Internal error: duplicate multi-result column names.", call. = FALSE)
  spec
}

# TRUE when the call keeps the scalar schema (one radius configuration and one normalisation).
.pst_is_scalar_call <- function(plan, norms) length(plan$configs) == 1L && length(norms) == 1L

.pst_multi_json_radius <- function(plan) {
  cfg <- unclass(plan$configs[[1L]])
  if (nzchar(plan$varying)) cfg[[plan$varying]] <- .pst_json_array(as.list(plan$values))
  cfg
}
.pst_multi_metadata <- function(fn, parameters, plan, norms, spec, rows, graph) {
  parameters$radius <- .pst_multi_json_radius(plan)
  parameters$normalization <- .pst_json_array(as.list(norms))
  md <- .pst_result_metadata(fn, parameters, "segment", rows, graph)
  md[["rpst:schema"]] <- "2"
  manifest <- lapply(seq_len(nrow(spec)), function(i)
    list(name = spec$name[[i]], role = spec$role[[i]], radius = spec$radius[[i]],
         normalization = if (is.na(spec$normalization[[i]])) NULL else spec$normalization[[i]]))
  c(md,
    "rpst:radius_varying" = plan$varying,
    "rpst:radius_fixed" = .pst_json(if (length(plan$fixed)) plan$fixed else structure(list(), names = character())),
    "rpst:radius_configurations" = .pst_json(.pst_json_array(lapply(plan$configs, unclass))),
    "rpst:normalizations" = .pst_json(.pst_json_array(as.list(norms))),
    "rpst:columns" = .pst_json(.pst_json_array(manifest)))
}

# In-memory multi-result data frame from the flat list of native columns.
.pst_multi_frame <- function(columns, spec, plan) {
  frame <- data.frame(segment_id = seq_along(columns[[1L]]))
  for (i in seq_len(nrow(spec))) frame[[spec$name[[i]]]] <- columns[[i]]
  attr(frame, "rpst_manifest") <- list(columns = spec, radii = lapply(plan$configs, unclass))
  frame
}

# Shared file/in-memory driver. `call_frame(configs)` runs the in-memory native entry; `call_stream(stream, columns, ...)`
# the file one. Both run PST once per radius.
.pst_multi_run <- function(graph, ptr, fn, plan, norms, spec, parameters, output_file, overwrite, spatial_output_file,
                           call_frame, call_stream) {
  if (is.null(output_file) && is.null(spatial_output_file))
    return(.pst_multi_frame(call_frame(), spec, plan))
  columns <- c("segment_id", spec$name)
  rows <- .Call(C_rpst_segment_graph_info, ptr)
  metadata <- .pst_multi_metadata(fn, parameters, plan, norms, spec, rows, graph)
  invisible(.pst_write_result_file(
    output_file, overwrite, columns = columns, expected_rows = rows,
    export = function(stream, batch_rows)
      call_stream(stream, columns, names(metadata), unname(metadata), batch_rows),
    spatial_output_file = spatial_output_file, graph = graph, metadata = metadata))
}

.pst_angular_choice_multi <- function(graph, ptr, plan, weighted, norms, threshold, precision,
                                      output_file, overwrite, spatial_output_file) {
  spec <- .pst_multi_spec("choice", plan, norms, weighted)
  native <- setdiff(norms, "none")
  parameters <- list(radius = NULL, weigh_by_length = weighted, normalization = NULL,
                     angle_threshold = threshold, angle_precision = precision)
  .pst_multi_run(graph, ptr, "angular_choice", plan, norms, spec, parameters, output_file, overwrite,
                 spatial_output_file,
                 function() .Call(C_rpst_angular_choice_multi, ptr, plan$configs, weighted, native, threshold, precision),
                 function(stream, columns, md_names, md_values, batch_rows)
                   .Call(C_rpst_angular_choice_multi_stream, ptr, plan$configs, weighted, native, threshold, precision,
                         stream, columns, md_names, md_values, batch_rows))
}

.pst_angular_integration_multi <- function(graph, ptr, plan, weighted, norms, threshold, precision, weight_outputs,
                                           output_file, overwrite, spatial_output_file) {
  weighted <- .pst_flag(weighted, "weigh_by_length")
  weight_outputs <- .pst_flag(weight_outputs, "weight_outputs")
  spec <- .pst_multi_spec("integration", plan, norms, weighted, weight_outputs)
  parameters <- list(radius = NULL, weigh_by_length = weighted, normalization = NULL,
                     angle_threshold = threshold, angle_precision = precision, weight_outputs = weight_outputs)
  .pst_multi_run(graph, ptr, "angular_integration", plan, norms, spec, parameters, output_file, overwrite,
                 spatial_output_file,
                 function() .Call(C_rpst_angular_integration_multi, ptr, plan$configs, weighted, norms, threshold,
                                  precision, weight_outputs),
                 function(stream, columns, md_names, md_values, batch_rows)
                   .Call(C_rpst_angular_integration_multi_stream, ptr, plan$configs, weighted, norms, threshold,
                         precision, weight_outputs, stream, columns, md_names, md_values, batch_rows))
}
