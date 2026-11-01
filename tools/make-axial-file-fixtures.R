#!/usr/bin/env Rscript
# Development-only generator (never run by the package or its tests) for the tiny
# FlatGeobuf fixtures behind axial_graph(<path>). Regenerate from the repository root with
#
#   Rscript tools/make-axial-file-fixtures.R tests/testthat/fixtures/axial-files
#   python3 tools/make-axial-parquet-fixtures.py tests/testthat/fixtures/axial-files   # needs pyarrow
#
# The line geometry of every non-indexed case comes from the direct pinned-PST axial reference fixture
# (tests/testthat/fixtures/axial-inputs-direct-v3.3.2.R), so each file reproduces a case whose lengths,
# crossings and integration scores PST itself produced. FlatGeobuf is written by GDAL via sf (the same writer as
# the segment-graph FlatGeobuf fixtures). `order-indexed.fgb` carries a spatial index, so GDAL stores it in Hilbert order; the
# generator searches for a layout whose T-junction pair is stored in the OPPOSITE order to the input order.
suppressMessages(library(sf))
out <- commandArgs(TRUE)[[1]]; dir.create(out, showWarnings = FALSE, recursive = TRUE)
ref <- dget("tests/testthat/fixtures/axial-inputs-direct-v3.3.2.R")
lines_of <- function(case) matrix(as.double(unlist(case$x)), ncol = 4L, byrow = TRUE)
as_sfc <- function(m, crs = 32630)
  st_sfc(lapply(seq_len(nrow(m)), function(i) st_linestring(rbind(m[i, 1:2], m[i, 3:4]))), crs = crs)
write_fgb <- function(m, name, index = FALSE, crs = 32630) {
  f <- file.path(out, paste0(name, ".fgb")); unlink(f)
  x <- st_sf(id = seq_len(nrow(m)), geometry = as_sfc(m, crs))
  suppressWarnings(suppressMessages(st_write(x, f, driver = "FlatGeobuf", quiet = TRUE,
                    layer_options = paste0("SPATIAL_INDEX=", if (index) "YES" else "NO"))))
}
rows <- list()
for (case in ref$cases) {
  if (!is.null(case$line_indices)) next               # indexed coordinate tables are not LineString files
  m <- lines_of(case)
  write_fgb(m, case$name)
  rows[[case$name]] <- data.frame(case = case$name, row = seq_len(nrow(m)), x1 = m[, 1], y1 = m[, 2], x2 = m[, 3], y2 = m[, 4])
}
# Order-sensitive layout: a T junction (A has the junction in its interior, B ends on it) plus filler lines.
# Input order is [A, B, fillers]; search for a filler layout whose Hilbert-ordered file puts B before A.
A <- c(0, 0, 100, 0); B <- c(40, 0, 40, 60)
found <- NULL
for (seed in 1:200) {
  set.seed(seed)
  fill <- cbind(runif(10, -400, 400), runif(10, -400, 400)); fill <- cbind(fill, fill + cbind(runif(10, 5, 60), runif(10, 5, 60)))
  m <- rbind(A, B, fill); rownames(m) <- NULL
  write_fgb(m, "order-indexed", index = TRUE)
  back <- st_read(file.path(out, "order-indexed.fgb"), quiet = TRUE)
  coords <- t(vapply(st_geometry(back), function(g) as.vector(t(unclass(g))), numeric(4)))
  pa <- which(apply(coords, 1, function(r) all(r == A))); pb <- which(apply(coords, 1, function(r) all(r == B)))
  if (pb < pa) { found <- m; break }
}
stopifnot(!is.null(found))
rows[["order-indexed"]] <- data.frame(case = "order-indexed", row = seq_len(nrow(found)), x1 = found[, 1], y1 = found[, 2], x2 = found[, 3], y2 = found[, 4])
csv <- do.call(rbind, rows)
for (v in c("x1", "y1", "x2", "y2")) csv[[v]] <- sprintf("%.17g", csv[[v]])   # exact binary64 round trip
write.csv(csv, file.path(out, "lines.csv"), row.names = FALSE, quote = FALSE)
cat("seed", seed, "\n")
