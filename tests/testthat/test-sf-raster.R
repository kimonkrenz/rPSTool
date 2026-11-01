source(test_path("fixtures", "raster-direct-v3.3.2.R"), local = TRUE)
sr_lines <- function(m, crs = NA_integer_, ...) {
  geometry <- sf::st_sfc(lapply(seq_len(nrow(m)), function(i)
    sf::st_linestring(matrix(m[i, ], 2L, byrow = TRUE))), crs = crs)
  if (...length()) sf::st_sf(..., geometry = geometry) else geometry
}
# Direct case 1 (cross_normalized_1_1): range 3 is non-empty, representable and has
# holes; range 5 is native-valid but not representable (two-vertex ring).
sr_case <- function() raster_direct_fixture[[1L]]
sr_good <- function() sr_case()$ranges[3L, , drop = FALSE]
sr_bad <- function() sr_case()$ranges[5L, , drop = FALSE]
sr_args <- function() list(x = matrix(c(0, 0, 2, 2, 0, 2, 2, 0), 2L, 4L, byrow = TRUE),
                           values1 = c(1, 2), values2 = c(3, 4))
sr_ring_ok <- function(ring) nrow(ring) >= 3L && all(is.finite(ring))
sr_representable <- function(polygons) all(vapply(polygons, function(range)
  all(vapply(range, function(polygon) length(polygon) > 0L && all(vapply(polygon, sr_ring_ok, NA)), NA)), NA))
sr_expected_ring <- function(ring) {
  n <- nrow(ring)
  closed <- all(ring[1L, ] == ring[n, ])
  unname(if (closed) ring else rbind(ring, ring[1L, ]))
}

test_that("the direct raster cases give identical rasters from sf line input (a stratified selection in CRAN mode)", {
  skip_if_not_installed("sf")
  checked <- 0L
  # CRAN mode: a deterministic subset containing every argument signature and edge value of the fixture (the direct-PST
  # comparison of all 79 cases is test-raster.R); full mode visits all 79 cases.
  cases <- rpst_cases(raster_direct_fixture, every = 5L, by = list(rpst_case_signature), each = list(rpst_case_edges))
  for (case in cases) {
    args <- case$args
    sf_args <- args
    # Alternate plain sfc and attributed sf inputs; attributes must be ignored.
    attributed <- checked %% 2L == 1L
    sf_args$x <- if (attributed) sr_lines(args$x, NA_integer_, values1 = 99, id = "a") else sr_lines(args$x)
    if (!is.null(args$y)) sf_args$y <- sr_lines(args$y, NA_integer_, weight = 7)
    m <- do.call(compare_line_results, args)
    s <- do.call(compare_line_results, sf_args)
    expect_identical(names(s), names(m))
    for (use in 1:2) {
      expect_identical(raster_data(s), raster_data(m), info = case$name)
      expect_identical(raster_to_polygons(s, case$ranges), raster_to_polygons(m, case$ranges), info = case$name)
    }
    for (field in c("pitch", "format", "min", "max", "values"))
      expect_equal(raster_data(s)[[field]], case$expected[[field]], tolerance = 0, info = paste(case$name, field))
    expect_equal(raster_to_polygons(s, case$ranges), case$polygons, tolerance = 0, info = case$name)
    raster_free(m); raster_free(s)
    checked <- checked + 1L
  }
  expect_identical(checked, if (rpst_full_tests()) 79L else length(cases))
})

