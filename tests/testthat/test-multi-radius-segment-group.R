# Multi-radius Segment Group Integration (docs/compatibility/multi-radius.md). Every radius column must equal the independently executed scalar
# call with that radius, EXACTLY (values, types and the NA pattern: the scalar function is deterministic across worker caps, see
# test-segment-groups.R); PST runs once per radius; every radius is validated before the first run; the file route holds the table the
# in-memory route returns. The Parquet checks need the optional arrow package and are skipped (not weakened) where it is missing; the
# native stream itself is still exercised below through the Arrow stream producer.

sg_chain <- function(n = 5L) cbind(0:(n - 1L) * 3, 0, 1:n * 3, 0)
# connected singleton groups plus one group without native nodes (PST writes -1, 0, 0 there)
sg_isolated <- function() { s <- segment_graph(rbind(sg_chain(3), c(10, 0, 11, 0))); segment_group_graph(s, c(1:3, 4L)) }
sg_connected <- function(n = 7L) segment_group_graph(segment_graph(sg_chain(n)), seq_len(n))
# one group: PST writes no outputs at all, so every value is NA in every radius
sg_nonodes <- function() segment_group_graph(segment_graph(sg_chain(5L)), rep(1L, 5L))
sg_ring <- function() {
  s <- segment_graph(rbind(c(0, 0, 4, 0), c(4, 0, 4, 4), c(4, 4, 0, 4), c(0, 4, 0, 0), c(4, 0, 8, 0), c(8, 0, 8, 4), c(8, 4, 4, 4)))
  segment_group_graph(s, c(1, 2, 3, 4, 5, 6, 7))
}
sg_counts <- function(reset = FALSE) .Call(rPSTool:::C_rpst_axial_instrumentation, reset, NULL)[[8L]]
sg_fail_after <- function(k) invisible(.Call(rPSTool:::C_rpst_axial_instrumentation, FALSE, as.double(k)))

sg_expect_matches_scalar <- function(multi, g, radius) {
  plan <- rPSTool:::.pst_radius_plan(radius, FALSE)
  manifest <- attr(multi, "rpst_manifest")
  expect_false(is.null(manifest))
  expect_identical(names(multi)[[1L]], "group_id")
  expect_identical(multi$group_id, seq_len(g$n_groups))
  expect_identical(names(multi), c("group_id", manifest$columns$name))
  for (i in seq_along(plan$configs)) {
    scalar <- segment_group_integration(g, plan$configs[[i]])
    expect_null(attr(scalar, "rpst_manifest"))     # a scalar call keeps the scalar schema
    expect_identical(names(scalar)[[1L]], "group_id")
    for (nm in setdiff(names(scalar), "group_id")) {
      expect_true(nm %in% names(multi), info = nm)
      expect_identical(multi[[nm]], scalar[[nm]], info = nm)           # values, type and NA pattern, exactly
    }
    expect_identical(manifest$columns$name[manifest$columns$radius == i], setdiff(names(scalar), "group_id"))
  }
}

test_that("every radius column equals the scalar call for each radius field, fixed limit and graph", {
  graphs <- list(connected = sg_connected(), isolated = sg_isolated(), ring = sg_ring())
  radii <- list(analysis_radius(steps = c(0, 1, 2, 3)), analysis_radius(steps = c(3, 1)),
                analysis_radius(walking = c(0, 2.5, 4, 100)), analysis_radius(walking = c(4, 12), steps = 2),
                analysis_radius(steps = c(1, 4), walking = 7))
  for (nm in names(graphs)) for (i in seq_along(radii)) {
    multi <- segment_group_integration(graphs[[nm]], radii[[i]])
    sg_expect_matches_scalar(multi, graphs[[nm]], radii[[i]])
    expect_identical(unname(vapply(multi[-1L], typeof, "")), rep(c("double", "integer", "double"), length(rPSTool:::.pst_radius_plan(radii[[i]], FALSE)$configs)))
  }
})

