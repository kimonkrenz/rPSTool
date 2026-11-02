# docs/spatial-io/result-files.md: direct Parquet persistence of Angular Integration and Angular Choice. Every persisted
# table is compared with the existing in-memory data frame (names, order, rows, R types, values and the raw bytes of
# every double) and with the pinned direct-PST reference. The Arrow ownership protocol itself is tested in
# test-result-stream.R.

skip_result_file <- function() {
  skip_if_not_installed("arrow", "25.0.0")
}
rf_compare <- function(actual, expected, tolerance = 3e-6) {
  expected <- as.double(unlist(expected))
  expect_identical(is.nan(actual), is.nan(expected))
  expect_identical(is.infinite(actual), is.infinite(expected))
  expect_identical(actual[!is.finite(expected)], expected[!is.finite(expected)])
  expect_equal(actual[is.finite(expected)], expected[is.finite(expected)], tolerance = tolerance)
}
test_that("persisted angular results equal the in-memory results and the direct-PST reference for the selected control combinations (all of them in the full suite)", {
  skip_result_file()
  ref <- dget(test_path("fixtures", "angular-controls-direct-v3.3.2.R"))
  expect_identical(ref$pst_commit, unname(rPSTool:::.pst_engine_pin()[["pst_commit"]]))
  old <- Sys.getenv("RPST_NUM_THREADS", unset = NA_character_)
  on.exit(if (is.na(old)) Sys.unsetenv("RPST_NUM_THREADS") else Sys.setenv(RPST_NUM_THREADS = old), add = TRUE)
  Sys.setenv(RPST_NUM_THREADS = "1")
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "result.parquet")
  graphs <- list()
  on.exit(for (g in graphs) rs_native("segment_graph_release", g$ptr), add = TRUE)
  nan <- 0; inf <- 0; written <- 0; problems <- character()
  note <- function(label, what) if (nzchar(what)) problems <<- c(problems, paste(label, what))
  for (case in rpst_cases(ref$cases, every = 60L,
                           by = list(function(x) paste(x$graph$name, x$routine, x$weighted), function(x) paste(x$routine, x$weighted, rpst_radius_class(x)),
                                     function(x) x$threshold, function(x) x$precision, function(x) paste(x$routine, x$weighted, x$threshold, x$precision)))) {
    name <- case$graph$name
    if (is.null(graphs[[name]])) graphs[[name]] <- segment_graph(matrix(unlist(case$graph$x), ncol = 4, byrow = TRUE))
    g <- graphs[[name]]
    args <- list(graph = g, radius = do.call(analysis_radius, case$radius), weigh_by_length = case$weighted,
                 angle_threshold = case$threshold, angle_precision = case$precision)
    for (norm in names(case$normalized)) {
      label <- paste(case$routine, name, norm, written)
      args$normalization <- norm
      if (case$routine == "integration") {
        args$weight_outputs <- TRUE
        memory <- do.call(angular_integration, args)
        out <- do.call(angular_integration, c(args, list(output_file = file, overwrite = TRUE)))
      } else {
        memory <- do.call(angular_choice, args)
        out <- do.call(angular_choice, c(args, list(output_file = file, overwrite = TRUE)))
      }
      persisted <- rs_read(file)
      note(label, rs_diff_tables(persisted, memory))
      if (!identical(legacy_names(out$columns), names(memory)) || !identical(out$rows, nrow(memory))) note(label, "descriptor")
      if (case$routine == "integration") {
        note(label, rs_diff_reference(persisted$integration, case$normalized[[norm]]))
        note(label, rs_diff_reference(persisted$total_weight, case$weights))
        note(label, rs_diff_reference(persisted$total_depth_weight, case$depth_weights))
      } else {
        note(label, rs_diff_reference(persisted$choice, case$scores))
        note(label, rs_diff_reference(persisted$normalized, case$normalized[[norm]]))
        if (case$weighted) note(label, rs_diff_reference(persisted$total_depth_weight, case$depth_weights))
      }
      if (!identical(persisted$segment_id, seq_along(case$counts))) note(label, "segment_id")
      if (!identical(persisted$node_count, as.integer(unlist(case$counts)))) note(label, "node_count")
      note(label, rs_diff_reference(persisted$total_depth, case$depths))
      for (column in persisted) if (is.double(column)) { nan <- nan + sum(is.nan(column)); inf <- inf + sum(is.infinite(column)) }
      written <- written + 1
    }
  }
  expect_identical(problems, character())
  expect_gt(written, if (rpst_full_tests()) 3000 else 100)   # every case in full mode; the thinned subset otherwise
  expect_gt(inf, 0)     # real PST Inf values were persisted and compared byte for byte with the in-memory result
  expect_identical(nan, 0)  # the reference holds no NaN; NaN and -0 bit patterns are covered by the synthetic producer tests
})

