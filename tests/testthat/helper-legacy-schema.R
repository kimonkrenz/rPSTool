# The numerical regression tests were written against the generic column names (`integration`, `choice`, `node_count`, ...).
# The output-naming change (docs/output-naming.md) only relabels columns, so those tests are kept unchanged and run through
# this adapter: it calls the real public function and renames each single-result column back to its role name, so every
# existing value comparison still applies. The new schema itself is asserted in test-output-naming.R, which calls the real
# functions through `rPSTool::`. Results with several columns of one role (multi-radius calls) and file descriptors are
# returned untouched.
legacy_role <- function(name) {
  parts <- strsplit(name, "_", fixed = TRUE)[[1L]]
  code <- parts[[1L]]; raw <- "n" %in% parts[-1L]
  switch(code,
    ai = , ni = , nj = , gi = "integration",
    ac = if (raw) "choice" else "normalized",
    nb = , at = if (raw) "betweenness" else "normalized",
    nc = , anc = "node_count", td = , atd = "total_depth", tw = "total_weight", tdw = "total_depth_weight",
    rc = "reached_count", rln = "reached_length", rca = "reached_area",
    ar = "attraction_reach", ad = "attraction_distance", di = "destination_index", od = "od_betweenness",
    NULL)
}
# Old multi-result names (`choice_w500`, `integration_turner_w500`, `node_count_w500`) from the manifest of a multi-result frame:
# role, radius index, normalisation and the varying radius field with its values.
legacy_multi_names <- function(role, radius, norm, varying, values) {
  codes <- c(straight = "s", walking = "w", steps = "n", angular = "a", axmeter = "x")
  tag <- vapply(radius, function(i) if (nzchar(varying))
    paste0("_", codes[[varying]], rPSTool:::.pst_radius_value_text(values[[i]], varying == "steps")) else "", "")
  base <- ifelse(role == "normalized", paste0("choice_", norm),
          ifelse(role == "integration", paste0("integration_", norm), role))
  paste0(base, tag)
}
legacy_varying <- function(radii) {
  fields <- c("straight", "walking", "steps", "angular", "axmeter")
  v <- fields[vapply(fields, function(f) length(unique(vapply(radii, function(r) if (is.null(r[[f]])) NA_real_ else as.double(r[[f]]), 1))) > 1L, NA)]
  if (length(v)) v[[1L]] else ""
}
legacy_frame <- function(x) {
  man <- attr(x, "rpst_manifest", exact = TRUE)
  if (is.data.frame(x) && is.list(man) && !is.null(man$columns)) {   # multi-result frame
    spec <- man$columns; varying <- legacy_varying(man$radii)
    values <- if (nzchar(varying)) lapply(man$radii, function(r) r[[varying]]) else NULL
    names(x)[-1L] <- legacy_multi_names(spec$role, spec$radius, spec$normalization, varying, values)
    attr(x, "rpst_manifest") <- NULL
    return(x)
  }
  if (!is.data.frame(x)) {
    if (is.list(x) && !inherits(x, "pst_result_file")) x[] <- lapply(x, legacy_frame)
    return(x)
  }
  roles <- vapply(names(x), function(n) { r <- legacy_role(n); if (is.null(r)) NA_character_ else r }, "")
  known <- !is.na(roles)
  if (!any(known) || anyDuplicated(roles[known])) return(x)
  names(x)[known] <- roles[known]
  x
}
# Custom weights must be named (weight_name etc.). The pinned-PST numerical
# tests exercise values, not names, so the adapter supplies a descriptive
# identifier for any weight vector a test passes without one. Name behaviour
# itself is tested through explicit rPSTool:: calls in test-output-naming.R.
legacy_weight_names <- c(weights = "weight_name", attraction_values = "weight_name", line_weights = "weight_name",
                         origin_weights = "origin_weight_name",
                         destination_weights = "destination_weight_name")
legacy_default_names <- c(weights = "population", attraction_values = "capacity", line_weights = "travel_cost",
                          origin_weights = "population", destination_weights = "jobs")
legacy_wrap <- function(name) {
  real <- getExportedValue("rPSTool", name)
  function(...) {
    args <- as.list(match.call(real, as.call(c(list(as.name("real")), list(...))))[-1L])
    for (w in intersect(names(legacy_weight_names), names(args))) {
      nm <- legacy_weight_names[[w]]
      if (!is.null(args[[w]]) && !(nm %in% names(args)))
        args[[nm]] <- legacy_default_names[[w]]
    }
    legacy_frame(do.call(real, args))
  }
}
angular_integration <- legacy_wrap("angular_integration")
angular_choice <- legacy_wrap("angular_choice")
network_integration <- legacy_wrap("network_integration")
network_reach <- legacy_wrap("network_reach")
network_betweenness <- legacy_wrap("network_betweenness")
attraction_reach <- legacy_wrap("attraction_reach")
attraction_distance <- legacy_wrap("attraction_distance")
od_betweenness <- legacy_wrap("od_betweenness")
segment_group_integration <- legacy_wrap("segment_group_integration")
legacy_ni_run <- function(...) legacy_frame(rPSTool:::.pst_network_integration_run(...))
# Legacy role names for a vector of result column names (unchanged where unknown or ambiguous).
legacy_names <- function(nm) {
  roles <- vapply(nm, function(n) { r <- legacy_role(n); if (is.null(r)) NA_character_ else r }, "")
  known <- !is.na(roles)
  if (!any(known) || anyDuplicated(roles[known])) return(nm)
  nm[known] <- roles[known]
  nm
}
legacy_integration_names <- function(weights)
  c("segment_id", "integration", "node_count", "total_depth", if (weights) c("total_weight", "total_depth_weight"))
legacy_choice_names <- function(weigh_by_length, normalization)
  c("segment_id", "choice", "node_count", "total_depth", if (weigh_by_length) "total_depth_weight",
    if (normalization != "none") "normalized")
