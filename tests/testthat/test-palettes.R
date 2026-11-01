# Palette definitions, nested subsets, continuous mappings and the retrieval API (docs/palettes.md). The expected colours are the
# approved definitions, typed out here independently of R/palette-data.R, and fixtures/palette-reference.R (the 513-point curves
# and the output of the original Coral Night generator).
source(test_path("fixtures", "palette-reference.R"))

ids <- c("axmanesque", "axmanesque_hue", "blue_red", "purple_orange", "greyscale", "monochrome", "depthmapx_classic",
         "coral_night", "coral_day", "axmanesque_white", "depthmapx_classic_white")
expected_native <- list(
  axmanesque = c("#3333DD", "#3388DD", "#22CCDD", "#22CCBB", "#22DD88", "#88DD22", "#BBCC22", "#DDCC22", "#DD8833", "#DD3333"),
  axmanesque_hue = c("#3333DD", "#3377DD", "#33BBDD", "#33DDBB", "#33DD55", "#55DD33", "#BBDD33", "#DDBB33", "#DD7733", "#DD3333"),
  blue_red = c("#4575B4", "#91BFDB", "#E0F3F8", "#FFFFBF", "#FEE090", "#FC8D59", "#D73027"),
  purple_orange = c("#542788", "#998EC3", "#D8DAEB", "#F7F7F7", "#FEE0B6", "#F1A340", "#B35806"),
  greyscale = c("#000000", "#444444", "#777777", "#AAAAAA", "#CCCCCC", "#EEEEEE", "#FFFFFF"))
expected_native$monochrome <- expected_native$greyscale
expected_white <- list(
  axmanesque_white = c("#C4F0F4", "#79DFE8", "#22CCDD", "#22CCBB", "#22DD88", "#BBCC22", "#DDCC22", "#DD8833", "#DD3333"),
  depthmapx_classic_white = c("#C4F5FF", "#78EFFF", "#00FFFF", "#00FF77", "#00FF00", "#77FF00", "#DFD33A", "#FF7700", "#FF0000"))

test_that("all eleven palettes are listed with their intended backgrounds", {
  table <- colour_palettes()
  expect_identical(table$palette, ids)
  expect_identical(table$background[match(c("coral_night", "coral_day", "axmanesque_white", "depthmapx_classic_white"),
                                          table$palette)], c("#000000", "#FFFFFF", "#FFFFFF", "#FFFFFF"))
  expect_true(all(is.na(table$background[table$family == "depthmapX"])))
  expect_identical(table$family, c(rep("depthmapX", 7), rep("rPSTool", 4)))
  expect_identical(table$sizes[table$palette == "depthmapx_classic"], "none")
  expect_identical(table$sizes[table$palette == "coral_day"], "3, 5, 9")
  expect_identical(table$sizes[table$palette == "axmanesque"], "10")
  expect_identical(table$na_colour[table$palette %in% c("greyscale", "monochrome")], c(NA_character_, NA_character_))
  expect_identical(table$na_colour[table$palette == "blue_red"], "#7F7F7F")
})

test_that("the historical depthmapX palettes keep their native band counts and exact colours", {
  for (id in names(expected_native)) {
    expect_identical(colour_palette(id), expected_native[[id]], info = id)
    expect_identical(colour_palette(id, n = length(expected_native[[id]])), expected_native[[id]], info = id)
  }
  expect_length(colour_palette("axmanesque"), 10L)
  expect_length(colour_palette("axmanesque_hue"), 10L)
  expect_identical(colour_palette("monochrome"), colour_palette("greyscale"))
  expect_error(colour_palette("axmanesque", n = 9), "offers 10 discrete colours")
  expect_error(colour_palette("blue_red", n = 3), "offers 7 discrete colours")
  expect_error(colour_palette("depthmapx_classic"), "no discrete colours")
})

