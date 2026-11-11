#!/usr/bin/env Rscript
# Offline integrity check, run from the repository root before R CMD build.
inventory <- utils::read.table("inst/upstream/FILES.md5", col.names = c("md5", "path"),
                        colClasses = "character", quote = "", comment.char = "")
if (anyDuplicated(inventory$path) || !nrow(inventory)) stop("Invalid inventory")
if (!all(file.exists(inventory$path))) stop("Missing vendored/provenance file")
actual <- unname(tools::md5sum(inventory$path))
if (!identical(actual, inventory$md5)) stop("Vendored content differs from upstream inventory")
root <- "src/vendor/pstalgo"
files <- list.files(root, recursive = TRUE, all.files = TRUE, no.. = TRUE)
expected <- sub(paste0("^", root, "/"), "", inventory$path[startsWith(
  inventory$path, paste0(root, "/"))])
if (!identical(sort(files), sort(expected))) stop("Vendor file set differs from inventory")
if (any(grepl("(^|/)(python|pstqgis)(/|$)|[.]py$", files))) {
  stop("Forbidden Python/QGIS content")
}
preserved_input <- "inst/upstream/build-inputs/CalculateIsovists.cpp"
original_input <- "src/vendor/pstalgo/src/analyses/CalculateIsovists.cpp"
read_bytes <- function(path) readBin(path, "raw", n = file.info(path)$size)
if (!file.exists(preserved_input) ||
    !identical(read_bytes(preserved_input), read_bytes(original_input))) {
  stop("Preserved packaging input differs from pristine upstream source")
}
message("Verified ", length(files), " pristine vendor files and upstream provenance (offline)")

sources <- inventory$path[grepl("[.]cpp$", inventory$path)]
expected_objects <- c("init.o", "native-smoke.o", "pst-graph.o", "pst-geoparquet.o", "pst-flatgeobuf.o", "pst-result-stream.o", "pst-output-file.o", "pst-arrow-test-stream.o", "pst-construction.o", "pst-isovist.o", "pst-raster.o", "rpst-workers.o", "pst-progress.o", sub("[.]cpp$", ".o",
    sub("^src/vendor/pstalgo/src/", ".rpst-build/", sources)))
for (makevars in c("src/Makevars", "src/Makevars.win")) {
  lines <- readLines(makevars)
  start <- grep("^OBJECTS =", lines)
  end <- which(seq_along(lines) > start & lines == "")[[1L]]
  object_text <- paste(lines[start:(end - 1L)], collapse = " ")
  listed <- regmatches(object_text, gregexpr("[A-Za-z0-9_./-]+[.]o", object_text))[[1L]]
  if (!identical(sort(listed), sort(expected_objects))) {
    stop("Incomplete or duplicate object list in ", makevars)
  }
}
message("Verified complete native object lists on Unix and Windows")

# Validate the exact combined qualification/safety copy without repairing drift.
verify_isovist_copy <- function() {
  tmp <- tempfile("verify-isovist-", tmpdir = ".local")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  env <- new.env(parent = baseenv())
  sys.source("src/portability/harden-isovist.R", envir = env)
  expected <- file.path(tmp, ".rpst-build", "CalculateIsovists.cpp")
  env$harden_isovist(preserved_input, expected)
  copy <- "src/.rpst-build/analyses/CalculateIsovists.cpp"
  if (file.exists(copy) && !identical(read_bytes(copy), read_bytes(expected)))
    stop("Unexpected isovist build-copy changes")
  for (makevars in c("src/Makevars", "src/Makevars.win")) {
    text <- paste(readLines(makevars), collapse="\n")
    if (!grepl("portability/harden-isovist.R ../inst/upstream/build-inputs/CalculateIsovists.cpp .rpst-build/analyses/CalculateIsovists.cpp", text, fixed=TRUE) ||
        !grepl("-c .rpst-build/analyses/CalculateIsovists.cpp -o $@", text, fixed=TRUE) ||
        grepl("-c vendor/pstalgo/src/analyses/CalculateIsovists.cpp", text, fixed=TRUE))
      stop("Isovist generation/compilation recipe drift")
  }
}
dir.create(".local", showWarnings=FALSE)
verify_isovist_copy()
message("Verified exact reversible isovist safety/qualification copy and both build recipes")

