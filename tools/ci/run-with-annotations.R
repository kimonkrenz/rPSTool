#!/usr/bin/env Rscript
# Preserve the complete child output and exit status; also expose failures in
# check annotations when runner-log storage is unavailable to an API client.
args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) stop("Usage: run-with-annotations.R script [arguments]")
rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
log <- tempfile("rpst-ci-command-", fileext = ".log")
status <- system2(rscript, shQuote(args), stdout = log, stderr = log)
lines <- readLines(log, warn = FALSE)
unlink(log)
cat(lines, sep = "\n")
if (status != 0L && identical(Sys.getenv("GITHUB_ACTIONS"), "true")) {
  detail <- paste(tail(lines, 180L), collapse = "\n")
  # GitHub truncates command annotations; put the actual final error first.
  detail <- substring(detail, max(1L, nchar(detail) - 3400L + 1L))
  detail <- gsub("%", "%25", detail, fixed = TRUE)
  detail <- gsub("\r", "%0D", detail, fixed = TRUE)
  detail <- gsub("\n", "%0A", detail, fixed = TRUE)
  cat("\n::error title=Strict package check failure::", detail, "\n", sep = "")
}
quit(status = status)
