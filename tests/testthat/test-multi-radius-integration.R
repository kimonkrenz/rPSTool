# Multi-radius Network Integration, including junction results (docs/compatibility/multi-radius.md). The supported radius field stays
# steps (as in the official PST for QGIS plugin): several steps values are a multi-radius; every other field is refused as before.
# Every multi column must equal the independently executed scalar call; PST runs once per radius; the file route holds the same table
# as the in-memory result. Parquet checks need the optional arrow package and are skipped (not weakened) where it is missing.

ni_segments <- function() {
  set.seed(11)
  n <- 40
  x <- cumsum(runif(n, 1, 3)); y <- cumsum(rnorm(n))
  s <- cbind(x[-n], y[-n], x[-1], y[-1])
  unname(rbind(s, cbind(s[8:22, 1], s[8:22, 2], s[8:22, 1] + 1, s[8:22, 2] + 5)))
}
ni_graph <- function() axial_graph(ni_segments())
ni_counts <- function(reset = FALSE) .Call(rPSTool:::C_rpst_axial_instrumentation, reset, NULL)
ni_fail_after <- function(k) invisible(.Call(rPSTool:::C_rpst_axial_instrumentation, FALSE, as.double(k)))
ni_skip_fgb <- function() { skip_if_not_installed("sf"); skip_if_not_installed("jsonlite") }
ni_meta <- function(path) {
  raw <- .Call(rPSTool:::C_rpst_fgb_columns, enc2native(path))$metadata
  jsonlite::fromJSON(rawToChar(raw), simplifyVector = FALSE)
}
ni_steps <- function(...) analysis_radius(steps = c(...))
ni_fgb_graph <- function(dir, n = 30) {
  src <- so_write_fgb(file.path(dir, "net.fgb"), so_segments(n))
  list(src = src, g = axial_graph(src))
}

test_that("every line column equals the scalar call, in the supplied order, with the scalar names, values and types", {
  g <- ni_graph()
  for (steps in list(c(1, 2, 3), c(4, 0, 2), c(2, 5), c(3, 1, 2147483647))) {
    multi <- network_integration(g, radius = ni_steps(steps))
    k <- length(steps)
    expect_identical(ncol(multi), 1L + 3L * k)
    expect_identical(multi$line_id, seq_len(nrow(multi)))
    manifest <- attr(multi, "rpst_manifest")
    expect_identical(manifest$columns$radius, rep(seq_len(k), each = 3L))
    expect_identical(manifest$columns$role, rep(c("integration", "node_count", "total_depth"), k))
    expect_true(all(is.na(manifest$columns$normalization)))
    expect_length(manifest$radii, k)
    seen <- character()
    for (i in seq_len(k)) {
      scalar <- network_integration(g, steps = steps[[i]])
      expect_null(attr(scalar, "rpst_manifest"))
      for (nm in setdiff(names(scalar), "line_id")) {
        expect_identical(multi[[nm]], scalar[[nm]], info = nm)          # exact values and types
        seen <- c(seen, nm)
      }
    }
    expect_identical(setdiff(names(multi), "line_id"), seen)           # nothing else, in the supplied order
    expect_false(anyDuplicated(names(multi)) > 0)
  }
  m <- network_integration(g, radius = ni_steps(3, 1, 2))
  expect_identical(names(m), c("line_id", "ni_s_rs3", "nc_s_rs3", "td_s_rs3", "ni_s_rs1", "nc_s_rs1", "td_s_rs1",
                               "ni_s_rs2", "nc_s_rs2", "td_s_rs2"))
  expect_identical(vapply(m, typeof, "")[2:4], c(ni_s_rs3 = "double", nc_s_rs3 = "integer", td_s_rs3 = "double"))
})