# Task 005A: exact preserved input, verified RAII copy, and both build recipes.
graph_input <- "inst/upstream/build-inputs/CreateGraph.cpp"
graph_original <- "src/vendor/pstalgo/src/analyses/CreateGraph.cpp"
graph_copy <- "src/.rpst-build/analyses/CreateGraph.cpp"
if (!file.exists(graph_input) ||
    !identical(read_bytes(graph_input), read_bytes(graph_original)) ||
    !identical(unname(tools::md5sum(graph_input)), "0aea4b5325e2d3177ae91d2008da4f55")) {
  stop("Preserved graph constructor input differs from pinned upstream source")
}
# Exercise the transformer even when no generated copy exists. Never repair
# existing build state here: verification must reject any drift in that copy.
verify_graph_copy <- function() {
  dir.create(".local", showWarnings = FALSE)
  tmp <- tempfile("verify-graph-", tmpdir = ".local")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  expected <- file.path(tmp, ".rpst-build", "analyses", "CreateGraph.cpp")
  env <- new.env(parent = baseenv())
  sys.source("src/portability/harden-graph-constructors.R", envir = env)
  env$harden_graph_constructors(graph_input, expected)
  if (!identical(unname(tools::md5sum(expected)), "6ae192582ff4bafaf7f03a189c7c10f5") ||
      (file.exists(graph_copy) && !identical(read_bytes(graph_copy), read_bytes(expected)))) {
    stop("Unexpected graph constructor build-copy changes")
  }
}
verify_graph_copy()
recipe <- c(
  ".rpst-build/analyses/CreateGraph.cpp: vendor/pstalgo/src/analyses/CreateGraph.cpp ../inst/upstream/build-inputs/CreateGraph.cpp portability/harden-graph-constructors.R rpst-prepare",
  "\tmkdir -p .rpst-build/analyses",
  "\t\"$(R_HOME)/bin$(R_ARCH_BIN)/Rscript\" portability/harden-graph-constructors.R ../inst/upstream/build-inputs/CreateGraph.cpp .rpst-build/analyses/CreateGraph.cpp",
  "",
  ".rpst-build/analyses/CreateGraph.o: .rpst-build/analyses/CreateGraph.cpp",
  "\tmkdir -p .rpst-build/analyses",
  "\t$(CXX) $(ALL_CPPFLAGS) $(ALL_CXXFLAGS) $(RPST_FP_FLAGS) -c .rpst-build/analyses/CreateGraph.cpp -o $@"
)
for (makevars in c("src/Makevars", "src/Makevars.win")) {
  lines <- readLines(makevars)
  start <- which(lines == recipe[[1L]])
  if (length(start) != 1L ||
      !identical(lines[start + seq_along(recipe) - 1L], recipe) ||
      !identical(lines[grepl("CreateGraph[.]cpp|CreateGraph[.]o:", lines)],
                 recipe[c(1L, 3L, 5L, 7L)])) {
    stop("Graph constructor generation/compilation recipe drift in ", makevars)
  }
}
message("Verified exact graph constructor RAII transformation and Unix/Windows build recipes")

