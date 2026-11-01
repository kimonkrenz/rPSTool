iso_rect <- function(x, y, size) rbind(c(x, y), c(x, y + size), c(x + size, y + size), c(x + size, y))
iso_close <- function(m) rbind(m, m[1L, ])
iso_poly <- function(...) sf::st_polygon(lapply(list(...), iso_close))
iso_layer <- function(..., crs = NA_integer_) sf::st_sfc(..., crs = crs)
iso_pts <- function(m, crs = NA_integer_)
  sf::st_sfc(lapply(seq_len(nrow(m)), function(i) sf::st_point(m[i, ])), crs = crs)
iso_empty <- matrix(numeric(), 0L, 2L)

iso_matrix_args <- function() list(
  obstacles = list(list(iso_rect(2, -1, 2)), list(), list(iso_rect(-4, 1, 1))),
  attraction_points = list(rbind(c(1, 0), c(5, 0), c(-1, 0)), iso_empty, rbind(c(0, 2), c(20, 20))),
  attraction_polygons = list(list(iso_rect(0, 3, 1)), list(), list(iso_rect(-2, -2, 1))))
iso_sf_args <- function(crs = NA_integer_) list(
  obstacles = list(iso_layer(iso_poly(iso_rect(2, -1, 2)), crs = crs), iso_layer(crs = crs),
                   iso_layer(iso_poly(iso_rect(-4, 1, 1)), crs = crs)),
  attraction_points = list(iso_pts(rbind(c(1, 0), c(5, 0), c(-1, 0)), crs), iso_pts(iso_empty, crs),
                           iso_pts(rbind(c(0, 2), c(20, 20)), crs)),
  attraction_polygons = list(iso_layer(iso_poly(iso_rect(0, 3, 1)), crs = crs), iso_layer(crs = crs),
                             iso_layer(iso_poly(iso_rect(-2, -2, 1)), crs = crs)))

test_that("sf isovist contexts match the matrix API exactly", {
  skip_if_not_installed("sf")
  m <- do.call(isovist_context, iso_matrix_args())
  s <- do.call(isovist_context, iso_sf_args())
  for (view in list(c(360, 0), c(90, 30), c(200, 300))) for (o in list(c(0, 0), c(.3, .1)))
    expect_identical(isovist(s, o, 10, view[1], view[2]), isovist(m, o, 10, view[1], view[2]))
  # Repeated use and independent output lifetime.
  out <- isovist(s, c(0, 0), 10)
  isovist_context_free(s); isovist_context_free(m); invisible(gc())
  expect_error(isovist(s, c(0, 0), 10))
  expect_identical(out$area, isovist(do.call(isovist_context, iso_matrix_args()), c(0, 0), 10)$area)
})

test_that("a structural sf closure is equivalent to the open ring and to a repeated vertex", {
  skip_if_not_installed("sf")
  open <- isovist_context(obstacles = list(list(iso_rect(2, -1, 2))))
  rep <- isovist_context(obstacles = list(list(iso_close(iso_rect(2, -1, 2)))))
  sfc <- isovist_context(obstacles = list(iso_layer(iso_poly(iso_rect(2, -1, 2)))))
  for (o in list(c(0, 0), c(3, 0), c(.5, 2))) for (v in list(c(360, 0), c(90, 30)))
    for (ctx in list(rep, sfc))
      expect_identical(isovist(ctx, o, 10, v[1], v[2]), isovist(open, o, 10, v[1], v[2]))
})

test_that("winding is never rewound and sf attributes/order are respected", {
  skip_if_not_installed("sf")
  ccw <- iso_rect(2, -1, 2)[4:1, ]
  m <- isovist_context(obstacles = list(list(ccw)))
  s <- isovist_context(obstacles = list(iso_layer(iso_poly(ccw))))
  expect_identical(isovist(s, c(0, 0), 10), isovist(m, c(0, 0), 10))
  d <- sf::st_sf(w = 5, geometry = iso_layer(iso_poly(iso_rect(2, -1, 2))))
  expect_identical(isovist(isovist_context(obstacles = list(d)), c(0, 0), 10),
                   isovist(isovist_context(obstacles = list(list(iso_rect(2, -1, 2)))), c(0, 0), 10))
})

