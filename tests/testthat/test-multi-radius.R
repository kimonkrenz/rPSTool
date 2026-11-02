# Multi-radius and multi-normalisation (docs/compatibility/multi-radius.md): every multi column must equal the independently executed scalar
# call, PST must run once per radius, and file and in-memory routes must agree.

mr_segments <- function() {
  set.seed(7)
  n <- 40
  x <- cumsum(runif(n, 1, 3)); y <- cumsum(rnorm(n))
  s <- cbind(x[-n], y[-n], x[-1], y[-1])
  rbind(s, cbind(s[8:22, 1], s[8:22, 2], s[8:22, 1] + 1, s[8:22, 2] + 5))
}
mr_graph <- function() segment_graph(mr_segments())
mr_counts <- function(reset = FALSE) .Call(rPSTool:::C_rpst_angular_instrumentation, reset, NULL)
mr_fail_after <- function(k) invisible(.Call(rPSTool:::C_rpst_angular_instrumentation, FALSE, as.double(k)))
mr_tag <- function(plan, i) rPSTool:::.pst_radius_tag(plan, i)

test_that("pst_radius keeps scalar behaviour and validates vectors", {
  expect_identical(analysis_radius(walking = 100), analysis_radius(walking = c(100)))
  expect_s3_class(analysis_radius(walking = c(500, 100, 1000), angular = 180), "pst_radius")
  expect_error(analysis_radius(walking = c(1, 2), steps = c(1, 2)), "At most one")
  expect_error(analysis_radius(walking = c(1, 2), straight = c(1, 2)), "Cartesian")
  expect_error(analysis_radius(walking = c(1, 1)), "duplicate")
  expect_error(analysis_radius(walking = c(0, -0)), "duplicate")
  expect_error(analysis_radius(walking = c(1, 1 + 2^-40)), "identical native floats")
  expect_error(analysis_radius(steps = c(1L, 1)), "duplicate")
  expect_error(analysis_radius(walking = c(1, NA)), "NA")
  expect_error(analysis_radius(steps = c(1L, NA)), "NA|whole number")
  expect_error(analysis_radius(walking = factor(c("1", "2"))), "numeric")
  expect_error(analysis_radius(walking = c(a = 1, b = 1)), "duplicate")   # names never make a value distinct
  expect_error(analysis_radius(walking = c(1, Inf)), "finite")
  expect_error(analysis_radius(walking = c(1, -2)), "finite non-negative")
  expect_error(analysis_radius(walking = numeric(0)), "at least one")
  expect_error(analysis_radius(walking = c(1, 1e39)), "finite non-negative")
  expect_error(analysis_radius(walking = c(1e39, 2e39)), "finite non-negative")        # range errors precede duplicate detection
  expect_error(analysis_radius(walking = c(1e-46, 2e-46)), "underflows")
  expect_error(analysis_radius(angular = c(5, 1e300)), "finite non-negative")
  expect_error(analysis_radius(steps = c(1, 2.5)), "whole number")
  expect_error(analysis_radius(straight = c(1, 1e30)), "overflows")  # squared straight radius is not a finite float
  expect_error(analysis_radius(walking = c("1", "2")), "numeric")
  expect_s3_class(analysis_radius(walking = c(0, 5)), "pst_radius")      # zero stays a valid radius
  expect_error(angular_choice(mr_graph(), analysis_radius(axmeter = 5)), "axmeter")
  expect_error(angular_choice(mr_graph(), analysis_radius(walking = 5, axmeter = c(1, 2))), "axmeter")
})

test_that("only the two angular analyses accept a multi-radius; the others refuse before any work", {
  r <- analysis_radius(walking = c(1, 2))
  axial <- axial_graph(mr_segments())
  expect_error(network_reach(axial, r), "supported only by")
  expect_error(network_betweenness(axial, r, distance = "walking"), "supported only by")
  expect_error(network_integration(axial, radius = r), "supported only by")
  expect_error(od_betweenness(axial, rbind(c(0, 0)), r), "supported only by")
  expect_error(attraction_reach(axial, rbind(c(0, 0)), r), "supported only by")
  expect_error(attraction_distance(axial, rbind(c(0, 0)), r), "supported only by")
  expect_error(segment_group_integration(segment_group_graph(mr_graph(), rep(1:2, length.out = nrow(mr_segments()))), r),
               "native float value")   # its own scalar-only radius check
  # the native boundary itself still only accepts scalar fields
  expect_error(.Call(rPSTool:::C_rpst_radius_validate, r), "native float")
})

