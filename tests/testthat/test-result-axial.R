# docs/spatial-io/result-files.md §6: direct Parquet persistence of the mask-free axial-graph analyses: Network Integration
# (lines), Reach (lines and supplied origins), OD Betweenness, Attraction Reach and Attraction Distance. Every
# persisted table is compared with the existing in-memory data frame (names, order, rows, R types and the raw bytes
# of every double) and with the pinned direct-PST references already used by the in-memory tests. The Arrow stream
# ownership protocol itself is tested in test-result-stream.R; the shared writer in test-result-file.R and
# test-result-publication.R.

# Weight vectors used by the tests below; the object names become the weight names in the result columns.
origin_wt_c_1_2 <- c(1, 2)
capacity_c_1_3 <- c(1, 3)

skip_result_file <- function() {
  skip_if_not_installed("arrow", "25.0.0")
}
ra_rows <- function(x, width = 2L) matrix(as.double(unlist(x)), ncol = width, byrow = TRUE)
ra_graph <- function(case) {
  args <- case[intersect(names(case), c("x", "line_indices", "unlinks", "points", "points_per_polygon",
                                        "polygon_point_interval"))]
  args$x <- ra_rows(args$x, if (is.null(args$line_indices)) 4L else 2L)
  for (field in c("line_indices", "unlinks", "points"))
    if (!is.null(args[[field]])) args[[field]] <- ra_rows(args[[field]])
  if (!is.null(args$points_per_polygon)) args$points_per_polygon <- as.double(unlist(args$points_per_polygon))
  do.call(axial_graph, args)
}
ra_release <- function(graphs) for (g in graphs) rs_native("graph_release", g$ptr)
ra_nonfinite <- function(persisted) {
  c(nan = sum(vapply(persisted, function(x) if (is.double(x)) sum(is.nan(x)) else 0, 0)),
    inf = sum(vapply(persisted, function(x) if (is.double(x)) sum(is.infinite(x)) else 0, 0)))
}

test_that("attraction results equal the in-memory results and the direct-PST reference in every supported mode", {
  skip_result_file()
  ref <- dget(test_path("fixtures", "attractions-direct-v3.3.2.R"))
  expect_identical(ref$pst_commit, unname(rPSTool:::.pst_engine_pin()[["pst_commit"]]))
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  graphs <- list(); on.exit(ra_release(graphs), add = TRUE)
  before <- rs_baseline()
  problems <- character(); written <- 0; classes <- c(nan = 0, inf = 0)
  note <- function(label, what) if (nzchar(what)) problems <<- c(problems, paste(label, what))
  for (case in rpst_cases(ref$cases, every = 40L, by = list(rpst_case_signature), each = list(rpst_case_edges))) {
    name <- case$graph$name
    if (is.null(graphs[[name]])) {
      args <- case$graph[intersect(names(case$graph), c("x", "points", "points_per_polygon", "polygon_point_interval"))]
      args$x <- ra_rows(args$x, 4L); args$points <- ra_rows(args$points)
      if (!is.null(args$points_per_polygon)) args$points_per_polygon <- as.double(unlist(args$points_per_polygon))
      graphs[[name]] <- do.call(axial_graph, args)
    }
    g <- graphs[[name]]
    g$n_lines <- g$n_points <- g$n_point_groups <- g$n_crossings <- 999L   # metadata is never the authority
    args <- case$args
    args$attraction_points <- ra_rows(args$attraction_points)
    args$radius <- do.call(analysis_radius, args$radius)
    if (!is.null(args$points_per_polygon)) args$points_per_polygon <- as.double(unlist(args$points_per_polygon))
    # Weight identifiers are inferred from the expression passed to the weight arguments, and do.call() would pass the
    # evaluated vectors. Bind each weight to a name and hand do.call the symbol, exactly as a user would write it.
    for (field in c("attraction_values", "line_weights"))
      if (!is.null(args[[field]])) { assign(field, as.double(unlist(args[[field]]))); args[[field]] <- as.name(field) }
    fn <- if (case$analysis == "reach") attraction_reach else attraction_distance
    # distance cases are run with and without the optional native destination index
    for (indices in if (case$analysis == "distance") c(isTRUE(args$destination_indices), !isTRUE(args$destination_indices)) else NA) {
      if (!is.na(indices)) args$destination_indices <- indices
      label <- paste(case$analysis, name, written)
      memory <- do.call(fn, c(list(graph = g), args))
      out <- do.call(fn, c(list(graph = g), args, list(output_file = file, overwrite = TRUE)))
      persisted <- rs_read(file)
      note(label, rs_diff_tables(persisted, memory))
      if (!identical(out$columns, names(memory)) || !identical(out$rows, nrow(memory))) note(label, "descriptor")
      if (!identical(persisted$origin_id, seq_along(case$scores))) note(label, "origin_id")
      note(label, rs_diff_reference(persisted[[2L]], case$scores, tolerance = 2e-6))
      if (case$analysis == "distance" && isTRUE(indices)) {
        # the pinned reference holds the native indices only for the cases that requested them
        if (isTRUE(case$args$destination_indices) &&
            !identical(pick(persisted, "^di_"), as.integer(unlist(case$indices)))) note(label, "destination_index")
        if (length(persisted) != 3L) note(label, "missing destination_index")
      } else if (length(persisted) != 2L) note(label, "unexpected column")
      classes <- classes + ra_nonfinite(persisted)
      written <- written + 1
    }
  }
  expect_identical(problems, character())
  expect_gt(written, 30)
  expect_gt(classes[["nan"]] + classes[["inf"]], 0)  # native NaN/Inf were persisted as values (never as Arrow nulls)
  expect_true(rs_balanced(before))
})

