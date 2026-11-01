#!/usr/bin/env Rscript
# compare-exports.R -- standalone comparison of a real PST-for-QGIS export with the rPSTool result for the same case.
#
# Usage:
#   Rscript compare-exports.R --qgis qgis-exports/C01.csv --rpst rpst/C01.csv --id seg_id [--columns ACwl,ACwlC] [--rtol 1e-6] [--atol 0]
#   Rscript compare-exports.R --qgis-dir qgis-exports --rpst-dir rpst --cases cases/cases.json      # every case with an export
#
# Inputs are CSV files (QGIS: right-click layer > Export > Save Features As > CSV; include the id field). Rows are matched by the
# id column, never by position. Compared columns: --columns, or every column of the rPSTool file except the id.
# Report, per case: rows missing on either side, duplicated ids, missing columns, non-finite values (NA/NaN/Inf, classified per side),
# and numerical differences (count, maximum absolute and relative difference, worst ids). Exit status: 0 only if everything matches
# within the stated tolerance; 1 on any finding; 2 for usage or file errors.
#
# Tolerance: relative |a-b| <= rtol*max(|a|,|b|) or absolute |a-b| <= atol. The default rtol = 1e-6 is deliberately above float32
# rounding (about 6e-8) because a CSV export may print fewer than the 9 digits that identify a float32; it is printed with every
# result, and the maximum observed relative difference is always reported, so a loose tolerance cannot hide a real discrepancy.
# Use --rtol 0 for exact comparison. A non-finite value matches only the same kind of non-finite value (NaN vs NaN, Inf vs Inf, NA vs NA);
# an empty field or the text NULL/NA in the QGIS export is read as NA, which is NOT equal to NaN.

parse_args <- function(args) {
  opt <- list(); i <- 1
  while (i <= length(args)) {
    if (!grepl("^--", args[i]) || i == length(args)) stop("usage error near ", args[i], call. = FALSE)
    opt[[sub("^--", "", args[i])]] <- args[i + 1]; i <- i + 2
  }
  opt
}
read_numeric <- function(path, id) {
  d <- read.csv(path, check.names = FALSE, na.strings = c("", "NA", "NULL", "null"), colClasses = "character", stringsAsFactors = FALSE)
  if (!id %in% names(d)) stop("id column '", id, "' not found in ", path, call. = FALSE)
  d
}
as_num <- function(x) suppressWarnings(as.numeric(x))   # "NaN", "Inf", "-Inf" parse; NA stays NA
# TRUE when the two paths are the same file or have identical bytes: that is an rPSTool self-comparison, not a QGIS result.
is_self_comparison <- function(q, r) {
  normalizePath(q) == normalizePath(r) || unname(tools::md5sum(q)) == unname(tools::md5sum(r))
}
kind <- function(v) ifelse(is.na(v) & !is.nan(v), "NA", ifelse(is.nan(v), "NaN", ifelse(is.infinite(v), ifelse(v > 0, "Inf", "-Inf"), "finite")))

#' Compare one case. Returns list(findings = character(), lines = character()).
compare_case <- function(qgis_path, rpst_path, id, columns = NULL, rtol = 1e-6, atol = 0) {
  q <- read_numeric(qgis_path, id); r <- read_numeric(rpst_path, id)
  lines <- character(); bad <- character()
  add <- function(msg, fail = TRUE) { lines <<- c(lines, msg); if (fail) bad <<- c(bad, msg) }
  qid <- q[[id]]; rid <- r[[id]]
  for (side in list(list("QGIS", qid), list("rPSTool", rid)))
    if (anyDuplicated(side[[2]])) add(sprintf("DUPLICATE ids in %s export: %s", side[[1]], paste(unique(side[[2]][duplicated(side[[2]])]), collapse = ",")))
  only_r <- setdiff(rid, qid); only_q <- setdiff(qid, rid)
  if (length(only_r)) add(sprintf("MISSING ROWS: %d id(s) present in rPSTool but absent from the QGIS export: %s", length(only_r), paste(head(only_r, 10), collapse = ",")))
  if (length(only_q)) add(sprintf("EXTRA ROWS: %d id(s) present in the QGIS export but absent from rPSTool: %s", length(only_q), paste(head(only_q, 10), collapse = ",")))
  if (is.null(columns)) columns <- setdiff(names(r), id)
  absent <- setdiff(columns, names(q)); absent_r <- setdiff(columns, names(r))
  if (length(absent)) add(sprintf("MISSING COLUMNS in QGIS export: %s (available: %s)", paste(absent, collapse = ","), paste(setdiff(names(q), id), collapse = ",")))
  if (length(absent_r)) add(sprintf("MISSING COLUMNS in rPSTool result: %s", paste(absent_r, collapse = ",")))
  common <- intersect(qid[!duplicated(qid)], rid[!duplicated(rid)])
  qi <- match(common, qid); ri <- match(common, rid)
  for (col in setdiff(columns, c(absent, absent_r))) {
    a <- as_num(q[[col]][qi]); b <- as_num(r[[col]][ri])
    ka <- kind(a); kb <- kind(b)
    # entries that are non-numeric text in the export (not NA-like) would be silently NA after parsing: flag them
    junk <- is.na(a) & !is.na(q[[col]][qi]) & !grepl("^\\s*-?nan\\s*$", q[[col]][qi], ignore.case = TRUE)
    if (any(junk)) add(sprintf("column %s: %d QGIS value(s) are not numeric text (e.g. '%s')", col, sum(junk), q[[col]][qi][which(junk)[1]]))
    nonfinite <- ka != "finite" | kb != "finite"
    mism_kind <- nonfinite & ka != kb
    if (any(mism_kind)) add(sprintf("column %s: %d row(s) differ in non-finite status (QGIS/rPSTool), e.g. id %s: %s / %s", col, sum(mism_kind), common[which(mism_kind)[1]], ka[which(mism_kind)[1]], kb[which(mism_kind)[1]]))
    if (any(nonfinite & ka == kb)) add(sprintf("column %s: %d row(s) non-finite in BOTH (same kind; informational: %s)", col, sum(nonfinite & ka == kb), paste(unique(ka[nonfinite & ka == kb]), collapse = ",")), fail = FALSE)
    both <- ka == "finite" & kb == "finite"
    if (any(both)) {
      d <- abs(a[both] - b[both]); sc <- pmax(abs(a[both]), abs(b[both]))
      rel <- ifelse(sc > 0, d / sc, 0)
      fail <- d > atol & rel > rtol
      worst <- which.max(rel)
      msg <- sprintf("column %s: %d finite pair(s); max abs diff %.3g, max rel diff %.3g (id %s: QGIS %.9g, rPSTool %.9g)",
                     col, sum(both), max(d), max(rel), common[both][worst], a[both][worst], b[both][worst])
      if (any(fail)) add(sprintf("DIFFERENCE %s; %d value(s) outside rtol=%g/atol=%g, first ids: %s", msg, sum(fail), rtol, atol,
                                 paste(head(common[both][fail], 5), collapse = ",")))
      else add(paste("ok:", msg), fail = FALSE)
    } else if (!any(nonfinite)) add(sprintf("column %s: no comparable rows", col))
  }
  list(findings = bad, lines = lines)
}