verify_worker_copies <- function() {
  dir.create(".local", showWarnings=FALSE)
  tmp <- tempfile("verify-workers-",tmpdir=".local")
  on.exit(unlink(tmp,recursive=TRUE),add=TRUE)
  env <- new.env(parent=baseenv())
  sys.source("src/portability/limit-workers.R",envir=env)
  for (name in c("AngularChoiceAlgo","SegmentBetweenness","SegmentGroupIntegration","AttractionReach","AttractionDistance","ODBetweenness")) {
    original <- paste0("src/vendor/pstalgo/src/analyses/",name,".cpp")
    input <- paste0("inst/upstream/build-inputs/",name,".cpp")
    copy <- paste0("src/.rpst-build/analyses/",name,".cpp")
    expected <- file.path(tmp,".rpst-build",paste0(name,".cpp"))
    if (!file.exists(input) || !identical(read_bytes(original),read_bytes(input)))
      stop("Preserved worker input differs from pinned source")
    env$limit_workers(input,expected)
    if (file.exists(copy) && !identical(read_bytes(copy),read_bytes(expected)))
      stop("Unexpected worker build-copy changes")
    recipe <- c(
      paste0(".rpst-build/analyses/",name,".cpp: vendor/pstalgo/src/analyses/",name,".cpp ../inst/upstream/build-inputs/",name,".cpp portability/limit-workers.R rpst-prepare"),
      "\tmkdir -p .rpst-build/analyses",
      paste0('\t"$(R_HOME)/bin$(R_ARCH_BIN)/Rscript" portability/limit-workers.R ../inst/upstream/build-inputs/',name,'.cpp .rpst-build/analyses/',name,'.cpp'),
      "",
      paste0(".rpst-build/analyses/",name,".o: .rpst-build/analyses/",name,".cpp"),
      "\tmkdir -p .rpst-build/analyses",
      paste0("\t$(CXX) $(ALL_CPPFLAGS) $(ALL_CXXFLAGS) $(RPST_FP_FLAGS) -c .rpst-build/analyses/",name,".cpp -o $@"))
    for (makevars in c("src/Makevars","src/Makevars.win")) {
      lines <- readLines(makevars)
      start <- which(lines==recipe[[1L]])
      if (length(start)!=1L || !identical(lines[start+seq_along(recipe)-1L],recipe) ||
          !identical(lines[grepl(paste0("/",name,"[.]cpp|/",name,"[.]o:"),lines)],recipe[c(1L,3L,5L,7L)]))
        stop("Worker generation/compilation recipe drift in ",makevars)
    }
  }
}
verify_worker_copies()
message("Verified central worker transformations, preserved inputs and Unix/Windows recipes")

# Construction: preserved raw inputs, exact reversible safety copies and recipes.
verify_construction_copies <- function() {
  tmp <- tempfile("verify-construction-",tmpdir=".local")
  on.exit(unlink(tmp,recursive=TRUE),add=TRUE)
  env <- new.env(parent=baseenv())
  sys.source("src/portability/harden-network-construction.R",envir=env)
  for (key in c("CreateJunctions","CreateSegmentMap")) {
    input <- paste0("inst/upstream/build-inputs/",key,".cpp")
    vendor <- paste0("src/vendor/pstalgo/src/analyses/",key,".cpp")
    if (!identical(read_bytes(input),read_bytes(vendor))) stop("Preserved construction input drift")
    expected <- file.path(tmp,".rpst-build","analyses",paste0(key,".cpp"))
    env$harden_network_construction(input,expected)
    copy <- paste0("src/.rpst-build/analyses/",key,".cpp")
    if (file.exists(copy) && !identical(read_bytes(copy),read_bytes(expected)))
      stop("Unexpected construction build-copy changes")
    for (makevars in c("src/Makevars","src/Makevars.win")) {
      text <- paste(readLines(makevars),collapse="\n")
      recipe <- paste0('portability/harden-network-construction.R ../',input,' .rpst-build/analyses/',key,'.cpp')
      compile <- paste0('-c .rpst-build/analyses/',key,'.cpp -o $@')
      if (!grepl(recipe,text,fixed=TRUE) || !grepl(compile,text,fixed=TRUE) ||
          grepl(paste0('-c vendor/pstalgo/src/analyses/',key,'.cpp'),text,fixed=TRUE))
        stop("Construction generation/compilation recipe drift")
    }
  }
}
verify_construction_copies()
message("Verified construction safety copies, preserved inputs and Unix/Windows recipes")