test_that("tags are exact, ordered and collision free", {
  p <- function(...) rPSTool:::.pst_radius_plan(analysis_radius(...), TRUE)
  tags <- function(plan) vapply(seq_along(plan$configs), function(i) mr_tag(plan, i), "")
  expect_identical(tags(p(walking = c(500, 1000, 1500))), c("_w500", "_w1000", "_w1500"))
  expect_identical(tags(p(walking = c(0.5, 20, 1e-3, 0))), c("_w0p5", "_w20", "_w0p001", "_w0"))
  expect_identical(tags(p(walking = c(1e20, 3))), c("_w100000000000000000000", "_w3"))
  expect_identical(tags(p(steps = c(3L, 1, 20))), c("_n3", "_n1", "_n20"))
  expect_identical(tags(p(straight = c(2, 1), angular = 90)), c("_s2", "_s1"))
  expect_identical(tags(p(angular = c(180, 45.5))), c("_a180", "_a45p5"))
  expect_identical(tags(p(walking = c(0.1 + 0.2, 7))), c("_w0p3", "_w7"))  # native-float shortest text
  expect_identical(tags(p(walking = 500, angular = 90)), "")
  plan <- p(walking = c(500, 100), angular = 180)
  expect_identical(plan$varying, "walking"); expect_identical(plan$fixed, list(angular = 180))
  expect_identical(vapply(plan$configs, function(x) x$walking, 1), c(500, 100))
  expect_true(all(vapply(plan$configs, function(x) x$angular, 1) == 180))
})

test_that("Angular Choice: every multi column equals the scalar call", {
  g <- mr_graph()
  norms <- c("turner", "syntax", "none", "standard")
  for (weighted in c(FALSE, TRUE)) {
    for (setup in list(list(r = quote(analysis_radius(walking = c(30, 5, 12))), dim = "walking", code = "w"),
                       list(r = quote(analysis_radius(steps = c(3, 1, 2), angular = 180)), dim = "steps", code = "n"),
                       list(r = quote(analysis_radius(angular = c(135, 45), walking = 40)), dim = "angular", code = "a"),
                       list(r = quote(analysis_radius(straight = c(10, 0, 4))), dim = "straight", code = "s"))) {
      radius <- eval(setup$r)
      values <- radius[[setup$dim]]
      multi <- angular_choice(g, radius, weigh_by_length = weighted, normalization = norms,
                                  angle_threshold = 20, angle_precision = 3)
      expect_s3_class(multi, "data.frame")
      expect_identical(multi$segment_id, seq_len(nrow(mr_segments())))
      per <- 3 + weighted + 3
      expect_equal(ncol(multi), 1 + length(values) * per)
      for (i in seq_along(values)) {
        one <- radius; one[[setup$dim]] <- values[[i]]
        for (nm in c("turner", "syntax", "standard")) {
          ref <- angular_choice(g, one, weigh_by_length = weighted, normalization = nm,
                                    angle_threshold = 20, angle_precision = 3)
          expect_identical(mcol(multi, "choice", i), pick(ref, re_ac_raw))
          expect_identical(mcol(multi, "node_count", i), pick(ref, "^nc_"))
          expect_identical(mcol(multi, "total_depth", i), pick(ref, "^td_"))
          if (nm == "none") expect_false("none" %in% attr(multi, "rpst_manifest")$columns$normalization)
          else expect_identical(mcol(multi, "normalized", i, nm), pick(ref, re_ac_norm))
          if (weighted) expect_identical(mcol(multi, "total_depth_weight", i), pick(ref, "^tdw_"))
        }
      }
      # radius-major order: the requested order is the column order
      first <- names(multi)[2L]
      expect_identical(first, attr(multi, "rpst_manifest")$columns$name[[1L]])
      expect_identical(attr(multi, "rpst_manifest")$columns$radius[[1L]], 1L)
    }
  }
  m <- attr(rPSTool::angular_choice(g, analysis_radius(walking = c(5, 9)), normalization = c("syntax", "turner")), "rpst_manifest")
  expect_identical(m$columns$name[1:5], c("ac_a_rw5_n", "nc_a_rw5", "td_a_rw5", "ac_a_rw5_c", "ac_a_rw5_t"))
  expect_identical(m$columns$radius, rep(1:2, each = 5))
})

