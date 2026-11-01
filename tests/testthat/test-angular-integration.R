angular_reference <- function() dget(test_path("fixtures", "angular-integration-v3.3.2.R"))
native_angular <- function(ptr, steps = NULL) .Call(rPSTool:::C_rpst_angular_integration, ptr, steps)

# Exact upstream per-element predicate; actual is the denominator.
angular_matches_upstream <- function(actual, expected, tolerance) {
  if (length(actual) != length(expected)) return(FALSE)
  all(vapply(seq_along(actual), function(i) {
    if (actual[[i]] == 0) return(abs(expected[[i]] - actual[[i]]) <= tolerance)
    abs((expected[[i]] - actual[[i]]) / actual[[i]]) <= tolerance
  }, logical(1)))
}

test_that("Angular Integration matches pinned upstream chain and square oracles", {
  ref <- angular_reference()
  expect_identical(ref$pst_commit, unname(rPSTool:::.pst_engine_pin()[["pst_commit"]]))
  for (case in list(ref$chain, ref$square)) {
    g <- segment_graph(case$segments)
    original <- angular_integration(g)
    expect_s3_class(original, "data.frame")
    expect_identical(names(original), c("segment_id", "integration", "node_count", "total_depth"))
    expect_identical(original$segment_id, seq_len(nrow(case$segments)))
    expect_type(original$integration, "double")
    expect_type(original$total_depth, "double")
    expect_identical(original$node_count, case$node_count)
    expect_true(angular_matches_upstream(original$total_depth, case$total_depth, ref$tolerance))
    expect_true(angular_matches_upstream(original$integration, case$integration, ref$tolerance))
    raw <- native_angular(g$ptr)
    expect_identical(original$integration, raw[[1L]])
    expect_identical(original$node_count, raw[[2L]])
    expect_identical(original$total_depth, raw[[3L]])
    pointer <- g$ptr
    g$n_segments <- 999L
    expect_identical(angular_integration(g), original)
    expect_identical(angular_integration(g, steps = 2147483647), original)
    expect_identical(g$ptr, pointer)
  }
  g <- segment_graph(ref$chain$segments)
  for (case in ref$chain$steps) {
    expect_identical(angular_integration(g, case$limit)$node_count, case$node_count)
    expect_identical(angular_integration(g, as.double(case$limit))$node_count, case$node_count)
  }
})

test_that("endpoint equality alone establishes segment connectivity", {
  counts <- function(x) angular_integration(segment_graph(x))$node_count
  expect_identical(counts(rbind(c(0, 0, 2, 0), c(1, -1, 1, 1))), c(1L, 1L))
  expect_identical(counts(rbind(c(0, 0, 2, 0), c(1, 0, 1, 1))), c(1L, 1L))
  expect_identical(counts(rbind(c(0, 0, 1, 0), c(1, 0, 1, 1))), c(2L, 2L))
  expect_identical(counts(rbind(c(0, 0, 1, 0), c(1 + 1e-10, 0, 1, 1))), c(1L, 1L))
  expect_identical(counts(rbind(c(0, 0, 1, 0), c(1, 0, 1, 1)) + 1e6), c(2L, 2L))
  single <- angular_integration(segment_graph(matrix(c(0, 0, 3, 0), 1)))
  expect_identical(single$node_count, 1L)
  expect_identical(single$total_depth, 0)
  expect_identical(single$integration, 0)
})