test_that("the native Axmanesque (ten bands) differs from its nine-anchor white adaptation", {
  expect_length(colour_palette("axmanesque_white"), 9L)
  expect_false(identical(colour_palette("axmanesque"), colour_palette("axmanesque_white")))
  expect_false("#DD3333" %in% colour_palette("axmanesque_white")[1:8])
  expect_error(colour_palette("axmanesque_white", n = 10), "offers 3, 5, 9")
})

test_that("the derived palettes return the approved 9, 5 and 3 colour sets", {
  for (id in c("coral_night", "coral_day")) {
    reference <- palette_reference[[id]]
    expect_identical(colour_palette(id), reference$discrete_9)
    expect_identical(colour_palette(id, n = 9), reference$discrete_9)
    expect_identical(colour_palette(id, n = 5), reference$discrete_5)
    expect_identical(colour_palette(id, n = 3), reference$discrete_3)
  }
  expect_identical(colour_palette("coral_night")[c(1, 3, 5, 7, 9)], c("#3135FE", "#007486", "#5E9C5C", "#A6B501", "#FFB3B0"))
  expect_identical(colour_palette("coral_day", 3), c("#DFF0FF", "#82CD5C", "#C24537"))
  for (id in names(expected_white)) {
    anchors <- expected_white[[id]]
    expect_identical(colour_palette(id), anchors)
    expect_identical(colour_palette(id, 5), anchors[c(1, 3, 5, 7, 9)])
    expect_identical(colour_palette(id, 3), anchors[c(1, 5, 9)])
  }
  # Classic White differs from the earlier tentative Classic A only at anchor 7.
  expect_identical(colour_palette("depthmapx_classic_white")[7], "#DFD33A")
})

test_that("the nested sets are subsets of the nine anchors and sit on the continuous curves", {
  for (id in ids[8:11]) {
    nine <- colour_palette(id)
    expect_true(all(colour_palette(id, 5) %in% nine))
    expect_true(all(colour_palette(id, 3) %in% colour_palette(id, 5)))
    expect_identical(colour_map(seq(0, 1, length.out = 9), id), nine, info = id)
    expect_identical(colour_map(c(0, 0.5, 1), id), colour_palette(id, 3), info = id)
  }
})

test_that("reverse reverses the discrete colours and the continuous design, never the palette definition", {
  for (id in ids[-7]) {
    expect_identical(colour_palette(id, reverse = TRUE), rev(colour_palette(id)))
  }
  expect_identical(colour_palette("coral_day", 5, reverse = TRUE), rev(palette_reference$coral_day$discrete_5))
  x <- c(0, 0.2, 0.55, 0.9, 1)
  for (id in ids) expect_identical(colour_map(x, id, reverse = TRUE), colour_map(1 - x, id), info = id)
  expect_false(identical(colour_map(x, "coral_day"), colour_map(x, "coral_day", reverse = TRUE)))
})

test_that("Coral Day follows nearest-index lookup of its 513-point curve, ties to even", {
  curve <- palette_reference$coral_day$curve_513
  expect_identical(colour_map((0:512) / 512, "coral_day"), curve)
  expect_identical(colour_map(c(0, 1), "coral_day"), c("#DFF0FF", "#C24537"))
  # 0.5/512 and 1.5/512 are ties: 0 and 2 are the even neighbours.
  expect_identical(colour_map(c(0.5, 1.5, 2.5) / 512, "coral_day", limits = c(0, 1)), curve[c(1, 3, 3)])
  expect_identical(colour_map(c(0.3, 0.7) / 512, "coral_day", limits = c(0, 1)), curve[c(1, 2)])
})

test_that("Coral Night reproduces the 513-point curve and the original generator at arbitrary positions", {
  expect_identical(colour_map((0:512) / 512, "coral_night"), palette_reference$coral_night$curve_513)
  reference <- palette_reference$night_reference
  expect_identical(colour_map(reference$k / 4096, "coral_night", limits = c(0, 1)), reference$hex)
  # The local correction is centred on t = 0.875 (anchor 8) and absent elsewhere.
  expect_identical(colour_map(0.875, "coral_night", limits = c(0, 1)), "#EFAD65")
})

