#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>

extern SEXP rpst_native_smoke(void);
extern SEXP rpst_graph_create(SEXP);
extern SEXP rpst_graph_info(SEXP);
extern SEXP rpst_graph_release(SEXP);
extern SEXP rpst_graph_lifecycle(void);
extern SEXP rpst_network_integration(SEXP, SEXP);
extern SEXP rpst_segment_graph_create(SEXP);
extern SEXP rpst_segment_graph_info(SEXP);
extern SEXP rpst_segment_graph_release(SEXP);
extern SEXP rpst_segment_graph_lifecycle(void);
extern SEXP rpst_angular_integration(SEXP, SEXP);
extern SEXP rpst_radius_validate(SEXP);
extern SEXP rpst_angular_choice_multi(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_betweenness_multi(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_betweenness_multi_stream(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_reach_multi(SEXP, SEXP, SEXP);
extern SEXP rpst_network_integration_multi(SEXP, SEXP, SEXP);
extern SEXP rpst_network_integration_multi_stream(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_reach_multi_stream(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_angular_integration_multi(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_angular_choice_multi_stream(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_angular_integration_multi_stream(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_angular_instrumentation(SEXP, SEXP);
extern SEXP rpst_axial_instrumentation(SEXP, SEXP);
extern SEXP rpst_progress_begin(SEXP, SEXP, SEXP);
extern SEXP rpst_progress_end(void);
extern SEXP rpst_progress_active(void);
extern SEXP rpst_progress_test(SEXP, SEXP);
extern SEXP rpst_workers(void);
extern SEXP rpst_reach(SEXP, SEXP);
extern SEXP rpst_reach_points(SEXP, SEXP, SEXP);
extern SEXP rpst_betweenness(SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_betweenness_weighted(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_angular_choice(SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_segment_grouping(SEXP, SEXP, SEXP);
extern SEXP rpst_segment_grouping_stream(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_segment_group_graph_create(SEXP, SEXP);
extern SEXP rpst_segment_group_graph_info(SEXP);
extern SEXP rpst_segment_group_graph_release(SEXP);
extern SEXP rpst_segment_group_graph_lifecycle(void);
extern SEXP rpst_segment_group_integration(SEXP, SEXP);
extern SEXP rpst_segment_group_output_test(SEXP, SEXP, SEXP);
extern SEXP rpst_graph_create_inputs(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_graph_line_lengths(SEXP);
extern SEXP rpst_graph_crossing_coords(SEXP);
extern SEXP rpst_network_integration_outputs(SEXP, SEXP, SEXP);
extern SEXP rpst_graph_point_state(SEXP);
extern SEXP rpst_attraction_reach(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_attraction_distance(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_od_betweenness(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_angular_integration_controls(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_angular_choice_controls(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_create_junctions(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_create_segment_map(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_construction_lifecycle(void);
extern SEXP rpst_isovist_context_create(SEXP, SEXP, SEXP);
extern SEXP rpst_isovist_context_release(SEXP);
extern SEXP rpst_isovist_calculate(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_isovist_lifecycle(void);
extern SEXP rpst_compare_results(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_raster_release(SEXP);
extern SEXP rpst_raster_data(SEXP);
extern SEXP rpst_raster_polygons(SEXP, SEXP, SEXP);
extern SEXP rpst_raster_lifecycle(void);
extern SEXP rpst_path_is_regular_file(SEXP);
extern SEXP rpst_fgb_inspect(SEXP);
extern SEXP rpst_fgb_columns(SEXP);
extern SEXP rpst_fgb_write_spatial(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_file_identity(SEXP);
extern SEXP rpst_output_entry_exists(SEXP);
extern SEXP rpst_output_remove_entry(SEXP);
extern SEXP rpst_fgb_segment_graph(SEXP, SEXP, SEXP);
extern SEXP rpst_fgb_axial_graph(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_geoparquet_axial_graph(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_axial_graph_new_pointer(void);
extern SEXP rpst_angular_integration_stream(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_angular_choice_stream(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_result_test_export(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_result_test_drive(SEXP, SEXP);
extern SEXP rpst_result_counters(void);
extern SEXP rpst_output_supported(void);
extern SEXP rpst_output_create_exclusive(SEXP);
extern SEXP rpst_output_publish(SEXP, SEXP, SEXP);
extern SEXP rpst_network_integration_stream(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_reach_points_stream(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_od_betweenness_stream(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_attraction_reach_stream(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_attraction_distance_stream(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_betweenness_weighted_stream(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_segment_group_integration_stream(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_segment_group_output_test_stream(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_arrow_stream_new(void);
extern SEXP rpst_arrow_stream_is_live(SEXP);
extern SEXP rpst_arrow_stream_release(SEXP);
extern SEXP rpst_arrow_stream_free(SEXP);
extern SEXP rpst_arrow_set_addressable_limit(SEXP);
extern SEXP rpst_geoparquet_segment_graph(SEXP, SEXP, SEXP, SEXP);
extern SEXP rpst_arrow_decode_matrix(SEXP, SEXP, SEXP);
extern SEXP rpst_arrow_test_export(SEXP, SEXP);
extern SEXP rpst_arrow_test_counters(void);
extern SEXP rpst_segment_graph_new_pointer(void);
static const R_CallMethodDef call_methods[] = {
    {"rpst_fgb_inspect", (DL_FUNC) &rpst_fgb_inspect, 1},
    {"rpst_fgb_columns", (DL_FUNC) &rpst_fgb_columns, 1},
    {"rpst_fgb_write_spatial", (DL_FUNC) &rpst_fgb_write_spatial, 7},
    {"rpst_file_identity", (DL_FUNC) &rpst_file_identity, 1},
    {"rpst_output_entry_exists", (DL_FUNC) &rpst_output_entry_exists, 1},
    {"rpst_output_remove_entry", (DL_FUNC) &rpst_output_remove_entry, 1},
    {"rpst_fgb_segment_graph", (DL_FUNC) &rpst_fgb_segment_graph, 3},
    {"rpst_fgb_axial_graph", (DL_FUNC) &rpst_fgb_axial_graph, 7},
    {"rpst_geoparquet_axial_graph", (DL_FUNC) &rpst_geoparquet_axial_graph, 8},
    {"rpst_axial_graph_new_pointer", (DL_FUNC) &rpst_axial_graph_new_pointer, 0},
    {"rpst_angular_integration_stream", (DL_FUNC) &rpst_angular_integration_stream, 12},
    {"rpst_angular_choice_stream", (DL_FUNC) &rpst_angular_choice_stream, 11},
    {"rpst_result_test_export", (DL_FUNC) &rpst_result_test_export, 10},
    {"rpst_result_test_drive", (DL_FUNC) &rpst_result_test_drive, 2},
    {"rpst_result_counters", (DL_FUNC) &rpst_result_counters, 0},
    {"rpst_output_supported", (DL_FUNC) &rpst_output_supported, 0},
    {"rpst_output_create_exclusive", (DL_FUNC) &rpst_output_create_exclusive, 1},
    {"rpst_output_publish", (DL_FUNC) &rpst_output_publish, 3},
    {"rpst_path_is_regular_file", (DL_FUNC) &rpst_path_is_regular_file, 1},
    {"rpst_network_integration_stream", (DL_FUNC) &rpst_network_integration_stream, 7},
    {"rpst_reach_points_stream", (DL_FUNC) &rpst_reach_points_stream, 8},
    {"rpst_od_betweenness_stream", (DL_FUNC) &rpst_od_betweenness_stream, 12},
    {"rpst_attraction_reach_stream", (DL_FUNC) &rpst_attraction_reach_stream, 17},
    {"rpst_attraction_distance_stream", (DL_FUNC) &rpst_attraction_distance_stream, 15},
    {"rpst_betweenness_weighted_stream", (DL_FUNC) &rpst_betweenness_weighted_stream, 11},
    {"rpst_segment_group_integration_stream", (DL_FUNC) &rpst_segment_group_integration_stream, 7},
    {"rpst_segment_group_output_test_stream", (DL_FUNC) &rpst_segment_group_output_test_stream, 8},
    {"rpst_arrow_stream_new", (DL_FUNC) &rpst_arrow_stream_new, 0},
    {"rpst_arrow_stream_is_live", (DL_FUNC) &rpst_arrow_stream_is_live, 1},
    {"rpst_arrow_stream_release", (DL_FUNC) &rpst_arrow_stream_release, 1},
    {"rpst_arrow_stream_free", (DL_FUNC) &rpst_arrow_stream_free, 1},
    {"rpst_arrow_set_addressable_limit", (DL_FUNC) &rpst_arrow_set_addressable_limit, 1},
    {"rpst_geoparquet_segment_graph", (DL_FUNC) &rpst_geoparquet_segment_graph, 4},
    {"rpst_arrow_decode_matrix", (DL_FUNC) &rpst_arrow_decode_matrix, 3},
    {"rpst_arrow_test_export", (DL_FUNC) &rpst_arrow_test_export, 2},
    {"rpst_arrow_test_counters", (DL_FUNC) &rpst_arrow_test_counters, 0},
    {"rpst_segment_graph_new_pointer", (DL_FUNC) &rpst_segment_graph_new_pointer, 0},
    {"rpst_compare_results", (DL_FUNC) &rpst_compare_results, 8},
    {"rpst_raster_release", (DL_FUNC) &rpst_raster_release, 1},
    {"rpst_raster_data", (DL_FUNC) &rpst_raster_data, 1},
    {"rpst_raster_polygons", (DL_FUNC) &rpst_raster_polygons, 3},
    {"rpst_raster_lifecycle", (DL_FUNC) &rpst_raster_lifecycle, 0},
    {"rpst_isovist_context_create", (DL_FUNC) &rpst_isovist_context_create, 3},
    {"rpst_isovist_context_release", (DL_FUNC) &rpst_isovist_context_release, 1},
    {"rpst_isovist_calculate", (DL_FUNC) &rpst_isovist_calculate, 7},
    {"rpst_isovist_lifecycle", (DL_FUNC) &rpst_isovist_lifecycle, 0},
    {"rpst_create_junctions", (DL_FUNC) &rpst_create_junctions, 6},
    {"rpst_create_segment_map", (DL_FUNC) &rpst_create_segment_map, 9},
    {"rpst_construction_lifecycle", (DL_FUNC) &rpst_construction_lifecycle, 0},
    {"rpst_angular_integration_controls", (DL_FUNC) &rpst_angular_integration_controls, 7},
    {"rpst_angular_choice_controls", (DL_FUNC) &rpst_angular_choice_controls, 6},
    {"rpst_od_betweenness", (DL_FUNC) &rpst_od_betweenness, 7},
    {"rpst_attraction_reach", (DL_FUNC) &rpst_attraction_reach, 12},
    {"rpst_attraction_distance", (DL_FUNC) &rpst_attraction_distance, 10},
    {"rpst_graph_point_state", (DL_FUNC) &rpst_graph_point_state, 1},
    {"rpst_graph_create_inputs", (DL_FUNC) &rpst_graph_create_inputs, 6},
    {"rpst_graph_line_lengths", (DL_FUNC) &rpst_graph_line_lengths, 1},
    {"rpst_graph_crossing_coords", (DL_FUNC) &rpst_graph_crossing_coords, 1},
    {"rpst_network_integration_outputs", (DL_FUNC) &rpst_network_integration_outputs, 3},
    {"rpst_segment_grouping", (DL_FUNC) &rpst_segment_grouping, 3},
    {"rpst_segment_grouping_stream", (DL_FUNC) &rpst_segment_grouping_stream, 8},
    {"rpst_segment_group_graph_create", (DL_FUNC) &rpst_segment_group_graph_create, 2},
    {"rpst_segment_group_graph_info", (DL_FUNC) &rpst_segment_group_graph_info, 1},
    {"rpst_segment_group_graph_release", (DL_FUNC) &rpst_segment_group_graph_release, 1},
    {"rpst_segment_group_graph_lifecycle", (DL_FUNC) &rpst_segment_group_graph_lifecycle, 0},
    {"rpst_segment_group_integration", (DL_FUNC) &rpst_segment_group_integration, 2},
    {"rpst_segment_group_output_test", (DL_FUNC) &rpst_segment_group_output_test, 3},

    {"rpst_segment_graph_create", (DL_FUNC) &rpst_segment_graph_create, 1},
    {"rpst_segment_graph_info", (DL_FUNC) &rpst_segment_graph_info, 1},
    {"rpst_segment_graph_release", (DL_FUNC) &rpst_segment_graph_release, 1},
    {"rpst_segment_graph_lifecycle", (DL_FUNC) &rpst_segment_graph_lifecycle, 0},
    {"rpst_angular_integration", (DL_FUNC) &rpst_angular_integration, 2},
    {"rpst_native_smoke", (DL_FUNC) &rpst_native_smoke, 0},
    {"rpst_graph_create", (DL_FUNC) &rpst_graph_create, 1},
    {"rpst_graph_info", (DL_FUNC) &rpst_graph_info, 1},
    {"rpst_graph_release", (DL_FUNC) &rpst_graph_release, 1},
    {"rpst_graph_lifecycle", (DL_FUNC) &rpst_graph_lifecycle, 0},
    {"rpst_network_integration", (DL_FUNC) &rpst_network_integration, 2},
    {"rpst_reach", (DL_FUNC) &rpst_reach, 2},
    {"rpst_reach_points", (DL_FUNC) &rpst_reach_points, 3},
    {"rpst_betweenness", (DL_FUNC) &rpst_betweenness, 4},
    {"rpst_betweenness_weighted", (DL_FUNC) &rpst_betweenness_weighted, 6},
    {"rpst_angular_choice", (DL_FUNC) &rpst_angular_choice, 4},
    {"rpst_workers", (DL_FUNC) &rpst_workers, 0},
    {"rpst_radius_validate", (DL_FUNC) &rpst_radius_validate, 1},
    {"rpst_angular_choice_multi", (DL_FUNC) &rpst_angular_choice_multi, 6},
    {"rpst_betweenness_multi", (DL_FUNC) &rpst_betweenness_multi, 6},
    {"rpst_betweenness_multi_stream", (DL_FUNC) &rpst_betweenness_multi_stream, 11},
    {"rpst_reach_multi", (DL_FUNC) &rpst_reach_multi, 3},
    {"rpst_network_integration_multi", (DL_FUNC) &rpst_network_integration_multi, 3},
    {"rpst_network_integration_multi_stream", (DL_FUNC) &rpst_network_integration_multi_stream, 7},
    {"rpst_reach_multi_stream", (DL_FUNC) &rpst_reach_multi_stream, 8},
    {"rpst_angular_integration_multi", (DL_FUNC) &rpst_angular_integration_multi, 7},
    {"rpst_angular_choice_multi_stream", (DL_FUNC) &rpst_angular_choice_multi_stream, 11},
    {"rpst_angular_integration_multi_stream", (DL_FUNC) &rpst_angular_integration_multi_stream, 12},
    {"rpst_angular_instrumentation", (DL_FUNC) &rpst_angular_instrumentation, 2},
    {"rpst_axial_instrumentation", (DL_FUNC) &rpst_axial_instrumentation, 2},
    {"rpst_progress_begin", (DL_FUNC) &rpst_progress_begin, 3},
    {"rpst_progress_end", (DL_FUNC) &rpst_progress_end, 0},
    {"rpst_progress_active", (DL_FUNC) &rpst_progress_active, 0},
    {"rpst_progress_test", (DL_FUNC) &rpst_progress_test, 2},
    {NULL, NULL, 0}
};

void attribute_visible R_init_rPSTool(DllInfo *dll)
{
    R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
    R_forceSymbols(dll, TRUE);
}
