#' Construct an in-memory PST axial graph from two-point lines
#'
#' Calls the pinned PST v3.3.2 `PSTACreateGraph` routine. Indexed endpoints,
#' unlinks, retained points and polygon-generated point groups use the same
#' native builder. Each matrix row is
#' one line in the default four-column `x1, y1, x2, y2` interface. With
#' indexed coordinates, rows of `line_indices` define lines. Column names are
#' optional and do not change that order. Lines are passed unchanged to PST's
#' axial graph builder, which finds their crossings; they are not automatically
#' split into a separate PST segment graph.
#'
#' Coordinates must be finite (except NaN/NaN polygon ring separators), and
#' their extent must fit PST's native local float and squared-distance
#' representation. PST centres double coordinates and stores local coordinates
#' as floats; lengths and positions reflect that rounding, and rPSTool preserves
#' that behaviour. Sampling intervals must fit native float storage, and a
#' conservative perimeter/interval bound must fit signed native point counts.
#' No snapping, reprojection, filtering, reordering or unit conversion is
#' performed.
#'
#' PST samples each closed polygon ring beginning at its first corner, carries
#' spacing across edges and adjusts the closing gap. Ring order and empty groups
#' are preserved. Polygon corner counts include separator rows. `n_points` counts
#' generated samples rather than supplied corners. `n_point_groups` uses the
#' native graph getter because the pinned exported info routine always reports
#' zero.
#' This matrix interface has no CRS metadata: supply suitable planar coordinates
#' in the units intended for subsequent analyses.
#'
#' With optional package `sf` installed, `x` also accepts `sf`/`sfc` XY
#' LINESTRING features with exactly two vertices, or POINT features when using
#' `line_indices`. `unlinks` accepts XY POINT features. `points` accepts XY POINT
#' or POLYGON features; polygon counts are derived (leave `points_per_polygon`
#' NULL) and `polygon_point_interval` is still required. Polygon rings retain
#' order and winding; only their final repeated closing coordinate is removed,
#' and NaN/NaN separates rings. Each POLYGON feature is one native group sampling
#' all its ring boundaries, including holes. Empty POLYGON features retain empty
#' groups. MULTIPOLYGON, multipart lines/points, collections, empty POINT/LINESTRING
#' features and Z/M are rejected. No input attributes are interpreted or retained.
#'
#' File input. `x` may instead be one character path to a GeoParquet (1.0/1.1,
#' WKB) or FlatGeobuf (major version 3) file; the format is identified from the file
#' content, not its extension, with the file contract documented for
#' [segment_graph()]: every feature is one non-null XY LineString with
#' exactly two finite vertices, geographic CRS is rejected, and nothing is split,
#' snapped, reprojected or repaired. `line_indices` must be NULL with a path;
#' `unlinks`, `points`, `points_per_polygon` and
#' `polygon_point_interval` keep their matrix or sf forms. Lines are used in the
#' file's physical order, which fixes line numbering, crossing order and which line of
#' a pair is first for unlink eligibility; a spatially indexed FlatGeobuf is stored in
#' Hilbert order, not the writer's order. The file's CRS becomes the graph's
#' `crs` attribute, and sf `unlinks`/`points` must have compatible CRS
#' (unknown cannot be mixed with known; matrices carry no CRS). The file is read in
#' one pass into a transient native coordinate array and then discarded; no sf object
#' or R coordinate matrix is built, but PST's own graph storage still dominates memory.
#'
#' Known geographic CRS is rejected: transform explicitly before calling PST.
#' Multiple sf inputs must have compatible CRS, including missing CRS (unknown
#' cannot be mixed with known). Unknown CRS is allowed on user responsibility.
#' Mixed matrix/sf coordinates must already share the same coordinate frame;
#' matrices are not assigned a CRS or converted. Projected units are unchanged.
#' Only sf CRS metadata is retained as the graph's `crs` attribute; geometry and
#' input objects are not retained. Matrix-only calls keep their existing contract.
#'
#' The graph lives on the native heap until its external pointer becomes
#' unreachable and R finalises it with `PSTAFreeGraph`. Copying the R object
#' shares ownership of the same pointer. Native graphs cannot be persisted
#' with `saveRDS()` or sent to another R process: reconstruct from coordinates
#' after reading or transferring data. Inputs are not retained. The finalizer
#' calls `PSTAFreeGraph` once after the last external-pointer reference
#' disappears. Inspection and analysis results own independent R storage.
#'
#' @param x An integer or double matrix with at least one row: four columns `x1, y1, x2, y2`, or
#'   two columns `x, y` when `line_indices` is supplied; or one character path to a
#'   GeoParquet or FlatGeobuf file of two-vertex LineStrings.
#' @param line_indices Optional numeric two-column matrix of whole one-based
#'   indices into `x`. Each row defines a line; unused coordinates still affect
#'   PST's world origin. Rows and endpoint direction are preserved.
#' @param unlinks Optional numeric two-column coordinate matrix. Each unlink
#'   removes the nearest eligible pairwise crossing; PST applies no tolerance.
#'   Eligibility requires the first line of the pair to cross in its interior.
#' @param points Optional numeric two-column matrix of graph points, or polygon
#'   corners when `points_per_polygon` is supplied. PST retains native nearest-
#'   line assignments. Polygon rings close automatically; do not repeat their
#'   first corner. NaN/NaN rows separate rings within a polygon (NA is invalid).
#' @param points_per_polygon Optional numeric vector of non-negative whole
#'   corner-row counts, including separator rows, summing to `nrow(points)`.
#'   Each polygon produces one native point group; zero counts retain empty groups.
#' @param polygon_point_interval Positive finite native-float sampling interval,
#'   required with polygons. PST generates points along the closed ring edges.
#'   Optional coordinate matrices may have zero rows. All construction inputs are
#'   copied by PST and are not retained by the R wrapper.
#' @return An S3 `pst_graph` list containing `ptr` (an owned external pointer),
#'   `type` (`"axial"`), `n_lines`, `n_crossings`, `n_points`, `n_point_groups`
#'   (counts read from PST), and `pst_version` (`"3.3.2"`). Treat these fields as
#'   read-only. Geometry is held by PST rather than the R list. Printing
#'   (`print.pst_graph()`) returns the object invisibly.
#' @export
#' @examples
#' lines <- rbind(c(0, 0, 2, 0), c(1, -1, 1, 1))
#' g <- axial_graph(lines)
#' print(g)
#' coords <- rbind(c(0, 0), c(2, 0), c(1, -1), c(1, 1))
#' indexed <- axial_graph(coords, line_indices = rbind(c(1L, 2L), c(3L, 4L)),
#'                        points = rbind(c(0.5, 1), c(1.5, 0)))
#' axial_line_lengths(indexed)
#' corners <- rbind(c(0, 1), c(2, 1), c(2, 2), c(0, 2))
#' polygon_graph <- axial_graph(lines, points = corners, points_per_polygon = 4L,
#'                              polygon_point_interval = 1)
#' polygon_graph$n_point_groups
axial_graph <- function(x, line_indices = NULL, unlinks = NULL, points = NULL,
                      points_per_polygon = NULL, polygon_point_interval = NULL) {
  if (is.character(x) && is.null(dim(x))) {
    if (!is.null(line_indices))
      stop("line_indices must be NULL when x is a file path: a LineString file defines its lines directly.",
           call. = FALSE)
    return(.pst_path_graph(x, "axial", list(unlinks = unlinks, points = points,
                                            points_per_polygon = points_per_polygon,
                                            polygon_point_interval = polygon_point_interval)))
  }
  crs <- .pst_sf_crs(x, unlinks, points)
  x <- if (is.null(line_indices)) .pst_sf_lines(x, "x") else .pst_sf_points(x, "x")
  unlinks <- .pst_sf_points(unlinks, "unlinks")
  point_input <- .pst_sf_graph_points(points, points_per_polygon)
  points <- point_input$points
  points_per_polygon <- point_input$counts
  ptr <- .Call(C_rpst_graph_create_inputs, x, line_indices, unlinks, points,
               points_per_polygon, polygon_point_interval)
  .pst_axial_graph_object(ptr, crs)
}

