# Build-only CRAN-compatibility copy of FlatBuffers 24.12.23 flatbuffers/base.h.
#
# R CMD check --as-cran (_R_CHECK_PRAGMAS_) rejects `#pragma GCC diagnostic ignored`. The pinned upstream
# base.h contains exactly two such suppressions, each as a push/ignored block and a matching pop block:
#   1. GCC 10 only: "-Wstringop-overflow" around WriteScalar (upstream issue 5950)
#   2. non-MSVC:    "-Wfloat-equal"        around IsTheSameAs
# This script deletes exactly those four complete conditional blocks (so the push/pop state stays balanced)
# and nothing else; the MSVC `#pragma warning` handling is kept. The upstream bytes (inst/upstream/flatbuffers)
# are never modified, and the output is only ever written below a .rpst-build directory.
strip_flatbuffers_diagnostics <- function(source_file, output_file) {
  original_md5 <- "e32af5dbf0f85239ad10c7009d0cb1c9"   # pinned upstream base.h (SHA-256 3f28edd0...ef8)
  generated_md5 <- "9bbb6aef93eeab1d6f6617c880fc667e"
  gcc10 <- "#if (FLATBUFFERS_GCC >= 100000) && (FLATBUFFERS_GCC < 110000)\n"
  nonmsvc <- "#if !defined(_MSC_VER)\n"
  blocks <- c(
    paste0(gcc10, "  #pragma GCC diagnostic push\n  #pragma GCC diagnostic ignored \"-Wstringop-overflow\"\n#endif\n"),
    paste0(gcc10, "  #pragma GCC diagnostic pop\n#endif\n"),
    paste0(nonmsvc, "  #pragma GCC diagnostic push\n  #pragma GCC diagnostic ignored \"-Wfloat-equal\"\n#endif\n"),
    paste0(nonmsvc, "  #pragma GCC diagnostic pop\n#endif\n"))
  read_bytes <- function(path) readBin(path, "raw", n = file.info(path)$size)
  if (!file.exists(source_file) || !identical(unname(tools::md5sum(source_file)), original_md5))
    stop("FlatBuffers base.h does not match the pinned upstream checksum")
  original <- read_bytes(source_file)
  text <- rawToChar(original)
  count <- function(pattern, x) {
    m <- gregexpr(pattern, x, fixed = TRUE)[[1L]]
    if (m[[1L]] == -1L) 0L else length(m)
  }
  transformed <- text
  for (i in seq_along(blocks)) {
    if (count(blocks[[i]], text) != 1L) stop("Expected exactly one upstream diagnostic block ", i)
    pos <- regexpr(blocks[[i]], transformed, fixed = TRUE)
    transformed <- paste0(substr(transformed, 1L, pos - 1L),
                          substring(transformed, pos + nchar(blocks[[i]])))
  }
  # Every remaining GCC/clang diagnostic pragma must be gone, and nothing but the blocks may differ.
  if (grepl("#pragma\\s+(GCC|clang)\\s+diagnostic", transformed, perl = TRUE))
    stop("A GCC/clang diagnostic pragma remains in the generated copy")
  restored <- transformed
  for (i in 1:4) {  # re-insert in ascending order at the recorded upstream offsets
    pos <- regexpr(blocks[[i]], text, fixed = TRUE)
    restored <- paste0(substr(restored, 1L, pos - 1L), blocks[[i]], substring(restored, pos))
  }
  if (!identical(charToRaw(restored), original)) stop("Transformation changed more than the four blocks")
  portable_path <- gsub("\\", "/", output_file, fixed = TRUE)
  if (!grepl("(^|/)[.]rpst-build/", portable_path) || basename(output_file) != "base.h")
    stop("Output must be a generated .rpst-build copy of base.h")
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  candidate <- tempfile("flatbuffers-base-", tmpdir = dirname(output_file))
  on.exit(unlink(candidate), add = TRUE)
  bytes <- charToRaw(transformed)
  writeBin(bytes, candidate)
  if (!identical(read_bytes(candidate), bytes) ||
      !identical(unname(tools::md5sum(candidate)), generated_md5) ||
      !identical(read_bytes(source_file), original))
    stop("Generated copy or upstream source failed verification")
  if (file.exists(output_file) && identical(read_bytes(output_file), bytes)) return(invisible(output_file))
  if (file.exists(output_file) && unlink(output_file) != 0L) stop("Cannot replace the generated build copy")
  if (!file.rename(candidate, output_file)) stop("Cannot publish the verified build copy")
  invisible(output_file)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) != 2L) stop("Usage: strip-flatbuffers-diagnostics.R upstream-base.h generated-copy")
  strip_flatbuffers_diagnostics(args[[1L]], args[[2L]])
}
