# ggplot2 colour and fill scales (optional dependency). Built plot colours must equal colour_map(); legends must show the exact class
# colours; a palette never changes the plot background.
skip_if_not_installed("ggplot2")
skip_if_not_installed("gtable")
skip_if_not_installed("grid")

scale_fixture <- function() data.frame(x = 1:12, y = 1, v = c(0, 1, 2, 3.5, 5, 7, 9.9, 10, 12, 15, 20, 30))
built_colours <- function(plot, aesthetic = "colour") ggplot2::ggplot_build(plot)$data[[1L]][[aesthetic]]

# Fill colours of every rectangle in a grob tree, in drawing order.
rect_fills <- function(grob) {
  fills <- character()
  walk <- function(g) {
    if (inherits(g, "gtable")) for (child in g$grobs) walk(child)
    if (inherits(g, "gTree")) for (child in g$children) walk(child)
    if (inherits(g, "rect") && !is.null(g$gp$fill)) fills <<- c(fills, g$gp$fill)
  }
  walk(grob)
  fills
}

# Fill colours of the populated legend of a gtable. ggplot2 names the guide box "guide-box" (3.4 and earlier) or by position,
# for example "guide-box-right" (3.5 and later, where the unused positions hold empty guide boxes), so every layout entry whose
# name starts with "guide-box" is examined and the first with any filled rectangle is used.
legend_fills_of <- function(table) {
  for (i in which(grepl("^guide-box", table$layout$name))) {
    fills <- rect_fills(table$grobs[[i]])
    if (length(fills)) return(fills)
  }
  character()
}
legend_fills <- function(plot) legend_fills_of(ggplot2::ggplotGrob(plot))

# TRUE when `expected` occurs in `fills` as consecutive entries, in that order (the legend also holds key backgrounds).
has_run <- function(fills, expected) {
  n <- length(expected)
  n <= length(fills) && any(vapply(seq_len(length(fills) - n + 1L), function(i) identical(fills[i:(i + n - 1L)], expected), NA))
}

test_that("the legend helper handles both ggplot2 guide-box naming conventions and picks the populated guide", {
  legend <- gtable::gtable(grid::unit(1, "null"), grid::unit(1, "null"))
  legend <- gtable::gtable_add_grob(legend, grid::rectGrob(gp = grid::gpar(fill = "#AAAAAA")), 1, 1)
  legend <- gtable::gtable_add_grob(legend, grid::rectGrob(gp = grid::gpar(fill = "#BBBBBB")), 1, 1)
  empty <- ggplot2::zeroGrob()
  make_table <- function(names, grobs) {
    table <- gtable::gtable(grid::unit(rep(1, length(names)), "null"), grid::unit(1, "null"))
    for (i in seq_along(names)) table <- gtable::gtable_add_grob(table, grobs[[i]], 1, i, name = names[i])
    table
  }
  expect_identical(legend_fills_of(make_table("guide-box", list(legend))), c("#AAAAAA", "#BBBBBB"))
  expect_identical(legend_fills_of(make_table(c("guide-box-left", "guide-box-right", "guide-box-bottom"),
                                              list(empty, legend, empty))), c("#AAAAAA", "#BBBBBB"))
  expect_identical(legend_fills_of(make_table("panel", list(legend))), character())
})

test_that("continuous scales map exactly as colour_map does", {
  d <- scale_fixture()
  for (id in c("coral_night", "coral_day", "axmanesque_white", "depthmapx_classic_white", "axmanesque", "blue_red", "depthmapx_classic")) {
    p <- ggplot2::ggplot(d, ggplot2::aes(x, y, colour = v)) + ggplot2::geom_point() + scale_colour_rpst_c(id)
    expect_identical(built_colours(p), colour_map(d$v, id), info = id)
  }
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y, fill = v)) + ggplot2::geom_tile() +
    scale_fill_rpst_c("coral_night", limits = c(0, 40), reverse = TRUE)
  expect_identical(built_colours(p, "fill"), colour_map(d$v, "coral_night", limits = c(0, 40), reverse = TRUE))
})

test_that("continuous scales honour explicit limits, out-of-range handling and missing values", {
  d <- scale_fixture()
  d$v[c(2, 5)] <- c(NA, 45)
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y, colour = v)) + ggplot2::geom_point() +
    scale_colour_rpst_c("coral_day", limits = c(0, 40))
  expect_identical(built_colours(p), colour_map(d$v, "coral_day", limits = c(0, 40)))
  expect_identical(built_colours(p)[2], "#7F7F7F")
  expect_identical(built_colours(p)[5], "#C24537")                                  # squished to the high end
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y, colour = v)) + ggplot2::geom_point() +
    scale_colour_rpst_c("coral_day", limits = c(0, 40), oob = "censor", na.value = "red")
  expect_identical(built_colours(p)[c(2, 5)], c("red", "red"))
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y, colour = v)) + ggplot2::geom_point() + scale_colour_rpst_c("greyscale")
  expect_true(is.na(built_colours(p)[2]))
})

