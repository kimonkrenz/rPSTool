# The public API: exact exported names, no residual `pst_` prefix, documented, and the S3 class identifiers unchanged.
test_that("the exports are exactly the documented functions and none carries a pst_ prefix", {
  expected <- c("analysis_radius", "angular_choice", "angular_integration", "attraction_distance", "attraction_reach",
                "axial_crossing_coords", "axial_graph", "axial_line_lengths", "compare_line_results", "create_junctions",
                "create_segment_map", "isovist", "isovist_context", "isovist_context_free", "network_betweenness",
                "network_integration", "network_reach", "od_betweenness", "raster_data", "raster_free", "raster_to_polygons",
                "segment_graph", "segment_group_graph", "segment_group_integration", "segment_grouping",
                # palettes (R/palettes.R, R/palette-mapping.R, R/palette-scales.R) and the example data (R/example-data.R)
                "colour_map", "colour_palette", "colour_palettes", "load_example_data", "scale_colour_rpst_b", "scale_colour_rpst_c",
                "scale_fill_rpst_b", "scale_fill_rpst_c")
  expect_setequal(getNamespaceExports("rPSTool"), expected)
  expect_false(any(grepl("^pst_", getNamespaceExports("rPSTool"))))
  expect_false("rpst_project_status" %in% getNamespaceExports("rPSTool"))
})

test_that("every exported function is documented and S3 class identifiers keep their names", {
  lib <- dirname(system.file(package = "rPSTool"))
  for (fn in getNamespaceExports("rPSTool"))   # utils::help() resolves a topic through the installed help index
    expect_gt(length(do.call(utils::help, list(fn, package = "rPSTool", lib.loc = lib))), 0L)
  g <- axial_graph(rbind(c(0, 0, 10, 0), c(5, -5, 5, 5)))
  expect_s3_class(g, "pst_graph")
  expect_s3_class(segment_graph(rbind(c(0, 0, 10, 0))), "pst_segment_graph")
  expect_s3_class(analysis_radius(steps = 1), "pst_radius")
})
