#' Create a reusable native PST isovist context
#'
#' Creates reusable native state with pinned PST v3.3.2 (commit
#' `63df80a2cf3dd289be95ea3d91667c3490719b75`). Coordinates are finite, planar
#' and unmodified, and must fit native local-float and distance bounds. Polygon
#' vertices retain supplied order and winding; PST expects Cartesian clockwise
#' rings. No closing, snapping, deduplication or polygon repair is performed.
#' Empty contexts and empty groups are allowed. Context geometry is copied by
#' PST and input R matrices are not retained.
#'
#' Optional sf/sfc layers may replace a group. A polygon group is an XY POLYGON
#' layer whose features keep their order; each feature must have exactly one
#' ring (holes, empty polygons, MULTIPOLYGON, Z/M are rejected). Only the
#' structural closing coordinate of each ring is removed; every other vertex and
#' the winding are preserved. A point group is an XY POINT layer. Geographic CRS
#' and mismatched layer CRS are rejected and nothing is reprojected; matrix
#' groups contribute no metadata. When sf participates, compatible CRS metadata
#' is kept only as the context `"crs"` attribute.
#'
#' At most 256 combined groups and 2^24 objects per group are supported by
#' native visibility packing. Native pointers cannot be serialized or
#' transferred between R processes; reconstruct from geometry. Use
#' [isovist_context_free()] for explicit release.
#'
#' @param obstacles List of groups, each a list of integer/double two-column
#'   `x,y` polygon vertex matrices, or an XY POLYGON sf/sfc layer (one ring per
#'   feature; holes, empty polygons and MULTIPOLYGON rejected; only the structural
#'   closing coordinate is removed; winding never changed). Each polygon must
#'   have at least one vertex.
#' @param attraction_points List of groups, each an integer/double two-column
#'   `x,y` point matrix (possibly zero rows) or an XY POINT sf/sfc layer.
#' @param attraction_polygons Same grouped polygon representation as `obstacles`.
#' @return A `pst_isovist_context` with an exact-tagged native `ptr`. Copying
#'   shares ownership; collection of the last owner frees the context. Inputs
#'   are not retained.
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

#' Calculate a PST isovist and grouped visibility
#'
#' A synchronous call to pinned PST v3.3.2 using a reusable native context,
#' returning independent R storage. The native result depends on its context and
#' returns storage to it on destruction: rPSTool copies all outputs while that result
#' is alive, then frees it before returning. Returned R storage remains valid
#' after context release.
#'
#' PST uses local float geometry and an area-corrected segmented perimeter.
#' Direction is measured counterclockwise from positive x and ignored for a
#' full circle. An origin inside an obstacle causes that obstacle to be skipped.
#' Native geometry, area, ordering and visibility rules are preserved.
#'
#' Verified build-copy guards prevent three upstream invalid-access states: an
#' empty calculated vertex array and insufficient vertices for partial-view
#' attraction-point or attraction-polygon processing. These signal a controlled
#' R error when PST publishes no result handle, without exposing partial
#' outputs. Small radii, narrow views, zero area and safely written degenerate
#' geometry are not broadly rejected. No synthetic polygon, area, visibility or
#' NA result is returned; successful calculations retain pinned PST behaviour.
#'
#' @param context A live `pst_isovist_context`.
#' @param origin Numeric vector of length two containing `x,y`.
#' @param max_distance Finite nonnegative native float view distance.
#' @param field_of_view Finite angle from 0 to 360 degrees, default 360.
#' @param direction Finite native float direction in degrees, default 0.
#' @param perimeter_segments Whole perimeter resolution of at least 3, default 64.
#' @param output `"native"` (default) or `"sf"`. With `"sf"` (requires sf),
#'   `polygon` is a length-one POLYGON `sfc` built from the copied native
#'   vertices, appending the first vertex only when the result is not already
#'   closed. CRS comes from the context (unknown if none). Results with fewer
#'   than three vertices or nonfinite coordinates error; no validity check,
#'   repair or normalisation is applied.
#' @return A list with `polygon` (double `x,y` matrix, not automatically closed),
#'   `area` (native float widened to double), `visible_obstacles`,
#'   `visible_attraction_points`, and `visible_attraction_polygons`. Each visibility
#'   component is a list of integer index vectors, one per original input group,
#'   including empty groups. Indices are one-based within each group; native
#'   ordering is preserved. Group counts are the lengths of these vectors.
#' @seealso [isovist_context()]
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

#' Release a native isovist context
#'
#' Explicitly releases a native isovist context. Explicit release invalidates
#' every R wrapper sharing this pointer. Repeated release is safe; subsequent
#' calculations reject the dead pointer. No native result escapes a calculation:
#' each has already freed its dependent native result, and all returned
#' calculation outputs have independent R storage.
#' @param context A `pst_isovist_context`.
#' @return Invisibly `NULL`.
#' @seealso [isovist_context()]
#' @export
#' @examples
#' ctx <- isovist_context()
#' isovist_context_free(ctx)
#' isovist_context_free(ctx) # repeated release is safe
isovist_context_free <- function(context) {
  invisible(.Call(C_rpst_isovist_context_release, .pst_isovist_pointer(context)))
}
