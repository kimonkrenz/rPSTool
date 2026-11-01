# Mutation tests for the isovist-only 1-binary32-ULP portability allowance.
f32 <- function(x) readBin(writeBin(x, raw(), size = 4L), "numeric", size = 4L)
f32_next <- function(x, steps = 1L) {
  bits <- readBin(writeBin(x, raw(), size = 4L), "integer", size = 4L, n = length(x))
  readBin(writeBin(bits + steps, raw(), size = 4L), "numeric", size = 4L, n = length(x))
}
poly <- function() rbind(c(f32(1.1), f32(2.2)), c(f32(-3.3), f32(4.4)), c(0, f32(5.5)))

test_that("identical polygons and one-ULP finite differences on either axis are allowed", {
  p <- poly()
  expect_null(isovist_polygon_difference(p, p))
  for (cell in list(c(1, 1), c(2, 2), c(3, 2))) {
    for (step in c(1L, -1L)) {
      q <- p; q[cell[1], cell[2]] <- f32_next(p[cell[1], cell[2]], step)
      expect_false(identical(p, q))
      expect_null(isovist_polygon_difference(q, p))
      expect_null(isovist_polygon_difference(p, q))
    }
  }
  q <- p; q[1, ] <- f32_next(p[1, ], 1L); q[3, 2] <- f32_next(p[3, 2], -1L)
  expect_null(isovist_polygon_difference(q, p))
})

test_that("a one-ULP step across zero and a sign-crossing pair are handled by ULP distance", {
  tiny <- f32_next(0, 1L)
  expect_null(isovist_polygon_difference(matrix(c(tiny, 0), 1L), matrix(c(0, 0), 1L)))
  expect_null(isovist_polygon_difference(matrix(c(-0, 1), 1L), matrix(c(0, 1), 1L)))
  expect_null(isovist_polygon_difference(matrix(c(-tiny, 1), 1L), matrix(c(0, 1), 1L)))
  expect_false(is.null(isovist_polygon_difference(matrix(c(tiny, 1), 1L), matrix(c(-tiny, 1), 1L))))
})

test_that("-0.0f versus the smallest subnormal is one ULP in both directions; wider cases stay rejected", {
  tiny <- f32_next(0, 1L)               # smallest positive binary32 subnormal
  expect_identical(tiny, 2^-149)
  # -0.0f has bit pattern 0x80000000 (R's NA_integer_ when read as integer).
  expect_identical(readBin(writeBin(-0, raw(), size = 4L, endian = "big"), "raw", n = 4L),
                   as.raw(c(0x80, 0, 0, 0)))
  expect_identical(isovist_f32_key(c(-0, 0, tiny, -tiny)), c(0, 0, 1, -1))
  expect_false(anyNA(isovist_f32_key(c(-0, 0))))
  for (pair in list(list(-0, tiny), list(tiny, -0), list(0, tiny), list(tiny, 0))) {
    expect_null(isovist_polygon_difference(matrix(c(pair[[1L]], 1), 1L), matrix(c(pair[[2L]], 1), 1L)))
  }
  # -0.0f versus -smallest subnormal is also one ULP; two ULP either side is not.
  expect_null(isovist_polygon_difference(matrix(c(-0, 1), 1L), matrix(c(-tiny, 1), 1L)))
  tiny2 <- f32_next(0, 2L)
  for (pair in list(list(-0, tiny2), list(tiny2, -0), list(0, tiny2), list(-tiny2, 0),
                    list(tiny, -tiny), list(-tiny, tiny))) {
    expect_match(isovist_polygon_difference(matrix(c(pair[[1L]], 1), 1L), matrix(c(pair[[2L]], 1), 1L)),
                 "2 binary32 ULP")
  }
})

test_that("two ULP, non-binary32 values, shape, order and non-finite changes are rejected", {
  p <- poly()
  for (cell in list(c(1, 1), c(2, 2), c(3, 2))) {
    q <- p; q[cell[1], cell[2]] <- f32_next(p[cell[1], cell[2]], 2L)
    expect_match(isovist_polygon_difference(q, p), "2 binary32 ULP")
    q <- p; q[cell[1], cell[2]] <- f32_next(p[cell[1], cell[2]], -3L)
    expect_match(isovist_polygon_difference(q, p), "3 binary32 ULP")
    q <- p; q[cell[1], cell[2]] <- p[cell[1], cell[2]] * (1 + 1e-12)
    expect_match(isovist_polygon_difference(q, p), "not binary32-representable")
  }
  expect_match(isovist_polygon_difference(p[1:2, ], p), "dimensions")
  expect_match(isovist_polygon_difference(p[, 1, drop = FALSE], p), "dimensions")
  expect_match(isovist_polygon_difference(p[3:1, ], p), "binary32 ULP")
  expect_match(isovist_polygon_difference(p, as.vector(p)), "dimensions")
  storage <- p; storage.mode(storage) <- "integer"
  expect_match(isovist_polygon_difference(p, storage), "dimensions")
  for (bad in list(NaN, Inf, -Inf, NA_real_)) {
    q <- p; q[2, 1] <- bad
    expect_match(isovist_polygon_difference(q, p), "non-finite")
    expect_match(isovist_polygon_difference(p, q), "non-finite")
  }
  q <- p; r <- p; q[2, 1] <- Inf; r[2, 1] <- -Inf
  expect_match(isovist_polygon_difference(q, r), "non-finite")
  q <- p; r <- p; q[2, 1] <- NaN; r[2, 1] <- NA_real_
  expect_match(isovist_polygon_difference(q, r), "non-finite")
})

test_that("the allowance is confined to polygon coordinates in the isovist tests", {
  path <- test_path("test-isovist.R")
  text <- readLines(path, warn = FALSE)
  # Area stays exactly compared in the direct-fixture test.
  expect_true(any(grepl("expect_identical(actual$area,native$area", text, fixed = TRUE)))
  expect_false(any(grepl("expect_isovist_polygon(actual$area", text, fixed = TRUE)))
  expect_true(any(grepl("expect_isovist_polygon(actual$polygon,expected", text, fixed = TRUE)))
})