test_that("Angular Choice: scalar calls keep their schema; length-one vectors are scalar; several norms alone use the multi schema", {
  g <- mr_graph()
  scalar <- angular_choice(g, analysis_radius(walking = 12), normalization = "syntax")
  expect_identical(names(scalar), c("segment_id", "ac_a_rw12_n", "nc_a_rw12", "td_a_rw12", "ac_a_rw12_c"))
  expect_null(attr(scalar, "rpst_manifest"))
  expect_identical(angular_choice(g, analysis_radius(walking = c(12)), normalization = c("syntax")), scalar)
  expect_identical(names(angular_choice(g)), c("segment_id", "ac_a_rg_n", "nc_a_rg", "td_a_rg"))
  one_radius <- angular_choice(g, analysis_radius(walking = 12, angular = 180), normalization = c("syntax", "turner"))
  expect_identical(names(one_radius), c("segment_id", "ac_a_rw12_ra180_n", "nc_a_rw12_ra180", "td_a_rw12_ra180",
                                        "ac_a_rw12_ra180_c", "ac_a_rw12_ra180_t"))
  expect_identical(mcol(one_radius, "normalized", 1L, "syntax"),
                   pick(angular_choice(g, analysis_radius(walking = 12, angular = 180), normalization = "syntax"), re_ac_norm))
  none <- angular_choice(g, analysis_radius(walking = c(3, 4)), normalization = c("none", "none")[1])
  expect_identical(names(none), c("segment_id", "ac_a_rw3_n", "nc_a_rw3", "td_a_rw3", "ac_a_rw4_n", "nc_a_rw4", "td_a_rw4"))
  expect_error(angular_choice(g, normalization = c("syntax", "syntax")), "duplicates")
  expect_error(angular_choice(g, normalization = c("syntax", "bogus")), "one or more of")
  expect_error(angular_choice(g, normalization = character()), "normalization must be one of")
  expect_error(angular_choice(g, normalization = c("syntax", NA)), "one or more of")
  expect_error(angular_choice(g, normalization = "hillier"), "normalization must be one of")
})

test_that("Angular Integration: every multi column equals the scalar call", {
  g <- mr_graph()
  norms <- c("hillier", "turner", "syntax")
  for (weighted in c(FALSE, TRUE)) for (outputs in c(FALSE, TRUE)) {
    radius <- analysis_radius(walking = c(25, 6, 14), angular = 180)
    multi <- angular_integration(g, radius = radius, weigh_by_length = weighted, normalization = norms,
                                     angle_threshold = 15, angle_precision = 2, weight_outputs = outputs)
    has_w <- weighted || outputs
    expect_identical(ncol(multi), 1L + 3L * (3L + 2L + 2L * has_w))
    for (v in c(25, 6, 14)) {
      one <- analysis_radius(walking = v, angular = 180)
      for (nm in norms) {
        ref <- angular_integration(g, radius = one, weigh_by_length = weighted, normalization = nm,
                                       angle_threshold = 15, angle_precision = 2, weight_outputs = outputs)
        i <- match(v, c(25, 6, 14))
        expect_identical(mcol(multi, "integration", i, nm), pick(ref, "^ai_"))
        expect_identical(mcol(multi, "node_count", i), pick(ref, "^nc_"))
        expect_identical(mcol(multi, "total_depth", i), pick(ref, "^td_"))
        if (has_w) {
          expect_identical(mcol(multi, "total_weight", i), pick(ref, "^tw_"))
          expect_identical(mcol(multi, "total_depth_weight", i), pick(ref, "^tdw_"))
        }
      }
    }
    expect_identical(names(multi)[2:4], attr(multi, "rpst_manifest")$columns$name[1:3])
    expect_identical(attr(multi, "rpst_manifest")$columns$normalization[1:3], norms)
  }
  scalar <- angular_integration(g, radius = analysis_radius(walking = 6), normalization = "syntax")
  expect_identical(names(scalar), c("segment_id", "ai_a_rw6_a", "nc_a_rw6", "td_a_rw6"))
  expect_identical(angular_integration(g, radius = analysis_radius(walking = 6), normalization = c("syntax")), scalar)
  steps_multi <- angular_integration(g, radius = analysis_radius(steps = c(2, 1)), normalization = c("turner", "syntax"))
  expect_identical(mcol(steps_multi, "integration", 2L, "turner"), pick(angular_integration(g, steps = 1), "^ai_"))
  several_norms <- angular_integration(g, steps = 2, normalization = c("turner", "hillier"))
  expect_identical(names(several_norms), c("segment_id", "ai_a_rs2_t", "ai_a_rs2_h", "nc_a_rs2", "td_a_rs2"))
  expect_error(angular_integration(g, steps = 2, radius = analysis_radius(walking = c(1, 2))), "not both")
  expect_error(angular_integration(g, normalization = c("turner", "turner")), "duplicates")
  expect_error(angular_integration(g, normalization = c("none", "turner")), "one or more of")
})

