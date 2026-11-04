#' Map numbers to palette colours
#'
#' Assigns each value one colour of a palette, either on a continuous scale between explicit limits or into classes with
#' user-supplied boundaries. rPSTool does not classify: it neither computes equal intervals, quantiles or natural breaks nor transforms
#' the values. Boundaries calculated elsewhere (for example with the 'classInt' package) are passed as `breaks`.
#'
#' **Continuous mapping** (`breaks = NULL`). Values are rescaled linearly, `t = (x - limits[1]) / (limits[2] - limits[1])`, and the
#' colour at position `t` of the palette's continuous design is returned (see [colour_palettes()]). `limits` defaults to the range of
#' the finite values; if all finite values are equal and no limits are given every value is placed at `t = 0.5`, as depthmapX does
#' for an empty range. Explicit limits must satisfy `limits[1] < limits[2]`. `reverse = TRUE` maps `t` to `1 - t`.
#'
#' **Class mapping** (`breaks` given). `breaks` are the class boundaries in increasing order, so `k` classes need `k + 1` boundaries,
#' and class `i` receives colour `i` of the discrete palette with `k` colours (so `k` must be a size the palette offers; colours
#' are never interpolated). With `right = TRUE` (the default, and depthmapX's convention) classes are `[b1, b2]`, `(b2, b3]`, ...,
#' `(bk, bk+1]`; with `right = FALSE` they are `[b1, b2)`, ..., `[bk, bk+1]`. Both outer boundaries are therefore included.
#' `limits` must not be given: the outer boundaries are the limits. `reverse = TRUE` reverses the colour order.
#'
#' **Missing and out-of-range values.** `NA`, `NaN` and infinite values are missing and receive `na_colour`. A finite value outside
#' the limits (continuous) or outside the outer boundaries (classes) is handled by `oob`: `"squish"` gives it the colour of the
#' nearest end, `"censor"` treats it as missing. The default is `"squish"` for continuous mapping, which is depthmapX's behaviour,
#' and `"censor"` for classes, so that no value is silently placed in a class whose boundaries it lies outside.
#'
#' @param x A numeric vector (not a factor); a logical vector containing only `NA` counts as missing numeric values.
#' @param palette A palette identifier, see [colour_palettes()].
#' @param limits `NULL`, or two finite numbers: the values placed at the two ends of the palette. Continuous mapping only.
#' @param breaks `NULL` for continuous mapping, or a strictly increasing finite numeric vector of class boundaries.
#' @param reverse `TRUE` reverses the palette.
#' @param na_colour The colour of missing values: `NULL` for the palette's default (`colour_palettes()$na_colour`), a single colour
#'   string, or `NA` for no colour (transparent when drawn).
#' @param oob `"squish"` or `"censor"`, see Details; `NULL` selects the default for the mapping type.
#' @param right Whether classes are closed on the right, see Details. Class mapping only.
#' @return A character vector of upper-case `"#RRGGBB"` colours the length of `x` (`NA` where a missing value has no colour).
#' @seealso [colour_palette()], [scale_colour_rpst_b()]
#' @export
#' @examples
#' x <- c(1, 4, 9, 16, NA, 25)
#' colour_map(x, "coral_day")
#' colour_map(x, "coral_night", limits = c(0, 30), reverse = TRUE)
#'
#' # User-supplied class boundaries: six classes would need a palette of six colours,
#' # so five classes with a 5-colour nested palette. Boundaries may be unequal.
#' breaks <- c(0, 2, 5, 10, 20, 30)
#' colour_map(x, "coral_day", breaks = breaks)
#' colour_palette("coral_day", n = 5)
#'
#' # Boundaries calculated by another package ('classInt' is optional and not
#' # required by rPSTool):
#' if (requireNamespace("classInt", quietly = TRUE)) {
#'   cl <- classInt::classIntervals(c(x[!is.na(x)], 2, 3, 30), n = 5, style = "fisher")
#'   colour_map(x, "coral_day", breaks = cl$brks)
#' }
colour_map <- function(x, palette = "coral_day", limits = NULL, breaks = NULL, reverse = FALSE,
                       na_colour = NULL, oob = NULL, right = TRUE) {
  if (is.logical(x) && all(is.na(x))) x <- as.numeric(x)   # a vector of NA is a missing numeric vector
  if (!is.numeric(x) || is.factor(x)) stop("x must be a numeric vector", call. = FALSE)
  entry <- .pal_entry(palette)
  .pal_check_flag(reverse, "reverse")
  .pal_check_flag(right, "right")
  na_colour <- .pal_na_colour(entry, na_colour)
  classes <- !is.null(breaks)
  oob <- .pal_oob_mode(oob, if (classes) "censor" else "squish")
  finite <- is.finite(x)
  result <- rep(na_colour, length(x))
  if (classes) {
    if (!is.null(limits)) {
      stop("limits cannot be combined with breaks: the outer boundaries of breaks are the limits", call. = FALSE)
    }
    breaks <- .pal_check_breaks(breaks)
    colours <- .pal_discrete(entry, length(breaks) - 1L)
    if (reverse) colours <- rev(colours)
    class <- rep(NA_integer_, length(x))
    class[finite] <- .bincode(x[finite], breaks, right = right, include.lowest = TRUE)
    if (identical(oob, "squish")) {
      class[finite & x < breaks[1L]] <- 1L
      class[finite & x > breaks[length(breaks)]] <- length(colours)
    }
    keep <- !is.na(class)
    result[keep] <- colours[class[keep]]
    return(result)
  }
  if (!is.null(limits)) {
    limits <- .pal_check_limits(limits)
  } else if (any(finite)) {
    limits <- range(x[finite])
  } else {
    return(result)
  }
  t <- rep(NA_real_, length(x))
  if (limits[1L] == limits[2L]) {
    t[finite] <- 0.5
  } else {
    t[finite] <- (x[finite] - limits[1L]) / (limits[2L] - limits[1L])
  }
  outside <- finite & (t < 0 | t > 1)
  if (identical(oob, "squish")) t[outside] <- pmin(pmax(t[outside], 0), 1) else t[outside] <- NA_real_
  if (reverse) t <- 1 - t
  keep <- !is.na(t)
  result[keep] <- .pal_from_t(entry, t[keep])
  result
}