test_that("column selection, parameters and worker counts follow the in-memory contract exactly", {
  skip_result_file()
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  g <- rf_graph(); on.exit(rs_native("segment_graph_release", g$ptr), add = TRUE)
  old <- Sys.getenv("RPST_NUM_THREADS", unset = NA_character_)
  on.exit(if (is.na(old)) Sys.unsetenv("RPST_NUM_THREADS") else Sys.setenv(RPST_NUM_THREADS = old), add = TRUE)
  problems <- character(); runs <- 0
  for (threads in c("1", "3")) {
    Sys.setenv(RPST_NUM_THREADS = threads)
    for (weigh in c(FALSE, TRUE)) for (wo in c(FALSE, TRUE)) for (norm in c("turner", "syntax", "hillier"))
      for (radius in list(NULL, analysis_radius(steps = 2), analysis_radius(walking = 25), analysis_radius(angular = 1.5)))
        for (settings in list(c(0, 1), c(30, 7))) {
          args <- list(g, radius = radius, weigh_by_length = weigh, weight_outputs = wo, normalization = norm,
                       angle_threshold = settings[[1]], angle_precision = settings[[2]])
          memory <- do.call(angular_integration, args)
          do.call(angular_integration, c(args, list(output_file = file, overwrite = TRUE)))
          what <- rs_diff_tables(rs_read(file), memory)
          if (!identical(names(memory), legacy_integration_names(weigh || wo))) what <- "names helper"
          if (nzchar(what)) problems <- c(problems, paste("integration", threads, weigh, wo, norm, what))
          runs <- runs + 1
        }
    for (weigh in c(FALSE, TRUE)) for (norm in c("none", "standard", "turner", "syntax"))
      for (radius in list(analysis_radius(), analysis_radius(steps = 3), analysis_radius(walking = 25), analysis_radius(straight = 30)))
        for (settings in list(c(0, 1), c(45, 5))) {
          args <- list(g, radius = radius, weigh_by_length = weigh, normalization = norm,
                       angle_threshold = settings[[1]], angle_precision = settings[[2]])
          memory <- do.call(angular_choice, args)
          do.call(angular_choice, c(args, list(output_file = file, overwrite = TRUE)))
          what <- rs_diff_tables(rs_read(file), memory)
          if (!identical(names(memory), legacy_choice_names(weigh, norm))) what <- "names helper"
          if (nzchar(what)) problems <- c(problems, paste("choice", threads, weigh, norm, what))
          runs <- runs + 1
        }
  }
  expect_identical(problems, character())
  expect_gt(runs, 300)
  # the optional steps argument of Angular Integration
  memory <- angular_integration(g, steps = 2)
  angular_integration(g, steps = 2, output_file = file, overwrite = TRUE)
  rs_expect_same(rs_read(file), memory)
})

test_that("float columns are stored as float32 and counts as int32; the schema is fixed and non-nullable", {
  skip_result_file()
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  g <- rf_graph(); on.exit(rs_native("segment_graph_release", g$ptr), add = TRUE)
  angular_choice(g, weigh_by_length = TRUE, normalization = "syntax", radius = analysis_radius(steps = 4),
                     output_file = file)
  schema <- rs_pq(file)$GetSchema()
  types <- vapply(schema$fields, function(f) f$type$ToString(), "")
  expect_identical(unname(types), c("int32", "float", "int32", "float", "float", "float"))
  expect_identical(schema$names, c("segment_id", "choice", "node_count", "total_depth", "total_depth_weight", "normalized"))
  expect_false(any(vapply(schema$fields, function(f) f$nullable, NA)))
  # floats are exactly representable: widening the stored float32 reproduces the in-memory double bit for bit
  memory <- angular_choice(g, weigh_by_length = TRUE, normalization = "syntax", radius = analysis_radius(steps = 4))
  expect_identical(rs_bytes(rs_read(file)$choice), rs_bytes(memory$choice))
  expect_true(all(memory$choice == as.double(readBin(writeBin(memory$choice, raw(), size = 4L), "numeric", n = nrow(memory), size = 4L))))
})