test_that("scalar calls keep the scalar schema; a one-element steps vector is a scalar call", {
  g <- ni_graph()
  expect_null(attr(network_integration(g), "rpst_manifest"))
  expect_null(attr(network_integration(g, steps = 2), "rpst_manifest"))
  expect_null(attr(network_integration(g, radius = analysis_radius(steps = 2)), "rpst_manifest"))
  expect_identical(names(network_integration(g, steps = 2)), c("line_id", "ni_s_rs2", "nc_s_rs2", "td_s_rs2"))
  expect_identical(network_integration(g, radius = ni_steps(2)), network_integration(g, steps = 2))
  expect_identical(names(network_integration(g)), c("line_id", "ni_s_rg", "nc_s_rg", "td_s_rg"))
  expect_identical(names(network_integration(g, junctions = TRUE)$junctions), c("junction_id", "x", "y", "nj_s_rg"))
})

test_that("junction results: shared coordinates and one score column per radius equal the scalar junction tables", {
  g <- ni_graph()
  steps <- c(1, 3, 2)
  multi <- network_integration(g, radius = ni_steps(steps), junctions = TRUE)
  expect_named(multi, c("lines", "junctions"))
  expect_identical(multi$lines, network_integration(g, radius = ni_steps(steps)))
  scalar <- lapply(steps, function(s) network_integration(g, steps = s, junctions = TRUE))
  j <- multi$junctions
  expect_identical(names(j), c("junction_id", "x", "y", "nj_s_rs1", "nj_s_rs3", "nj_s_rs2"))
  expect_identical(j$junction_id, seq_len(nrow(j)))
  expect_gt(nrow(j), 0L)
  for (i in seq_along(steps)) {
    sj <- scalar[[i]]$junctions
    expect_identical(j$x, sj$x); expect_identical(j$y, sj$y)           # junction positions are radius independent
    expect_identical(j[[names(sj)[4L]]], sj[[names(sj)[4L]]])
    expect_identical(scalar[[i]]$lines, network_integration(g, steps = steps[[i]]))
  }
  # the same table with sf points
  skip_if_not_installed("sf")
  s <- network_integration(g, radius = ni_steps(steps), junctions = TRUE, junction_output = "sf")
  expect_s3_class(s$junctions, "sf")
  expect_identical(names(s$junctions), c("junction_id", names(j)[-(1:3)], "geometry"))
  expect_identical(sf::st_coordinates(s$junctions)[, 1], j$x)
  expect_identical(sf::st_coordinates(s$junctions)[, 2], j$y)
  for (nm in names(j)[-(1:3)]) expect_identical(s$junctions[[nm]], j[[nm]])
  expect_identical(s$lines, multi$lines)
  # with a CRS the points carry it, as in a scalar call
  scalar_sf <- network_integration(g, steps = 2, junctions = TRUE, junction_output = "sf")
  expect_identical(sf::st_crs(s$junctions), sf::st_crs(scalar_sf$junctions))
  # a graph without crossings gives a zero-row junction table for every radius
  flat <- axial_graph(rbind(c(0, 0, 3, 0), c(0, 5, 3, 5)))
  none <- network_integration(flat, radius = ni_steps(1, 2), junctions = TRUE)
  expect_identical(nrow(none$junctions), 0L)
  expect_identical(names(none$junctions), c("junction_id", "x", "y", "nj_s_rs1", "nj_s_rs2"))
  expect_identical(nrow(network_integration(flat, steps = 1, junctions = TRUE)$junctions), 0L)
  # junction_output = "sf" still needs junctions = TRUE
  expect_error(network_integration(g, radius = ni_steps(1, 2), junction_output = "sf"), "requires junctions = TRUE")
})

