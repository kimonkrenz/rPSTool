#!/usr/bin/env Rscript
# Development-only JSON -> deterministic static R fixture; no runtime Python.
args <- commandArgs(trailingOnly=TRUE)
if(length(args)!=2L)stop("Usage: write-r-fixture.R OUTPUT_JSON FIXTURE_R")
reference <- jsonlite::fromJSON(args[[1L]],simplifyVector=FALSE)
stopifnot(identical(reference$pst_commit,"63df80a2cf3dd289be95ea3d91667c3490719b75"))
writeLines(sub("[ \t]+$","",capture.output(dput(reference, control=c("keepNA","keepInteger","niceNames","showAttributes","hexNumeric")))),args[[2L]],useBytes=TRUE)
