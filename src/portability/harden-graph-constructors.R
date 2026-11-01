# Build-only RAII transformation for the exact pinned PST source.
harden_graph_constructors <- function(source_file, output_file) {
  original_md5 <- "0aea4b5325e2d3177ae91d2008da4f55"
  hardened_md5 <- "6ae192582ff4bafaf7f03a189c7c10f5"
  old <- c(
    "#include <pstalgo/graph/SegmentGraph.h>",
    "\tauto graph = new CAxialGraph();",
    "\tauto graph = new CSegmentGraph();",
    "\tauto graph = new CSegmentGroupGraph();",
    "\tgraph->Create(*segment_graph, desc->m_GroupIndexPerSegment, desc->m_GroupCount);\n\n\treturn graph;",
    "\tgraph->setWorldOrigin(world_origin);\n\n\treturn graph;",
    "\t\tdelete graph;\n\t\treturn 0;\n\t}\n\n\treturn graph;"
  )
  new <- c(
    "#include <pstalgo/graph/SegmentGraph.h>\n#include <memory>",
    "\tstd::unique_ptr<CAxialGraph> graph(new CAxialGraph());",
    "\tstd::unique_ptr<CSegmentGraph> graph(new CSegmentGraph());",
    "\tstd::unique_ptr<CSegmentGroupGraph> graph(new CSegmentGroupGraph());",
    "\tgraph->Create(*segment_graph, desc->m_GroupIndexPerSegment, desc->m_GroupCount);\n\n\treturn graph.release();",
    "\tgraph->setWorldOrigin(world_origin);\n\n\treturn graph.release();",
    "\t\treturn 0;\n\t}\n\n\treturn graph.release();"
  )
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
  # Undo only the seven documented edits and demand the complete original bytes.
  restored <- transformed
  for (i in rev(seq_along(old))) {
    if (count(new[[i]], restored) != 1L) stop("Unexpected intended edit count")
    restored <- sub(new[[i]], old[[i]], restored, fixed = TRUE)
  }
  if (!identical(charToRaw(restored), original)) {
    stop("Constructor transformation changed more than the intended edits")
  }
  # Output is restricted to generated build state, never the vendor tree.
  portable_path <- gsub("\\", "/", output_file, fixed = TRUE)
  if (!grepl("(^|/)[.]rpst-build/", portable_path) ||
      basename(output_file) != "CreateGraph.cpp") {
    stop("Output must be a generated .rpst-build/CreateGraph.cpp")
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
  candidate <- tempfile("constructor-raii-", tmpdir = dirname(output_file))
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
  if (length(args) != 2L) stop("Usage: harden-graph-constructors.R original generated-copy")
  harden_graph_constructors(args[[1L]], args[[2L]])
}