test_that("the steps-only rule and every scalar rule hold for a vector, and refuse before any calculation", {
  g <- ni_graph()
  ni_counts(TRUE)
  expect_error(network_integration(g, radius = analysis_radius(walking = c(5, 10))), "steps radius")
  expect_error(network_integration(g, radius = analysis_radius(straight = c(5, 10))), "steps radius")
  expect_error(network_integration(g, radius = analysis_radius(angular = c(5, 10))), "steps radius")
  expect_error(network_integration(g, radius = analysis_radius(axmeter = c(5, 10))), "steps radius")
  expect_error(network_integration(g, radius = analysis_radius(steps = c(1, 2), walking = 5)), "steps radius")   # a fixed non-steps limit
  expect_error(network_integration(g, radius = analysis_radius(steps = c(1, 2), angular = 90), junctions = TRUE), "steps radius")
  expect_error(network_integration(g, steps = 1, radius = ni_steps(1, 2)), "either steps or radius")
  expect_error(network_integration(g, steps = c(1, 2)), "steps must be NULL or one")                              # the steps argument stays scalar
  expect_error(analysis_radius(steps = c(1, 1)), "duplicate")
  expect_error(analysis_radius(steps = c(1, 2), walking = c(1, 2)), "At most one")
  expect_error(analysis_radius(steps = c(1, 2.5)), "whole number")
  expect_error(analysis_radius(steps = c(1, NA)), "NA|whole number")
  expect_error(analysis_radius(steps = c(1, 2147483648)), "2147483647|finite non-negative")
  expect_error(network_integration(g, radius = ni_steps(1, 2), junction_output = "bogus"), "arg")
  expect_error(network_integration(segment_graph(ni_segments()), radius = ni_steps(1, 2)), "axial")
  expect_error(network_integration(g, radius = ni_steps(1, 2), overwrite = NA, output_file = tempfile()), "overwrite")
  expect_identical(ni_counts(TRUE)[4L], 0)      # no PST run happened for any of them
  # an analysis outside the registry still refuses a vector (Attraction Reach/Distance and OD Betweenness accept one since test-multi-radius-attraction.R)
  expect_error(rPSTool:::.pst_validate_radius(analysis_radius(steps = c(1, 2))), "supported only by")
  expect_error(network_integration(g, radius = list(steps = c(1, 2))), "analysis_radius")
})

test_that("junctions must be TRUE or FALSE for a multi-radius call, before any calculation and with or without file output", {
  g <- ni_graph()
  ni_counts(TRUE)
  dir <- tempfile("ni-junctions-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE))
  for (bad in list(NA, 1, 0L, "TRUE", "yes", c(TRUE, FALSE), logical(), NULL, NA_integer_, list(TRUE))) {
    expect_error(network_integration(g, radius = ni_steps(1, 2), junctions = bad), "junctions must be TRUE or FALSE", info = deparse(bad))
    expect_error(network_integration(g, radius = ni_steps(1, 2), junctions = bad, junction_output = "sf"), "junctions must be TRUE or FALSE", info = deparse(bad))
    expect_error(network_integration(g, radius = ni_steps(1, 2), junctions = bad, output_file = file.path(dir, "o.parquet")),
                 "junctions must be TRUE or FALSE", info = deparse(bad))
    expect_error(network_integration(g, radius = ni_steps(1, 2), junctions = bad, spatial_output_file = file.path(dir, "o.fgb")),
                 "junctions must be TRUE or FALSE", info = deparse(bad))
  }
  expect_identical(ni_counts(TRUE)[4L], 0)
  expect_identical(list.files(dir, all.files = TRUE, no.. = TRUE), character())
  # valid flags keep working
  expect_named(network_integration(g, radius = ni_steps(1, 2), junctions = TRUE), c("lines", "junctions"))
  expect_s3_class(network_integration(g, radius = ni_steps(1, 2), junctions = FALSE), "data.frame")
})

test_that("junction sf output of a multi-radius call carries a projected CRS, also with zero crossings", {
  ni_skip_fgb()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE))
  g <- ni_fgb_graph(dir)$g                               # a FlatGeobuf source in EPSG:32630 (UTM 30N)
  r <- ni_steps(1, 3, 2)
  multi <- network_integration(g, radius = r, junctions = TRUE, junction_output = "sf")
  scalar <- network_integration(g, steps = 3, junctions = TRUE, junction_output = "sf")
  expect_s3_class(multi$junctions, "sf")
  expect_gt(nrow(multi$junctions), 0L)
  expect_false(is.na(sf::st_crs(multi$junctions)))
  expect_identical(sf::st_crs(multi$junctions)$epsg, 32630L)
  expect_identical(sf::st_crs(multi$junctions), sf::st_crs(scalar$junctions))
  expect_identical(sf::st_crs(multi$junctions)$wkt, sf::st_crs(scalar$junctions)$wkt)
  expect_identical(sf::st_coordinates(multi$junctions), sf::st_coordinates(scalar$junctions))
  expect_identical(multi$junctions[["nj_s_rs3"]], scalar$junctions[["nj_s_rs3"]])
  expect_identical(names(multi$junctions), c("junction_id", "nj_s_rs1", "nj_s_rs3", "nj_s_rs2", "geometry"))
  # zero crossings: two disjoint lines in the same CRS
  src <- so_write_fgb(file.path(dir, "flat.fgb"), rbind(c(100, 200, 103, 200), c(100, 205, 103, 205)))
  flat <- axial_graph(src)
  none <- network_integration(flat, radius = ni_steps(1, 2), junctions = TRUE, junction_output = "sf")
  scalar_none <- network_integration(flat, steps = 1, junctions = TRUE, junction_output = "sf")
  expect_s3_class(none$junctions, "sf")
  expect_identical(nrow(none$junctions), 0L)
  expect_identical(names(none$junctions), c("junction_id", "nj_s_rs1", "nj_s_rs2", "geometry"))
  expect_identical(sf::st_crs(none$junctions)$epsg, 32630L)
  expect_identical(sf::st_crs(none$junctions), sf::st_crs(scalar_none$junctions))
  expect_identical(nrow(none$lines), 2L)
  # a graph without a CRS gives sf points without one, as a scalar call does
  nocrs <- network_integration(ni_graph(), radius = ni_steps(1, 2), junctions = TRUE, junction_output = "sf")
  expect_true(is.na(sf::st_crs(nocrs$junctions)))
})