# Raster allocations and blur workers are transformed only in verified build copies.
verify_raster_copies <- function() {
  env <- new.env(parent=baseenv())
  sys.source("src/portability/harden-raster.R",envir=env)
  tmp <- tempfile("verify-raster-",tmpdir=".local")
  on.exit(unlink(tmp,recursive=TRUE),add=TRUE)
  sources <- c("CreateBufferPolygons.cpp"="src/vendor/pstalgo/src/analyses/CreateBufferPolygons.cpp", "Raster.cpp"="src/vendor/pstalgo/src/Raster.cpp",
               "Blur.cpp"="src/vendor/pstalgo/src/gfx/Blur.cpp",
               "Arr2d.h"="src/vendor/pstalgo/include/pstalgo/utils/Arr2d.h")
  copies <- c("CreateBufferPolygons.cpp"="src/.rpst-build/analyses/CreateBufferPolygons.cpp", "Raster.cpp"="src/.rpst-build/Raster.cpp",
              "Blur.cpp"="src/.rpst-build/gfx/Blur.cpp",
              "Arr2d.h"="src/.rpst-build/include/pstalgo/utils/Arr2d.h")
  for (key in names(sources)) {
    input <- file.path("inst/upstream/build-inputs",key)
    if (!identical(read_bytes(input),read_bytes(sources[[key]])))
      stop("Preserved raster input differs from pristine upstream source")
    expected <- file.path(tmp,".rpst-build",key)
    env$harden_raster(input,expected)
    if (file.exists(copies[[key]]) && !identical(read_bytes(copies[[key]]),read_bytes(expected)))
      stop("Unexpected raster build-copy changes")
    for (makevars in c("src/Makevars","src/Makevars.win")) {
      text <- paste(readLines(makevars),collapse="\n")
      recipe <- paste("portability/harden-raster.R",paste0("../",input),sub("^src/","",copies[[key]]))
      if (!grepl(recipe,text,fixed=TRUE)) stop("Raster generation recipe drift")
      if (key!="Arr2d.h" && (!grepl(paste("-c",sub("^src/","",copies[[key]]),"-o $@"),text,fixed=TRUE) ||
          grepl(paste("-c",sub("^src/","",sources[[key]])),text,fixed=TRUE)))
        stop("Raster compilation recipe drift")
      if (key=="Arr2d.h" && (!grepl("$(CXX) -I.rpst-build/include $(ALL_CPPFLAGS)",text,fixed=TRUE) ||
          !grepl("CreateBufferPolygons.cpp .rpst-build/include/pstalgo/utils/Arr2d.h",text,fixed=TRUE)))
        stop("Raster FlipY header selection drift")
    }
  }
}
verify_raster_copies()
message("Verified exact raster allocation/kernel/worker safety copies and both build recipes")

# Deterministic floating-point evaluation policy (-ffp-contract=off, eight-name
# float-overload header with static_asserts) in both build files.
sys.source("tools/fp-policy.R", envir = (fp_env <- new.env(parent = baseenv())))
for (makevars in c("src/Makevars", "src/Makevars.win")) {
  violations <- fp_env$fp_policy_violations(readLines(makevars), readLines("src/rpst-float-overloads.h"), makevars)
  if (length(violations)) stop(paste(violations, collapse = "\n"))
}
message("Verified deterministic floating-point policy: -ffp-contract=off on every compile rule, eight-name float-overload header")

