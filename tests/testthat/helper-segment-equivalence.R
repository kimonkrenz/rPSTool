# Shared by the path-input equivalence tests (GeoParquet, FlatGeobuf).

segment_balance <- function() {
  counts <- native_segment("lifecycle")
  counts[[1]] - counts[[2]]
}

# Every currently bound analysis that consumes a segment graph, run on one graph.
segment_analyses <- function(g) {
  grouping <- segment_grouping(g, angle_threshold = 20)
  group_graph <- segment_group_graph(g, grouping$group_id)
  list(
    integration = angular_integration(g),
    integration_steps = angular_integration(g, radius = analysis_radius(steps = 3)),
    integration_walk = angular_integration(g, radius = analysis_radius(walking = 250)),
    integration_weighted = angular_integration(g, weigh_by_length = TRUE, weight_outputs = TRUE),
    integration_syntax = angular_integration(g, normalization = "syntax",
                                                 radius = analysis_radius(steps = 4)),
    integration_hillier = angular_integration(g, normalization = "hillier",
                                                  weigh_by_length = TRUE),
    integration_angle = angular_integration(g, angle_threshold = 30, angle_precision = 4),
    choice = angular_choice(g),
    choice_walk = angular_choice(g, radius = analysis_radius(walking = 250)),
    choice_weighted = angular_choice(g, weigh_by_length = TRUE, normalization = "turner"),
    choice_angle = angular_choice(g, normalization = "syntax", angle_threshold = 30,
                                      angle_precision = 4, radius = analysis_radius(steps = 3)),
    grouping = grouping,
    group_integration = segment_group_integration(group_graph),
    group_integration_steps = segment_group_integration(group_graph, analysis_radius(steps = 1)))
}

gp_lattice <- function() {
  unname(as.matrix(utils::read.csv(test_path("fixtures", "geoparquet", "expected-lattice.csv"))))
}
gp_lines <- function(matrix) {
  sf::st_sfc(lapply(seq_len(nrow(matrix)), function(i)
    sf::st_linestring(rbind(matrix[i, 1:2], matrix[i, 3:4]))), crs = sf::st_crs(NA))
}