test_that("OD Betweenness results equal the in-memory results and the direct-PST reference", {
  skip_result_file()
  ref <- dget(test_path("fixtures", "od-direct-v3.3.2.R"))
  expect_identical(ref$pst_commit, unname(rPSTool:::.pst_engine_pin()[["pst_commit"]]))
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  graphs <- list(); on.exit(ra_release(graphs), add = TRUE)
  old <- Sys.getenv("RPST_NUM_THREADS", unset = NA_character_)
  on.exit(if (is.na(old)) Sys.unsetenv("RPST_NUM_THREADS") else Sys.setenv(RPST_NUM_THREADS = old), add = TRUE)
  Sys.setenv(RPST_NUM_THREADS = "1")
  problems <- character()
  for (case in rpst_cases(od_supported_cases(ref$cases), every = 60L, by = list(rpst_case_signature), each = list(rpst_case_edges))) {
    name <- case$graph$name
    if (is.null(graphs[[name]])) graphs[[name]] <- ra_graph(case$graph)
    g <- graphs[[name]]
    g$n_lines <- 999L
    args <- case$args
    args$origins <- ra_rows(args$origins)
    args$radius <- do.call(analysis_radius, args$radius)
    for (field in c("origin_weights", "destination_weights"))   # named objects, passed to do.call as symbols
      if (!is.null(args[[field]])) { assign(field, as.double(unlist(args[[field]]))); args[[field]] <- as.name(field) }
    memory <- do.call(od_betweenness, c(list(graph = g), args))
    do.call(od_betweenness, c(list(graph = g), args, list(output_file = file, overwrite = TRUE)))
    persisted <- rs_read(file)
    label <- paste(name, length(problems))
    if (nzchar(d <- rs_diff_tables(persisted, memory))) problems <- c(problems, paste(label, d))
    if (!identical(persisted$line_id, seq_along(case$scores))) problems <- c(problems, paste(label, "line_id"))
    if (nzchar(d <- rs_diff_reference(pick(persisted, "^od_"), case$scores, tolerance = 2e-6)))
      problems <- c(problems, paste(label, d))
  }
  expect_identical(problems, character())
})

