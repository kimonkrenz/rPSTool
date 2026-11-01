# Test-suite mode of the local validation scripts (docs/testing.md).
#
# tools/ci/check-local.R is the FULL development validation: it always runs every case of every direct-PST fixture, whatever
# RPST_FULL_TESTS the parent environment carries, so a stray RPST_FULL_TESTS=false can never turn it into a reduced run that
# still reports success. The CRAN-mode suite stays selectable explicitly, by running tools/ci/check-package.R directly with
# RPST_FULL_TESTS=false (a CRAN-style timing run, not a full validation).

# check-local.R: force full mode for itself and for every subprocess it launches.
pst_enforce_full_suite_mode <- function() {
  Sys.setenv(RPST_FULL_TESTS = "true")
  invisible(TRUE)
}

# check-package.R: full unless the environment explicitly says "false" (any letter case); unset means full.
pst_full_tests_requested <- function(value = Sys.getenv("RPST_FULL_TESTS", "true")) {
  !identical(tolower(value), "false")
}