test_that("sf polygon output reproduces the representable direct polygon results (all of them in the full suite)", {
  skip_if_not_installed("sf")
  cases <- 0L; representable_cases <- 0L; ranges <- 0L; representable_ranges <- 0L
  for (case in raster_direct_fixture) {
    r <- do.call(compare_line_results, case$args)
    cases <- cases + 1L
    ok <- vapply(case$polygons, function(range) sr_representable(list(range)), NA)
    ranges <- ranges + length(ok); representable_ranges <- representable_ranges + sum(ok)
    if (all(ok)) {
      representable_cases <- representable_cases + 1L
      out <- raster_to_polygons(r, case$ranges, output = "sf")
      expect_type(out, "list"); expect_false(inherits(out, "sfc"))
      expect_length(out, length(case$polygons))
      for (i in seq_along(out)) {
        expect_s3_class(out[[i]], "sfc_POLYGON")
        expect_length(out[[i]], length(case$polygons[[i]]))
        expect_true(is.na(sf::st_crs(out[[i]])))
        for (j in seq_along(case$polygons[[i]])) {
          native_rings <- case$polygons[[i]][[j]]
          sf_rings <- unclass(out[[i]][[j]])
          expect_length(sf_rings, length(native_rings)) # first = outer, rest = holes in order
          for (k in seq_along(native_rings)) {
            expect_identical(unname(sf_rings[[k]]), sr_expected_ring(native_rings[[k]]), info = case$name)
          }
        }
      }
    } else {
      expect_error(raster_to_polygons(r, case$ranges, output = "sf"), "range [0-9]+ polygon [0-9]+ ring [0-9]+")
      # Native remains the authority, and the owner stays usable.
      expect_equal(raster_to_polygons(r, case$ranges), case$polygons, tolerance = 0, info = case$name)
      expect_equal(raster_data(r)$values, case$expected$values, tolerance = 0, info = case$name)
    }
    # Per-range partition through the public function.
    for (i in which(ok)) {
      one_range <- case$ranges[i, , drop = FALSE]
      one <- raster_to_polygons(r, one_range, output = "sf")
      expect_length(one, 1L)
      expect_length(one[[1L]], length(case$polygons[[i]]))
      # A single-range call reproduces that range of the full fixture.
      expect_equal(raster_to_polygons(r, one_range), case$polygons[i], tolerance = 0, info = case$name)
      for (j in seq_along(case$polygons[[i]])) for (k in seq_along(case$polygons[[i]][[j]]))
        expect_identical(unname(unclass(one[[1L]][[j]])[[k]]), sr_expected_ring(case$polygons[[i]][[j]][[k]]))
    }
    for (i in which(!ok))
      expect_error(raster_to_polygons(r, case$ranges[i, , drop = FALSE], output = "sf"), "ring")
    raster_free(r)
  }
  expect_identical(cases, 79L)
  # Pinned partition counts of the 79 direct cases: whole outputs and ranges.
  expect_identical(c(representable_cases, cases - representable_cases), c(32L, 47L))
  # 438 ranges: 291 empty, 81 non-empty representable (33 with holes), 66 non-empty unrepresentable.
  expect_identical(c(ranges, representable_ranges), c(438L, 372L))
})

test_that("ring closure helper adds exactly one structural closure and rejects the rest", {
  f <- rPSTool:::.pst_sf_output_ring
  open <- rbind(c(0, 0), c(1, 0), c(1, 1))
  expect_identical(f(open)$ring, rbind(open, open[1L, ]))
  closed <- rbind(open, open[1L, ])
  expect_identical(f(closed)$ring, closed)
  # Degenerate but representable: repeated vertices, zero area, no reorientation.
  line <- rbind(c(0, 0), c(0, 0), c(1, 1))
  expect_identical(f(line)$ring, rbind(line, line[1L, ]))
  cw <- rbind(c(0, 0), c(0, 1), c(1, 1)); ccw <- cw[3:1, ]
  expect_identical(f(cw)$ring[1:3, ], cw); expect_identical(f(ccw)$ring[1:3, ], ccw)
  expect_identical(f(matrix(numeric(), 0L, 2L))$problem, "vertices")
  expect_identical(f(matrix(c(NaN, NaN), 1L))$problem, "vertices")
  expect_identical(f(open[1:2, ])$problem, "vertices")
  expect_identical(f(rbind(open[1:2, ], c(NaN, 0)))$problem, "nonfinite")
  expect_identical(f(rbind(open[1:2, ], c(Inf, 0)))$problem, "nonfinite")
  expect_identical(f(rbind(c(0, 0), c(1, 1), c(0, 0)))$problem, "closure")
})

test_that("unrepresentable rings fail with their position and never yield partial results", {
  skip_if_not_installed("sf")
  good <- rbind(c(0, 0), c(1, 0), c(1, 1))
  convert <- rPSTool:::.pst_sf_raster_polygons
  expect_error(convert(list(list(list(good), list(good, good[1:2, ]))), NULL), "range 1 polygon 2 ring 2")
  expect_error(convert(list(list(), list(list(good, matrix(numeric(), 0L, 2L)))), NULL), "range 2 polygon 1 ring 2")
  expect_error(convert(list(list(list(rbind(c(NaN, NaN))))), NULL), "range 1 polygon 1 ring 1")
  expect_error(convert(list(list(list(rbind(good[1:2, ], c(Inf, 0))))), NULL), "nonfinite")
  expect_error(convert(list(list(list(rbind(c(0, 0), c(1, 1), c(0, 0))))), NULL), "already-closed")
  expect_error(convert(list(list(list())), NULL), "no rings")
  expect_identical(convert(list(), NULL), list())
  out <- convert(list(list(), list(list(good, good + 0.1))), 3857)
  expect_s3_class(out[[1L]], "sfc_POLYGON"); expect_length(out[[1L]], 0L)
  expect_length(unclass(out[[2L]][[1L]]), 2L) # outer ring then hole
  expect_equal(sf::st_crs(out[[2L]]), sf::st_crs(3857))
  expect_equal(sf::st_crs(out[[1L]]), sf::st_crs(3857))
})