test_that("mixed matrix and sf groups and matrix-only contexts keep their fields", {
  skip_if_not_installed("sf")
  mixed <- isovist_context(obstacles = list(list(iso_rect(2, -1, 2)), iso_layer(iso_poly(iso_rect(-4, 1, 1)))))
  expect_true(is.na(sf::st_crs(attr(mixed, "crs"))))
  expect_null(attr(isovist_context(obstacles = list(list(iso_rect(2, -1, 2)))), "crs"))
  expect_identical(names(mixed), c("ptr", "pst_version"))
  expect_identical(isovist(mixed, c(0, 0), 10)$visible_obstacles,
                   isovist(isovist_context(obstacles = list(list(iso_rect(2, -1, 2)), list(iso_rect(-4, 1, 1)))), c(0, 0), 10)$visible_obstacles)
  ctx <- isovist_context(obstacles = list(iso_layer(iso_poly(iso_rect(2, -1, 2)), crs = 3857)))
  expect_identical(names(ctx), c("ptr", "pst_version"))
  expect_equal(sf::st_crs(attr(ctx, "crs")), sf::st_crs(3857))
})

test_that("unsupported sf isovist geometry and CRS are rejected before native state", {
  skip_if_not_installed("sf")
  ring <- iso_rect(2, -1, 2)
  hole <- sf::st_polygon(list(iso_close(iso_rect(0, 0, 10)), iso_close(iso_rect(1, 1, 2))))
  expect_error(isovist_context(obstacles = list(iso_layer(hole))), "exactly one ring")
  expect_error(isovist_context(attraction_polygons = list(iso_layer(hole))), "exactly one ring")
  expect_error(isovist_context(obstacles = list(iso_layer(sf::st_polygon()))), "exactly one ring")
  expect_error(isovist_context(obstacles = list(iso_layer(sf::st_multipolygon(list(list(iso_close(ring))))))), "POLYGON")
  expect_error(isovist_context(obstacles = list(iso_layer(sf::st_polygon(list(ring))))), "closed")
  expect_error(isovist_context(obstacles = list(iso_layer(sf::st_polygon(list(cbind(iso_close(ring), 0)))))), "XY")
  expect_error(isovist_context(obstacles = list(iso_layer(sf::st_polygon(list(iso_close(rbind(c(Inf, 0), ring[-1, ]))))))), "finite")
  expect_error(isovist_context(attraction_points = list(iso_layer(sf::st_multipoint(ring)))), "POINT")
  expect_error(isovist_context(attraction_points = list(iso_layer(iso_poly(ring)))), "POINT")
  expect_error(isovist_context(obstacles = iso_layer(iso_poly(ring))), "list of groups")
  expect_error(isovist_context(obstacles = list(iso_layer(iso_poly(ring), crs = 4326))), "Geographic")
  expect_error(isovist_context(obstacles = list(iso_layer(iso_poly(ring), crs = 3857)),
                                   attraction_points = list(iso_pts(rbind(c(0, 0)), 3395))), "compatible")
  expect_error(isovist_context(obstacles = list(iso_layer(iso_poly(ring), crs = 3857)),
                                   attraction_polygons = list(iso_layer(iso_poly(ring)))), "compatible")
  # A failed conversion leaves no state; a good context still works afterwards.
  ctx <- isovist_context(obstacles = list(iso_layer(iso_poly(ring))))
  expect_gt(isovist(ctx, c(0, 0), 10)$area, 0)
})

test_that("sf isovist output closes exactly once and keeps native polygon authority", {
  skip_if_not_installed("sf")
  ctx <- isovist_context(obstacles = list(iso_layer(iso_poly(iso_rect(2, -1, 2)), crs = 3857)))
  native <- isovist(ctx, c(0, 0), 10, 360, 0, 16)
  out <- isovist(ctx, c(0, 0), 10, 360, 0, 16, output = "sf")
  expect_s3_class(out$polygon, "sfc_POLYGON")
  expect_length(out$polygon, 1L)
  expect_equal(sf::st_crs(out$polygon), sf::st_crs(3857))
  ring <- unclass(out$polygon[[1L]])[[1L]]
  n <- nrow(native$polygon)
  expect_identical(unname(ring[seq_len(n), ]), unname(native$polygon))
  expect_identical(unname(ring[n + 1L, ]), unname(native$polygon[1L, ]))
  expect_identical(nrow(ring), n + 1L)
  expect_identical(out[-1L], native[-1L])
  # Native stays default and untouched by sf output.
  expect_identical(isovist(ctx, c(0, 0), 10, 360, 0, 16), native)
  # Matrix-only contexts yield an unknown CRS.
  plain <- isovist(isovist_context(), c(0, 0), 10, output = "sf")
  expect_true(is.na(sf::st_crs(plain$polygon)))
  isovist_context_free(ctx); invisible(gc())
  expect_s3_class(out$polygon, "sfc_POLYGON")
})

