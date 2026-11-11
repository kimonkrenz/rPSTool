# Build-only correction of PST's SphereTree radius query for the exact pinned PST source (docs/compatibility/attractions.md, patch 0012).
#
# `SphereTree::GetCloseLines(int *list, REAL x, REAL y, REAL rad)` collects the lines found into `list` and counts them in the local `count`,
# but returns the member `nResult`, which only the other (segment) overload maintains. The returned value is therefore stale: whatever the
# last segment query during graph construction left behind. Its only caller, `CAxialGraph::getLinesFromPoint()`, uses it as the number
# of valid entries of the graph-owned scratch buffer, so it also reads entries of earlier queries (and zero-initialised ones, i.e. line 0).
# Attraction Reach with line origins, straight distance and a finite straight radius then counts wrong lines, and its scores depend on the
# call history of the graph. The edit returns the number of lines actually written; no other expression changes.
fix_sphere_tree <- function(source_file, output_file) {
  original_md5 <- "c3fffbf37b872ecbe480ee7ba2e07a8f"
  fixed_md5 <- "f61c8ed4e321a5830edc4e890f07a098"
  key <- "SphereTree.cpp"
  old <- "\t\telementFlags[list[i]] = 0;\n\n\treturn nResult;"
  new <- "\t\telementFlags[list[i]] = 0;\n\n\treturn count;"
  read_bytes <- function(path) readBin(path, "raw", n = file.info(path)$size)
  if (!file.exists(source_file) || !identical(unname(tools::md5sum(source_file)), original_md5))
    stop("PST source does not match the pinned original checksum")
  original <- read_bytes(source_file)
  text <- rawToChar(original)
  count <- function(pattern, text) {
    matches <- gregexpr(pattern, text, fixed = TRUE)[[1L]]
    if (matches[[1L]] == -1L) 0L else length(matches)
  }
  if (count(old, text) != 1L || count(new, text) != 0L)
    stop("Expected exactly one original pattern and no transformed pattern")
  transformed <- sub(old, new, text, fixed = TRUE)
  prefix <- "#line 1 \"vendor/pstalgo/src/utils/SphereTree.cpp\"\n"
  transformed <- paste0(prefix, transformed)
  if (lengths(regmatches(transformed, gregexpr("\n", transformed, fixed = TRUE))) !=
      lengths(regmatches(text, gregexpr("\n", text, fixed = TRUE))) + 1L)
    stop("The SphereTree fix changed the line count")
  restored <- substring(transformed, nchar(prefix) + 1L)
  if (count(new, restored) != 1L) stop("Unexpected intended edit count")
  restored <- sub(new, old, restored, fixed = TRUE)
  if (!identical(charToRaw(restored), original)) stop("SphereTree transformation changed more than the intended edit")
  portable_path <- gsub("\\", "/", output_file, fixed = TRUE)
  if (!grepl("(^|/)[.]rpst-build/", portable_path) || basename(output_file) != key)
    stop("Output must be a generated .rpst-build copy")
  parent <- dirname(output_file)
  missing <- character()
  while (!dir.exists(parent)) {
    missing <- c(basename(parent), missing)
    next_parent <- dirname(parent)
    if (identical(next_parent, parent)) stop("Cannot resolve output directory")
    parent <- next_parent
  }
  resolved <- do.call(file.path, as.list(c(normalizePath(parent, winslash = "/"), missing, basename(output_file))))
  if (grepl("/vendor/pstalgo/", resolved, fixed = TRUE) || identical(normalizePath(source_file, winslash = "/"), resolved))
    stop("Refusing to write into the vendor tree")
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  candidate <- tempfile("sphere-tree-fix-", tmpdir = dirname(output_file))
  on.exit(unlink(candidate), add = TRUE)
  bytes <- charToRaw(transformed)
  writeBin(bytes, candidate)
  if (!identical(read_bytes(candidate), bytes) || !identical(unname(tools::md5sum(candidate)), fixed_md5) ||
      !identical(read_bytes(source_file), original))
    stop("Generated copy or original source failed verification")
  if (file.exists(output_file) && identical(read_bytes(output_file), bytes)) return(invisible(output_file))
  if (file.exists(output_file) && unlink(output_file) != 0L) stop("Cannot replace the generated build copy")
  if (!file.rename(candidate, output_file)) stop("Cannot publish the verified build copy")
  invisible(output_file)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) != 2L) stop("Usage: fix-sphere-tree.R original generated-copy")
  fix_sphere_tree(args[[1L]], args[[2L]])
}
