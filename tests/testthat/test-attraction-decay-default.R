# Attraction Reach: effective decay_constant when it is not supplied.
# Authority: engine values from the pinned C API (evidence N, fixture
# attraction-decay-default-direct-v3.3.2.R); default selection from the original
# PST for QGIS wizard (attractionreachwiz.py:84-85, pow with C = 1; evidence S).
adr_ref <- function() dget(test_path("fixtures", "attraction-decay-default-direct-v3.3.2.R"))
adr_graph <- function(ref) axial_graph(matrix(as.double(unlist(ref$graph$x)), ncol = 4L, byrow = TRUE))
adr_points <- function(ref) matrix(as.double(unlist(ref$graph$points)), ncol = 2L, byrow = TRUE)
adr_call <- function(g, ref, case, ...) {
  attraction_reach(g, adr_points(ref), radius = do.call(analysis_radius, case$radius),
                       distance = case$distance, attraction_values = as.double(unlist(ref$graph$values)), ...)
}

test_that("omitted decay_constant is 0 for constant decay and 1 for power, curve and divide", {
  ref <- adr_ref()
  expect_identical(ref$pst_commit, unname(rPSTool:::.pst_engine_pin()[["pst_commit"]]))
  # One worker: with several, the order of float accumulation (and so the last bit) varies between calls. The test must not
  # depend on a value another test file happened to leave in the environment.
  old <- Sys.getenv("RPST_NUM_THREADS", unset = NA_character_)
  Sys.setenv(RPST_NUM_THREADS = "1")
  on.exit(if (is.na(old)) Sys.unsetenv("RPST_NUM_THREADS") else Sys.setenv(RPST_NUM_THREADS = old), add = TRUE)
  g <- adr_graph(ref)
  on.exit(.Call(get("C_rpst_graph_release", asNamespace("rPSTool")), g$ptr), add = TRUE)
  seen <- 0L
  for (case in ref$cases) {
    expected <- as.double(unlist(case$scores))
    # explicit constants always reproduce the direct native value
    explicit <- adr_call(g, ref, case, decay = case$decay, decay_constant = case$constant)
    expect_equal(explicit$attraction_reach, expected, tolerance = 2e-6)
    implied <- if (case$decay == "constant") 0 else 1
    if (case$constant == implied) {
      omitted <- adr_call(g, ref, case, decay = case$decay)
      expect_identical(omitted$attraction_reach, explicit$attraction_reach)
      seen <- seen + 1L
    }
  }
  expect_equal(seen, 12L)   # 3 distances x (constant@0, power/curve/divide@1)
})

test_that("the fixture discriminates the effective default from the alternatives", {
  ref <- adr_ref()
  by <- function(decay, const, dist)
    Filter(function(c) c$decay == decay && c$constant == const && c$distance == dist, ref$cases)[[1L]]$scores
  for (decay in c("power", "curve", "divide")) {
    one <- as.double(unlist(by(decay, 1, "walking")))
    expect_false(isTRUE(all.equal(one, as.double(unlist(by(decay, 0, "walking"))))), info = decay)
    expect_false(isTRUE(all.equal(one, as.double(unlist(by(decay, 2, "walking"))))), info = decay)
    expect_true(any(one != 0), info = decay)
  }
})

test_that("an explicit constant of zero keeps its meaning for nonconstant decay", {
  ref <- adr_ref()
  g <- adr_graph(ref)
  on.exit(.Call(get("C_rpst_graph_release", asNamespace("rPSTool")), g$ptr), add = TRUE)
  case <- Filter(function(c) c$decay == "power" && c$constant == 0 && c$distance == "steps", ref$cases)[[1L]]
  out <- adr_call(g, ref, case, decay = "power", decay_constant = 0)
  expect_equal(out$attraction_reach, as.double(unlist(case$scores)), tolerance = 2e-6)
  expect_false(isTRUE(all.equal(out$attraction_reach,
                                adr_call(g, ref, case, decay = "power")$attraction_reach)))
  # unrelated Reach behaviour is unchanged: the default call is constant decay at 0
  expect_identical(adr_call(g, ref, case)$attraction_reach,
                   adr_call(g, ref, case, decay = "constant", decay_constant = 0)$attraction_reach)
})

test_that("the file-backed path records and uses the effective constant", {
  skip_if_not_installed("arrow", "25.0.0")
  ref <- adr_ref()
  g <- adr_graph(ref)
  on.exit(.Call(get("C_rpst_graph_release", asNamespace("rPSTool")), g$ptr), add = TRUE)
  file <- tempfile(fileext = ".parquet"); on.exit(unlink(file), add = TRUE)
  case <- Filter(function(c) c$decay == "curve" && c$constant == 1 && c$distance == "steps", ref$cases)[[1L]]
  adr_call(g, ref, case, decay = "curve", output_file = file)
  got <- rs_read(file)
  expect_equal(as.double(got$attraction_reach), as.double(unlist(case$scores)), tolerance = 2e-6)
  p <- jsonlite::fromJSON(rs_pq(file)$GetSchema()$metadata[["rpst:parameters"]])
  expect_equal(p$decay_constant, 1)
})
