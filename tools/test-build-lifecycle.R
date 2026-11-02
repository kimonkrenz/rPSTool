#!/usr/bin/env Rscript
# Run on every CI OS: build, remove generated state, and load the installed DLL.
# Smoke test of the package installed in `lib` after native cleanup (never pkgload/load_all or the source tree).
smoke_installed_package <- function(lib) {
  stopifnot(!"pkgload" %in% loadedNamespaces(), !"devtools" %in% loadedNamespaces())
  ns <- asNamespace("rPSTool")
  stopifnot(identical(normalizePath(getNamespaceInfo(ns, "path"), winslash = "/"),
                      normalizePath(file.path(lib, "rPSTool"), winslash = "/")))
  dll <- getLoadedDLLs()[["rPSTool"]]
  # R installs the DLL in libs/ (Unix/macOS, empty r_arch) or libs/<r_arch>/ (Windows, e.g. libs/x64/).
  expected <- paste(c(lib, "rPSTool", "libs", if (nzchar(.Platform$r_arch)) .Platform$r_arch,
                      paste0("rPSTool", .Platform$dynlib.ext)), collapse = "/")
  stopifnot(identical(normalizePath(dll[["path"]], winslash = "/"), normalizePath(expected, winslash = "/")))
  call <- function(name, ...) .Call(get(paste0("C_rpst_", name), envir = ns), ...)
  native <- call("native_smoke")  # PST's own callback fixture through a registered routine
  stopifnot(identical(native[c(1L, 3L, 4L)], c(37L, 0L, -1L)), identical(native[[8L]], 1L))
  count <- function() call("result_counters")
  settle <- function() { invisible(gc()); invisible(gc()) }
  settle()
  before <- count()

  # Axial graph: construct, inspect, analyse, release explicitly and by GC.
  lines <- rbind(c(0, 0, 2, 0), c(1, -1, 1, 1))
  g <- rPSTool::axial_graph(lines)
  stopifnot(identical(g$n_lines, 2L), identical(g$n_crossings, 1L),
            identical(call("graph_info", g$ptr), c(2L, 1L, 0L, 0L)))
  integration <- rPSTool::network_integration(g, steps = 2L)
  stopifnot(identical(integration$nc_s_rs2, c(2L, 2L)), identical(integration$td_s_rs2, c(1, 1)))
  stopifnot(identical(rPSTool::network_integration(g, steps = 2L), integration))  # graph is reusable
  call("graph_release", g$ptr)
  call("graph_release", g$ptr)  # repeated release is a no-op
  stopifnot(inherits(try(rPSTool::network_integration(g, steps = 2L), silent = TRUE), "try-error"))
  rPSTool::axial_graph(lines)
  # Segment graph: a distinct native owner, analysed and released the same way.
  s <- rPSTool::segment_graph(rbind(c(0, 0, 3, 0), c(3, 0, 3, 3)))
  stopifnot(identical(s$n_segments, 2L), identical(call("segment_graph_info", s$ptr), 2L))
  angular <- rPSTool::angular_integration(s, steps = 2L)
  stopifnot(identical(angular$nc_a_rs2, c(2L, 2L)), identical(angular$ai_a_rs2_t, c(0.5, 0.5)))
  # Handles are not interchangeable between graph families.
  stopifnot(inherits(try(rPSTool::network_integration(s, steps = 2L), silent = TRUE), "try-error"),
            inherits(try(rPSTool::angular_integration(g, steps = 2L), silent = TRUE), "try-error"))
  call("segment_graph_release", s$ptr)
  call("segment_graph_release", s$ptr)
  rPSTool::segment_graph(rbind(c(0, 0, 3, 0), c(3, 0, 3, 3)))  # released by GC below

  # Result owner and Arrow C stream producer (synthetic table, scripted consumer; no `arrow` needed).
  rows <- 4L
  stream <- call("arrow_stream_new")
  call("result_test_export", stream, "id", c("score", "count"), c(0L, 1L),
       list(as.raw(rep_len(c(0x00, 0x00, 0x80, 0x3f), 4L * rows)), 1:rows), character(), character(),
       as.double(rows), 2, c(0L, -1L, 0L, -1L))
  ops <- matrix(c(3L, 0L,  3L, 1L,  3L, 2L,  6L, 0L,  4L, 0L,  5L, 0L), ncol = 2L, byrow = TRUE)
  res <- call("result_test_drive", stream, ops)
  stopifnot(identical(res[1:3], c(0, 0, 100)))  # two batches, then end of stream
  call("arrow_stream_free", stream)
  call("arrow_stream_free", stream)

  settle()
  after <- count()
  d <- after - before
  stopifnot(d[["tables_made"]] > 0, d[["streams_made"]] > 0,
            identical(unname(d[c("tables_made", "streams_made", "schemas_made", "batches_made", "children_made")]),
                      unname(d[c("tables_freed", "streams_released", "schemas_released", "batches_released",
                                 "children_released")])))
  message("Installed-package smoke test passed")
}

