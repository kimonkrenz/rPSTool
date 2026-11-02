#' Build an axial graph from lines
#'
#' Creates an axial graph, the representation PST uses for axial-line and crossing-based analyses
#' ([network_integration()], [network_reach()], [network_betweenness()], [od_betweenness()],
#' [attraction_reach()] and [attraction_distance()]). The graph is built once and can be reused by any
#' number of analyses. PST finds the crossings between the lines; the lines are not split into segments (use
#' [create_segment_map()] and [segment_graph()] for segment-based analyses).
#'
#' @details
#' **Lines.** Each row of a four-column matrix is one line: `x1, y1, x2, y2`. Column names are optional and
#' do not change that order. Alternatively, supply a two-column matrix of coordinates (`x, y`) and a
#' `line_indices` matrix whose rows give the one-based coordinate rows of each line's endpoints. Unused
#' coordinates still affect PST's world origin. Rows and endpoint direction are preserved, and nothing is
#' snapped, reprojected, filtered, reordered or converted between units.
#'
#' **Coordinates.** Coordinates must be finite (except `NaN`/`NaN` polygon-ring separators) and their extent
#' must fit PST's single-precision local coordinates. PST centres the coordinates and stores them as
#' single-precision values, so lengths and positions reflect that rounding. Supply planar coordinates in the
#' units you intend to use for radii. A matrix carries no coordinate reference system.
#'
#' **Unlinks.** Each row of `unlinks` is a point that removes the nearest eligible crossing; PST applies no
#' tolerance. A crossing is eligible only if the first line of the pair crosses in its interior.
#'
#' **Points and polygons.** `points` adds points to the graph, which are assigned to their nearest line and
#' are used by the attraction analyses and by [od_betweenness()]. With `points_per_polygon`, `points` holds
#' polygon corners instead. `points_per_polygon` gives the number of corner rows of each polygon,
#' including separator rows. `NaN`/`NaN` rows separate rings within one polygon, and each ring closes
#' automatically, so do not repeat its first corner. PST samples every closed ring at
#' `polygon_point_interval`, starting at the first corner, carrying the spacing across edges and adjusting
#' the closing gap. Each polygon becomes one point group. Ring order and empty groups are preserved, and
#' `n_points` counts the generated samples, not the corners.
#'
#' **`sf` input.** With the suggested package 'sf', `x` may be an `sf` or `sfc` object of XY LINESTRING
#' features with exactly two vertices (or POINT features when `line_indices` is used). `unlinks` accepts XY
#' POINT features and `points` accepts XY POINT or POLYGON features. For polygons the corner counts are
#' derived (leave `points_per_polygon` as `NULL`), while `polygon_point_interval` is still required. Polygon
#' rings keep their order and winding and only the repeated closing coordinate is removed; holes are sampled
#' along with the outer ring. Attributes are ignored.
#'
#' **File input.** `x` may instead be one path to a GeoParquet (1.0 or 1.1, WKB) or FlatGeobuf (major
#' version 3) file whose features are all two-vertex XY LineStrings; the format is recognised from the file
#' content, not its extension. See [segment_graph()] for the file contract. `line_indices` must be `NULL`
#' with a path. Lines are used in the file's physical order, which fixes line numbering and crossing order
#' (a spatially indexed FlatGeobuf is stored in Hilbert order rather than the writer's order). The file's
#' coordinate reference system becomes the graph's `crs` attribute. The file is read in one pass without
#' building an `sf` object or an R coordinate matrix.
#'
#' **Coordinate reference systems.** A known geographic CRS is rejected: transform to a projected CRS
#' yourself. When several `sf` inputs are supplied their CRS must be compatible, and an unknown CRS cannot be
#' mixed with a known one. An unknown CRS is allowed on your responsibility, and mixed matrix and `sf`
#' inputs must already share the same coordinate frame. Only the CRS is retained, as the graph's `crs`
#' attribute.
#'
#' **Using the graph.** The graph is held in native memory and is released automatically once no R object
#' refers to it. It cannot be saved with `saveRDS()` or sent to another R process; rebuild it from the
#' coordinates instead. Inputs are not retained.
#'
#' @section Limitations:
#' MULTIPOLYGON, multipart lines or points, geometry collections, empty POINT or LINESTRING features and Z/M
#' coordinates are rejected. Native graphs cannot be serialised (see Details).
#'
#' @param x An integer or double matrix with at least one row: four columns `x1, y1, x2, y2`, or two
#'   columns `x, y` when `line_indices` is supplied; an `sf`/`sfc` object (see Details); or one path to a
#'   GeoParquet or FlatGeobuf file of two-vertex LineStrings.
#' @param line_indices Optional two-column numeric matrix of whole, one-based indices into the rows of `x`.
#'   Each row defines one line.
#' @param unlinks Optional two-column numeric matrix of `x, y` coordinates (or XY POINT features) that
#'   remove the nearest eligible crossing.
#' @param points Optional two-column numeric matrix of points to add to the graph, or of polygon corners
#'   when `points_per_polygon` is supplied.
#' @param points_per_polygon Optional vector of non-negative whole numbers: the number of corner rows (including
#'   separator rows) of each polygon, summing to `nrow(points)`. A zero keeps an empty group.
#' @param polygon_point_interval Positive, finite sampling interval in coordinate units. Required with
#'   polygons.
#' @return An object of class `pst_graph`: a list with `type` (`"axial"`), `n_lines`, `n_crossings`,
#'   `n_points`, `n_point_groups` (counts read from PST) and `pst_version`, plus the native handle `ptr`.
#'   Treat these fields as read-only. `print()` shows a summary and returns the object invisibly.
#' @seealso [segment_graph()] for segment-based analyses, [axial_line_lengths()] and [axial_crossing_coords()]
#'   to inspect the graph, [load_example_data()] for an example network.
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

#' Inspect the lines and crossings of an axial graph
#'
#' `axial_line_lengths()` returns the length of every line in a graph and `axial_crossing_coords()` returns
#' the coordinates where PST found the lines to cross. Both read values stored in the graph; nothing is
#' recalculated.
#'
#' @details
#' Lengths are PST's single-precision values widened to doubles, so they reflect PST's coordinate rounding.
#' Crossings are listed in PST's crossing order, including endpoint joins that PST retains.
#'
#' @param graph An axial graph created by [axial_graph()].
#' @param output For `axial_crossing_coords()`: `"native"` (default) returns a matrix and `"sf"` returns
#'   point geometry (requires the suggested package 'sf').
#' @return `axial_line_lengths()` returns a numeric vector in the row order of the lines supplied to
#'   [axial_graph()]. `axial_crossing_coords()` returns a numeric matrix with columns `x` and `y`, with zero
#'   rows when there are no crossings. With `output = "sf"` the crossings are XY POINT features with a
#'   one-based `crossing_id` in the same order, carrying the graph's CRS (unknown if it has none).
#' @seealso [axial_graph()]
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
