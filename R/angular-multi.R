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

# The ordered result columns of a multi-result call: name, role, radius index, normalisation (NA for raw/diagnostics). The
# names come from the central naming layer (R/naming.R), so a scalar and a multi-radius call name the same column alike;
# attr(, "cols") holds the full column descriptions for the manifest.
.pst_multi_spec <- function(analysis, plan, norms, weighted, weight_outputs = FALSE, threshold = 0, precision = 1) {
  .pst_multi_spec_from(plan, function(config)
    if (analysis == "choice") .pst_nm_angular_choice(config, weighted, norms, threshold, precision)
    else .pst_nm_angular_integration(config, weighted, weight_outputs, norms, threshold, precision))
}

# Analysis-independent core of the column spec: `columns_of(config)` returns the naming-layer column descriptions of one scalar
# radius configuration. `id_col` is the result identifier column that comes first (and may not be reused as a result name);
# `normalized_roles` are the roles whose `normalization` is reported in the spec.
.pst_multi_spec_from <- function(plan, columns_of, id_col = "segment_id", normalized_roles = c("normalized", "integration")) {
  rows <- list(); all_cols <- list()
  for (i in seq_along(plan$configs)) {
    cols <- columns_of(plan$configs[[i]])
    for (col in cols) {
      norm <- if (col$role %in% normalized_roles) col$normalization else NA_character_
      rows[[length(rows) + 1L]] <- data.frame(name = col$name, role = col$role, radius = i, normalization = norm,
                                              stringsAsFactors = FALSE)
      col$radius_index <- i
      all_cols[[length(all_cols) + 1L]] <- col
    }
  }
  spec <- do.call(rbind, rows)
  if (anyDuplicated(tolower(c(id_col, spec$name))))
    stop("Internal error: duplicate multi-result column names.", call. = FALSE)
  attr(spec, "cols") <- all_cols
  spec
}

# TRUE when the call keeps the scalar schema (one radius configuration and one normalisation).
.pst_is_scalar_call <- function(plan, norms) length(plan$configs) == 1L && length(norms) == 1L

.pst_multi_json_radius <- function(plan) {
  cfg <- unclass(plan$configs[[1L]])
  if (nzchar(plan$varying)) cfg[[plan$varying]] <- .pst_json_array(as.list(plan$values))
  cfg
}
# `norms = NULL` (analyses without a normalisation choice) omits the normalisation entries. `graph_type`, `order` and
# `float_columns` describe the result table's graph and rows as `.pst_result_metadata()` does.
.pst_multi_metadata <- function(fn, parameters, plan, norms, spec, rows, graph, graph_type = "segment",
                                order = NULL, float_columns = TRUE) {
  parameters$radius <- .pst_multi_json_radius(plan)
  if (!is.null(norms)) parameters$normalization <- .pst_json_array(as.list(norms))
  md <- if (is.null(order)) .pst_result_metadata(fn, parameters, graph_type, rows, graph, float_columns = float_columns)
        else .pst_result_metadata(fn, parameters, graph_type, rows, graph, order, float_columns = float_columns)
  md[["rpst:schema"]] <- "2"
  full <- attr(spec, "cols")
  manifest <- lapply(seq_len(nrow(spec)), function(i) {
    col <- full[[i]]
    c(list(name = spec$name[[i]], role = spec$role[[i]], radius = spec$radius[[i]],
           normalization = if (is.na(spec$normalization[[i]])) NULL else spec$normalization[[i]]),
      col[c("code", "distance", "weight", "parameters")][nzchar(unlist(col[c("code", "distance", "weight", "parameters")]))],
      if (!is.null(col$weight_name)) list(weight_name = col$weight_name),   # the R object the weights came from, as in a scalar manifest
      list(radius_tag = col$radius))
  })
  c(md,
    "rpst:radius_varying" = plan$varying,
    "rpst:radius_fixed" = .pst_json(if (length(plan$fixed)) plan$fixed else structure(list(), names = character())),
    "rpst:radius_configurations" = .pst_json(.pst_json_array(lapply(plan$configs, unclass))),
    if (!is.null(norms)) c("rpst:normalizations" = .pst_json(.pst_json_array(as.list(norms)))),
    "rpst:columns" = .pst_json(.pst_json_array(manifest)))
}

# In-memory multi-result data frame from the flat list of native columns.
.pst_multi_frame <- function(columns, spec, plan, id_col = "segment_id", ids = seq_along(columns[[1L]])) {
  frame <- data.frame(ids)
  names(frame) <- id_col
  for (i in seq_len(nrow(spec))) frame[[spec$name[[i]]]] <- columns[[i]]
  attr(frame, "rpst_manifest") <- list(columns = spec, radii = lapply(plan$configs, unclass))
  frame
}

# Shared file/in-memory driver. `call_frame(configs)` runs the in-memory native entry; `call_stream(stream, columns, ...)`
# the file one. Both run PST once per radius.
# The defaults describe the angular segment tables; other analyses pass their own identifier column, native row count and
# metadata description.
.pst_multi_run <- function(graph, ptr, fn, plan, norms, spec, parameters, output_file, overwrite, spatial_output_file,
                           call_frame, call_stream, id_col = "segment_id",
                           rows = .Call(C_rpst_segment_graph_info, ptr), graph_type = "segment", order = NULL,
                           float_columns = TRUE) {
  # one analysis per radius; each is labelled with its first result variable
  .pst_progress_scope(vapply(seq_along(plan$configs), function(i) spec$name[spec$radius == i][[1L]], ""))
  if (is.null(output_file) && is.null(spatial_output_file))
    return(.pst_multi_frame(call_frame(), spec, plan, id_col))
  columns <- c(id_col, spec$name)
  metadata <- .pst_multi_metadata(fn, parameters, plan, norms, spec, rows, graph, graph_type, order, float_columns)
  invisible(.pst_write_result_file(
    output_file, overwrite, columns = columns, expected_rows = rows,
    export = function(stream, batch_rows)
      call_stream(stream, columns, names(metadata), unname(metadata), batch_rows),
    spatial_output_file = spatial_output_file, graph = graph, metadata = metadata))
}

.pst_angular_choice_multi <- function(graph, ptr, plan, weighted, norms, threshold, precision,
                                      output_file, overwrite, spatial_output_file) {
  spec <- .pst_multi_spec("choice", plan, norms, weighted, FALSE, threshold, precision)
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
  spec <- .pst_multi_spec("integration", plan, norms, weighted, weight_outputs, threshold, precision)
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
