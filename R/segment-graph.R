#' Construct an in-memory PST segment graph
#'
#' Calls PST v3.3.2 `PSTACreateSegmentGraph`. Each row is one two-point
#' segment with columns ordered `x1, y1, x2, y2`, regardless of column names.
#' PST joins endpoints with exactly equal double coordinate pairs, before
#' conversion to local floats. Interior crossings and endpoint-on-interior
#' contacts do not connect segments. No crossing detection, snapping, splitting,
#' filtering, reprojection or other preprocessing is performed.
#'
#' Coordinates must be finite and fit PST's native local coordinate, center,
#' length and squared distance representations. Supply suitable planar
#' coordinates; this interface has no CRS metadata or unit conversion.
#'
#' Optional `sf`/`sfc` input accepts only XY LINESTRING features with exactly
#' two finite vertices. Feature order and direction are preserved. Multipart,
#' empty, longer polylines, mixed geometry and Z/M are rejected. No attributes
#' are interpreted. Known geographic CRS is rejected; transform explicitly.
#' Missing CRS is allowed on user responsibility. Projected coordinates retain
#' native units. Only CRS metadata is retained as a `crs` attribute, with no
#' retained input object or duplicate geometry. See [axial_graph()] for CRS policy.
#'
#' A single character path reads one local file whose format is identified from its CONTENT (never its extension):
#' GeoParquet (first four bytes `PAR1`, trailing `PAR1` required) or FlatGeobuf major version 3 (first seven bytes
#' `66 67 62 03 66 67 62`, any patch byte). Anything else is an error. Both routes require every feature to be a
#' non-null, 2D `LineString` with exactly two finite vertices; null, empty, Z/M/ZM, multipart and longer geometries are
#' errors that name the first offending one-based record. Polylines are never split, nothing is reordered, snapped or
#' reprojected, and no identifier or attribute is read or retained. Both end in the same native segment-graph builder
#' as matrix and `sf` input, so the same coordinates give identical results.
#'
#' **GeoParquet** (GeoParquet 1.0/1.1, WKB): needs the optional packages `arrow` (>= 25.0.0), `jsonlite` and `sf`.
#' The geometry column is the file's `primary_column`. Source row order is the graph segment order. The file is
#' streamed through the Arrow C interface straight into the single native coordinate array PST consumes, without
#' building an `sf` object or a coordinate matrix. CRS: a projected `crs` is retained as the graph's `crs` attribute;
#' `"crs": null` is an unknown CRS and is allowed; a file with no `crs` key means GeoParquet's default (OGC:CRS84,
#' geographic) and is rejected, as is any geographic CRS and any `edges` other than planar. GeoParquet 2.0, native
#' GeoArrow encodings, directories, multiple files and cloud paths are unsupported. Peak Arrow memory depends strongly
#' on the file's Parquet row-group size; it is not bounded by a scanner batch size, and files with large row groups
#' are not rejected.
#'
#' **FlatGeobuf** (major version 3): needs only `sf` (to interpret the CRS). The header and every feature record are
#' FlatBuffers structurally verified with a pinned FlatBuffers verifier before use; header and record buffers are
#' limited to 64 MiB and every size prefix and the declared feature count are checked against the file size. The file is
#' read sequentially, one record at a time, in its PHYSICAL ORDER: segment `i` is the `i`-th record. Files written with
#' a spatial index (GDAL's default) are stored in Hilbert order, so segment numbers then differ from the order of the
#' data before it was written, which cannot be recovered; write with `SPATIAL_INDEX=NO` to keep order. The spatial
#' index is never read. The header may not declare Z/M/T dimensions or a geometry type other than LineString
#' (or per-feature types). A declared feature count must match the number of records exactly (0 means unknown).
#' CRS: no CRS table, or exactly GDAL's "Undefined Cartesian SRS with unknown unit" representation, is an unknown CRS
#' (`sf::st_crs(NA)`); any other CRS is interpreted through `sf` (projected retained, geographic or uninterpretable
#' rejected). Big-endian hosts are rejected. Verification covers the structure of every record, not full FlatGeobuf
#' validity; concurrent modification of the file while it is read is unsupported (memory-safe, results undefined).
#' Further details (a repository link, not shipped in the installed package):
#' <https://github.com/kimonkrenz/rPSTool/blob/main/docs/spatial-io/flatgeobuf-input.md> and
#' <https://github.com/kimonkrenz/rPSTool/blob/main/docs/spatial-io/geoparquet-input.md>.
#'
#' This graph owns a native `HPSTASegmentGraph`, incompatible with the axial
#' `HPSTAGraph` returned by [axial_graph()]. Only segment APIs may use it.
#' Copying the R object shares ownership. Last-owner collection calls
#' `PSTAFreeSegmentGraph` exactly once. The input matrix is not retained.
#' Reconstruct graphs from coordinates after serialization or transfer to
#' another R process; native pointers cannot be persisted.
#'
#' @param x An integer or double matrix with at least one row and exactly
#'   four columns, ordered `x1, y1, x2, y2`; an `sf`/`sfc` object of two-vertex
#'   LINESTRINGs; or one character path to a local GeoParquet or FlatGeobuf file (see Details).
#' @return An S3 `pst_segment_graph` list containing `ptr` (an owned native
#'   external pointer), `type` (`"segment"`), `n_segments` (the constructor
#'   count), and `pst_version` (`"3.3.2"`). Treat fields as read-only.
#' @export
#' @examples
#' g <- segment_graph(rbind(c(0, 0, 3, 0), c(3, 0, 3, 3)))
#' print(g)
segment_graph <- function(x) {
  if (is.character(x) && is.null(dim(x))) return(.pst_path_segment_graph(x))
  crs <- .pst_sf_crs(x)
  x <- .pst_sf_lines(x, "x")
  if (!is.matrix(x) || !(typeof(x) %in% c("integer", "double"))) {
    stop("Coordinates must be a numeric matrix with four columns: x1, y1, x2, y2.",
         call. = FALSE)
  }
  if (nrow(x) < 1L || ncol(x) != 4L) {
    stop("Coordinates must have at least one row and exactly four columns: x1, y1, x2, y2.",
         call. = FALSE)
  }
  if (any(!is.finite(x))) {
    stop("Coordinates must all be finite (no NA, NaN or Inf).", call. = FALSE)
  }
  ptr <- .Call(C_rpst_segment_graph_create, x)
  .pst_segment_graph_object(ptr, crs)
}

# Wrap a built native segment-graph pointer (matrix, sf or GeoParquet route alike).
.pst_segment_graph_object <- function(ptr, crs = NULL) {
  graph <- structure(list(ptr = ptr, type = "segment",
                 n_segments = .Call(C_rpst_segment_graph_info, ptr),
                 pst_version = "3.3.2"), class = "pst_segment_graph")
  if (!is.null(crs)) attr(graph, "crs") <- crs
  graph
}

#' @rdname segment_graph
#' @param ... Unused additional arguments.
#' @export
print.pst_segment_graph <- function(x, ...) {
  if (!inherits(x, "pst_segment_graph") || !is.list(x) || is.null(x$ptr)) {
    stop("Invalid pst_segment_graph object; construct it with segment_graph().",
         call. = FALSE)
  }
  n <- .Call(C_rpst_segment_graph_info, x$ptr)
  cat(sprintf("<pst_segment_graph> PST 3.3.2 segment graph: %d segments\n", n))
  invisible(x)
}
