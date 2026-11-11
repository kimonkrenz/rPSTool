# Regression tests for the pinned-PST defect in SphereTree::GetCloseLines(list, x, y, radius) (patch 0012, src/portability/fix-sphere-tree.R):
# the radius query returned a stale member instead of the number of lines it had found, so Attraction Reach with line origins, straight
# distance and a finite straight radius counted wrong lines and depended on the call history of the graph. The expected scores below are computed
# independently in R from the geometry, so they do not depend on PST at all.

sl_segments <- function() {
  set.seed(11)
  n <- 40
  x <- cumsum(runif(n, 1, 3)); y <- cumsum(rnorm(n))
  s <- cbind(x[-n], y[-n], x[-1], y[-1])
  unname(rbind(s, cbind(s[8:22, 1], s[8:22, 2], s[8:22, 1] + 1, s[8:22, 2] + 5)))
}
sl_attractions <- function() rbind(c(3, 1), c(9, 5), c(20, 12), c(16, 9), c(5.5, 2.5), c(12.25, 7.75))
sl_values <- c(2, 0, 3, 1, 5, 4)                                     # integers: the constant-decay sums are exact in single precision
sl_dist <- function(p, s) {                                          # distance from a point to a segment
  d <- s[3:4] - s[1:2]
  t <- if (sum(d * d) == 0) 0 else max(0, min(1, sum((p - s[1:2]) * d) / sum(d * d)))   # a zero-length segment is its point
  sqrt(sum((p - (s[1:2] + t * d))^2))
}
# distances of every (line, attraction) pair; radii used in the tests keep a margin to every one of them, so single-precision rounding
# cannot move a line across the boundary
sl_distances <- function(segments, attractions)
  outer(seq_len(nrow(segments)), seq_len(nrow(attractions)), Vectorize(function(i, k) sl_dist(attractions[k, ], segments[i, ])))
sl_expected <- function(segments, attractions, radius, values = rep(1, nrow(attractions))) {
  d <- sl_distances(segments, attractions)
  expect_true(min(abs(d - radius)) > 1e-3, info = paste("radius", radius, "is too close to a distance"))
  as.numeric((d <= radius) %*% values)
}
sl_radii <- c(0, 0.5, 2.5, 6, 12, 40, 1000)
sl_reach <- function(g, radius, values = NULL, ...) {
  attraction_values <- values
  attraction_reach(g, sl_attractions(), analysis_radius(straight = radius), "lines", "straight", attraction_values = attraction_values, ...)
}

test_that("straight line Attraction Reach equals the independently computed geometric count, with unit and valued attractions", {
  segments <- sl_segments(); a <- sl_attractions()
  g <- axial_graph(segments)
  for (r in sl_radii) {
    expect_identical(sl_reach(g, r)[[2L]], sl_expected(segments, a, r), info = paste("unit values, radius", r))
    expect_identical(sl_reach(g, r, sl_values)[[2L]], sl_expected(segments, a, r, sl_values), info = paste("valued, radius", r))
  }
  # a score is never larger than the total attraction value: the old defect produced sums of many repeated lines
  expect_true(all(sl_reach(g, 12)[[2L]] <= length(sl_values)))
})

test_that("straight line Attraction Reach is reproducible and independent of the call history of the graph", {
  segments <- sl_segments()
  want <- lapply(sl_radii, function(r) sl_expected(segments, sl_attractions(), r))
  # first call on a fresh graph, in several orders of radii
  for (order in list(seq_along(sl_radii), rev(seq_along(sl_radii)), c(4, 1, 6, 2, 7, 3, 5))) {
    g <- axial_graph(segments)
    for (i in order) expect_identical(sl_reach(g, sl_radii[[i]])[[2L]], want[[i]], info = paste("order", paste(order, collapse = ","), "radius", sl_radii[[i]]))
  }
  # one graph, many repeats, interleaved with other analyses that use the graph and its tree
  g <- axial_graph(segments)
  for (rep in 1:12) {
    expect_identical(sl_reach(g, 12)[[2L]], want[[5L]])
    if (rep %% 2L == 0L) invisible(attraction_reach(g, sl_attractions(), analysis_radius(walking = 20), "lines", "walking"))
    if (rep %% 3L == 0L) invisible(network_reach(g, analysis_radius(straight = 7)))
    if (rep %% 4L == 0L) invisible(attraction_distance(g, sl_attractions(), analysis_radius(), "lines", "walking"))
  }
  # a graph with retained points and polygons has the same results
  g2 <- axial_graph(segments, points = rbind(c(2, 1), c(6, 2), c(10, 8), c(14, 10)))
  for (r in sl_radii) expect_identical(sl_reach(g2, r)[[2L]], want[[match(r, sl_radii)]])
})

test_that("straight line Attraction Reach is the same on one, two and the default number of workers", {
  segments <- sl_segments()
  want <- lapply(sl_radii, function(r) sl_expected(segments, sl_attractions(), r, sl_values))
  for (workers in list("1", "2", "3", NULL)) withr::with_envvar(c(RPST_NUM_THREADS = if (is.null(workers)) NA else workers), {
    g <- axial_graph(segments)
    expect_identical(.Call(rPSTool:::C_rpst_workers), if (is.null(workers)) .Call(rPSTool:::C_rpst_workers) else as.numeric(min(as.numeric(workers), parallel::detectCores())))
    for (rep in 1:3) for (i in seq_along(sl_radii))
      expect_identical(sl_reach(g, sl_radii[[i]], sl_values)[[2L]], want[[i]], info = paste("workers", workers, "radius", sl_radii[[i]]))
  })
})