test_that("the pst_result_file descriptor is returned invisibly and in-memory calls are unchanged", {
  skip_result_file()
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  g <- rf_graph(); on.exit(rs_native("segment_graph_release", g$ptr), add = TRUE)
  file <- file.path(dir, "r.parquet")
  v <- withVisible(angular_integration(g, output_file = file))
  expect_false(v$visible)
  expect_s3_class(v$value, "pst_result_file")
  expect_identical(names(unclass(v$value)), c("path", "rows", "columns", "format"))
  expect_identical(v$value$path, rs_norm(file))
  expect_identical(v$value$rows, 60L)
  expect_identical(v$value$format, "parquet")
  expect_output(print(v$value), "pst_result_file")
  expect_true(withVisible(angular_integration(g))$visible)
  expect_s3_class(angular_choice(g), "data.frame")
  # new arguments are appended: every earlier formal keeps its position
  expect_identical(names(formals(angular_integration)),
                   c("graph", "steps", "radius", "weigh_by_length", "normalization", "angle_threshold",
                     "angle_precision", "weight_outputs", "output_file", "overwrite", "spatial_output_file"))
  expect_identical(names(formals(angular_choice)),
                   c("graph", "radius", "weigh_by_length", "normalization", "angle_threshold", "angle_precision",
                     "output_file", "overwrite", "spatial_output_file"))
  expect_null(formals(angular_choice)$output_file)
  expect_false(formals(angular_choice)$overwrite)
  expect_error(angular_choice(g, overwrite = NA), "overwrite must be TRUE or FALSE")
  expect_error(angular_choice(g, output_file = file, overwrite = "yes"), "overwrite must be TRUE or FALSE")
})

test_that("file metadata records versions, pin, function, parameters, graph, CRS and identifier convention", {
  skip_result_file()
  skip_if_not_installed("sf")
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  lines <- sf::st_sf(geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(0, 0), c(100, 0))), sf::st_linestring(rbind(c(100, 0), c(100, 100))), crs = 32630))
  g <- segment_graph(lines); on.exit(rs_native("segment_graph_release", g$ptr), add = TRUE)
  file <- file.path(dir, "r.parquet")
  g$n_segments <- 999L                                   # editable R metadata must never reach the file
  angular_integration(g, radius = analysis_radius(walking = 50, steps = 2), weigh_by_length = TRUE,
                          normalization = "syntax", angle_threshold = 20, angle_precision = 3, output_file = file)
  md <- rs_pq(file)$GetSchema()$metadata
  status <- rPSTool:::.pst_engine_pin()
  expect_identical(md[["rpst:pst_version"]], unname(status[["pst_version"]]))
  expect_identical(md[["rpst:pst_commit"]], unname(status[["pst_commit"]]))
  expect_identical(md[["rpst:version"]], as.character(getNamespaceVersion("rPSTool")))
  expect_identical(md[["rpst:function"]], "angular_integration")
  expect_identical(md[["rpst:graph_type"]], "segment")
  expect_identical(md[["rpst:graph_rows"]], "2")
  expect_identical(md[["rpst:id_base"]], "1")
  expect_match(md[["rpst:order"]], "native graph order")
  expect_match(md[["rpst:crs_wkt"]], "UTM zone 30N")
  expect_match(md[["rpst:float_columns"]], "float32")
  skip_if_not_installed("jsonlite")
  p <- jsonlite::fromJSON(md[["rpst:parameters"]], simplifyVector = TRUE)
  expect_equal(p$radius$walking, 50); expect_equal(p$radius$steps, 2)
  expect_null(p$radius$straight)
  expect_true(p$weigh_by_length); expect_identical(p$normalization, "syntax")
  expect_equal(p$angle_threshold, 20); expect_equal(p$angle_precision, 3)
  expect_identical(rs_read_parquet(file)$segment_id, 1:2)
})