.pal_na_colour <- function(entry, na_colour) {
  if (is.null(na_colour)) return(entry$na_colour)
  if (length(na_colour) != 1L || (!is.na(na_colour) && !is.character(na_colour))) {
    stop("na_colour must be NULL, NA or a single colour string", call. = FALSE)
  }
  if (is.na(na_colour)) NA_character_ else as.character(na_colour)
}

.pal_oob_mode <- function(oob, default) {
  if (is.null(oob)) return(default)
  if (!is.character(oob) || length(oob) != 1L || !oob %in% c("squish", "censor")) {
    stop("oob must be \"squish\" or \"censor\"", call. = FALSE)
  }
  oob
}

.pal_check_limits <- function(limits) {
  if (!is.numeric(limits) || length(limits) != 2L || any(!is.finite(limits)) || limits[1L] >= limits[2L]) {
    stop("limits must be two finite numbers with limits[1] < limits[2]", call. = FALSE)
  }
  as.double(limits)
}

.pal_check_breaks <- function(breaks) {
  if (!is.numeric(breaks) || length(breaks) < 2L || any(!is.finite(breaks)) || is.unsorted(breaks, strictly = TRUE)) {
    stop("breaks must be at least two finite, strictly increasing class boundaries", call. = FALSE)
  }
  as.double(breaks)
}

# ---- numbers in [0, 1] to colours: the continuous design of each palette --------------------------------------------------------

# `t`: finite numbers in [0, 1]. Returns upper-case hex colours.
.pal_from_t <- function(entry, t) {
  switch(entry$kind,
    bands = .pal_band_lookup(entry$colours, t),
    classic = .classic_hex(t),
    coral_day = .pal_coral_day_513[as.integer(round(pmin(pmax(t, 0), 1) * 512)) + 1L],
    coral_night = .rgb_hex(.night_rgb(t)),
    linear = .rgb_hex(.linear_rgb(entry$colours, t)),
    stop("internal error: unknown palette kind", call. = FALSE))
}

# depthmapX equal ranges: band index int((field - 1e-9) * bands), truncated towards zero, so band k > 1 is (k-1, k] / bands.
.pal_band_lookup <- function(colours, t) {
  colours[as.integer((pmin(pmax(t, 0), 1) - 1e-9) * length(colours)) + 1L]
}

.hex_rgb_matrix <- function(hex) {
  matrix(strtoi(c(substring(hex, 2L, 3L), substring(hex, 4L, 5L), substring(hex, 6L, 7L)), 16L), ncol = 3L)
}