# CRAN-significant diagnostic fixes live only in verified, reversible build copies.
verify_diagnostic_copies <- function() {
  env <- new.env(parent = baseenv())
  sys.source("src/portability/fix-diagnostics.R", envir = env)
  tmp <- tempfile("verify-diagnostics-", tmpdir = ".local")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  # key -> c(vendor path, generated copy path, directory of the copy), all relative to src/
  families <- list(
    "Limits.cpp" = c("vendor/pstalgo/src/Limits.cpp", ".rpst-build/Limits.cpp"),
    "ProgressUtil.cpp" = c("vendor/pstalgo/src/ProgressUtil.cpp", ".rpst-build/ProgressUtil.cpp"),
    "NetworkIntegration.cpp" = c("vendor/pstalgo/src/analyses/NetworkIntegration.cpp", ".rpst-build/analyses/NetworkIntegration.cpp"),
    "ShortestPathTraversal.cpp" = c("vendor/pstalgo/src/experimental/ShortestPathTraversal.cpp", ".rpst-build/experimental/ShortestPathTraversal.cpp"),
    "AABSPTree.cpp" = c("vendor/pstalgo/src/geometry/AABSPTree.cpp", ".rpst-build/geometry/AABSPTree.cpp"),
    "Geometry.cpp" = c("vendor/pstalgo/src/geometry/Geometry.cpp", ".rpst-build/geometry/Geometry.cpp"),
    "SignedDistanceField.cpp" = c("vendor/pstalgo/src/geometry/SignedDistanceField.cpp", ".rpst-build/geometry/SignedDistanceField.cpp"),
    "AxialGraph.cpp" = c("vendor/pstalgo/src/graph/AxialGraph.cpp", ".rpst-build/graph/AxialGraph.cpp"),
    "IsovistCalculator.h" = c("vendor/pstalgo/include/pstalgo/geometry/IsovistCalculator.h",
                              ".rpst-build/include-isovist/pstalgo/geometry/IsovistCalculator.h"))
  for (key in names(families)) {
    input <- file.path("inst/upstream/build-inputs", key)
    vendor <- file.path("src", families[[key]][[1L]])
    copy <- file.path("src", families[[key]][[2L]])
    if (!identical(read_bytes(input), read_bytes(vendor)))
      stop("Preserved diagnostic input differs from pristine upstream source: ", key)
    expected <- file.path(tmp, ".rpst-build", key)
    env$fix_diagnostics(input, expected)
    if (file.exists(copy) && !identical(read_bytes(copy), read_bytes(expected)))
      stop("Unexpected diagnostic build-copy changes: ", key)
    generate <- paste0("portability/fix-diagnostics.R ../", input, " ", families[[key]][[2L]])
    for (makevars in c("src/Makevars", "src/Makevars.win")) {
      lines <- readLines(makevars)
      rule <- paste0(families[[key]][[2L]], ": ", families[[key]][[1L]], " ../", input,
                     " portability/fix-diagnostics.R rpst-prepare")
      at <- which(lines == rule)
      if (length(at) != 1L ||
          !identical(lines[at + 2L], paste0('\t"$(R_HOME)/bin$(R_ARCH_BIN)/Rscript" ', generate)))
        stop("Diagnostic generation recipe drift for ", key, " in ", makevars)
      if (key != "IsovistCalculator.h") {
        object <- sub("[.]cpp$", ".o", families[[key]][[2L]])
        compile <- paste0("-c ", families[[key]][[2L]], " -o $@")
        compile_at <- which(lines == paste0(object, ": ", families[[key]][[2L]]))
        if (length(compile_at) != 1L || !endsWith(lines[compile_at + 2L], compile) ||
            grepl(paste0("-c ", families[[key]][[1L]]), paste(lines, collapse = "\n"), fixed = TRUE))
          stop("Diagnostic compilation recipe drift for ", key, " in ", makevars)
      }
    }
  }
  for (makevars in c("src/Makevars", "src/Makevars.win")) {
    text <- readLines(makevars)
    if (any(grepl("-Icompat", text, fixed = TRUE)) || dir.exists("src/compat"))
      stop("The Maths.h include-case shim (-Icompat, src/compat) must stay removed")
    for (object in c(".rpst-build/analyses/CalculateIsovists.o", ".rpst-build/geometry/IsovistCalculator.o")) {
      line <- text[startsWith(text, paste0("\t$(CXX) -I.rpst-build/include-isovist $(ALL_CPPFLAGS)")) &
                     grepl(sub("[.]o$", ".cpp", sub("^[.]rpst-build/(analyses|geometry)/", "", object)), text, fixed = TRUE)]
      if (length(line) != 1L) stop("Isovist overlay include drift for ", object, " in ", makevars)
    }
    if (sum(grepl("-Ivendor/pstalgo/src $(ALL_CPPFLAGS)", text, fixed = TRUE)) != 1L)
      stop("ProgressUtil generated-copy include drift in ", makevars)
  }
}
verify_diagnostic_copies()
message("Verified diagnostic build copies, preserved inputs, shim removal and Unix/Windows recipes")

