# docs/spatial-io/result-files.md §7.3: direct Parquet persistence of segment_grouping(). The grouping runs ONCE natively; the native
# zero-based buffers are moved into the Arrow stream and shifted to the public one-based convention in place; the two scalars
# become the schema metadata keys rpst:n_groups / rpst:n_colors. Every persisted table is compared with the unchanged in-memory
# data frame (names, order, R types, values) and with the pinned direct-PST fixture; the scalars with the in-memory attributes.

skip_grouping_file <- function() {
  skip_if_not_installed("arrow", "25.0.0")
}
gr_release <- function(g) rs_native("segment_graph_release", g$ptr)
gr_meta <- function(file) rs_pq(file)$GetSchema()$metadata
gr_types <- function(file) unname(vapply(rs_pq(file)$GetSchema()$fields, function(f) f$type$ToString(), ""))
gr_nullable <- function(file) unname(vapply(rs_pq(file)$GetSchema()$fields, function(f) f$nullable, NA))
# a deterministic irregular network with many groups at moderate thresholds
gr_network <- function() {
  i <- rep(1:7, times = 8); j <- rep(1:8, each = 7)
  w <- ((i * 7 + j * 3) %% 5) - 2
  rbind(cbind(i * 10, j * 10, (i + 1) * 10, j * 10 + w * 2), cbind(j * 10 + w, i * 10, j * 10, (i + 1) * 10 + w))
}
gr_frame <- function(memory) { out <- memory; attr(out, "n_groups") <- NULL; attr(out, "n_colors") <- NULL; out }

test_that("segment_grouping gains output_file/overwrite as appended formals; the in-memory result is unchanged", {
  expect_identical(names(formals(segment_grouping)),
                   c("graph", "angle_threshold", "split_at_junctions", "output_file", "overwrite"))
  expect_null(formals(segment_grouping)$output_file); expect_false(formals(segment_grouping)$overwrite)
  s <- segment_graph(gr_network()); on.exit(gr_release(s), add = TRUE)
  a <- segment_grouping(s, 30); b <- segment_grouping(s, 30, output_file = NULL, overwrite = FALSE)
  expect_identical(a, b)
  expect_identical(names(a), c("segment_id", "group_id", "color"))
  expect_identical(vapply(a, typeof, ""), c(segment_id = "integer", group_id = "integer", color = "integer"))
  expect_identical(sort(names(attributes(a))), c("class", "n_colors", "n_groups", "names", "row.names"))
})

