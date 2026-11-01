#' Colour palettes for ordered numerical values
#'
#' rPSTool ships eleven palettes for drawing network analysis results, in three groups: (1) seven colour modes reproduced from
#' depthmapX v0.9.1 with their historical identities and mapping rules; (2) two white-background adaptations
#' (`axmanesque_white`, `depthmapx_classic_white`) that reuse some depthmapX colours; and (3) two palettes designed for rPSTool
#' (`coral_night`, `coral_day`). `colour_palettes()` lists them, `colour_palette()` returns the exact discrete colours of a
#' palette, and [colour_map()] maps numbers to colours. None of these functions needs ggplot2 and none alters an analysis result;
#' [scale_colour_rpst_c()] and friends use the same definitions in ggplot2.
#'
#' @section Palettes:
#' \describe{
#'   \item{`axmanesque`, `axmanesque_hue`, `blue_red`, `purple_orange`, `greyscale`, `monochrome`, `depthmapx_classic`}{The seven
#'   depthmapX v0.9.1 modes ("Equal Ranges (3-Colour)", "(3-Colour Hue Only)", "(Blue-Red)", "(Purple-Orange)", "(Greyscale)",
#'   "(Monochrome)" and "depthmapX Classic"). Their colour values are reproduced from depthmapX (`salalib/pafcolor.cpp`, tag
#'   v0.9.1; GPL-3.0-or-later, Copyright (C) 2011-2012 Tasos Varoudis) and the Classic band mapping was reimplemented in R. They
#'   are included for historical fidelity and are unchanged. The first six are
#'   *equal ranges* palettes with 10, 10, 7, 7, 7 and 7 native bands, so their continuous mapping is a band lookup, not a
#'   gradient. `monochrome` shares the greyscale colours; depthmapX also uses it to vary line thickness, which a colour mapping does
#'   not reproduce. `depthmapx_classic` has no discrete colours: it is a piecewise calculated rainbow with its landmarks at
#'   `0, .05, .10, .55, 1` (blue, cyan, green, yellow, red), channels quantised to sixteen levels. It is not a gradient with equally
#'   spaced stops.}
#'   \item{`axmanesque_white`, `depthmapx_classic_white`}{White-background adaptations (designs "A, pale cyan start" and "F,
#'   clearer yellow transition"), each defined by nine anchor colours. Some anchors reuse depthmapX colours: seven of the nine
#'   `axmanesque_white` anchors (3 to 9) are colours of the depthmapX Equal Ranges (3-Colour) array, and the `depthmapx_classic_white`
#'   anchors at the cyan, green and red landmarks are the depthmapX Classic landmark colours (`#00FFFF`, `#00FF00`, `#FF0000`). The
#'   remaining anchors (the pale cyan start colours, the intermediate Classic hues and the adjusted Classic yellow) are not
#'   depthmapX values. They are additional palettes: the native ten-band Axmanesque and the native Classic mapping are separate
#'   identifiers and are unchanged.}
#'   \item{`coral_night`}{Coral Night, designed for rPSTool: a rainbow-style scale for a black or dark background.}
#'   \item{`coral_day`}{Coral Day, designed for rPSTool (the selected "H, earlier warmth" design): a scale for a white or light
#'   background.}
#' }
#' The four non-historical palettes have nine anchors at `seq(0, 1, length.out = 9)` and the nested discrete variants of 3 colours
#' (anchors 1, 5, 9), 5 colours (1, 3, 5, 7, 9) and 9 colours (all). Their continuous designs are: for the two Coral palettes the
#' selected curves (Coral Day: nearest-index lookup of the selected 513-point table, `round(t * 512)` with ties to even; Coral
#' Night: the original generator, evaluated at the requested position), and for the two white adaptations piecewise linear
#' interpolation of the encoded sRGB channels through the nine anchors, rounded to the nearest integer with ties to even (no
#' other colour space is used). Continuous positions outside `[0, 1]` are clipped.
#'
#' @section Intended backgrounds and what is claimed:
#' `coral_night` is intended for a black or dark background; `coral_day`, `axmanesque_white` and `depthmapx_classic_white` for a white
#' or light one; the historical modes carry no stated background. The `background` column of `colour_palettes()` records this
#' intention. **No function in rPSTool changes a plot's background**: choosing a palette never alters the theme.
#'
#' These are visual design aims, not demonstrated properties. The Coral palettes were designed to give an overall dark-to-light (Night)
#' or light-to-dark (Day) progression of values with visibly distinct colour transitions; the anchors are ordered in lightness but small
#' lightness dips occur along the continuous curves. The white adaptations aim to reduce the visual weight of dark blues and strong
#' reds on white while retaining recognisable legacy hue sequences, and still contain bright cyan and green and uneven lightness. No
#' palette has been observer-tested, and rPSTool does not claim colour-blind safety, perceptual uniformity or improved reading accuracy
#' for any of them. The depthmapX source comments describe its Blue-Red and Purple-Orange arrays as red-green colour-blind safe;
#' rPSTool neither verifies nor repeats that claim.
#'
#' Provenance, source files and the decisions behind these definitions are in the repository's palette documentation
#' (<https://github.com/kimonkrenz/rPSTool/blob/main/docs/palettes.md>; the repository is not public yet). The Blue-Red and
#' Purple-Orange colour values coincide with the 7-class ColorBrewer RdYlBu and PuOr schemes (Brewer et al.); ColorBrewer's
#' licence terms were not verified.
#'
#' @param palette A palette identifier: one of `colour_palettes()$palette`.
#' @param n The number of discrete colours. `NULL` (the default) returns the palette's native set: 10, 10, 7, 7, 7 and 7 for the
#'   equal-range depthmapX palettes and 9 for the other four palettes. Those four also accept 3 and 5. Any other number is an
#'   error: colours are never interpolated to fill a requested size. `depthmapx_classic` has no discrete colours.
#' @param reverse `TRUE` reverses the order of the colours (high to low).
#' @return `colour_palettes()` returns a data frame with one row per palette: `palette` (identifier), `name`, `family`
#'   (`"depthmapX"` or `"rPSTool"`), `background` (intended background as a hex colour, or `NA`), `sizes` (available discrete sizes,
#'   or `"none"`), `continuous` (how a continuous value is mapped) and `na_colour` (the default missing-value colour; `NA`
#'   means transparent). `colour_palette()` returns an unnamed character vector of upper-case `"#RRGGBB"` colours ordered from the
#'   lowest to the highest value (or reversed).
#' @seealso [colour_map()], [scale_colour_rpst_c()]
#' @export
#' @examples
#' colour_palettes()[, c("palette", "name", "background")]
#' colour_palette("coral_day")
#' colour_palette("coral_night", n = 5)
#' colour_palette("coral_night", n = 3, reverse = TRUE)
#' colour_palette("axmanesque")                  # the original ten bands
#' # Sampling the selected continuous design instead of the nested discrete colours:
#' colour_map(seq(0, 1, length.out = 17), "coral_night")
colour_palettes <- function() {
  table <- .pal_table()
  data.frame(
    palette = vapply(table, `[[`, "", "id"),
    name = vapply(table, `[[`, "", "name"),
    family = vapply(table, `[[`, "", "family"),
    background = vapply(table, function(p) p$background, NA_character_),
    sizes = vapply(table, function(p) {
      if (identical(p$kind, "classic")) "none" else paste(.pal_sizes(p), collapse = ", ")
    }, ""),
    continuous = vapply(table, `[[`, "", "continuous"),
    na_colour = vapply(table, function(p) p$na_colour, NA_character_),
    row.names = NULL, stringsAsFactors = FALSE)
}