test_that("binned scales give class i exactly colour i, for unequal widths, with a matching legend", {
  d <- scale_fixture()
  breaks <- c(0, 2, 5, 10, 20, 30)
  five <- colour_palette("coral_day", 5)
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y, colour = v)) + ggplot2::geom_point() + scale_colour_rpst_b(breaks, "coral_day")
  expect_identical(built_colours(p), colour_map(d$v, "coral_day", breaks = breaks))
  expect_identical(built_colours(p), five[c(1, 1, 1, 2, 2, 3, 3, 3, 4, 4, 4, 5)])
  expect_true(has_run(legend_fills(p), five))
  expect_false(has_run(legend_fills(p), rev(five)))
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y, fill = v)) + ggplot2::geom_tile() +
    scale_fill_rpst_b(breaks, "coral_night", reverse = TRUE)
  expect_identical(built_colours(p, "fill"), colour_map(d$v, "coral_night", breaks = breaks, reverse = TRUE))
  expect_true(has_run(legend_fills(p), rev(colour_palette("coral_night", 5))))
  expect_false(has_run(legend_fills(p), colour_palette("coral_night", 5)))
  # every nested size and a native depthmapX palette
  for (spec in list(list("coral_day", c(0, 10, 20, 30)), list("axmanesque_white", 0:9 * 3.3), list("blue_red", 0:7 * 4.3))) {
    brks <- spec[[2]]
    p <- ggplot2::ggplot(d, ggplot2::aes(x, y, colour = v)) + ggplot2::geom_point() + scale_colour_rpst_b(brks, spec[[1]])
    expect_identical(built_colours(p), colour_map(d$v, spec[[1]], breaks = brks), info = spec[[1]])
    expect_true(has_run(legend_fills(p), colour_palette(spec[[1]], length(brks) - 1L)), info = spec[[1]])
  }
})

test_that("binned scales close classes as requested, censor out-of-range values and colour missing values", {
  d <- data.frame(x = 1:6, y = 1, v = c(0, 2, 2.5, 5, NA, 31))
  breaks <- c(0, 2, 5, 10, 20, 30)
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y, colour = v)) + ggplot2::geom_point() + scale_colour_rpst_b(breaks, "coral_day")
  expect_identical(built_colours(p), colour_map(d$v, "coral_day", breaks = breaks))
  expect_identical(built_colours(p)[5:6], c("#7F7F7F", "#7F7F7F"))
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y, colour = v)) + ggplot2::geom_point() +
    scale_colour_rpst_b(breaks, "coral_day", right = FALSE)
  expect_identical(built_colours(p), colour_map(d$v, "coral_day", breaks = breaks, right = FALSE))
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y, colour = v)) + ggplot2::geom_point() +
    scale_colour_rpst_b(breaks, "coral_day", oob = "squish")
  expect_identical(built_colours(p)[6], colour_palette("coral_day", 5)[5])
})

test_that("scales are validated before use and never change the plot background", {
  expect_error(scale_colour_rpst_c("nope"), "unknown palette")
  expect_error(scale_colour_rpst_c("coral_day", limits = c(1, 1)), "limits")
  expect_error(scale_colour_rpst_c("coral_day", reverse = NA), "reverse")
  expect_error(scale_colour_rpst_c("coral_day", oob = "x"), "oob")
  expect_error(scale_fill_rpst_b(c(0, 1, 2), "coral_day"), "offers 3, 5, 9")
  expect_error(scale_fill_rpst_b(c(2, 1, 0, 3), "coral_day"), "strictly increasing")
  expect_error(scale_fill_rpst_b(c(0, 1, 2, 3), "depthmapx_classic"), "no discrete colours")
  d <- scale_fixture()
  bare <- ggplot2::ggplot(d, ggplot2::aes(x, y, colour = v)) + ggplot2::geom_point()
  for (id in c("coral_night", "coral_day")) {
    styled <- bare + scale_colour_rpst_c(id)
    expect_identical(styled$theme, bare$theme)
    expect_identical(ggplot2::theme_get()$panel.background, ggplot2::theme_get()$panel.background)
    expect_null(styled$theme$panel.background)
    expect_null(styled$theme$plot.background)
  }
  local({
    dark <- bare + ggplot2::theme(panel.background = ggplot2::element_rect(fill = "black")) + scale_colour_rpst_c("coral_day")
    expect_identical(dark$theme$panel.background$fill, "black")             # the user's background is kept, not overridden
  })
})
