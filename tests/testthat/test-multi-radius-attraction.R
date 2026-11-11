# Multi-radius Attraction Reach, Attraction Distance and OD Betweenness (docs/compatibility/multi-radius.md). Every multi column must equal the
# independently executed scalar call with that radius; PST runs once per radius; all radii are validated (including the function-specific
# distance rules) before the first PST run; the file routes hold the same table as the in-memory result. Parquet checks need the optional arrow
# package and are skipped (not weakened) where it is missing; FlatGeobuf checks need sf and jsonlite.

na_segments <- function() {
  set.seed(11)
  n <- 40
  x <- cumsum(runif(n, 1, 3)); y <- cumsum(rnorm(n))
  s <- cbind(x[-n], y[-n], x[-1], y[-1])
  unname(rbind(s, cbind(s[8:22, 1], s[8:22, 2], s[8:22, 1] + 1, s[8:22, 2] + 5)))
}
# retained points (origin = "points") and two triangular point groups (origin = "point_groups")
na_retained <- function() rbind(c(2, 1), c(6, 2), c(10, 8), c(14, 10), c(5, 9), c(8, 12), c(11, 11), c(7, 4))
na_graph <- function() axial_graph(na_segments(), points = na_retained(), points_per_polygon = c(3, 5), polygon_point_interval = 1)
na_attractions <- function() rbind(c(3, 1), c(9, 5), c(20, 12), c(16, 9))
na_polygons <- function() rbind(c(3, 1), c(5, 1), c(4, 3), c(12, 6), c(14, 6), c(14, 8), c(12, 8))
na_polygon_sizes <- c(3, 4)
na_counts <- function(reset = FALSE) .Call(rPSTool:::C_rpst_axial_instrumentation, reset, NULL)[5:7]   # attraction reach, attraction distance, OD
na_fail_after <- function(k) invisible(.Call(rPSTool:::C_rpst_axial_instrumentation, FALSE, as.double(k)))
na_skip_fgb <- function() { skip_if_not_installed("sf"); skip_if_not_installed("jsonlite") }
na_meta <- function(path) {
  raw <- .Call(rPSTool:::C_rpst_fgb_columns, enc2native(path))$metadata
  jsonlite::fromJSON(rawToChar(raw), simplifyVector = FALSE)
}

# Comparison of a multi-radius column with the scalar column. Equality is EXACT (values and types) unless a tolerance is given. The only
# measured run-to-run variability of any analysed score is Attraction Reach with attraction values or a non-constant decay on SEVERAL
# workers: workers add their partial scores in a nondeterministic order, which moves the last float bits (25 repeats of each case gave
# at most 3.5e-7 relative deviation, about three float epsilons; with RPST_NUM_THREADS=1 every case, including that one, is bit for bit
# reproducible). Those comparisons therefore run exactly on one worker and with tolerance `na_tol` (1e-6, a factor of three above the
# measured maximum) on several. Types, missing and non-finite patterns, and integer columns are always compared exactly.
na_tol <- 1e-6
na_same <- function(actual, expected, info = NULL, tolerance = 0) {
  expect_identical(typeof(actual), typeof(expected), info = info)
  expect_identical(is.na(actual), is.na(expected), info = info)
  expect_identical(is.nan(actual), is.nan(expected), info = info)
  finite <- is.finite(expected)
  expect_identical(actual[!finite], expected[!finite], info = info)
  if (is.integer(expected) || tolerance == 0) expect_identical(actual, expected, info = info)
  else expect_equal(actual[finite], expected[finite], tolerance = tolerance, info = info)
}
# Run `code` with the worker cap `workers` (NULL = the machine default); the analyses read RPST_NUM_THREADS at every call.
na_with_workers <- function(workers, code) {
  old <- Sys.getenv("RPST_NUM_THREADS", unset = NA)
  on.exit(if (is.na(old)) Sys.unsetenv("RPST_NUM_THREADS") else Sys.setenv(RPST_NUM_THREADS = old), add = TRUE)
  if (is.null(workers)) Sys.unsetenv("RPST_NUM_THREADS") else Sys.setenv(RPST_NUM_THREADS = workers)
  force(code)
}

na_expect_columns_match_scalar <- function(multi, radius, scalar_fn, id = c("origin_id", "line_id"), tolerance = 0) {
  plan <- rPSTool:::.pst_radius_plan(radius, FALSE)
  manifest <- attr(multi, "rpst_manifest")$columns
  seen <- character()
  for (i in seq_along(plan$configs)) {
    scalar <- scalar_fn(plan$configs[[i]])
    expect_null(attr(scalar, "rpst_manifest"))                        # a scalar call keeps the single-result schema
    for (nm in setdiff(names(scalar), id)) {
      expect_true(nm %in% names(multi), info = nm)
      na_same(multi[[nm]], scalar[[nm]], info = nm, tolerance = tolerance)
      expect_identical(manifest$radius[match(nm, manifest$name)], i)
      seen <- c(seen, nm)
    }
  }
  expect_identical(setdiff(names(multi), id), seen)
  expect_false(anyDuplicated(names(multi)) > 0)
}