#' @rdname colour_palettes
#' @export
colour_palette <- function(palette, n = NULL, reverse = FALSE) {
  entry <- .pal_entry(palette)
  .pal_check_flag(reverse, "reverse")
  colours <- .pal_discrete(entry, n)
  if (reverse) rev(colours) else colours
}

# ---- registry ---------------------------------------------------------------------------------------------------------------

.pal_table <- function() {
  historical <- function(id, name, colours, ...) {
    list(id = id, name = name, family = "depthmapX", kind = "bands", colours = colours, background = NA_character_,
         continuous = paste0("equal-range band lookup (", length(colours), " bands)"), na_colour = "#7F7F7F", ...)
  }
  anchored <- function(id, name, kind, colours, background, continuous) {
    list(id = id, name = name, family = "rPSTool", kind = kind, colours = colours, background = background,
         continuous = continuous, na_colour = "#7F7F7F")
  }
  table <- list(
    historical("axmanesque", "Equal Ranges (3-Colour)", .pal_axmanesque),
    historical("axmanesque_hue", "Equal Ranges (3-Colour Hue Only)", .pal_axmanesque_hue),
    historical("blue_red", "Equal Ranges (Blue-Red)", .pal_blue_red),
    historical("purple_orange", "Equal Ranges (Purple-Orange)", .pal_purple_orange),
    historical("greyscale", "Equal Ranges (Greyscale)", .pal_greyscale),
    historical("monochrome", "Equal Ranges (Monochrome)", .pal_greyscale),
    list(id = "depthmapx_classic", name = "depthmapX Classic", family = "depthmapX", kind = "classic", colours = NULL,
         background = NA_character_, continuous = "calculated piecewise rainbow, 16 levels per channel", na_colour = "#7F7F7F"),
    anchored("coral_night", "Coral Night", "coral_night", .pal_coral_night, "#000000",
             "selected curve (original generator)"),
    anchored("coral_day", "Coral Day", "coral_day", .pal_coral_day, "#FFFFFF",
             "selected curve (513-point table, nearest index)"),
    anchored("axmanesque_white", "Axmanesque White", "linear", .pal_axmanesque_white, "#FFFFFF",
             "linear sRGB interpolation through nine anchors"),
    anchored("depthmapx_classic_white", "depthmapX Classic White", "linear", .pal_depthmapx_classic_white, "#FFFFFF",
             "linear sRGB interpolation through nine anchors"))
  for (i in seq_along(table)) {   # depthmapX greyscale and monochrome hide missing values; every colour mode shows grey
    if (table[[i]]$id %in% c("greyscale", "monochrome")) table[[i]]$na_colour <- NA_character_
  }
  table
}