.rgb_hex <- function(rgb) {
  sprintf("#%02X%02X%02X", as.integer(rgb[, 1L]), as.integer(rgb[, 2L]), as.integer(rgb[, 3L]))
}

# Piecewise linear interpolation of the encoded 8-bit channels through equally spaced anchors, rounded half to even.
.linear_rgb <- function(anchors, t) {
  a <- .hex_rgb_matrix(anchors)
  segments <- nrow(a) - 1L
  position <- pmin(pmax(t, 0), 1) * segments
  k <- pmin(floor(position), segments - 1L)
  u <- position - k
  low <- a[k + 1L, , drop = FALSE]
  high <- a[k + 2L, , drop = FALSE]
  round(low + (high - low) * u)
}

# ---- depthmapX Classic mapping ----------------------------------------

# `htmlByte`: (unsigned char)((c + 0.0333) * 15) * 0x11, i.e. sixteen levels per channel. A non-finite argument converts to 0 on
# the x86-64 and AArch64 conversions of the source's out-of-range cast (formally undefined behaviour in C++).
.html_byte <- function(x) {
  level <- floor((x + 0.0333) * 15) * 17
  level[!is.finite(level)] <- 0
  level
}

# `field` in [0, 1]; `blue` and `red` are depthmapX's landmark sliders (defaults 0 and 1; the rPSTool API does not expose them).
.classic_rgb <- function(field, blue = 0, red = 1) {
  green <- blue + (red - blue) / 10
  r <- g <- b <- numeric(length(field))
  b1 <- field >= 0 & field < blue
  b2 <- field >= blue & field < (green + blue) / 2
  b3 <- field >= (green + blue) / 2 & field < green
  b4 <- field >= green & field < (green + red) / 2
  b5 <- field >= (green + red) / 2 & field < red
  b6 <- field >= red
  r[b1] <- .html_byte(0.5 * (blue - field[b1]) / blue)
  b[b1] <- 255
  b[b2] <- 255
  g[b2] <- .html_byte(2 * (field[b2] - blue) / (green - blue))
  b[b3] <- .html_byte(2 * (green - field[b3]) / (green - blue))
  g[b3] <- 255
  g[b4] <- 255
  r[b4] <- .html_byte(2 * (field[b4] - green) / (red - green))
  g[b5] <- .html_byte(2 * (red - field[b5]) / (red - green))
  r[b5] <- 255
  r[b6] <- 255
  b[b6] <- .html_byte(0.5 * (field[b6] - red) / (1 - red))
  cbind(r, g, b)
}

.classic_hex <- function(t) .rgb_hex(.classic_rgb(pmin(pmax(t, 0), 1)))

# ---- Coral Night: the original generator ----------------------------------------------------------------------------------------

.night_anchor_t <- c(0, 0.25, 0.5, 0.75, 1)
.night_parameters <- list(
  lightness = c(38.5, 44.408752936949185, 59.016990574754914, 70.36637328608104, 80),
  saturation = c(0.9999999999950034, 1, 0.608102864945657, 0.999999999992646, 0.9999999999987064),
  hue = c(-3.71337972804794, 8, -9.999999999999998, 5.295359468624341, 11.999999999999892))
.night_correction <- list(centre = 0.875, half_width = 0.125, rgb8 = c(-15, 6, 63))

.srgb_decode <- function(x) ifelse(x <= 0.04045, x / 12.92, ((x + 0.055) / 1.055)^2.4)
.srgb_encode <- function(x) ifelse(x <= 0.0031308, 12.92 * x, 1.055 * pmax(x, 0)^(1 / 2.4) - 0.055)
.luminance_weights <- c(0.2126, 0.7152, 0.0722)

# Linear interpolation on the equally spaced anchors (numpy.interp semantics: the last anchor is returned exactly).
.night_interp <- function(y, t) {
  j <- findInterval(t, .night_anchor_t, rightmost.closed = TRUE)
  j <- pmin(j, length(y) - 1L)
  slope <- (y[j + 1L] - y[j]) / (.night_anchor_t[j + 1L] - .night_anchor_t[j])
  value <- slope * (t - .night_anchor_t[j]) + y[j]
  value[t == 1] <- y[length(y)]
  value
}

