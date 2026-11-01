#!/usr/bin/env Rscript
# Smoke tests for compare-exports.R: two positive and several negative cases on tiny synthetic CSVs. Exit 0 if all behave as expected.
# Usage: Rscript selftest/smoke-test.R   (from tools/validation/qgis-comparison)
Sys.setenv(PST_COMPARE_NO_MAIN = "1")
here <- tryCatch(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))), error = function(e) ".")
source(file.path(here, "..", "compare-exports.R"))
tmp <- tempfile("cmp-"); dir.create(tmp); on.exit(unlink(tmp, recursive = TRUE))
w <- function(name, df) {   # write.csv would turn NaN into the NA string; write numbers explicitly
  p <- file.path(tmp, name)
  txt <- function(x) if (is.numeric(x)) ifelse(is.nan(x), "NaN", ifelse(is.na(x), "", as.character(x))) else as.character(x)
  write.csv(as.data.frame(lapply(df, txt)), p, row.names = FALSE, quote = FALSE); p }
base <- data.frame(id = c(10, 20, 30, 40), v = c(1, 2.5, NaN, Inf), w = c(0.1, 0.2, 0.3, 0.4))
r <- w("r.csv", base)
check <- function(label, cond) { cat(sprintf("%-60s %s\n", label, if (cond) "ok" else "FAILED")); if (!cond) fails <<- fails + 1L }
fails <- 0L
n <- function(...) length(compare_case(...)$findings)
# positive
check("identical files pass", n(w("q1.csv", base), r, "id") == 0)
shuffled <- base[c(3, 1, 4, 2), ]
check("different row order passes (rows matched by id)", n(w("q2.csv", shuffled), r, "id") == 0)
check("difference within rtol passes", n(w("q2b.csv", transform(base, w = w * (1 + 5e-7))), r, "id") == 0)
# negative
check("missing row is reported", n(w("q3.csv", base[-2, ]), r, "id") > 0)
check("extra row is reported", n(r, w("q3b.csv", base[-2, ]), "id") > 0)
check("missing column is reported", n(w("q4.csv", base[, c("id", "v")]), r, "id") > 0)
check("numerical difference beyond rtol is reported", n(w("q5.csv", transform(base, w = w * 1.001)), r, "id") > 0)
check("difference hidden by loose rtol is visible only when rtol is loose", n(w("q5b.csv", transform(base, w = w * 1.001)), r, "id", rtol = 0.01) == 0)
check("NaN vs finite is reported", n(w("q6.csv", transform(base, v = replace(v, 3, 7))), r, "id") > 0)
check("NA vs NaN is reported (not equal)", { q <- base; q$v[3] <- NA; n(w("q7.csv", q), r, "id") > 0 })
check("Inf vs -Inf is reported", n(w("q8.csv", transform(base, v = replace(v, 4, -Inf))), r, "id") > 0)
check("duplicate ids are reported", n(w("q9.csv", rbind(base, base[1, ])), r, "id") > 0)
check("non-numeric text is reported", { q <- base; q$w <- as.character(q$w); q$w[2] <- "abc"; n(w("q10.csv", q), r, "id") > 0 })
check("same file or identical bytes is flagged as a self-comparison", is_self_comparison(r, r) && is_self_comparison(r, w("q11.csv", base)))
check("a genuinely different export is not a self-comparison", !is_self_comparison(w("q12.csv", transform(base, w = w * 1.001)), r))
if (fails) { cat(fails, "smoke test(s) FAILED\n"); quit(status = 1L) } else cat("all smoke tests passed\n")
