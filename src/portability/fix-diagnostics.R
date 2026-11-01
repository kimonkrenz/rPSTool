# Verified, semantics-preserving build copies that remove the compiler diagnostics R CMD check reports as significant
# (-Wswitch, -Wbitwise-instead-of-logical, -Wreorder, -Wclass-memaccess) and the include-spelling of Geometry.cpp
# (docs/build-and-platforms.md; patch 0011 in inst/upstream/PATCHES.md). No arithmetic, comparison, evaluation order, enum mapping, memory layout
# or object lifetime changes: every edit is a cast, an explicit empty `case`, a permutation of a mem-initializer list that
# already executes in declaration order, or a lowercase include spelling. Every edit stays on its own line, so the line
# numbers of the pinned source (kept through #line 1) and of all other diagnostics do not move.
fix_diagnostics <- function(source_file, output_file) {
  specifications <- list(
    "Limits.cpp" = list(path = "src/Limits.cpp", original = "199550e4110215e07a8ecb586a91ea5c", fixed = "9141bd3c5e7ba646df0c81173bca7c72",
      old = c("\tcase DIST_AXMETER: return EPSTADistanceType_Axmeter;",
              "\tcase EPSTADistanceType_Axmeter: return DIST_AXMETER;"),
      new = c("\tcase DIST_AXMETER: return EPSTADistanceType_Axmeter; case _DIST_COUNT: break;",
              "\tcase EPSTADistanceType_Axmeter: return DIST_AXMETER; case EPSTADistanceType_Weights: break;")),
    "ProgressUtil.cpp" = list(path = "src/ProgressUtil.cpp", original = "7267986bf47780d4bbfa94553ec4f231", fixed = "afb57f9342358c33d8a3bed02aaab813",
      old = c("\t, m_MinFilterIntervalMSec(min_progress_interval_ms)\n\t, m_Progress(0)\n\t, m_Cancel(false)"),
      new = c("\t, m_Progress(0)\n\t, m_Cancel(false)\n\t, m_MinFilterIntervalMSec(min_progress_interval_ms)")),
    "AABSPTree.cpp" = list(path = "src/geometry/AABSPTree.cpp", original = "d834bf5274a74b61eaa9876ed07a1490", fixed = "2e6282e00e69ef91736df2b6f15684ad",
      old = c("\t: m_Nodes(std::move(other.m_Nodes))\n\t, m_BB(other.m_BB)"),
      new = c("\t: m_BB(other.m_BB)\n\t, m_Nodes(std::move(other.m_Nodes))")),
    "SignedDistanceField.cpp" = list(path = "src/geometry/SignedDistanceField.cpp", original = "0a8942a1868d72cc7ad52d92bb73cafd", fixed = "8cec4ab9c78d746857e7b25036a9c0ed",
      old = c("return ((pos.x < sdf.Width()) & (pos.y < sdf.Height())) ? sdf.at(pos.x, pos.y) : 0; // std::numeric_limits<float>::max();\n\t\t};\n\n\t\tconst auto testInRange",
              "return ((x < sdf.Width()) & (y < sdf.Height())) && testInRange(sdf.at(x, y));",
              "if ((x >= sdf.Width()) | (y >= sdf.Height()))",
              "return (sdf.at(x, y) >= range_min) & (sdf.at(x, y) < range_max);"),
      new = c("return ((int)(pos.x < sdf.Width()) & (int)(pos.y < sdf.Height())) ? sdf.at(pos.x, pos.y) : 0; // std::numeric_limits<float>::max();\n\t\t};\n\n\t\tconst auto testInRange",
              "return ((int)(x < sdf.Width()) & (int)(y < sdf.Height())) && testInRange(sdf.at(x, y));",
              "if ((int)(x >= sdf.Width()) | (int)(y >= sdf.Height()))",
              "return (int)(sdf.at(x, y) >= range_min) & (int)(sdf.at(x, y) < range_max);")),
    "ShortestPathTraversal.cpp" = list(path = "src/experimental/ShortestPathTraversal.cpp", original = "1a4093aa7fa0508e44356ed4fc77f813", fixed = "70903d9e6a44683706beee1ae130ff37",
      old = c("\t\t\t, m_VisitedNodes(graph.NetworkNodeCount())\n\t\t\t, m_NodeStates(graph.NetworkNodeCount())"),
      new = c("\t\t\t, m_NodeStates(graph.NetworkNodeCount())\n\t\t\t, m_VisitedNodes(graph.NetworkNodeCount())")),
    "NetworkIntegration.cpp" = list(path = "src/analyses/NetworkIntegration.cpp", original = "5f58c8cf6279a2c1dcaaf8cd637749fe", fixed = "4d8fdb209ea95e16c1c569b55c81b22f",
      old = c("memset(desc->m_OutJunctionCoords, 0,"),
      new = c("memset((void*)desc->m_OutJunctionCoords, 0,")),
    "AxialGraph.cpp" = list(path = "src/graph/AxialGraph.cpp", original = "8b72e64b2721ed2a53b7c9fe07511de4", fixed = "1a2c23b55c8cd3ebfda7a7209f4f55e3",
      old = c("memset(&m_lines.front(), 0,", "memset(&m_points.front(), 0,"),
      new = c("memset((void*)&m_lines.front(), 0,", "memset((void*)&m_points.front(), 0,")),
    "Geometry.cpp" = list(path = "src/geometry/Geometry.cpp", original = "2e33fab7ee47fe92b1cf148b1522b4b8", fixed = "b9aff27c96b4a9a538f7ebc0e31231da",
      old = c("#include <pstalgo/Maths.h>"),
      new = c("#include <pstalgo/maths.h>")),
    "IsovistCalculator.h" = list(path = "include/pstalgo/geometry/IsovistCalculator.h", original = "138e76cac9a4b608dad8f9fd7830a263", fixed = "55f6d9bae92db7da3b227194c095230d",
      old = c("\t\t\t: m_EdgeIndexAndEndBit(edge_index | ((uint32_t)is_end_point << 31)), Angle(angle) {}"),
      new = c("\t\t\t: Angle(angle), m_EdgeIndexAndEndBit(edge_index | ((uint32_t)is_end_point << 31)) {}"))
  )
  key <- basename(source_file)
  if (!(key %in% names(specifications))) stop("Unsupported diagnostic source")
  spec <- specifications[[key]]
  original_md5 <- spec$original; fixed_md5 <- spec$fixed
  old <- spec$old; new <- spec$new
  read_bytes <- function(path) readBin(path, "raw", n = file.info(path)$size)
  if (!file.exists(source_file) ||
      !identical(unname(tools::md5sum(source_file)), original_md5)) {
    stop("PST source does not match the pinned original checksum")
  }
  original <- read_bytes(source_file)
  text <- rawToChar(original)
  count <- function(pattern, text) {
    matches <- gregexpr(pattern, text, fixed = TRUE)[[1L]]
    if (matches[[1L]] == -1L) 0L else length(matches)
  }
  transformed <- text
  for (i in seq_along(old)) {
    if (count(old[[i]], transformed) != 1L || count(new[[i]], transformed) != 0L) {
      stop("Expected exactly one original pattern and no transformed pattern: ", i)
    }
    transformed <- sub(old[[i]], new[[i]], transformed, fixed = TRUE)
  }
  prefix <- paste0("#line 1 \"vendor/pstalgo/", spec$path, "\"\n")
  transformed <- paste0(prefix, transformed)
  # Every edit keeps its line count, so source locations of the pinned file stay exact.
  if (lengths(regmatches(transformed, gregexpr("\n", transformed, fixed = TRUE))) !=
      lengths(regmatches(text, gregexpr("\n", text, fixed = TRUE))) + 1L) {
    stop("A diagnostic fix changed the line count")
  }
  # Undo the documented edits and diagnostic prefix, demanding complete original bytes.
  restored <- substring(transformed, nchar(prefix) + 1L)
  for (i in rev(seq_along(old))) {
    if (count(new[[i]], restored) != 1L) stop("Unexpected intended edit count")
    restored <- sub(new[[i]], old[[i]], restored, fixed = TRUE)
  }
  if (!identical(charToRaw(restored), original)) {
    stop("Diagnostic transformation changed more than the intended edits")
  }
  # Output is restricted to generated build state, never the vendor tree.
  portable_path <- gsub("\\", "/", output_file, fixed = TRUE)
  if (!grepl("(^|/)[.]rpst-build/", portable_path) || basename(output_file) != key) {
    stop("Output must be a generated .rpst-build diagnostic copy")
  }
  # Resolve existing ancestors before creating directories, so a symlink
  # cannot redirect even directory creation into the pristine vendor tree.
  parent <- dirname(output_file)
  missing <- character()
  while (!dir.exists(parent)) {
    missing <- c(basename(parent), missing)
    next_parent <- dirname(parent)
    if (identical(next_parent, parent)) stop("Cannot resolve output directory")
    parent <- next_parent
  }
  resolved <- do.call(file.path, as.list(c(
      normalizePath(parent, winslash = "/"), missing, basename(output_file))))
  if (grepl("/vendor/pstalgo/", resolved, fixed = TRUE) ||
      identical(normalizePath(source_file, winslash = "/"), resolved)) {
    stop("Refusing to write into the vendor tree")
  }
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  candidate <- tempfile("diagnostic-fix-", tmpdir = dirname(output_file))
  on.exit(unlink(candidate), add = TRUE)
  bytes <- charToRaw(transformed)
  writeBin(bytes, candidate)
  if (!identical(read_bytes(candidate), bytes) ||
      !identical(unname(tools::md5sum(candidate)), fixed_md5) ||
      !identical(read_bytes(source_file), original)) {
    stop("Generated copy or original source failed verification")
  }
  if (file.exists(output_file) && identical(read_bytes(output_file), bytes)) {
    return(invisible(output_file))
  }
  if (file.exists(output_file) && unlink(output_file) != 0L) {
    stop("Cannot replace the generated build copy")
  }
  if (!file.rename(candidate, output_file)) stop("Cannot publish the verified build copy")
  invisible(output_file)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) != 2L) stop("Usage: fix-diagnostics.R original generated-copy")
  fix_diagnostics(args[[1L]], args[[2L]])
}