test_that("missing outputs are decided per radius: no-node graphs are NA everywhere, written -1/0 are kept", {
  multi <- segment_group_integration(sg_nonodes(), analysis_radius(steps = c(0, 1, 5)))
  expect_identical(nrow(multi), 1L)
  for (nm in names(multi)[-1L]) expect_true(is.na(multi[[nm]]), info = nm)
  expect_identical(unname(vapply(multi[-1L], typeof, "")), rep(c("double", "integer", "double"), 3L))
  multi <- segment_group_integration(sg_isolated(), analysis_radius(steps = c(0, 1, 2)))
  gi <- grep("^gi_", names(multi), value = TRUE); nc <- grep("^nc_", names(multi), value = TRUE); td <- grep("^td_", names(multi), value = TRUE)
  expect_length(gi, 3L)
  for (i in 1:3) {
    expect_identical(multi[[gi[[i]]]][[4L]], -1)          # the isolated group: PST's written -1, 0, 0
    expect_identical(multi[[nc[[i]]]][[4L]], 0L)
    expect_identical(multi[[td[[i]]]][[4L]], 0)
  }
  written <- segment_group_integration(sg_isolated(), analysis_radius(steps = c(1, 2)))
  expect_false(any(is.na(unlist(written)) & !is.nan(unlist(written))))   # written NaN/Inf/-1/0 are values, never missing
  expect_true(any(is.nan(written$gi_rs1)) && any(is.infinite(written$gi_rs2)))
})

test_that("the pinned-PST fixture networks give scalar-equal multi-radius results (finite, NaN, Inf, -1 and 0 values)", {
  reference <- dget(file.path("fixtures", "segment-groups-direct-v3.3.2.R"))
  segments <- lapply(reference$networks, function(rows) segment_graph(do.call(rbind, rows)))
  seen <- 0L
  for (case in rpst_cases(reference$integrations, every = 40L, by = list(rpst_case_signature), each = list(rpst_case_edges))) {
    g <- segment_group_graph(segments[[case$network]], case$ids)
    for (radius in list(analysis_radius(steps = c(0, 1, 2, 5)), analysis_radius(walking = c(0, 3, 50), steps = 4)))
      sg_expect_matches_scalar(segment_group_integration(g, radius), g, radius)
    seen <- seen + 1L
  }
  expect_gt(seen, 0L)
})

test_that("a single radius or a one-element vector keeps the scalar schema", {
  g <- sg_connected()
  one <- segment_group_integration(g, analysis_radius(steps = 2))
  expect_null(attr(one, "rpst_manifest"))
  expect_identical(one, segment_group_integration(g, analysis_radius(steps = c(2))))
  expect_identical(names(one), c("group_id", "gi_rs2", "nc_rs2", "td_rs2"))
  multi <- segment_group_integration(g, analysis_radius(steps = c(2, 3)))
  expect_identical(names(multi), c("group_id", "gi_rs2", "nc_rs2", "td_rs2", "gi_rs3", "nc_rs3", "td_rs3"))
  expect_identical(multi$gi_rs2, one$gi_rs2)
  manifest <- attr(multi, "rpst_manifest")
  expect_identical(manifest$columns$radius, rep(1:2, each = 3L))
  expect_identical(manifest$columns$role, rep(c("integration", "node_count", "total_depth"), 2L))
  expect_identical(length(manifest$radii), 2L)
})

