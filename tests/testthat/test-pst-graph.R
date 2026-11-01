native_graph <- function(name, ...) {
  .Call(get(paste0("C_rpst_graph_", name), envir = asNamespace("rPSTool")), ...)
}

crossing_lines <- function() rbind(c(0, 0, 2, 0), c(1, -1, 1, 1))

test_that("matrix rows construct a genuine PST axial graph", {
  x <- crossing_lines()
  original <- x
  g <- axial_graph(x)
  expect_s3_class(g, "pst_graph")
  expect_type(g$ptr, "externalptr")
  expect_identical(g$type, "axial")
  expect_identical(g$pst_version, "3.3.2")
  expect_identical(g$n_lines, 2L)
  expect_identical(g$n_crossings, 1L)
  expect_identical(g$n_points, 0L)
  expect_identical(g$n_point_groups, 0L)
  expect_identical(native_graph("info", g$ptr), c(2L, 1L, 0L, 0L))
  expect_identical(x, original)
  expect_null(g$coordinates)
  expect_output(result <- withVisible(print(g)), "2 lines, 1 crossings")
  expect_false(result$visible)
  expect_identical(result$value, g)
  # Printing queries PST rather than trusting editable cached metadata.
  g$n_lines <- -10L
  expect_output(print(g), "2 lines")
})

test_that("integer, single-line and nonintersecting inputs retain PST topology", {
  x <- matrix(c(0L, 0L, 10L, 0L), nrow = 1L)
  expect_identical(axial_graph(x)$n_lines, 1L)
  expect_identical(axial_graph(x)$n_crossings, 0L)
  # Compact sequence storage (ALTREP on supported R versions) is materialised
  # before conversion buffers are allocated, for either numeric storage type.
  for (x in list(structure(1:8, dim = c(2L, 4L)),
                 structure(as.double(1:8), dim = c(2L, 4L)))) {
    expect_identical(axial_graph(x)$n_lines, 2L)
    ptr <- native_graph("create", x)
    expect_identical(native_graph("info", ptr)[[1L]], 2L)
    native_graph("release", ptr)
  }
  expect_identical(axial_graph(rbind(c(0, 0, 1, 0), c(2, 1, 3, 1)))$n_crossings, 0L)
  expect_identical(axial_graph(rbind(c(0, 0, 1, 0), c(1, 0, 1, 1)))$n_crossings, 1L)
  expect_identical(axial_graph(crossing_lines() + 1e6)$n_crossings, 1L)
  # PST retains degenerate/short lines; the binding does not filter them.
  expect_identical(axial_graph(matrix(rep(0, 4), 1L))$n_lines, 1L)
  expect_identical(axial_graph(matrix(c(0, 0, 0.001, 0), 1L))$n_lines, 1L)
})

test_that("invalid coordinates fail at both R and native boundaries", {
  bad_type <- list(NULL, numeric(4), list(0, 0, 1, 1), data.frame(x = 1),
                   matrix("a", 1, 4), matrix(TRUE, 1, 4), matrix(1+1i, 1, 4),
                   array(1, c(1, 2, 2)), new("externalptr"))
  for (x in bad_type) {
    expect_error(axial_graph(x), "numeric matrix")
    expect_error(native_graph("create", x), "numeric matrix")
  }
  for (x in list(matrix(numeric(), 0, 4), matrix(1, 1, 3), matrix(1, 2, 5))) {
    expect_error(axial_graph(x), "at least one row and exactly four columns")
    expect_error(native_graph("create", x), "at least one row and exactly four columns")
  }
  for (value in c(NA_real_, NaN, Inf, -Inf)) {
    x <- crossing_lines()
    x[2, 3] <- value
    expect_error(axial_graph(x), "finite")
    expect_error(native_graph("create", x), "finite")
  }
  expect_error(axial_graph(matrix(c(NA_integer_, 0L, 1L, 1L), 1)), "finite")
  expect_error(native_graph("create", matrix(c(NA_integer_, 0L, 1L, 1L), 1)), "finite")
  # Finiteness alone does not protect PST's double midpoint or float distances.
  for (x in list(matrix(c(1e308, 0, 1e308, 1), 1),
                 matrix(c(-1e100, 0, 1e100, 1), 1),
                 matrix(c(-1e20, 0, 1e20, 1), 1))) {
    expect_error(axial_graph(x), "overflows PST")
  }
})

test_that("foreign, missing, released and serialised pointers fail safely", {
  for (ptr in list(NULL, 1, new("externalptr"))) {
    expect_error(native_graph("info", ptr), "Invalid pst_graph native pointer")
    expect_error(native_graph("release", ptr), "Invalid pst_graph native pointer")
    expect_error(print(structure(list(ptr = ptr), class = "pst_graph")), "Invalid pst_graph")
  }
  expect_error(rPSTool:::print.pst_graph(list()), "Invalid pst_graph")
  g <- axial_graph(crossing_lines())
  restored <- unserialize(serialize(g, NULL))
  expect_error(print(restored), "no longer live")
  expect_error(native_graph("info", restored$ptr), "no longer live")
  native_graph("release", restored$ptr) # A null serialised owner is harmless.
  expect_output(print(g), "2 lines")
  alias <- g
  native_graph("release", g$ptr)
  native_graph("release", alias$ptr)
  expect_error(print(alias), "no longer live")
})

test_that("last-owner GC frees exactly once and aliases keep the graph alive", {
  gc()
  before <- native_graph("lifecycle")
  g <- axial_graph(crossing_lines())
  alias <- g
  rm(g)
  gc()
  expect_output(print(alias), "2 lines")
  expect_identical(native_graph("lifecycle") - before, c(1, 0, 1))
  rm(alias)
  gc()
  expect_identical(native_graph("lifecycle") - before, c(1, 1, 0))
  gc()
  expect_identical(native_graph("lifecycle") - before, c(1, 1, 0))
})

test_that("repeated creation, explicit finalisation, failures and GC are safe", {
  gc()
  before <- native_graph("lifecycle")
  for (i in seq_len(200L)) {
    g <- axial_graph(crossing_lines())
    if (i %% 2L == 0L) {
      native_graph("release", g$ptr)
      native_graph("release", g$ptr)
    }
    rm(g)
    if (i %% 10L == 0L) gc()
  }
  gc()
  expect_identical(native_graph("lifecycle") - before, c(200, 200, 0))
  before <- native_graph("lifecycle")
  for (i in seq_len(50L)) {
    expect_error(axial_graph(matrix(c(-1e100, 0, 1e100, 1), 1)), "overflows PST")
  }
  gc()
  expect_identical(native_graph("lifecycle"), before)
  # An R error after successful native acquisition cannot orphan its owner.
  fail_after_creation <- function() {
    ptr <- native_graph("create", crossing_lines())
    stop("deliberate R error after acquisition")
  }
  expect_error(fail_after_creation(), "after acquisition")
  gc()
  expect_identical(native_graph("lifecycle") - before, c(1, 1, 0))
})