# Custom weights are named after the R object they were passed as; the wrappers make that object `values`, `costs`, `origin_w`, `dest_w`.
na_reach <- function(g, a, radius, ..., attraction_values = NULL) attraction_reach(g, a, radius, ..., attraction_values = attraction_values)
na_dist <- function(g, a, radius, ..., line_weights = NULL) attraction_distance(g, a, radius, ..., line_weights = line_weights)
na_od <- function(g, o, radius, ..., origin_weights = NULL, destination_weights = NULL)
  od_betweenness(g, o, radius, ..., origin_weights = origin_weights, destination_weights = destination_weights)

na_radii <- function() list(analysis_radius(walking = c(8, 3, 20)), analysis_radius(steps = c(2, 1, 4), straight = 15),
                            analysis_radius(straight = c(5, 12)), analysis_radius(angular = c(90, 45), walking = 30),
                            analysis_radius(axmeter = c(10, 40)))

test_that("Attraction Reach: every radius column equals the scalar call, for every radius field, origin and distance", {
  g <- na_graph(); a <- na_attractions()
  info <- .Call(rPSTool:::C_rpst_graph_info, g$ptr)   # lines, junctions, points (retained and polygon samples), point groups
  for (r in na_radii()) for (origin in c("lines", "junctions", "points", "point_groups")) {
    d <- if (!is.null(r$walking) && is.null(r$steps)) "walking" else if (!is.null(r$straight) && is.null(r$steps)) "straight" else
         if (!is.null(r$angular)) "angular" else if (!is.null(r$axmeter)) "axmeter" else "steps"
    multi <- attraction_reach(g, a, r, origin, d)
    expect_identical(names(multi)[[1L]], "origin_id")
    expect_identical(multi$origin_id, seq_len(nrow(multi)))
    expect_identical(nrow(multi), info[[c(lines = 1L, junctions = 2L, points = 3L, point_groups = 4L)[[origin]]]])
    na_expect_columns_match_scalar(multi, r, function(cfg) attraction_reach(g, a, cfg, origin, d))
  }
  # radius-major, in the supplied order, with the scalar names
  m <- attraction_reach(g, a, analysis_radius(walking = c(8, 3, 20)), distance = "walking")
  expect_identical(names(m), c("origin_id", "ar_w_rw8", "ar_w_rw3", "ar_w_rw20"))
  expect_identical(vapply(m, typeof, ""), c(origin_id = "integer", ar_w_rw8 = "double", ar_w_rw3 = "double", ar_w_rw20 = "double"))
})

test_that("Attraction Reach keeps every option under several radii: values, decay, polygons, distribution, collection", {
  g <- na_graph(); a <- na_attractions()
  values <- c(2, 0, 3.5, 1)
  r <- analysis_radius(walking = c(30, 6, 12))
  # exact on one worker, within the measured float-summation tolerance on several (see na_tol)
  for (setting in list(list(workers = "1", tol = 0), list(workers = NULL, tol = na_tol))) na_with_workers(setting$workers, {
    for (decay in c("constant", "power", "curve", "divide")) {
      multi <- na_reach(g, a, r, distance = "walking", attraction_values = values, decay = decay, decay_constant = 2)
      expect_true(all(grepl("_wattraction_values", names(multi)[-1L])))
      na_expect_columns_match_scalar(multi, r, function(cfg)
        na_reach(g, a, cfg, distance = "walking", attraction_values = values, decay = decay, decay_constant = 2), tolerance = setting$tol)
    }
    default_decay <- attraction_reach(g, a, r, distance = "walking", decay = "power")      # NULL decay_constant -> 1, as a scalar call
    na_expect_columns_match_scalar(default_decay, r, function(cfg) attraction_reach(g, a, cfg, distance = "walking", decay = "power"),
                                   tolerance = setting$tol)
    pvalues <- c(4, 1)
    for (dist in c("copy", "divide")) for (coll in c("mean", "sum", "min", "max")) for (origin in c("lines", "point_groups")) {
      multi <- na_reach(g, na_polygons(), r, origin, "walking", points_per_polygon = na_polygon_sizes, polygon_point_interval = 0.5,
                        attraction_values = pvalues, distribution = dist, collection = coll)
      na_expect_columns_match_scalar(multi, r, function(cfg)
        na_reach(g, na_polygons(), cfg, origin, "walking", points_per_polygon = na_polygon_sizes, polygon_point_interval = 0.5,
                 attraction_values = pvalues, distribution = dist, collection = coll), tolerance = setting$tol)
    }
  })
  # distance "none" and empty attractions
  na_expect_columns_match_scalar(attraction_reach(g, a, analysis_radius(steps = c(1, 3)), distance = "none"), analysis_radius(steps = c(1, 3)),
                                 function(cfg) attraction_reach(g, a, cfg, distance = "none"))
  empty <- matrix(numeric(), 0, 2)
  na_expect_columns_match_scalar(attraction_reach(g, empty, r, distance = "walking"), r,
                                 function(cfg) attraction_reach(g, empty, cfg, distance = "walking"))
})

