#!/usr/bin/env Rscript
# Developer check (not a CI gate): compile each rPSTool-owned C++ unit with the compiler and flags that R is configured
# with (R CMD config) plus -Wall, and report every diagnostic that does not come from the pristine vendor tree.
# It takes minutes instead of the hour of a full `R CMD check`, and uses the platform's own warning set
# (Rtools GCC on Windows, Apple clang on macOS), so it reproduces what the strict validator would reject.
# Run from the repository root:   Rscript tools/check-wrapper-warnings.R [unit ...]
# Exit status 1 if an rPSTool-owned warning or a compile error is found. Units needing generated build copies
# (pst-flatgeobuf) are not compiled here.
args <- commandArgs(trailingOnly = TRUE)
r <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "R.exe" else "R")
config <- function(...) {
  out <- suppressWarnings(system2(r, c("CMD", "config", ...), stdout = TRUE, stderr = FALSE))
  Filter(nzchar, strsplit(trimws(paste(out, collapse = " ")), "[[:space:]]+")[[1L]])
}
cxx <- config("CXX17")
if (!length(cxx)) stop("R CMD config CXX17 returned no compiler")
flags <- c(config("CXX17STD"), config("CXX17FLAGS"), config("--cppflags"))
units <- c("native-smoke", "pst-construction", "pst-graph", "pst-geoparquet", "pst-result-stream", "pst-output-file",
           "pst-arrow-test-stream", "pst-isovist", "pst-raster", "rpst-workers", "pst-progress")
if (length(args)) units <- args
package_flags <- c("-pthread", "-ffp-contract=off", "-Ivendor/pstalgo/include", "-Ivendor/pstalgo/src/analyses",
                   "-include", "rpst-float-overloads.h", "-include", "rpst-compat.h")
object <- tempfile(fileext = ".o"); on.exit(unlink(object), add = TRUE)
setwd("src")
problems <- character()
for (unit in units) {
  source <- paste0(unit, ".cpp")
  if (!file.exists(source)) stop("no such unit: src/", source)
  log <- tempfile(fileext = ".log")
  status <- system2(cxx[[1L]], c(cxx[-1L], flags, if (!any(grepl("^-Wall$", flags))) "-Wall", package_flags,
                                 "-c", source, "-o", shQuote(object)), stdout = log, stderr = log)
  diagnostics <- gsub("\\\\", "/", readLines(log, warn = FALSE)); unlink(log)
  found <- grep("(warning|error):", diagnostics, value = TRUE)
  ours <- found[!grepl("^(\\./)?(vendor|\\.rpst-build)/", found) & !grepl("^[A-Za-z]:/.*/(vendor|\\.rpst-build)/", found)]
  if (status != 0L || length(ours)) problems <- c(problems, paste0(unit, ": ", if (status != 0L) "compile failed; " else "", length(ours), " rPSTool-source diagnostics"), ours)
  message(sprintf("%-22s %s", unit, if (status == 0L && !length(ours)) "clean" else "DIAGNOSTICS"))
}
if (length(problems)) { cat(problems, sep = "\n"); quit(status = 1L) }
message("No rPSTool-owned compiler warnings (vendor diagnostics are governed by the exact inventories).")