# Wrap a built native axial pointer (matrix, sf and file routes alike).
.pst_axial_graph_object <- function(ptr, crs = NULL) {
  info <- .Call(C_rpst_graph_info, ptr)
  graph <- structure(list(ptr = ptr, type = "axial", n_lines = info[[1L]],
                 n_crossings = info[[2L]], n_points = info[[3L]],
                 n_point_groups = info[[4L]], pst_version = "3.3.2"),
            class = "pst_graph")
  if (!is.null(crs)) attr(graph, "crs") <- crs
  graph
}

# File routes only: reconcile the file's CRS with any sf unlinks/points exactly as the sf route does (a known
# CRS cannot mix with an unknown one; geographic CRS is rejected), then stage them as native matrices. This runs
# after the file header/metadata is read and before any native pointer exists.
.pst_axial_auxiliary <- function(aux, file_crs) {
  crs <- .pst_sf_crs(aux$unlinks, aux$points, reference = file_crs)
  unlinks <- .pst_sf_points(aux$unlinks, "unlinks")
  point_input <- .pst_sf_graph_points(aux$points, aux$points_per_polygon)
  list(crs = crs, unlinks = unlinks, points = point_input$points,
       points_per_polygon = point_input$counts, polygon_point_interval = aux$polygon_point_interval)
}