test_that("Attraction Distance: every radius column equals the scalar call, with and without destination indices", {
  g <- na_graph(); a <- na_attractions()
  wts <- seq(0.5, by = 0.25, length.out = 54)
  radii <- c(na_radii()[c(1, 2, 4)], list(analysis_radius(steps = c(1, 2)), analysis_radius(walking = c(0, 15))))
  for (r in radii) for (origin in c("lines", "junctions", "points", "point_groups")) for (di in c(TRUE, FALSE)) for (d in c("walking", "steps", "angular", "weights")) {
    multi <- na_dist(g, a, r, origin, d, destination_indices = di, line_weights = if (d == "weights") wts)
    expect_identical(ncol(multi), 1L + length(rPSTool:::.pst_radius_plan(r, FALSE)$configs) * (1L + di))
    na_expect_columns_match_scalar(multi, r, function(cfg)
      na_dist(g, a, cfg, origin, d, destination_indices = di, line_weights = if (d == "weights") wts))
  }
  m <- attraction_distance(g, a, analysis_radius(walking = c(8, 3)), distance = "walking")
  expect_identical(names(m), c("origin_id", "ad_w_rw8", "di_w_rw8", "ad_w_rw3", "di_w_rw3"))
  expect_identical(vapply(m, typeof, ""), c(origin_id = "integer", ad_w_rw8 = "double", di_w_rw8 = "integer", ad_w_rw3 = "double", di_w_rw3 = "integer"))
  expect_true(any(m$di_w_rw3 == -1L) || any(m$ad_w_rw3 == -1))   # unreachable origins keep PST's -1, unchanged
  # polygons, point edge cost, and straight distance with a straight vector
  polys <- na_distance_polygons <- na_polygons()
  for (origin in c("lines", "points", "point_groups")) {
    r <- analysis_radius(walking = c(30, 6))
    na_expect_columns_match_scalar(attraction_distance(g, polys, r, origin, "walking", na_polygon_sizes, 0.5, point_edge_weight = 0.25), r,
      function(cfg) attraction_distance(g, polys, cfg, origin, "walking", na_polygon_sizes, 0.5, point_edge_weight = 0.25))
  }
  r <- analysis_radius(straight = c(4, 9, 25))
  for (origin in c("lines", "junctions", "points")) for (di in c(TRUE, FALSE)) {
    na_expect_columns_match_scalar(attraction_distance(g, a, r, origin, "straight", destination_indices = di), r,
      function(cfg) attraction_distance(g, a, cfg, origin, "straight", destination_indices = di))
  }
  # a straight vector without any other limit is also fine for a network distance (a straight radius is ignored there)
  na_expect_columns_match_scalar(attraction_distance(g, a, r, distance = "walking"), r,
                                 function(cfg) attraction_distance(g, a, cfg, distance = "walking"))
})

test_that("OD Betweenness: every radius column equals the scalar call for each distance, mode and weighting", {
  g <- na_graph()
  origins <- rbind(c(1, 1), c(5, 2), c(12, 8), c(9, 4))
  set.seed(3)
  ow <- c(1, 2.5, 0, 4); dw <- rep(c(1, 0, 2, 3, 1, 5, 2, 1), length.out = .Call(rPSTool:::C_rpst_graph_info, g$ptr)[[3L]])
  radii <- c(na_radii()[1:4], list(analysis_radius(walking = c(0, 10))))
  for (r in radii) for (distance in c("walking", "angular")) for (mode in c("all", "closest")) for (w in 1:3) {
    ow_arg <- if (w >= 2) ow; dw_arg <- if (w == 3) dw
    multi <- na_od(g, origins, r, distance = distance, destination_mode = mode, origin_weights = ow_arg, destination_weights = dw_arg)
    expect_identical(names(multi)[[1L]], "line_id")
    expect_identical(nrow(multi), 54L)
    na_expect_columns_match_scalar(multi, r, function(cfg)
      na_od(g, origins, cfg, distance = distance, destination_mode = mode, origin_weights = ow_arg, destination_weights = dw_arg), "line_id")
  }
  m <- od_betweenness(g, origins, analysis_radius(walking = c(8, 3)))
  expect_identical(names(m), c("line_id", "od_w_rw8", "od_w_rw3"))
  # no origins, and a graph without destinations, give PST's written scores for each radius
  r <- analysis_radius(steps = c(1, 2))
  empty <- matrix(numeric(), 0, 2)
  na_expect_columns_match_scalar(od_betweenness(g, empty, r), r, function(cfg) od_betweenness(g, empty, cfg), "line_id")
  bare <- axial_graph(na_segments())
  na_expect_columns_match_scalar(od_betweenness(bare, origins, r), r, function(cfg) od_betweenness(bare, origins, cfg), "line_id")
})

test_that("one radius keeps the scalar schema and shape for all three analyses", {
  g <- na_graph(); a <- na_attractions(); o <- rbind(c(1, 1), c(5, 2))
  for (res in list(attraction_reach(g, a, analysis_radius(walking = 8), distance = "walking"),
                   attraction_reach(g, a, analysis_radius(walking = c(8)), distance = "walking"),
                   attraction_distance(g, a, analysis_radius(walking = 8), distance = "walking"),
                   od_betweenness(g, o, analysis_radius(walking = 8))))
    expect_null(attr(res, "rpst_manifest"))
  expect_identical(names(attraction_distance(g, a, analysis_radius(walking = 8), distance = "walking")),
                   c("origin_id", "ad_w_rw8", "di_w_rw8"))
  expect_identical(attraction_reach(g, a, analysis_radius(walking = c(8)), distance = "walking"),
                   attraction_reach(g, a, analysis_radius(walking = 8), distance = "walking"))
})

