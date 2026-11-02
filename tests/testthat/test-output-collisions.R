# Existing-column collisions are decided in a preflight, BEFORE any native analytical calculation runs
# (docs/spatial-io/spatial-output.md, docs/output-naming.md). The proof that the native calculation was not started does not
# rest on "no output file exists": every native analysis entry point is replaced by an unmistakable sentinel, so a calculation
# that did start would fail with the sentinel's own error instead of the collision message.

col_analysis_symbols <- c(
  "C_rpst_angular_choice", "C_rpst_angular_choice_stream", "C_rpst_angular_choice_controls", "C_rpst_angular_integration_controls", "C_rpst_network_integration_outputs", "C_rpst_angular_choice_multi", "C_rpst_angular_choice_multi_stream",
  "C_rpst_angular_integration", "C_rpst_angular_integration_stream", "C_rpst_angular_integration_multi",
  "C_rpst_angular_integration_multi_stream", "C_rpst_attraction_distance", "C_rpst_attraction_distance_stream",
  "C_rpst_attraction_reach", "C_rpst_attraction_reach_stream", "C_rpst_betweenness", "C_rpst_betweenness_weighted",
  "C_rpst_betweenness_weighted_stream", "C_rpst_network_integration", "C_rpst_network_integration_stream",
  "C_rpst_od_betweenness", "C_rpst_od_betweenness_stream", "C_rpst_reach", "C_rpst_reach_points", "C_rpst_reach_points_stream",
  "C_rpst_segment_group_integration", "C_rpst_segment_group_integration_stream")
# .Call() rejects the sentinel with one of two messages, depending on how the entry point is registered; either one means
# "the native calculation was reached".
col_sentinel <- "rpst_native_calculation_was_invoked|requires the use of native symbols"
col_sentinel_value <- "rpst_native_calculation_was_invoked"
col_mock_native <- function(env = parent.frame()) {
  args <- stats::setNames(rep(list(col_sentinel_value), length(col_analysis_symbols)), col_analysis_symbols)
  do.call(testthat::local_mocked_bindings, c(args, list(.package = "rPSTool", .env = env)))
}
col_fgb_segments <- function(dir, names) {
  m <- so_segments(); a <- so_attributes(nrow(m)); for (n in names) a[[n]] <- seq_len(nrow(m)) * 100
  so_write_fgb(file.path(dir, "src.fgb"), m, attrs = a)
}
col_fgb_axial <- function(dir, names) {
  m <- so_segments(); a <- so_attributes(nrow(m)); for (n in names) a[[n]] <- seq_len(nrow(m)) * 100
  so_write_fgb(file.path(dir, "axsrc.fgb"), m, attrs = a)
}

test_that("the sentinel really replaces the native entry points (positive control)", {
  skip_if_not_installed("sf")
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  g <- segment_graph(col_fgb_segments(dir, character()))
  col_mock_native()
  expect_error(rPSTool::angular_choice(g, radius = analysis_radius(steps = 2), spatial_output_file = file.path(dir, "o.fgb")), col_sentinel)
  expect_error(rPSTool::angular_choice(g, radius = analysis_radius(steps = 2)), col_sentinel)
})

test_that("an exact collision stops before native computation when overwrite = FALSE, and leaves everything untouched", {
  skip_if_not_installed("sf")
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  src <- col_fgb_segments(dir, c("ac_a_rs2_n", "td_a_rs2"))
  before <- so_md5(src); g <- segment_graph(src); out <- file.path(dir, "o.fgb")
  col_mock_native()
  expect_error(rPSTool::angular_choice(g, radius = analysis_radius(steps = 2), spatial_output_file = out),
               "already exist in the source: ac_a_rs2_n, td_a_rs2.*overwrite = TRUE")
  expect_false(file.exists(out)); expect_length(so_leftovers(dir), 0L); expect_identical(so_md5(src), before)
  # with overwrite = TRUE the preflight passes and the (sentinel) native calculation is reached
  expect_error(rPSTool::angular_choice(g, radius = analysis_radius(steps = 2), spatial_output_file = out, overwrite = TRUE), col_sentinel)
  expect_false(file.exists(out))
})

test_that("a case-only collision stops before native computation, with or without overwrite", {
  skip_if_not_installed("sf")
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  src <- col_fgb_segments(dir, "AC_A_RS2_N"); before <- so_md5(src); g <- segment_graph(src); out <- file.path(dir, "o.fgb")
  col_mock_native()
  for (ow in c(FALSE, TRUE)) {
    expect_error(rPSTool::angular_choice(g, radius = analysis_radius(steps = 2), spatial_output_file = out, overwrite = ow), "only by letter case")
    expect_false(file.exists(out))
  }
  expect_identical(so_md5(src), before)
})

