#' Create an isovist context
#'
#' Creates a reusable scene for isovist analysis: obstacles (polygons) and, optionally, groups of attraction points
#' and attraction polygons whose visibility you want to record. Pass the context to [isovist()] for each viewpoint.
#'
#' @details
#' Coordinates must be finite, planar and within PST's single-precision range. Polygon vertices keep their order and
#' winding; PST expects clockwise rings in Cartesian coordinates. No closing, snapping, deduplication or repair is
#' performed. Empty contexts and empty groups are allowed. Geometry is copied, so the R objects are not retained.
#'
#' With the suggested package 'sf', a group can instead be an XY POLYGON layer (one ring per feature, in order) or, for
#' attraction points, an XY POINT layer. Holes, empty polygons, MULTIPOLYGON and Z/M are rejected, and only each ring's closing
#' coordinate is removed. A known geographic CRS and mismatched layer CRS are rejected, and nothing is reprojected. When 'sf'
#' inputs are used, compatible CRS metadata is kept as the context's `"crs"` attribute.
#'
#' The context is held in native memory. It cannot be saved or sent to another R process; rebuild it from the geometry. Use
#' [isovist_context_free()] to release it explicitly.
#'
#' @section Limitations:
#' At most 256 groups in total and 2^24 objects per group are supported.
#'
#' @param obstacles A list of groups. Each group is a list of two-column numeric matrices (`x`, `y`), one polygon per
#'   matrix with at least one vertex, or an XY POLYGON `sf`/`sfc` layer.
#' @param attraction_points A list of groups, each a two-column numeric point matrix (possibly with zero rows) or an XY
#'   POINT `sf`/`sfc` layer.
#' @param attraction_polygons Attraction polygons, in the same grouped form as `obstacles`.
#' @return An object of class `pst_isovist_context`.
#' @seealso [isovist()], [isovist_context_free()]
#' @export
#' @examples
#' ctx <- isovist_context()
#' isovist(ctx, c(0, 0), 10)
#' isovist_context_free(ctx)
#'
#' # One obstacle (clockwise square) and one group of two attraction points
#' square <- list(list(rbind(c(2, -1), c(2, 1), c(3, 1), c(3, -1))))
#' ctx <- isovist_context(obstacles = square,
#'                        attraction_points = list(rbind(c(5, 0), c(-1, 0))))
#' v <- isovist(ctx, c(0, 0), 10)
#' v$visible_attraction_points # only the second point is visible
#' isovist_context_free(ctx)
isovist_context <- function(obstacles = list(), attraction_points = list(),
                                attraction_polygons = list()) {
  crs <- .pst_sf_isovist_crs(list(obstacles, attraction_points, attraction_polygons))
  obstacles <- .pst_sf_isovist_groups(obstacles, TRUE, "obstacles")
  attraction_points <- .pst_sf_isovist_groups(attraction_points, FALSE, "attraction_points")
  attraction_polygons <- .pst_sf_isovist_groups(attraction_polygons, TRUE, "attraction_polygons")
  ptr <- .Call(C_rpst_isovist_context_create,
               .pst_isovist_geometry(obstacles, TRUE),
               .pst_isovist_geometry(attraction_points, FALSE),
               .pst_isovist_geometry(attraction_polygons, TRUE))
  context <- structure(list(ptr = ptr, pst_version = "3.3.2"), class = "pst_isovist_context")
  if (!is.null(crs)) attr(context, "crs") <- crs
  context
}

.pst_isovist_geometry <- function(groups, polygon) {
  if (!is.list(groups)) stop("Isovist geometry must be a list of groups.", call. = FALSE)
  matrices <- if (polygon) {
    if (!all(vapply(groups, is.list, logical(1))))
      stop("Polygon groups must each be a list of vertex matrices.", call. = FALSE)
    unlist(groups, recursive = FALSE, use.names = FALSE)
  } else groups
  valid <- vapply(matrices, function(x) is.matrix(x) &&
    typeof(x) %in% c("integer", "double") && ncol(x) == 2L &&
    (!polygon || nrow(x) > 0L), logical(1))
  if (!all(valid)) stop("Isovist coordinates require two-column numeric matrices; polygons need vertices.", call. = FALSE)
  counts <- if (polygon) lengths(groups) else vapply(matrices, nrow, integer(1))
  coords <- if (length(matrices)) do.call(rbind, unname(matrices)) else matrix(numeric(), 0L, 2L)
  out <- list(coords, counts)
  if (polygon) out[[3L]] <- vapply(matrices, nrow, integer(1))
  out
}