test_that("persisted grouping equals the in-memory result and the pinned direct-PST fixture, with the scalars as metadata", {
  skip_grouping_file()
  ref <- dget(test_path("fixtures", "segment-groups-direct-v3.3.2.R"))
  expect_identical(ref$pst_commit, unname(rPSTool:::.pst_engine_pin()[["pst_commit"]]))
  dir <- tempfile("rpst-grp-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  graphs <- lapply(ref$networks, function(rows) segment_graph(do.call(rbind, rows)))
  on.exit(for (g in graphs) gr_release(g), add = TRUE)
  before <- rs_baseline()
  checked <- 0
  for (case in ref$groupings) {
    g <- graphs[[case$network]]; file <- file.path(dir, "r.parquet")
    memory <- segment_grouping(g, case$angle, case$split)
    d <- segment_grouping(g, case$angle, case$split, output_file = file, overwrite = file.exists(file))
    expect_s3_class(d, "pst_result_file"); expect_identical(d$columns, c("segment_id", "group_id", "color")); expect_identical(d$format, "parquet")
    expect_identical(d$rows, nrow(memory))
    persisted <- rs_read(file)
    rs_expect_same(persisted, gr_frame(memory))                                       # exact, incl. types and row order
    expect_identical(persisted$group_id, as.integer(case$ids)); expect_identical(persisted$color, as.integer(case$colors))
    expect_identical(gr_types(file), c("int32", "int32", "int32")); expect_identical(gr_nullable(file), c(FALSE, FALSE, FALSE))
    md <- gr_meta(file)
    expect_identical(md[["rpst:n_groups"]], as.character(attr(memory, "n_groups"))); expect_identical(md[["rpst:n_groups"]], as.character(case$n_groups))
    expect_identical(md[["rpst:n_colors"]], as.character(attr(memory, "n_colors"))); expect_identical(md[["rpst:n_colors"]], as.character(case$n_colors))
    expect_identical(max(persisted$group_id), as.integer(md[["rpst:n_groups"]])); expect_identical(max(persisted$color), as.integer(md[["rpst:n_colors"]]))
    expect_identical(min(persisted$group_id), 1L); expect_identical(min(persisted$color), 1L)   # one-based, never zero
    expect_identical(rs_pq(file)$num_rows, nrow(memory))
    unlink(file); checked <- checked + 1
  }
  expect_gte(checked, 1)
  expect_true(rs_balanced(before))
})

test_that("metadata keeps the provenance keys once each and the grouping parameters", {
  skip_grouping_file()
  dir <- tempfile("rpst-grp-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  s <- segment_graph(gr_network()); on.exit(gr_release(s), add = TRUE)
  file <- file.path(dir, "r.parquet"); segment_grouping(s, 45, TRUE, output_file = file)
  md <- gr_meta(file)
  expect_false(anyDuplicated(names(md)) > 0)
  for (key in c("rpst:schema", "rpst:version", "rpst:pst_version", "rpst:pst_commit", "rpst:function", "rpst:parameters",
                "rpst:graph_type", "rpst:graph_rows", "rpst:crs_wkt", "rpst:id_base", "rpst:order", "rpst:n_groups", "rpst:n_colors"))
    expect_identical(sum(names(md) == key), 1L, info = key)
  expect_identical(md[["rpst:function"]], "segment_grouping"); expect_identical(md[["rpst:graph_type"]], "segment")
  expect_identical(md[["rpst:graph_rows"]], as.character(nrow(segment_grouping(s)))); expect_identical(md[["rpst:id_base"]], "1")
  expect_identical(md[["rpst:pst_commit"]], unname(rPSTool:::.pst_engine_pin()[["pst_commit"]]))
  parameters <- jsonlite::fromJSON(md[["rpst:parameters"]])
  expect_equal(parameters$angle_threshold, 45); expect_true(parameters$split_at_junctions)
  expect_match(md[["rpst:order"]], "one-based")
  expect_false("rpst:float_columns" %in% names(md))          # the table has no native single-precision column (all int32)
  angular <- file.path(dir, "angular.parquet"); angular_choice(s, output_file = angular)
  expect_true("rpst:float_columns" %in% names(gr_meta(angular)))   # other families are unchanged
})

test_that("many thresholds, both split modes and group/colour extremes persist exactly; the graph is reused", {
  skip_grouping_file()
  dir <- tempfile("rpst-grp-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  star <- local({ a <- seq(0, 2 * pi, length.out = 21)[1:20]; cbind(0, 0, cos(a) * 10, sin(a) * 10) })   # 20 segments meeting at one point
  networks <- list(irregular = gr_network(), chain = cbind(0:4 * 3, 0, 1:5 * 3, 0), single = rbind(c(0, 0, 1, 0)), star = star,
                   disconnected = rbind(c(0, 0, 1, 0), c(5, 0, 6, 0), c(10, 0, 11, 0)),
                   square = rbind(c(0, 0, 1, 0), c(1, 0, 1, 1), c(1, 1, 0, 1), c(0, 1, 0, 0)))
  graphs <- lapply(networks, segment_graph); on.exit(for (g in graphs) gr_release(g), add = TRUE)
  before <- rs_baseline(); seen <- c(groups = 0, colors = 0)
  # the float-narrowing extremes (smallest float subnormal, largest float) and an integer-typed threshold are accepted alike
  for (name in names(graphs)) for (angle in list(0, 1e-45, 1, 30, 30L, 90, 179, 180, 360, 1e38)) for (split in c(FALSE, TRUE)) {
    memory <- segment_grouping(graphs[[name]], angle, split)
    segment_grouping(graphs[[name]], angle, split, output_file = file, overwrite = TRUE)
    persisted <- rs_read(file); md <- gr_meta(file)
    expect_identical(rs_diff_tables(persisted, gr_frame(memory)), "", info = paste(name, angle, split))
    expect_identical(md[["rpst:n_groups"]], as.character(attr(memory, "n_groups")), info = paste(name, angle, split))
    expect_identical(md[["rpst:n_colors"]], as.character(attr(memory, "n_colors")), info = paste(name, angle, split))
    seen <- pmax(seen, c(attr(memory, "n_groups"), attr(memory, "n_colors")))
  }
  expect_gt(seen[["groups"]], 20); expect_gt(seen[["colors"]], 2)      # the sweep really covers many groups and several colours (star: 10-20)
  star_split <- segment_grouping(graphs$star, 90, TRUE)
  expect_identical(c(attr(star_split, "n_groups"), attr(star_split, "n_colors")), c(20L, 20L))   # 20 segments at one point, each its own group, all colours distinct
  # thresholds that do not fit a native float are rejected by BOTH routes with the same message, and create nothing
  for (bad in c(5e-324, 1e-320, 1.8e308, -1, NA_real_, Inf)) {
    m1 <- tryCatch(segment_grouping(graphs$chain, bad), error = conditionMessage)
    m2 <- tryCatch(segment_grouping(graphs$chain, bad, output_file = file, overwrite = TRUE), error = conditionMessage)
    expect_match(m1, "angle_threshold must be one finite non-negative native float", info = bad); expect_identical(m2, m1, info = bad)
  }
  expect_identical(nrow(segment_grouping(graphs$single)), 1L)
  one <- segment_grouping(graphs$single, output_file = file, overwrite = TRUE); expect_identical(one$rows, 1L)
  expect_identical(rs_read(file)$group_id, 1L); expect_identical(gr_meta(file)[["rpst:n_groups"]], "1")
  expect_true(rs_balanced(before))
})

test_that("small batches and a row-group layout that does not divide the result persist exactly", {
  skip_grouping_file()
  dir <- tempfile("rpst-grp-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  s <- segment_graph(gr_network()); on.exit(gr_release(s), add = TRUE)
  memory <- segment_grouping(s, 30)
  md <- rPSTool:::.pst_result_metadata("segment_grouping", list(), "segment", nrow(memory), s)
  columns <- c("segment_id", "group_id", "color")
  for (batch in c(1, 7, 50, nrow(memory) - 1, nrow(memory), 10000)) {
    file <- file.path(dir, paste0("b", batch, ".parquet"))
    rPSTool:::.pst_write_result_file(file, FALSE, columns = columns, expected_rows = nrow(memory), batch_rows = batch,
      export = function(stream, batch_rows) .Call(rPSTool:::C_rpst_segment_grouping_stream, s$ptr, 30, FALSE, stream, columns,
                                                  names(md), unname(md), batch_rows))
    rs_expect_same(rs_read(file), gr_frame(memory))
    expect_identical(gr_meta(file)[["rpst:n_groups"]], as.character(attr(memory, "n_groups")))
    expect_identical(rs_pq(file)$num_row_groups, as.integer(ceiling(nrow(memory) / min(batch, 1048576))), info = batch)
  }
})

test_that("bad arguments, wrong or dead graphs and unusable destinations are rejected before anything is computed or created", {
  skip_grouping_file()
  dir <- tempfile("rpst-grp-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  s <- segment_graph(gr_network()); a <- axial_graph(gr_network()); dead <- segment_graph(gr_network())
  gr_release(dead)
  on.exit({ gr_release(s); .Call(rPSTool:::C_rpst_graph_release, a$ptr) }, add = TRUE)
  before <- rs_baseline()
  bad <- list(
    function() segment_grouping(s, -1, output_file = file), function() segment_grouping(s, NA_real_, output_file = file),
    function() segment_grouping(s, c(1, 2), output_file = file), function() segment_grouping(s, Inf, output_file = file),
    function() segment_grouping(s, 1, NA, output_file = file), function() segment_grouping(s, 1, "yes", output_file = file),
    function() segment_grouping(s, output_file = file, overwrite = NA), function() segment_grouping(s, output_file = c(file, file)),
    function() segment_grouping(s, output_file = ""), function() segment_grouping(s, output_file = dir),
    function() segment_grouping(s, output_file = file.path(dir, "missing-dir", "r.parquet")),
    function() segment_grouping(a, output_file = file),                       # axial graph: wrong family
    function() segment_grouping(dead, output_file = file),                    # released pointer
    function() segment_grouping(unserialize(serialize(s, NULL)), output_file = file))   # dead after deserialisation
  for (k in seq_along(bad)) expect_error(bad[[k]](), info = k)
  expect_false(file.exists(file)); expect_length(rs_leftovers(dir), 0L)
  expect_identical(rs_counters()[["tables_made"]], before[["tables_made"]])       # no result table was ever built: no calculation ran
  expect_true(rs_balanced(before))
})

test_that("existing destinations survive failures; no-clobber, overwrite and failed writes leave no temporaries", {
  skip_grouping_file()
  dir <- tempfile("rpst-grp-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  s <- segment_graph(gr_network()); on.exit(gr_release(s), add = TRUE)
  segment_grouping(s, 30, output_file = file); keep <- rs_md5(file)
  expect_error(segment_grouping(s, 30, output_file = file), "already exists")
  expect_identical(rs_md5(file), keep)
  # the native result is built, then the write fails: the old destination is untouched, nothing is left behind
  n <- nrow(segment_grouping(s, 30))
  columns <- c("segment_id", "group_id", "color"); md <- rPSTool:::.pst_result_metadata("segment_grouping", list(), "segment", n, s)
  before <- rs_baseline()
  expect_error(rPSTool:::.pst_write_result_file(file, TRUE, columns = columns, expected_rows = n, export = function(stream, batch_rows) {
    .Call(rPSTool:::C_rpst_segment_grouping_stream, s$ptr, 30, FALSE, stream, columns, names(md), unname(md), batch_rows)
    stop("boom after the native result was exported") }), "boom")
  expect_identical(rs_md5(file), keep); expect_length(rs_leftovers(dir), 0L)
  # a wrong expected row count is refused at publication
  expect_error(rPSTool:::.pst_write_result_file(file, TRUE, columns = columns, expected_rows = 5, export = function(stream, batch_rows)
    .Call(rPSTool:::C_rpst_segment_grouping_stream, s$ptr, 30, FALSE, stream, columns, names(md), unname(md), batch_rows)),
    "unexpected number of rows")
  expect_identical(rs_md5(file), keep); expect_length(rs_leftovers(dir), 0L)
  expect_true(rs_balanced(before))
  # overwrite = TRUE replaces atomically with the new parameters' result
  segment_grouping(s, 90, TRUE, output_file = file, overwrite = TRUE)
  expect_false(identical(rs_md5(file), keep))
  rs_expect_same(rs_read(file), gr_frame(segment_grouping(s, 90, TRUE)))
})

test_that("stream-level argument validation matches the in-memory route and a live stream is refused", {
  skip_grouping_file()
  s <- segment_graph(gr_network()); on.exit(gr_release(s), add = TRUE)
  stream <- rs_native("arrow_stream_new"); on.exit(rs_native("arrow_stream_free", stream), add = TRUE)
  call <- function(angle = 30, split = FALSE, names = c("segment_id", "group_id", "color"), mn = "k", mv = "v", batch = 100, st = stream)
    .Call(rPSTool:::C_rpst_segment_grouping_stream, s$ptr, angle, split, st, names, mn, mv, batch)
  expect_error(call(angle = -1), "angle_threshold"); expect_error(call(split = NA), "split_at_junctions")
  expect_error(call(names = c("segment_id", "group_id")), "needs exactly 3 column names")
  expect_error(call(batch = 0), "batch size must be a whole number between 1 and"); expect_error(call(mn = c("a", "b")), "metadata must be a named character vector")
  expect_error(call(st = "not a stream"))
  expect_null(call())                                                      # a valid call fills the stream
  expect_error(call(), "Arrow stream is already live")                          # and the second call on the same live stream is refused
})

test_that("the written file outlives the graph, and repeated persistence does not accumulate native owners", {
  skip_grouping_file()
  dir <- tempfile("rpst-grp-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  before <- rs_baseline()
  s <- segment_graph(gr_network()); memory <- segment_grouping(s, 30)
  for (k in 1:5) segment_grouping(s, 30, output_file = file.path(dir, paste0("r", k, ".parquet")))
  gr_release(s); rm(s); invisible(gc())
  for (k in 1:5) rs_expect_same(rs_read(file.path(dir, paste0("r", k, ".parquet"))), gr_frame(memory))
  expect_true(rs_balanced(before))
})

test_that("symlink and directory destinations behave as for every output_file: never followed, never replaced as a directory", {
  skip_grouping_file()
  dir <- tempfile("rpst-grp-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  s <- segment_graph(gr_network()); on.exit(gr_release(s), add = TRUE)
  rs_if_symlinks(dir, {
    target <- file.path(dir, "real.parquet"); writeLines("original", target)
    dangling <- file.path(dir, "dangling.parquet"); rs_symlink(file.path(dir, "nowhere.parquet"), dangling)
    expect_error(segment_grouping(s, output_file = dangling), "already exists")      # a dangling link is not silently written through
    if (.Platform$OS.type == "unix") expect_identical(Sys.readlink(dangling), file.path(dir, "nowhere.parquet"))
    expect_false(file.exists(file.path(dir, "nowhere.parquet")))
    link <- file.path(dir, "link.parquet"); rs_symlink(target, link)
    expect_error(segment_grouping(s, output_file = link), "already exists")
    segment_grouping(s, output_file = link, overwrite = TRUE)                        # the link itself is replaced by a regular file ...
    expect_identical(Sys.readlink(link), ""); expect_true(file.exists(link))
    expect_identical(readLines(target), "original")                                      # ... and the file it pointed to is untouched
  })
  expect_error(segment_grouping(s, output_file = dir, overwrite = TRUE), "is a directory")
  expect_true(dir.exists(dir)); expect_length(rs_leftovers(dir), 0L)
})