test_that("Network Integration and Reach results equal the in-memory results and the direct-PST references", {
  skip_result_file()
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  graphs <- list(); on.exit(ra_release(graphs), add = TRUE)
  problems <- character()
  note <- function(label, what) if (nzchar(what)) problems <<- c(problems, paste(label, what))
  # (a) the independent pinned upstream integration oracle, unrestricted and with every step limit
  ni <- dget(test_path("fixtures", "network-integration-v3.3.2.R"))
  g <- axial_graph(ni$lines); graphs$ni <- g
  memory <- network_integration(g)
  expect_identical(network_integration(g, output_file = file)$columns, c("line_id", "ni_s_rg", "nc_s_rg", "td_s_rg"))
  persisted <- rs_read(file)
  note("ni", rs_diff_tables(persisted, memory))
  expect_identical(pick(persisted, "^nc_"), ni$node_count)
  expect_identical(pick(persisted, "^td_"), ni$total_depth)
  for (case in ni$steps) {
    network_integration(g, steps = case$limit, output_file = file, overwrite = TRUE)
    expect_identical(pick(rs_read(file), "^nc_"), case$node_count)
    note(paste("steps", case$limit), rs_diff_tables(rs_read(file), network_integration(g, steps = case$limit)))
  }
  # (b) every radius combination of the official-wrapper oracle for integration and (line) reach
  p4 <- dget(test_path("fixtures", "core-network-direct-v3.3.2.R"))
  a <- axial_graph(do.call(rbind, p4$rows)); graphs$p4 <- a
  checked <- 0
  for (case in rpst_cases(p4$cases, every = 5L, by = list(rpst_case_signature), each = list(rpst_case_edges))) {
    if (!case$routine %in% c("integration", "reach")) next
    radius <- do.call(analysis_radius, case$radius)
    if (case$routine == "integration") {
      # The oracle exercises the native engine with every radius field, so the unrestricted internal implementation is used
      # (the public network_integration() accepts only steps radii; the public rejection is tested in test-network-integration.R and at the end of this file).
      memory <- rPSTool:::.pst_network_integration_run(a, radius = radius)
      rPSTool:::.pst_network_integration_run(a, radius = radius, output_file = file, overwrite = TRUE)
      persisted <- rs_read(file)
      expect_identical(pick(persisted, "^nc_"), as.integer(case$count))
    } else {
      memory <- network_reach(a, radius)
      network_reach(a, radius, output_file = file, overwrite = TRUE)
      persisted <- rs_read(file)
      expect_identical(pick(persisted, "^rc_"), as.integer(case$count))
    }
    note(paste(case$routine, checked), rs_diff_tables(persisted, memory))
    checked <- checked + 1
  }
  expect_gt(checked, 10)
  # (c) Reach from supplied origins (origin_id) against the pinned optional-mode oracle
  t7 <- dget(test_path("fixtures", "reach-betweenness-direct-v3.3.2.R"))
  nets <- lapply(t7$networks, function(rows) axial_graph(do.call(rbind, rows))); graphs <- c(graphs, nets)
  origins_checked <- 0
  for (case in rpst_cases(t7$cases, every = 25L, by = list(rpst_case_signature), each = list(rpst_case_edges))) {
    if (case$routine != "reach") next
    points <- do.call(rbind, case$points)
    radius <- do.call(analysis_radius, case$radius)
    memory <- network_reach(nets[[case$network]], radius, points)
    out <- network_reach(nets[[case$network]], radius, points, output_file = file, overwrite = TRUE)
    persisted <- rs_read(file)
    note(paste("origins", origins_checked), rs_diff_tables(persisted, memory))
    expect_columns(persisted, c("^origin_id$", "^rc_", "^rln_", "^rca_"))
    expect_identical(persisted$origin_id, seq_len(nrow(points)))
    expect_identical(pick(persisted, "^rc_"), as.integer(case$count))
    expect_identical(out$rows, nrow(points))
    origins_checked <- origins_checked + 1
  }
  expect_gt(origins_checked, 0)
  expect_identical(problems, character())
})

