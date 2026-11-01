# Helpers for the Arrow-independent native GeoParquet boundary tests. They drive the decoder
# with the internal synthetic Arrow C stream producer (src/pst-arrow-test-stream.cpp); no R
# arrow, pyarrow, Python or libarrow is involved.
native_arrow <- function(name, ...) {
  .Call(get(paste0("C_rpst_", name), envir = asNamespace("rPSTool")), ...)
}

# Standard little-/big-endian WKB for a plain 2D LineString (or arbitrary type/point count).
wkb_line <- function(x1, y1, x2, y2, endian = "little", type = 2L, npoints = 2L,
                     coords = c(x1, y1, x2, y2)) {
  int <- function(v) writeBin(as.integer(v), raw(), size = 4L, endian = endian)
  c(as.raw(if (endian == "little") 1L else 0L), int(type), int(npoints),
    if (length(coords)) writeBin(as.double(coords), raw(), endian = endian) else raw())
}

# A pool of valid rows with distinct, exactly representable coordinates.
valid_rows <- function(n, big = integer()) {
  lapply(seq_len(n), function(i) {
    wkb_line(i, 10 * i, i + 0.5, 10 * i + 0.25, endian = if (i %in% big) "big" else "little")
  })
}
valid_matrix <- function(n) {
  i <- seq_len(n)
  cbind(i, 10 * i, i + 0.5, 10 * i + 0.25)
}

stream_counters <- function() native_arrow("arrow_test_counters")
counter_delta <- function(before, after = stream_counters()) after - before

# Build a synthetic stream owned by an rPSTool stream pointer.
synthetic_stream <- function(rows, large = FALSE, plan = NULL, nulls_parent = NULL,
                             nulls_child = NULL, numeric = NULL, flags = NULL,
                             child_name = NULL, child_format = NULL, top_format = NULL) {
  ptr <- native_arrow("arrow_stream_new")
  spec <- list(rows = rows, large = large)
  if (!is.null(plan)) spec$plan <- matrix(as.double(plan), ncol = 5L, byrow = FALSE)
  if (!is.null(nulls_parent)) spec$nulls_parent <- as.integer(nulls_parent)
  if (!is.null(nulls_child)) spec$nulls_child <- as.integer(nulls_child)
  if (!is.null(numeric)) spec$numeric <- numeric
  if (!is.null(flags)) spec$flags <- flags
  if (!is.null(child_name)) spec$child_name <- child_name
  if (!is.null(child_format)) spec$child_format <- child_format
  if (!is.null(top_format)) spec$top_format <- top_format
  native_arrow("arrow_test_export", ptr, spec)
  ptr
}
# Batch plan: one row per batch, columns first, count, parent_offset, child_offset, tail.
batch_plan <- function(...) {
  rows <- list(...)
  do.call(rbind, lapply(rows, function(r) c(r, rep(0, 5 - length(r)))))
}

decode_stream <- function(stream, rows, column = "geometry") {
  native_arrow("arrow_decode_matrix", stream, column, as.double(rows))
}