test_that("every radius is validated before the first PST run", {
  g <- sg_connected()
  # (the radius is built inside the assertion: analysis_radius() itself rejects some of these at construction, the rest reach the function)
  invalid <- list(
    list(quote(analysis_radius(straight = c(1, 2))), "does not support the straight"),
    list(quote(analysis_radius(angular = c(90, 180))), "does not support the angular"),
    list(quote(analysis_radius(axmeter = c(5, 9))), "does not support the axmeter"),
    list(quote(analysis_radius(walking = c(5, 9), straight = 4)), "does not support the straight"),
    list(quote(analysis_radius(walking = c(5, 9), angular = 90)), "does not support the angular"),
    list(quote(analysis_radius(steps = c(1, 1))), "duplicate"),
    list(quote(analysis_radius(walking = c(5, 5))), "duplicate"),
    list(quote(analysis_radius(walking = c(1, 2), steps = c(1, 2))), "At most one"),
    list(quote(analysis_radius(steps = c(1, NA))), "NA"),
    list(quote(analysis_radius(walking = c(1, -2))), "non-negative"),
    list(quote(analysis_radius(steps = c(1, 2.5))), "whole"))
  sg_counts(TRUE)
  for (case in invalid) expect_error(segment_group_integration(g, eval(case[[1L]])), case[[2L]], info = deparse(case[[1L]]))
  expect_error(segment_group_integration(g, list(walking = c(1, 2))), "analysis_radius")
  expect_identical(sg_counts(), 0)
  # the scalar rule is unchanged: a straight scalar radius is refused by the native layer
  expect_error(segment_group_integration(g, analysis_radius(straight = 3)), "supports only walking and steps")
  expect_identical(sg_counts(), 0)
  # a failing request never creates output
  dir <- tempfile("sg"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  expect_error(segment_group_integration(g, analysis_radius(straight = c(1, 2)), output_file = file.path(dir, "x.parquet")), "does not support")
  expect_identical(list.files(dir, all.files = TRUE, no.. = TRUE), character())
  expect_identical(sg_counts(), 0)
})

test_that("PST runs once per radius and a failure on a later radius leaves the graph usable", {
  g <- sg_ring()
  sg_counts(TRUE)
  segment_group_integration(g, analysis_radius(steps = c(1, 2, 3, 4)))
  expect_identical(sg_counts(), 4)
  segment_group_integration(g, analysis_radius(steps = 2))   # a scalar call uses the scalar native entry point
  expect_identical(sg_counts(), 4)
  sg_counts(TRUE)
  sg_fail_after(2)
  expect_error(segment_group_integration(g, analysis_radius(steps = c(1, 2, 3, 4))), "injected native failure")
  sg_fail_after(-1)
  expect_identical(sg_counts(), 2)
  after <- segment_group_integration(g, analysis_radius(steps = c(1, 2)))
  expect_identical(after$gi_rs1, segment_group_integration(g, analysis_radius(steps = 1))$gi_rs1)
  expect_identical(.Call(rPSTool:::C_rpst_segment_group_graph_info, g$ptr), 7L)
})

test_that("the central worker policy applies to the multi-radius call, including no-node graphs", {
  connected <- sg_ring(); no_nodes <- sg_nonodes()
  r <- analysis_radius(steps = c(1, 2, 3))
  withr::local_envvar(RPST_NUM_THREADS = "1")
  base <- segment_group_integration(connected, r)
  for (cap in c("1", "2", "3", "4294967295")) {
    withr::local_envvar(RPST_NUM_THREADS = cap)
    expect_identical(segment_group_integration(connected, r), base)
    expect_true(all(is.na(unlist(segment_group_integration(no_nodes, r)[-1L]))))
  }
  for (bad in c("0", "-1", "1.5", "2x", " 2", "4294967296")) {
    withr::local_envvar(RPST_NUM_THREADS = bad)
    expect_error(segment_group_integration(connected, r), "RPST_NUM_THREADS")
    expect_error(segment_group_integration(no_nodes, r), "RPST_NUM_THREADS")
  }
})

test_that("the multi-radius native stream runs once per radius, reports the group count and fails cleanly", {
  g <- sg_isolated(); ptr <- g$ptr
  plan <- rPSTool:::.pst_radius_plan(analysis_radius(steps = c(0, 1, 2)), FALSE)
  columns <- c("group_id", rPSTool:::.pst_nm_names(unlist(lapply(plan$configs, rPSTool:::.pst_nm_segment_group_integration), recursive = FALSE)))
  expect_length(columns, 10L)
  run <- function(cols = columns) {
    stream <- .Call(rPSTool:::C_rpst_arrow_stream_new)
    on.exit(.Call(rPSTool:::C_rpst_arrow_stream_free, stream))
    .Call(rPSTool:::C_rpst_segment_group_integration_multi_stream, ptr, plan$configs, stream, cols, "rpst:test", "x", 4)
  }
  sg_counts(TRUE)
  expect_identical(run(), 4)
  expect_identical(sg_counts(), 3)
  expect_error(run(columns[-1L]), "name")                      # a wrong column count is refused
  sg_counts(TRUE)
  sg_fail_after(1)
  expect_error(run(), "injected native failure")
  sg_fail_after(-1)
  expect_identical(sg_counts(), 1)
  expect_identical(run(), 4)
  expect_error(.Call(rPSTool:::C_rpst_segment_group_integration_multi_stream, ptr, list(analysis_radius(straight = 1)), NULL, columns, "a", "b", 4))
})

test_that("Segment Group Integration is registered as a multi-radius analysis and documented as such", {
  expect_true("segment_group_integration" %in% rPSTool:::.pst_multi_radius_functions)
  expect_match(paste(rPSTool:::.pst_multi_radius_list(), collapse = ""), "segment_group_integration()", fixed = TRUE)
  expect_error(rPSTool:::.pst_validate_radius(analysis_radius(steps = c(1, 2))), "supported only by")
})

skip_sg_parquet <- function() {
  skip_if_not_installed("jsonlite"); skip_if_not_installed("arrow", "25.0.0")
}

test_that("Parquet output of the multi-radius call equals the in-memory result, with nullable NA and schema-2 metadata", {
  skip_sg_parquet()
  dir <- tempfile("sg"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE))
  for (nm in c("isolated", "ring", "nonodes")) {
    g <- switch(nm, isolated = sg_isolated(), ring = sg_ring(), nonodes = sg_nonodes())
    r <- analysis_radius(steps = c(0, 1, 3))
    frame <- segment_group_integration(g, r)
    path <- file.path(dir, paste0(nm, ".parquet"))
    res <- segment_group_integration(g, r, output_file = path)
    expect_s3_class(res, "pst_result_file")
    expect_identical(res$columns, names(frame))
    expect_identical(res$rows, nrow(frame))
    t <- rs_read_parquet(path, as_data_frame = FALSE)
    expect_identical(names(t), names(frame))
    d <- as.data.frame(t)
    expect_identical(d$group_id, frame$group_id)
    for (col in setdiff(names(frame), "group_id")) {
      expect_identical(is.na(d[[col]]), is.na(frame[[col]]), info = col)
      expect_identical(is.nan(d[[col]]), is.nan(frame[[col]]), info = col)
      expect_identical(as.numeric(d[[col]]), as.numeric(frame[[col]]), info = col)
    }
    meta <- t$schema$metadata
    expect_identical(meta[["rpst:schema"]], "2")
    expect_identical(meta[["rpst:function"]], "segment_group_integration")
    expect_identical(meta[["rpst:graph_type"]], "segment_group")
    expect_identical(meta[["rpst:radius_varying"]], "steps")
    cols <- jsonlite::fromJSON(meta[["rpst:columns"]], simplifyVector = FALSE)
    expect_identical(vapply(cols, function(x) x$name, ""), setdiff(names(frame), "group_id"))
    expect_identical(vapply(cols, function(x) x$radius, 1), rep(1:3, each = 3L) + 0)
    expect_error(segment_group_integration(g, r, output_file = path), "already exists")
  }
  g <- sg_ring(); r <- analysis_radius(steps = c(1, 2, 3))
  path <- file.path(dir, "ring.parquet"); md5 <- unname(tools::md5sum(path))
  sg_fail_after(1)
  expect_error(segment_group_integration(g, r, output_file = path, overwrite = TRUE), "injected native failure")
  sg_fail_after(-1)
  expect_identical(unname(tools::md5sum(path)), md5)       # the existing file is untouched
  fresh <- file.path(dir, "fresh.parquet")
  sg_fail_after(2)
  expect_error(segment_group_integration(g, r, output_file = fresh), "injected native failure")
  sg_fail_after(-1)
  expect_false(file.exists(fresh))
  expect_identical(grep("rpst|tmp", list.files(dir, all.files = TRUE, no.. = TRUE), value = TRUE, ignore.case = TRUE), character())
  scalar <- file.path(dir, "scalar.parquet")
  segment_group_integration(g, analysis_radius(steps = 2), output_file = scalar)
  expect_identical(rs_read_parquet(scalar, as_data_frame = FALSE)$schema$metadata[["rpst:schema"]], "1")
  # spatial output stays unsupported for segment groups
  expect_error(segment_group_integration(g, r, spatial_output_file = file.path(dir, "x.parquet")), "unused argument")
})
