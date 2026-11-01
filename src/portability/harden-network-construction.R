# Build-only safety guards for exact pinned PST construction sources.
harden_network_construction <- function(source_file, output_file) {
  key <- sub("[.]cpp$", "", basename(source_file))
  checksums <- list(
    CreateJunctions = c("f73b874843ccf5e16524d9a72ecf4d6d", "3e5712f2cd08fd5eda64edf0a0d61eff"),
    CreateSegmentMap = c("b530a721b7d0351fdadd099d893a8546", "98c988a98f1587bf431e120436563827"))
  if (!(key %in% names(checksums))) stop("Unsupported network construction source")
  original_md5 <- checksums[[key]][[1L]]
  hardened_md5 <- checksums[[key]][[2L]]
  if (key == "CreateJunctions") {
    old <- c("\t\t// Process unlinks",
      "\t\tstd::sort(pts.begin(), pts.end()")
    new <- c("\t\tif (m_Points.size() > 0x7FFFFFFFu)\n\t\t\tthrow std::runtime_error(\"CreateJunctions: too many output points\");\n#line 75 \"vendor/pstalgo/src/analyses/CreateJunctions.cpp\"\n\t\t// Process unlinks",
      "\t\tif (pts.size() > 0xFFFFFFFFull)\n\t\t\tthrow std::runtime_error(\"CreateJunctions: too many raw intersection points\");\n#line 230 \"vendor/pstalgo/src/analyses/CreateJunctions.cpp\"\n\t\tstd::sort(pts.begin(), pts.end()")
  }
  else if (key == "CreateSegmentMap") {
    old <- c("\t\t\tFindCuts(lines.data(), (unsigned int)lines.size(), desc.m_ExtrudeCut, cuts, progress);",
      "\t\t\t\t// Merge")
    new <- c("\t\t\tFindCuts(lines.data(), (unsigned int)lines.size(), desc.m_ExtrudeCut, cuts, progress);\n\t\t\tif (cuts.size() > 0x7FFFFFFFull ||\n\t\t\t\t(EPSTARoadNetworkType_RoadCenterLines != desc.m_RoadNetworkType && lines.size() * 2ull + cuts.size() >= 0x80000000ull))\n\t\t\t\tthrow std::runtime_error(\"CreateSegmentMap: too many native points\");\n#line 184 \"vendor/pstalgo/src/analyses/CreateSegmentMap.cpp\"",
      "\t\t\t\tif (p2_index == s0.m_P0)\n\t\t\t\t\tthrow std::runtime_error(\"CreateSegmentMap: unsafe cyclic detail reduction\");\n#line 717 \"vendor/pstalgo/src/analyses/CreateSegmentMap.cpp\"\n\t\t\t\t// Merge")
  }
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
  prefix <- paste0('#include <stdexcept>\n#line 1 "vendor/pstalgo/src/analyses/', key, '.cpp"\n')
  transformed <- paste0(prefix, transformed)
  # Undo the documented edits and diagnostic prefix, demanding complete original bytes.
  restored <- substring(transformed, nchar(prefix) + 1L)
  for (i in rev(seq_along(old))) {
    if (count(new[[i]], restored) != 1L) stop("Unexpected intended edit count")
    restored <- sub(new[[i]], old[[i]], restored, fixed = TRUE)
  }
  if (!identical(charToRaw(restored), original)) {
    stop("Network construction transformation changed more than the intended edits")
  }
  # Output is restricted to generated build state, never the vendor tree.
  portable_path <- gsub("\\", "/", output_file, fixed = TRUE)
  if (!grepl("(^|/)[.]rpst-build/", portable_path) ||
      basename(output_file) != paste0(key, ".cpp")) {
    stop("Output must be a generated .rpst-build network construction copy")
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
  candidate <- tempfile("network-safety-", tmpdir = dirname(output_file))
  on.exit(unlink(candidate), add = TRUE)
  bytes <- charToRaw(transformed)
  writeBin(bytes, candidate)
  if (!identical(read_bytes(candidate), bytes) ||
      !identical(unname(tools::md5sum(candidate)), hardened_md5) ||
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
  if (length(args) != 2L) stop("Usage: harden-network-construction.R original generated-copy")
  harden_network_construction(args[[1L]], args[[2L]])
}