test_that("the multi-result manifest describes every column, including the weight names", {
  g <- na_graph(); a <- na_attractions(); o <- rbind(c(1, 1), c(5, 2))
  values <- c(2, 0, 3.5, 1); wts <- seq(0.5, by = 0.25, length.out = 54); ow <- c(1, 2); dw <- rep(1, .Call(rPSTool:::C_rpst_graph_info, g$ptr)[[3L]])
  r <- analysis_radius(steps = c(1, 2), walking = 20)
  ar <- na_reach(g, a, r, "points", "walking", attraction_values = values, decay = "power", decay_constant = 2)
  man <- attr(ar, "rpst_manifest")
  expect_identical(man$columns$role, rep("attraction_reach", 2L))
  expect_identical(man$columns$radius, 1:2)
  expect_length(man$radii, 2L)
  cols <- attr(man$columns, "cols")
  expect_identical(vapply(cols, function(x) x$weight_name, ""), rep("attraction_values", 2L))
  expect_identical(vapply(cols, function(x) x$distance, ""), rep("w", 2L))
  expect_identical(vapply(cols, function(x) x$radius, ""), c("rw20_rs1", "rw20_rs2"))
  ad <- na_dist(g, a, r, distance = "weights", line_weights = wts)
  expect_identical(attr(attr(ad, "rpst_manifest")$columns, "cols")[[1L]]$weight_name, "line_weights")
  expect_identical(attr(ad, "rpst_manifest")$columns$role, rep(c("attraction_distance", "destination_index"), 2L))
  od <- na_od(g, o, r, origin_weights = ow, destination_weights = dw)
  expect_identical(attr(attr(od, "rpst_manifest")$columns, "cols")[[1L]]$weight_name, "origin: origin_weights; destination: destination_weights")
  expect_identical(vapply(attr(attr(od, "rpst_manifest")$columns, "cols"), function(x) x$weight, ""),
                   rep("woorigin_weights_wddestination_weights", 2L))
})

# ---- validation: every radius is checked before the first PST run ----------------------------------------------------------------

test_that("invalid radius sets are rejected before any native work", {
  g <- na_graph(); a <- na_attractions(); o <- rbind(c(1, 1), c(5, 2))
  na_counts(TRUE)
  # two varying fields, duplicates (also after float narrowing), invalid values at any position, empty vectors
  bad <- list(quote(analysis_radius(walking = c(5, 10), steps = c(1, 2))), quote(analysis_radius(walking = c(5, 5))),
              quote(analysis_radius(walking = c(5, 5 + 1e-9))), quote(analysis_radius(steps = c(1, 1.5))),
              quote(analysis_radius(walking = c(5, -1))), quote(analysis_radius(walking = c(5, NA))),
              quote(analysis_radius(walking = c(5, Inf))), quote(analysis_radius(steps = c(1, 2^31))),
              quote(analysis_radius(walking = numeric())))
  for (expr in bad) {
    expect_error(attraction_reach(g, a, eval(expr), distance = "walking"), info = deparse(expr))
    expect_error(attraction_distance(g, a, eval(expr), distance = "walking"), info = deparse(expr))
    expect_error(od_betweenness(g, o, eval(expr)), info = deparse(expr))
  }
  expect_identical(na_counts(TRUE), c(0, 0, 0))
})

test_that("Attraction Distance applies its distance, axmeter and point-group rules to every radius before the first run", {
  g <- na_graph(); a <- na_attractions()
  wts <- rep(1, 54)
  na_counts(TRUE)
  expect_error(attraction_distance(g, a, analysis_radius(walking = c(5, 10)), distance = "straight"), "straight-only radius")
  expect_error(attraction_distance(g, a, analysis_radius(steps = c(1, 2)), distance = "straight"), "straight-only radius")
  expect_error(attraction_distance(g, a, analysis_radius(straight = c(5, 9), steps = 2), distance = "straight"), "straight-only radius")
  expect_error(attraction_distance(g, a, analysis_radius(axmeter = c(5, 10)), distance = "walking"), "axmeter radius")
  expect_error(attraction_distance(g, a, analysis_radius(walking = 5, axmeter = 10), distance = "walking"), "axmeter radius")
  expect_error(attraction_distance(g, a, analysis_radius(straight = c(5, 9)), origin = "point_groups", distance = "straight"),
               "point-group outputs unwritten")
  # weights rules, with a vector radius
  expect_error(attraction_distance(g, a, analysis_radius(steps = c(1, 2)), distance = "weights"), "line_weights is required")
  expect_error(na_dist(g, a, analysis_radius(steps = c(1, 2)), distance = "walking", line_weights = wts), "requires distance = weights")
  expect_error(na_dist(g, a, analysis_radius(steps = c(1, 2)), distance = "weights", line_weights = wts[-1]), "exactly one value per")
  expect_error(na_dist(g, a, analysis_radius(steps = c(1, 2)), distance = "weights", line_weights = c(-1, wts[-1])), "non-negative")
  expect_error(attraction_distance(g, a, analysis_radius(steps = c(1, 2)), distance = "walking", point_edge_weight = -1), "non-negative")
  expect_error(attraction_distance(g, a, analysis_radius(steps = c(1, 2)), distance = "walking", destination_indices = NA), "TRUE or FALSE")
  expect_error(attraction_distance(g, a, analysis_radius(steps = c(1, 2)), origin = "bogus"), "origin must be one of")
  expect_error(attraction_distance(g, a[, 1, drop = FALSE], analysis_radius(steps = c(1, 2))), "two columns|2 columns|columns")
  expect_identical(na_counts(TRUE), c(0, 0, 0))                # no PST run happened for any of them
  # a mixed set is rejected as a whole: the first radius would have been valid on its own
  expect_s3_class(attraction_distance(g, a, analysis_radius(straight = 5), distance = "straight"), "data.frame")
  na_counts(TRUE)
  expect_error(attraction_distance(g, a, analysis_radius(walking = c(5, 10)), distance = "straight"))
  expect_identical(na_counts(TRUE), c(0, 0, 0))
  # the scalar rules are unchanged for a single radius
  expect_error(attraction_distance(g, a, analysis_radius(walking = 5), distance = "straight"), "straight-only radius")
  expect_error(attraction_distance(g, a, analysis_radius(axmeter = 5), distance = "walking"), "axmeter radius")
})

