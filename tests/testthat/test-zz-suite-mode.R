# Runs last (file name sorts last). In full development mode no case loop may have been thinned; in CRAN mode thinning must have
# actually happened. Counters are filled by rpst_cases() in tests/testthat/helper-suite-mode.R across the files of one test run.
test_that("the active suite mode did what it claims", {
  kept <- .rpst_suite_stats$kept
  total <- .rpst_suite_stats$total
  if (total == 0L) {
    succeed("no case loop ran in this invocation (a single-file run)")
  } else if (rpst_full_tests()) {
    expect_identical(kept, total)
  } else {
    expect_lt(kept, total)
    expect_gt(kept, 0L)
  }
})