test_that("non-finite and unreachable native values are stored as values, never as nulls", {
  skip_result_file()
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  g <- axial_graph(cbind(0:2, 0, 1:3, 0), points = rbind(c(0.5, 0.5), c(2.5, 0.5)))
  on.exit(rs_native("graph_release", g$ptr), add = TRUE)
  # a small neighbourhood: PST's own -1 / NaN / Inf integration values pass through unchanged
  memory <- network_integration(g, steps = 0)
  network_integration(g, steps = 0, output_file = file)
  persisted <- rs_read(file); rs_expect_same(persisted, memory)
  expect_true(all(is.nan(pick(persisted, "^ni_")) | pick(persisted, "^ni_") == -1 | is.infinite(pick(persisted, "^ni_"))))
  expect_identical(rs_pq(file)$GetSchema()$GetFieldByName("ni_s_rs0")$nullable, FALSE)
  # unreachable attraction distance keeps native -1 and the signed destination index -1
  far <- rbind(c(100, 100))
  memory <- attraction_distance(g, far, analysis_radius(walking = 1), distance = "walking")
  attraction_distance(g, far, analysis_radius(walking = 1), distance = "walking", output_file = file, overwrite = TRUE)
  persisted <- rs_read(file); rs_expect_same(persisted, memory)
  expect_true(any(pick(persisted, "^ad_") == -1))
  expect_true(any(pick(persisted, "^di_") == -1L))
  types <- vapply(rs_read_parquet(file, as_data_frame = FALSE)$schema$fields, function(f) f$type$ToString(), "")
  expect_identical(unname(types), c("int32", "float", "int32"))
})

test_that("a zero-row result (no junctions or points of the requested origin kind) is a valid empty file", {
  skip_result_file()
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  g <- axial_graph(rbind(c(0, 0, 3, 0), c(10, 0, 13, 0)))   # two lines, no crossings, no points
  on.exit(rs_native("graph_release", g$ptr), add = TRUE)
  pts <- rbind(c(1, 1))
  for (origin in c("junctions", "points", "point_groups")) {
    memory <- attraction_reach(g, pts, origin = origin, distance = "steps")
    out <- attraction_reach(g, pts, origin = origin, distance = "steps", output_file = file, overwrite = TRUE)
    expect_identical(out$rows, 0L)
    expect_identical(nrow(memory), 0L)
    persisted <- rs_read(file)
    expect_columns(persisted, c("^origin_id$", "^ar_"))
    expect_identical(length(persisted$origin_id), 0L)
    expect_identical(typeof(pick(persisted, "^ar_")), typeof(pick(memory, "^ar_")))
    expect_equal(rs_pq(file)$num_rows, 0)
    memory <- attraction_distance(g, pts, origin = origin, distance = "steps")
    attraction_distance(g, pts, origin = origin, distance = "steps", output_file = file, overwrite = TRUE)
    rs_expect_same(rs_read(file), memory)
  }
})

test_that("public signatures append output_file/overwrite/spatial_output_file and leave every earlier formal untouched", {
  # the weight names of the output-naming scheme are inferred from the call: no argument was added for them
  expect_identical(names(formals(rPSTool::network_integration)),
                   c("graph", "steps", "radius", "junctions", "junction_output", "output_file", "overwrite", "spatial_output_file"))
  expect_identical(names(formals(rPSTool::network_reach)), c("graph", "radius", "origins", "output_file", "overwrite", "spatial_output_file"))
  expect_identical(names(formals(rPSTool::od_betweenness)),
                   c("graph", "origins", "radius", "distance", "destination_mode", "origin_weights",
                     "destination_weights", "output_file", "overwrite", "spatial_output_file"))
  expect_identical(names(formals(rPSTool::attraction_reach)),
                   c("graph", "attraction_points", "radius", "origin", "distance", "points_per_polygon",
                     "polygon_point_interval", "attraction_values", "decay", "decay_constant", "distribution",
                     "collection", "output_file", "overwrite", "spatial_output_file"))
  expect_identical(names(formals(rPSTool::attraction_distance)),
                   c("graph", "attraction_points", "radius", "origin", "distance", "points_per_polygon",
                     "polygon_point_interval", "line_weights", "point_edge_weight", "destination_indices",
                     "output_file", "overwrite", "spatial_output_file"))
  for (f in list(rPSTool::network_integration, rPSTool::network_reach, rPSTool::od_betweenness,
                 rPSTool::attraction_reach, rPSTool::attraction_distance)) {
    expect_null(formals(f)$output_file)
    expect_false(formals(f)$overwrite)
  }
})

