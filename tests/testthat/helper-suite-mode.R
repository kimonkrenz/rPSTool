# Two validation purposes, one test suite (docs/testing.md).
#
# FULL (development) mode runs every case of every direct-PST reference fixture. It is selected by RPST_FULL_TESTS=true (the
# local gate, tools/ci/check-package.R, sets it) or by NOT_CRAN=true (devtools-style development runs).
# DEFAULT (CRAN) mode runs the same tests, but the heavy fixture-driven loops visit a deterministic subset of their cases:
# every `every`-th case plus the first case of every level of every stratum in `by`, so each graph, routine, option signature and
# parameter level is still compared with the direct pinned-PST result. Nothing is skipped: a thinned loop is still a test that
# runs and can fail, so the skip accounting of the warning policy (no skips on Linux/macOS, the exact inventory on Windows) is
# unchanged in both modes.
rpst_full_tests <- function() {
  flag <- tolower(Sys.getenv("RPST_FULL_TESTS", Sys.getenv("NOT_CRAN", "false")))
  flag %in% c("true", "1", "yes")
}

# `by`: list of functions, each mapping one case to ONE label (the labels of all `by` functions are pasted); the first case of every
# distinct label is kept. `each`: list of functions mapping a case to SEVERAL labels (for example edge-value flags); the first case
# of every distinct label of every function is kept, so each flag is represented independently of the others.
.rpst_suite_stats <- new.env(parent = emptyenv())
.rpst_suite_stats$kept <- 0L
.rpst_suite_stats$total <- 0L
rpst_cases <- function(cases, by = list(), every = 10L, each = list()) {
  n <- length(cases)
  if (rpst_full_tests() || n == 0L) {
    .rpst_suite_stats$kept <- .rpst_suite_stats$kept + n
    .rpst_suite_stats$total <- .rpst_suite_stats$total + n
    return(cases)
  }
  keep <- seq.int(1L, n, by = as.integer(every))
  for (f in by) {
    labels <- vapply(cases, function(x) paste(f(x), collapse = "|"), "")
    keep <- c(keep, match(unique(labels), labels))
  }
  for (f in each) {
    labels <- lapply(cases, function(x) unique(as.character(f(x))))
    flat <- unlist(labels)
    owner <- rep(seq_along(labels), lengths(labels))
    keep <- c(keep, owner[match(unique(flat), flat)])
  }
  keep <- sort(unique(c(keep, n)))
  .rpst_suite_stats$kept <- .rpst_suite_stats$kept + length(keep)
  .rpst_suite_stats$total <- .rpst_suite_stats$total + n
  cases[keep]
}

# Edge-value flags of a case: for every argument (recursively) whether it is empty, contains zero, a negative value, or a
# non-finite value. Used with `each` so that zero radii, zero/negative weights, empty point sets and non-finite inputs stay covered.
rpst_case_edges <- function(x) {
  out <- character()
  walk <- function(v, path) {
    if (is.list(v)) {
      for (i in seq_along(v)) walk(v[[i]], paste(path, if (is.null(names(v))) i else names(v)[[i]], sep = "$"))
    } else if (is.numeric(v)) {
      if (!length(v)) out <<- c(out, paste(path, "empty"))
      else {
        if (any(v == 0, na.rm = TRUE)) out <<- c(out, paste(path, "zero"))
        if (any(v < 0, na.rm = TRUE)) out <<- c(out, paste(path, "negative"))
        if (any(!is.finite(v))) out <<- c(out, paste(path, "nonfinite"))
      }
    } else if (is.null(v)) out <<- c(out, paste(path, "null"))
  }
  for (n in setdiff(names(x), c("name", "label", "id", "x", "count", "score", "depth", "counts", "scores", "depths", "weights",
                                "depth_weights", "normalized", "indices", "lengths", "crossings", "integrations", "point_state"))) walk(x[[n]], n)
  out
}

# A generic stratum for direct-fixture cases, built from the case itself: every short character/logical field (routine, analysis,
# weighted, ...; not per-case labels), the name of a nested graph and the set of option names that are non-NULL. Numbers are left out on purpose.
rpst_case_signature <- function(x) {
  parts <- vapply(setdiff(names(x), c("name", "label", "id")), function(n) {   # per-case labels are not strata
    v <- x[[n]]
    if (is.null(v)) return("")
    if ((is.character(v) || is.logical(v)) && length(v) <= 3L) return(paste(n, paste(v, collapse = ",")))
    if (is.list(v) && length(v) && !is.null(names(v))) {
      label <- if (is.character(v$name) && length(v$name) == 1L) v$name else ""
      return(paste(n, label, paste(sort(names(v)[!vapply(v, is.null, NA)]), collapse = "+")))
    }
    ""
  }, "")
  paste(parts[nzchar(parts)], collapse = "/")
}

# Thin a list of cases that each hold a list of sub-items (for example one reference case with several radii) in CRAN mode.
# Every case keeps at least its first item, and the first (case, item) pair of every distinct label of every `by` function applied to
# an ITEM is kept as well, so each case (graph) and each item class (for example each radius type) is still compared with the direct
# pinned-PST result; `every` additionally keeps every n-th pair. In full mode the cases are returned unchanged.
rpst_thin_items <- function(cases, field, every = 4L, by = list(), case_label = function(case) case$name) {
  pairs <- unlist(lapply(seq_along(cases), function(i) lapply(seq_along(cases[[i]][[field]]), function(j) c(i, j))), recursive = FALSE)
  item <- function(p) cases[[p[[1L]]]][[field]][[p[[2L]]]]
  keep <- rpst_cases(pairs, every = every,
                     by = c(list(function(p) case_label(cases[[p[[1L]]]])), lapply(by, function(f) function(p) f(item(p)))))
  if (length(keep) == length(pairs)) return(cases)
  kept <- split(vapply(keep, `[[`, 0, 2L), factor(vapply(keep, `[[`, 0, 1L), levels = seq_along(cases)))
  lapply(seq_along(cases), function(i) {                       # a case without items keeps all its other checks unchanged
    case <- cases[[i]]
    if (length(kept[[i]])) case[[field]] <- case[[field]][sort(kept[[i]])]
    case
  })
}
# Radius class of a reference item: which radius types are set, and which of them are zero.
rpst_radius_class <- function(item) paste(names(item$radius), ifelse(vapply(item$radius, function(v) all(unlist(v) == 0), NA), "0", "+"), collapse = " ")
