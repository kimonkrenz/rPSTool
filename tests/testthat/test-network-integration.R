integration_reference <- function() {
  dget(test_path("fixtures", "network-integration-v3.3.2.R"))
}

native_integration <- function(pointer, steps = NULL) {
  .Call(rPSTool:::C_rpst_network_integration, pointer, steps)
}

graph_lifecycle <- function() .Call(rPSTool:::C_rpst_graph_lifecycle)
release_graph <- function(pointer) .Call(rPSTool:::C_rpst_graph_release, pointer)

test_that("Network Integration matches the independent pinned upstream oracle", {
  reference <- integration_reference()
  expect_identical(reference$pst_commit, unname(rPSTool:::.pst_engine_pin()[["pst_commit"]]))
  g <- axial_graph(reference$lines)
  result <- network_integration(g)
  expect_s3_class(result, "data.frame")
  expect_identical(names(result), c("line_id", "integration", "node_count", "total_depth"))
  expect_identical(result$line_id, 1:5)
  expect_type(result$integration, "double")
  expect_type(result$node_count, "integer")
  expect_type(result$total_depth, "double")
  expect_identical(result$node_count, reference$node_count)
  expect_identical(result$total_depth, reference$total_depth)
  # Reproduce IsRoughlyEqual(actual, expected) exactly: actual is the relative
  # denominator, with an absolute comparison when actual is zero.
  expect_true(all(is.finite(result$integration)))
  matches_upstream <- vapply(seq_along(result$integration), function(i) {
    actual <- result$integration[[i]]
    expected <- reference$integration[[i]]
    tolerance <- reference$integration_relative_tolerance
    if (actual == 0) return(abs(expected - actual) <= tolerance)
    abs((expected - actual) / actual) <= tolerance
  }, logical(1))
  expect_true(all(matches_upstream))
  # Native outputs are copied verbatim to named R columns, never recomputed.
  raw <- native_integration(g$ptr)
  expect_identical(result$integration, raw[[1L]])
  expect_identical(result$node_count, raw[[2L]])
  expect_identical(result$total_depth, raw[[3L]])
})

test_that("the upstream step-radius oracle holds on the same persistent graph", {
  reference <- integration_reference()
  g <- axial_graph(reference$lines)
  original <- network_integration(g)
  pointer <- g$ptr
  gc()
  before <- graph_lifecycle()
  for (case in reference$steps) {
    expect_identical(network_integration(g, steps = case$limit)$node_count, case$node_count)
    expect_identical(network_integration(g, steps = as.double(case$limit))$node_count,
                     case$node_count)
  }
  expect_identical(network_integration(g), original)
  expect_identical(network_integration(g, steps = 2147483647), original)
  expect_identical(g$ptr, pointer)
  expect_identical(graph_lifecycle(), before) # Analysis does not create/free owners.
  expect_output(print(g), "5 lines")
  # Output sizes come from PST, not user-editable metadata.
  g$n_lines <- 999L
  expect_identical(network_integration(g), original)
})

test_that("single and disconnected lines preserve upstream sentinel behaviour", {
  reference <- integration_reference()
  single <- network_integration(axial_graph(reference$single_line))
  expect_identical(single$integration, reference$single_integration)
  expect_identical(single$node_count, reference$single_node_count)
  expect_identical(single$total_depth, reference$single_total_depth)
  disconnected <- network_integration(axial_graph(rbind(c(0, 0, 3, 0), c(10, 1, 13, 1))))
  expect_identical(disconnected$integration, c(-1, -1))
  expect_identical(disconnected$node_count, c(1L, 1L))
  expect_identical(disconnected$total_depth, c(0, 0))
  g <- axial_graph(reference$lines)
  zero <- network_integration(g, steps = 0)
  expect_identical(zero$integration, rep(-1, 5))
  expect_identical(zero$total_depth, rep(0, 5))
  # The exact pinned formula has 0/0 for N=2, and a zero denominator for
  # zero relative asymmetry when N=3. The wrapper must preserve these values.
  one <- network_integration(g, steps = 1)
  expect_true(all(is.nan(one$integration[c(1L, 5L)])))
  expect_identical(one$integration[2:4], rep(Inf, 3))
})

test_that("input line ordering is retained without mutating the graph", {
  reference <- integration_reference()
  order <- c(3L, 1L, 5L, 2L, 4L)
  baseline <- network_integration(axial_graph(reference$lines))
  result <- network_integration(axial_graph(reference$lines[order, ]))
  expect_identical(result$line_id, 1:5)
  expect_identical(result$node_count, baseline$node_count[order])
  expect_identical(result$total_depth, baseline$total_depth[order])
  expect_identical(result$integration, baseline$integration[order])
})