test_that("argument errors and unsupported combinations are rejected before any file exists or is replaced", {
  skip_result_file()
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  g <- axial_graph(cbind(0:2, 0, 1:3, 0), points = rbind(c(0.5, 0.5)))
  s <- segment_graph(rbind(c(0, 0, 3, 0), c(3, 0, 3, 3)))
  on.exit({ rs_native("graph_release", g$ptr); rs_native("segment_graph_release", s$ptr) }, add = TRUE)
  pts <- rbind(c(1, 1))
  bad <- list(
    integration_overwrite = function() network_integration(g, output_file = file, overwrite = NA),
    integration_junctions = function() network_integration(g, junctions = TRUE, output_file = file),
    integration_radius = function() network_integration(g, steps = -1, output_file = file),
    integration_both = function() network_integration(g, steps = 1, radius = analysis_radius(), output_file = file),
    reach_radius = function() network_reach(g, radius = list(), output_file = file),
    reach_origins = function() network_reach(g, origins = rbind(c(NA, 1)), output_file = file),
    reach_graph_type = function() network_reach(s, output_file = file),
    integration_graph_type = function() network_integration(s, output_file = file),
    od_mode = function() od_betweenness(g, pts, destination_mode = "x", output_file = file),
    od_weights = function() od_betweenness(g, pts, origin_weights = origin_wt_c_1_2, output_file = file),
    ar_origin = function() attraction_reach(g, pts, origin = "bogus", output_file = file),
    ar_decay = function() attraction_reach(g, pts, decay = "bogus", output_file = file),
    ad_straight_group = function() attraction_distance(g, pts, origin = "point_groups", distance = "straight",
                                                           output_file = file),
    ad_weights = function() attraction_distance(g, pts, distance = "weights", output_file = file),
    ad_indices = function() attraction_distance(g, pts, destination_indices = NA, output_file = file),
    path_empty = function() network_reach(g, output_file = ""),
    path_directory = function() network_reach(g, output_file = dir),
    path_missing_dir = function() network_reach(g, output_file = file.path(dir, "nope", "x.parquet")))
  for (name in names(bad)) expect_error(bad[[name]](), regexp = ".", info = name)
  expect_identical(list.files(dir, all.files = TRUE, no.. = TRUE), character())
  # an existing file is never replaced or damaged by a rejected call, nor by one that fails natively after validation
  writeLines("keep", file)
  expect_error(network_reach(g, output_file = file), "already exists")
  expect_error(network_reach(g, radius = list(), output_file = file, overwrite = TRUE))
  expect_error(attraction_distance(g, pts, origin = "point_groups", distance = "straight",
                                       output_file = file, overwrite = TRUE), "unwritten")
  expect_identical(readLines(file), "keep")
  expect_identical(rs_leftovers(dir), character())
  # the no-clobber and overwrite contract is the shared one
  expect_no_error(network_reach(g, output_file = file, overwrite = TRUE))
  expect_identical(length(rs_read(file)$line_id), 3L)
})

