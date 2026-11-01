#' ggplot2 colour and fill scales for rPSTool palettes
#'
#' Continuous (`_c`) and binned (`_b`) scales for numerical data that use the palette definitions of [colour_palettes()]. They need
#' the 'ggplot2' package, which rPSTool does not require; everything else in rPSTool works without it. A scale changes only the colour or
#' fill mapping: it never alters the plot theme or background, so a palette intended for a black background still needs
#' `ggplot2::theme()` to supply one (see the intended backgrounds in [colour_palettes()]).
#'
#' **Continuous scales** map the data (or `limits`) linearly onto the palette's continuous design, exactly as [colour_map()]
#' does; the colour bar is the sampled design. For the equal-range depthmapX palettes the design is a set of bands, so the colour bar
#' is stepped, and for `depthmapx_classic` it is the calculated rainbow; neither is a gradient through a few stops.
#'
#' **Binned scales** take user-supplied class boundaries `breaks` (`k + 1` increasing values for `k` classes) and give class `i`
#' exactly colour `i` of the discrete palette with `k` colours, for unequal as well as equal widths, with a matching
#' stepped legend. `k` must be a size the palette offers (3, 5 or 9 for the Coral and white-background palettes). The outer boundaries are the limits of
#' the scale. rPSTool does not calculate class boundaries; use any classification package and pass its boundaries (see the examples).
#' Class closure and out-of-range values follow [colour_map()].
#'
#' @param palette A palette identifier, see [colour_palettes()].
#' @param breaks For `_b` scales, the class boundaries (see Details).
#' @param ... Further arguments passed to `ggplot2::continuous_scale()` or `ggplot2::binned_scale()`, for example `name`, `labels`
#'   or (continuous scales) `breaks`.
#' @param limits `NULL` (the data range) or two numbers, for the `_c` scales. Binned scales take their limits from `breaks`.
#' @param reverse `TRUE` reverses the palette.
#' @param right For `_b` scales, whether classes are closed on the right (the default) or on the left; see [colour_map()].
#' @param na.value The colour of missing values; `NULL` selects the palette's default (`colour_palettes()$na_colour`, where `NA`
#'   draws nothing).
#' @param oob How values outside the limits are handled: `"squish"` or `"censor"` (see [colour_map()]), or a ggplot2 out-of-bounds
#'   function such as `scales::squish`. The defaults are `"squish"` for `_c` and `"censor"` for `_b` scales.
#' @param guide The guide; `"colourbar"` for `_c` and `"coloursteps"` for `_b` scales by default.
#' @return A ggplot2 scale object.
#' @seealso [colour_map()], [colour_palettes()]
#' @name scale_rpst
#' @examples
#' if (requireNamespace("ggplot2", quietly = TRUE)) {
#'   library(ggplot2)
#'   d <- data.frame(x = 1:40, y = (1:40 %% 7) + 1, value = seq(0, 30, length.out = 40))
#'   base <- ggplot(d, aes(x, y, colour = value)) + geom_point(size = 4)
#'
#'   base + scale_colour_rpst_c("coral_day")
#'   base + scale_colour_rpst_c("coral_night", limits = c(0, 40), reverse = TRUE) +
#'     # the background is the user's choice:
#'     theme(panel.background = element_rect(fill = "black"))
#'
#'   # Five classes with explicit (unequal) boundaries; class i has exactly
#'   # colour i of the 5-colour palette.
#'   brks <- c(0, 2, 5, 10, 20, 30)
#'   base + scale_colour_rpst_b(breaks = brks, palette = "coral_day")
#'
#'   # Boundaries calculated elsewhere, e.g. with the optional 'classInt' package:
#'   if (requireNamespace("classInt", quietly = TRUE)) {
#'     brks <- classInt::classIntervals(d$value, n = 5, style = "quantile")$brks
#'     ggplot(d, aes(x, y, fill = value)) + geom_tile() +
#'       scale_fill_rpst_b(breaks = brks, palette = "axmanesque_white")
#'   }
#' }
NULL

#' @rdname scale_rpst
#' @export
scale_colour_rpst_c <- function(palette = "coral_day", ..., limits = NULL, reverse = FALSE, na.value = NULL,
                                oob = "squish", guide = "colourbar") {
  .rpst_continuous_scale("colour", palette, ..., limits = limits, reverse = reverse, na.value = na.value, oob = oob,
                         guide = guide)
}

