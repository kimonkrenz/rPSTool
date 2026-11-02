# docs/spatial-io/result-files.md §13: Parquet output with Arrow nulls for Segment Betweenness and Segment Group Integration.
# Every persisted table is compared with the existing in-memory data frame (names, order, rows, R types, 8 bytes of every
# double: so typed NA vs NaN is checked) AND with the pinned direct-PST fixtures, with the null pattern derived
# independently from the fixture's own NA positions. A written NaN/Inf/-1/0 is a value, never a null; an unwritten
# diagnostic is a null, never a number.

skip_masked_file <- function() {
  skip_if_not_installed("arrow", "25.0.0")
}
ma_nullable <- function(file) unname(vapply(rs_pq(file)$GetSchema()$fields, function(f) f$nullable, NA))
ma_types <- function(file) unname(vapply(rs_pq(file)$GetSchema()$fields, function(f) f$type$ToString(), ""))
ma_nulls <- function(file, col) rs_read_parquet(file, as_data_frame = FALSE)$column(col)$null_count
ma_graph_release <- function(g) .Call(rPSTool:::C_rpst_graph_release, g$ptr)
ma_group_release <- function(g) .Call(rPSTool:::C_rpst_segment_group_graph_release, g$ptr)
# expected nullable flags of network_betweenness output by normalization (decided by the call, never by the data)
ma_flags <- function(norm) c(FALSE, FALSE, TRUE, TRUE, if (norm != "none") norm %in% c("freeman", "syntax"))

test_that("persisted Segment Betweenness equals the in-memory result and the pinned fixtures, with fixture-derived nulls", {
  skip_masked_file()
  ref <- dget(test_path("fixtures", "reach-betweenness-direct-v3.3.2.R"))
  expect_identical(ref$pst_commit, unname(rPSTool:::.pst_engine_pin()[["pst_commit"]]))
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  graphs <- lapply(ref$networks, function(rows) axial_graph(do.call(rbind, rows)))
  on.exit(for (g in graphs) ma_graph_release(g), add = TRUE)
  before <- rs_baseline()
  problems <- character(); written <- 0; seen <- c(nan = 0, null = 0, valid_nan = 0)
  note <- function(label, what) if (nzchar(what)) problems <<- c(problems, paste(label, what))
  # CRAN mode: a deterministic subset that still contains every signature (routine, distance, option set) and every edge value
  # flag of the fixture; full mode writes and compares every case.
  for (case in rpst_cases(Filter(function(c) c$routine == "betweenness", ref$cases), every = 20L,
                          by = list(rpst_case_signature), each = list(rpst_case_edges))) {
    g <- graphs[[case$network]]
    g$n_lines <- 999L                                           # editable R metadata is never the authority
    radius <- do.call(analysis_radius, case$radius)
    points <- if (is.null(case$points)) NULL else do.call(rbind, case$points)
    for (norm in c("none", names(case$normalizations))) {
      label <- paste(case$network, case$name, case$distance, norm)
      args <- list(graph = g, radius = radius, distance = case$distance, normalization = norm, weights = case$weights,
                   attraction_points = points)
      memory <- do.call(network_betweenness, args)
      out <- do.call(network_betweenness, c(args, list(output_file = file, overwrite = TRUE)))
      persisted <- rs_read(file)
      note(label, rs_diff_tables(persisted, memory))
      if (!identical(legacy_names(out$columns), names(memory)) || !identical(out$rows, nrow(memory))) note(label, "descriptor")
      if (!identical(ma_nullable(file), ma_flags(norm))) note(label, "nullable flags")
      if (!identical(ma_types(file), c("int32", "float", "int32", "float", if (norm != "none") "float"))) note(label, "types")
      # fixture parity, and nulls from the fixture's own NA positions (not from rPSTool's computation)
      note(label, rs_diff_reference(persisted$betweenness, case$score))
      if (!identical(persisted$node_count, as.integer(case$count))) note(label, "node_count")
      note(label, rs_diff_reference(persisted$total_depth, case$depth))
      if (!identical(rs_null_kind(persisted$total_depth), is.na(case$depth))) note(label, "total_depth nulls")
      if (ma_nulls(file, 1L) != 0L) note(label, "raw betweenness has nulls")
      if (ma_nulls(file, 2L) != sum(is.na(case$count))) note(label, "node_count null count")
      if (norm != "none") {
        expected <- case$normalizations[[norm]]
        note(label, rs_diff_reference(persisted$normalized, expected))
        expected_null <- if (norm == "standard") rep(FALSE, length(expected)) else is.na(expected) & !is.nan(expected)
        if (!identical(rs_null_kind(persisted$normalized), expected_null)) note(label, "normalized nulls")
        if (ma_nulls(file, 4L) != sum(expected_null)) note(label, "normalized null count")
        seen[["valid_nan"]] <- seen[["valid_nan"]] + sum(is.nan(persisted$normalized))
      }
      seen[["null"]] <- seen[["null"]] + sum(rs_null_kind(persisted$node_count))
      written <- written + 1
    }
  }
  expect_identical(problems, character())
  expect_gt(written, if (rpst_full_tests()) 500 else 60)
  expect_gt(seen[["null"]], 0)          # real unwritten diagnostics were persisted as nulls ...
  expect_gt(seen[["valid_nan"]], 0)     # ... and real written NaN (signed weights) stayed a value
  expect_true(rs_balanced(before))
})