test_that("Attraction Reach and OD Betweenness reject invalid inputs before the first run, with a vector radius", {
  g <- na_graph(); a <- na_attractions(); o <- rbind(c(1, 1), c(5, 2))
  na_counts(TRUE)
  rr <- analysis_radius(walking = c(5, 10))
  expect_error(attraction_reach(g, a, rr, decay = "bogus"), "decay must be one of")
  expect_error(attraction_reach(g, a, rr, distance = "weights"), "distance must be one of")
  expect_error(attraction_reach(g, a, rr, decay_constant = Inf), "decay_constant")
  expect_error(na_reach(g, a, rr, attraction_values = c(1, 2)), "exactly one value")
  expect_error(na_reach(g, a, rr, attraction_values = c(1, NA, 1, 1)), "finite")
  expect_error(attraction_reach(g, a, rr, attraction_values = c(1, 1, 1, 1)), "Cannot infer a weight name|weight name")
  expect_error(attraction_reach(g, a, rr, points_per_polygon = c(1, 1, 1, 2)), "polygon_point_interval|points_per_polygon|sum")
  expect_error(attraction_reach(g, a, rr, polygon_point_interval = 1), "requires points_per_polygon")
  expect_error(od_betweenness(g, o, analysis_radius(axmeter = c(5, 10))), "axmeter radius is not supported")
  expect_error(od_betweenness(g, o, analysis_radius(walking = 5, axmeter = 10)), "axmeter radius is not supported")
  expect_error(od_betweenness(g, o, rr, distance = "steps"), "distance must be one of")
  expect_error(od_betweenness(g, o, rr, destination_mode = "x"), "destination_mode must be one of")
  expect_error(na_od(g, o, rr, origin_weights = c(1, 2, 3)), "exactly one value")
  expect_error(na_od(g, o, rr, destination_weights = c(1, 2)), "exactly one value")
  expect_error(od_betweenness(g, cbind(c(1, NA), c(1, 2)), rr), "finite|NA|origins")
  expect_error(od_betweenness(g, o, rr, overwrite = NA), "overwrite")
  expect_identical(na_counts(TRUE), c(0, 0, 0))
})

test_that("PST runs exactly once per radius, in the supplied order, and a failure on a later radius is an ordinary error", {
  g <- na_graph(); a <- na_attractions(); o <- rbind(c(1, 1), c(5, 2), c(12, 8))
  na_counts(TRUE)
  invisible(attraction_reach(g, a, analysis_radius(walking = c(8, 3, 20, 5)), distance = "walking"))
  expect_identical(na_counts(TRUE), c(4, 0, 0))
  invisible(attraction_distance(g, a, analysis_radius(walking = c(8, 3, 20)), distance = "walking"))
  expect_identical(na_counts(TRUE), c(0, 3, 0))
  invisible(od_betweenness(g, o, analysis_radius(steps = c(1, 2, 3, 4, 5))))
  expect_identical(na_counts(TRUE), c(0, 0, 5))
  invisible(attraction_distance(g, a, analysis_radius(walking = c(8, 3)), distance = "walking", destination_indices = FALSE))
  expect_identical(na_counts(TRUE), c(0, 2, 0))
  # scalar calls (also a one-element vector) take the scalar route
  invisible(attraction_reach(g, a, analysis_radius(walking = 8), distance = "walking"))
  invisible(attraction_reach(g, a, analysis_radius(walking = c(8)), distance = "walking"))
  invisible(od_betweenness(g, o, analysis_radius(walking = 8)))
  expect_identical(na_counts(TRUE), c(0, 0, 0))
  # a failure after k completed radii is a normal R error; nothing is returned and the graph stays usable
  calls <- list(function() attraction_reach(g, a, analysis_radius(walking = c(8, 3, 20)), distance = "walking"),
                function() attraction_distance(g, a, analysis_radius(walking = c(8, 3, 20)), distance = "walking"),
                function() od_betweenness(g, o, analysis_radius(walking = c(8, 3, 20))))
  for (k in 0:2) for (call in calls) {
    na_counts(TRUE)
    na_fail_after(k)
    expect_error(call(), "injected native failure")
    na_fail_after(-1)
    expect_equal(sum(na_counts(TRUE)), k)   # exactly the k radii before the failing one ran; no later radius did
  }
  for (call in calls) expect_s3_class(call(), "data.frame")
})

