#!/usr/bin/env Rscript
# DEVELOPMENT-ONLY. Run the rPSTool side of cases/cases.json on the test GeoPackage and write one CSV per case.
# Usage: Rscript run-rpst-cases.R [--gpkg <dir>/data/pst-qgis-test.gpkg] [--out <dir>/rpst] [--cases cases/cases.json] [--case C01_...]
# Output: <out>/<case id>.csv with the id column (named as in the layer) followed by the columns named in the case's 'rpst' list.
# Needs rPSTool (installed), sf and jsonlite. The 'rpst' code in cases.json is the complete, reviewable statement of what rPSTool is asked to do.
suppressPackageStartupMessages({ library(rPSTool); library(sf); library(jsonlite) })
args <- commandArgs(trailingOnly = TRUE); opt <- list()
for (i in seq_len(length(args) %/% 2) * 2 - 1) opt[[sub("^--", "", args[i])]] <- args[i + 1]
here <- tryCatch(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))), error = function(e) ".")
gpkg <- opt[['gpkg']]; if (is.null(gpkg)) gpkg <- file.path(here, "data", "pst-qgis-test.gpkg")
out <- opt[['out']]; if (is.null(out)) out <- file.path(here, "rpst")
spec <- fromJSON(if (is.null(opt[['cases']])) file.path(here, "cases", "cases.json") else opt[['cases']], simplifyVector = FALSE)
if (!file.exists(gpkg)) stop("missing ", gpkg, "; run make-test-network.R first")
layers <- setNames(lapply(st_layers(gpkg)$name, function(l) st_read(gpkg, l, quiet = TRUE)), st_layers(gpkg)$name)
dir.create(out, showWarnings = FALSE, recursive = TRUE)
for (cs in spec$cases) {
  if (!is.null(opt[['case']]) && cs$id != opt[['case']]) next
  res <- eval(parse(text = cs$rpst), envir = list2env(list(layers = layers), parent = globalenv()))
  idf <- spec$id_fields[[cs$layer]]
  df <- data.frame(layers[[cs$layer]][[idf]], res, check.names = FALSE)
  names(df)[1] <- idf
  # write.csv would turn NaN into NA; keep NaN/Inf explicit and print finite values with 17 significant digits
  txt <- function(x) if (is.numeric(x)) ifelse(is.nan(x), "NaN", ifelse(is.na(x), "NA", ifelse(is.infinite(x), ifelse(x > 0, "Inf", "-Inf"), sprintf("%.17g", x)))) else as.character(x)
  write.csv(as.data.frame(lapply(df, txt), check.names = FALSE), file.path(out, paste0(cs$id, ".csv")), row.names = FALSE, quote = FALSE)
  cat(sprintf("%-48s %d rows, %d result columns -> %s\n", cs$id, nrow(df), length(res), file.path(out, paste0(cs$id, ".csv"))))
}
