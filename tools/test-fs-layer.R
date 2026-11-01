#!/usr/bin/env Rscript
# Builds tools/validation/windows/fs-harness.cpp with the compiler R is configured with and runs it on a scratch directory: the
# POSIX (or Win32) filesystem layer behind result-file publication, without R and without arrow. Run from the repository root.
cxx <- system2(file.path(R.home("bin"), "R"), c("CMD", "config", "CXX17"), stdout = TRUE, stderr = FALSE)
cxx_parts <- strsplit(trimws(cxx), "[[:space:]]+")[[1]]   # e.g. "g++ -std=gnu++17": the program, then its flags
if (!length(cxx_parts) || !nzchar(cxx_parts[1])) stop("R reports no C++17 compiler (R CMD config CXX17)")
exe <- tempfile("fs-harness", fileext = if (.Platform$OS.type == "windows") ".exe" else "")
log <- tempfile(fileext = ".log")
work <- tempfile("fs-harness-work")
on.exit(unlink(c(exe, log, work), recursive = TRUE), add = TRUE)
# system2() quotes the program itself; each path argument is quoted here, and the output goes to a file through stdout/stderr
# (never through shell redirection text, which a Windows toolchain would receive as input file names).
status <- suppressWarnings(system2(cxx_parts[1],
  c(cxx_parts[-1], "-std=c++17", "-O1", "-pthread", shQuote(paste0("-I", normalizePath("src", winslash = "/"))),
    shQuote(normalizePath("tools/validation/windows/fs-harness.cpp", winslash = "/")), "-o", shQuote(exe)),
  stdout = log, stderr = log))
if (!identical(as.integer(status), 0L)) {
  detail <- if (file.exists(log)) readLines(log, warn = FALSE) else character()
  if (length(detail)) cat(detail, sep = "\n")
  stop("The filesystem harness did not compile (", cxx_parts[1], " exited with status ", status, if (!length(detail)) "; it wrote no output",
       ")", call. = FALSE)
}
dir.create(work)
out <- suppressWarnings(system2(exe, shQuote(work), stdout = TRUE, stderr = TRUE))
cat(out, sep = "\n")
if (!is.null(attr(out, "status")) || !any(grepl(" 0 failed", out))) stop("The filesystem harness reported failures")
cat("Filesystem layer test passed.\n")