#' @rdname axial_graph
#' @param ... Unused additional arguments. For printing, `x` is a `pst_graph` object.
#' @export
print.pst_graph <- function(x, ...) {
  if (!inherits(x, "pst_graph") || !is.list(x) || is.null(x$ptr)) {
    stop("Invalid pst_graph object; construct it with axial_graph().", call. = FALSE)
  }
  info <- .Call(C_rpst_graph_info, x$ptr)
  cat(sprintf("<pst_graph> PST 3.3.2 axial graph: %d lines, %d crossings\n",
              info[[1L]], info[[2L]]))
  invisible(x)
}

#' Inspect native axial graph lengths and crossings
#'
#' Calls `PSTAGetGraphLineLengths` and `PSTAGetGraphCrossingCoords`. Lengths are
#' native float values widened to doubles. Crossings are native local floats
#' converted back to world doubles, in PST's crossing order, including endpoint
#' joins retained by PST. No ordering, rounding or values are computed in R.
#' @param graph A live axial `pst_graph` created by [axial_graph()].
#' @param output Geometry return form for `axial_crossing_coords()`:
#'   `"native"` (default matrix) or `"sf"` (requires optional package `sf`).
#' @return `axial_line_lengths()` returns a double vector in input line-row
#'   order. `axial_crossing_coords()` returns a double matrix with columns
#'   `x, y`, including a zero-row matrix when there are no crossings.
#'   Both results own their R storage independently of the graph.
#'   With `output = "sf"`, crossing coordinates become XY POINT geometry with
#'   one-based `crossing_id` in native crossing order, and the graph's retained
#'   CRS (otherwise unknown). Coordinates come solely from the native output.
#' @export
#' @examples
#' g <- axial_graph(rbind(c(0, 0, 2, 0), c(1, -1, 1, 1)))
#' axial_line_lengths(g)
#' axial_crossing_coords(g)
axial_line_lengths <- function(graph) {
  .Call(C_rpst_graph_line_lengths, .pst_analysis_graph(graph, FALSE))
}

#' @rdname axial_line_lengths
#' @export
axial_crossing_coords <- function(graph, output = c("native", "sf")) {
  output <- match.arg(output)
  out <- .Call(C_rpst_graph_crossing_coords, .pst_analysis_graph(graph, FALSE))
  colnames(out) <- c("x", "y")
  if (output == "sf") .pst_sf_point_output(out, attr(graph, "crs", exact = TRUE),
                                           data.frame(crossing_id = seq_len(nrow(out)))) else out
}