main <- function() {
  dir.create(".local", showWarnings = FALSE)
  lib <- file.path(".local", "lifecycle-library")
  dir.create(lib, recursive = TRUE, showWarnings = FALSE)
  # testthat changes working directories; lazy-load paths must stay absolute.
  lib <- normalizePath(lib, winslash = "/", mustWork = TRUE)
  r <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "R.exe" else "R")
  log <- file.path(".local", "lifecycle-install.log")
  status <- system2(r, c("CMD", "INSTALL", "--preclean", "--clean",
      shQuote(paste0("--library=", lib)), "."),
      stdout = log, stderr = log)
  if (status != 0L) {
    cat(readLines(log, warn = FALSE), sep = "\n")
    stop("Native installation/lifecycle test failed")
  }
  if (dir.exists("src/.rpst-build")) stop("R native cleanup left generated build state")
  library("rPSTool", lib.loc = lib, character.only = TRUE)
  # No build inputs/objects remain; the installed package must still run. The complete suite runs once, under
  # `R CMD check` (tools/ci/check-package.R); this is a short smoke test of the *installed* DLL only.
  smoke_installed_package(lib)
  env <- new.env(parent = baseenv())
  sys.source("src/portability/harden-isovist.R", envir = env)
  original <- "src/vendor/pstalgo/src/analyses/CalculateIsovists.cpp"
  copy <- "src/.rpst-build/analyses/CalculateIsovists.cpp"
  on.exit(unlink("src/.rpst-build", recursive = TRUE), add = TRUE)
  env$harden_isovist(original, copy)
  first <- unname(tools::md5sum(copy))
  unlink("src/.rpst-build", recursive = TRUE)
  env$harden_isovist(original, copy)
  stopifnot(identical(first, unname(tools::md5sum(copy))))
  sys.source("src/portability/harden-graph-constructors.R", envir = env)
  original <- "inst/upstream/build-inputs/CreateGraph.cpp"
  copy <- "src/.rpst-build/analyses/CreateGraph.cpp"
  env$harden_graph_constructors(original, copy)
  first <- unname(tools::md5sum(copy))
  unlink(copy)
  env$harden_graph_constructors(original, copy)
  stopifnot(identical(first, unname(tools::md5sum(copy))))
  sys.source("src/portability/limit-workers.R", envir = env)
  for (name in c("AngularChoiceAlgo", "SegmentBetweenness", "SegmentGroupIntegration","AttractionReach","AttractionDistance","ODBetweenness")) {
    original <- paste0("inst/upstream/build-inputs/", name, ".cpp")
    copy <- paste0("src/.rpst-build/analyses/", name, ".cpp")
    env$limit_workers(original, copy)
    first <- unname(tools::md5sum(copy))
    unlink(copy)
    env$limit_workers(original, copy)
    stopifnot(identical(first, unname(tools::md5sum(copy))))
  }
  sys.source("src/portability/harden-network-construction.R", envir = env)
  for (key in c("CreateJunctions","CreateSegmentMap")) {
    original <- paste0("inst/upstream/build-inputs/",key,".cpp")
    copy <- paste0("src/.rpst-build/analyses/",key,".cpp")
    env$harden_network_construction(original,copy)
    first <- unname(tools::md5sum(copy))
    unlink(copy)
    env$harden_network_construction(original,copy)
    stopifnot(identical(first,unname(tools::md5sum(copy))))
  }
  sys.source("src/portability/harden-raster.R", envir = env)
  for (key in c("CreateBufferPolygons.cpp","Raster.cpp","Blur.cpp","Arr2d.h")) {
    original <- file.path("inst/upstream/build-inputs",key)
    subdir <- switch(key,"CreateBufferPolygons.cpp"="analyses",
                     "Blur.cpp"="gfx","Arr2d.h"="include/pstalgo/utils","")
    copy <- file.path("src/.rpst-build",subdir,key)
    env$harden_raster(original,copy)
    first <- unname(tools::md5sum(copy));unlink(copy)
    env$harden_raster(original,copy)
    stopifnot(identical(first,unname(tools::md5sum(copy))))
  }
  sys.source("src/portability/fix-diagnostics.R", envir = env)
  diagnostic_copies <- c("Limits.cpp" = "", "ProgressUtil.cpp" = "", "NetworkIntegration.cpp" = "analyses",
                         "ShortestPathTraversal.cpp" = "experimental", "AABSPTree.cpp" = "geometry", "Geometry.cpp" = "geometry",
                         "SignedDistanceField.cpp" = "geometry", "AxialGraph.cpp" = "graph",
                         "IsovistCalculator.h" = "include-isovist/pstalgo/geometry")
  for (key in names(diagnostic_copies)) {
    original <- file.path("inst/upstream/build-inputs", key)
    copy <- file.path("src/.rpst-build", diagnostic_copies[[key]], key)
    env$fix_diagnostics(original, copy)
    first <- unname(tools::md5sum(copy)); unlink(copy)
    env$fix_diagnostics(original, copy)
    stopifnot(identical(first, unname(tools::md5sum(copy))))
  }
  sys.source("tools/verify-vendor.R", envir = new.env(parent = baseenv()))
  message("Build lifecycle passed: native clean install, DLL runs after cleanup, deterministic regeneration, pristine vendor")
}
# Keep ordinary console output intact and make CI failures reviewable through
# the check API as well as the full runner log/artifact.
run_lifecycle <- function() {
  dir.create(".local", showWarnings = FALSE)
  log_path <- ".local/lifecycle-test.log"
  connection <- file(log_path, open = "wt")
  sink(connection, split = TRUE)
  failure <- tryCatch({ main(); NULL }, error = identity)
  sink()
  close(connection)
  if (!is.null(failure)) {
    if (identical(Sys.getenv("GITHUB_ACTIONS"), "true")) {
      detail <- paste(tail(readLines(log_path, warn = FALSE), 120L), collapse = "\n")
      detail <- paste(conditionMessage(failure), detail, sep = "\n")
      detail <- gsub("%", "%25", detail, fixed = TRUE)
      detail <- gsub("\r", "%0D", detail, fixed = TRUE)
      detail <- gsub("\n", "%0A", detail, fixed = TRUE)
      cat("::error title=Native build lifecycle failure::", detail, "\n", sep = "")
    }
    stop(conditionMessage(failure), call. = FALSE)
  }
}
run_lifecycle()