test_that("PST runs once per radius, and a failure on a later radius leaves the graph usable", {
  g <- ni_graph()
  ni_counts(TRUE)
  network_integration(g, radius = ni_steps(1, 2, 3, 4))
  expect_identical(ni_counts(TRUE)[4L], 4)
  network_integration(g, radius = ni_steps(1, 2, 3), junctions = TRUE)
  expect_identical(ni_counts(TRUE)[4L], 3)
  before <- network_integration(g, steps = 2)
  before_j <- network_integration(g, steps = 2, junctions = TRUE)
  for (k in 0:2) for (junctions in c(FALSE, TRUE)) {
    ni_fail_after(k)
    expect_error(network_integration(g, radius = ni_steps(1, 2, 3), junctions = junctions), "injected native failure")
    ni_fail_after(-1)
  }
  expect_identical(network_integration(g, steps = 2), before)
  expect_identical(network_integration(g, steps = 2, junctions = TRUE), before_j)
  expect_identical(nrow(network_integration(g, radius = ni_steps(1, 2))), nrow(before))
})

test_that("PST's special values are returned unchanged for every radius", {
  g <- axial_graph(cbind(c(0, 3), 0, c(3, 6), 0))        # two lines: -1 / NaN / Inf cases arise for small neighbourhoods
  m <- network_integration(g, radius = ni_steps(0, 1, 2))
  for (s in 0:2) {
    sc <- network_integration(g, steps = s)
    for (nm in setdiff(names(sc), "line_id")) expect_identical(m[[nm]], sc[[nm]], info = nm)
  }
})

