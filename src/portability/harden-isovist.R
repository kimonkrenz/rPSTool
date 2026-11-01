# Verified type qualification and approved post-calculation memory-safety guards.
harden_isovist <- function(source_file, output_file) {
  original_md5 <- "42c16aa243ccc11e2b2e95692407ebb7"
  hardened_md5 <- "fd1f956a159c1d136bae53acf75227bc"
  old <- c("\t\tResult& Result() { return m_Result; }",
    "\n\tauto resultRef = std::make_unique<ResultRef>(*this, m_ResultPool.Borrow());",
    "\t\t\tif (!m_TempAttrEdgeQueue.empty())\n\t\t\t{",
    "\t\t\tif (!m_TempAttrPointCalc.empty())\n\t\t\t{",
    "\t\t\t\t\t\t: m_Points(points)\n\t\t\t\t\t\t, m_IsLoop(isLoop)\n\t\t\t\t\t\t, m_FovDiamondAngle0(fov_diamond_angle_0)\n\t\t\t\t\t\t, m_At(0)")
  new <- c("\t\tCIsovistContext::Result& Result() { return m_Result; }",
    "\n\t// Safety only: fail before accessing an insufficient calculated vertex array.\n\tauto require_isovist_points = [&](size_t minimum)\n\t{\n\t\tif (isovist_points.size() < minimum)\n\t\t{\n\t\t\tm_LocalIsovistPool.Return(std::move(isovist_points));\n\t\t\tthrow std::runtime_error(\"Isovist has too few points for native access\");\n\t\t}\n\t};\n\trequire_isovist_points(1);\n#line 514 \"vendor/pstalgo/src/analyses/CalculateIsovists.cpp\"\n\n\tauto resultRef = std::make_unique<ResultRef>(*this, m_ResultPool.Borrow());",
    "\t\t\tif (!m_TempAttrEdgeQueue.empty())\n\t\t\t{\n\t\t\t\tif (desc.m_FieldOfViewDegrees < 360)\n\t\t\t\t\trequire_isovist_points(3);\n\t\t\t\telse\n\t\t\t\t\trequire_isovist_points(2);\n#line 745 \"vendor/pstalgo/src/analyses/CalculateIsovists.cpp\"",
    "\t\t\tif (!m_TempAttrPointCalc.empty())\n\t\t\t{\n\t\t\t\tif (desc.m_FieldOfViewDegrees < 360)\n\t\t\t\t\trequire_isovist_points(2);\n#line 616 \"vendor/pstalgo/src/analyses/CalculateIsovists.cpp\"",
    "\t\t\t\t\t\t: m_IsLoop(isLoop)\n\t\t\t\t\t\t, m_FovDiamondAngle0(fov_diamond_angle_0)\n\t\t\t\t\t\t, m_At(0)\n\t\t\t\t\t\t, m_Points(points)")
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
  prefix <- "#include <stdexcept>\n#line 1 \"vendor/pstalgo/src/analyses/CalculateIsovists.cpp\"\n"
  transformed <- paste0(prefix, transformed)
  # Undo the documented edits and diagnostic prefix, demanding complete original bytes.
  restored <- substring(transformed, nchar(prefix) + 1L)
  for (i in rev(seq_along(old))) {
    if (count(new[[i]], restored) != 1L) stop("Unexpected intended edit count")
    restored <- sub(new[[i]], old[[i]], restored, fixed = TRUE)
  }
  if (!identical(charToRaw(restored), original)) {
    stop("Isovist transformation changed more than the intended edits")
  }
  # Output is restricted to generated build state, never the vendor tree.
  portable_path <- gsub("\\", "/", output_file, fixed = TRUE)
  if (!grepl("(^|/)[.]rpst-build/", portable_path) ||
      basename(output_file) != "CalculateIsovists.cpp") {
    stop("Output must be a generated .rpst-build isovist copy")
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
  candidate <- tempfile("isovist-safety-", tmpdir = dirname(output_file))
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
  if (length(args) != 2L) stop("Usage: harden-isovist.R original generated-copy")
  harden_isovist(args[[1L]], args[[2L]])
}
