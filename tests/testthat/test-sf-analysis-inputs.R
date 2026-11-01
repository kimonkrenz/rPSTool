sa_rows <- function(x, width = 2L) matrix(as.double(unlist(x)), ncol = width, byrow = TRUE)
sa_points <- function(x, crs = NA_integer_) sf::st_sfc(
  lapply(seq_len(nrow(x)), function(i) sf::st_point(x[i, ])), crs = crs)
sa_graph <- function(x) {
  args <- x[intersect(names(x), c("x", "line_indices", "unlinks", "points",
                                "points_per_polygon", "polygon_point_interval"))]
  args$x <- sa_rows(args$x, if (is.null(args$line_indices)) 4L else 2L)
  for (field in c("line_indices", "unlinks", "points"))
    if (!is.null(args[[field]])) args[[field]] <- sa_rows(args[[field]])
  if (!is.null(args$points_per_polygon)) args$points_per_polygon <- as.double(unlist(args$points_per_polygon))
  do.call(axial_graph, args)
}
sa_calls <- function(g) list(
  function(x) network_reach(g, origins = x),
  function(x) od_betweenness(g, x),
  function(x) attraction_reach(g, x),
  function(x) attraction_distance(g, x))

test_that("analysis matrices bypass optional sf availability and graph CRS checks", {
  g <- axial_graph(cbind(0:2, 0, 1:3, 0), points = rbind(c(1.5, .5)))
  p <- rbind(c(-.5, 0))
  calls <- sa_calls(g)
  baseline <- lapply(calls, function(fn) fn(p))
  # A matrix call must not inspect CRS or load sf, even with retained metadata.
  attr(g, "crs") <- structure(list(input = NA_character_, wkt = NA_character_), class = "crs")
  expect_s3_class(attr(g, "crs"), "crs")
  calls <- sa_calls(g) # Capture the CRS-bearing copy after R copy-on-modify.
  local_mocked_bindings(.pst_require_sf = function() stop("optional package 'sf' required"), .package = "rPSTool")
  for (i in seq_along(calls)) {
    expect_identical(calls[[i]](p), baseline[[i]])
    expect_error(calls[[i]](structure(list(), class = "sfc")), "optional package 'sf'")
  }
})