# Patch 0012: the SphereTree radius query fix lives only in a verified, reversible build copy (docs: inst/upstream/PATCHES.md).
verify_sphere_tree_copy <- function() {
  env <- new.env(parent = baseenv())
  sys.source("src/portability/fix-sphere-tree.R", envir = env)
  input <- "inst/upstream/build-inputs/SphereTree.cpp"
  vendor <- "src/vendor/pstalgo/src/utils/SphereTree.cpp"
  copy <- "src/.rpst-build/utils/SphereTree.cpp"
  if (!identical(read_bytes(input), read_bytes(vendor)))
    stop("Preserved SphereTree input differs from pristine upstream source")
  tmp <- tempfile("verify-sphere-tree-", tmpdir = ".local")
  dir.create(".local", showWarnings = FALSE)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  expected <- file.path(tmp, ".rpst-build", "SphereTree.cpp")
  env$fix_sphere_tree(input, expected)
  if (file.exists(copy) && !identical(read_bytes(copy), read_bytes(expected)))
    stop("Unexpected SphereTree build-copy changes")
  # the copy differs from the pristine file only by the added #line prefix and the one-expression fix
  lines <- strsplit(rawToChar(read_bytes(expected)), "\n", fixed = TRUE)[[1L]]
  pristine <- strsplit(rawToChar(read_bytes(vendor)), "\n", fixed = TRUE)[[1L]]
  changed <- which(lines[-1L] != pristine)
  if (length(lines) != length(pristine) + 1L || length(changed) != 1L ||
      !identical(pristine[changed], "\treturn nResult;") || !identical(lines[changed + 1L], "\treturn count;"))
    stop("The SphereTree copy changes more than the intended expression")
  generate <- "portability/fix-sphere-tree.R ../inst/upstream/build-inputs/SphereTree.cpp .rpst-build/utils/SphereTree.cpp"
  for (makevars in c("src/Makevars", "src/Makevars.win")) {
    text <- readLines(makevars)
    rule <- ".rpst-build/utils/SphereTree.cpp: vendor/pstalgo/src/utils/SphereTree.cpp ../inst/upstream/build-inputs/SphereTree.cpp portability/fix-sphere-tree.R rpst-prepare"
    at <- which(text == rule)
    object <- which(text == ".rpst-build/utils/SphereTree.o: .rpst-build/utils/SphereTree.cpp")
    if (length(at) != 1L || !identical(text[at + 2L], paste0('\t"$(R_HOME)/bin$(R_ARCH_BIN)/Rscript" ', generate)) ||
        length(object) != 1L || !grepl("-c .rpst-build/utils/SphereTree.cpp -o $@", text[object + 2L], fixed = TRUE) ||
        any(grepl("-c vendor/pstalgo/src/utils/SphereTree.cpp", text, fixed = TRUE)))
      stop("SphereTree generation/compilation recipe drift in ", makevars)
  }
}
verify_sphere_tree_copy()
message("Verified the SphereTree radius-query correction copy, preserved input and Unix/Windows recipes")
