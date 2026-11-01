test_that("segment rows own a genuine separate graph and private size", {
  x <- segment_rows()
  original <- x
  g <- segment_graph(x)
  expect_s3_class(g, "pst_segment_graph")
  expect_false(inherits(g, "pst_graph"))
  expect_type(g$ptr, "externalptr")
  expect_identical(g$type, "segment")
  expect_identical(g$n_segments, 2L)
  expect_identical(g$pst_version, "3.3.2")
  expect_identical(x, original)
  expect_null(g$coordinates)
  expect_output(result <- withVisible(print(g)), "2 segments")
  expect_false(result$visible)
  expect_identical(result$value, g)
  g$n_segments <- -1L
  expect_output(print(g), "2 segments")
  for (x in list(matrix(c(0L, 0L, 3L, 0L), 1),
                 structure(1:8, dim = c(2L, 4L)),
                 structure(as.double(1:8), dim = c(2L, 4L)))) {
    p <- native_segment("create", x)
    expect_identical(native_segment("info", p), nrow(x))
    native_segment("release", p)
  }
  # No filtering of degenerate or short segments.
  for (x in list(matrix(rep(0, 4), 1), matrix(c(0, 0, 0.001, 0), 1)))
    expect_identical(segment_graph(x)$n_segments, 1L)
})

test_that("invalid coordinates fail at both R and native boundaries", {
  bad_type <- list(NULL, numeric(4), list(0, 0, 1, 1), data.frame(x = 1),
                   matrix("a", 1, 4), matrix(TRUE, 1, 4), matrix(1+1i, 1, 4),
                   array(1, c(1, 2, 2)), new("externalptr"))
  for (x in bad_type) {
    expect_error(segment_graph(x), "numeric matrix")
    expect_error(native_segment("create", x), "numeric matrix")
  }
  for (x in list(matrix(numeric(), 0, 4), matrix(1, 1, 3), matrix(1, 2, 5))) {
    expect_error(segment_graph(x), "at least one row and exactly four columns")
    expect_error(native_segment("create", x), "at least one row and exactly four columns")
  }
  for (value in c(NA_real_, NaN, Inf, -Inf)) {
    x <- segment_rows()
    x[2, 3] <- value
    expect_error(segment_graph(x), "finite")
    expect_error(native_segment("create", x), "finite")
  }
  expect_error(segment_graph(matrix(c(NA_integer_, 0L, 1L, 1L), 1)), "finite")
  expect_error(native_segment("create", matrix(c(NA_integer_, 0L, 1L, 1L), 1)), "finite")
  # Finiteness alone does not protect PST's double midpoint or float distances.
  for (x in list(matrix(c(1e308, 0, 1e308, 1), 1),
                 matrix(c(-1e100, 0, 1e100, 1), 1),
                 matrix(c(-1e20, 0, 1e20, 1), 1))) {
    expect_error(segment_graph(x), "overflows PST")
  }
})

test_that("foreign, missing, released and serialised pointers fail safely", {
  for (ptr in list(NULL, 1, new("externalptr"))) {
    expect_error(native_segment("info", ptr), "Invalid pst_segment_graph native pointer")
    expect_error(native_segment("release", ptr), "Invalid pst_segment_graph native pointer")
    expect_error(print(structure(list(ptr = ptr), class = "pst_segment_graph")), "Invalid pst_segment_graph")
  }
  expect_error(rPSTool:::print.pst_segment_graph(list()), "Invalid pst_segment_graph")
  g <- segment_graph(segment_rows())
  restored <- unserialize(serialize(g, NULL))
  expect_error(print(restored), "no longer live")
  expect_error(native_segment("info", restored$ptr), "no longer live")
  native_segment("release", restored$ptr) # A null serialised owner is harmless.
  expect_output(print(g), "2 segments")
  alias <- g
  native_segment("release", g$ptr)
  native_segment("release", alias$ptr)
  expect_error(print(alias), "no longer live")
})

test_that("last-owner GC frees exactly once and aliases keep the graph alive", {
  gc()
  before <- native_segment("lifecycle")
  g <- segment_graph(segment_rows())
  alias <- g
  rm(g)
  gc()
  expect_output(print(alias), "2 segments")
  expect_identical(native_segment("lifecycle") - before, c(1, 0, 1))
  rm(alias)
  gc()
  expect_identical(native_segment("lifecycle") - before, c(1, 1, 0))
  gc()
  expect_identical(native_segment("lifecycle") - before, c(1, 1, 0))
})

test_that("repeated creation, explicit finalisation, failures and GC are safe", {
  gc()
  before <- native_segment("lifecycle")
  for (i in seq_len(200L)) {
    g <- segment_graph(segment_rows())
    if (i %% 2L == 0L) {
      native_segment("release", g$ptr)
      native_segment("release", g$ptr)
    }
    rm(g)
    if (i %% 10L == 0L) gc()
  }
  gc()
  expect_identical(native_segment("lifecycle") - before, c(200, 200, 0))
  before <- native_segment("lifecycle")
  for (i in seq_len(50L)) {
    expect_error(segment_graph(matrix(c(-1e100, 0, 1e100, 1), 1)), "overflows PST")
  }
  gc()
  expect_identical(native_segment("lifecycle"), before)
  # An R error after successful native acquisition cannot orphan its owner.
  fail_after_creation <- function() {
    ptr <- native_segment("create", segment_rows())
    stop("deliberate R error after acquisition")
  }
  expect_error(fail_after_creation(), "after acquisition")
  gc()
  expect_identical(native_segment("lifecycle") - before, c(1, 1, 0))
})
