# Direct file input for segment_graph(<character path>) and axial_graph(<character path>): one local regular file, identified by CONTENT
# (never by extension) and routed to the matching reader. Every reader ends in the same shared native
# segment-graph builder as the matrix and sf routes.

# Common path validation. Returns the normalised path of one existing, readable, regular local file.
.pst_check_input_path <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path))
    stop("path must be a single non-empty, non-missing character string.", call. = FALSE)
  path <- path.expand(path)
  info <- file.info(path)
  if (is.na(info$size)) stop("File does not exist: ", path, call. = FALSE)
  if (isTRUE(info$isdir))
    stop("path is a directory; exactly one file is supported.", call. = FALSE)
  if (!isTRUE(.Call(C_rpst_path_is_regular_file, path)))
    stop("path is not a regular local file (devices, pipes and special files are unsupported): ",
         path, call. = FALSE)
  con <- tryCatch(file(path, "rb"), error = function(e) NULL, warning = function(w) NULL)
  if (is.null(con)) stop("File is not readable: ", path, call. = FALSE)
  close(con)
  normalizePath(path, mustWork = TRUE)
}

# Identify the format from the file's own bytes:
#   first four bytes "PAR1"                    -> GeoParquet (the trailing "PAR1" is then required)
#   else first seven bytes 66 67 62 03 66 67 62 -> FlatGeobuf major version 3 (any eighth, patch-level, byte)
#   else the FlatGeobuf family marker with another major version -> explicit unsupported-major error
#   else unsupported format.
# A valid FlatGeobuf file whose last bytes happen to equal "PAR1" is FlatGeobuf: the trailer is only
# examined on the Parquet branch.
.pst_sniff_file_format <- function(path) {
  size <- file.size(path)
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)
  head <- readBin(con, "raw", 8L)
  parquet_magic <- charToRaw("PAR1")
  if (length(head) >= 4L && identical(head[1:4], parquet_magic)) {
    if (size < 12) stop("File is too small to be a Parquet file: ", path, call. = FALSE)
    seek(con, size - 4)
    if (!identical(readBin(con, "raw", 4L), parquet_magic))
      stop("File does not start and end with the Parquet magic bytes 'PAR1': ", path, call. = FALSE)
    return("geoparquet")
  }
  if (length(head) < 8L)
    stop("File is too small to identify as GeoParquet or FlatGeobuf: ", path, call. = FALSE)
  fgb <- as.raw(c(0x66, 0x67, 0x62))
  if (identical(head[c(1:3, 5:7)], c(fgb, fgb))) {
    if (head[4] == as.raw(3L)) return("flatgeobuf")
    stop("Unsupported FlatGeobuf major version ", as.integer(head[4]),
         "; only major version 3 is supported: ", path, call. = FALSE)
  }
  stop("Unsupported file format: it starts with neither the Parquet magic bytes 'PAR1' nor the ",
       "FlatGeobuf signature. Supported inputs are GeoParquet and FlatGeobuf: ", path, call. = FALSE)
}

# Route one validated path to the matching reader. `target` is "segment" (segment_graph) or "axial"
# (axial_graph); `aux` carries axial_graph()'s in-memory unlinks/points inputs (axial only).
.pst_path_graph <- function(path, target = "segment", aux = NULL) {
  path <- .pst_check_input_path(path)
  format <- .pst_sniff_file_format(path)
  graph <- switch(format,
                  geoparquet = .pst_geoparquet_graph(path, target, aux),
                  flatgeobuf = .pst_flatgeobuf_graph(path, target, aux))
  # Lightweight source provenance (path, format, row count, size, mtime, file identity; never geometry) so that
  # `spatial_output_file` can re-read the original features later. See R/spatial-output.R.
  .pst_attach_source(graph, path, format)
}
.pst_path_segment_graph <- function(path) .pst_path_graph(path, "segment")