test_that("FlatGeobuf output of multi-radius Network Integration equals the in-memory result and records schema 2", {
  ni_skip_fgb()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE))
  s <- ni_fgb_graph(dir); g <- s$g
  frame <- network_integration(g, radius = ni_steps(2, 1, 3))
  out <- file.path(dir, "ni.fgb")
  res <- network_integration(g, radius = ni_steps(2, 1, 3), spatial_output_file = out)
  expect_s3_class(res, "pst_result_file")
  expect_identical(so_leftovers(dir), character())
  back <- so_read(out, "flatgeobuf")
  result_names <- setdiff(names(frame), "line_id")
  expect_identical(back$names, c(names(so_attributes(30)), result_names))
  for (col in result_names) {
    expect_identical(is.na(back$attrs[[col]]), is.na(frame[[col]]), info = col)
    expect_equal(as.numeric(back$attrs[[col]]), as.numeric(frame[[col]]), tolerance = 0, info = col)
  }
  expect_identical(back$wkb, so_wkb_of(s$src))
  meta <- ni_meta(out)
  expect_identical(meta[["rpst:schema"]], "2")
  expect_identical(meta[["rpst:function"]], "network_integration")
  expect_identical(meta[["rpst:graph_type"]], "axial")
  expect_identical(meta[["rpst:graph_rows"]], "30")
  expect_identical(meta[["rpst:radius_varying"]], "steps")
  cols <- jsonlite::fromJSON(meta[["rpst:columns"]], simplifyVector = FALSE)
  expect_identical(vapply(cols, function(x) x$name, ""), result_names)
  expect_equal(vapply(cols, function(x) x$radius, 1), rep(1:3, each = 3))
  expect_length(jsonlite::fromJSON(meta[["rpst:radius_configurations"]], simplifyVector = FALSE), 3L)
  # scalar file schema unchanged
  out1 <- file.path(dir, "scalar.fgb")
  network_integration(g, steps = 2, spatial_output_file = out1)
  expect_identical(ni_meta(out1)[["rpst:schema"]], "1")
})

test_that("multi-radius file output keeps the junction contract, collision, overwrite and failure guarantees", {
  ni_skip_fgb()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE))
  g <- ni_fgb_graph(dir)$g
  r <- ni_steps(1, 2, 3)
  out <- file.path(dir, "out.fgb")
  # a result file cannot hold junction results, scalar or not; nothing is created
  expect_error(network_integration(g, radius = r, junctions = TRUE, spatial_output_file = out), "one result per junction|junction")
  expect_error(network_integration(g, radius = r, junctions = TRUE, output_file = file.path(dir, "o.parquet")), "junction")
  expect_error(network_integration(g, steps = 2, junctions = TRUE, spatial_output_file = out), "one result per junction|junction")
  expect_false(file.exists(out))
  network_integration(g, radius = r, spatial_output_file = out)
  md5 <- so_md5(out)
  expect_error(network_integration(g, radius = r, spatial_output_file = out), "already exists")
  expect_identical(so_md5(out), md5)
  ni_fail_after(1)
  expect_error(network_integration(g, radius = r, spatial_output_file = out, overwrite = TRUE), "injected native failure")
  ni_fail_after(-1)
  expect_identical(so_md5(out), md5)
  fresh <- file.path(dir, "fresh.fgb")
  ni_fail_after(2)
  expect_error(network_integration(g, radius = r, spatial_output_file = fresh), "injected native failure")
  ni_fail_after(-1)
  expect_false(file.exists(fresh))
  expect_identical(so_leftovers(dir), character())
  expect_s3_class(network_integration(g, radius = ni_steps(2, 3), spatial_output_file = out, overwrite = TRUE), "pst_result_file")
  expect_false(identical(so_md5(out), md5))
  expect_identical(nrow(network_integration(g, steps = 2)), 30L)
  ni_counts(TRUE)
  expect_error(network_integration(g, radius = analysis_radius(steps = c(1, 2), walking = 3), spatial_output_file = file.path(dir, "x.fgb")), "steps radius")
  expect_error(network_integration(g, radius = r, spatial_output_file = file.path(dir, "x.parquet")), "must end in")
  expect_identical(ni_counts(TRUE)[4L], 0)
  expect_identical(sort(list.files(dir)), sort(c("net.fgb", "out.fgb")))
})