test_that("a released, deserialised or dead graph is rejected and creates no file", {
  skip_result_file()
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  g <- axial_graph(cbind(0:2, 0, 1:3, 0), points = rbind(c(0.5, 0.5)))
  copy <- unserialize(serialize(g, NULL))            # a dead external pointer
  for (f in list(function(x) network_integration(x, output_file = file), function(x) network_reach(x, output_file = file),
                 function(x) od_betweenness(x, rbind(c(1, 1)), output_file = file),
                 function(x) attraction_reach(x, rbind(c(1, 1)), output_file = file),
                 function(x) attraction_distance(x, rbind(c(1, 1)), output_file = file)))
    expect_error(f(copy), "live|pst_graph")
  network_reach(g, output_file = file)                   # works while alive
  ptr <- g$ptr
  rs_native("graph_release", ptr)
  expect_error(network_reach(g, output_file = file, overwrite = TRUE), "live|pst_graph")
  expect_error(network_integration(g, output_file = file, overwrite = TRUE), "live|pst_graph")
  expect_identical(rs_read(file)$line_id, 1:3)       # the earlier result file outlives the graph
  unlink(file)
  expect_error(od_betweenness(g, rbind(c(1, 1)), output_file = file), "live|pst_graph")
  expect_false(file.exists(file))
  expect_identical(rs_leftovers(dir), character())
})

test_that("file metadata records function, parameters, native graph size, order convention and CRS", {
  skip_result_file()
  skip_if_not_installed("sf")
  skip_if_not_installed("jsonlite")
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  lines <- sf::st_sf(geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(0, 0), c(100, 0))), sf::st_linestring(rbind(c(100, 0), c(100, 100))),
    sf::st_linestring(rbind(c(50, -50), c(50, 50))), crs = 32630))
  g <- axial_graph(lines); on.exit(rs_native("graph_release", g$ptr), add = TRUE)
  g$n_lines <- 999L                                   # editable R metadata must never reach the file
  meta <- function() rs_pq(file)$GetSchema()$metadata
  network_integration(g, radius = analysis_radius(steps = 2), output_file = file)
  md <- meta(); status <- rPSTool:::.pst_engine_pin()
  expect_identical(md[["rpst:function"]], "network_integration")
  expect_identical(md[["rpst:graph_type"]], "axial")
  expect_identical(md[["rpst:graph_rows"]], "3")
  expect_identical(md[["rpst:pst_commit"]], unname(status[["pst_commit"]]))
  expect_identical(md[["rpst:id_base"]], "1")
  expect_match(md[["rpst:order"]], "native line order")
  expect_match(md[["rpst:crs_wkt"]], "UTM zone 30N")
  p <- jsonlite::fromJSON(md[["rpst:parameters"]], simplifyVector = TRUE)
  expect_null(p$radius$walking); expect_equal(p$radius$steps, 2); expect_null(p$radius$straight)
  network_reach(g, origins = rbind(c(10, 0), c(90, 10)), output_file = file, overwrite = TRUE)
  md <- meta()
  expect_identical(md[["rpst:function"]], "network_reach")
  expect_match(md[["rpst:order"]], "supplied origin row order")
  expect_equal(jsonlite::fromJSON(md[["rpst:parameters"]])$origins, 2)
  od_betweenness(g, rbind(c(10, 0)), distance = "angular", destination_mode = "closest",
                     output_file = file, overwrite = TRUE)
  p <- jsonlite::fromJSON(meta()[["rpst:parameters"]])
  expect_identical(p$distance, "angular"); expect_identical(p$destination_mode, "closest")
  attraction_reach(g, rbind(c(10, 10), c(80, 10)), origin = "junctions", distance = "steps", decay = "power",
                       decay_constant = 2, collection = "max", attraction_values = capacity_c_1_3,
                       output_file = file, overwrite = TRUE)
  md <- meta(); p <- jsonlite::fromJSON(md[["rpst:parameters"]])
  expect_identical(md[["rpst:function"]], "attraction_reach")
  expect_match(md[["rpst:order"]], "junction order")
  expect_identical(p$origin, "junctions"); expect_identical(p$decay, "power"); expect_equal(p$decay_constant, 2)
  expect_equal(p$attraction_points, 2); expect_equal(p$attraction_values, 2)   # sizes only, never the data
  attraction_distance(g, rbind(c(10, 10)), point_edge_weight = 0.5, destination_indices = FALSE,
                          output_file = file, overwrite = TRUE)
  p <- jsonlite::fromJSON(meta()[["rpst:parameters"]])
  expect_equal(p$point_edge_weight, 0.5); expect_false(p$destination_indices)
})