test_that("Zero radii, vector-of-length-one and requested order behave like the scalar calls", {
  g <- mr_graph()
  m <- angular_choice(g, analysis_radius(walking = c(0, 8, 3)), normalization = c("turner", "standard"))
  for (i in seq_along(c(0, 8, 3))) {
    ref <- angular_choice(g, analysis_radius(walking = c(0, 8, 3)[[i]]), normalization = "turner")
    expect_identical(mcol(m, "normalized", i, "turner"), pick(ref, re_ac_norm))
  }
  rev_m <- angular_choice(g, analysis_radius(walking = c(3, 8, 0)), normalization = c("standard", "turner"))
  expect_identical(rev_m$ac_a_rw8_n, m$ac_a_rw8_n)
  expect_identical(names(rev_m)[2], "ac_a_rw3_n")
})

test_that("PST runs once per radius, never once per normalisation; normalisers are the exported ones", {
  g <- mr_graph()
  mr_counts(TRUE)
  invisible(angular_choice(g, analysis_radius(walking = c(4, 8, 12, 16)), normalization = c("none", "standard", "turner", "syntax")))
  expect_identical(mr_counts(TRUE), c(4, 12, 0, 0))
  invisible(angular_integration(g, radius = analysis_radius(walking = c(4, 8, 12)), normalization = c("turner", "syntax", "hillier")))
  expect_identical(mr_counts(TRUE), c(0, 0, 3, 9))
  invisible(angular_choice(g, analysis_radius(walking = 9), normalization = "syntax"))   # scalar: one run, one normaliser
  expect_identical(mr_counts(TRUE), c(1, 1, 0, 0))
  invisible(angular_choice(g, analysis_radius(walking = 9), normalization = c("turner", "syntax", "standard")))
  expect_identical(mr_counts(TRUE), c(1, 3, 0, 0))
})

test_that("the test-only instrumentation validates its arguments and never changes state on a bad call", {
  on.exit(mr_fail_after(-1), add = TRUE)
  call <- function(reset, after) .Call(rPSTool:::C_rpst_angular_instrumentation, reset, after)
  mr_counts(TRUE)
  g <- mr_graph()
  invisible(angular_choice(g, analysis_radius(walking = 9)))
  before <- mr_counts()
  for (bad in list(NA_real_, NaN, Inf, -Inf, -2, 2147483648, 1.5, 1e300, "1", c(1, 2), TRUE, 1L))
    expect_error(call(FALSE, bad), "fail_after")
  for (bad in list(NA, NULL, "TRUE", c(TRUE, FALSE), 1))
    expect_error(call(bad, NULL), "reset")
  expect_identical(mr_counts(), before)                                    # a rejected call changed nothing
  invisible(angular_choice(g, analysis_radius(walking = 9)))                 # and no fault was armed by the bad calls
  expect_identical(call(FALSE, 0)[[1L]], before[[1L]] + 1)                   # valid: arms "fail the next run"
  expect_error(angular_choice(g, analysis_radius(walking = 9)), "injected native failure")
  invisible(angular_choice(g, analysis_radius(walking = 9)))                 # one-shot: disarmed itself
  expect_identical(call(FALSE, 2147483647)[[1L]] >= 0, TRUE)
  expect_identical(call(FALSE, -1)[[1L]] >= 0, TRUE)
  invisible(angular_choice(g, analysis_radius(walking = 9)))
})