test_that("closure helper never appends a second closure and rejects unrepresentable results", {
  skip_if_not_installed("sf")
  closed <- rbind(c(0, 0), c(0, 1), c(1, 1), c(0, 0))
  expect_identical(nrow(unclass(rPSTool:::.pst_sf_polygon_output(closed, NULL)[[1L]])[[1L]]), 4L)
  open <- rbind(c(0, 0), c(0, 1), c(1, 1))
  expect_identical(nrow(unclass(rPSTool:::.pst_sf_polygon_output(open, NULL)[[1L]])[[1L]]), 4L)
  # Duplicates and zero area are not repaired: three open identical vertices
  # still close to a four-coordinate ring.
  zero <- rbind(c(0, 0), c(0, 0), c(0, 1))
  expect_identical(nrow(unclass(rPSTool:::.pst_sf_polygon_output(zero, NULL)[[1L]])[[1L]]), 4L)
  # An already-closed three-row result has no second closure and < 4 coordinates.
  expect_error(rPSTool:::.pst_sf_polygon_output(rbind(c(0, 0), c(0, 1), c(0, 0)), NULL), "four coordinates")
  expect_error(rPSTool:::.pst_sf_polygon_output(open[1:2, ], NULL), "fewer than three")
  expect_error(rPSTool:::.pst_sf_polygon_output(rbind(open[1:2, ], c(NaN, 0)), NULL), "nonfinite")
  expect_error(rPSTool:::.pst_sf_polygon_output(matrix(c(0, 0), 1L), NULL), "fewer than three")
})

test_that("a singleton native result cannot be sf but remains available natively", {
  skip_if_not_installed("sf")
  ctx <- isovist_context()
  native <- isovist(ctx, c(0, 0), .01, 90)
  expect_equal(nrow(native$polygon), 1L)
  expect_error(isovist(ctx, c(0, 0), .01, 90, output = "sf"), "fewer than three")
  expect_identical(isovist(ctx, c(0, 0), .01, 90), native)
  expect_error(isovist(ctx, c(0, 0), 1, output = "bad"))
})

test_that("matrix isovist calls do not require sf", {
  ctx <- isovist_context(obstacles = list(list(iso_rect(2, -1, 2))))
  baseline <- isovist(ctx, c(0, 0), 10)
  testthat::local_mocked_bindings(.pst_require_sf = function() stop("optional package 'sf' required"), .package = "rPSTool")
  expect_identical(isovist(ctx, c(0, 0), 10), baseline)
  expect_error(isovist(ctx, c(0, 0), 10, output = "sf"), "optional package")
  expect_identical(names(isovist_context(obstacles = list(list(iso_rect(2, -1, 2))))), c("ptr", "pst_version"))
})

# ---- Fixture-driven coverage against the existing direct-PST isovist fixture ----
iso_fixture <- function() dget(test_path("fixtures", "isovist-direct-v3.3.2.R"))
iso_failure_names <- c("degenerate_partial_near_polygon", "degenerate_two_point_near_polygon",
                       "degenerate_partial_straddling_points", "degenerate_full_near_polygon")
iso_layer_of <- function(group, polygon) {
  if (!polygon) return(iso_pts(group))
  iso_layer(lapply(group, function(ring) iso_poly(ring)))
}
# NULL when the matrix input has no faithful sf form (an intentionally repeated
# terminal vertex cannot be distinguished from sf's structural closure).
iso_to_sf <- function(kind) {
  args <- isovist_input(kind)
  if (kind == "closed_polygon") return(NULL)
  for (family in names(args)) {
    polygon <- family != "attraction_points"
    args[[family]] <- lapply(args[[family]], iso_layer_of, polygon = polygon)
  }
  args
}

