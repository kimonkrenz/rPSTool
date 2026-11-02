# Multi-radius / multi-normalisation file output through the Parquet and GeoParquet writers (docs/compatibility/multi-radius.md). These need
# the optional arrow package (>= 25.0.0) and are skipped (never weakened) where it is missing.

skip_multi_parquet <- function() {
  skip_if_not_installed("sf")
  skip_if_not_installed("arrow", "25.0.0")
  skip_if_not_installed("jsonlite")
}
mp_fail_after <- function(k) invisible(.Call(rPSTool:::C_rpst_angular_instrumentation, FALSE, as.double(k)))
mp_meta <- function(path) rs_read_parquet(path, as_data_frame = FALSE)$schema$metadata
mp_json <- function(x) jsonlite::fromJSON(x, simplifyVector = FALSE)
mp_same_values <- function(actual, expected) {
  expect_identical(is.nan(actual), is.nan(expected))
  expect_identical(is.infinite(actual), is.infinite(expected))
  expect_identical(as.numeric(actual), as.numeric(expected))
}

test_that("attribute-only Parquet: one combined table, schema 2 metadata, exact round trip", {
  skip_multi_parquet()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE))
  g <- segment_graph(so_write_gpq(file.path(dir, "net.parquet"), so_segments(30)))
  for (case in list(
      list(fn = rPSTool::angular_choice, args = list(radius = analysis_radius(walking = c(25, 10, 60), straight = 70, angular = 170),
                                                weigh_by_length = TRUE, normalization = c("syntax", "none", "standard", "turner"),
                                                angle_threshold = 15, angle_precision = 3),
           vary = "walking", fixed = c("straight", "angular"), roles = "choice"),
      list(fn = rPSTool::angular_integration, args = list(radius = analysis_radius(steps = c(3, 1, 2), angular = 180),
                                                     normalization = c("hillier", "turner"), weight_outputs = TRUE,
                                                     angle_threshold = 15, angle_precision = 3),
           vary = "steps", fixed = "angular", roles = "integration"))) {
    frame <- do.call(case$fn, c(list(g), case$args))
    path <- file.path(dir, paste0(case$roles, ".parquet"))
    res <- do.call(case$fn, c(list(g), case$args, list(output_file = path)))
    expect_s3_class(res, "pst_result_file")
    expect_identical(res$columns, names(frame))
    expect_identical(res$rows, 30L)
    t <- rs_read_parquet(path, as_data_frame = FALSE)
    expect_identical(names(t), names(frame))
    expect_identical(t$num_rows, 30L)
    d <- as.data.frame(t)
    expect_identical(d$segment_id, frame$segment_id)
    for (nm in setdiff(names(frame), "segment_id")) mp_same_values(d[[nm]], frame[[nm]])
    for (nm in grep("^nc_", names(frame), value = TRUE)) expect_true(t$schema$GetFieldByName(nm)$type$ToString() == "int32")
    for (nm in grep("^(ac|ai|td|tw|tdw)_", names(frame), value = TRUE)) expect_true(t$schema$GetFieldByName(nm)$type$ToString() == "float")
    md <- mp_meta(path)
    expect_identical(md[["rpst:schema"]], "2")
    expect_identical(md[["rpst:function"]], paste0("angular_", case$roles))
    expect_identical(md[["rpst:radius_varying"]], case$vary)
    expect_setequal(names(mp_json(md[["rpst:radius_fixed"]])), case$fixed)
    expect_length(mp_json(md[["rpst:radius_configurations"]]), length(case$args$radius[[case$vary]]))
    expect_identical(unlist(mp_json(md[["rpst:normalizations"]])), case$args$normalization)
    manifest <- mp_json(md[["rpst:columns"]])
    expect_identical(vapply(manifest, function(x) x$name, ""), setdiff(names(frame), "segment_id"))
    expect_true(all(c("rpst:pst_commit", "rpst:pst_version", "rpst:graph_type", "rpst:graph_rows", "rpst:id_base", "rpst:order") %in% names(md)))
    params <- mp_json(md[["rpst:parameters"]])
    expect_equal(params$angle_threshold, 15); expect_equal(params$angle_precision, 3)
    expect_identical(md[["rpst:pst_commit"]], unname(rPSTool:::.pst_engine_pin()[["pst_commit"]]))
  }
  # a scalar call keeps schema 1; it now carries the same column manifest as the multi-result schema
  scalar <- file.path(dir, "scalar.parquet")
  angular_choice(g, analysis_radius(walking = 25), normalization = "syntax", output_file = scalar)
  expect_identical(mp_meta(scalar)[["rpst:schema"]], "1")
  expect_identical(vapply(mp_json(mp_meta(scalar)[["rpst:columns"]]), function(x) x$name, ""),
                   c("ac_a_rw25_n", "nc_a_rw25", "td_a_rw25", "ac_a_rw25_c"))
  expect_identical(names(rs_read_parquet(scalar)), c("segment_id", "ac_a_rw25_n", "nc_a_rw25", "td_a_rw25", "ac_a_rw25_c"))
})

