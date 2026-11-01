#!/usr/bin/env Rscript
# Windows validation of result-file writing. Run from the repository root on the machine under test:
#
#   Rscript tools/validation/windows/run-validation.R [--full] [--keep-dir=DIR]
#
# What it does (each step is recorded; a failing step does not stop the later ones):
#   1. records the environment (R, Rtools compiler, Windows version, file system of the temporary directory, whether
#      symbolic and hard links can be created);
#   2. builds and runs tools/validation/windows/fs-harness.cpp (the Win32 filesystem layer on its own);
#   3. installs rPSTool into a scratch library and runs the result-file test files with testthat (output and skips recorded);
#   4. with --full, runs the complete local gate (Rscript tools/ci/check-local.R), including R CMD check and the Windows skip
#      inventory check.
# Everything is written to a directory named windows-validation-<timestamp> (or --keep-dir); the file SUMMARY.txt there
# is the one-page result. Zip the directory and return it for review. Nothing outside that directory and the scratch
# library is modified.

args <- commandArgs(TRUE)
full <- "--full" %in% args
out <- sub("^--keep-dir=", "", grep("^--keep-dir=", args, value = TRUE))
if (!length(out)) out <- paste0("windows-validation-", format(Sys.time(), "%Y%m%d-%H%M%S"))
dir.create(out, showWarnings = FALSE, recursive = TRUE)
out <- normalizePath(out, winslash = "/")
stopifnot(file.exists("DESCRIPTION"), grepl("^Package: rPSTool", readLines("DESCRIPTION", 1L)))
root <- normalizePath(".", winslash = "/")
if (.Platform$OS.type != "windows") message("NOTE: this is not Windows; the script still runs, but it does not validate Windows.")

summary_lines <- character()
record <- function(step, ok, note = "") {
  line <- sprintf("%-4s %-46s %s", if (is.na(ok)) "N/A" else if (isTRUE(ok)) "PASS" else "FAIL", step, note)
  summary_lines <<- c(summary_lines, line)
  message(line)
  writeLines(summary_lines, file.path(out, "SUMMARY.txt"))
}
# Every argument is quoted here, and system2() quotes the command itself (paths such as C:/Users/First Last/... contain spaces); `raw` arguments are passed as they
# are (compiler flags that are several tokens, never paths).
run <- function(command, args, log, raw = character(), ...) {
  status <- suppressWarnings(system2(command, c(raw, vapply(args, shQuote, "")),
                                     stdout = file.path(out, log), stderr = file.path(out, log), ...))
  is.null(attr(status, "status")) && identical(as.integer(status), 0L)
}

# RPST_FULL_TESTS must reach the child process through its inherited environment: set it here for the duration of `code` and
# restore the previous value (or remove it) afterwards. (system2(env=) is not used: on Windows it is prepended to the command line.)
with_full_tests <- function(code) {
  old <- Sys.getenv("RPST_FULL_TESTS", NA_character_)
  on.exit(if (is.na(old)) Sys.unsetenv("RPST_FULL_TESTS") else Sys.setenv(RPST_FULL_TESTS = old), add = TRUE)
  Sys.setenv(RPST_FULL_TESTS = "true")
  force(code)
}