test_that("the white adaptations interpolate encoded sRGB linearly and round ties to even", {
  # Midpoint of anchors 1 and 2: R (196 + 121) / 2 = 158.5 -> 158, G (240 + 223) / 2 = 231.5 -> 232, B (244 + 232) / 2 = 238.
  expect_identical(colour_map(1 / 16, "axmanesque_white", limits = c(0, 1)), "#9EE8EE")
  # Classic White anchors 3 and 4 (#00FFFF, #00FF77): B (255 + 119) / 2 = 187.
  expect_identical(colour_map(5 / 16, "depthmapx_classic_white", limits = c(0, 1)), "#00FFBB")
  # A quarter of the way from anchor 6 (#77FF00) to anchor 7 (#DFD33A): R 119 + 104/4 = 145, G 255 - 44/4 = 244, B 58/4 = 14.5 -> 14.
  expect_identical(colour_map((5 + 0.25) / 8, "depthmapx_classic_white", limits = c(0, 1)), "#91F40E")
  # Quarter steps are exact in double arithmetic; the result is a colour between its anchors on every channel.
  t <- seq(0, 1, length.out = 129)
  rgb <- t(vapply(colour_map(t, "axmanesque_white"), function(h) strtoi(substring(h, c(2, 4, 6), c(3, 5, 7)), 16L), integer(3)))
  anchors <- t(vapply(expected_white$axmanesque_white, function(h) strtoi(substring(h, c(2, 4, 6), c(3, 5, 7)), 16L), integer(3)))
  segment <- pmin(floor(t * 8) + 1, 8)
  for (channel in 1:3) {
    low <- pmin(anchors[segment, channel], anchors[segment + 1, channel])
    high <- pmax(anchors[segment, channel], anchors[segment + 1, channel])
    expect_true(all(rgb[, channel] >= low & rgb[, channel] <= high))
  }
})

test_that("equal-range depthmapX palettes use band lookup with upper-inclusive boundaries and depthmapX's epsilon", {
  for (id in c("axmanesque", "axmanesque_hue", "blue_red", "purple_orange", "greyscale", "monochrome")) {
    bands <- expected_native[[id]]
    n <- length(bands)
    edge <- (1:(n - 1)) / n
    expect_identical(colour_map(c(0, 1), id), bands[c(1, n)], info = id)
    expect_identical(colour_map(edge, id, limits = c(0, 1)), bands[1:(n - 1)], info = id)          # (k-1, k] / n belongs to band k
    expect_identical(colour_map(edge + 1e-8, id, limits = c(0, 1)), bands[2:n], info = id)
    expect_identical(colour_map((seq_len(n) - 0.5) / n, id, limits = c(0, 1)), bands, info = id)
  }
  expect_identical(colour_map(0.1, "axmanesque", limits = c(0, 1)), "#3333DD")
  expect_identical(colour_map(0.1 + 1e-8, "axmanesque", limits = c(0, 1)), "#3388DD")
})