test_that("GeoParquet spatial output: geometry, attributes, CRS and row groups pass through; results are sliced across row groups", {
  skip_multi_parquet()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE))
  m <- so_segments(30)
  attrs <- so_attributes(30); attrs$ac_a_rw25_n <- seq_len(30)   # a source column that a result column replaces
  src <- so_write_gpq(file.path(dir, "net.parquet"), m, attrs, chunk = 7L)
  g <- segment_graph(src)
  radius <- analysis_radius(walking = c(25, 10), angular = 180)
  norms <- c("turner", "syntax")
  frame <- rPSTool::angular_choice(g, radius, normalization = norms)
  out <- file.path(dir, "out.parquet")
  expect_error(rPSTool::angular_choice(g, radius, normalization = norms, spatial_output_file = out), "already exist in the source: ac_a_rw25_n")
  expect_false(file.exists(out))
  res <- rPSTool::angular_choice(g, radius, normalization = norms, spatial_output_file = out, overwrite = TRUE)
  expect_s3_class(res, "pst_result_file")
  expect_true(res$spatial)
  expect_identical(res$replaced, "ac_a_rw25_n")
  expect_identical(res$appended, setdiff(names(frame), c("segment_id", "ac_a_rw25_n")))
  expect_identical(so_leftovers(dir), character())
  back <- so_read(out, "geoparquet")
  source_names <- setdiff(names(rs_read_parquet(src, as_data_frame = FALSE)), "geometry")
  expect_identical(back$names, c(source_names, setdiff(names(frame), c("segment_id", "ac_a_rw25_n"))))
  for (nm in setdiff(names(frame), "segment_id")) mp_same_values(as.numeric(back$attrs[[nm]]), frame[[nm]])
  # geometry and the untouched source attributes are byte for byte the source's
  original <- as.data.frame(rs_read_parquet(src, as_data_frame = FALSE))
  expect_identical(back$wkb, unclass(original$geometry))
  for (nm in setdiff(names(so_attributes(30)), character())) expect_identical(back$attrs[[nm]], original[[nm]])
  # geo metadata, foreign metadata and row-group layout survive; rpst keys added
  src_md <- rs_read_parquet(src, as_data_frame = FALSE)$schema$metadata
  out_md <- mp_meta(out)
  expect_identical(out_md[["geo"]], src_md[["geo"]])
  expect_identical(out_md[["other_key"]], "kept")
  expect_identical(out_md[["rpst:schema"]], "2")
  expect_identical(unlist(mp_json(out_md[["rpst:normalizations"]])), norms)
  reader <- rs_pq(out)
  expect_identical(reader$num_row_groups, rs_pq(src)$num_row_groups)
  # integration, same route
  fi <- rPSTool::angular_integration(g, radius = radius, normalization = c("hillier", "turner"), weigh_by_length = TRUE)
  angular_integration(g, radius = radius, normalization = c("hillier", "turner"), weigh_by_length = TRUE,
                          spatial_output_file = file.path(dir, "int.parquet"))
  back2 <- so_read(file.path(dir, "int.parquet"), "geoparquet")
  for (nm in setdiff(names(fi), "segment_id")) mp_same_values(as.numeric(back2$attrs[[nm]]), fi[[nm]])
  expect_identical(back2$wkb, unclass(original$geometry))
})

