#' Compare two sets of line results on a raster
#'
#' Draws line values onto a raster, blurs them with a Gaussian filter and compares two sets of values, either from two line
#' layers or from two value sets on one layer. Use it to see where one set of results is higher or lower than another across
#' space. Use [raster_data()] to read the result and [raster_to_polygons()] to turn value ranges into polygons.
#'
#' @details
#' Each line is drawn with its value; PST then applies Gaussian blur. In `"normalized"` mode the blurred difference is divided
#' by its maximum absolute magnitude (the reported minimum and maximum are those before normalisation). In
#' `"relative_percent"` mode the result is `100 * (max(after, m) / max(before, m) - 1)` after blurring both layers. Signed
#' values and non-positive `m` keep PST's behaviour. A zero difference denominator, zero blur or zero relative denominators can
#' produce `NaN` or `Inf`, which are preserved, and equal non-zero layers can retain floating-point residuals. Raster extents are
#' snapped to the resolution. Zero-area extents and dimensions that overflow are rejected. Input geometry is not snapped, and
#' there is no CRS conversion.
#'
#' @param x A numeric matrix with rows `x1, y1, x2, y2`, or an XY LINESTRING `sf`/`sfc` object with exactly two finite vertices
#'   per feature (one feature per row, in feature order and endpoint direction). Longer lines, MULTILINESTRING, empty features,
#'   non-finite coordinates and Z/M are rejected, not reduced to their endpoints.
#' @param values1,values2 Numeric values for the first and second layer (one per row). With `y = NULL`, both vectors address
#'   the rows of `x`. Values are never read from `sf` attributes.
#' @param y Optional second line layer in the same form as `x`. A known geographic CRS is rejected, `sf` inputs must have
#'   compatible CRS (known versus unknown included), and a matrix is assumed to share the numerical frame.
#' @param mode `"normalized"` or `"relative_percent"`.
#' @param blur_radius Non-negative Gaussian standard deviation in coordinate units (default 1).
#' @param resolution Positive pixel size in coordinate units. The default is `blur_radius`, which is usable only when
#'   `blur_radius` is positive: with `blur_radius = 0` the call fails with "resolution is outside its finite native float
#'   bounds.", so supply `resolution` explicitly (for example `blur_radius = 0, resolution = 0.5`). A non-positive
#'   `resolution` or a negative `blur_radius` is rejected likewise.
#' @param m Finite lower threshold used in `"relative_percent"` comparisons.
#' @return A `pst_raster` object. When `sf` inputs take part, their CRS is kept as `attr(raster, "crs")`.
#' @seealso [raster_data()], [raster_to_polygons()], [raster_free()]
#' @export
#' @examples
#' x <- matrix(c(0, 0, 2, 2, 0, 2, 2, 0), 2, 4, byrow = TRUE)
#' r <- compare_line_results(x, c(1, 2), c(3, 4))
#' d <- raster_data(r)
#' polygons <- raster_to_polygons(r, matrix(c(0.1, 1), 1, 2))
#' raster_free(r)
#'
#' # With blur_radius = 0 the default resolution would be 0: supply it.
#' r0 <- compare_line_results(x, c(1, 2), c(3, 4), blur_radius = 0, resolution = 0.5)
#' raster_data(r0)$dimensions
#' raster_free(r0)
compare_line_results <- function(x, values1, values2, y = NULL,
                                mode = c("normalized", "relative_percent"),
                                blur_radius = 1, resolution = blur_radius, m = 0) {
  mode <- match.arg(mode)
  crs <- .pst_sf_crs(x, y)
  x <- .pst_sf_lines(x, "x")
  y <- .pst_sf_lines(y, "y")
  raster <- structure(list(ptr = .Call(C_rpst_compare_results, x, values1, values2, y,
                            as.integer(match(mode, c("normalized", "relative_percent")) - 1L),
                            blur_radius, resolution, m)), class = "pst_raster")
  if (!is.null(crs)) attr(raster, "crs") <- crs
  raster
}

.pst_raster_pointer <- function(raster) {
  if (!inherits(raster, "pst_raster") || !is.list(raster) ||
      typeof(raster$ptr) != "externalptr")
    stop("Expected a pst_raster comparison result.", call. = FALSE)
  raster$ptr
}