test_that("zero ranges, empty ranges and the raster owner after failed sf conversion", {
  skip_if_not_installed("sf")
  case <- sr_case()
  r <- do.call(compare_line_results, case$args)
  expect_identical(raster_to_polygons(r, matrix(numeric(), 0L, 2L), output = "sf"), list())
  expect_identical(raster_to_polygons(r, matrix(numeric(), 0L, 2L)), list())
  empty <- raster_to_polygons(r, matrix(c(1e6, 2e6), 1L), output = "sf")
  expect_length(empty, 1L); expect_s3_class(empty[[1L]], "sfc_POLYGON"); expect_length(empty[[1L]], 0L)
  good <- raster_to_polygons(r, sr_good(), output = "sf")
  expect_length(good[[1L]], length(case$polygons[[3L]]))
  expect_gt(max(lengths(lapply(unclass(good[[1L]]), unclass))), 1L) # holes retained after the outer ring
  data <- raster_data(r)
  native_bad <- raster_to_polygons(r, sr_bad())
  before <- .Call(rPSTool:::C_rpst_raster_lifecycle)
  expect_error(raster_to_polygons(r, sr_bad(), output = "sf"), "range 1 polygon [0-9]+ ring [0-9]+")
  after <- .Call(rPSTool:::C_rpst_raster_lifecycle)
  # The one transient native polygon result was created and freed; nothing leaked.
  expect_identical(after[4:6] - before[4:6], c(1, 1, 0))
  expect_identical(raster_data(r), data)
  expect_identical(raster_to_polygons(r, sr_bad()), native_bad)
  expect_equal(native_bad, case$polygons[5L], tolerance = 0)
  expect_identical(raster_to_polygons(r, sr_good(), output = "sf"), good)
  raster_free(r)
})

test_that("raster CRS follows the shared sf CRS contract", {
  skip_if_not_installed("sf")
  a <- sr_args(); x <- a$x
  bare <- do.call(compare_line_results, a)
  expect_null(attr(bare, "crs")); expect_identical(names(bare), "ptr")
  proj <- do.call(compare_line_results, c(list(x = sr_lines(x, 3857)), a[-1L]))
  expect_equal(sf::st_crs(attr(proj, "crs")), sf::st_crs(3857))
  expect_identical(names(proj), "ptr")
  unknown <- do.call(compare_line_results, c(list(x = sr_lines(x)), a[-1L]))
  expect_true(is.na(sf::st_crs(attr(unknown, "crs"))))
  v <- a[-1L]
  # x only, y only, both, and mixed with matrices (matrix never receives a CRS).
  y_only <- compare_line_results(x, v$values1, v$values2, y = sr_lines(x, 3857))
  expect_equal(sf::st_crs(attr(y_only, "crs")), sf::st_crs(3857))
  both <- compare_line_results(sr_lines(x, 3857), v$values1, v$values2, y = sr_lines(x + 1, 3857))
  expect_equal(sf::st_crs(attr(both, "crs")), sf::st_crs(3857))
  mixed <- compare_line_results(sr_lines(x, 3857), v$values1, v$values2, y = x + 1)
  expect_equal(sf::st_crs(attr(mixed, "crs")), sf::st_crs(3857))
  expect_error(compare_line_results(sr_lines(x, 3857), v$values1, v$values2, y = sr_lines(x)), "compatible")
  expect_error(compare_line_results(sr_lines(x), v$values1, v$values2, y = sr_lines(x, 3857)), "compatible")
  expect_error(compare_line_results(sr_lines(x, 3857), v$values1, v$values2, y = sr_lines(x, 3395)), "compatible")
  expect_error(compare_line_results(sr_lines(x, 4326), v$values1, v$values2), "Geographic")
  expect_error(compare_line_results(x, v$values1, v$values2, y = sr_lines(x, 4326)), "Geographic")
  # Output CRS comes from the raster owner; matrix rasters give unknown CRS.
  case <- sr_case()
  from_sf <- do.call(compare_line_results, c(list(x = sr_lines(case$args$x, 3857)), case$args[-1L]))
  expect_equal(sf::st_crs(raster_to_polygons(from_sf, sr_good(), output = "sf")[[1L]]), sf::st_crs(3857))
  from_matrix <- do.call(compare_line_results, case$args)
  expect_true(is.na(sf::st_crs(raster_to_polygons(from_matrix, sr_good(), output = "sf")[[1L]])))
  from_unknown <- do.call(compare_line_results, c(list(x = sr_lines(case$args$x)), case$args[-1L]))
  expect_true(is.na(sf::st_crs(raster_to_polygons(from_unknown, sr_good(), output = "sf")[[1L]])))
})

