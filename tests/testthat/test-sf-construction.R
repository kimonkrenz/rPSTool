sc_points <- function(x, crs = NA_integer_) sf::st_sfc(
  lapply(seq_len(nrow(x)), function(i) sf::st_point(unname(x[i, ]))), crs = crs)
sc_lines <- function(x, crs = NA_integer_) sf::st_sfc(
  lapply(seq_len(nrow(x)), function(i) sf::st_linestring(matrix(x[i, ], 2L, 2L, byrow = TRUE))), crs = crs)
sc_args <- function(case) {
  args <- case$args
  for (field in intersect(names(args), c("x", "y", "coords", "unlinks", "line_indices", "line_indices_y"))) {
    width <- if ((field == "x" && is.null(args$line_indices)) ||
                 (field == "y" && is.null(args$line_indices_y))) 4L else 2L
    args[[field]] <- matrix(as.double(unlist(args[[field]])), ncol = width, byrow = TRUE)
  }
  if (!is.null(args$sections)) args$sections <- as.double(unlist(args$sections))
  args
}
# Invert the fixture's native sections, retaining ordered source groups. A final
# negative section has no following object: finalize that same source in sf.
sc_features <- function(coords, sections) {
  features <- list(); parts <- list(); offset <- 0L
  for (i in seq_along(sections)) {
    n <- if (sections[[i]] < 0) -sections[[i]] - 1 else sections[[i]]
    part <- coords[offset + seq_len(n), , drop = FALSE]
    parts[[length(parts) + 1L]] <- part
    offset <- offset + n
    if (sections[[i]] >= 0 || i == length(sections)) {
      features[[length(features) + 1L]] <- if (length(parts) == 1L)
        sf::st_linestring(parts[[1L]]) else sf::st_multilinestring(parts)
      parts <- list()
    }
  }
  sf::st_sfc(features)
}
sc_point_rows <- function(x) {
  if (!nrow(x)) return(matrix(numeric(), 0L, 2L))
  do.call(rbind, lapply(sf::st_geometry(x), as.numeric))
}
sc_line_rows <- function(x) {
  if (!nrow(x)) return(matrix(numeric(), 0L, 4L))
  do.call(rbind, lapply(sf::st_geometry(x), function(p) as.vector(t(p))))
}

test_that("matrix construction bypasses sf, including unavailable adapter failures", {
  x <- rbind(c(-10, 0, 10, 0), c(0, -10, 0, 10))
  xy <- rbind(c(0, 0), c(10, 0))
  j <- create_junctions(x)
  m <- create_segment_map(xy, 2, snap = 0, tail = 0)
  local_mocked_bindings(.pst_require_sf = function() stop("optional package 'sf' required"), .package = "rPSTool")
  expect_identical(create_junctions(x), j)
  expect_identical(create_segment_map(xy, 2, snap = 0, tail = 0), m)
  for (output in "sf") {
    expect_error(create_junctions(x, output = output), "optional package 'sf'")
    expect_error(create_segment_map(xy, 2, output = output), "optional package 'sf'")
  }
  fake <- structure(list(), class = "sfc")
  expect_error(create_junctions(fake), "optional package 'sf'")
  expect_error(create_segment_map(fake), "optional package 'sf'")
  expect_error(create_junctions(x, unlinks = fake), "optional package 'sf'")
  expect_error(create_segment_map(xy, 2, unlinks = fake), "optional package 'sf'")
})

