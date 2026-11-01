#!/usr/bin/env Rscript
# Exact, reversible, fail-closed diagnostic build copies (src/portability/fix-diagnostics.R)
# and their wiring (tools/verify-vendor.R: verify_diagnostic_copies).
main <- function() {
  env <- new.env(parent = baseenv())
  sys.source("src/portability/fix-diagnostics.R", envir = env)
  fix <- env$fix_diagnostics
  read_bytes <- function(path) readBin(path, "raw", n = file.info(path)$size)
  dir.create(".local", showWarnings = FALSE)
  tmp <- tempfile("diagnostic-fixes-", tmpdir = ".local")
  dir.create(tmp); on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  rejects <- function(expr, pattern) {
    err <- tryCatch({force(expr); NULL}, error = identity)
    if (!inherits(err, "error") || !grepl(pattern, conditionMessage(err), fixed = TRUE))
      stop("Expected ", pattern, "; got ", if (is.null(err)) "success" else conditionMessage(err))
  }
  vendor <- c(
    "Limits.cpp" = "src/Limits.cpp", "ProgressUtil.cpp" = "src/ProgressUtil.cpp",
    "AABSPTree.cpp" = "src/geometry/AABSPTree.cpp", "SignedDistanceField.cpp" = "src/geometry/SignedDistanceField.cpp",
    "ShortestPathTraversal.cpp" = "src/experimental/ShortestPathTraversal.cpp",
    "NetworkIntegration.cpp" = "src/analyses/NetworkIntegration.cpp", "AxialGraph.cpp" = "src/graph/AxialGraph.cpp",
    "Geometry.cpp" = "src/geometry/Geometry.cpp", "IsovistCalculator.h" = "include/pstalgo/geometry/IsovistCalculator.h")
  clone <- function(from, to) {   # owned clone of the function with one statement replaced, to exercise one gate alone
    body_text <- paste(deparse(body(fix), width.cutoff = 500L), collapse = "\n")
    stopifnot(grepl(from, body_text, fixed = TRUE))
    mutated <- fix
    body(mutated) <- parse(text = sub(from, to, body_text, fixed = TRUE))[[1L]]
    mutated
  }
  unchecked <- clone("!identical(unname(tools::md5sum(source_file)), original_md5)", "FALSE")
  wrong_fixed <- clone("fixed_md5 <- spec$fixed", 'fixed_md5 <- "00000000000000000000000000000000"')
  for (key in names(vendor)) {
    original <- file.path("inst/upstream/build-inputs", key)
    pristine <- file.path("src/vendor/pstalgo", vendor[[key]])
    bytes <- read_bytes(original)
    stopifnot(identical(bytes, read_bytes(pristine)))              # preserved input == pinned vendor bytes
    output <- file.path(tmp, ".rpst-build", key)
    fix(original, output); expected <- read_bytes(output)
    fix(original, output); stopifnot(identical(expected, read_bytes(output)))          # deterministic
    writeBin(charToRaw("corrupt generated state"), output)
    fix(original, output); stopifnot(identical(expected, read_bytes(output)))          # drift repaired
    # one #line prefix, the same number of lines otherwise, and only a handful of touched lines
    out_lines <- strsplit(rawToChar(expected), "\n", fixed = TRUE)[[1L]]
    in_lines <- strsplit(rawToChar(bytes), "\n", fixed = TRUE)[[1L]]
    stopifnot(startsWith(out_lines[[1L]], "#line 1 \"vendor/pstalgo/"), length(out_lines) - 1L == length(in_lines))
    changed <- sum(out_lines[-1L] != in_lines)
    stopifnot(changed >= 1L, changed <= 8L)
    # checksum gate: edited, already-fixed and truncated inputs are rejected and leave everything untouched
    input <- file.path(tmp, key)
    for (mutation in list(c(bytes, charToRaw("\n")), expected, bytes[-1L])) {
      writeBin(mutation, input)
      rejects(fix(input, output), "pinned original checksum")
      stopifnot(identical(expected, read_bytes(output)), identical(bytes, read_bytes(original)))
    }
    unlink(output)
    rejects(fix(input, output), "pinned original checksum"); stopifnot(!file.exists(output))
    # pattern gate, independent of the checksum: a drifted (absent or duplicated) target is never edited
    text <- rawToChar(bytes)
    for (drifted in c("// unrelated\n", paste0(text, text), sub("^#line [^\n]*\n", "", rawToChar(expected)))) {
      writeBin(charToRaw(drifted), input)
      rejects(unchecked(input, output), "Expected exactly one original pattern")
      stopifnot(!file.exists(output))
    }
    # result checksum gate and output guards
    rejects(wrong_fixed(original, output), "Generated copy or original source failed verification")
    stopifnot(!file.exists(output), !length(list.files(dirname(output))))
    rejects(fix(original, original), "Output must be")
    rejects(fix(original, file.path(tmp, "vendor", "pstalgo", ".rpst-build", key)), "Refusing to write into the vendor tree")
    stopifnot(!dir.exists(file.path(tmp, "vendor")))
    if (.Platform$OS.type != "windows") {
      alias <- file.path(tmp, "alias", ".rpst-build"); dir.create(dirname(alias), showWarnings = FALSE)
      stopifnot(file.symlink(normalizePath("src/vendor/pstalgo"), alias))
      rejects(fix(original, file.path(alias, "forbidden-diagnostics", key)), "Refusing to write into the vendor tree")
      stopifnot(!dir.exists("src/vendor/pstalgo/forbidden-diagnostics")); unlink(alias)
    }
  }
  rejects(fix(file.path(tmp, "NotListed.cpp"), file.path(tmp, ".rpst-build", "NotListed.cpp")), "Unsupported diagnostic source")

  # Semantic guards on the exact approved edits (no arithmetic, evaluation order or layout change).
  generated <- function(key) rawToChar(read_bytes({o <- file.path(tmp, ".rpst-build", key); fix(file.path("inst/upstream/build-inputs", key), o); o}))
  initializer_lists <- list(
    "ProgressUtil.cpp" = "\t, m_Progress(0)\n\t, m_Cancel(false)\n\t, m_MinFilterIntervalMSec(min_progress_interval_ms)",
    "AABSPTree.cpp" = "\t: m_BB(other.m_BB)\n\t, m_Nodes(std::move(other.m_Nodes))",
    "ShortestPathTraversal.cpp" = "\t\t\t, m_NodeStates(graph.NetworkNodeCount())\n\t\t\t, m_VisitedNodes(graph.NetworkNodeCount())",
    "IsovistCalculator.h" = ": Angle(angle), m_EdgeIndexAndEndBit(edge_index | ((uint32_t)is_end_point << 31)) {}")
  for (key in names(initializer_lists))
    stopifnot(grepl(initializer_lists[[key]], generated(key), fixed = TRUE))   # declaration order, initializer expressions unchanged
  stopifnot(grepl("case _DIST_COUNT: break;", generated("Limits.cpp"), fixed = TRUE),
            grepl("case EPSTADistanceType_Weights: break;", generated("Limits.cpp"), fixed = TRUE),
            sum(gregexpr("memset((void*)", generated("AxialGraph.cpp"), fixed = TRUE)[[1L]] > 0L) == 2L,
            grepl("memset((void*)desc->m_OutJunctionCoords, 0,", generated("NetworkIntegration.cpp"), fixed = TRUE),
            grepl("#include <pstalgo/maths.h>", generated("Geometry.cpp"), fixed = TRUE),
            !grepl("Maths.h", generated("Geometry.cpp"), fixed = TRUE),
            sum(gregexpr("(int)(", generated("SignedDistanceField.cpp"), fixed = TRUE)[[1L]] > 0L) >= 8L)

  # Wiring verification fails closed on generated drift and on recipe drift in both build files.
  verifier <- new.env(parent = baseenv())
  sys.source("tools/verify-vendor.R", envir = verifier)
  with_mutation <- function(path, bytes, action) {
    existed <- file.exists(path)
    previous <- if (existed) read_bytes(path) else NULL
    on.exit(if (existed) writeBin(previous, path) else unlink(path), add = TRUE)
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    writeBin(bytes, path); force(action)
  }
  for (path in c("src/.rpst-build/Limits.cpp", "src/.rpst-build/geometry/Geometry.cpp",
                 "src/.rpst-build/include-isovist/pstalgo/geometry/IsovistCalculator.h")) {
    if (!file.exists(path)) next   # present after a build; absent copies are regenerated by make, never repaired here
    with_mutation(path, charToRaw("generated drift"), {
      rejects(verifier$verify_diagnostic_copies(), "Unexpected diagnostic build-copy changes")
      stopifnot(identical(read_bytes(path), charToRaw("generated drift")))
    })
  }
  for (path in c("src/Makevars", "src/Makevars.win")) {
    makevars <- rawToChar(read_bytes(path))
    for (pattern in c("portability/fix-diagnostics.R ../inst/upstream/build-inputs/Limits.cpp .rpst-build/Limits.cpp",
                      "-c .rpst-build/geometry/SignedDistanceField.cpp -o $@",
                      "-c .rpst-build/graph/AxialGraph.cpp -o $@",
                      "$(CXX) -I.rpst-build/include-isovist $(ALL_CPPFLAGS) $(ALL_CXXFLAGS) $(RPST_FP_FLAGS) -c .rpst-build/analyses/CalculateIsovists.cpp",
                      "-Ivendor/pstalgo/src $(ALL_CPPFLAGS)")) {
      stopifnot(grepl(pattern, makevars, fixed = TRUE))
      with_mutation(path, charToRaw(sub(pattern, "invalid recipe", makevars, fixed = TRUE)),
                    rejects(verifier$verify_diagnostic_copies(), "drift"))
    }
    with_mutation(path, charToRaw(sub("PKG_CPPFLAGS = ", "PKG_CPPFLAGS = -Icompat ", makevars, fixed = TRUE)),
                  rejects(verifier$verify_diagnostic_copies(), "must stay removed"))
  }
  dir.create("src/compat", showWarnings = FALSE)
  rejects(verifier$verify_diagnostic_copies(), "must stay removed"); unlink("src/compat", recursive = TRUE)
  message("Diagnostic fix transformations passed: exact/reversible checksums, deterministic regeneration, ",
          "drift/path/symlink rejection, semantic edit guards, recipe/shim wiring")
}
main()