test_that("a failure in the middle of the sequence aborts the whole request and leaves the graph usable", {
  on.exit(mr_fail_after(-1), add = TRUE)   # never leak an armed fault into another test
  g <- mr_graph()
  before <- angular_choice(g, analysis_radius(walking = 7), normalization = "syntax")
  mr_fail_after(3)
  expect_error(angular_choice(g, analysis_radius(walking = c(4, 8, 12, 16)), normalization = c("turner", "syntax")),
               "injected native failure")
  mr_fail_after(1)
  expect_error(angular_integration(g, radius = analysis_radius(walking = c(4, 8, 12)), normalization = c("turner", "syntax")),
               "injected native failure")
  mr_fail_after(-1)
  expect_identical(angular_choice(g, analysis_radius(walking = 7), normalization = "syntax"), before)
  gc()
})

test_that("results do not depend on the graph object after the call", {
  g <- mr_graph()
  m <- angular_choice(g, analysis_radius(walking = c(4, 8)), normalization = c("turner", "syntax"))
  rm(g); gc()
  expect_identical(ncol(m), 11L)
})

# ---- file output (FlatGeobuf needs no arrow; the Parquet routes are exercised when arrow is available) ----------------------
skip_multi_fgb <- function() { skip_if_not_installed("sf"); skip_if_not_installed("jsonlite") }
mr_fgb_meta <- function(path) {
  raw <- .Call(rPSTool:::C_rpst_fgb_columns, enc2native(path))$metadata
  jsonlite::fromJSON(rawToChar(raw), simplifyVector = FALSE)
}