test_that("axial analyses with custom weights are checked before native computation too", {
  skip_if_not_installed("sf")
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  src <- col_fgb_axial(dir, c("nb_s_rs2_wpopulation_n"))
  g <- axial_graph(src); out <- file.path(dir, "o.fgb"); before <- so_md5(src)
  col_mock_native()
  w <- rep(1, g$n_lines)
  expect_error(rPSTool::network_betweenness(g, analysis_radius(steps = 2), weights = w, weight_name = "Population", spatial_output_file = out),
               "already exist in the source: nb_s_rs2_wpopulation_n")
  expect_false(file.exists(out)); expect_identical(so_md5(src), before)
  # names that normalise to the same identifier name the same column, so they collide as well
  expect_error(rPSTool::network_betweenness(g, analysis_radius(steps = 2), weights = w, weight_name = "POPULATION (%)", spatial_output_file = out),
               "already exist in the source: nb_s_rs2_wpopulation_n")
  expect_false(file.exists(out))
  # a different weight name is a different quantity: no collision, the calculation starts
  expect_error(rPSTool::network_betweenness(g, analysis_radius(steps = 2), weights = w, weight_name = "jobs", spatial_output_file = out),
               col_sentinel)
})

test_that("name validation precedes both collision handling and native computation", {
  skip_if_not_installed("sf")
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  g <- axial_graph(col_fgb_axial(dir, character())); col_mock_native()
  w <- rep(1, g$n_lines)
  expect_error(rPSTool::network_betweenness(g, weights = w), "Custom weights require weight_name")
  expect_error(rPSTool::network_betweenness(g, weights = w, weight_name = "%%"), "weight_name")
  expect_error(rPSTool::network_betweenness(g, weights = w, weight_name = "%%", spatial_output_file = file.path(dir, "o.fgb")), "weight_name")
  expect_false(file.exists(file.path(dir, "o.fgb")))
})

test_that("duplicate generated names are rejected before native computation, in memory as well as to files", {
  nm <- rPSTool:::.pst_nm_names
  mk <- function(...) lapply(c(...), function(n) list(name = n))
  expect_identical(nm(mk("a", "b")), c("a", "b"))
  expect_error(nm(mk("a", "b", "a")), "duplicate result column names: a")
  expect_error(nm(mk("ai_a_rs3_t", "AI_A_RS3_T")), "duplicate result column names")
  skip_if_not_installed("sf")
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  g <- segment_graph(col_fgb_segments(dir, character()))
  col_mock_native()
  testthat::local_mocked_bindings(.pst_nm_angular_choice = function(...) list(list(name = "x"), list(name = "X")), .package = "rPSTool")
  expect_error(rPSTool::angular_choice(g, radius = analysis_radius(steps = 2)), "duplicate result column names")
  expect_error(rPSTool::angular_choice(g, radius = analysis_radius(steps = 2), spatial_output_file = file.path(dir, "o.fgb")), "duplicate result column names")
  expect_false(file.exists(file.path(dir, "o.fgb")))
})

test_that("overwrite = TRUE replaces only the colliding columns, in the new file, and preserves everything else", {
  skip_if_not_installed("sf")
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  src <- col_fgb_segments(dir, c("ac_a_rs2_n", "keep_me")); before <- so_md5(src)
  g <- segment_graph(src); out <- file.path(dir, "o.fgb")
  res <- rPSTool::angular_choice(g, radius = analysis_radius(steps = 2), spatial_output_file = out, overwrite = TRUE)
  expect_identical(res$replaced, "ac_a_rs2_n"); expect_identical(res$appended, c("nc_a_rs2", "td_a_rs2"))
  a <- sf::st_read(src, quiet = TRUE); b <- sf::st_read(out, quiet = TRUE)
  expect_identical(names(b), c(setdiff(names(a), "geometry")[seq_along(setdiff(names(a), "geometry"))], "nc_a_rs2", "td_a_rs2", "geometry"))
  expect_identical(b$keep_me, a$keep_me); expect_identical(b$osm_id, a$osm_id)                     # unrelated attributes
  expect_identical(sf::st_as_binary(sf::st_geometry(b)), sf::st_as_binary(sf::st_geometry(a)))    # geometry and order
  expect_identical(sf::st_crs(b), sf::st_crs(a))
  mem <- rPSTool::angular_choice(g, radius = analysis_radius(steps = 2))
  expect_equal(b$ac_a_rs2_n, mem$ac_a_rs2_n, tolerance = 0)
  expect_identical(so_md5(src), before)                                                             # source unchanged
})
