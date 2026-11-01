#!/usr/bin/env Rscript
# R CMD check stays unchanged. This gate admits only the exact pinned upstream
# warning inventory after checking successful installation and package tests.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("Usage: Rscript tools/ci/check-package.R ubuntu|macos|windows")
platform <- args[[1L]]
actual_platform <- if (.Platform$OS.type == "windows") "windows" else
  if (Sys.info()[["sysname"]] == "Darwin") "macos" else "ubuntu"
if (!identical(platform, actual_platform)) stop("CI platform does not match executor")
root <- normalizePath(".", winslash = "/", mustWork = TRUE)
sys.source("tools/verify-vendor.R", envir = new.env(parent = baseenv()))
source("tools/ci/pst-warning-policy.R")
invisible(read_pst_warning_policy(platform)) # Reject malformed policies before the build.
# The local gate is the FULL development validation: every case of every direct-PST fixture (docs/testing.md).
# RPST_FULL_TESTS=false selects the thinned CRAN-mode suite, e.g. for a CRAN-style timing run; that run is not a full validation.
source("tools/ci/gate-mode.R")
full_tests <- pst_full_tests_requested()
Sys.setenv(RPST_FULL_TESTS = if (full_tests) "true" else "false")
for (variable in c("_R_CHECK_FORCE_SUGGESTS_", "_R_CHECK_CRAN_INCOMING_")) {
  if (Sys.getenv(variable) == "") do.call(Sys.setenv, setNames(list("false"), variable))
}
r <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "R.exe" else "R")
version <- read.dcf("DESCRIPTION")[[1L, "Version"]]
dir.create(".local/ci-check", recursive = TRUE, showWarnings = FALSE)
check_dir <- normalizePath(".local/ci-check", winslash = "/", mustWork = TRUE)
# Never let a failed invocation be validated against a previous run's results.
unlink(file.path(check_dir, c("rPSTool.Rcheck", paste0("rPSTool_", version, ".tar.gz"),
                             "build.out", "check.out")), recursive = TRUE)
run <- function(arguments, log) {
  # R CMD build copies the source tree before applying .Rbuildignore. Windows
  # cannot copy a log held open by that same command inside the source tree.
  temporary_log <- tempfile("rpst-command-", fileext = ".log")
  on.exit(unlink(temporary_log), add = TRUE)
  status <- system2(r, arguments, stdout = temporary_log, stderr = temporary_log)
  if (!file.copy(temporary_log, log, overwrite = TRUE)) stop("Cannot preserve command log")
  cat(readLines(log, warn = FALSE), sep = "\n")
  status
}
setwd(check_dir)
build_status <- run(c("CMD", "build", "--no-manual", shQuote(root)), "build.out")
if (build_status != 0L || any(grepl(
    "(^|[[:space:]])warning(s| message(s)?)?:|^warning in|\\bERROR\\b|\\.\\.\\. WARNING",
    readLines("build.out", warn = FALSE), ignore.case = TRUE, perl = TRUE))) {
  stop("Source package build failed or warned")
}
tarball <- paste0("rPSTool_", version, ".tar.gz")
if (!file.exists(tarball)) stop("Missing source package tarball")
status <- run(c("CMD", "check", "--no-manual", "--as-cran", shQuote(tarball)), "check.out")
logs <- file.path(check_dir, "rPSTool.Rcheck")
setwd(root)
# Report the original failure, never a secondary "cannot open the connection". The check directory was emptied
# before this invocation, so every log below belongs to it.
report_missing <- function(what) {
  cat(sprintf("\n--- %s (R CMD check exit status %s). Last lines of check.out:\n", what, status))
  out <- file.path(check_dir, "check.out")
  if (file.exists(out)) cat(tail(readLines(out, warn = FALSE), 40L), sep = "\n")
  stop(what, call. = FALSE)
}
read_log <- function(name) {
  path <- file.path(logs, name)
  if (!file.exists(path)) report_missing(paste0("R CMD check did not produce ", name))
  readLines(path, warn = FALSE)
}
test_log <- tryCatch(pst_read_test_log(logs), error = function(e) report_missing(conditionMessage(e)))
if (test_log$failed) {
  # The complete original diagnostics of the failing tests, then a hard stop: a failed log is never validated.
  cat("\n--- Package tests failed; complete ", basename(test_log$path), ":\n", sep = "")
  cat(test_log$lines, sep = "\n")
  stop("R CMD check reported failing package tests (", test_log$path, ")", call. = FALSE)
}
expectations <- pst_check_suite_mode(test_log$lines, full_tests)
cat(sprintf("Package tests: %s suite, %d expectations passed\n", if (full_tests) "FULL development" else "CRAN-mode (thinned)", expectations))
validate_pst_check(platform, read_log("00install.out"), read_log("00check.log"), test_log$lines, status)
# Verify that the complete source inventory is still pristine after the check.
sys.source("tools/verify-vendor.R", envir = new.env(parent = baseenv()))
