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

test_that("the generic column spec reproduces the angular spec and honours the identifier column", {
  plan <- rPSTool:::.pst_radius_plan(analysis_radius(walking = c(100, 200)), TRUE)
  angular <- rPSTool:::.pst_multi_spec("choice", plan, "none", FALSE)
  generic <- rPSTool:::.pst_multi_spec_from(plan, function(config) rPSTool:::.pst_nm_angular_choice(config, FALSE, "none", 0, 1))
  expect_identical(angular, generic)
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
