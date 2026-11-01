sf_lines <- function(x, crs = NA_integer_) {
  sf::st_sfc(lapply(seq_len(nrow(x)), function(i)
    sf::st_linestring(matrix(x[i, ], ncol = 2L, byrow = TRUE))), crs = crs)
}
sf_points <- function(x, crs = NA_integer_) {
  sf::st_sfc(lapply(seq_len(nrow(x)), function(i) sf::st_point(x[i, ])), crs = crs)
}
sf_state <- function(g) .Call(rPSTool:::C_rpst_graph_point_state, g$ptr)

# Keep native/matrix tests executable even when the suggested adapter is absent.
test_that("matrix paths do not require or load sf", {
  expect_identical(names(axial_graph(matrix(c(0, 0, 1, 0), 1L))),
                   c("ptr", "type", "n_lines", "n_crossings", "n_points", "n_point_groups", "pst_version"))
  expect_null(attr(axial_graph(matrix(c(0, 0, 1, 0), 1L)), "crs"))
  expect_null(attr(segment_graph(matrix(c(0, 0, 1, 0), 1L)), "crs"))
  # Exercise the real runtime guard without requiring an uninstalled package.
  local_mocked_bindings(.pst_require_sf = function() stop("The optional package 'sf' is required for sf geometry adapters."), .package = "rPSTool")
  expect_s3_class(axial_graph(matrix(c(0, 0, 1, 0), 1L)), "pst_graph")
  expect_s3_class(segment_graph(matrix(c(0, 0, 1, 0), 1L)), "pst_segment_graph")
  fake <- structure(list(), class = "sfc")
  expect_error(axial_graph(fake), "optional package 'sf'")
  expect_error(axial_crossing_coords(axial_graph(matrix(c(0, 0, 1, 0), 1L)), "sf"), "optional package 'sf'")
})