.pal_ids <- function() vapply(.pal_table(), `[[`, "", "id")

.pal_entry <- function(palette) {
  if (!is.character(palette) || length(palette) != 1L || is.na(palette)) {
    stop("palette must be a single palette identifier; see colour_palettes()$palette", call. = FALSE)
  }
  table <- .pal_table()
  ids <- vapply(table, `[[`, "", "id")
  hit <- match(palette, ids)
  if (is.na(hit)) {
    stop("unknown palette '", palette, "'; available palettes: ", paste(ids, collapse = ", "), call. = FALSE)
  }
  table[[hit]]
}

# Discrete sizes a palette offers: the native band count of a depthmapX palette, 3, 5 and 9 for the derived palettes.
.pal_sizes <- function(entry) {
  if (identical(entry$kind, "bands")) length(entry$colours) else if (identical(entry$kind, "classic")) integer() else c(3L, 5L, 9L)
}

# Nested discrete colours of the derived palettes: anchors 1, 5, 9 / 1, 3, 5, 7, 9 / all nine.
.pal_nested_positions <- list(`3` = c(1L, 5L, 9L), `5` = c(1L, 3L, 5L, 7L, 9L), `9` = 1:9)

.pal_discrete <- function(entry, n) {
  if (identical(entry$kind, "classic")) {
    stop("palette '", entry$id, "' has no discrete colours: depthmapX Classic is a calculated continuous mapping. ",
         "Use colour_map() or the derived palette 'depthmapx_classic_white'", call. = FALSE)
  }
  sizes <- .pal_sizes(entry)
  if (is.null(n)) n <- if (identical(entry$kind, "bands")) length(entry$colours) else 9L
  if (!is.numeric(n) || length(n) != 1L || is.na(n) || n != round(n) || !n %in% sizes) {
    stop("palette '", entry$id, "' offers ", paste(sizes, collapse = ", "), " discrete colours; n = ",
         paste(format(n), collapse = ", "), " is not available (colours are never interpolated)", call. = FALSE)
  }
  if (identical(entry$kind, "bands")) entry$colours else entry$colours[.pal_nested_positions[[as.character(n)]]]
}

.pal_check_flag <- function(x, name) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) stop(name, " must be TRUE or FALSE", call. = FALSE)
}