test_that("the wrong implementations are caught: NaN stays a value, raw and standard scores are never nulled", {
  skip_masked_file()
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  g <- axial_graph(cbind(0:2, 0, 1:3, 0)); on.exit(ma_graph_release(g), add = TRUE)
  run <- function(weights, norm, distance = "walking", ...) {
    network_betweenness(g, distance = distance, normalization = norm, weights = weights, output_file = file, overwrite = TRUE, ...)
    rs_read(file)
  }
  # skipped middle origin (weight 0): raw score and standard normalisation are defined; diagnostics and Freeman/syntax are not
  p <- run(c(1, 0, 1), "freeman")
  expect_identical(p$betweenness, c(0.75, 1, 0.75)); expect_identical(ma_nulls(file, 1L), 0L)
  expect_identical(p$node_count, c(3L, NA, 3L)); expect_identical(p$normalized, c(0.75, NA, 0.75))
  p <- run(c(1, 0, 1), "standard")
  expect_identical(p$normalized, c(0, 1, 0)); expect_identical(ma_nulls(file, 4L), 0L)      # defined despite the skipped origin
  expect_identical(ma_nulls(file, 2L), 1L)                                                    # node_count still has its null
  # written NaN (negative signed weight): rows 1 and 3 are valid NaN, row 2 is a null; not "NaN means null"
  p <- run(c(1, -10, 1), "syntax")
  expect_identical(is.nan(p$normalized), c(TRUE, FALSE, TRUE))
  expect_identical(rs_null_kind(p$normalized), c(FALSE, TRUE, FALSE))
  expect_identical(ma_nulls(file, 4L), 1L)
  expect_identical(p$betweenness, c(-1.75, -4, -1.75))                                       # raw score of the skipped origin
  # everything unwritten: all diagnostics null, raw/standard still all valid, types retained
  p <- run(c(0, 0, 0), "freeman")
  expect_identical(p$node_count, rep(NA_integer_, 3)); expect_identical(p$total_depth, rep(NA_real_, 3))
  expect_identical(p$normalized, rep(NA_real_, 3)); expect_identical(typeof(p$normalized), "double")
  expect_identical(ma_nulls(file, 1L), 0L)
  p <- run(c(0, 0, 0), "standard"); expect_identical(ma_nulls(file, 4L), 0L)
  # unweighted calls write every diagnostic: no null at all, but the declared schema is unchanged
  p <- run(NULL, "syntax")
  expect_identical(ma_nulls(file, 2L), 0L); expect_identical(ma_nulls(file, 3L), 0L); expect_identical(ma_nulls(file, 4L), 0L)
  expect_identical(ma_nullable(file), ma_flags("syntax"))
})