if (requireNamespace("sf", quietly = TRUE)) {
  test_that("sf lines feed exactly the same native graph families in feature order", {
    for (storage in c("integer", "double")) for (offset in c(0, 1e9)) {
      x <- rbind(c(3, 0, 0, 0), c(3, 0, 3, 3), c(1, -1, 1, 1)) + offset
      storage.mode(x) <- storage
      lines <- sf_lines(x, 3857)
      layer <- sf::st_sf(weight = c(99, -1, 0), id = c("z", "x", "y"), geometry = lines)
      for (input in list(lines, layer)) {
        g <- axial_graph(input)
        m <- axial_graph(x)
        expect_identical(axial_line_lengths(g), axial_line_lengths(m))
        expect_identical(axial_crossing_coords(g), axial_crossing_coords(m))
        expect_identical(network_integration(g), network_integration(m))
        expect_identical(network_reach(g), network_reach(m))
        expect_identical(network_betweenness(g), network_betweenness(m))
        expect_identical(attr(g, "crs"), sf::st_crs(lines))
        s <- segment_graph(input)
        sm <- segment_graph(x)
        expect_identical(angular_integration(s), angular_integration(sm))
        expect_identical(angular_choice(s), angular_choice(sm))
        expect_identical(names(g), names(m))
        expect_identical(names(s), names(sm))
      }
    }
  })

  test_that("POINT indexed coordinates, graph points and unlinks preserve native order", {
    coords <- rbind(c(1, -1), c(0, 0), c(1, 1), c(2, 0), c(5, 5))
    indices <- rbind(c(2, 4), c(3, 1))
    points <- rbind(c(1.5, 0.1), c(0.5, 0.1))
    unlinks <- matrix(c(1, 0), 1L)
    a <- axial_graph(sf_points(coords, 3857), indices, sf_points(unlinks, 3857), sf_points(points, 3857))
    b <- axial_graph(coords, indices, unlinks, points)
    expect_identical(sf_state(a), sf_state(b))
    expect_identical(axial_crossing_coords(a), axial_crossing_coords(b))
    expect_identical(network_integration(a, junctions = TRUE), network_integration(b, junctions = TRUE))
    expect_identical(axial_line_lengths(a), axial_line_lengths(b))
    expect_identical(sf_state(axial_graph(coords, indices, points = sf_points(points, 3857))),
                     sf_state(axial_graph(coords, indices, points = points)))
  })

  test_that("POLYGON closure, holes, feature groups and empty groups map exactly", {
    x <- rbind(c(-1, 0, 6, 0), c(3, -3, 3, 6))
    outer <- rbind(c(0, 0), c(5, 0), c(5, 5), c(0, 5), c(0, 0))
    hole <- rbind(c(1, 1), c(1, 2), c(2, 2), c(2, 1), c(1, 1))
    second <- outer + 10
    polygons <- sf::st_sfc(sf::st_polygon(list(outer, hole)), sf::st_polygon(list()),
                           sf::st_polygon(list(second)), crs = 3857)
    canonical <- rbind(outer[-5, ], c(NaN, NaN), hole[-5, ], second[-5, ])
    g <- axial_graph(sf_lines(x, 3857), points = polygons, polygon_point_interval = .7)
    m <- axial_graph(x, points = canonical, points_per_polygon = c(9, 0, 4), polygon_point_interval = .7)
    expect_identical(sf_state(g), sf_state(m))
    expect_identical(g$n_point_groups, 3L)
    expect_identical(attraction_reach(g, matrix(c(1, 0), 1), origin = "point_groups"),
                     attraction_reach(m, matrix(c(1, 0), 1), origin = "point_groups"))
    expect_error(axial_graph(x, points = polygons, points_per_polygon = c(9, 0, 4), polygon_point_interval = 1), "must be NULL")
    expect_error(axial_graph(x, points = polygons), "interval")
    expect_error(axial_graph(x, points = sf::st_sfc(sf::st_multipolygon(list(list(outer))))), "POLYGON")
    expect_error(axial_graph(x, points = sf::st_sfc(structure(list(matrix(numeric(), 0, 2)), class = c("XY", "POLYGON", "sfg")))), "empty rings")
    expect_error(axial_graph(x, points = sf::st_sfc(structure(list(outer[-5, ]), class = c("XY", "POLYGON", "sfg")))), "closed")
  })

  test_that("CRS is checked without reprojection, assignment or unit conversion", {
    x <- matrix(c(0, 0, 3, 0), 1)
    p <- matrix(c(1, 1), 1)
    expect_error(axial_graph(sf_lines(x, 4326)), "Geographic")
    expect_error(segment_graph(sf_lines(x, 4326)), "Geographic")
    expect_error(axial_graph(x, points = sf_points(p, 4326)), "Geographic")
    expect_error(axial_graph(sf_lines(x, 3857), points = sf_points(p, 27700)), "compatible CRS")
    expect_error(axial_graph(sf_lines(x, 3857), unlinks = sf_points(p)), "compatible CRS")
    expect_error(axial_graph(sf_lines(x), points = sf_points(p, 3857)), "compatible CRS")
    expect_true(is.na(attr(axial_graph(sf_lines(x)), "crs")))
    expect_identical(axial_line_lengths(axial_graph(sf_lines(x, 2263))), axial_line_lengths(axial_graph(x)))
    expect_identical(attr(axial_graph(x, points = sf_points(p, 3857)), "crs"), sf::st_crs(3857))
    expect_identical(axial_line_lengths(axial_graph(sf_lines(x, 3857), points = p)), 3)
  })

  test_that("unsupported geometry cannot silently lose vertices, parts or dimensions", {
    x <- matrix(c(0, 0, 3, 0), 1)
    wrong <- list(sf::st_linestring(matrix(c(0, 0, 1, 1, 2, 0), 3, 2, byrow = TRUE)),
                  sf::st_linestring(matrix(numeric(), 0, 2)),
                  sf::st_multilinestring(list(matrix(x, 2, 2, byrow = TRUE))),
                  sf::st_point(c(0, 0)), sf::st_geometrycollection(list(sf::st_point(c(0, 0)))),
                  sf::st_linestring(matrix(c(0, 0, 1, 2, 0, 1), 2, 3, byrow = TRUE)),
                  sf::st_linestring(matrix(c(0, 0, 1, 2, 0, 1), 2, 3, byrow = TRUE), dim = "XYM"),
                  sf::st_linestring(matrix(0, 2, 4), dim = "XYZM"))
    for (part in wrong) for (create in list(axial_graph, segment_graph))
      expect_error(create(sf::st_sfc(part)), "two finite|LINESTRING|XY")
    mixed <- sf::st_sfc(sf::st_linestring(matrix(x, 2, 2, byrow = TRUE)), sf::st_point(c(0, 0)))
    expect_error(axial_graph(mixed), "LINESTRING")
    for (part in list(sf::st_point(), sf::st_point(c(0, 0, 1)), sf::st_multipoint(matrix(c(0, 0), 1))))
      expect_error(axial_graph(x, points = sf::st_sfc(part)), "nonempty|XY|POLYGON")
    expect_error(axial_graph(sf_lines(matrix(numeric(), 0, 4))), "row|line|coordinate", ignore.case = TRUE)
    expect_identical(sf_state(axial_graph(x, points = sf_points(matrix(numeric(), 0, 2))))[[1]],
                     sf_state(axial_graph(x))[[1]])
  })

  test_that("sf output uses only native crossing coordinates and survives graph/input GC", {
    x <- rbind(c(0, 0, 2, 0), c(1, -1, 1, 1))
    input <- sf::st_sf(weight = c(10, 20), geometry = sf_lines(x, 3857))
    g <- axial_graph(input)
    baseline <- network_integration(g)
    native <- axial_crossing_coords(g)
    result <- axial_crossing_coords(g, output = "sf")
    expect_identical(result$crossing_id, seq_len(nrow(native)))
    expect_identical(unname(sf::st_coordinates(result)[, 1:2, drop = FALSE]), unname(native))
    expect_identical(sf::st_crs(result), sf::st_crs(3857))
    input$geometry <- sf_lines(x + 1000, 27700)
    rm(input); gc()
    expect_identical(network_integration(g), baseline)
    expect_identical(axial_crossing_coords(g), native)
    for (i in 1:3) expect_identical(network_integration(g), baseline)
    .Call(rPSTool:::C_rpst_graph_release, g$ptr)
    expect_identical(unname(sf::st_coordinates(result)[, 1:2, drop = FALSE]), unname(native))
    expect_error(axial_crossing_coords(g, "sf"), "released|live|invalid", ignore.case = TRUE)
    empty <- axial_crossing_coords(axial_graph(matrix(c(0, 0, 1, 0), 1)), "sf")
    expect_s3_class(empty, "sf")
    expect_identical(nrow(empty), 0L)
    expect_true(is.na(sf::st_crs(empty)))
  })
}
