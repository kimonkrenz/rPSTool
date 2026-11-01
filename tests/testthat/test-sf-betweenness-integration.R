sb_rows <- function(rows, width = 2L) matrix(as.double(unlist(rows)), ncol = width, byrow = TRUE)
sb_pts <- function(m, crs = NA_integer_, ...) {
  geometry <- sf::st_sfc(lapply(seq_len(nrow(m)), function(i) sf::st_point(m[i, ])), crs = crs)
  if (...length()) sf::st_sf(..., geometry = geometry) else geometry
}
sb_lines <- function(m, crs = NA_integer_) sf::st_sfc(lapply(seq_len(nrow(m)), function(i)
  sf::st_linestring(matrix(m[i, ], 2L, byrow = TRUE))), crs = crs)
sb_chain <- function() cbind(0:2, 0, 1:3, 0)
sb_near <- function(actual, expected) {
  expect_identical(is.na(actual), is.na(expected))
  expect_identical(is.nan(actual), is.nan(expected))
  expect_identical(actual[!is.finite(expected)], expected[!is.finite(expected)])
}

test_that("sf attraction points reproduce the direct Betweenness fixture cases with points (all of them in the full suite)", {
  skip_if_not_installed("sf")
  ref <- dget(test_path("fixtures", "reach-betweenness-direct-v3.3.2.R"))
  graphs <- lapply(ref$networks, function(rows) axial_graph(do.call(rbind, rows)))
  checked <- 0L
  for (case in rpst_cases(ref$cases, every = 20L, by = list(rpst_case_signature), each = list(rpst_case_edges))) {
    if (case$routine == "reach" || is.null(case$points)) next
    g <- graphs[[case$network]]
    radius <- do.call(analysis_radius, case$radius)
    points <- do.call(rbind, case$points)
    shapes <- list(sb_pts(points), sb_pts(points, 3857, weight = seq_len(nrow(points)), id = "a"))
    for (shape in shapes) {
      g_for <- if (is.na(sf::st_crs(shape))) g else axial_graph(sb_lines(do.call(rbind, ref$networks[[case$network]]), 3857))
      expect_identical(
        network_betweenness(g_for, radius, case$distance, weights = case$weights, attraction_points = shape),
        network_betweenness(g_for, radius, case$distance, weights = case$weights, attraction_points = points))
      for (norm in names(case$normalizations))
        expect_identical(network_betweenness(g_for, radius, case$distance, norm, case$weights, shape),
                         network_betweenness(g_for, radius, case$distance, norm, case$weights, points))
    }
    checked <- checked + 1L
  }
  expect_gt(checked, 0L)
})

test_that("order, explicit weights (zero, negative) and attribute independence hold for all distances", {
  skip_if_not_installed("sf")
  g <- axial_graph(sb_chain())
  p <- rbind(c(.25, 0), c(.75, 0), c(2.5, 0))
  for (distance in c("walking", "steps", "angular", "axmeter")) for (w in list(NULL, c(2, 3, 4), c(2, 0, -1), c(0, 0, 0))) {
    expected <- network_betweenness(g, distance = distance, weights = w, attraction_points = p)
    expect_identical(network_betweenness(g, distance = distance, weights = w, attraction_points = sb_pts(p)), expected)
    # Attributes never supply weights.
    attributed <- sb_pts(p, NA_integer_, weight = c(9, 9, 9), weights = c(5, 6, 7))
    expect_identical(network_betweenness(g, distance = distance, weights = w, attraction_points = attributed), expected)
    if (!is.null(w)) {
      order <- c(3, 1, 2)
      expect_identical(network_betweenness(g, distance = distance, weights = w[order], attraction_points = sb_pts(p[order, ])),
                       network_betweenness(g, distance = distance, weights = w[order], attraction_points = p[order, ]))
    }
  }
  # Mismatched weight length remains the native contract.
  expect_error(network_betweenness(g, weights = c(1, 2), attraction_points = sb_pts(p)))
})