test_that("the schema is decided by the call, so files from one analysis concatenate", {
  skip_masked_file()
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  g <- axial_graph(cbind(0:2, 0, 1:3, 0)); on.exit(ma_graph_release(g), add = TRUE)
  for (norm in c("none", "standard", "freeman", "syntax"))
    for (weights in list(NULL, c(1, 1, 1), c(1, 0, 1), c(0, 0, 0), c(2, 3, 4))) {
      network_betweenness(g, normalization = norm, weights = weights, output_file = file, overwrite = TRUE)
      expect_identical(ma_nullable(file), ma_flags(norm), info = paste(norm, paste(weights, collapse = ",")))
    }
})

test_that("persisted Segment Betweenness matches in memory for weighted sweeps, thread caps and batch layouts", {
  skip_masked_file()
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  i <- rep(1:5, times = 6); j <- rep(1:6, each = 5)
  x <- rbind(cbind(i * 10, j * 10, (i + 1) * 10, j * 10), cbind(j * 10, i * 10, j * 10, (i + 1) * 10))
  x[seq(3, nrow(x), by = 3), c(2, 4)] <- x[seq(3, nrow(x), by = 3), c(2, 4)] + 3
  g <- axial_graph(x); on.exit(ma_graph_release(g), add = TRUE)
  old <- Sys.getenv("RPST_NUM_THREADS", unset = NA_character_)
  on.exit(if (is.na(old)) Sys.unsetenv("RPST_NUM_THREADS") else Sys.setenv(RPST_NUM_THREADS = old), add = TRUE)
  problems <- character(); runs <- 0; nulls <- 0
  for (threads in c("1", "3")) {
    Sys.setenv(RPST_NUM_THREADS = threads)
    for (seed in 1:2) {
      set.seed(seed); w <- sample(c(-2, -1, 0, 0, 1, 2.5), nrow(x), replace = TRUE)
      for (distance in c("walking", "steps", "angular", "axmeter"))
        for (norm in c("none", "standard", "freeman", "syntax")) {
          args <- list(graph = g, radius = analysis_radius(steps = 3), distance = distance, normalization = norm, weights = w)
          memory <- do.call(network_betweenness, args)
          do.call(network_betweenness, c(args, list(output_file = file, overwrite = TRUE)))
          d <- rs_diff_tables(rs_read(file), memory)
          if (nzchar(d)) problems <- c(problems, paste(threads, seed, distance, norm, d))
          nulls <- nulls + sum(is.na(memory$node_count)); runs <- runs + 1
        }
    }
  }
  expect_identical(problems, character()); expect_gt(runs, 60); expect_gt(nulls, 0)
  # batch layouts (non-byte-aligned row groups): the same table in every layout
  Sys.setenv(RPST_NUM_THREADS = "1")
  memory <- network_betweenness(g, analysis_radius(steps = 3), "steps", "freeman", w)
  cols <- names(memory)
  for (batch in c(1, 7, 13, 59, 60, 61, 1000)) {
    rPSTool:::.pst_write_result_file(file, TRUE, columns = cols, expected_rows = NA_real_, batch_rows = batch,
      export = function(stream, batch_rows) .Call(rPSTool:::C_rpst_betweenness_weighted_stream, g$ptr, analysis_radius(steps = 3), "steps",
                                                  "freeman", w, NULL, stream, cols, character(), character(), batch_rows))
    rs_expect_same(rs_read(file), memory)
    expect_identical(rs_pq(file)$num_row_groups, as.integer(ceiling(nrow(x) / min(batch, 1048576))))
  }
})