test_that("depthmapX Classic is the calculated sixteen-level rainbow with landmarks at 0, .05, .10, .55, 1", {
  at <- function(t) colour_map(t, "depthmapx_classic", limits = c(0, 1))
  # Hand-computed from makeDepthmapClassic / htmlByte: 2 * (f - blue) / (green - blue) etc., then trunc((c + 0.0333) * 15) * 17.
  expect_identical(at(c(0, 0.025, 0.05, 0.075, 0.1, 0.3, 0.8, 1)),
                   c("#0000FF", "#0077FF", "#00FFFF", "#00FF77", "#00FF00", "#77FF00", "#FF7700", "#FF0000"))
  grid <- at(seq(0, 1, by = 0.001))
  channels <- unlist(lapply(grid, function(h) strtoi(substring(h, c(2, 4, 6), c(3, 5, 7)), 16L)))
  expect_true(all(channels %in% (17L * (0:15))))
  # A gradient through five equally spaced stops is a different design: it would put yellow at 0.5 and green at 0.25.
  expect_false(identical(at(0.25), "#00FF00"))
  expect_identical(at(0.54), "#FFFF00")                               # (0.54 - 0.1) * 2 / 0.9 = 0.978 -> level 15 in the red channel
  # Classic is not its nine-anchor white adaptation sampled at the same positions.
  expect_false(identical(colour_map(seq(0, 1, length.out = 9), "depthmapx_classic"), colour_palette("depthmapx_classic_white")))
})

test_that("colour_map handles limits, clipping, missing values and constant data", {
  x <- c(10, 20, 30, NA, NaN, Inf, -Inf)
  out <- colour_map(x, "coral_day")
  expect_identical(out[1:3], colour_map(c(0, 0.5, 1), "coral_day"))
  expect_identical(out[4:7], rep("#7F7F7F", 4))
  expect_identical(colour_map(x, "coral_day", na_colour = "white")[4:7], rep("white", 4))
  expect_identical(colour_map(x, "coral_day", na_colour = NA)[4:7], rep(NA_character_, 4))
  expect_identical(colour_map(x, "greyscale")[4:7], rep(NA_character_, 4))                   # depthmapX hides greyscale NAs
  expect_identical(colour_map(x, "greyscale", na_colour = "#123456")[4], "#123456")
  # explicit limits: squish (the default) clamps like depthmapX, censor removes the value
  expect_identical(colour_map(c(-5, 0, 50, 100, 200), "coral_day", limits = c(0, 100)),
                   colour_map(c(0, 0, 0.5, 1, 1), "coral_day", limits = c(0, 1)))
  expect_identical(colour_map(c(-5, 0, 100, 200), "coral_day", limits = c(0, 100), oob = "censor"),
                   c("#7F7F7F", "#DFF0FF", "#C24537", "#7F7F7F"))
  expect_identical(colour_map(5, "coral_night", limits = c(5, 6)), "#3135FE")
  # constant data without limits: every value at t = 0.5
  expect_identical(colour_map(c(7, 7, 7), "coral_day"), rep(colour_map(0.5, "coral_day", limits = c(0, 1)), 3))
  expect_identical(colour_map(c(NA, NA), "coral_day"), c("#7F7F7F", "#7F7F7F"))
  expect_identical(colour_map(numeric(), "coral_day"), character())
  expect_identical(colour_map(1:3, "coral_day"), colour_map(c(1, 2, 3), "coral_day"))
})

test_that("class boundaries: endpoint inclusion, unequal widths, exact class colours and reversal", {
  five <- palette_reference$coral_day$discrete_5
  breaks <- c(0, 2, 5, 10, 20, 30)
  x <- c(0, 1, 2, 2.0001, 5, 5.5, 10, 12, 20, 30)
  expect_identical(colour_map(x, "coral_day", breaks = breaks), five[c(1, 1, 1, 2, 2, 3, 3, 4, 4, 5)])
  expect_identical(colour_map(x, "coral_day", breaks = breaks, right = FALSE), five[c(1, 1, 2, 2, 3, 3, 4, 4, 5, 5)])
  expect_identical(colour_map(x, "coral_day", breaks = breaks, reverse = TRUE),
                   rev(five)[c(1, 1, 1, 2, 2, 3, 3, 4, 4, 5)])
  expect_identical(colour_map(c(-1, 31, 0, 30), "coral_day", breaks = breaks), c("#7F7F7F", "#7F7F7F", five[1], five[5]))
  expect_identical(colour_map(c(-1, 31), "coral_day", breaks = breaks, oob = "squish"), five[c(1, 5)])
  expect_identical(colour_map(c(NA, NaN, Inf, 3), "coral_day", breaks = breaks), c(rep("#7F7F7F", 3), five[2]))
  expect_identical(colour_map(c(NA, 3), "greyscale", breaks = c(0, 1, 2, 3, 4, 5, 6, 7)),
                   c(NA, expected_native$greyscale[3]))
  # classes with nested 3 and 9 colours and a native depthmapX palette
  expect_identical(colour_map(c(1, 5, 9), "coral_night", breaks = c(0, 3, 6, 10)), palette_reference$coral_night$discrete_3)
  expect_identical(colour_map(0.5 + 0:8, "coral_day", breaks = 0:9), palette_reference$coral_day$discrete_9)
  expect_identical(colour_map(0.5 + 0:9, "axmanesque", breaks = 0:10), expected_native$axmanesque)
  # the class colours are the discrete colours, not a gradient sampled at class mid-points
  expect_false(identical(colour_map(c(1, 4, 8, 15, 25), "coral_day", breaks = breaks),
                         colour_map(c(1, 4, 8, 15, 25), "coral_day", limits = c(0, 30))))
})