test_that("Parquet and GeoParquet output of multi-radius Network Integration equals the in-memory result", {
  skip_if_not_installed("sf"); skip_if_not_installed("jsonlite"); skip_if_not_installed("arrow", "25.0.0")
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE))
  g <- ni_graph()
  frame <- network_integration(g, radius = ni_steps(1, 3, 2))
  path <- file.path(dir, "ni.parquet")
  res <- network_integration(g, radius = ni_steps(1, 3, 2), output_file = path)
  expect_s3_class(res, "pst_result_file")
  expect_identical(res$columns, names(frame))
  expect_identical(res$rows, nrow(frame))
  t <- rs_read_parquet(path, as_data_frame = FALSE)
  expect_identical(names(t), names(frame))
  d <- as.data.frame(t)
  expect_identical(d$line_id, frame$line_id)
  for (nm in setdiff(names(frame), "line_id")) {
    expect_identical(is.na(d[[nm]]), is.na(frame[[nm]]), info = nm)
    expect_identical(as.numeric(d[[nm]]), as.numeric(frame[[nm]]), info = nm)
  }
  meta <- t$schema$metadata
  expect_identical(meta[["rpst:schema"]], "2")
  expect_identical(meta[["rpst:graph_type"]], "axial")
  expect_error(network_integration(g, radius = ni_steps(1, 3, 2), output_file = path), "already exists")
  ni_fail_after(1)
  fresh <- file.path(dir, "fresh.parquet")
  expect_error(network_integration(g, radius = ni_steps(1, 3, 2), output_file = fresh), "injected native failure")
  ni_fail_after(-1)
  expect_false(file.exists(fresh))
  expect_identical(so_leftovers(dir), character())
  # GeoParquet
  src <- so_write_gpq(file.path(dir, "net.parquet"), so_segments(30), chunk = 7L)
  gg <- axial_graph(src)
  gf <- network_integration(gg, radius = ni_steps(2, 1))
  out <- file.path(dir, "geo.parquet")
  network_integration(gg, radius = ni_steps(2, 1), spatial_output_file = out)
  back <- so_read(out, "geoparquet")
  for (nm in setdiff(names(gf), "line_id")) {
    expect_identical(is.na(back$attrs[[nm]]), is.na(gf[[nm]]), info = nm)
    expect_identical(as.numeric(back$attrs[[nm]]), as.numeric(gf[[nm]]), info = nm)
  }
  # geometry, CRS and metadata
  original <- as.data.frame(rs_read_parquet(src, as_data_frame = FALSE))
  expect_identical(back$wkb, unclass(original$geometry))                                   # geometry byte for byte
  src_md <- rs_read_parquet(src, as_data_frame = FALSE)$schema$metadata
  out_md <- rs_read_parquet(out, as_data_frame = FALSE)$schema$metadata
  expect_identical(out_md[["geo"]], src_md[["geo"]])                                       # GeoParquet metadata and CRS unchanged
  expect_match(out_md[["geo"]], "32630|UTM")
  expect_identical(out_md[["other_key"]], "kept")
  expect_identical(out_md[["rpst:schema"]], "2")
  expect_identical(out_md[["rpst:function"]], "network_integration")
  expect_identical(out_md[["rpst:graph_type"]], "axial")
  expect_identical(out_md[["rpst:graph_rows"]], "30")
  expect_identical(out_md[["rpst:radius_varying"]], "steps")
  cols <- jsonlite::fromJSON(out_md[["rpst:columns"]], simplifyVector = FALSE)
  expect_identical(vapply(cols, function(x) x$name, ""), setdiff(names(gf), "line_id"))
  expect_equal(vapply(cols, function(x) x$radius, 1), rep(1:2, each = 3))
  expect_identical(rs_pq(out)$num_row_groups, rs_pq(src)$num_row_groups)                   # row-group layout survives
  expect_identical(so_leftovers(dir), character())
  # the source's own attributes are carried over untouched
  for (nm in names(so_attributes(30))) expect_identical(back$attrs[[nm]], original[[nm]])
})
