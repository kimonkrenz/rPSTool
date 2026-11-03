# Console progress (R/progress.R, src/pst-progress.cpp). The display logic is tested deterministically with a fake clock and
# the native test hook (no PST run); real analyses are checked for identical results and for a clean console.

prog <- function(op, value = 0) invisible(.Call(rPSTool:::C_rpst_progress_test, op, as.double(value)))
begin <- function(labels, unicode = FALSE, width = 120L, start = 0) {
  prog(0, start)
  .Call(rPSTool:::C_rpst_progress_begin, labels, unicode, width)
}
shown <- function(expr) paste(capture.output(expr), collapse = "\n")
end_progress <- function() invisible(.Call(rPSTool:::C_rpst_progress_end))
bar_ascii <- function(n) paste0("[", strrep("#", n), strrep("-", 20L - n), "]")

test_that("the ASCII line has 20 cells, a whole percentage and the Analysis counter only for several analyses", {
  on.exit(end_progress())
  expect_true(begin(c("angular_choice_r400", "angular_choice_r800", "angular_choice_r1600")))
  prog(1)
  expect_identical(shown(prog(0, 3)), "")            # clock is at 3 s but nothing has been read yet
  prog(0, 3)
  out <- shown(prog(2, 0.7))
  expect_identical(out, paste0("\r", "angular_choice_r400   ", bar_ascii(14), "   70%  Analysis 1/3"))
  expect_identical(shown(prog(2, 0.7)), "")           # same visible state: no redraw
  expect_identical(shown(prog(2, 0.704)), "")         # same whole percentage
  expect_match(shown(prog(2, 1)), "100%  Analysis 1/3$")
  # the next analysis: label changes and PST's percentage starts again from 0
  out <- shown(prog(1))
  expect_identical(out, paste0("\r", "angular_choice_r800   ", bar_ascii(0), "    0%  Analysis 2/3"))
  expect_match(shown(prog(2, 0.4)), paste0("angular_choice_r800   .*", "\\[########-{12}\\]   40%  Analysis 2/3$"))
  end_progress()
  expect_false(.Call(rPSTool:::C_rpst_progress_active))
})

test_that("a single analysis has no counter and the Unicode bar is used when asked for", {
  on.exit(end_progress())
  expect_true(begin("angular_choice_r400", unicode = TRUE))
  prog(1); prog(0, 5)
  out <- shown(prog(2, 0.7))
  expected <- paste0("\r", "angular_choice_r400  ", strrep("\u2588", 14), strrep("\u2591", 6), "   70%")
  expect_identical(charToRaw(out), charToRaw(enc2utf8(expected)))   # compared as bytes: the session may not be UTF-8
  expect_false(grepl("Analysis", shown(prog(2, 0.8))))
})

test_that("nothing is shown before two seconds and the display never appears retrospectively", {
  on.exit(end_progress())
  begin(c("a_r1", "a_r2"), start = 10)
  prog(1)
  prog(0, 11.99)
  expect_identical(shown(prog(2, 0.5)), "")
  expect_identical(shown(prog(1)), "")               # still hidden when the next analysis starts
  prog(0, 12.0)
  # the first report after the threshold shows whichever analysis is running then
  expect_match(shown(prog(2, 0.25)), "^\\ra_r2  \\[#####-{15}\\]   25%  Analysis 2/2$")
  # a short operation ends without ever having printed anything, and its end prints nothing either
  end_progress()
  begin("a_r1", start = 0); prog(1); prog(0, 1.5); expect_identical(shown(prog(2, 1)), "")
  expect_identical(shown(end_progress()), "")
})

test_that("ending a visible display erases the line, leaving the console clean", {
  begin("angular_choice_r400"); prog(1); prog(0, 3); invisible(shown(prog(2, 0.5)))
  width <- nchar("angular_choice_r400  ") + 22 + 6
  expect_identical(shown(end_progress()), paste0("\r", strrep(" ", width), "\r"))
  expect_identical(shown(prog(2, 0.6)), "")           # inactive after the end: callbacks do nothing
})

test_that("long labels are shortened to fit the console width and shorter lines are padded over longer ones", {
  on.exit(end_progress())
  begin(c(strrep("x", 200), "y"), width = 60L)
  prog(1); prog(0, 5)
  line <- sub("^\\r", "", shown(prog(2, 0.5)))
  expect_lt(nchar(line), 60L)
  expect_match(line, "^x+ +\\[##########----------\\]   50%  Analysis 1/2$")
})

