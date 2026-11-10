# Shared multi-radius infrastructure (R/radius.R, R/angular-multi.R): analysis-independent helpers that later
# analyses reuse. Angular behaviour itself is covered by test-multi-radius*.R.

test_that("the multi-radius error names exactly the registered analyses", {
  expect_identical(rPSTool:::.pst_multi_radius_list(c("a")), "a()")
  expect_identical(rPSTool:::.pst_multi_radius_list(c("a", "b")), "a() and b()")
  expect_identical(rPSTool:::.pst_multi_radius_list(c("a", "b", "c")), "a(), b() and c()")
  expect_identical(rPSTool:::.pst_multi_radius_functions, c("angular_choice", "angular_integration"))
  r <- analysis_radius(walking = c(100, 200))
  expect_error(rPSTool:::.pst_validate_radius(r),
               "supported only by angular_choice() and angular_integration()", fixed = TRUE)
})

test_that("unsupported radius fields are rejected before validation or native work", {
  r <- analysis_radius(walking = c(100, 200), angular = 90)
  expect_error(rPSTool:::.pst_radius_require_fields(r, c("walking", "steps"), "f"),
               "f() does not support the angular radius limit(s); supported: walking, steps.", fixed = TRUE)
  expect_invisible(rPSTool:::.pst_radius_require_fields(r, c("walking", "angular"), "f"))
  expect_identical(rPSTool:::.pst_radius_require_fields(NULL, "steps", "f"), NULL)   # a plain steps number has nothing to check
  # a varying field outside the supported set is rejected like a scalar one
  expect_error(rPSTool:::.pst_radius_plan(analysis_radius(straight = c(1, 2)), TRUE, fields = "walking", fn = "f"),
               "does not support the straight")
  plan <- rPSTool:::.pst_radius_plan(analysis_radius(walking = c(5, 10)), TRUE, fields = c("walking", "steps"), fn = "f")
  expect_identical(plan$varying, "walking")
  expect_identical(plan$values, c(5, 10))
})

test_that("the generic column spec honours the identifier column and the supplied descriptions", {
  plan <- rPSTool:::.pst_radius_plan(analysis_radius(walking = c(100, 200)), TRUE)
  # a delegating comparison against .pst_multi_spec() would be circular; the angular output is pinned by the
  # pre-refactor fixture test below
  one <- function(config) list(list(name = paste0("x_", rPSTool:::.pst_nm_radius(config)), role = "normalized",
                                    normalization = "std"))
  generic <- rPSTool:::.pst_multi_spec_from(plan, one)
  expect_identical(generic$name, c("x_rw100", "x_rw200"))
  expect_identical(generic$radius, 1:2)
  expect_identical(generic$normalization, c("std", "std"))
  # the identifier column participates in the duplicate-name check
  expect_error(rPSTool:::.pst_multi_spec_from(plan, function(config) list(list(name = "group_id", role = "x")),
                                              id_col = "group_id"), "duplicate")
})

test_that("the generic multi frame and metadata describe other identifiers, graph types and tables", {
  plan <- rPSTool:::.pst_radius_plan(analysis_radius(walking = c(100, 200)), TRUE)
  spec <- rPSTool:::.pst_multi_spec("choice", plan, "none", FALSE)
  columns <- lapply(seq_len(nrow(spec)), function(i) as.numeric(i + 0:2))
  frame <- rPSTool:::.pst_multi_frame(columns, spec, plan)
  expect_identical(names(frame)[[1L]], "segment_id")
  expect_identical(frame$segment_id, 1:3)
  other <- rPSTool:::.pst_multi_frame(columns, spec, plan, id_col = "group_id", ids = c(7L, 8L, 9L))
  expect_identical(names(other)[[1L]], "group_id")
  expect_identical(other$group_id, c(7L, 8L, 9L))
  expect_identical(names(other)[-1L], spec$name)

  fx <- list(); attr(fx, "crs") <- NULL
  md <- rPSTool:::.pst_multi_metadata("fn", list(), plan, NULL, spec, 3L, fx, graph_type = "axial",
                                      order = "my order", float_columns = FALSE)
  expect_identical(md[["rpst:schema"]], "2")
  expect_identical(md[["rpst:graph_type"]], "axial")
  expect_identical(md[["rpst:order"]], "my order")
  expect_false("rpst:float_columns" %in% names(md))
  expect_false("rpst:normalizations" %in% names(md))   # no normalisation choice, no entry
  expect_identical(md[["rpst:radius_varying"]], "walking")
  ang <- rPSTool:::.pst_multi_metadata("fn", list(), plan, c("none", "standard"), spec, 3L, fx)
  expect_identical(ang[["rpst:graph_type"]], "segment")
  expect_true("rpst:float_columns" %in% names(ang))
  expect_identical(ang[["rpst:normalizations"]], "[\"none\",\"standard\"]")
})