test_that("multi-radius straight line Attraction Reach equals the geometry, the scalar calls and itself, on every worker setting", {
  segments <- sl_segments()
  radii <- c(12, 2.5, 40, 0.5)
  want <- lapply(radii, function(r) sl_expected(segments, sl_attractions(), r, sl_values))
  for (workers in list("1", "2", NULL)) withr::with_envvar(c(RPST_NUM_THREADS = if (is.null(workers)) NA else workers), {
    g <- axial_graph(segments)
    multi <- NULL
    for (rep in 1:3) {
      m <- sl_reach(g, radii, sl_values)
      expect_identical(names(m), c("origin_id", paste0("ar_l_rl", c("12", "2p5", "40", "0p5"), "_wattraction_values")))
      for (i in seq_along(radii)) expect_identical(m[[i + 1L]], want[[i]], info = paste("workers", workers, "radius", radii[[i]]))
      if (!is.null(multi)) expect_identical(m, multi)                      # identical across repeated calls
      multi <- m
    }
    for (i in seq_along(radii)) expect_identical(multi[[i + 1L]], sl_reach(g, radii[[i]], sl_values)[[2L]])   # and to the scalar call
  })
  # a vector in the straight field with the network distances is unaffected (a straight radius is ignored there)
  g <- axial_graph(segments)
  expect_identical(attraction_reach(g, sl_attractions(), analysis_radius(straight = c(5, 9)), "lines", "walking"),
                   attraction_reach(g, sl_attractions(), analysis_radius(straight = c(5, 9)), "lines", "walking"))
})

test_that("straight line Attraction Reach written through the native result stream equals the in-memory result and the geometry", {
  skip_if_not_installed("sf"); skip_if_not_installed("jsonlite")
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE))
  src <- so_write_fgb(file.path(dir, "net.fgb"), so_segments(30))
  g <- axial_graph(src)
  a <- rbind(c(105, 205), c(112, 207), c(120, 215), c(140, 230), c(130, 210))
  seg <- so_segments(30)
  d <- outer(seq_len(30), seq_len(nrow(a)), Vectorize(function(i, k) sl_dist(a[k, ], seg[i, ])))
  radii <- c(15.37, 40.41, 3.71)
  expect_true(min(abs(outer(as.vector(d), radii, "-"))) > 1e-3)
  # PST's finite straight query does not return zero-length lines (a separate, pre-existing property of its sphere tree, outside this
  # correction); the source has such lines, so they are left out of the comparison
  keep <- (seg[, 3] - seg[, 1])^2 + (seg[, 4] - seg[, 2])^2 > 0
  expect_true(any(!keep))
  for (workers in c("1", "3")) withr::with_envvar(c(RPST_NUM_THREADS = workers), {
    multi <- attraction_reach(g, a, analysis_radius(straight = radii), "lines", "straight")
    for (i in seq_along(radii)) expect_identical(multi[[i + 1L]][keep], as.numeric(rowSums(d <= radii[[i]]))[keep])
    for (rep in 1:2) {
      out <- file.path(dir, paste0("multi-", workers, "-", rep, ".fgb"))
      attraction_reach(g, a, analysis_radius(straight = radii), "lines", "straight", spatial_output_file = out)
      back <- so_read(out, "flatgeobuf")
      for (nm in setdiff(names(multi), "origin_id")) expect_identical(as.numeric(back$attrs[[nm]]), multi[[nm]], info = nm)
    }
    scalar <- file.path(dir, paste0("scalar-", workers, ".fgb"))
    attraction_reach(g, a, analysis_radius(straight = 15.37), "lines", "straight", spatial_output_file = scalar)
    expect_identical(as.numeric(so_read(scalar, "flatgeobuf")$attrs[["ar_l_rl15p37"]]), multi[["ar_l_rl15p37"]])
  })
})

test_that("straight line Attraction Reach written to Parquet equals the in-memory result and the geometry", {
  skip_if_not_installed("arrow", "25.0.0"); skip_if_not_installed("sf")
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE))
  segments <- sl_segments()
  g <- axial_graph(segments)
  radii <- c(12, 2.5, 40)
  for (workers in c("1", "3")) withr::with_envvar(c(RPST_NUM_THREADS = workers), {
    multi <- sl_reach(g, radii, sl_values)
    path <- file.path(dir, paste0("reach-", workers, ".parquet"))
    sl_reach(g, radii, sl_values, output_file = path)
    d <- as.data.frame(rs_read_parquet(path, as_data_frame = FALSE))
    for (i in seq_along(radii)) {
      expect_identical(as.numeric(d[[names(multi)[i + 1L]]]), sl_expected(segments, sl_attractions(), radii[[i]], sl_values))
      expect_identical(as.numeric(d[[names(multi)[i + 1L]]]), multi[[i + 1L]])
    }
  })
})

test_that("results of the other analyses that share the graph are untouched by the SphereTree correction", {
  # The corrected function has one caller (the finite straight line query of Attraction Reach). Everything else keeps its exact values: these
  # checks compare against geometry/closed forms that do not involve the corrected code.
  g <- axial_graph(cbind(0:4 * 3, 0, 1:5 * 3, 0))                        # five collinear unit steps of length 3
  r <- network_reach(g, analysis_radius(steps = 1))
  expect_identical(r[[2L]], c(2L, 3L, 3L, 3L, 2L))
  expect_identical(nrow(network_betweenness(g, analysis_radius(steps = 2))), 5L)
})