test_that("Betweenness sf points follow the graph-versus-analysis CRS contract", {
  skip_if_not_installed("sf")
  p <- rbind(c(.25, 0), c(2.5, 0))
  matrix_graph <- axial_graph(sb_chain())
  sf_graph <- axial_graph(sb_lines(sb_chain(), 3857))
  unknown_graph <- axial_graph(sb_lines(sb_chain()))
  expected <- network_betweenness(matrix_graph, attraction_points = p)
  expect_identical(network_betweenness(matrix_graph, attraction_points = sb_pts(p, 3857)), expected)
  expect_identical(network_betweenness(matrix_graph, attraction_points = sb_pts(p)), expected)
  expect_error(network_betweenness(matrix_graph, attraction_points = sb_pts(p, 4326)), "Geographic")
  expect_identical(network_betweenness(sf_graph, attraction_points = sb_pts(p, 3857)), expected)
  expect_error(network_betweenness(sf_graph, attraction_points = sb_pts(p)), "compatible")
  expect_error(network_betweenness(sf_graph, attraction_points = sb_pts(p, 3395)), "compatible")
  expect_error(network_betweenness(unknown_graph, attraction_points = sb_pts(p, 3857)), "compatible")
  expect_identical(network_betweenness(unknown_graph, attraction_points = sb_pts(p)), expected)
  # Matrix input on a CRS-bearing graph is unchanged and needs no sf.
  local_mocked_bindings(.pst_require_sf = function() stop("optional package 'sf' required"), .package = "rPSTool")
  expect_identical(network_betweenness(sf_graph, attraction_points = p), expected)
  expect_identical(network_betweenness(matrix_graph, attraction_points = p), expected)
  expect_error(network_betweenness(matrix_graph, attraction_points = sb_pts(p)), "optional package")
})

test_that("unsupported Betweenness sf points are rejected before the native call", {
  skip_if_not_installed("sf")
  g <- axial_graph(sb_chain())
  ok <- network_betweenness(g, attraction_points = rbind(c(.25, 0)))
  expect_error(network_betweenness(g, attraction_points = sb_pts(matrix(numeric(), 0L, 2L))))
  expect_error(network_betweenness(g, attraction_points = sf::st_sfc(sf::st_point())), "nonempty finite")
  expect_error(network_betweenness(g, attraction_points = sb_pts(rbind(c(Inf, 0)))), "nonempty finite")
  expect_error(network_betweenness(g, attraction_points = sf::st_sfc(sf::st_multipoint(rbind(c(0, 0), c(1, 0))))), "POINT")
  expect_error(network_betweenness(g, attraction_points = sf::st_sfc(sf::st_point(c(0, 0)), sf::st_linestring(rbind(c(0, 0), c(1, 0))))), "POINT")
  expect_error(network_betweenness(g, attraction_points = sf::st_sfc(sf::st_point(c(0, 0, 1)))), "XY")
  expect_error(network_betweenness(g, attraction_points = sf::st_sfc(sf::st_point(c(0, 0, 1), dim = "XYM"))), "XY")
  expect_identical(network_betweenness(g, attraction_points = rbind(c(.25, 0))), ok)
})

test_that("Betweenness does not retain or depend on sf input after the call", {
  skip_if_not_installed("sf")
  g <- axial_graph(sb_chain())
  points <- sb_pts(rbind(c(.25, 0), c(2.5, 0)))
  expected <- network_betweenness(g, weights = c(2, 3), attraction_points = points)
  points[[1L]][1L] <- 99
  mutated <- network_betweenness(g, weights = c(2, 3), attraction_points = points)
  expect_false(identical(mutated, expected))
  rm(points); invisible(gc())
  expect_identical(network_betweenness(g, weights = c(2, 3), attraction_points = rbind(c(.25, 0), c(2.5, 0))), expected)
  expect_identical(network_betweenness(g, weights = c(2, 3), attraction_points = sb_pts(rbind(c(.25, 0), c(2.5, 0)))), expected)
})

