# Build-only portability transformation for the exact pinned PST source.
qualify_isovist <- function(source_file, output_file) {
  original_md5 <- "42c16aa243ccc11e2b2e95692407ebb7"
  qualified_md5 <- "a98b22b9a2f066e734ffc8a51fe35974"
  old_line <- "\t\tResult& Result() { return m_Result; }"
  new_line <- "\t\tCIsovistContext::Result& Result() { return m_Result; }"
  read_bytes <- function(path) readBin(path, "raw", n = file.info(path)$size)
  if (!file.exists(source_file) ||
      !identical(unname(tools::md5sum(source_file)), original_md5)) {
    stop("PST source does not match the pinned original checksum")
  }
  original <- read_bytes(source_file)
  text <- rawToChar(original)
  before <- strsplit(text, "\n", fixed = TRUE)[[1L]]
  line <- which(before == old_line)
  if (length(line) != 1L) stop("Expected exactly one exact original signature line")
  transformed <- sub(old_line, new_line, text, fixed = TRUE)
  after <- strsplit(transformed, "\n", fixed = TRUE)[[1L]]
  if (length(before) != length(after) ||
      !identical(which(before != after), line) || after[[line]] != new_line) {
    stop("Portability transformation changed more than the intended line")
  }
  # Output is restricted to generated build state, never the vendor tree.
  portable_path <- gsub("\\", "/", output_file, fixed = TRUE)
  if (!grepl("(^|/)[.]rpst-build/", portable_path) ||
      basename(output_file) != "CalculateIsovists.cpp") {
    stop("Output must be a generated .rpst-build/CalculateIsovists.cpp")
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
  candidate <- tempfile("qualification-", tmpdir = dirname(output_file))
  on.exit(unlink(candidate), add = TRUE)
  bytes <- charToRaw(transformed)
  writeBin(bytes, candidate)
  if (!identical(read_bytes(candidate), bytes) ||
      !identical(unname(tools::md5sum(candidate)), qualified_md5) ||
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
  if (length(args) != 2L) stop("Usage: qualify-isovist.R original generated-copy")
  qualify_isovist(args[[1L]], args[[2L]])
}