test_that("a multi-batch result with many row groups equals the in-memory result", {
  skip_result_file()
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  g <- rf_graph(); on.exit(rs_native("segment_graph_release", g$ptr), add = TRUE)
  memory <- angular_choice(g, weigh_by_length = TRUE, normalization = "turner", radius = analysis_radius(steps = 3))
  cols <- c("segment_id", rPSTool:::.pst_nm_names(rPSTool:::.pst_nm_angular_choice(analysis_radius(steps = 3), TRUE, "turner", 0, 1)))
  ptr <- g$ptr
  for (batch in c(1, 7, 59, 60, 61, 1000)) {
    expect_no_error(rPSTool:::.pst_write_result_file(file, TRUE, columns = cols, expected_rows = 60,
      batch_rows = batch, export = function(stream, batch_rows)
        .Call(rPSTool:::C_rpst_angular_choice_stream, ptr, analysis_radius(steps = 3), TRUE, "turner", 0, 1, stream, cols,
              c("rpst:test"), c("batch"), batch_rows)))
    rs_expect_same(rs_read(file), memory)
    expect_identical(rs_pq(file)$num_row_groups, as.integer(ceiling(60 / min(batch, 1048576))))
  }
})

test_that("the native stream entry points validate their arguments before running or exporting anything", {
  skip_result_file()
  g <- rf_graph(); on.exit(rs_native("segment_graph_release", g$ptr), add = TRUE)
  ptr <- g$ptr
  stream <- rs_native("arrow_stream_new"); on.exit(rs_native("arrow_stream_free", stream), add = TRUE)
  cols <- c("segment_id", "choice", "node_count", "total_depth")
  go <- function(stream_arg = stream, names_ = cols, mn = character(), mv = character(), batch = 1000, norm = "none",
                 radius = analysis_radius()) {
    .Call(rPSTool:::C_rpst_angular_choice_stream, ptr, radius, FALSE, norm, 0, 1, stream_arg, names_, mn, mv, batch)
  }
  before <- rs_baseline()
  expect_error(go(names_ = cols[-1]), "exactly 4 column names")
  expect_error(go(names_ = c(cols[1:3], NA)), "non-missing, non-empty")
  expect_error(go(names_ = c(cols[1:3], "")), "non-missing, non-empty")
  expect_error(go(mn = "a", mv = character()), "named character vector")
  expect_error(go(mn = "", mv = "x"), "keys must be non-empty")
  expect_error(go(mn = "a", mv = NA_character_), "keys must be non-empty")
  expect_error(go(batch = 0), "batch size")
  expect_error(go(batch = 1.5), "batch size")
  expect_error(go(norm = "bogus"), "normalization")
  expect_error(go(names_ = c(cols, "normalized"), norm = "syntax"), NA)           # exports (5 names incl. normalized)
  expect_true(rs_native("arrow_stream_is_live", stream))
  expect_error(go(), "already live")
  expect_error(go(stream_arg = "x"), "Invalid rPSTool Arrow stream")
  rs_native("arrow_stream_release", stream)
  expect_error(.Call(rPSTool:::C_rpst_angular_choice_stream, list(ptr = ptr), analysis_radius(), FALSE, "none", 0, 1,
                     rs_native("arrow_stream_new"), cols, character(), character(), 100), "Invalid pst_segment_graph")
  settle <- function() { invisible(gc()); invisible(gc()) }
  settle()
  expect_true(rs_balanced(before))
})

test_that("graph reuse, release and serialisation are unaffected by persisting results", {
  skip_result_file()
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  before <- rs_baseline()
  g <- rf_graph()
  first <- angular_choice(g)
  angular_choice(g, output_file = file)
  expect_identical(angular_choice(g), first)                  # the graph is reusable after a persisted analysis
  persisted <- rs_read(file)
  rs_native("segment_graph_release", g$ptr)
  expect_error(angular_choice(g, output_file = file, overwrite = TRUE), "no longer live")
  rs_expect_same(rs_read(file), first)                           # a failed analysis leaves the earlier file intact
  rs_expect_same(persisted, first)                               # and the file outlives its graph
  copy <- unserialize(serialize(rf_graph(), NULL))
  expect_error(angular_integration(copy, output_file = file, overwrite = TRUE), "no longer live")
  rs_expect_same(rs_read(file), first)
  expect_identical(rs_leftovers(dir), character())
  invisible(gc()); invisible(gc())
  expect_true(rs_balanced(before))
})
