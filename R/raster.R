#' Compare line results using PST's native raster
#'
#' Rasterizes line intensities and applies PST's Gaussian blur to compare two
#' line layers (or two value sets on one layer).
#'
#' @param x Numeric matrix with rows `x1, y1, x2, y2`, or an XY LINESTRING sf/sfc
#'   with exactly two finite vertices per feature (one feature = one row, in
#'   feature order and endpoint direction; longer lines, MULTILINESTRING, empty
#'   features, nonfinite coordinates and Z/M are rejected, never reduced to
#'   endpoints).
#' @param values1,values2 Numeric values for the first and second line layers
#'   (one value per row of the respective layer). With `y = NULL`, both vectors
#'   address rows of `x`.
#' @param y Optional second line layer in the same matrix or sf/sfc form.
#'   Values are never read from sf attributes. Known geographic CRS is rejected;
#'   sf inputs must have compatible CRS (known versus unknown included); a
#'   matrix is assumed to share the numerical frame and is never assigned a CRS.
#' @param mode `"normalized"` or `"relative_percent"` (native normalized or
#'   relative-percent comparison).
#' @param blur_radius Nonnegative Gaussian standard deviation in coordinate
#'   units (default 1).
#' @param resolution Positive pixel size in coordinate units. The default,
#'   `resolution = blur_radius`, is only usable when `blur_radius` is positive:
#'   with `blur_radius = 0` the default resolves to 0 and the call fails with
#'   the error "resolution is outside its finite native float bounds.", so
#'   `resolution` must then be supplied explicitly (for example
#'   `compare_line_results(x, v1, v2, blur_radius = 0, resolution = 0.5)`).
#'   A non-positive `resolution` and a negative `blur_radius` are rejected
#'   likewise ("blur_radius is outside its finite native float bounds.").
#' @param m Finite native lower threshold used in relative-percent comparisons.
#' @return A `pst_raster` retaining the native comparison owner. When sf takes
#'   part, only the CRS metadata is kept, as `attr(raster, "crs")`; source sf
#'   objects are not retained. Matrix-only rasters are unchanged.
#' @details PST rasterizes line intensities and applies its Gaussian blur.
#'   Normalized mode divides the blurred difference by its maximum absolute
#'   magnitude using floating-point absolute values consistently across toolchains;
#'   its reported min/max precede normalization. Relative-percent
#'   mode computes `100 * (max(after, m) / max(before, m) - 1)` after blurring
#'   both layers. Signed values and nonpositive `m` retain native semantics.
#'   A genuinely zero difference denominator, zero blur and relative denominators
#'   can produce native NaN
#'   or Inf; these are preserved. Equal nonzero layers can retain float residuals.
#'   Zero-area raster extents and overflowing native dimensions are rejected.
#'   PST snaps raster extents to resolution; no input geometry snapping, CRS
#'   conversion, file I/O or callback occurs.
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

#' Copy native raster data into R
#'
#' Copies native raster storage into R using its native pitch and format.
#'
#' @param raster A live `pst_raster` from [compare_line_results()].
#' @return A list with `bbox` (named numeric `xmin, ymin, xmax, ymax`),
#'   `dimensions` (named integer `width, height`), `pitch` (a number: the native
#'   row stride of the PST raster storage in bytes, at least `width` times the
#'   bytes per pixel), `format` (a string naming the native pixel type: `"float"`
#'   for 32-bit floating point, copied into a double matrix, or `"byte"` for
#'   8-bit unsigned pixels, copied into an integer matrix; comparison rasters
#'   currently have format `"float"`), native comparison `min` and `max` (numbers;
#'   in normalized mode they precede normalization), and a `values` matrix with
#'   `height` rows and `width` columns. Rows run from maximum y toward minimum y;
#'   columns run from minimum x toward maximum x. Pixel centers are half a pixel
#'   inside the extent. Data are copied by native pitch and format, so `pitch`
#'   is informational: it is not needed to index `values`.
#' @details The returned data remain usable after the raster is released.
#'   NaN and Inf remain native values, without a missing-value policy.
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

#' Convert PST raster ranges to copied polygon rings
#'
#' Copies geometry produced by the exported PST raster conversion.
#'
#' @param raster A live `pst_raster`.
#' @param ranges Numeric two-column matrix with native float lower and upper
#'   limits. Membership is lower-inclusive and upper-exclusive. Infinite
#'   limits are supported; reversed or equal limits yield native empty ranges.
#' @param output `"native"` (default) or `"sf"` (requires sf).
#' @return With `"native"`, a list in range-row order, containing polygons, each
#'   containing two-column coordinate matrices in native ring order (outer ring,
#'   holes). Empty ranges contain empty lists. Rings are not closed by adding a
#'   point. With `"sf"`, an ordinary list in range-row order whose elements are
#'   `sfc_POLYGON` objects, one POLYGON per native polygon in native order, with
#'   the native outer ring first and holes after it in native order; an empty
#'   range is a zero-feature `sfc_POLYGON` and zero ranges give an empty list.
#'   CRS is the raster's retained CRS (unknown if none). Every native coordinate
#'   is kept in order and the first coordinate is appended only when a ring is
#'   not already closed. Rings with fewer than three rows, nonfinite coordinates
#'   or an already-closed ring with fewer than four rows cannot be represented:
#'   the call errors naming the range, polygon and ring, with no partial or
#'   repaired result. Native output remains available. No validity, area or
#'   orientation policy is applied.
#' @details PST interpolates boundaries using an out-of-grid value of zero.
#'   Selecting zero at the grid boundary can produce nonfinite vertices; these
#'   are copied faithfully. No ring repair, orientation change
#'   or reordering occurs. The transient polygon owner is freed after copying;
#'   returned geometry has an independent lifetime.
#' @seealso [compare_line_results()]
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

#' Release a native comparison raster
#'
#' Releases the comparison owner and its dependent raster.
#'
#' @param raster A `pst_raster`.
#' @return `NULL`, invisibly.
#' @details Release is idempotent and invalidates all aliases. Garbage
#'   collection also releases the comparison owner. Saved/deserialized native
#'   pointers must be reconstructed; copied raster data and polygons are ordinary
#'   R values with independent lifetimes.
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