# Monotone piecewise cubic Hermite interpolation with the shape-preserving derivatives of Fritsch and Butland, as scipy's
# PchipInterpolator computes them, evaluated at `xi`.
.pchip <- function(x, y, xi) {
  n <- length(x)
  h <- diff(x)
  m <- diff(y) / h
  d <- numeric(n)
  for (k in 2:(n - 1L)) {
    if (m[k - 1L] != 0 && m[k] != 0 && sign(m[k - 1L]) == sign(m[k])) {
      w1 <- 2 * h[k] + h[k - 1L]
      w2 <- h[k] + 2 * h[k - 1L]
      d[k] <- 1 / ((w1 / m[k - 1L] + w2 / m[k]) / (w1 + w2))
    }
  }
  edge <- function(h0, h1, m0, m1) {
    value <- ((2 * h0 + h1) * m0 - h0 * m1) / (h0 + h1)
    if (sign(value) != sign(m0)) 0 else if (sign(m0) != sign(m1) && abs(value) > 3 * abs(m0)) 3 * m0 else value
  }
  d[1L] <- edge(h[1L], h[2L], m[1L], m[2L])
  d[n] <- edge(h[n - 1L], h[n - 2L], m[n - 1L], m[n - 2L])
  i <- findInterval(xi, x, rightmost.closed = TRUE)
  i <- pmin(i, n - 1L)
  slope <- m[i]
  tt <- (d[i] + d[i + 1L] - 2 * slope) / h[i]
  c3 <- tt / h[i]
  c2 <- (slope - d[i]) / h[i] - tt
  dx <- xi - x[i]
  ((c3 * dx + c2) * dx + d[i]) * dx + y[i]
}

# Saturated reference colour of a hue in degrees, as three columns of encoded RGB in [0, 1] (HSV with s = v = 1).
.hue_template <- function(hue) {
  h <- hue / 60
  sector <- floor(h) %% 6
  f <- h - floor(h)
  channel <- function(constant, slope) constant[sector + 1L] + slope[sector + 1L] * f
  cbind(channel(c(1, 1, 0, 0, 0, 1), c(0, -1, 0, 0, 1, 0)),
        channel(c(0, 1, 1, 1, 0, 0), c(1, 0, 0, -1, 0, 0)),
        channel(c(0, 0, 0, 1, 1, 1), c(0, 0, 1, 0, 0, -1)))
}

# Ordered rainbow of constant target luminance: a monotone lightness curve fixes the luminance, a saturated reference colour is dimmed
# in linear light (or mixed with white), then saturation is reduced towards the neutral of equal luminance.
.night_rainbow <- function(t) {
  p <- .night_parameters
  lightness <- .pchip(.night_anchor_t, p$lightness, t)
  target <- ((lightness + 16) / 116)^3
  saturation <- .night_interp(p$saturation, t)
  hue <- (240 * (1 - t) + .night_interp(p$hue, t)) %% 360
  linear <- .srgb_decode(.hue_template(hue))
  base <- as.vector(linear %*% .luminance_weights)
  darkened <- linear * (target / base)
  mix <- (target - base) / (1 - base)
  lightened <- linear * (1 - mix) + mix
  maximum <- darkened
  brighter <- target > base
  maximum[brighter, ] <- lightened[brighter, ]
  .srgb_encode(pmin(pmax(target + saturation * (maximum - target), 0), 1))
}

# Of the eight neighbouring 8-bit cube corners choose the one whose linear luminance is closest to the target luminance.
.night_quantise <- function(rgb) {
  lo <- floor(rgb * 255)
  hi <- ceiling(rgb * 255)
  target <- as.vector(.srgb_decode(rgb) %*% .luminance_weights)
  best <- rep(Inf, nrow(rgb))
  chosen <- rgb
  for (a in 0:1) for (b in 0:1) for (c in 0:1) {
    corner <- cbind(if (a) hi[, 1L] else lo[, 1L], if (b) hi[, 2L] else lo[, 2L], if (c) hi[, 3L] else lo[, 3L]) / 255
    error <- abs(as.vector(.srgb_decode(corner) %*% .luminance_weights) - target) + 1e-10 * rowSums((corner - rgb)^2)
    better <- error < best   # the first corner wins ties, as numpy.argmin does
    best[better] <- error[better]
    chosen[better, ] <- corner[better, ]
  }
  chosen
}

# Integer RGB matrix of Coral Night at positions `t` in [0, 1].
.night_rgb <- function(t) {
  t <- pmin(pmax(t, 0), 1)
  base <- .night_quantise(.night_rainbow(t))
  weight <- pmax(0, 1 - abs(t - .night_correction$centre) / .night_correction$half_width)
  correction <- outer(weight, .night_correction$rgb8)
  round(pmin(pmax(base * 255 + correction, 0), 255))
}