test_that("native NaN and infinities in a multi-radius GeoParquet are stored exactly", {
  skip_multi_parquet()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE))
  ref <- dget(test_path("fixtures", "angular-multi-radius-direct-v3.3.2.R"))
  m <- matrix(unlist(ref$graphs$large_star), ncol = 4, byrow = TRUE)
  g <- segment_graph(so_write_gpq(file.path(dir, "star.parquet"), m, data.frame(id = seq_len(nrow(m)))))
  radius <- analysis_radius(walking = c(1e19, 6e18))
  frame <- rPSTool::angular_integration(g, radius = radius, weigh_by_length = TRUE, normalization = c("hillier", "syntax"))
  expect_true(any(!is.finite(frame$ai_a_rw10000000000000000000_wl_h)))
  out <- file.path(dir, "o.parquet")
  angular_integration(g, radius = radius, weigh_by_length = TRUE, normalization = c("hillier", "syntax"), spatial_output_file = out)
  back <- so_read(out, "geoparquet")
  for (nm in setdiff(names(frame), "segment_id")) mp_same_values(as.numeric(back$attrs[[nm]]), frame[[nm]])
  angular_integration(g, radius = radius, weigh_by_length = TRUE, normalization = c("hillier", "syntax"),
                          output_file = file.path(dir, "a.parquet"))
  d <- as.data.frame(rs_read_parquet(file.path(dir, "a.parquet")))
  for (nm in setdiff(names(frame), "segment_id")) mp_same_values(d[[nm]], frame[[nm]])
})

test_that("overwrite behaviour: no clobber by default, atomic replacement on request, for both Parquet routes", {
  skip_multi_parquet()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE))
  g <- segment_graph(so_write_gpq(file.path(dir, "net.parquet"), so_segments(24)))
  radius <- analysis_radius(walking = c(20, 40))
  source_md5 <- so_md5(file.path(dir, "net.parquet"))
  for (route in c("output_file", "spatial_output_file")) {
    out <- file.path(dir, paste0(route, ".parquet"))
    call <- function(...) do.call(angular_choice, c(list(g, radius, normalization = c("turner", "syntax")), setNames(list(out), route), list(...)))
    call()
    md5 <- so_md5(out)
    expect_error(call(), "already exists")
    expect_identical(so_md5(out), md5)
    expect_identical(so_leftovers(dir), character())
    expect_s3_class(call(overwrite = TRUE), "pst_result_file")   # deterministic content, replaced atomically
    expect_identical(so_leftovers(dir), character())
    expect_identical(rs_read_parquet(out, as_data_frame = FALSE)$num_rows, 24L)
  }
  expect_identical(so_md5(file.path(dir, "net.parquet")), source_md5)   # the source network is never modified
})

test_that("a failure after earlier radii completed publishes nothing and leaves an existing destination unchanged", {
  skip_multi_parquet()
  on.exit(mp_fail_after(-1), add = TRUE)
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  src <- so_write_gpq(file.path(dir, "net.parquet"), so_segments(24))
  src_md5 <- so_md5(src)
  g <- segment_graph(src)
  radius <- analysis_radius(walking = c(5, 10, 20, 40))
  for (route in c("output_file", "spatial_output_file")) {
    existing <- file.path(dir, paste0("existing-", route, ".parquet"))
    fresh <- file.path(dir, paste0("fresh-", route, ".parquet"))
    run <- function(path, ...) do.call(angular_choice, c(list(g, radius, normalization = "turner"), setNames(list(path), route), list(...)))
    run(existing)
    md5 <- so_md5(existing)
    mp_fail_after(3)                                                   # radii 1-3 complete, the 4th fails
    expect_error(run(existing, overwrite = TRUE), "injected native failure")
    mp_fail_after(2)
    expect_error(run(fresh), "injected native failure")
    mp_fail_after(-1)
    expect_identical(so_md5(existing), md5)
    expect_false(file.exists(fresh))
    expect_identical(so_leftovers(dir), character())
  }
  expect_identical(so_md5(src), src_md5)                                # the source network is never touched
  expect_identical(nrow(angular_choice(g, analysis_radius(walking = 5))), 24L)   # the graph stays usable
})

test_that("destination problems are refused before any PST run, and nothing is created", {
  skip_multi_parquet()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE))
  g <- segment_graph(so_write_gpq(file.path(dir, "net.parquet"), so_segments(24)))
  mr <- analysis_radius(walking = c(5, 10))
  mp_calls <- function() .Call(rPSTool:::C_rpst_angular_instrumentation, TRUE, NULL)[[1L]]
  mp_calls()
  expect_error(angular_choice(g, mr, output_file = file.path(dir, "no-such-dir", "x.parquet")), "directory")
  expect_error(angular_choice(g, mr, spatial_output_file = file.path(dir, "wrong-extension.fgb")), "must end in")
  expect_identical(mp_calls(), 0)   # destination problems are found before any PST run
  expect_identical(so_leftovers(dir), character())
})