test_that("graphs are reused and not rebuilt, and the native result owners balance", {
  skip_result_file()
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  g <- axial_graph(cbind(0:5, 0, 1:6, 0), points = rbind(c(0.5, 0.5), c(4.5, 0.5)))
  pointer <- g$ptr
  on.exit(rs_native("graph_release", g$ptr), add = TRUE)
  before <- rs_baseline()
  lifecycle <- .Call(rPSTool:::C_rpst_graph_lifecycle)
  for (i in 1:5) {
    network_integration(g, output_file = file, overwrite = TRUE)
    network_reach(g, output_file = file, overwrite = TRUE)
    od_betweenness(g, rbind(c(1, 1)), output_file = file, overwrite = TRUE)
    attraction_reach(g, rbind(c(1, 1)), output_file = file, overwrite = TRUE)
    attraction_distance(g, rbind(c(1, 1)), output_file = file, overwrite = TRUE)
  }
  expect_identical(g$ptr, pointer)
  expect_identical(.Call(rPSTool:::C_rpst_graph_lifecycle), lifecycle)   # no graph created or freed by analyses
  expect_true(rs_balanced(before))
  expect_identical(rs_leftovers(dir), character())
  # in-memory calls are unaffected after file calls
  expect_identical(network_reach(g)$line_id, 1:6)
})

test_that("multi-batch files from the new stream entry points equal the in-memory results, with signed indices intact", {
  skip_result_file()
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  g <- axial_graph(cbind(0:29, 0, 1:30, 0), points = rbind(c(0.5, 0.5), c(20.5, 0.5)))
  on.exit(rs_native("graph_release", g$ptr), add = TRUE)
  ptr <- g$ptr
  radius <- analysis_radius(steps = 3)
  pts <- rbind(c(100, 100), c(5, 1), c(25, 1))
  memory <- attraction_distance(g, pts, radius, distance = "walking")
  cols <- names(memory)
  for (batch in c(1, 7, 29, 30, 31, 1000)) {
    out <- NULL
    expect_no_error(out <- rPSTool:::.pst_write_result_file(file, TRUE, columns = cols, expected_rows = NA_real_,
      batch_rows = batch, export = function(stream, batch_rows)
        .Call(rPSTool:::C_rpst_attraction_distance_stream, ptr, radius, "lines", "walking", pts, NULL, NULL, NULL, 0,
              TRUE, stream, cols, "rpst:test", "batch", batch_rows)))
    expect_identical(out$rows, 30L)
    rs_expect_same(rs_read(file), memory)
    expect_identical(rs_pq(file)$num_row_groups, as.integer(ceiling(30 / batch)))
  }
  # Integration through its stream entry point, one row per batch
  memory <- network_integration(g, steps = 4)
  cols <- names(memory)
  rPSTool:::.pst_write_result_file(file, TRUE, columns = cols, expected_rows = NA_real_, batch_rows = 1,
    export = function(stream, batch_rows)
      .Call(rPSTool:::C_rpst_network_integration_stream, ptr, 4, stream, cols, character(), character(), batch_rows))
  rs_expect_same(rs_read(file), memory)
})

