#' Build a segment graph from segments
#'
#' Creates a segment graph, the representation PST uses for segment-based analyses ([angular_integration()],
#' [angular_choice()], [segment_grouping()] and [segment_group_graph()]). The graph is built once and can be
#' reused by any number of analyses.
#'
#' @details
#' **Segments.** Each row is one two-point segment, ordered `x1, y1, x2, y2`, regardless of column names.
#' PST joins two segments where they share an endpoint with exactly equal double coordinates. Crossings in the
#' interior of segments and endpoints that touch the interior of another segment do not connect segments. No
#' crossing detection, snapping, splitting, filtering or reprojection is performed; use [create_segment_map()]
#' to prepare a street network first.
#'
#' **Coordinates.** Coordinates must be finite and within PST's single-precision coordinate range. Supply planar
#' coordinates in the units you intend to use for radii. A matrix carries no CRS.
#'
#' **`sf` input.** With the suggested package 'sf', `x` may hold XY LINESTRING features with exactly two finite
#' vertices. Feature order and direction are kept and attributes are ignored. A known geographic CRS is rejected;
#' transform explicitly. A missing CRS is allowed on your responsibility. Only the CRS is retained, as the graph's
#' `crs` attribute. See [axial_graph()] for the CRS policy.
#'
#' **File input.** A single path reads one local file. The format is recognised from the file content, never its
#' extension: GeoParquet or FlatGeobuf (major version 3). Both require every feature to be a non-null, two-dimensional
#' LineString with exactly two finite vertices. Null, empty, Z/M, multipart and longer geometries are errors that
#' name the first offending record. Polylines are never split, and nothing is reordered, snapped, reprojected or
#' repaired. No identifier or attribute is read. The same coordinates give the same graph by any input route.
#'
#' *GeoParquet* (1.0 or 1.1, WKB) needs the suggested packages 'arrow' (>= 25.0.0), 'jsonlite' and 'sf'. The
#' geometry column is the file's `primary_column`, and source row order is the segment order. A projected `crs` is
#' retained as the graph's CRS, and `"crs": null` means an unknown CRS. A file with no `crs` key means
#' GeoParquet's default (OGC:CRS84, geographic) and is rejected, as is any geographic CRS and any `edges` value
#' other than planar.
#'
#' *FlatGeobuf* (major version 3) needs only 'sf' (to interpret the CRS). The file is read sequentially in its
#' physical order: segment `i` is record `i`. Files written with a spatial index (GDAL's default) are stored in
#' Hilbert order, so segment numbers then differ from the order of the data before it was written; write with
#' `SPATIAL_INDEX=NO` to keep the order. A file with no CRS, or with GDAL's "Undefined Cartesian SRS with
#' unknown unit", has an unknown CRS. Any other CRS is interpreted through 'sf' and must be projected. The
#' header may not declare Z/M/T dimensions or a geometry type other than LineString, and a declared feature
#' count must match the number of records.
#'
#' Further details: <https://github.com/kimonkrenz/rPSTool/blob/main/docs/spatial-io/flatgeobuf-input.md> and
#' <https://github.com/kimonkrenz/rPSTool/blob/main/docs/spatial-io/geoparquet-input.md>.
#'
#' **Using the graph.** A segment graph is a different object from the axial graph made by [axial_graph()] and
#' only segment analyses accept it. It is held in native memory and is released automatically once no R object
#' refers to it. It cannot be saved with `saveRDS()` or sent to another R process; rebuild it from the
#' coordinates instead.
#'
#' @section Limitations:
#' GeoParquet 2.0, native GeoArrow encodings, directories, several files and cloud paths are not supported.
#' Peak memory when reading GeoParquet depends strongly on the file's Parquet row-group size, and files with
#' very large row groups are not rejected. FlatGeobuf verification covers the structure of every record, not full
#' FlatGeobuf validity; modifying a file while it is being read is unsupported. Big-endian hosts are rejected for
#' FlatGeobuf.
#'
#' @param x An integer or double matrix with at least one row and exactly four columns (`x1, y1, x2, y2`); an
#'   `sf`/`sfc` object of two-vertex LINESTRINGs; or one path to a local GeoParquet or FlatGeobuf file.
#' @return An object of class `pst_segment_graph`: a list with `type` (`"segment"`), `n_segments` and
#'   `pst_version`, plus the native handle `ptr`. Treat these fields as read-only. `print()` shows a summary.
#' @seealso [axial_graph()], [create_segment_map()] to prepare segments from a street network,
#'   [angular_integration()], [angular_choice()]
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
