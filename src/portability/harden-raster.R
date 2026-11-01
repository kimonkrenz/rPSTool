# Verified raster safety and explicitly approved floating absolute-value normalization.
harden_raster <- function(source_file, output_file) {
  key <- basename(source_file)
  specifications <- list(
    "Raster.cpp" = list(original = "6ca93a531343e8245d6a5b8ed5da5d78", hardened = "3c4144d04d1f89ed25851625edeaa31c",
      old = c("\t\tm_Bits = malloc(m_Pitch * m_Height);", "\t\tcase RasterFormat_Float:\n\t\t\treturn 4;"),
      new = c("\t\tif (width > std::numeric_limits<uint32_t>::max() / RasterFormatPixelSize(format) ||\n\t\t\tstatic_cast<uint64_t>(m_Pitch) * m_Height > std::numeric_limits<uint32_t>::max())\n\t\t\tthrow std::length_error(\"Raster allocation exceeds native unsigned bounds\");\n\t\tm_Bits = malloc(m_Pitch * m_Height);\n\t\tif (!m_Bits && m_Pitch && m_Height) throw std::bad_alloc();\n#line 41 \"vendor/pstalgo/src/Raster.cpp\"", "\t\tcase RasterFormat_Float:\n\t\t\treturn 4; case RasterFormat_Undefined: break;"),
      prefix = "#include <new>\n#line 1 \"vendor/pstalgo/src/Raster.cpp\"\n"),
    "Blur.cpp" = list(original = "823b9af062cc27c899bbf860a0d62b92", hardened = "707474991a984757ccf00190ce51c0a6",
      old = c("\t\tauto* blur_kernel = (float*)alloca((radius + 1) * sizeof(float));", "std::thread::hardware_concurrency()", "task.wait();"),
      new = c("\t\tstd::vector<float> kernel_storage(static_cast<size_t>(radius) + 1);\n\t\tauto* blur_kernel = kernel_storage.data();\n#line 36 \"vendor/pstalgo/src/gfx/Blur.cpp\"", "rpst_worker_count()", "task.get();"),
      prefix = "#line 1 \"vendor/pstalgo/src/gfx/Blur.cpp\"\n"),
    "Arr2d.h" = list(original = "18a0ede6363657c22c9b7bf86b7e6cb6", hardened = "4e38f713f232f19820c5aa60fad4df75",
      old = c("\t\tinline void FlipY()\n\t\t{", "\t\t\tvoid* rowBuffer = malloc(strideBytes);"),
      new = c("\t\tinline void FlipY()\n\t\t{\n\t\t\tif (m_Height < 2) return;", "\t\t\tvoid* rowBuffer = malloc(strideBytes);\n\t\t\tif (!rowBuffer && strideBytes) throw std::bad_alloc();\n#line 119 \"vendor/pstalgo/include/pstalgo/utils/Arr2d.h\""),
      prefix = "#include <new>\n#line 1 \"vendor/pstalgo/include/pstalgo/utils/Arr2d.h\"\n"),
    "CreateBufferPolygons.cpp" = list(original = "856c3252a9b756f7717161ce174f6879", hardened = "4f540cf92e30dcef34170880ee8b044a",
      old = c("std::max(abs(min), abs(max))", "return (x >= 0) & (x < (int)img.Width()) & (y >= 0) & (y < (int)img.Height());"),
      new = c("std::max(std::abs(min), std::abs(max))", "return (int)(x >= 0) & (int)(x < (int)img.Width()) & (int)(y >= 0) & (int)(y < (int)img.Height());"),
      prefix = "#line 1 \"vendor/pstalgo/src/analyses/CreateBufferPolygons.cpp\"\n")
  )
  if (!(key %in% names(specifications))) stop("Unsupported raster source")
  spec <- specifications[[key]]
  original_md5 <- spec$original; hardened_md5 <- spec$hardened
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
  prefix <- spec$prefix
  transformed <- paste0(prefix, transformed)
  # Undo the documented edits and diagnostic prefix, demanding complete original bytes.
  restored <- substring(transformed, nchar(prefix) + 1L)
  for (i in rev(seq_along(old))) {
    if (count(new[[i]], restored) != 1L) stop("Unexpected intended edit count")
    restored <- sub(new[[i]], old[[i]], restored, fixed = TRUE)
  }
  if (!identical(charToRaw(restored), original)) {
    stop("Raster transformation changed more than the intended edits")
  }
  # Output is restricted to generated build state, never the vendor tree.
  portable_path <- gsub("\\", "/", output_file, fixed = TRUE)
  if (!grepl("(^|/)[.]rpst-build/", portable_path) ||
      basename(output_file) != key) {
    stop("Output must be a generated .rpst-build raster copy")
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
  candidate <- tempfile("raster-safety-", tmpdir = dirname(output_file))
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
  if (length(args) != 2L) stop("Usage: harden-raster.R original generated-copy")
  harden_raster(args[[1L]], args[[2L]])
}