test_that("a multi-radius Attraction Reach with polygon attractions keeps the destination geometry options", {
  g <- na_graph()
  r <- analysis_radius(steps = c(1, 3))
  polys <- na_polygons()
  for (origin in c("lines", "junctions", "points", "point_groups")) {
    multi <- attraction_reach(g, polys, r, origin, "steps", na_polygon_sizes, 0.5)
    na_expect_columns_match_scalar(multi, r, function(cfg) attraction_reach(g, polys, cfg, origin, "steps", na_polygon_sizes, 0.5))
    # the polygon interval is part of every name, as in a scalar call
    expect_true(all(grepl("_pi0p5$", names(multi)[-1L])))
    d <- attraction_distance(g, polys, r, origin, "steps", na_polygon_sizes, 0.5)
    na_expect_columns_match_scalar(d, r, function(cfg) attraction_distance(g, polys, cfg, origin, "steps", na_polygon_sizes, 0.5))
  }
})

# ---- native file output ------------------------------------------------------------------------------------------------------------

na_fgb_graph <- function(dir, n = 30) {
  src <- so_write_fgb(file.path(dir, "net.fgb"), so_segments(n))
  list(src = src, g = axial_graph(src, points = rbind(c(105, 205), c(112, 207), c(120, 215), c(131, 203), c(118, 222))))
}
na_fgb_attractions <- function() rbind(c(105, 205), c(112, 207), c(120, 215), c(140, 230))
na_origins <- function() rbind(c(101, 201), c(115, 210), c(128, 221))

test_that("FlatGeobuf spatial output of the three multi-radius analyses equals the in-memory result and describes every column", {
  na_skip_fgb()
  withr::local_envvar(RPST_NUM_THREADS = "1")   # two separate runs are compared exactly: one worker is bit-for-bit reproducible
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE))
  s <- na_fgb_graph(dir); g <- s$g
  a <- na_fgb_attractions(); o <- na_origins()
  attrs <- names(so_attributes(30))
  n_points <- .Call(rPSTool:::C_rpst_graph_info, g$ptr)[[3L]]
  vals <- c(1, 2, 0, 4)
  dw <- rep(c(1, 2, 0), length.out = n_points)
  cases <- list(
    reach = list(call = function(...) na_reach(g, a, analysis_radius(walking = c(30, 10, 60), steps = 6), "lines", "walking",
                                               attraction_values = vals, decay = "power", ...), fn = "attraction_reach", vary = "walking"),
    distance = list(call = function(...) attraction_distance(g, a, analysis_radius(steps = c(1, 3, 5)), "lines", "steps", ...),
                    fn = "attraction_distance", vary = "steps"),
    distance_weights = list(call = function(...) na_dist(g, a, analysis_radius(angular = c(90, 180)), "lines", "weights",
                                                         destination_indices = FALSE, line_weights = rep(c(1, 2), 15), ...),
                            fn = "attraction_distance", vary = "angular"),
    od = list(call = function(...) na_od(g, o, analysis_radius(walking = c(25, 60, 15)), destination_mode = "closest",
                                          origin_weights = c(1, 2, 3), destination_weights = dw, ...), fn = "od_betweenness", vary = "walking"))
  for (nm in names(cases)) {
    case <- cases[[nm]]
    frame <- case$call()
    expect_false(is.null(attr(frame, "rpst_manifest")), info = nm)
    out <- file.path(dir, paste0(nm, ".fgb"))
    res <- case$call(spatial_output_file = out)
    expect_s3_class(res, "pst_result_file")
    expect_identical(so_leftovers(dir), character())
    back <- so_read(out, "flatgeobuf")
    result_names <- setdiff(names(frame), c("origin_id", "line_id"))
    expect_identical(back$names, c(attrs, result_names), info = nm)
    for (col in result_names) {
      expect_identical(is.na(back$attrs[[col]]), is.na(frame[[col]]), info = col)
      na_same(as.numeric(back$attrs[[col]]), as.numeric(frame[[col]]), info = col)
    }
    expect_identical(back$wkb, so_wkb_of(s$src))
    meta <- na_meta(out)
    expect_identical(meta[["rpst:schema"]], "2")
    expect_identical(meta[["rpst:function"]], case$fn)
    expect_identical(meta[["rpst:graph_type"]], "axial")
    expect_identical(meta[["rpst:graph_rows"]], "30")
    expect_identical(meta[["rpst:radius_varying"]], case$vary)
    cols <- jsonlite::fromJSON(meta[["rpst:columns"]], simplifyVector = FALSE)
    expect_identical(vapply(cols, function(x) x$name, ""), result_names)
    expect_equal(vapply(cols, function(x) x$radius, 1), attr(frame, "rpst_manifest")$columns$radius)
    expect_identical(length(jsonlite::fromJSON(meta[["rpst:radius_configurations"]], simplifyVector = FALSE)),
                     length(attr(frame, "rpst_manifest")$radii))
  }
  # the metadata names the weights and the fixed restrictions
  m <- na_meta(file.path(dir, "reach.fgb"))
  expect_identical(jsonlite::fromJSON(m[["rpst:radius_fixed"]], simplifyVector = FALSE), list(steps = 6L))
  cols <- jsonlite::fromJSON(m[["rpst:columns"]], simplifyVector = FALSE)
  expect_true(all(vapply(cols, function(x) identical(x$weight_name, "attraction_values"), NA)))
  cols <- jsonlite::fromJSON(na_meta(file.path(dir, "od.fgb"))[["rpst:columns"]], simplifyVector = FALSE)
  expect_true(all(vapply(cols, function(x) identical(x$weight_name, "origin: origin_weights; destination: destination_weights"), NA)))
  # destination indices are signed integers (-1 = none) in the file, exactly as in memory
  d <- attraction_distance(g, a, analysis_radius(steps = c(1, 3, 5)), "lines", "steps")
  back <- so_read(file.path(dir, "distance.fgb"), "flatgeobuf")
  expect_identical(as.integer(back$attrs[["di_s_rs1"]]), d[["di_s_rs1"]])
  expect_true(any(d[["di_s_rs1"]] == -1L))
  # a scalar call keeps the scalar schema
  out <- file.path(dir, "scalar.fgb")
  attraction_distance(g, a, analysis_radius(steps = 2), spatial_output_file = out)
  expect_identical(na_meta(out)[["rpst:schema"]], "1")
})

