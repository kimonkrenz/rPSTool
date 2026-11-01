test_that("the registered native probe calls the compiled PST core", {
  # PST's own callback fixture runs synchronously, without worker/R callbacks.
  x <- .Call(rPSTool:::C_rpst_native_smoke)
  expect_identical(x[c(1L, 3L, 4L)], c(37L, 0L, -1L))
  expect_identical(x[5:7], c(1L, 1L, 1L))
  expect_identical(x[[8L]], 1L) # aligned block allocation and destruction
  # Progress delivery is filtered by an upstream clock; status is always sent.
  expect_true(x[[2L]] %in% c(1L, 2L))
  expect_error(.Call("rpst_native_smoke", PACKAGE = "rPSTool"))
  routines <- getDLLRegisteredRoutines("rPSTool")
  expect_identical(routines$.Call$rpst_native_smoke$numParameters, 0L)
})