test_that("the new native stream entry points validate every argument before running or exporting anything", {
  skip_result_file()
  g <- axial_graph(cbind(0:2, 0, 1:3, 0), points = rbind(c(0.5, 0.5)))
  s <- segment_graph(rbind(c(0, 0, 3, 0), c(3, 0, 3, 3)))
  on.exit({ rs_native("graph_release", g$ptr); rs_native("segment_graph_release", s$ptr) }, add = TRUE)
  stream <- rs_native("arrow_stream_new"); on.exit(rs_native("arrow_stream_free", stream), add = TRUE)
  before <- rs_baseline()
  pts <- rbind(c(1, 1))
  # one wrong-sized name vector, then each class of malformed stream/metadata/batch argument, per entry point
  entries <- list(
    integration = function(...) .Call(rPSTool:::C_rpst_network_integration_stream, g$ptr, NULL, ...),
    reach = function(...) .Call(rPSTool:::C_rpst_reach_points_stream, g$ptr, analysis_radius(), NULL, ...),
    od = function(...) .Call(rPSTool:::C_rpst_od_betweenness_stream, g$ptr, pts, analysis_radius(), "walking", "all", NULL, NULL, ...),
    attraction_reach = function(...) .Call(rPSTool:::C_rpst_attraction_reach_stream, g$ptr, analysis_radius(), "lines", "steps",
                                           pts, NULL, NULL, NULL, "constant", 0, "divide", "mean", ...),
    attraction_distance = function(...) .Call(rPSTool:::C_rpst_attraction_distance_stream, g$ptr, analysis_radius(), "lines",
                                              "steps", pts, NULL, NULL, NULL, 0, TRUE, ...))
  widths <- c(integration = 4L, reach = 4L, od = 2L, attraction_reach = 2L, attraction_distance = 3L)
  for (name in names(entries)) {
    cols <- paste0("c", seq_len(widths[[name]]))
    go <- function(stream_arg = stream, names_ = cols, mn = character(), mv = character(), batch = 1000)
      entries[[name]](stream_arg, names_, mn, mv, batch)
    expect_error(go(names_ = cols[-1]), "exactly", info = name)
    expect_error(go(names_ = c(cols[-1], NA)), "non-missing, non-empty", info = name)
    expect_error(go(mn = "a"), "named character vector", info = name)
    expect_error(go(mn = "", mv = "x"), "keys must be non-empty", info = name)
    expect_error(go(batch = 0), "batch size", info = name)
    expect_error(go(batch = "1"), "batch size", info = name)
    expect_error(go(stream_arg = NULL), info = name)
    expect_error(go(stream_arg = g$ptr), info = name)           # a graph pointer is not a stream
    expect_false(rs_native("arrow_stream_is_live", stream), info = name)
  }
  # wrong graph family at the native boundary
  expect_error(.Call(rPSTool:::C_rpst_network_integration_stream, s$ptr, NULL, stream, paste0("c", 1:4), character(),
                     character(), 10), "pst_graph|axial|tag|live")
  # junction results have no file route at the native boundary either
  expect_true(rs_balanced(before))
})

test_that("a failure inside PST after the arguments are valid leaves no stream, no file and balanced owners", {
  skip_result_file()
  dir <- tempfile("rpst-out-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "r.parquet")
  g <- axial_graph(cbind(0:2, 0, 1:3, 0), points = rbind(c(0.5, 0.5)))
  on.exit(rs_native("graph_release", g$ptr), add = TRUE)
  before <- rs_baseline()
  # polygon sampling bounds are checked natively (after validation, inside the native scope)
  ring <- rbind(c(0, 0), c(1e12, 0), c(1e12, 1e12))
  expect_error(attraction_reach(g, ring, points_per_polygon = 3, polygon_point_interval = 1, output_file = file),
               "exceeds PST's native signed point-count")
  expect_error(attraction_distance(g, ring, points_per_polygon = 3, polygon_point_interval = 1,
                                       output_file = file), "Polygon sampling")
  expect_false(file.exists(file))
  expect_identical(rs_leftovers(dir), character())
  expect_true(rs_balanced(before))
})

test_that("the public network_integration() rejects non-steps radii also when writing a result file", {
  skip_result_file()
  g <- axial_graph(rbind(c(0, 0, 2, 0), c(1, -1, 1, 1))); on.exit(ra_release(list(g)), add = TRUE)
  file <- tempfile(fileext = ".parquet"); on.exit(unlink(file), add = TRUE)
  expect_error(network_integration(g, radius = analysis_radius(straight = 5), output_file = file),
               "supports only a topological steps radius")
  expect_false(file.exists(file))
})