test_that("unsupported sf raster line input is rejected before the native call", {
  skip_if_not_installed("sf")
  v <- sr_args()[-1L]
  call <- function(x) compare_line_results(x, v$values1, v$values2)
  seg <- function(...) sf::st_linestring(rbind(...))
  expect_error(call(sf::st_sfc(seg(c(0, 0), c(1, 1), c(2, 2)), seg(c(0, 0), c(1, 0)))), "exactly two")
  expect_error(call(sf::st_sfc(sf::st_multilinestring(list(rbind(c(0, 0), c(1, 1)))), seg(c(0, 0), c(1, 0)))), "LINESTRING")
  expect_error(call(sf::st_sfc(seg(c(0, 0), c(1, 1)), sf::st_point(c(0, 0)))), "LINESTRING")
  expect_error(call(sf::st_sfc(seg(c(0, 0), c(1, 1)), sf::st_linestring())), "exactly two")
  expect_error(call(sf::st_sfc(seg(c(0, 0), c(1, Inf)), seg(c(0, 0), c(1, 0)))), "exactly two")
  expect_error(call(sf::st_sfc(sf::st_linestring(rbind(c(0, 0, 1), c(1, 1, 1))), seg(c(0, 0), c(1, 0)))), "XY")
  # Values stay explicit: mismatched lengths keep the native contract.
  expect_error(compare_line_results(sr_lines(sr_args()$x), 1, 2))
  # Zero-length two-vertex lines remain accepted exactly like the matrix path.
  z <- rbind(c(0, 0, 0, 0), c(0, 0, 2, 2))
  expect_identical(raster_data(compare_line_results(sr_lines(z), c(1, 2), c(2, 1))),
                   raster_data(compare_line_results(z, c(1, 2), c(2, 1))))
})

test_that("raster results do not depend on the source sf objects or the raster owner", {
  skip_if_not_installed("sf")
  case <- sr_case()
  lines <- sr_lines(case$args$x, 3857, id = seq_len(nrow(case$args$x)))
  expected <- do.call(compare_line_results, case$args)
  r <- do.call(compare_line_results, c(list(x = lines), case$args[-1L]))
  lines[[1L]][1L] <- 99
  rm(lines); invisible(gc())
  expect_identical(raster_data(r), raster_data(expected))
  first <- raster_to_polygons(r, sr_good(), output = "sf")
  second <- raster_to_polygons(r, sr_good(), output = "sf")
  expect_identical(first, second)
  # Mutating a source object before a later call affects only that call's input.
  mutated <- sr_lines(case$args$x); mutated[[1L]][1L] <- case$args$x[1L, 1L] + 5
  changed <- do.call(compare_line_results, c(list(x = mutated), case$args[-1L]))
  expect_false(identical(raster_data(changed), raster_data(expected)))
  expect_identical(raster_data(r), raster_data(expected))
  # sf results stay valid and unchanged after the raster owner is released.
  snapshot <- serialize(first, NULL)
  raster_free(r); invisible(gc())
  expect_error(raster_data(r), "dead")
  expect_error(raster_to_polygons(r, sr_good(), output = "sf"), "dead")
  expect_identical(serialize(first, NULL), snapshot)
})

test_that("raster_data stays an ordinary R list with no sf conversion", {
  skip_if_not_installed("sf")
  r <- compare_line_results(sr_lines(sr_args()$x, 3857), c(1, 2), c(3, 4))
  d <- raster_data(r)
  expect_identical(names(d), c("bbox", "dimensions", "pitch", "format", "min", "max", "values"))
  expect_type(d, "list"); expect_false(inherits(d, c("sf", "sfc", "crs")))
  expect_null(attr(d$bbox, "crs")); expect_true(is.matrix(d$values))
  expect_identical(d, raster_data(do.call(compare_line_results, sr_args())))
})

test_that("matrix raster calls do not require sf; explicit sf use errors cleanly", {
  r <- do.call(compare_line_results, sr_args())
  data <- raster_data(r); native <- raster_to_polygons(r, matrix(c(-2, 2), 1L))
  local_mocked_bindings(.pst_require_sf = function() stop("optional package 'sf' required"), .package = "rPSTool")
  expect_identical(raster_data(r), data)
  expect_identical(raster_to_polygons(r, matrix(c(-2, 2), 1L)), native)
  expect_identical(raster_to_polygons(r, matrix(c(-2, 2), 1L), output = "native"), native)
  expect_s3_class(do.call(compare_line_results, sr_args()), "pst_raster")
  expect_error(raster_to_polygons(r, matrix(c(-2, 2), 1L), output = "sf"), "optional package")
  expect_error(raster_to_polygons(r, matrix(c(-2, 2), 1L), output = "bad"))
  expect_identical(raster_data(r), data)
})