test_that("invalid arguments are rejected with informative errors", {
  expect_error(colour_map("a", "coral_day"), "numeric")
  expect_error(colour_map(factor(1:2), "coral_day"), "numeric")
  expect_error(colour_map(1:3, "nope"), "unknown palette 'nope'")
  expect_error(colour_palette(c("coral_day", "coral_night")), "single palette")
  expect_error(colour_palette(NA_character_), "single palette")
  expect_error(colour_palette("coral_day", n = 4), "offers 3, 5, 9")
  expect_error(colour_palette("coral_day", n = 5.5), "offers 3, 5, 9")
  expect_error(colour_palette("coral_day", n = NA), "offers 3, 5, 9")
  expect_error(colour_palette("coral_day", reverse = NA), "reverse")
  expect_error(colour_map(1:3, "coral_day", limits = c(2, 1)), "limits")
  expect_error(colour_map(1:3, "coral_day", limits = c(1, 1)), "limits")
  expect_error(colour_map(1:3, "coral_day", limits = c(0, NA)), "limits")
  expect_error(colour_map(1:3, "coral_day", limits = 1), "limits")
  expect_error(colour_map(1:3, "coral_day", breaks = c(0, 1, 2, 3), limits = c(0, 3)), "cannot be combined")
  expect_error(colour_map(1:3, "coral_day", breaks = c(0, 3, 2, 5)), "strictly increasing")
  expect_error(colour_map(1:3, "coral_day", breaks = c(0, 1, 1, 3)), "strictly increasing")
  expect_error(colour_map(1:3, "coral_day", breaks = c(0, NA, 3)), "finite")
  expect_error(colour_map(1:3, "coral_day", breaks = 1), "at least two")
  expect_error(colour_map(1:3, "coral_day", breaks = c(0, 1, 2)), "offers 3, 5, 9")            # two classes
  expect_error(colour_map(1:3, "depthmapx_classic", breaks = c(0, 1, 2, 3)), "no discrete colours")
  expect_error(colour_map(1:3, "coral_day", oob = "drop"), "oob")
  expect_error(colour_map(1:3, "coral_day", na_colour = c("a", "b")), "na_colour")
  expect_error(colour_map(1:3, "coral_day", right = NA), "right")
})

test_that("rPSTool offers no classification and requires no classification package", {
  exports <- getNamespaceExports("rPSTool")
  expect_false(any(grepl("classif|interval|quantile|jenks|fisher|natural", exports, ignore.case = TRUE)))
  description <- read.dcf(system.file("DESCRIPTION", package = "rPSTool"))
  required <- paste(c(description[, intersect(c("Depends", "Imports", "LinkingTo"), colnames(description))]), collapse = ",")
  expect_false(grepl("classInt|ggplot2|scales", required))
})