test_that("Segment Betweenness attraction origins persist identically from matrix and sf input", {
  skip_masked_file()
  skip_if_not_installed("sf")
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  g <- axial_graph(cbind(0:5, 0, 1:6, 0)); on.exit(ma_graph_release(g), add = TRUE)
  pts <- rbind(c(0.5, 0.2), c(0.6, 0.1), c(4.5, 0.3))                  # lines 2..4 and 6 receive no attraction
  for (norm in c("none", "standard", "freeman", "syntax")) {
    memory <- network_betweenness(g, normalization = norm, attraction_points = pts)
    network_betweenness(g, normalization = norm, attraction_points = pts, output_file = file, overwrite = TRUE)
    rs_expect_same(rs_read(file), memory)
    expect_gt(sum(is.na(memory$node_count)), 0)
    network_betweenness(g, normalization = norm, attraction_points = sf::st_as_sf(as.data.frame(pts), coords = c(1, 2)),
                    output_file = file, overwrite = TRUE)
    rs_expect_same(rs_read(file), memory)
  }
})

test_that("Segment Betweenness file route rejects bad calls before any file exists and never damages an existing file", {
  skip_masked_file()
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  g <- axial_graph(cbind(0:2, 0, 1:3, 0)); s <- segment_graph(cbind(0:2 * 3, 0, 1:3 * 3, 0))
  on.exit({ ma_graph_release(g); rs_native("segment_graph_release", s$ptr) }, add = TRUE)
  before <- rs_baseline()
  expect_identical(names(formals(rPSTool::network_betweenness)), c("graph", "radius", "distance", "normalization", "weights",
                                                      "attraction_points", "output_file", "overwrite", "spatial_output_file", "weight_name"))
  bad <- list(function() network_betweenness(g, output_file = file, overwrite = NA),
              function() network_betweenness(g, distance = "bogus", output_file = file),
              function() network_betweenness(g, normalization = "bogus", output_file = file),
              function() network_betweenness(g, weights = c(1, 2), output_file = file),
              function() network_betweenness(g, weights = c(1, NA, 1), output_file = file),
              function() network_betweenness(g, radius = list(), output_file = file),
              function() network_betweenness(s, output_file = file),
              function() network_betweenness(g, output_file = ""),
              function() network_betweenness(g, output_file = dir))
  for (f in bad) expect_error(f())
  expect_identical(list.files(dir, all.files = TRUE, no.. = TRUE), character())
  network_betweenness(g, weights = c(1, 0, 1), output_file = file)
  md5 <- rs_md5(file)
  expect_error(network_betweenness(g, output_file = file), "already exists")
  expect_error(network_betweenness(s, output_file = file, overwrite = TRUE))
  Sys.setenv(RPST_NUM_THREADS = "0"); on.exit(Sys.unsetenv("RPST_NUM_THREADS"), add = TRUE)
  expect_error(network_betweenness(g, output_file = file, overwrite = TRUE), "RPST_NUM_THREADS")   # native failure after validation
  Sys.unsetenv("RPST_NUM_THREADS")
  expect_identical(rs_md5(file), md5); expect_identical(rs_leftovers(dir), character())
  # released and deserialised graphs
  copy <- unserialize(serialize(g, NULL))
  expect_error(network_betweenness(copy, output_file = file, overwrite = TRUE), "live|pst_graph")
  expect_identical(rs_md5(file), md5)
  expect_true(rs_balanced(before))
})

