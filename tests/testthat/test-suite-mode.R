# rpst_thin_items() (tests/testthat/helper-suite-mode.R): full mode keeps everything; CRAN mode keeps every parent case with items and
# every radius class, deterministically. Synthetic cases only; no PST computation.
tm_cases <- function() {
  classes <- list(list(walking = 5), list(steps = 2), list(straight = 0), list(angular = 90), list(walking = 5, steps = 2),
                  list(walking = 0), list())
  lapply(1:5, function(i) list(name = paste0("g", i), items = lapply(seq_len(12), function(j) list(
    id = j, radius = classes[[(i + j) %% length(classes) + 1L]]))))
}
tm_with_mode <- function(full, code) {
  old <- Sys.getenv("RPST_FULL_TESTS", unset = NA_character_)
  stats <- c(.rpst_suite_stats$kept, .rpst_suite_stats$total)
  on.exit({ if (is.na(old)) Sys.unsetenv("RPST_FULL_TESTS") else Sys.setenv(RPST_FULL_TESTS = old)
            .rpst_suite_stats$kept <- stats[1L]; .rpst_suite_stats$total <- stats[2L] })
  Sys.setenv(RPST_FULL_TESTS = if (full) "true" else "false")
  code()
}
n_items <- function(cases) sum(vapply(cases, function(x) length(x$items), 0L))

test_that("full mode keeps every case and nested item", {
  cases <- tm_cases()
  out <- tm_with_mode(TRUE, function() rpst_thin_items(cases, "items", every = 4L, by = list(rpst_radius_class)))
  expect_identical(out, cases)
})

test_that("CRAN mode keeps every parent case and every radius class, and is deterministic", {
  cases <- tm_cases()
  thin <- function() rpst_thin_items(cases, "items", every = 4L, by = list(rpst_radius_class))
  a <- tm_with_mode(FALSE, thin); b <- tm_with_mode(FALSE, thin)
  expect_identical(a, b)                                           # deterministic
  expect_length(a, length(cases))                                  # no parent case dropped
  expect_true(all(vapply(a, function(x) length(x$items) > 0L, NA)))  # each keeps at least one item
  expect_identical(vapply(a, `[[`, "", "name"), vapply(cases, `[[`, "", "name"))
  expect_lt(n_items(a), n_items(cases))                            # it genuinely reduces the comparisons
  all_classes <- unique(unlist(lapply(cases, function(x) vapply(x$items, rpst_radius_class, ""))))
  kept_classes <- unique(unlist(lapply(a, function(x) vapply(x$items, rpst_radius_class, ""))))
  expect_setequal(kept_classes, all_classes)                       # every radius class still represented
  expect_true(all(unlist(lapply(a, function(x) vapply(x$items, function(it) it$id %in% 1:12, NA)))))  # kept items are original items
})

test_that("a parent case without items is left unchanged in CRAN mode", {
  cases <- c(tm_cases(), list(list(name = "empty", items = list(), other = 1)))
  out <- tm_with_mode(FALSE, function() rpst_thin_items(cases, "items", every = 4L, by = list(rpst_radius_class)))
  expect_identical(out[[length(out)]], cases[[length(cases)]])
})