test_that("FlatGeobuf spatial output holds one combined table equal to the in-memory result", {
  skip_multi_fgb()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE))
  m <- so_segments(30)
  src <- so_write_fgb(file.path(dir, "net.fgb"), m)
  g <- segment_graph(src)
  radius <- analysis_radius(walking = c(25, 10, 60), angular = 180)
  norms <- c("turner", "syntax")
  frame <- rPSTool::angular_choice(g, radius, normalization = norms)
  out <- file.path(dir, "out.fgb")
  res <- angular_choice(g, radius, normalization = norms, spatial_output_file = out)
  expect_s3_class(res, "pst_result_file")
  expect_identical(res$appended, setdiff(names(frame), "segment_id"))
  expect_identical(so_leftovers(dir), character())
  back <- so_read(out, "flatgeobuf")
  expect_identical(back$names, c(names(so_attributes(30)), setdiff(names(frame), "segment_id")))
  for (nm in setdiff(names(frame), "segment_id")) expect_equal(as.numeric(back$attrs[[nm]]), as.numeric(frame[[nm]]), tolerance = 0)
  expect_identical(back$wkb, so_wkb_of(src))
  expect_equal(back$attrs[names(so_attributes(30))], so_attributes(30), ignore_attr = TRUE)
  meta <- mr_fgb_meta(out)
  expect_identical(meta[["rpst:schema"]], "2")
  expect_identical(meta[["rpst:function"]], "angular_choice")
  expect_identical(meta[["rpst:radius_varying"]], "walking")
  expect_identical(jsonlite::fromJSON(meta[["rpst:radius_fixed"]], simplifyVector = FALSE), list(angular = 180L))
  configs <- jsonlite::fromJSON(meta[["rpst:radius_configurations"]], simplifyVector = FALSE)
  expect_identical(vapply(configs, function(x) x$walking, 1), c(25, 10, 60))
  expect_true(all(vapply(configs, function(x) is.null(x$straight) && x$angular == 180, NA)))
  expect_identical(unlist(jsonlite::fromJSON(meta[["rpst:normalizations"]], simplifyVector = FALSE)), norms)
  cols <- jsonlite::fromJSON(meta[["rpst:columns"]], simplifyVector = FALSE)
  expect_identical(vapply(cols, function(x) x$name, ""), setdiff(names(frame), "segment_id"))
  expect_equal(vapply(cols, function(x) x$radius, 1), rep(1:3, each = 5))
  expect_identical(meta[["rpst:pst_commit"]], unname(rPSTool:::.pst_engine_pin()[["pst_commit"]]))
  params <- jsonlite::fromJSON(meta[["rpst:parameters"]], simplifyVector = FALSE)
  expect_equal(unlist(params$radius$walking), c(25, 10, 60)); expect_identical(unlist(params$normalization), norms)
  # integration, same route
  fi <- rPSTool::angular_integration(g, radius = radius, normalization = c("hillier", "turner"), weigh_by_length = TRUE)
  out2 <- file.path(dir, "int.fgb")
  angular_integration(g, radius = radius, normalization = c("hillier", "turner"), weigh_by_length = TRUE, spatial_output_file = out2)
  back2 <- so_read(out2, "flatgeobuf")
  for (nm in setdiff(names(fi), "segment_id")) expect_equal(as.numeric(back2$attrs[[nm]]), as.numeric(fi[[nm]]), tolerance = 0)
  expect_identical(mr_fgb_meta(out2)[["rpst:function"]], "angular_integration")
  # the scalar file schema is untouched
  out3 <- file.path(dir, "scalar.fgb")
  angular_choice(g, analysis_radius(walking = 25), normalization = "syntax", spatial_output_file = out3)
  expect_identical(mr_fgb_meta(out3)[["rpst:schema"]], "1")
  expect_identical(vapply(jsonlite::fromJSON(mr_fgb_meta(out3)[["rpst:columns"]], simplifyVector = FALSE), function(x) x$name, ""),
                   c("ac_a_rw25_n", "nc_a_rw25", "td_a_rw25", "ac_a_rw25_c"))
})

test_that("a source column with a result's name needs overwrite = TRUE; earlier columns are kept as ordinary attributes", {
  skip_multi_fgb()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE))
  m <- so_segments(20)
  attrs <- so_attributes(20); attrs$ac_a_rw25_n <- 1:20; attrs$nc_a_rw10 <- 1:20
  src <- so_write_fgb(file.path(dir, "net.fgb"), m, attrs)
  before <- so_md5(src)
  g <- segment_graph(src)
  expect_error(rPSTool::angular_choice(g, analysis_radius(walking = c(25, 10)), spatial_output_file = file.path(dir, "o.fgb")),
               "already exist in the source: ac_a_rw25_n, nc_a_rw10")
  expect_false(file.exists(file.path(dir, "o.fgb")))
  res <- rPSTool::angular_choice(g, analysis_radius(walking = c(25, 10)), spatial_output_file = file.path(dir, "o.fgb"), overwrite = TRUE)
  expect_setequal(res$replaced, c("ac_a_rw25_n", "nc_a_rw10"))
  expect_identical(so_md5(src), before)
  back <- so_read(file.path(dir, "o.fgb"), "flatgeobuf")
  expect_identical(sum(back$names == "ac_a_rw25_n"), 1L)
  expect_equal(as.numeric(back$attrs$ac_a_rw25_n), pick(angular_choice(g, analysis_radius(walking = 25)), re_ac_raw), tolerance = 0)
  # chain: a second run with different radii keeps the first run's columns as ordinary attributes
  res2 <- rPSTool::angular_choice(segment_graph(file.path(dir, "o.fgb")), analysis_radius(walking = c(25, 99)),
                             spatial_output_file = file.path(dir, "o2.fgb"), overwrite = TRUE)
  expect_true(all(c("ac_a_rw10_n", "ac_a_rw25_n", "ac_a_rw99_n") %in% so_read(file.path(dir, "o2.fgb"), "flatgeobuf")$names))
  expect_false("ac_a_rw10_n" %in% res2$columns[res2$columns %in% c("ac_a_rw99_n")])
})