if (requireNamespace("sf", quietly = TRUE)) {
  test_that("supplied POINT origins match direct-PST Reach and OD scenarios exactly", {
    ref <- dget(test_path("fixtures", "reach-betweenness-direct-v3.3.2.R"))
    for (case in rpst_cases(Filter(function(x) x$routine == "reach", ref$cases), every = 5L, by = list(rpst_case_signature), each = list(rpst_case_edges))) {
      g <- axial_graph(sa_rows(ref$networks[[case$network]], 4L))
      p <- sa_rows(case$points)
      radius <- do.call(analysis_radius, case$radius)
      expect_identical(network_reach(g, radius, sa_points(p)), network_reach(g, radius, p))
    }
    ref <- dget(test_path("fixtures", "od-direct-v3.3.2.R"))
    graphs <- list()
    for (case in rpst_cases(od_supported_cases(ref$cases), every = 40L, by = list(rpst_case_signature), each = list(rpst_case_edges))) {
      name <- case$graph$name
      if (is.null(graphs[[name]])) graphs[[name]] <- sa_graph(case$graph)
      args <- case$args
      args$origins <- sa_rows(args$origins)
      args$radius <- do.call(analysis_radius, args$radius)
      for (field in c("origin_weights", "destination_weights"))
        if (!is.null(args[[field]])) args[[field]] <- as.double(unlist(args[[field]]))
      baseline <- do.call(od_betweenness, c(list(graph = graphs[[name]]), args))
      args$origins <- sa_points(args$origins)
      expect_identical(do.call(od_betweenness, c(list(graph = graphs[[name]]), args)), baseline)
    }
    g <- axial_graph(cbind(0:2, 0, 1:3, 0))
    p <- rbind(c(-.4999, 0), c(-.5, 0), c(-.5001, 0), c(.5, 2), c(2.5, 0))
    for (radius in list(analysis_radius(), analysis_radius(straight = 1), analysis_radius(walking = 0),
                        analysis_radius(steps = 1), analysis_radius(angular = 0), analysis_radius(axmeter = 2))) {
      for (order in list(seq_len(nrow(p)), c(5L, 3L, 1L, 4L, 2L)))
        expect_identical(network_reach(g, radius, sa_points(p[order, ])), network_reach(g, radius, p[order, ]))
    }
  })

  test_that("POINT attractions feed all existing direct fixture modes without attributes", {
    ref <- dget(test_path("fixtures", "attractions-direct-v3.3.2.R"))
    graphs <- list()
    for (case in rpst_cases(Filter(function(x) is.null(x$args$points_per_polygon), ref$cases), every = 40L, by = list(rpst_case_signature), each = list(rpst_case_edges))) {
      name <- case$graph$name
      if (is.null(graphs[[name]])) graphs[[name]] <- sa_graph(case$graph)
      args <- case$args
      args$attraction_points <- sa_rows(args$attraction_points)
      args$radius <- do.call(analysis_radius, args$radius)
      for (field in c("attraction_values", "line_weights"))
        if (!is.null(args[[field]])) args[[field]] <- as.double(unlist(args[[field]]))
      fn <- if (case$analysis == "reach") attraction_reach else attraction_distance
      baseline <- do.call(fn, c(list(graph = graphs[[name]]), args))
      args$attraction_points <- sf::st_sf(values = rep(999, nrow(args$attraction_points)),
                                         geometry = sa_points(args$attraction_points))
      expect_identical(do.call(fn, c(list(graph = graphs[[name]]), args)), baseline)
    }
  })

  test_that("POLYGON attractions reuse ordered closure/separator/group conversion", {
    # Pin summation order for exact equality; PST multi-worker float reductions
    # can differ by roundoff even between repeated identical matrix calls.
    old <- Sys.getenv("RPST_NUM_THREADS", unset = NA_character_)
    on.exit(if (is.na(old)) Sys.unsetenv("RPST_NUM_THREADS") else Sys.setenv(RPST_NUM_THREADS = old))
    Sys.setenv(RPST_NUM_THREADS = "1")
    x <- rbind(c(-1, 0, 6, 0), c(3, -3, 3, 6))
    g <- axial_graph(x, points = rbind(c(1, 0), c(4, 0)),
                   points_per_polygon = c(1, 1, 0), polygon_point_interval = 1)
    outer <- rbind(c(0, 0), c(5, 0), c(5, 5), c(0, 5), c(0, 0))
    hole <- rbind(c(1, 1), c(1, 2), c(2, 2), c(2, 1), c(1, 1))
    second <- outer + 10
    polygons <- sf::st_sfc(sf::st_polygon(list(outer, hole)), sf::st_polygon(list()),
                           sf::st_polygon(list(second)), crs = 3857)
    p <- rbind(outer[-5, ], c(NaN, NaN), hole[-5, ], second[-5, ])
    converted <- rPSTool:::.pst_sf_graph_points(polygons, NULL, "attraction_points")
    expect_identical(converted, list(points = p, counts = c(9, 0, 4)))
    for (origin in c("lines", "junctions", "points", "point_groups")) {
      for (distance in c("straight", "walking", "steps", "angular", "axmeter", "none")) {
        for (distribution in c("copy", "divide")) {
          args <- list(graph = g, origin = origin, distance = distance,
                       polygon_point_interval = .7, attraction_values = c(2, 9, 3),
                       distribution = distribution)
          expect_identical(do.call(attraction_reach, c(args, list(attraction_points = polygons))),
                           do.call(attraction_reach, c(args, list(attraction_points = p, points_per_polygon = c(9, 0, 4)))))
        }
      }
      for (distance in c("straight", "walking", "steps", "angular", "weights")) {
        if (origin == "point_groups" && distance == "straight") next
        for (indices in c(TRUE, FALSE)) {
          args <- list(graph = g, origin = origin, distance = distance, polygon_point_interval = .7,
                       destination_indices = indices, line_weights = if (distance == "weights") c(1, 2) else NULL)
          expect_identical(do.call(attraction_distance, c(args, list(attraction_points = polygons))),
                           do.call(attraction_distance, c(args, list(attraction_points = p, points_per_polygon = c(9, 0, 4)))))
        }
      }
    }
    saved <- list(attraction_reach(g, polygons, polygon_point_interval = .7),
                  attraction_distance(g, polygons, polygon_point_interval = .7))
    input <- sf::st_sf(value = c(999, 999, 999), geometry = polygons)
    result <- list(attraction_reach(g, input, polygon_point_interval = .7),
                   attraction_distance(g, input, polygon_point_interval = .7))
    input$geometry <- sa_points(rbind(c(999, 999), c(999, 999), c(999, 999)))
    rm(input); gc()
    expect_identical(result, saved)
    perm <- c(3L, 1L, 2L)
    reordered <- rbind(second[-5, ], outer[-5, ], c(NaN, NaN), hole[-5, ])
    expect_identical(attraction_reach(g, polygons[perm], polygon_point_interval = .7,
                                         attraction_values = c(2, 9, 3)[perm]),
                     attraction_reach(g, reordered, points_per_polygon = c(4, 9, 0),
                                         polygon_point_interval = .7, attraction_values = c(2, 9, 3)[perm]))
    expect_error(attraction_reach(g, polygons, polygon_point_interval = 1, attraction_values = 1), "weights must have exactly")
    for (fn in list(attraction_reach, attraction_distance)) {
      expect_error(fn(g, polygons, points_per_polygon = c(9, 0, 4)), "must be NULL")
      expect_error(fn(g, polygons), "interval")
      empty <- sf::st_sfc(sf::st_polygon(list()))
      expect_identical(fn(g, empty, polygon_point_interval = 1),
                       fn(g, matrix(numeric(), 0, 2), points_per_polygon = 0, polygon_point_interval = 1))
      empty_polygons <- sf::st_sfc()
      class(empty_polygons) <- c("sfc_POLYGON", "sfc")
      expect_error(fn(g, empty_polygons, polygon_point_interval = 1), "at least one POLYGON")
      # sf drops family metadata on a zero-feature mixed collection. It follows
      # the established empty POINT path, where a sampling interval is invalid.
      expect_error(fn(g, sf::st_sfc(), polygon_point_interval = 1), "requires points_per_polygon")
    }
  })

  test_that("analysis CRS checks graph metadata while mixed matrices keep their contract", {
    x <- cbind(0:2, 0, 1:3, 0)
    p <- rbind(c(0, 1), c(2, 0))
    for (crs in list(3857, 2263, NA_integer_)) {
      # Matrix network plus sf destinations also establishes graph CRS.
      g <- axial_graph(x, points = sa_points(p, crs))
      for (fn in sa_calls(g)) {
        expect_identical(fn(sa_points(p, crs)), fn(p))
        expect_identical(fn(sf::st_sf(weight = c(-999, 999), geometry = sa_points(p, crs))), fn(p))
        expect_error(fn(sa_points(p, 4326)), "Geographic")
        expect_error(fn(sa_points(p, 27700)), "compatible CRS")
        if (!is.na(crs)) expect_error(fn(sa_points(p)), "compatible CRS")
        else expect_error(fn(sa_points(p, 3857)), "compatible CRS")
      }
    }
    g <- axial_graph(x, points = p)
    for (fn in sa_calls(g)) {
      expect_identical(fn(sa_points(p, 3857)), fn(p))
      expect_identical(fn(sa_points(p)), fn(p))
      expect_error(fn(sa_points(p, 4326)), "Geographic")
    }
    ring <- rbind(c(0, 0), c(1, 0), c(1, 1), c(0, 0))
    g <- axial_graph(x, points = sa_points(p, 3857))
    for (fn in list(attraction_reach, attraction_distance)) {
      polygon <- sf::st_sfc(sf::st_polygon(list(ring)), crs = 3857)
      expect_identical(fn(g, polygon, polygon_point_interval = 1),
                       fn(g, ring[-4, ], points_per_polygon = 3, polygon_point_interval = 1))
      for (crs in list(4326, 27700, NA_integer_))
        expect_error(fn(g, sf::st_sfc(sf::st_polygon(list(ring)), crs = crs), polygon_point_interval = 1), "Geographic|compatible CRS")
    }
  })

  test_that("unsupported geometry and native validation fail without altering graphs", {
    g <- axial_graph(cbind(0:2, 0, 1:3, 0), points = rbind(c(1, 0)))
    ring <- rbind(c(0, 0), c(1, 0), c(1, 1), c(0, 0))
    wrong <- list(sf::st_point(), sf::st_point(c(0, 0, 1)), sf::st_point(c(0, 0, 1), dim = "XYM"),
                  sf::st_point(c(0, 0, 1, 2), dim = "XYZM"), sf::st_multipoint(rbind(c(0, 0))),
                  sf::st_linestring(ring), sf::st_multilinestring(list(ring)),
                  sf::st_multipolygon(list(list(ring))), sf::st_geometrycollection(list(sf::st_point(c(0, 0)))))
    for (fn in sa_calls(g)) {
      for (part in wrong) expect_error(fn(sf::st_sfc(part)), "XY|POINT|POLYGON|nonempty")
      expect_error(fn(sf::st_sfc(sf::st_point(c(0, 0)), sf::st_polygon(list(ring)))), "POINT|POLYGON")
      expect_error(fn(sa_points(rbind(c(1e30, 0)))), "overflow")
    }
    for (fn in list(attraction_reach, attraction_distance)) {
      for (part in list(sf::st_polygon(list(cbind(ring, 1))),
                        sf::st_polygon(list(cbind(ring, 1)), dim = "XYM"),
                        structure(list(ring[-4, ]), class = c("XY", "POLYGON", "sfg")),
                        structure(list(matrix(numeric(), 0, 2)), class = c("XY", "POLYGON", "sfg"))))
        expect_error(fn(g, sf::st_sfc(part), polygon_point_interval = 1), "XY|closed|empty rings")
    }
    empty <- sa_points(matrix(numeric(), 0, 2))
    expect_error(network_reach(g, origins = empty), "at least one row")
    for (fn in sa_calls(g)[-1]) expect_identical(fn(empty), fn(matrix(numeric(), 0, 2)))
    expect_error(od_betweenness(g, sa_points(rbind(c(0, 0))), origin_weights = c(1, 2)), "origin_weights")
    expect_error(attraction_reach(g, sa_points(rbind(c(0, 0))), attraction_values = c(1, 2)), "weights must have exactly")
  })

  test_that("Attraction Distance retains every mode exclusion with sf inputs", {
    g <- axial_graph(cbind(0:2, 0, 1:3, 0), points = rbind(c(1, 0)),
                   points_per_polygon = 1, polygon_point_interval = 1)
    ring <- rbind(c(0, 0), c(1, 0), c(1, 1), c(0, 0))
    for (input in list(sa_points(rbind(c(0, 0))), sf::st_sfc(sf::st_polygon(list(ring))))) {
      interval <- if (inherits(input, "sfc_POLYGON")) 1 else NULL
      for (radius in list(analysis_radius(), analysis_radius(straight = 0), analysis_radius(straight = 10)))
        for (indices in c(TRUE, FALSE))
          expect_error(attraction_distance(g, input, radius, origin = "point_groups", distance = "straight",
                                              polygon_point_interval = interval, destination_indices = indices), "outputs unwritten")
      for (field in c("walking", "steps", "angular", "axmeter")) {
        radius <- do.call(analysis_radius, setNames(list(1), field))
        expect_error(attraction_distance(g, input, radius, distance = "straight", polygon_point_interval = interval), "straight-only radius")
        # Non-straight radius must not broaden the point-group exclusion.
        expect_error(attraction_distance(g, input, radius, origin = "point_groups", distance = "straight",
                                            polygon_point_interval = interval), "straight-only radius")
      }
      expect_error(attraction_distance(g, input, analysis_radius(axmeter = 1), polygon_point_interval = interval), "axmeter radius")
      expect_error(attraction_distance(g, input, distance = "axmeter", polygon_point_interval = interval), "distance")
      expect_error(attraction_distance(g, input, distance = "weights", polygon_point_interval = interval), "line_weights")
      expect_error(attraction_distance(g, input, distance = "weights", line_weights = c(1, -1, 1),
                                          polygon_point_interval = interval), "non-negative")
      expect_error(attraction_distance(g, input, destination_indices = NA, polygon_point_interval = interval), "destination_indices")
      expect_error(attraction_distance(g, input, line_weights = 1:3, polygon_point_interval = interval), "line_weights")
      expect_error(attraction_distance(g, input, point_edge_weight = -1, polygon_point_interval = interval), "point_edge_weight")
    }
  })

  test_that("ordered explicit weights, integer coordinates and large frames survive input GC", {
    x <- cbind(0:2, 0, 1:3, 0)
    p <- rbind(c(0, 1), c(2, 0), c(1, 2))
    for (offset in c(0, 1e14)) {
      g <- axial_graph(x + offset, points = p + offset)
      for (fn in sa_calls(g)) expect_identical(fn(sa_points(p + offset)), fn(p + offset))
    }
    g <- axial_graph(x, points = p)
    storage.mode(p) <- "integer"
    for (fn in sa_calls(g)) expect_identical(fn(sa_points(p)), fn(p))
    order <- c(3L, 1L, 2L)
    expect_identical(rPSTool:::.pst_sf_points(sa_points(p[order, ]), "origins"), p[order, ] * 1.0)
    layer <- sf::st_sf(weight = c(999, 0, -999), id = letters[1:3], geometry = sa_points(p[order, ]))
    ow <- c(2, 0, 3)[order]
    av <- c(2, -1, 3)[order]
    results <- list(network_reach(g, origins = layer), od_betweenness(g, layer, origin_weights = ow),
                    attraction_reach(g, layer, attraction_values = av), attraction_distance(g, layer))
    baseline <- list(network_reach(g, origins = p[order, ]), od_betweenness(g, p[order, ], origin_weights = ow),
                     attraction_reach(g, p[order, ], attraction_values = av), attraction_distance(g, p[order, ]))
    expect_identical(results, baseline)
    graph_names <- names(g)
    layer$geometry <- sa_points(p + 1000); ow[] <- -999; av[] <- 0
    rm(layer, ow, av); gc()
    expect_identical(results, baseline)
    expect_identical(names(g), graph_names)
    for (fn in sa_calls(g)) expect_identical(fn(sa_points(p)), fn(p))
    .Call(rPSTool:::C_rpst_graph_release, g$ptr)
    expect_identical(results, baseline)
    for (fn in sa_calls(g)) expect_error(fn(sa_points(p)), "live|released")
  })
}