# Independent regression: the expected values are literals captured from the package before the infrastructure was generalised
# (fixtures/angular-multi-schema-pre-refactor.R), not recomputed through the refactored helpers.
test_that("angular multi-radius specs, schema-2 metadata and frames are unchanged by the refactor", {
  source(testthat::test_path("fixtures", "angular-multi-schema-pre-refactor.R"), local = TRUE)
  ns <- asNamespace("rPSTool")
  g <- segment_graph(cbind(0:4 * 3, 0, 1:5 * 3, 0))
  cases <- list(
    choice_walk = list(an = "choice", radius = analysis_radius(walking = c(100, 500)), norms = c("none", "standard"),
                       weighted = FALSE),
    choice_steps_fixed = list(an = "choice", radius = analysis_radius(steps = c(1, 3), angular = 180),
                              norms = c("turner", "syntax", "none"), weighted = TRUE),
    integ_walk = list(an = "integration", radius = analysis_radius(walking = c(100, 500)), norms = c("turner", "hillier"),
                      weighted = TRUE, wo = TRUE),
    integ_angular = list(an = "integration", radius = analysis_radius(angular = c(90, 180)), norms = "syntax",
                         weighted = FALSE, wo = FALSE))
  expect_identical(names(cases), names(angular_multi_expected))
  for (nm in names(cases)) {
    k <- cases[[nm]]; want <- angular_multi_expected[[nm]]
    plan <- ns$.pst_radius_plan(k$radius, TRUE)
    spec <- if (k$an == "choice") ns$.pst_multi_spec("choice", plan, k$norms, k$weighted, FALSE, 0, 1)
            else ns$.pst_multi_spec("integration", plan, k$norms, k$weighted, k$wo, 0, 1)
    expect_identical(as.data.frame(spec), want$spec, info = nm)          # names, roles, radius index, normalisation, order
    expect_identical(attr(spec, "cols"), want$cols, info = nm)           # full column descriptions
    params <- if (k$an == "choice")
      list(radius = NULL, weigh_by_length = k$weighted, normalization = NULL, angle_threshold = 0, angle_precision = 1)
    else list(radius = NULL, weigh_by_length = k$weighted, normalization = NULL, angle_threshold = 0, angle_precision = 1,
              weight_outputs = k$wo)
    md <- ns$.pst_multi_metadata(if (k$an == "choice") "angular_choice" else "angular_integration", params, plan,
                                 k$norms, spec, 5L, structure(list(), crs = NULL))
    md <- md[!names(md) %in% c("rpst:version", "rpst:pst_version", "rpst:pst_commit")]
    expect_identical(as.list(md), want$metadata, info = nm)              # schema 2, radius, manifest, normalisations
    frame <- if (k$an == "choice") angular_choice(g, k$radius, weigh_by_length = k$weighted, normalization = k$norms)
             else angular_integration(g, radius = k$radius, weigh_by_length = k$weighted, normalization = k$norms,
                                      weight_outputs = k$wo)
    expect_identical(names(frame), want$frame_names, info = nm)
    expect_identical(vapply(frame, typeof, ""), want$frame_types, info = nm)
    expect_identical(attr(frame, "rpst_manifest")$columns, want$manifest_columns, info = nm)
    expect_identical(attr(frame, "rpst_manifest")$radii, want$manifest_radii, info = nm)
  }
})