if (requireNamespace("sf", quietly = TRUE)) {
  test_that("the direct construction fixtures agree exactly through sf (all 124 in the full suite)", {
    ref <- dget(test_path("fixtures", "network-construction-direct-v3.3.2.R"))
    # CRAN mode: a deterministic subset containing every fixture kind, argument signature and edge value; full mode visits all 124.
    for (case in rpst_cases(ref$cases, every = 5L, by = list(rpst_case_signature, function(x) x$kind), each = list(rpst_case_edges))) {
      args <- sc_args(case)
      fn <- if (case$kind == "junctions") create_junctions else create_segment_map
      baseline <- do.call(fn, args)
      if (case$kind == "junctions") {
        args$x <- if (is.null(args$line_indices)) sc_lines(args$x) else sc_points(args$x)
        if (!is.null(args$y)) args$y <- if (is.null(args$line_indices_y)) sc_lines(args$y) else sc_points(args$y)
      } else {
        coords <- args$coords; sections <- args$sections
        args$coords <- sc_features(coords, sections); args$sections <- NULL
        converted <- rPSTool:::.pst_sf_sections(args$coords, NULL)
        expected <- sections
        if (tail(expected, 1L) < 0) expected[length(expected)] <- -tail(expected, 1L) - 1
        expect_identical(converted$coords, coords, info = case$name)
        expect_identical(converted$sections, expected, info = case$name)
      }
      if (!is.null(args$unlinks)) args$unlinks <- sc_points(args$unlinks)
      expect_identical(do.call(fn, args), baseline, info = case$name)
      spatial <- do.call(fn, c(args, list(output = "sf")))
      if (case$kind == "junctions") {
        expect_identical(names(spatial), c("junction_id", "geometry"))
        expect_identical(spatial$junction_id, seq_len(nrow(baseline)))
        expect_identical(sc_point_rows(spatial), unname(baseline), info = case$name)
      } else {
        expect_identical(names(spatial), names(baseline))
        expect_identical(names(spatial$segments), c("source_id", "geometry"))
        expect_identical(names(spatial$unlinks), "geometry")
        expect_identical(spatial$source_id, baseline$source_id)
        expect_identical(spatial$segments$source_id, baseline$source_id)
        expect_identical(sc_line_rows(spatial$segments), unname(baseline$segments), info = case$name)
        expect_identical(sc_point_rows(spatial$unlinks), unname(baseline$unlinks), info = case$name)
      }
    }
  })

  test_that("multipart parts, empty objects and singleton sections keep order and source IDs", {
    empty <- matrix(numeric(), 0L, 2L)
    a <- rbind(c(0, 0), c(10, 0), c(10, 5))
    b <- rbind(c(50, 0), c(60, 0))
    singleton <- rbind(c(100, 100))
    geometry <- sf::st_sfc(sf::st_linestring(empty), sf::st_multilinestring(list()),
      sf::st_multilinestring(list(empty, a, singleton, b, empty)),
      sf::st_linestring(singleton), sf::st_linestring(b + 100))
    expected <- list(coords = rbind(a, singleton, b, singleton, b + 100),
                     sections = c(0, 0, -1, -4, -2, -3, 0, 1, 2))
    expect_identical(rPSTool:::.pst_sf_sections(geometry, NULL), expected)
    args <- list(snap = 0, tail = 0, deviation = 0)
    actual <- do.call(create_segment_map, c(list(coords = geometry), args))
    baseline <- do.call(create_segment_map, c(expected, args))
    expect_identical(actual, baseline)
    expect_identical(actual$source_id, c(3L, 3L, 3L, 5L))
    expect_identical(unname(actual$segments), rbind(c(0, 0, 10, 0), c(10, 0, 10, 5),
                                                   c(50, 0, 60, 0), c(150, 100, 160, 100)))
    perm <- c(5L, 3L, 1L, 4L, 2L)
    converted <- rPSTool:::.pst_sf_sections(geometry[perm], NULL)
    expect_identical(do.call(create_segment_map, c(list(coords = geometry[perm]), args)),
                     do.call(create_segment_map, c(converted, args)))
    expect_error(create_segment_map(geometry, sections = expected$sections), "must be NULL")
    expect_error(create_segment_map(sf::st_sfc(sf::st_linestring(empty), sf::st_linestring(singleton))), "edge|sections")
    expect_error(create_segment_map(sf::st_sfc()), "sections|edge")
    expect_error(create_segment_map(a), "sections")
  })

  test_that("empty junction and native cycle guards remain unchanged", {
    empty <- sf::st_sfc()
    cross <- sc_lines(rbind(c(-10, 0, 10, 0), c(0, -10, 0, 10)))
    expect_error(create_junctions(empty), "Empty first junction layer")
    expect_error(create_junctions(sc_points(rbind(c(0, 0))), matrix(integer(), 0, 2)), "Empty first junction layer")
    expect_identical(dim(create_junctions(cross, y = empty)), c(0L, 2L))
    for (x in list(cross[1], cross)) {
      out <- create_junctions(x, y = empty, output = "sf")
      expect_identical(nrow(out), 0L)
      expect_identical(out$junction_id, integer())
    }
    square <- rbind(c(0, 0), c(1, 0), c(1, 1), c(0, 1), c(0, 0))
    for (coords in list(square, rbind(c(0, 0), c(1, 0), c(2, 0), c(0, 0)),
                        rbind(c(0, 0), c(10, 0), c(10, 10), c(0, 10), c(0, .1)))) {
      snap <- if (nrow(coords) == 5 && coords[nrow(coords), 2] == .1) .2 else 0
      deviation <- if (snap > 0) 20 else if (nrow(coords) == 4) 0 else 1
      for (output in c("native", "sf"))
        expect_error(create_segment_map(sf::st_sfc(sf::st_linestring(coords)),
                     snap = snap, tail = 0, deviation = deviation, output = output), "PSTACreateSegmentMap failed")
    }
    for (scale in c(1, 10)) {
      xy <- square * scale
      expect_identical(create_segment_map(sf::st_sfc(sf::st_linestring(xy)), snap = 0, tail = 0, deviation = if (scale == 1) 0 else 1),
                       create_segment_map(xy, 5, snap = 0, tail = 0, deviation = if (scale == 1) 0 else 1))
    }
    expect_identical(.Call(rPSTool:::C_rpst_construction_lifecycle)[[3L]], 0)
  })

  test_that("construction CRS is derived solely from compatible sf metadata", {
    x <- rbind(c(-10, 0, 10, 0), c(0, -10, 0, 10))
    coords <- rbind(c(0, 0), c(10, 0))
    p <- matrix(numeric(), 0, 2)
    for (crs in list(3857, 2263, NA_integer_)) {
      lines <- sc_lines(x, crs); points <- sc_points(p, crs)
      j <- create_junctions(lines, unlinks = points, output = "sf")
      m <- create_segment_map(sf::st_sfc(sf::st_linestring(coords), crs = crs), unlinks = points, output = "sf")
      for (out in list(j, m$segments, m$unlinks)) expect_identical(sf::st_crs(out), sf::st_crs(lines))
      expect_identical(create_junctions(lines), create_junctions(x))
      expect_identical(create_segment_map(sf::st_sfc(sf::st_linestring(coords), crs = crs)), create_segment_map(coords, 2))
      for (other in list(4326, 27700, if (is.na(crs)) 3857 else NA_integer_)) {
        expect_error(create_junctions(lines, y = sc_lines(x, other)), "Geographic|compatible CRS")
        expect_error(create_junctions(lines, unlinks = sc_points(p, other)), "Geographic|compatible CRS")
        expect_error(create_segment_map(sf::st_sfc(sf::st_linestring(coords), crs = crs), unlinks = sc_points(p, other)), "Geographic|compatible CRS")
      }
      # Metadata can come from either layer or even an explicit empty unlink.
      expect_identical(sf::st_crs(create_junctions(x, y = lines, output = "sf")), sf::st_crs(lines))
      expect_identical(sf::st_crs(create_junctions(x, unlinks = points, output = "sf")), sf::st_crs(lines))
      mixed <- create_segment_map(coords, 2, unlinks = points, output = "sf")
      expect_identical(sf::st_crs(mixed$segments), sf::st_crs(lines))
    }
    expect_error(create_junctions(sc_lines(x, 4326)), "Geographic")
    expect_error(create_segment_map(sf::st_sfc(sf::st_linestring(coords), crs = 4326)), "Geographic")
    expect_true(is.na(sf::st_crs(create_junctions(x, output = "sf"))))
    m <- create_segment_map(coords, 2, output = "sf")
    expect_true(is.na(sf::st_crs(m$segments)))
    expect_true(is.na(sf::st_crs(m$unlinks)))
  })

  test_that("unsupported families, dimensions and invalid parts fail explicitly", {
    xy <- rbind(c(0, 0), c(10, 0)); ring <- rbind(xy, c(10, 10), c(0, 0))
    wrong <- list(sf::st_point(c(0, 0)), sf::st_multipoint(xy), sf::st_polygon(list(ring)),
                  sf::st_multipolygon(list(list(ring))), sf::st_geometrycollection(list(sf::st_linestring(xy))),
                  sf::st_linestring(cbind(xy, 1)), sf::st_linestring(cbind(xy, 1), dim = "XYM"),
                  sf::st_multilinestring(list(cbind(xy, 1, 2)), dim = "XYZM"))
    for (part in wrong) expect_error(create_segment_map(sf::st_sfc(part)), "XY|LINESTRING")
    for (part in list(sf::st_linestring(ring), sf::st_multilinestring(list(xy)), sf::st_linestring(matrix(numeric(), 0, 2))))
      expect_error(create_junctions(sf::st_sfc(part)), "two finite|LINESTRING")
    for (part in list(sf::st_point(), sf::st_point(c(0, 0, 1)), sf::st_multipoint(xy))) {
      p <- sf::st_sfc(part)
      expect_error(create_junctions(sc_lines(matrix(c(0, 0, 10, 0), 1)), unlinks = p), "XY|POINT|nonempty")
      expect_error(create_segment_map(sf::st_sfc(sf::st_linestring(xy)), unlinks = p), "XY|POINT|nonempty")
    }
    invalid <- xy; invalid[1, 1] <- Inf
    expect_error(create_segment_map(sf::st_sfc(sf::st_multilinestring(list(xy, invalid)))), "finite")
    expect_error(create_segment_map(sf::st_sfc(sf::st_linestring(xy)), network_type = "road_center_lines", unlinks = sc_points(xy)), "unlinks")
    expect_identical(create_segment_map(sf::st_sfc(sf::st_linestring(xy)), network_type = "road_center_lines", unlinks = sc_points(matrix(numeric(), 0, 2))),
                     create_segment_map(xy, 2, network_type = "road_center_lines", unlinks = matrix(numeric(), 0, 2)))
  })

  test_that("sf results ignore input attributes and survive mutation and GC", {
    x <- rbind(c(-10, 0, 10, 0), c(0, -10, 0, 10))
    input <- sf::st_sf(source_id = c(999, -1), arbitrary = c("a", "b"), geometry = sc_lines(x, 3857))
    junctions <- create_junctions(input, output = "sf")
    segments <- create_segment_map(input, snap = 0, tail = 0, output = "sf")
    saved <- unserialize(serialize(list(junctions, segments), NULL))
    input$geometry <- sc_lines(x + 999); input$source_id[] <- 0
    rm(input); gc()
    expect_identical(list(junctions, segments), saved)
    expect_identical(names(junctions), c("junction_id", "geometry"))
    expect_identical(names(segments$segments), c("source_id", "geometry"))
    expect_identical(sc_point_rows(junctions), unname(create_junctions(x)))
    baseline <- create_segment_map(t(matrix(t(x), 2L)), c(2, 2), snap = 0, tail = 0)
    expect_identical(sc_line_rows(segments$segments), unname(baseline$segments))
    expect_identical(segments$source_id, baseline$source_id)
  })
}