test_that("multi-radius file output of the three analyses keeps the collision, overwrite and failure guarantees", {
  na_skip_fgb()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE))
  s <- na_fgb_graph(dir); g <- s$g
  a <- na_fgb_attractions(); o <- na_origins()
  r <- analysis_radius(steps = c(1, 2, 3))
  fns <- list(function(path, ...) attraction_reach(g, a, r, spatial_output_file = path, ...),
              function(path, ...) attraction_distance(g, a, r, spatial_output_file = path, ...),
              function(path, ...) od_betweenness(g, o, r, spatial_output_file = path, ...))
  for (i in seq_along(fns)) {
    fn <- fns[[i]]
    out <- file.path(dir, paste0("out", i, ".fgb"))
    fn(out)
    md5 <- so_md5(out)
    expect_error(fn(out), "already exists")
    expect_identical(so_md5(out), md5)
    na_fail_after(1)                                     # a failure on a later radius leaves the existing file untouched
    expect_error(fn(out, overwrite = TRUE), "injected native failure")
    na_fail_after(-1)
    expect_identical(so_md5(out), md5)
    fresh <- file.path(dir, paste0("fresh", i, ".fgb"))
    na_fail_after(2)
    expect_error(fn(fresh), "injected native failure")
    na_fail_after(-1)
    expect_false(file.exists(fresh))
    expect_identical(so_leftovers(dir), character())
    expect_s3_class(fn(out, overwrite = TRUE), "pst_result_file")
  }
  expect_identical(nrow(attraction_reach(g, a, analysis_radius(steps = 2))), 30L)   # the graph is still usable
  # requests that fail validation create nothing and run nothing
  na_counts(TRUE)
  expect_error(attraction_distance(g, a, analysis_radius(walking = c(5, 9)), distance = "straight",
                                   spatial_output_file = file.path(dir, "x.fgb")), "straight-only radius")
  expect_error(od_betweenness(g, o, analysis_radius(axmeter = c(5, 9)), spatial_output_file = file.path(dir, "x.fgb")), "axmeter")
  expect_error(attraction_reach(g, a, r, output_file = file.path(dir, "o.parquet"), spatial_output_file = file.path(dir, "x.fgb")),
               "mutually exclusive")
  expect_error(od_betweenness(g, o, r, spatial_output_file = file.path(dir, "x.parquet")), "must end in")
  expect_identical(na_counts(TRUE), c(0, 0, 0))
  expect_false(any(file.exists(file.path(dir, c("x.fgb", "x.parquet", "o.parquet")))))
})

test_that("spatial output of the attraction analyses stays restricted to line origins, also with several radii", {
  na_skip_fgb()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE))
  g <- na_fgb_graph(dir)$g
  a <- na_fgb_attractions()
  na_counts(TRUE)
  for (origin in c("junctions", "points", "point_groups")) {
    expect_error(attraction_reach(g, a, analysis_radius(steps = c(1, 2)), origin, spatial_output_file = file.path(dir, "x.fgb")),
                 "not one-to-one")
    expect_error(attraction_distance(g, a, analysis_radius(steps = c(1, 2)), origin, spatial_output_file = file.path(dir, "x.fgb")),
                 "not one-to-one")
  }
  expect_identical(na_counts(TRUE), c(0, 0, 0))
  expect_identical(list.files(dir), "net.fgb")
})

skip_na_parquet <- function() {
  skip_if_not_installed("sf"); skip_if_not_installed("jsonlite"); skip_if_not_installed("arrow", "25.0.0")
}