test_that("invalid graph owners and step limits are rejected before PST calls", {
  for (g in list(NULL, 1, matrix(1, 1, 4), list(),
                 structure(list(type = "segment", ptr = new("externalptr")), class = "pst_graph"))) {
    expect_error(network_integration(g), "live axial pst_graph")
  }
  for (pointer in list(NULL, 1, new("externalptr"))) {
    expect_error(native_integration(pointer), "Invalid pst_graph native pointer")
  }
  expect_error(network_integration(structure(list(type = "axial", ptr = 1), class = "pst_graph")),
               "Invalid pst_graph native pointer")
  g <- axial_graph(integration_reference()$lines)
  invalid_steps <- list(TRUE, "1", list(1), numeric(), c(1, 2), NA_integer_,
                        NA_real_, NaN, Inf, -Inf, -1, 0.5, 2147483648, 1+1i)
  # Collect unreachable owners from earlier tests before measuring this call.
  # Error allocations may otherwise trigger unrelated graph finalizers.
  gc()
  before <- graph_lifecycle()
  for (steps in invalid_steps) {
    expect_error(network_integration(g, steps = steps), "steps must be NULL")
    expect_error(native_integration(g$ptr, steps), "steps must be NULL")
  }
  expect_identical(graph_lifecycle(), before)
  expect_identical(network_integration(g)$node_count, rep(5L, 5))
  restored <- unserialize(serialize(g, NULL))
  expect_error(network_integration(restored), "no longer live")
  release_graph(g$ptr)
  expect_error(network_integration(g), "no longer live")
  expect_error(native_integration(g$ptr), "no longer live")
  expect_error(.Call("rpst_network_integration", g$ptr, NULL, PACKAGE = "rPSTool"))
  routines <- getDLLRegisteredRoutines("rPSTool")
  expect_identical(routines$.Call$rpst_network_integration$numParameters, 2L)
})

test_that("analysis results outlive graphs while aliases preserve ownership", {
  gc()
  before <- graph_lifecycle()
  g <- axial_graph(integration_reference()$lines)
  alias <- g
  result <- network_integration(g)
  rm(g)
  gc()
  expect_identical(network_integration(alias), result)
  expect_identical(graph_lifecycle() - before, c(1, 0, 1))
  rm(alias)
  gc()
  expect_identical(graph_lifecycle() - before, c(1, 1, 0))
  expect_identical(result$total_depth, c(10, 7, 6, 7, 10))
  gc()
  expect_identical(graph_lifecycle() - before, c(1, 1, 0))
})

test_that("a non-null incompatible pointer tag fails before any PST graph call", {
  # A registered native symbol's address is a genuine non-null external
  # pointer with an incompatible native tag. Merely checking void*, TYPEOF
  # or nullness would incorrectly admit it. No other graph type is created.
  incompatible <- rPSTool:::C_rpst_native_smoke$address
  expect_type(incompatible, "externalptr")
  before <- graph_lifecycle()
  expect_error(native_integration(incompatible), "Invalid pst_graph native pointer")
  labelled_axial <- structure(list(type = "axial", ptr = incompatible), class = "pst_graph")
  expect_error(network_integration(labelled_axial), "Invalid pst_graph native pointer")
  expect_identical(graph_lifecycle(), before)
  # An S3 label incompatible with the selected API is also rejected in R,
  # even if its underlying owner is otherwise a valid live axial graph.
  g <- axial_graph(integration_reference()$lines)
  labelled_segment <- g
  labelled_segment$type <- "segment"
  expect_error(network_integration(labelled_segment), "live axial pst_graph")
  expect_identical(network_integration(g)$node_count, rep(5L, 5))
})

test_that("only unrestricted and steps-only radii are accepted, as in the official PST v3.3.2 interface", {
  g <- axial_graph(cbind(x1 = c(0, 3, 6, 9, 12), y1 = 0, x2 = c(3, 6, 9, 12, 15), y2 = 0))
  on.exit(release_graph(g$ptr), add = TRUE)
  unrestricted <- network_integration(g)
  # accepted, and unchanged from the unrestricted implementation
  expect_identical(network_integration(g, radius = analysis_radius()), unrestricted)
  expect_identical(network_integration(g, steps = 2), network_integration(g, radius = analysis_radius(steps = 2)))
  expect_identical(network_integration(g, steps = 2), legacy_ni_run(g, steps = 2))
  expect_identical(network_integration(g, steps = 0)$node_count, rep(1L, 5L))
  # rejected before any native call, whatever the combination
  for (r in list(analysis_radius(walking = 5), analysis_radius(straight = 5), analysis_radius(angular = 90),
                 analysis_radius(axmeter = 5), analysis_radius(steps = 2, walking = 5),
                 analysis_radius(steps = 2, straight = 5), analysis_radius(steps = 2, angular = 90),
                 analysis_radius(steps = 2, axmeter = 5), analysis_radius(walking = 5, axmeter = 5)))
    expect_error(network_integration(g, radius = r), "supports only a topological steps radius")
  expect_error(network_integration(g, radius = analysis_radius(steps = 2, walking = 5)), "walking")
  expect_error(network_integration(g, radius = analysis_radius(steps = 2, walking = 5)), "official PST v3.3.2")
  expect_error(network_integration(g, radius = analysis_radius(walking = 5), junctions = TRUE), "steps radius")
  # the graph is still usable afterwards
  expect_identical(network_integration(g), unrestricted)
})

test_that("public Network Integration matches the pinned internal runner on a non-chain axial fixture", {
  cases <- ax_reference()$cases
  eligible <- Filter(function(case) {
    length(case$x) >= 3L && is.null(case$line_indices) && !identical(case$name, "chain") &&
      any(vapply(case$integrations, function(entry)
        length(entry$radius) == 0L || identical(names(entry$radius), "steps"), logical(1)))
  }, cases)
  expect_gt(length(eligible), 0L)
  case <- eligible[[1L]]
  g <- do.call(axial_graph, c(list(ax_case_lines(case)), ax_case_args(case)))
  for (radius in list(NULL, analysis_radius(steps = 2))) {
    expect_identical(network_integration(g, radius = radius),
                     legacy_ni_run(g, radius = radius))
    expect_identical(network_integration(g, radius = radius, junctions = TRUE),
                     legacy_ni_run(g, radius = radius, junctions = TRUE))
  }
})