#' @rdname scale_rpst
#' @export
scale_fill_rpst_c <- function(palette = "coral_day", ..., limits = NULL, reverse = FALSE, na.value = NULL,
                              oob = "squish", guide = "colourbar") {
  .rpst_continuous_scale("fill", palette, ..., limits = limits, reverse = reverse, na.value = na.value, oob = oob,
                         guide = guide)
}

#' @rdname scale_rpst
#' @export
scale_colour_rpst_b <- function(breaks, palette = "coral_day", ..., reverse = FALSE, right = TRUE, na.value = NULL,
                                oob = "censor", guide = "coloursteps") {
  .rpst_binned_scale("colour", breaks, palette, ..., reverse = reverse, right = right, na.value = na.value, oob = oob,
                     guide = guide)
}

#' @rdname scale_rpst
#' @export
scale_fill_rpst_b <- function(breaks, palette = "coral_day", ..., reverse = FALSE, right = TRUE, na.value = NULL,
                              oob = "censor", guide = "coloursteps") {
  .rpst_binned_scale("fill", breaks, palette, ..., reverse = reverse, right = right, na.value = na.value, oob = oob,
                     guide = guide)
}

# ---- construction -----------------------------------------------------------------------------------------------------------------

.rpst_require_ggplot2 <- function() {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("the rPSTool ggplot2 scales need the 'ggplot2' package; the palettes themselves are available without it ",
         "(colour_palette(), colour_map())", call. = FALSE)
  }
}

# ggplot2 before 3.5.0 requires `scale_name`; later versions deprecate it.
.rpst_scale_name_argument <- function(name) {
  if (.rpst_version_lt(getNamespaceVersion("ggplot2"), "3.5.0")) list(scale_name = name) else list()
}

.rpst_version_lt <- function(version, than) numeric_version(version) < numeric_version(than)

.rpst_oob <- function(oob) {
  if (is.function(oob)) return(oob)
  if (!is.character(oob) || length(oob) != 1L || !oob %in% c("squish", "censor")) {
    stop("oob must be \"squish\", \"censor\" or a function", call. = FALSE)
  }
  if (identical(oob, "squish")) {
    function(x, range = c(0, 1)) {
      x[is.finite(x) & x < range[1L]] <- range[1L]
      x[is.finite(x) & x > range[2L]] <- range[2L]
      x
    }
  } else {
    function(x, range = c(0, 1)) {
      x[is.finite(x) & (x < range[1L] | x > range[2L])] <- NA
      x
    }
  }
}

.rpst_na_value <- function(entry, na.value) {
  if (is.null(na.value)) entry$na_colour else .pal_na_colour(entry, na.value)
}

.rpst_continuous_scale <- function(aesthetics, palette, ..., limits, reverse, na.value, oob, guide) {
  .rpst_require_ggplot2()
  entry <- .pal_entry(palette)
  .pal_check_flag(reverse, "reverse")
  if (!is.null(limits)) limits <- .pal_check_limits(limits)
  mapper <- function(t) {   # `t` arrives rescaled to [0, 1]
    out <- rep(NA_character_, length(t))
    keep <- is.finite(t)
    t <- pmin(pmax(t[keep], 0), 1)
    out[keep] <- .pal_from_t(entry, if (reverse) 1 - t else t)
    out
  }
  arguments <- c(list(aesthetics = aesthetics, palette = mapper, limits = limits, na.value = .rpst_na_value(entry, na.value),
                      oob = .rpst_oob(oob), guide = guide, ...),
                 .rpst_scale_name_argument("rpst_c"))
  do.call(ggplot2::continuous_scale, arguments)
}

.rpst_binned_scale <- function(aesthetics, breaks, palette, ..., reverse, right, na.value, oob, guide) {
  .rpst_require_ggplot2()
  entry <- .pal_entry(palette)
  .pal_check_flag(reverse, "reverse")
  .pal_check_flag(right, "right")
  breaks <- .pal_check_breaks(breaks)
  colours <- .pal_discrete(entry, length(breaks) - 1L)
  if (reverse) colours <- rev(colours)
  limits <- range(breaks)
  rescaled <- (breaks - limits[1L]) / (limits[2L] - limits[1L])
  mapper <- function(x) colours[findInterval(x, rescaled, all.inside = TRUE)]   # `x`: class midpoints rescaled to [0, 1]
  arguments <- c(list(aesthetics = aesthetics, palette = mapper, breaks = breaks, limits = limits, right = right,
                      na.value = .rpst_na_value(entry, na.value), oob = .rpst_oob(oob), guide = guide, ...),
                 .rpst_scale_name_argument("rpst_b"))
  do.call(ggplot2::binned_scale, arguments)
}