test_that("attribute-only Parquet output of the multi-radius analyses equals the in-memory result for every origin kind", {
  skip_na_parquet()
  withr::local_envvar(RPST_NUM_THREADS = "1")   # two separate runs are compared exactly: one worker is bit-for-bit reproducible
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE))
  g <- na_graph(); a <- na_attractions(); o <- rbind(c(1, 1), c(5, 2), c(12, 8))
  info <- .Call(rPSTool:::C_rpst_graph_info, g$ptr)
  cases <- list(
    list(fn = attraction_reach, args = list(a, analysis_radius(walking = c(8, 3, 20)), "points", "walking"), id = "origin_id", rows = info[[3L]], name = "reach-points"),
    list(fn = attraction_reach, args = list(a, analysis_radius(steps = c(2, 1)), "junctions", "steps"), id = "origin_id", rows = info[[2L]], name = "reach-junctions"),
    list(fn = attraction_distance, args = list(a, analysis_radius(walking = c(8, 3)), "point_groups", "walking"), id = "origin_id", rows = info[[4L]], name = "distance-groups"),
    list(fn = attraction_distance, args = list(a, analysis_radius(steps = c(1, 2)), "lines", "steps"), id = "origin_id", rows = info[[1L]], name = "distance-lines"),
    list(fn = od_betweenness, args = list(o, analysis_radius(steps = c(2, 1)), "walking"), id = "line_id", rows = info[[1L]], name = "od"))
  for (case in cases) {
    frame <- do.call(case$fn, c(list(g), case$args))
    path <- file.path(dir, paste0(case$name, ".parquet"))
    res <- do.call(case$fn, c(list(g), case$args, list(output_file = path)))
    expect_s3_class(res, "pst_result_file")
    expect_identical(res$columns, names(frame))
    expect_identical(res$rows, case$rows)
    t <- rs_read_parquet(path, as_data_frame = FALSE)
    expect_identical(names(t), names(frame))
    d <- as.data.frame(t)
    expect_identical(d[[case$id]], frame[[case$id]])
    for (nm in setdiff(names(frame), case$id)) {
      expect_identical(is.na(d[[nm]]), is.na(frame[[nm]]), info = nm)
      if (startsWith(nm, "di_")) expect_identical(as.integer(d[[nm]]), frame[[nm]], info = nm)     # signed, -1 kept
      else na_same(as.numeric(d[[nm]]), as.numeric(frame[[nm]]), info = nm)
    }
    meta <- t$schema$metadata
    expect_identical(meta[["rpst:schema"]], "2")
    expect_identical(meta[["rpst:graph_type"]], "axial")
    cols <- jsonlite::fromJSON(meta[["rpst:columns"]], simplifyVector = FALSE)
    expect_identical(vapply(cols, function(x) x$name, ""), setdiff(names(frame), case$id))
    expect_error(do.call(case$fn, c(list(g), case$args, list(output_file = path))), "already exists")
    na_fail_after(1)
    fresh <- file.path(dir, paste0("fresh-", case$name, ".parquet"))
    expect_error(do.call(case$fn, c(list(g), case$args, list(output_file = fresh))), "injected native failure")
    na_fail_after(-1)
    expect_false(file.exists(fresh))
    expect_identical(so_leftovers(dir), character())
  }
})

test_that("GeoParquet spatial output of the multi-radius attraction analyses: exact values, signed indices, metadata and publication", {
  skip_na_parquet()
  withr::local_envvar(RPST_NUM_THREADS = "1")   # two separate runs are compared exactly: one worker is bit-for-bit reproducible
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE))
  src <- so_write_gpq(file.path(dir, "net.parquet"), so_segments(30), so_attributes(30), chunk = 7L)
  g <- axial_graph(src, points = rbind(c(105, 205), c(112, 207), c(120, 215), c(131, 203), c(118, 222)))
  a <- na_fgb_attractions()
  original <- as.data.frame(rs_read_parquet(src, as_data_frame = FALSE))
  r <- analysis_radius(steps = c(1, 3))
  frame <- attraction_distance(g, a, r)
  out <- file.path(dir, "distance.parquet")
  res <- attraction_distance(g, a, r, spatial_output_file = out)
  expect_s3_class(res, "pst_result_file")
  expect_true(res$spatial)
  back <- so_read(out, "geoparquet")
  for (nm in setdiff(names(frame), "origin_id")) {
    if (startsWith(nm, "di_")) expect_identical(as.integer(back$attrs[[nm]]), frame[[nm]], info = nm)
    else na_same(as.numeric(back$attrs[[nm]]), frame[[nm]], info = nm)
  }
  expect_identical(back$wkb, unclass(original$geometry))
  md <- rs_read_parquet(out, as_data_frame = FALSE)$schema$metadata
  expect_identical(md[["rpst:schema"]], "2")
  expect_identical(md[["rpst:function"]], "attraction_distance")
  expect_identical(md[["rpst:radius_varying"]], "steps")
  md5 <- so_md5(out)
  expect_error(attraction_distance(g, a, r, spatial_output_file = out), "already exists")
  na_fail_after(1)
  expect_error(attraction_distance(g, a, r, spatial_output_file = out, overwrite = TRUE), "injected native failure")
  na_fail_after(-1)
  expect_identical(so_md5(out), md5)
  expect_identical(so_leftovers(dir), character())
  fr <- od_betweenness(g, na_origins(), analysis_radius(walking = c(20, 50)))
  out2 <- file.path(dir, "od.parquet")
  od_betweenness(g, na_origins(), analysis_radius(walking = c(20, 50)), spatial_output_file = out2)
  back2 <- so_read(out2, "geoparquet")
  for (nm in setdiff(names(fr), "line_id")) na_same(as.numeric(back2$attrs[[nm]]), fr[[nm]], info = nm)
})