test_that("Segment Betweenness metadata records the call, the native size and no input data", {
  skip_masked_file(); skip_if_not_installed("jsonlite")
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  g <- axial_graph(cbind(0:2, 0, 1:3, 0)); on.exit(ma_graph_release(g), add = TRUE)
  g$n_lines <- 999L
  network_betweenness(g, analysis_radius(steps = 2), "walking", "freeman", weights = c(1.2345678, 0, 1), output_file = file)
  md <- rs_pq(file)$GetSchema()$metadata
  expect_identical(md[["rpst:function"]], "network_betweenness"); expect_identical(md[["rpst:graph_type"]], "axial")
  expect_identical(md[["rpst:graph_rows"]], "3")
  p <- jsonlite::fromJSON(md[["rpst:parameters"]])
  expect_identical(p$distance, "walking"); expect_identical(p$normalization, "freeman"); expect_equal(p$weights, 3)
  expect_equal(p$radius$steps, 2)
  expect_false(grepl("1.2345678", md[["rpst:parameters"]], fixed = TRUE))       # sizes only, never the weights themselves
})

# ---- Segment Group Integration ---------------------------------------------------------------------------------------

test_that("persisted Segment Group Integration equals the in-memory result and the pinned fixtures (all 280 in the full suite)", {
  skip_masked_file()
  ref <- dget(test_path("fixtures", "segment-groups-direct-v3.3.2.R"))
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  segments <- lapply(ref$networks, function(rows) segment_graph(do.call(rbind, rows)))
  on.exit(for (s in segments) rs_native("segment_graph_release", s$ptr), add = TRUE)
  before <- rs_baseline()
  problems <- character(); all_null <- 0; valid_nan <- 0; valid_inf <- 0; minus_one <- 0
  # CRAN mode: the same kind of deterministic subset (all 280 cases in full mode).
  for (k in rpst_cases(seq_along(ref$integrations), every = 10L, by = list(function(k) rpst_case_signature(ref$integrations[[k]])),
                       each = list(function(k) rpst_case_edges(ref$integrations[[k]])))) {
    case <- ref$integrations[[k]]
    g <- segment_group_graph(segments[[case$network]], case$ids)
    g$n_groups <- 999L
    radius <- do.call(analysis_radius, case$radius)
    memory <- segment_group_integration(g, radius)
    out <- segment_group_integration(g, radius, output_file = file, overwrite = TRUE)
    persisted <- rs_read(file)
    note <- function(what) if (nzchar(what)) problems <<- c(problems, paste(k, what))
    note(rs_diff_tables(persisted, memory))
    if (!identical(legacy_names(out$columns), names(memory)) || !identical(out$rows, nrow(memory))) note("descriptor")
    if (!identical(ma_nullable(file), c(FALSE, TRUE, TRUE, TRUE))) note("nullable flags")
    if (!identical(ma_types(file), c("int32", "float", "int32", "float"))) note("types")
    if (!identical(persisted$group_id, seq_along(case$node_count))) note("group_id")
    # nulls from the fixture's own NA positions, identical across the three paired columns
    expected_null <- is.na(case$node_count)
    for (col in c("integration", "node_count", "total_depth"))
      if (!identical(is.na(persisted[[col]]) & !is.nan(persisted[[col]]), expected_null)) note(paste(col, "nulls"))
    if (!identical(persisted$node_count, as.integer(case$node_count))) note("node_count")
    note(rs_diff_reference(persisted$integration, case$integration, 1e-6))
    note(rs_diff_reference(persisted$total_depth, case$total_depth, 1e-6))
    if (all(expected_null)) all_null <- all_null + 1
    valid_nan <- valid_nan + sum(is.nan(persisted$integration)); valid_inf <- valid_inf + sum(is.infinite(persisted$integration))
    minus_one <- minus_one + sum(persisted$integration == -1, na.rm = TRUE)
    ma_group_release(g)
  }
  expect_identical(problems, character())
  expect_gt(all_null, if (rpst_full_tests()) 90 else 5)
  expect_gt(valid_nan, 0); expect_gt(valid_inf, 0); expect_gt(minus_one, 0)
  expect_true(rs_balanced(before))
})

