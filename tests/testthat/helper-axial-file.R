# Helpers for the axial_graph(<path>) tests (docs/spatial-io/axial-file-input.md). The fixtures in fixtures/axial-files/ are
# derived from the direct pinned-PST axial reference cases (see tools/make-axial-file-fixtures.R).
ax_native <- function(name, ...) .Call(get(paste0("C_rpst_", name), asNamespace("rPSTool")), ...)
ax_fixture <- function(name, ext) test_path("fixtures", "axial-files", paste0(name, ".", ext))
ax_rows <- function(rows, width = 2L) matrix(as.double(unlist(rows)), ncol = width, byrow = TRUE)
ax_vector <- function(values) as.double(unlist(values))
ax_reference <- function() dget(test_path("fixtures", "axial-inputs-direct-v3.3.2.R"))
ax_file_cases <- function() Filter(function(case) is.null(case$line_indices), ax_reference()$cases)

# Optional-input arguments of a reference case in their established matrix form.
ax_case_args <- function(case) {
  args <- case[intersect(names(case), c("unlinks", "points", "points_per_polygon", "polygon_point_interval"))]
  for (field in c("unlinks", "points")) if (field %in% names(args)) args[[field]] <- ax_rows(args[[field]])
  if ("points_per_polygon" %in% names(args)) args$points_per_polygon <- ax_vector(args$points_per_polygon)
  args
}
ax_case_lines <- function(case) ax_rows(case$x, 4L)

ax_exact_classes <- function(actual, expected) {
  expect_identical(is.na(actual), is.na(expected))
  expect_identical(is.nan(actual), is.nan(expected))
  expect_identical(is.infinite(actual), is.infinite(expected))
  expect_identical(actual[!is.finite(expected)], expected[!is.finite(expected)])
  expect_equal(actual[is.finite(expected)], expected[is.finite(expected)], tolerance = 1e-7)
}

# Everything the direct-PST reference records about one case, checked against a graph.
ax_expect_reference <- function(g, case) {
  info <- as.integer(unlist(case$native_info))
  info[[4L]] <- length(case$group_sizes)
  expect_identical(ax_native("graph_info", g$ptr), info)
  expect_identical(g$n_point_groups, info[[4L]])
  expect_identical(axial_line_lengths(g), ax_vector(case$lengths))
  expect_identical(unname(axial_crossing_coords(g)), ax_rows(case$crossings))
  state <- ax_native("graph_point_state", g$ptr)
  expect_equal(state[[1L]], ax_rows(case$point_state, 5L), tolerance = 1e-7)
  expect_identical(state[[2L]], as.integer(unlist(case$group_sizes)))
  for (expected in case$integrations) {
    radius <- do.call(analysis_radius, expected$radius)
    result <- rPSTool:::.pst_network_integration_run(g, radius = radius, junctions = TRUE)
    expect_identical(result$lines$node_count, as.integer(unlist(expected$counts)))
    ax_exact_classes(result$lines$integration, ax_vector(expected$scores))
    expect_identical(result$lines$total_depth, ax_vector(expected$depths))
    expect_identical(matrix(c(result$junctions$x, result$junctions$y), ncol = 2L), ax_rows(expected$junction_coords))
    ax_exact_classes(result$junctions$integration, ax_vector(expected$junction_scores))
  }
}

# Two graphs agree on every observable the package exposes (bit-identical: same coordinates, same PST code).
ax_expect_same_graph <- function(a, b, radii = list(NULL, analysis_radius(steps = 2), analysis_radius(walking = 250))) {
  expect_identical(c(a$n_lines, a$n_crossings, a$n_points, a$n_point_groups),
                   c(b$n_lines, b$n_crossings, b$n_points, b$n_point_groups))
  expect_identical(axial_line_lengths(a), axial_line_lengths(b))
  expect_identical(axial_crossing_coords(a), axial_crossing_coords(b))
  expect_identical(ax_native("graph_point_state", a$ptr), ax_native("graph_point_state", b$ptr))
  for (radius in radii)
    expect_identical(rPSTool:::.pst_network_integration_run(a, radius = radius, junctions = TRUE),
                     rPSTool:::.pst_network_integration_run(b, radius = radius, junctions = TRUE))
}

# GDAL's own read order of a FlatGeobuf file (an independent oracle for "physical file order").
ax_fgb_matrix <- function(path) {
  g <- sf::st_geometry(sf::st_read(path, quiet = TRUE))
  unname(t(vapply(g, function(l) c(l[1, ], l[2, ]), numeric(4))))
}
ax_lifecycle <- function() ax_native("graph_lifecycle")
ax_live <- function() { x <- ax_lifecycle(); x[[1]] - x[[2]] }
