# Helpers for the FlatGeobuf path-input tests. Malformed files are produced by BYTE PATCHING the committed
# GDAL-written fixtures in R (tests only): everything is copied into plain raw vectors and written to temp files,
# so no native owner is involved in producing the inputs.
fgb_fixture <- function(name) test_path("fixtures", "flatgeobuf", paste0(name, ".fgb"))
fgb_bytes <- function(name) { f <- fgb_fixture(name); readBin(f, "raw", file.size(f)) }
fgb_write <- function(bytes) { p <- tempfile(fileext = ".fgb"); writeBin(bytes, p); p }

u32le <- function(bytes, off) sum(as.numeric(as.integer(bytes[off + 1:4])) * 256^(0:3))
i32le <- function(bytes, off) readBin(bytes[off + 1:4], "integer", 1L, 4L, endian = "little")
u16le <- function(bytes, off) { v <- as.integer(bytes[off + 1:2]); v[1] + 256L * v[2] }
put <- function(bytes, off, value) { bytes[off + seq_along(value)] <- value; bytes }
# Little-endian encoders for hand-built FlatGeobuf bytes. Every helper validates its exact range instead of
# relying on floating-point arithmetic near the double integer boundary (which warns on some R builds).
exact_word <- function(v, what, max) {
  if (!is.numeric(v) || length(v) != 1L || !is.finite(v) || v != floor(v) || v < 0 || v > max)
    stop(what, " must be one finite whole number in [0, ", format(max, scientific = FALSE), "]", call. = FALSE)
  v
}
le32 <- function(v) {                                                            # 0 <= v <= 2^32 - 1
  v <- exact_word(v, "le32 value", 2^32 - 1)
  as.raw((v %/% 256^(0:3)) %% 256)
}
le64_words <- function(lo, hi) {                                                 # one uint64 = two exact uint32 words
  c(le32(exact_word(lo, "le64_words lo", 2^32 - 1)), le32(exact_word(hi, "le64_words hi", 2^32 - 1)))
}
le64 <- function(v) {                                                            # 0 <= v <= 2^53 - 1 (exact doubles)
  v <- exact_word(v, "le64 value", 2^53 - 1)
  le64_words(v %% 2^32, v %/% 2^32)
}
le64_max <- function() le64_words(2^32 - 1, 2^32 - 1)                            # UINT64_MAX
le64_2pow63 <- function() le64_words(0, 2^31)
le64_2pow53 <- function() le64_words(0, 2^21)

# Layout of a size-prefixed header: absolute offset of the header buffer (after the 8 magic bytes), its total size,
# and the absolute offset of the Header table's field slot `id` (NA when the field is absent).
fgb_header_total <- function(bytes) 4 + u32le(bytes, 8)
fgb_header_field <- function(bytes, id) {
  base <- 8
  table <- base + 4 + u32le(bytes, base + 4)
  vtable <- table - i32le(bytes, table)
  vt_size <- u16le(bytes, vtable)
  slot <- 4 + 2 * id
  if (slot + 2 > vt_size) return(NA_real_)
  off <- u16le(bytes, vtable + slot)
  if (off == 0L) NA_real_ else table + off
}
fgb_count_offset <- function(bytes) fgb_header_field(bytes, 8)       # features_count (uint64)
fgb_node_size_offset <- function(bytes) fgb_header_field(bytes, 9)   # index_node_size (uint16), absent when 16
fgb_data_start <- function(bytes) 8 + fgb_header_total(bytes)        # valid for files without an index

expect_fgb_rejected <- function(bytes, regex, info = NULL) {
  skip_if_not_installed("sf")
  invisible(gc())
  before <- segment_balance()
  expect_error(segment_graph(fgb_write(bytes)), regex, info = info)
  invisible(gc())
  expect_identical(segment_balance(), before, info = info)  # no graph published or leaked
}