test_that("group integration: sentinel traps, gaps and isolated groups stay valid, only unwritten rows are null", {
  skip_masked_file()
  ref <- dget(test_path("fixtures", "segment-groups-direct-v3.3.2.R"))
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  segments <- lapply(ref$networks, function(rows) segment_graph(do.call(rbind, rows)))
  on.exit(for (s in segments) rs_native("segment_graph_release", s$ptr), add = TRUE)
  persist <- function(k) {
    case <- ref$integrations[[k]]
    g <- segment_group_graph(segments[[case$network]], case$ids); on.exit(ma_group_release(g), add = TRUE)
    segment_group_integration(g, do.call(analysis_radius, case$radius), output_file = file, overwrite = TRUE)
    rs_read(file)
  }
  p <- persist(46)       # steps 0 on gapped ids: every group has a written -1; a "-1 means missing" sentinel would null them
  expect_identical(p$integration, rep(-1, 5)); expect_identical(ma_nulls(file, 2L), 0L)
  p <- persist(42)       # NaN, written -1 with count 0 (empty groups), Inf, group-id gaps
  expect_identical(is.nan(p$integration), c(TRUE, FALSE, FALSE, FALSE, TRUE))
  expect_identical(p$integration[2:4], c(-1, Inf, -1)); expect_identical(p$node_count, c(2L, 0L, 3L, 0L, 2L))
  expect_identical(ma_nulls(file, 2L), 0L); expect_identical(ma_nulls(file, 3L), 0L)
  p <- persist(12)       # NaN and Inf together, all valid
  expect_true(any(is.nan(p$integration)) && any(is.infinite(p$integration))); expect_identical(ma_nulls(file, 2L), 0L)
  p <- persist(191)      # an isolated group last: written -1, 0, 0
  expect_identical(c(p$integration[4], p$node_count[4], p$total_depth[4]), c(-1, 0L, 0))
  p <- persist(206)      # isolated group first (ids 4,3,2,1): order and validity preserved
  expect_identical(p$node_count[1], 0L); expect_identical(ma_nulls(file, 2L), 0L)
  p <- persist(1)        # a graph without native nodes: every row null in all three columns, types retained
  expect_identical(p$integration, NA_real_); expect_identical(p$node_count, NA_integer_); expect_identical(p$total_depth, NA_real_)
  p <- persist(161)      # two groups, none with nodes
  expect_identical(p$node_count, rep(NA_integer_, 2)); expect_identical(ma_nulls(file, 1L), 2L)
  expect_identical(ma_nullable(file), c(FALSE, TRUE, TRUE, TRUE))
})

test_that("group integration: unsupported radii, wrong graph family and dead pointers fail before any file", {
  skip_masked_file()
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  s <- segment_graph(cbind(0:4 * 3, 0, 1:5 * 3, 0)); a <- axial_graph(cbind(0:2, 0, 1:3, 0))
  g <- segment_group_graph(s, 1:5)
  on.exit({ ma_group_release(g); rs_native("segment_graph_release", s$ptr); ma_graph_release(a) }, add = TRUE)
  before <- rs_baseline()
  expect_identical(names(formals(rPSTool::segment_group_integration)), c("graph", "radius", "output_file", "overwrite"))
  for (field in c("straight", "angular", "axmeter"))
    expect_error(segment_group_integration(g, do.call(analysis_radius, setNames(list(1), field)), output_file = file),
                 "only walking and steps")
  expect_error(segment_group_integration(s, output_file = file), "pst_segment_group_graph")
  expect_error(segment_group_integration(a, output_file = file), "pst_segment_group_graph")
  expect_error(segment_group_integration(g, output_file = file, overwrite = NA), "overwrite")
  expect_error(segment_group_integration(g, output_file = ""), "output_file")
  expect_identical(list.files(dir, all.files = TRUE, no.. = TRUE), character())
  segment_group_integration(g, output_file = file); md5 <- rs_md5(file)
  expect_error(segment_group_integration(g, output_file = file), "already exists")
  expect_error(segment_group_integration(g, analysis_radius(angular = 1), output_file = file, overwrite = TRUE), "only walking")
  Sys.setenv(RPST_NUM_THREADS = "0"); on.exit(Sys.unsetenv("RPST_NUM_THREADS"), add = TRUE)
  expect_error(segment_group_integration(g, output_file = file, overwrite = TRUE), "RPST_NUM_THREADS")
  Sys.unsetenv("RPST_NUM_THREADS")
  copy <- unserialize(serialize(g, NULL))
  expect_error(segment_group_integration(copy, output_file = file, overwrite = TRUE), "no longer live|live")
  expect_identical(rs_md5(file), md5); expect_identical(rs_leftovers(dir), character())
  # the file outlives its graph
  g2 <- segment_group_graph(s, c(1, 1, 2, 2, 3)); other <- file.path(dir, "o.parquet")
  segment_group_integration(g2, output_file = other); ma_group_release(g2)
  expect_identical(nrow(as.data.frame(rs_read_parquet(other))), 3L)
  expect_true(rs_balanced(before))
})