test_that("a mid-sequence failure publishes nothing and leaves an existing destination untouched", {
  on.exit(mr_fail_after(-1), add = TRUE)
  skip_multi_fgb()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  src <- so_write_fgb(file.path(dir, "net.fgb"), so_segments(24))
  g <- segment_graph(src)
  out <- file.path(dir, "out.fgb")
  expect_s3_class(angular_choice(g, analysis_radius(walking = c(5, 10, 20, 40)), normalization = "turner",
                                     spatial_output_file = out), "pst_result_file")
  md5 <- so_md5(out)
  mr_fail_after(3)
  expect_error(angular_choice(g, analysis_radius(walking = c(6, 11, 21, 41)), normalization = "turner",
                                  spatial_output_file = out, overwrite = TRUE), "injected native failure")
  mr_fail_after(2)
  fresh <- file.path(dir, "fresh.fgb")
  expect_error(angular_integration(g, radius = analysis_radius(walking = c(6, 11, 21)), normalization = "turner",
                                       spatial_output_file = fresh), "injected native failure")
  mr_fail_after(-1)
  expect_identical(so_md5(out), md5)
  expect_false(file.exists(fresh))
  expect_identical(so_leftovers(dir), character())
  expect_error(angular_choice(g, analysis_radius(walking = c(5, 10)), spatial_output_file = out), "already exists")
  expect_identical(so_md5(out), md5)
  expect_s3_class(angular_choice(g, analysis_radius(walking = c(5, 10)), spatial_output_file = out, overwrite = TRUE), "pst_result_file")
  expect_false(identical(so_md5(out), md5))
  expect_identical(nrow(angular_choice(g, analysis_radius(walking = 5))), 24L)  # graph still usable
})

test_that("invalid requests are rejected before any calculation or file", {
  skip_multi_fgb()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE))
  g <- segment_graph(so_write_fgb(file.path(dir, "net.fgb"), so_segments(12)))
  mr_counts(TRUE)
  out <- file.path(dir, "o.fgb")
  expect_error(angular_choice(g, analysis_radius(walking = c(5, 6)), normalization = c("turner", "bogus"), spatial_output_file = out), "one or more of")
  expect_error(angular_choice(g, analysis_radius(walking = c(5, 6)), spatial_output_file = file.path(dir, "o.parquet")), "must end in")
  expect_error(angular_choice(g, analysis_radius(walking = c(5, 6)), output_file = out, spatial_output_file = out), "mutually exclusive")
  expect_identical(mr_counts(TRUE), c(0, 0, 0, 0))
  expect_identical(list.files(dir), "net.fgb")
})