#' Read the values of a comparison raster
#'
#' Copies the pixel values and extent of a raster created by [compare_line_results()] into ordinary R objects. The copy
#' remains usable after the raster is released. `NaN` and `Inf` are kept as PST wrote them.
#'
#' @param raster A raster created by [compare_line_results()].
#' @return A list with
#'   * `bbox`: named numeric `xmin, ymin, xmax, ymax`,
#'   * `dimensions`: named integer `width, height`,
#'   * `pitch`: the row stride of PST's raster storage in bytes (informational; it is not needed to index `values`),
#'   * `format`: the pixel type, `"float"` (copied into a double matrix) or `"byte"` (copied into an integer matrix);
#'     comparison rasters currently have format `"float"`,
#'   * `min` and `max`: PST's comparison minimum and maximum (before normalisation in normalised mode), and
#'   * `values`: a matrix with `height` rows and `width` columns. Rows run from maximum y towards minimum y and columns from
#'     minimum x towards maximum x. Pixel centres are half a pixel inside the extent.
#' @seealso [compare_line_results()]
#' @export
#' @examples
#' x <- matrix(c(0, 0, 2, 2, 0, 2, 2, 0), 2, 4, byrow = TRUE)
#' r <- compare_line_results(x, c(1, 2), c(3, 4))
#' d <- raster_data(r)
#' d$format
#' d$dimensions
#' dim(d$values)
#' raster_free(r)
raster_data <- function(raster) {
  result <- .Call(C_rpst_raster_data, .pst_raster_pointer(raster))
  names(result) <- c("bbox", "dimensions", "pitch", "format", "min", "max", "values")
  names(result$bbox) <- c("xmin", "ymin", "xmax", "ymax")
  names(result$dimensions) <- c("width", "height")
  result
}

#' Convert raster value ranges to polygons
#'
#' Extracts the outlines of the areas of a comparison raster whose values fall within given ranges. PST interpolates the
#' boundaries using a value of zero outside the grid, so selecting zero at the grid boundary can produce non-finite vertices, which
#' are copied faithfully. No ring repair, orientation change or reordering occurs.
#'
#' @param raster A raster created by [compare_line_results()].
#' @param ranges A two-column numeric matrix of lower and upper limits, one range per row. Membership is lower-inclusive and
#'   upper-exclusive. Infinite limits are allowed, and reversed or equal limits give empty ranges.
#' @param output `"native"` (default) or `"sf"` (requires 'sf').
#' @return With `"native"`, a list with one element per range, holding polygons, each a list of two-column coordinate
#'   matrices in PST's ring order (outer ring first, then holes). Empty ranges give empty lists. Rings are not closed by adding
#'   a point. With `"sf"`, a list with one `sfc_POLYGON` per range, one POLYGON per native polygon (outer ring first, holes
#'   after it), with the raster's CRS (unknown if none). An empty range gives a zero-feature `sfc_POLYGON`, and zero ranges give an
#'   empty list. The first coordinate is appended only when a ring is not already closed. A ring that cannot be represented (fewer
#'   than three rows, non-finite coordinates, or an already closed ring with fewer than four rows) is an error that names the
#'   range, polygon and ring; no partial or repaired result is returned.
#' @seealso [compare_line_results()], [raster_data()]
#' @export
#' @examples
#' x <- matrix(c(0, 0, 2, 2, 0, 2, 2, 0), 2, 4, byrow = TRUE)
#' r <- compare_line_results(x, c(1, 2), c(3, 4))
#' polygons <- raster_to_polygons(r, matrix(c(0.1, 1), 1, 2))
#' length(polygons)
#' raster_free(r)
raster_to_polygons <- function(raster, ranges, output = c("native", "sf")) {
  output <- match.arg(output)
  if (output == "sf") .pst_require_sf()
  polygons <- .Call(C_rpst_raster_polygons, .pst_raster_pointer(raster), ranges, FALSE)
  if (output == "native") return(polygons)
  .pst_sf_raster_polygons(polygons, attr(raster, "crs", exact = TRUE))
}

#' Release a comparison raster
#'
#' Releases the memory held by a raster created by [compare_line_results()]. Releasing is optional, since a raster is also
#' released when it is no longer in use, and repeating it is safe. After release the raster (and every copy of it) can no longer
#' be used, but data already copied with [raster_data()] or [raster_to_polygons()] is unaffected. A raster cannot be saved and
#' restored; recreate it instead.
#'
#' @param raster A raster created by [compare_line_results()].
#' @return `NULL`, invisibly.
#' @seealso [compare_line_results()]
#' @export
#' @examples
#' x <- matrix(c(0, 0, 2, 2, 0, 2, 2, 0), 2, 4, byrow = TRUE)
#' r <- compare_line_results(x, c(1, 2), c(3, 4))
#' raster_free(r)
#' raster_free(r) # idempotent
raster_free <- function(raster) {
  .Call(C_rpst_raster_release, .pst_raster_pointer(raster))
  invisible(NULL)
}