test_that("group integration metadata records the segment-group graph, its native group count and the radius", {
  skip_masked_file(); skip_if_not_installed("jsonlite")
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  s <- segment_graph(cbind(0:4 * 3, 0, 1:5 * 3, 0)); on.exit(rs_native("segment_graph_release", s$ptr), add = TRUE)
  g <- segment_group_graph(s, c(1, 3, 3, 3, 5)); on.exit(ma_group_release(g), add = TRUE)
  g$n_groups <- 999L
  segment_group_integration(g, analysis_radius(steps = 2), output_file = file)
  md <- rs_pq(file)$GetSchema()$metadata
  expect_identical(md[["rpst:function"]], "segment_group_integration")
  expect_identical(md[["rpst:graph_type"]], "segment_group"); expect_identical(md[["rpst:graph_rows"]], "5")
  expect_match(md[["rpst:order"]], "group id order")
  expect_equal(jsonlite::fromJSON(md[["rpst:parameters"]])$radius$steps, 2)
})

test_that("mask disagreement and impossible counts are rejected by the production file conversion, valid mixed masks persist", {
  skip_masked_file()
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  cols <- c("group_id", "integration", "node_count", "total_depth")
  hook <- function(score, count, depth)
    rPSTool:::.pst_write_result_file(file, TRUE, columns = cols, expected_rows = length(score), batch_rows = 3,
      export = function(stream, batch_rows) .Call(rPSTool:::C_rpst_segment_group_output_test_stream, score, count, depth, stream,
                                                  cols, character(), character(), batch_rows))
  before <- rs_baseline()
  expect_error(hook(c(1, 2), c(1L, NA_integer_), c(0, 0)), "write masks are inconsistent")
  expect_error(hook(c(1, 2), c(1L, 0L), c(0, -Inf)), "write masks are inconsistent")
  expect_error(hook(1, 2L, 0), "invalid group node count")
  expect_false(file.exists(file)); expect_identical(rs_leftovers(dir), character())
  # a mixed mask never comes from PST, but the conversion must still be exact: the score is not a sentinel
  for (seed in c(17, 29, -Inf, Inf, NaN, NA_real_)) {
    hook(c(seed, -1, 0, NaN, Inf, 5, 6), c(NA_integer_, 0L, 1L, 2L, 3L, 4L, 5L), c(-Inf, 0, 0, 1, 2, 3, 4))
    p <- rs_read(file)
    expect_identical(rs_null_kind(p$integration), c(TRUE, rep(FALSE, 6)))
    expect_identical(p$integration[2:7], c(-1, 0, NaN, Inf, 5, 6))
    expect_identical(p$node_count, c(NA_integer_, 0L, 1L, 2L, 3L, 4L, 5L))
    expect_identical(p$total_depth, c(NA_real_, 0, 0, 1, 2, 3, 4))
    expect_identical(rs_pq(file)$num_row_groups, 3L)    # 7 rows in batches of 3
  }
  expect_true(rs_balanced(before))
})