test_that("file-backed multi-radius calls record fixed straight / steps restrictions and the angle controls", {
  skip_multi_fgb()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE))
  g <- segment_graph(so_write_fgb(file.path(dir, "net.fgb"), so_segments(30)))
  cases <- list(
    list(radius = analysis_radius(walking = c(40, 15), straight = 25), fixed = list(straight = 25), vary = "walking"),
    list(radius = analysis_radius(angular = c(120, 60), steps = 4), fixed = list(steps = 4L), vary = "angular"),
    list(radius = analysis_radius(steps = c(2, 5), straight = 30, angular = 150), fixed = list(straight = 30, angular = 150), vary = "steps"))
  for (k in seq_along(cases)) {
    case <- cases[[k]]
    for (analysis in c("choice", "integration")) {
      args <- list(g, radius = case$radius, angle_threshold = 25, angle_precision = 4)
      if (analysis == "choice") { call <- rPSTool::angular_choice; args$normalization <- c("turner", "syntax"); args <- c(list(g, case$radius), args[-(1:2)]) }
      else { call <- rPSTool::angular_integration; args$normalization <- c("turner", "hillier"); args$weigh_by_length <- TRUE }
      frame <- do.call(call, args)
      out <- file.path(dir, sprintf("%s-%d.fgb", analysis, k))
      do.call(call, c(args, list(spatial_output_file = out)))
      back <- sf::st_drop_geometry(sf::st_read(out, quiet = TRUE))
      for (nm in setdiff(names(frame), "segment_id")) expect_equal(as.numeric(back[[nm]]), as.numeric(frame[[nm]]), tolerance = 0)
      meta <- mr_fgb_meta(out)
      expect_identical(meta[["rpst:radius_varying"]], case$vary)
      fixed <- jsonlite::fromJSON(meta[["rpst:radius_fixed"]], simplifyVector = FALSE)
      expect_identical(names(fixed), names(case$fixed))
      expect_equal(unlist(fixed), unlist(case$fixed))
      configs <- jsonlite::fromJSON(meta[["rpst:radius_configurations"]], simplifyVector = FALSE)
      expect_length(configs, 2L)
      for (f in names(case$fixed)) expect_true(all(vapply(configs, function(x) isTRUE(all.equal(x[[f]], case$fixed[[f]])), NA)))
      expect_equal(vapply(configs, function(x) x[[case$vary]], 1), as.numeric(case$radius[[case$vary]]))
      params <- jsonlite::fromJSON(meta[["rpst:parameters"]], simplifyVector = FALSE)
      expect_equal(params$angle_threshold, 25); expect_equal(params$angle_precision, 4)
      # the fixed restriction really applied: each column equals the scalar call with the same restriction
      first <- case$radius; first[[case$vary]] <- case$radius[[case$vary]][[1L]]
      sargs <- list(g, radius = first, angle_threshold = 25, angle_precision = 4)
      scalar <- if (analysis == "choice") angular_choice(g, first, normalization = "turner", angle_threshold = 25, angle_precision = 4)
                else angular_integration(g, radius = first, weigh_by_length = TRUE, normalization = "turner", angle_threshold = 25, angle_precision = 4)
      first_name <- paste0(if (analysis == "choice") "ac_a_" else "ai_a_", rPSTool:::.pst_nm_radius(first),
                           if (analysis == "choice") "_t_at25_ap4" else "_wl_t_at25_ap4")
      expect_identical(frame[[first_name]], if (analysis == "choice") pick(scalar, re_ac_norm) else pick(scalar, "^ai_"))
    }
  }
  # the angle controls matter: different controls give different columns (the call is not ignoring them)
  h <- mr_graph()
  a <- rPSTool::angular_choice(h, analysis_radius(walking = c(40, 15)), normalization = c("turner", "syntax"))
  b <- rPSTool::angular_choice(h, analysis_radius(walking = c(40, 15)), normalization = c("turner", "syntax"), angle_threshold = 60, angle_precision = 9)
  expect_false(identical(a$td_a_rw40, b$td_a_rw40_at60_ap9))
})

test_that("file output of the multi-result route is available on every platform", {
  expect_true(isTRUE(.Call(rPSTool:::C_rpst_output_supported)))
})

test_that("JSON arrays are valid and the metadata stays compact for many radii", {
  skip_if_not_installed("jsonlite")
  expect_identical(rPSTool:::.pst_json(rPSTool:::.pst_json_array(list(1, "a", NULL, TRUE))), "[1,\"a\",null,true]")
  expect_identical(rPSTool:::.pst_json(rPSTool:::.pst_json_array(list())), "[]")
  expect_identical(rPSTool:::.pst_json(rPSTool:::.pst_json_array(list(list(a = 1)))), "[{\"a\":1}]")
  plan <- rPSTool:::.pst_radius_plan(analysis_radius(walking = seq(50, 1000, by = 50)), TRUE)
  spec <- rPSTool:::.pst_multi_spec("choice", plan, c("turner", "syntax", "standard", "none"), TRUE)
  expect_identical(nrow(spec), 20L * 7L)
  graph <- structure(list(), class = "x")
  md <- rPSTool:::.pst_multi_metadata("angular_choice", list(radius = NULL, normalization = NULL), plan,
                                   c("turner", "syntax", "standard", "none"), spec, 10, graph)
  expect_lt(nchar(md[["rpst:columns"]]), 20000)
  expect_length(jsonlite::fromJSON(md[["rpst:columns"]], simplifyVector = FALSE), 140L)
  expect_identical(anyDuplicated(spec$name), 0L)
})