.pst_isovist_pointer <- function(context) {
  if (!inherits(context, "pst_isovist_context") || !is.list(context) || is.null(context$ptr))
    stop("Expected a pst_isovist_context created by isovist_context().", call. = FALSE)
  context$ptr
}

#' Calculate an isovist
#'
#' Calculates the isovist from a viewpoint: the area visible from that point within a maximum distance, given the
#' obstacles in an isovist context, and records which obstacles, attraction points and attraction polygons are visible.
#'
#' @details
#' The perimeter is a polygon with `perimeter_segments` segments, corrected so that it preserves area. Direction is measured
#' counterclockwise from the positive x axis and is ignored for a full circle. An origin inside an obstacle causes that
#' obstacle to be skipped. Geometry is single-precision, as in PST.
#'
#' rPSTool raises an error where PST would otherwise access invalid memory: when the calculated vertex array is empty, and
#' when there are too few vertices for partial-view processing of attraction points or attraction polygons. Small
#' radii, narrow views, zero area and degenerate geometry that PST writes safely are not rejected, and successful
#' calculations follow PST exactly. The returned values do not depend on the context after it has been freed.
#'
#' @param context An isovist context created by [isovist_context()].
#' @param origin Numeric vector of length two: `x, y`.
#' @param max_distance Finite, non-negative view distance.
#' @param field_of_view Finite angle from 0 to 360 degrees (default 360).
#' @param direction Finite direction in degrees (default 0).
#' @param perimeter_segments Whole number of perimeter segments, at least 3 (default 64).
#' @param output `"native"` (default) or `"sf"`. With `"sf"` (requires 'sf'), `polygon` is a one-feature POLYGON `sfc`
#'   with the context's CRS (unknown if none). The first vertex is appended only when the result is not already closed.
#'   Results with fewer than three vertices or non-finite coordinates are an error; no repair is applied.
#' @return A list with
#'   * `polygon`: a two-column matrix of vertices (`x`, `y`), not automatically closed,
#'   * `area`: the isovist area,
#'   * `visible_obstacles`, `visible_attraction_points` and `visible_attraction_polygons`: for each, a list with one
#'     integer vector per input group (including empty groups) of the one-based indices visible within that group, in PST's order.
#' @seealso [isovist_context()], [isovist_context_free()]
#' @export
#' @examples
#' ctx <- isovist_context()
#' v <- isovist(ctx, c(0, 0), 10)
#' v$area
#' nrow(v$polygon)
#' isovist_context_free(ctx)
#'
#' # A 90-degree view towards positive y
#' ctx <- isovist_context()
#' isovist(ctx, c(0, 0), 10, field_of_view = 90, direction = 90)$area
#' isovist_context_free(ctx)
isovist <- function(context, origin, max_distance, field_of_view = 360,
                        direction = 0, perimeter_segments = 64,
                        output = c("native", "sf")) {
  output <- match.arg(output)
  if (output == "sf") .pst_require_sf()
  out <- .Call(C_rpst_isovist_calculate, .pst_isovist_pointer(context), origin,
               max_distance, field_of_view, direction, perimeter_segments, FALSE)
  names(out) <- c("polygon", "area", "visible_obstacles", "visible_attraction_points",
                  "visible_attraction_polygons")
  colnames(out$polygon) <- c("x", "y")
  if (output == "sf")
    out$polygon <- .pst_sf_polygon_output(out$polygon, attr(context, "crs", exact = TRUE))
  out
}

#' Release an isovist context
#'
#' Releases the memory held by an isovist context. Releasing is optional, since a context is also released when it is no
#' longer in use, and repeating it is safe. After release the context (and every copy of it) can no longer be used, but
#' earlier results are unaffected.
#'
#' @param context An isovist context created by [isovist_context()].
#' @return `NULL`, invisibly.
#' @seealso [isovist_context()]
#' @export
#' @examples
#' ctx <- isovist_context()
#' isovist_context_free(ctx)
#' isovist_context_free(ctx) # repeated release is safe
isovist_context_free <- function(context) {
  invisible(.Call(C_rpst_isovist_context_release, .pst_isovist_pointer(context)))
}