# ---- 1. environment ----------------------------------------------------------------------------------------------------
env <- c(
  paste("date:", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  paste("R:", R.version.string, "|", R.version$platform),
  paste("OS:", utils::sessionInfo()$running),
  paste("tempdir:", tempdir()),
  paste("UTF-8 session:", l10n_info()[["UTF-8"]]),
  paste("arrow:", tryCatch(as.character(packageVersion("arrow")), error = function(e) "NOT INSTALLED")),
  paste("sf:", tryCatch(as.character(packageVersion("sf")), error = function(e) "NOT INSTALLED")),
  paste("jsonlite:", tryCatch(as.character(packageVersion("jsonlite")), error = function(e) "NOT INSTALLED")),
  paste("testthat:", tryCatch(as.character(packageVersion("testthat")), error = function(e) "NOT INSTALLED")),
  paste("git commit:", tryCatch(system2("git", c("rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE), error = function(e) "unknown")))
cxx <- system2(file.path(R.home("bin"), "R"), c("CMD", "config", "CXX17"), stdout = TRUE, stderr = FALSE)
cxx_parts <- strsplit(trimws(cxx), "[[:space:]]+")[[1]]   # e.g. "g++ -std=gnu++17": the program, then flags
env <- c(env, paste("CXX17:", cxx), paste("compiler version:", tryCatch(suppressWarnings(system2(cxx_parts[1], "--version", stdout = TRUE, stderr = FALSE))[1], error = function(e) "unknown")))
probe <- tempfile("rpst-probe-"); dir.create(probe)
invisible(file.create(file.path(probe, "t")))
env <- c(env, paste("symbolic links can be created:", suppressWarnings(isTRUE(file.symlink(file.path(probe, "t"), file.path(probe, "s"))))),
         paste("hard links can be created:", suppressWarnings(isTRUE(file.link(file.path(probe, "t"), file.path(probe, "h"))))))
if (.Platform$OS.type == "windows") {
  vol <- tryCatch(system2("cmd", c("/c", "vol", sub("^(.:).*$", "\\1", normalizePath(tempdir()))), stdout = TRUE, stderr = FALSE), error = function(e) "")
  fsinfo <- tryCatch(system2("fsutil", c("fsinfo", "volumeinfo", sub("^(.:).*$", "\\1\\\\", normalizePath(tempdir()))), stdout = TRUE, stderr = FALSE), error = function(e) "fsutil unavailable (needs an elevated prompt)")
  env <- c(env, paste("volume:", paste(vol, collapse = " ")), paste("fsutil:", paste(fsinfo, collapse = " | ")))
}
unlink(probe, recursive = TRUE)
writeLines(env, file.path(out, "environment.txt"))
record("environment recorded", TRUE, "environment.txt")
if (!requireNamespace("arrow", quietly = TRUE) || packageVersion("arrow") < "25.0.0")
  record("arrow >= 25.0.0 present", FALSE, "Parquet, GeoParquet and the multi-radius Parquet tests will be skipped: install arrow first")

# ---- 2. filesystem layer on its own ----------------------------------------------------------------------------------------
exe <- file.path(out, if (.Platform$OS.type == "windows") "fs-harness.exe" else "fs-harness")
built <- run(cxx_parts[1], c(paste0("-I", file.path(root, "src")), file.path(root, "tools/validation/windows/fs-harness.cpp"), "-o", exe),
             "fs-harness-build.log", raw = c(cxx_parts[-1], "-std=c++17", "-O1", "-pthread"))
record("fs-harness builds", built, "fs-harness-build.log")
if (built) {
  work <- file.path(tempdir(), "fs-harness-work"); dir.create(work)
  ok <- run(exe, work, "fs-harness-run.log")
  record("fs-harness passes on this file system", ok, "fs-harness-run.log (see SKIP/INFO lines)")
  unlink(work, recursive = TRUE)
}

# ---- 3a. subprocess preflight: the helper launches R scripts and the child sees RPST_FULL_TESTS --------------------------------
# Runs before anything is installed, through the same helper as the test run, so a broken launch is reported as such rather than as
# an empty test log.
preflight_script <- file.path(out, "preflight.R")
writeLines(c("cat('RPST-PREFLIGHT-MARKER\n')",
             "cat(sprintf('RPST_FULL_TESTS=%s\n', Sys.getenv('RPST_FULL_TESTS', unset = '<unset>')))"), preflight_script)
preflight_exit <- with_full_tests(run(file.path(R.home("bin"), "Rscript"), preflight_script, "preflight.log"))
preflight_log <- if (file.exists(file.path(out, "preflight.log"))) readLines(file.path(out, "preflight.log"), warn = FALSE) else character()
preflight_ok <- preflight_exit && "RPST-PREFLIGHT-MARKER" %in% preflight_log && "RPST_FULL_TESTS=true" %in% preflight_log
record("subprocess preflight (launch, output, environment)", preflight_ok,
       if (preflight_ok) "preflight.log" else paste0("preflight.log: exit ", if (preflight_exit) "0" else "non-zero",
                                                        "; captured: ", paste(utils::head(preflight_log, 5L), collapse = " | ")))

# ---- 3. package install + result-file tests --------------------------------------------------------------------------------
lib <- file.path(tempdir(), "rpst-validation-lib"); dir.create(lib)
installed <- preflight_ok && run(file.path(R.home("bin"), "R"), c("CMD", "INSTALL", "--no-multiarch", paste0("--library=", lib), root), "install.log")
record("R CMD INSTALL", installed, if (preflight_ok) "install.log" else "not attempted: the subprocess preflight failed")
if (installed) {
  files <- c("test-result-publication.R", "test-result-file.R", "test-result-stream.R", "test-result-axial.R", "test-result-grouping.R",
             "test-result-masked-stream.R", "test-result-masked-analyses.R", "test-spatial-output.R", "test-multi-radius.R",
             "test-multi-radius-parquet.R", "test-multi-radius-direct.R", "test-angular-controls.R", "test-attraction-decay-default.R",
             "test-flatgeobuf.R", "test-geoparquet.R", "test-axial-file-input.R")
  # The only skips that may occur: on Windows exactly the approved inventory, elsewhere none. A skip for any other reason (for
  # example a missing arrow or sf) is a failure of the validation, not a note.
  permitted <- if (.Platform$OS.type == "windows") {
    inv <- read.delim("tools/ci/windows-test-skips.tsv", quote = "", comment.char = "", colClasses = "character", check.names = FALSE)
    paste(inv$file, inv$test, sep = "\t")
  } else character()
  script <- file.path(out, "run-tests.R")
  writeLines(c(sprintf(".libPaths(c(%s, .libPaths()))", deparse(lib)), "library(testthat); library(rPSTool)",
               "Sys.setenv(RPST_FULL_TESTS = 'true')",
               sprintf("files <- c(%s)", paste(deparse(files), collapse = "")),
               "for (f in files) {",
               sprintf("  r <- as.data.frame(testthat::test_file(file.path(%s, 'tests', 'testthat', f), reporter = 'summary', stop_on_failure = FALSE))", deparse(root)),
               "  cat(sprintf('RESULT\\t%s\\t%d\\t%d\\t%d\\t%d\\t%d\\n', f, nrow(r), sum(r$nb), sum(r$failed), sum(r$error), sum(r$skipped)))",
               "  for (i in which(r$skipped)) cat(sprintf('SKIPPED\\t%s\\t%s\\n', f, r$test[i]))",
               "}"), script)
  exit_ok <- with_full_tests(run(file.path(R.home("bin"), "Rscript"), script, "tests.log"))
  log <- readLines(file.path(out, "tests.log"), warn = FALSE)
  rows <- strsplit(grep("^RESULT\t", log, value = TRUE), "\t")
  results <- data.frame(file = vapply(rows, `[`, "", 2L), tests = as.integer(vapply(rows, `[`, "", 3L)),
                        expectations = as.integer(vapply(rows, `[`, "", 4L)), failed = as.integer(vapply(rows, `[`, "", 5L)),
                        errors = as.integer(vapply(rows, `[`, "", 6L)), skipped = as.integer(vapply(rows, `[`, "", 7L)))
  skips <- sub("^SKIPPED\t", "", grep("^SKIPPED\t", log, value = TRUE))
  unexpected <- setdiff(skips, permitted)
  missing_files <- setdiff(files, results$file)
  writeLines(c(sprintf("%-40s tests=%d expectations=%d failed=%d errors=%d skipped=%d", results$file, results$tests, results$expectations,
                       results$failed, results$errors, results$skipped),
               if (length(skips)) paste("SKIPPED:", gsub("\t", " :: ", skips))), file.path(out, "tests-summary.txt"))
  problems <- c(if (!exit_ok) "the test subprocess exited with a non-zero status",
                if (length(missing_files)) paste("no summary for:", paste(missing_files, collapse = ", ")),
                if (anyDuplicated(results$file)) "a file was reported twice",
                if (any(results$tests == 0L)) paste("no tests ran in:", paste(results$file[results$tests == 0L], collapse = ", ")),
                if (sum(results$failed) + sum(results$errors) > 0L) sprintf("%d failed expectations and %d errors", sum(results$failed), sum(results$errors)),
                if (length(unexpected)) paste("unexpected skips:", paste(gsub("\t", " :: ", unexpected), collapse = " | ")))
  record("result-file tests (all files, no failures, only permitted skips)", length(problems) == 0L,
         if (length(problems)) paste(problems, collapse = "; ") else
           sprintf("%d files, %d expectations, %d permitted skips; tests-summary.txt, tests.log", nrow(results), sum(results$expectations), length(skips)))
}

# ---- 4. full local gate ----------------------------------------------------------------------------------------------------
if (full) {
  gate <- run(file.path(R.home("bin"), "Rscript"), "tools/ci/check-local.R", "check-local.log")
  record("tools/ci/check-local.R (full gate)", gate, "check-local.log; logs of R CMD check are under .local/ci-check")
  if (dir.exists(".local/ci-check")) file.copy(".local/ci-check", out, recursive = TRUE)
} else record("full gate (tools/ci/check-local.R)", NA, "not requested (--full)")

message("\nReturn the directory '", out, "' (zip it). SUMMARY.txt lists every step.")
quit(status = if (any(grepl("^FAIL", summary_lines))) 1L else 0L)