main <- function(args) {
  opt <- parse_args(args)
  rtol <- if (is.null(opt[["rtol"]])) 1e-6 else as.numeric(opt[["rtol"]]); atol <- if (is.null(opt[["atol"]])) 0 else as.numeric(opt[["atol"]])
  if (anyNA(c(rtol, atol)) || rtol < 0 || atol < 0) stop("rtol/atol must be non-negative numbers", call. = FALSE)
  jobs <- list()
  if (!is.null(opt[["qgis"]])) {
    if (is.null(opt[["rpst"]]) || is.null(opt[["id"]])) stop("--qgis needs --rpst and --id", call. = FALSE)
    jobs[[1]] <- list(name = basename(opt[["qgis"]]), q = opt[["qgis"]], r = opt[["rpst"]], id = opt[["id"]],
                      cols = if (is.null(opt[["columns"]])) NULL else strsplit(opt[["columns"]], ",")[[1]])
  } else if (!is.null(opt[["qgis-dir"]])) {
    if (!requireNamespace("jsonlite", quietly = TRUE)) stop("--qgis-dir needs jsonlite", call. = FALSE)
    spec <- jsonlite::fromJSON(opt[["cases"]], simplifyVector = FALSE)
    for (cs in spec$cases) {
      qp <- file.path(opt[["qgis-dir"]], paste0(cs$id, ".csv"))
      jobs[[length(jobs) + 1]] <- list(name = cs$id, q = qp, r = file.path(opt[["rpst-dir"]], paste0(cs$id, ".csv")),
                                       id = spec$id_fields[[cs$layer]], cols = NULL)
    }
  } else stop("give --qgis/--rpst/--id or --qgis-dir/--rpst-dir/--cases", call. = FALSE)
  failures <- 0L; compared <- 0L
  cat(sprintf("Tolerance: rtol=%g atol=%g (max observed differences are always printed)\n", rtol, atol))
  for (j in jobs) {
    cat("\n== ", j$name, "\n", sep = "")
    if (!file.exists(j$r)) { cat("  rPSTool result file missing: ", j$r, "\n", sep = ""); failures <- failures + 1L; next }
    if (!file.exists(j$q)) { cat("  NOT RUN: no QGIS export at ", j$q, " (not counted as a pass)\n", sep = ""); failures <- failures + 1L; next }
    if (is_self_comparison(j$q, j$r)) {
      cat("  SELF-COMPARISON: the 'QGIS' file is the rPSTool file or has identical bytes. This is not QGIS evidence (not counted as compared).\n")
      failures <- failures + 1L; next
    }
    res <- compare_case(j$q, j$r, j$id, j$cols, rtol, atol); compared <- compared + 1L
    cat(paste0("  ", res$lines, collapse = "\n"), "\n", sep = "")
    cat(if (length(res$findings)) sprintf("  RESULT: FAIL (%d finding(s))\n", length(res$findings)) else "  RESULT: PASS\n")
    if (length(res$findings)) failures <- failures + 1L
  }
  cat(sprintf("\n%d case(s) compared, %d with findings or not run\n", compared, failures))
  cat("Evidence level of a PASS here is Q only if the QGIS export came from a real QGIS run recorded per GUI-PROCEDURE.md.\n")
  quit(status = if (failures) 1L else 0L)
}
if (sys.nframe() == 0L && !interactive() && !identical(Sys.getenv("PST_COMPARE_NO_MAIN"), "1")) {
  tryCatch(main(commandArgs(trailingOnly = TRUE)), error = function(e) { message("error: ", conditionMessage(e)); quit(status = 2L) })
}