test_that("every faithful sf form of a successful direct fixture case is identical", {
  skip_if_not_installed("sf")
  checked <- 0L
  for (item in iso_fixture()$cases) {
    case <- item$case
    if (item$returncode != 0 || case$name %in% iso_failure_names) next
    sf_args <- iso_to_sf(case$geometry)
    if (is.null(sf_args)) next
    m <- do.call(isovist_context, isovist_input(case$geometry))
    s <- do.call(isovist_context, sf_args)
    for (reuse in 1:2) {
      expected <- isovist_call(m, case)
      actual <- isovist_call(s, case)
      expect_identical(actual, expected, info = case$name)
      native <- item$native
      reference <- do.call(rbind, lapply(native$points, unlist)); storage.mode(reference) <- "double"
      expect_isovist_polygon(actual$polygon, reference, info = case$name)
      expect_identical(actual$area, native$area, info = case$name)
    }
    isovist_context_free(m); isovist_context_free(s)
    checked <- checked + 1L
  }
  # 85 fixture cases, minus 8 guarded failures and the matrix-only closed polygon.
  expect_identical(checked, 76L)
})

test_that("the explicit terminal-closure matrix fixture stays matrix-only", {
  skip_if_not_installed("sf")
  expect_null(iso_to_sf("closed_polygon"))
  item <- Filter(function(x) x$case$geometry == "closed_polygon", iso_fixture()$cases)[[1L]]
  ctx <- do.call(isovist_context, isovist_input("closed_polygon"))
  expect_equal(nrow(isovist_call(ctx, item$case)$polygon), length(item$native$points))
})

test_that("sf-representable guarded failures fail identically and contexts stay reusable", {
  skip_if_not_installed("sf")
  hazards <- Filter(function(x) x$returncode != 0 || x$case$name %in% iso_failure_names,
                    iso_fixture()$cases)
  expect_length(hazards, 8L)
  kinds <- character()
  for (item in hazards) {
    kinds <- c(kinds, item$case$geometry)
    sf_args <- iso_to_sf(item$case$geometry) # "empty" has no groups, hence no layers
    m <- do.call(isovist_context, isovist_input(item$case$geometry))
    s <- do.call(isovist_context, sf_args)
    before <- isovist_life()
    expect_error(isovist_call(m, item$case), "no result was published")
    expect_error(isovist_call(s, item$case), "no result was published", info = item$case$name)
    expect_identical(isovist_life()[4:6], before[4:6])
    good <- isovist(s, c(0, 0), 1, 90)
    expect_identical(good, isovist(m, c(0, 0), 1, 90))
    expect_error(isovist_call(s, item$case), "no result was published")
    expect_identical(isovist(s, c(0, 0), 1, 90), good)
    expect_identical(isovist_life()[6], 0)
    isovist_context_free(m); isovist_context_free(s)
  }
  # Four empty-context cases (no layers to convert), plus polygon and point guards.
  expect_identical(sort(unique(kinds)), c("empty", "near_polygon", "straddling_points"))
})

test_that("context creation copies sf input; later mutation, removal and GC are irrelevant", {
  skip_if_not_installed("sf")
  args <- iso_sf_args(crs = 3857)
  ctx <- do.call(isovist_context, args)
  baseline <- isovist(ctx, c(0, 0), 10, 90, 30)
  full <- isovist(ctx, c(.3, .1), 10)
  # Replace the source objects with shifted geometry, then drop and collect them.
  shifted <- args
  shifted$obstacles[[1L]] <- iso_layer(iso_poly(iso_rect(50, 50, 1)), crs = 3857)
  shifted$attraction_points[[1L]] <- iso_pts(rbind(c(40, 40)), 3857)
  args$obstacles[[1L]] <- NULL
  rm(args, shifted)
  invisible(gc())
  expect_identical(isovist(ctx, c(0, 0), 10, 90, 30), baseline)
  expect_identical(isovist(ctx, c(.3, .1), 10), full)
  expect_equal(sf::st_crs(attr(ctx, "crs")), sf::st_crs(3857))
  # Results stay independent of the context too.
  isovist_context_free(ctx); invisible(gc())
  expect_error(isovist(ctx, c(0, 0), 10), "dead")
})