# ---- Integration junction output ----
test_that("sf junction output matches the direct fixture junction results (all of them in the full suite)", {
  skip_if_not_installed("sf")
  ref <- dget(test_path("fixtures", "axial-inputs-direct-v3.3.2.R"))
  checked <- 0L
  # The 28 axial-input graphs differ structurally (links, unlinks, points): none is thinned. CRAN mode visits a subset of the
  # eight radii of each graph that still includes every radius class (all of them in full mode).
  for (case in rpst_thin_items(ref$cases, "integrations", every = 8L, by = list(rpst_radius_class))) {
    args <- case[intersect(names(case), c("x", "line_indices", "unlinks", "points", "points_per_polygon", "polygon_point_interval"))]
    args$x <- sb_rows(args$x, if (is.null(args$line_indices)) 4L else 2L)
    for (field in c("line_indices", "unlinks", "points")) if (field %in% names(args)) args[[field]] <- sb_rows(args[[field]])
    if ("points_per_polygon" %in% names(args)) args$points_per_polygon <- as.double(unlist(args$points_per_polygon))
    g <- do.call(axial_graph, args)
    for (expected in case$integrations) {
      radius <- do.call(analysis_radius, expected$radius)
      native <- rPSTool:::.pst_network_integration_run(g, radius = radius, junctions = TRUE)
      out <- rPSTool:::.pst_network_integration_run(g, radius = radius, junctions = TRUE, junction_output = "sf")
      expect_identical(names(out), c("lines", "junctions"))
      expect_identical(out$lines, native$lines)
      expect_s3_class(out$lines, "data.frame"); expect_false(inherits(out$lines, "sf"))
      j <- out$junctions
      expect_s3_class(j, "sf")
      expect_identical(names(j), c("junction_id", "integration", "geometry"))
      expect_identical(j$junction_id, native$junctions$junction_id)
      expect_identical(j$integration, native$junctions$integration) # NaN/Inf/-2 multiplicity preserved
      xy <- if (nrow(j)) do.call(rbind, lapply(sf::st_geometry(j), unclass)) else matrix(numeric(), 0L, 2L)
      expect_identical(unname(xy), unname(cbind(native$junctions$x, native$junctions$y)))
      expect_true(is.na(sf::st_crs(j)))
      expect_identical(rPSTool:::.pst_network_integration_run(g, radius = radius, junctions = TRUE), native)
      checked <- checked + 1L
    }
  }
  expect_gt(checked, 0L)
})

test_that("junction sf output covers CRS, zero junctions, repeats, lifetime and defaults", {
  skip_if_not_installed("sf")
  chain <- cbind(0:4 * 3, 0, 1:5 * 3, 0)
  g <- axial_graph(sb_lines(chain, 3857))
  native <- network_integration(g, steps = 1, junctions = TRUE)
  out <- network_integration(g, steps = 1, junctions = TRUE, junction_output = "sf")
  expect_equal(sf::st_crs(out$junctions), sf::st_crs(3857))
  expect_identical(out$junctions$integration, native$junctions$integration)
  expect_true(any(is.nan(out$junctions$integration)) && any(is.infinite(out$junctions$integration)))
  for (i in 1:3) expect_identical(network_integration(g, steps = 1, junctions = TRUE, junction_output = "sf"), out)
  expect_identical(network_integration(g, junctions = TRUE, junction_output = "native"), network_integration(g, junctions = TRUE))
  expect_identical(names(network_integration(g, junctions = TRUE)$junctions), c("junction_id", "x", "y", "integration"))
  expect_identical(network_integration(g, steps = 1), native$lines)
  # Result lifetime is independent of the graph.
  snapshot <- serialize(out, NULL)
  rm(g); invisible(gc())
  expect_identical(serialize(out, NULL), snapshot)
  # Matrix-only graph: unknown CRS. Zero-junction graph: zero features.
  m <- axial_graph(chain)
  expect_true(is.na(sf::st_crs(network_integration(m, junctions = TRUE, junction_output = "sf")$junctions)))
  single <- axial_graph(matrix(c(0, 0, 1, 0), 1L))
  empty <- network_integration(single, junctions = TRUE, junction_output = "sf")$junctions
  expect_s3_class(empty, "sf"); expect_identical(nrow(empty), 0L)
  expect_identical(names(empty), c("junction_id", "integration", "geometry"))
  expect_identical(typeof(empty$junction_id), "integer"); expect_identical(typeof(empty$integration), "double")
  sf_single <- axial_graph(sb_lines(matrix(c(0, 0, 1, 0), 1L), 3857))
  expect_equal(sf::st_crs(network_integration(sf_single, junctions = TRUE, junction_output = "sf")$junctions), sf::st_crs(3857))
})

test_that("junction sf output is explicit and optional", {
  g <- axial_graph(cbind(0:2 * 3, 0, 1:3 * 3, 0))
  baseline <- network_integration(g, junctions = TRUE)
  expect_error(network_integration(g, junction_output = "sf"), "requires junctions = TRUE")
  expect_error(network_integration(g, junctions = TRUE, junction_output = "bad"))
  local_mocked_bindings(.pst_require_sf = function() stop("optional package 'sf' required"), .package = "rPSTool")
  expect_identical(network_integration(g, junctions = TRUE), baseline)
  expect_identical(network_integration(g), baseline$lines)
  expect_error(network_integration(g, junctions = TRUE, junction_output = "sf"), "optional package")
  expect_identical(network_integration(g, junctions = TRUE), baseline)
})