test_that("runtime graph compatibility cannot be forged with R metadata", {
  axial <- axial_graph(segment_rows())
  segment <- segment_graph(segment_rows())
  expect_error(angular_integration(axial), "live pst_segment_graph")
  expect_error(network_integration(segment), "live axial pst_graph")
  fake_segment <- structure(list(ptr = axial$ptr, type = "segment"), class = "pst_segment_graph")
  fake_axial <- structure(list(ptr = segment$ptr, type = "axial"), class = "pst_graph")
  expect_error(angular_integration(fake_segment), "Invalid pst_segment_graph native pointer")
  expect_error(network_integration(fake_axial), "Invalid pst_graph native pointer")
  expect_error(print(fake_segment), "Invalid pst_segment_graph native pointer")
  expect_error(print(fake_axial), "Invalid pst_graph native pointer")
  expect_error(native_angular(axial$ptr), "Invalid pst_segment_graph native pointer")
  expect_error(.Call(rPSTool:::C_rpst_network_integration, segment$ptr, NULL), "Invalid pst_graph native pointer")
  for (name in c("info", "release")) {
    expect_error(native_segment(name, axial$ptr), "Invalid pst_segment_graph native pointer")
    expect_error(.Call(get(paste0("C_rpst_graph_", name), envir = asNamespace("rPSTool")), segment$ptr), "Invalid pst_graph native pointer")
  }
  expect_identical(angular_integration(segment)$node_count, c(2L, 2L))
  expect_identical(network_integration(axial)$node_count, c(2L, 2L))
})

test_that("invalid owners, parameters and unsupported masks fail safely", {
  for (ptr in list(NULL, 1, new("externalptr"), rPSTool:::C_rpst_native_smoke$address))
    expect_error(native_angular(ptr), "Invalid pst_segment_graph native pointer")
  for (g in list(NULL, 1, list(), structure(list(ptr = 1, type = "axial"), class = "pst_segment_graph")))
    expect_error(angular_integration(g), "live pst_segment_graph")
  g <- segment_graph(segment_rows())
  for (steps in list(TRUE, "1", list(1), numeric(), c(1, 2), NA_integer_,
                     NA_real_, NaN, Inf, -Inf, -1, 0.5, 2147483648, 1+1i)) {
    expect_error(angular_integration(g, steps), "steps must be NULL")
    expect_error(native_angular(g$ptr, steps), "steps must be NULL")
  }
  restored <- unserialize(serialize(g, NULL))
  expect_error(angular_integration(restored), "no longer live")
  native_segment("release", g$ptr)
  expect_error(native_angular(g$ptr), "no longer live")
  # PST's mask indexes endpoint incidences, not distinct coordinate locations.
  star <- cbind(0, 0, cos(seq_len(33)), sin(seq_len(33)))
  high_degree <- segment_graph(star)
  expect_identical(high_degree$n_segments, 33L)
  expect_error(angular_integration(high_degree), "at most 32 endpoint incidences")
  expect_error(native_angular(high_degree$ptr), "at most 32 endpoint incidences")
  supported <- segment_graph(star[1:32, ])
  expect_identical(angular_integration(supported)$node_count, rep(32L, 32))
  expect_error(.Call("rpst_angular_integration", high_degree$ptr, NULL, PACKAGE = "rPSTool"))
  expect_identical(getDLLRegisteredRoutines("rPSTool")$.Call$rpst_angular_integration$numParameters, 2L)
})

test_that("asymmetric segment row ordering is retained", {
  x <- rbind(c(0, 0, 3, 0), c(3, 0, 3, 3), c(3, 3, 6, 3))
  baseline <- angular_integration(segment_graph(x))
  order <- c(3L, 1L, 2L)
  result <- angular_integration(segment_graph(x[order, ]))
  expect_identical(result$segment_id, 1:3)
  expect_identical(result$integration, baseline$integration[order])
  expect_identical(result$node_count, baseline$node_count[order])
  expect_identical(result$total_depth, baseline$total_depth[order])
})

test_that("results outlive owners and analyses neither acquire nor free graphs", {
  gc()
  before <- native_segment("lifecycle")
  g <- segment_graph(angular_reference()$square$segments)
  alias <- g
  result <- angular_integration(g)
  rm(g)
  gc()
  expect_identical(angular_integration(alias), result)
  expect_identical(native_segment("lifecycle") - before, c(1, 0, 1))
  rm(alias)
  gc()
  expect_identical(native_segment("lifecycle") - before, c(1, 1, 0))
  expect_identical(result$total_depth, rep(4, 4))
  expect_identical(result$node_count, rep(4L, 4))
})