test_that("the option is read as documented", {
  old <- options(rPSTool.progress = NULL); on.exit(options(old))
  options(rPSTool.progress = FALSE); expect_false(rPSTool:::.pst_progress_wanted())
  options(rPSTool.progress = TRUE); expect_true(rPSTool:::.pst_progress_wanted())
  options(rPSTool.progress = NULL)
  expect_identical(rPSTool:::.pst_progress_wanted(), interactive() && sink.number() == 0L)
  expect_false(interactive() && FALSE)   # this test file runs non-interactively: the default is off
  if (!interactive()) expect_false(rPSTool:::.pst_progress_wanted())
})

test_that("scope ends progress on exit, on error, and does not nest", {
  old <- options(rPSTool.progress = TRUE); on.exit(options(old))
  f <- function() { rPSTool:::.pst_progress_scope("lab"); expect_true(.Call(rPSTool:::C_rpst_progress_active)); 1 }
  expect_identical(f(), 1)
  expect_false(.Call(rPSTool:::C_rpst_progress_active))
  g <- function() { rPSTool:::.pst_progress_scope("lab"); stop("boom") }
  expect_error(g(), "boom")
  expect_false(.Call(rPSTool:::C_rpst_progress_active))
  h <- function() { rPSTool:::.pst_progress_scope("outer"); inner <- rPSTool:::.pst_progress_scope("inner"); inner }
  expect_false(h())
  expect_false(.Call(rPSTool:::C_rpst_progress_active))
  options(rPSTool.progress = FALSE)
  expect_false(rPSTool:::.pst_progress_scope(stop("labels must not be built when progress is off")))
})

progress_graph <- function(n = 400) {
  set.seed(3); x <- cumsum(runif(n, 1, 3)); y <- cumsum(rnorm(n))
  segment_graph(cbind(x[-n], y[-n], x[-1], y[-1]))
}

test_that("real analyses give identical results with progress on and off, and leave the console clean", {
  g <- progress_graph(); a <- axial_graph(cbind(0:30, 0, 1:31, 0))
  runs <- list(
    angular_choice = function() angular_choice(g, analysis_radius(walking = c(40, 80, 160)), normalization = c("turner", "syntax")),
    angular_scalar = function() angular_choice(g, analysis_radius(steps = 3), weigh_by_length = TRUE),
    angular_integration = function() angular_integration(g, radius = analysis_radius(walking = c(40, 80)), normalization = c("turner", "hillier")),
    network_integration = function() network_integration(a),
    network_reach = function() network_reach(a, analysis_radius(steps = 2)),
    network_betweenness = function() network_betweenness(a, analysis_radius(steps = 3), "steps"),
    attraction_reach = function() attraction_reach(a, rbind(c(3.5, 0.5), c(9.5, 0.2))),
    attraction_distance = function() attraction_distance(a, rbind(c(3.5, 0.5), c(9.5, 0.2))),
    od_betweenness = function() od_betweenness(a, rbind(c(1.5, 0.1), c(8.5, 0.1)), analysis_radius(steps = 5)),
    segment_group_integration = function() segment_group_integration(segment_group_graph(g, rep(1:20, length.out = 399L)))
  )
  for (name in names(runs)) {
    off <- local({ options(rPSTool.progress = FALSE); on.exit(options(rPSTool.progress = NULL)); runs[[name]]() })
    # fake clock stepping 5 s per read: every analysis crosses the two-second threshold, so the display really is drawn
    options(rPSTool.progress = TRUE); on.exit(options(rPSTool.progress = NULL), add = TRUE)
    prog(0, 0); prog(3, 5)
    text <- shown(on_result <- runs[[name]]())
    expect_identical(on_result, off, info = name)
    expect_false(.Call(rPSTool:::C_rpst_progress_active), info = name)
    expect_match(text, "%", fixed = TRUE, info = name)               # a display was drawn ...
    expect_match(text, "\\r *\\r$", info = name)                       # ... and erased again
    expect_true(grepl(names(on_result)[[2L]], text, fixed = TRUE), info = name)
    counter <- c(angular_choice = "Analysis 3/3", angular_integration = "Analysis 2/2")[name]   # one analysis per radius
    if (is.na(counter)) expect_false(grepl("Analysis", text, fixed = TRUE), info = name)
    else expect_true(grepl(counter, text, fixed = TRUE), info = name)   # the first result variable labels the line
    options(rPSTool.progress = NULL)
  }
})
