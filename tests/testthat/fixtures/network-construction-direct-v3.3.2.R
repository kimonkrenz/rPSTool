list(pst_commit = "63df80a2cf3dd289be95ea3d91667c3490719b75",
    cases = list(list(kind = "junctions", name = "three_sorted_crossings",
        args = list(x = list(list(-10L, 0L, 10L, 0L), list(0L,
            -10L, 0L, 10L), list(5L, -10L, 5L, 10L), list(-5L,
            -10L, -5L, 10L))), native = list(points = list(list(
            -0x1.4p+2, 0x0p+0), list(0x0p+0, 0x0p+0), list(0x1.4p+2,
            0x0p+0)))), list(kind = "junctions", name = "unlink_first",
        args = list(x = list(list(-10L, 0L, 10L, 0L), list(0L,
            -10L, 0L, 10L), list(5L, -10L, 5L, 10L), list(-5L,
            -10L, -5L, 10L)), unlinks = list(list(-5L, 0L))),
        native = list(points = list(list(0x0p+0, 0x0p+0), list(
            0x1.4p+2, 0x0p+0)))), list(kind = "junctions", name = "unlink_middle",
        args = list(x = list(list(-10L, 0L, 10L, 0L), list(0L,
            -10L, 0L, 10L), list(5L, -10L, 5L, 10L), list(-5L,
            -10L, -5L, 10L)), unlinks = list(list(0L, 0L))),
        native = list(points = list(list(0x1.4p+2, 0x0p+0)))),
        list(kind = "junctions", name = "unlink_last", args = list(
            x = list(list(-10L, 0L, 10L, 0L), list(0L, -10L,
                0L, 10L), list(5L, -10L, 5L, 10L), list(-5L,
                -10L, -5L, 10L)), unlinks = list(list(5L, 0L))),
            native = list(points = list(list(0x0p+0, 0x0p+0)))),
        list(kind = "junctions", name = "unlink_far", args = list(
            x = list(list(-10L, 0L, 10L, 0L), list(0L, -10L,
                0L, 10L), list(5L, -10L, 5L, 10L), list(-5L,
                -10L, -5L, 10L)), unlinks = list(list(10000L,
                10000L))), native = list(points = list(list(0x0p+0,
            0x0p+0)))), list(kind = "junctions", name = "unlink_two",
            args = list(x = list(list(-10L, 0L, 10L, 0L), list(
                0L, -10L, 0L, 10L), list(5L, -10L, 5L, 10L),
                list(-5L, -10L, -5L, 10L)), unlinks = list(list(
                -5L, 0L), list(5L, 0L))), native = list(points = list(
                list(0x0p+0, 0x0p+0)))), list(kind = "junctions",
            name = "two_collinear_shared_endpoint", args = list(
                x = list(list(0L, 0L, 1L, 0L), list(1L, 0L, 2L,
                  0L))), native = list(points = list())), list(
            kind = "junctions", name = "three_way_endpoint",
            args = list(x = list(list(0L, 0L, 1L, 0L), list(1L,
                0L, 2L, 0L), list(1L, 0L, 1L, 1L))), native = list(
                points = list(list(0x1p+0, 0x0p+0)))), list(kind = "junctions",
            name = "two_layers_endpoint", args = list(x = list(
                list(0L, 0L, 1L, 0L)), y = list(list(1L, 0L,
                1L, 1L))), native = list(points = list(list(0x1p+0,
                0x0p+0)))), list(kind = "junctions", name = "two_layers_crossings",
            args = list(x = list(list(-10L, 0L, 10L, 0L)), y = list(
                list(0L, -10L, 0L, 10L), list(5L, -10L, 5L, 10L),
                list(-5L, -10L, -5L, 10L))), native = list(points = list(
                list(-0x1.4p+2, 0x0p+0), list(0x0p+0, 0x0p+0),
                list(0x1.4p+2, 0x0p+0)))), list(kind = "junctions",
            name = "explicit_empty_second", args = list(x = list(
                list(-10L, 0L, 10L, 0L), list(0L, -10L, 0L, 10L),
                list(5L, -10L, 5L, 10L), list(-5L, -10L, -5L,
                  10L)), y = list()), native = list(points = list())),
        list(kind = "junctions", name = "native_written_empty",
            args = list(x = list(list(0L, 0L, 0L, 0L), list(1L,
                1L, 1L, 1L))), native = list(points = list())),
        list(kind = "junctions", name = "tail_fraction_0.019",
            args = list(x = list(list(0L, 0L, 100L, 0L), list(
                0x1.e666666666666p+0, -1L, 0x1.e666666666666p+0,
                1L))), native = list(points = list(list(0x1.e6668p+0,
                0x0p+0)))), list(kind = "junctions", name = "tail_fraction_0.021",
            args = list(x = list(list(0L, 0L, 100L, 0L), list(
                0x1.0cccccccccccdp+1, -1L, 0x1.0cccccccccccdp+1,
                1L))), native = list(points = list(list(0x1.0ccccp+1,
                0x0p+0)))), list(kind = "junctions", name = "tail_fraction_0.98",
            args = list(x = list(list(0L, 0L, 100L, 0L), list(
                0x1.88p+6, -1L, 0x1.88p+6, 1L))), native = list(
                points = list(list(0x1.87fffep+6, 0x0p+0)))),
        list(kind = "junctions", name = "tail_fraction_0.981",
            args = list(x = list(list(0L, 0L, 100L, 0L), list(
                0x1.8866666666666p+6, -1L, 0x1.8866666666666p+6,
                1L))), native = list(points = list(list(0x1.886664p+6,
                0x0p+0)))), list(kind = "junctions", name = "indexed_prefix",
            args = list(x = list(list(100L, 0L), list(0L, 0L),
                list(10L, 0L), list(5L, -5L), list(5L, 5L), list(
                  0x1.658e3ab795204p+830, 0x1.658e3ab795204p+830)),
                line_indices = list(list(2L, 3L), list(4L, 5L))),
            native = list(points = list(list(0x1.4p+2, 0x0p+0)))),
        list(kind = "junctions", name = "indexed_both", args = list(
            x = list(list(-10L, 0L), list(10L, 0L)), line_indices = list(
                list(1L, 2L)), y = list(list(0L, -10L), list(
                0L, 10L), list(0x1.658e3ab795204p+830, 0x1.658e3ab795204p+830)),
            line_indices_y = list(list(1L, 2L))), native = list(
            points = list(list(0x0p+0, 0x0p+0)))), list(kind = "junctions",
            name = "large_world_center", args = list(x = list(
                list(0x1.d1a94a1fecp+39, 0x1.d1a94a2p+39, 0x1.d1a94a2014p+39,
                  0x1.d1a94a2p+39), list(0x1.d1a94a2p+39, 0x1.d1a94a1fecp+39,
                  0x1.d1a94a2p+39, 0x1.d1a94a2014p+39))), native = list(
                points = list(list(0x1.d1a94a2p+39, 0x1.d1a94a2p+39)))),
        list(kind = "junctions", name = "reversed_duplicate",
            args = list(x = list(list(-10L, 0L, 10L, 0L), list(
                10L, 0L, -10L, 0L), list(0L, -10L, 0L, 10L))),
            native = list(points = list(list(0x0p+0, 0x0p+0)))),
        list(kind = "junctions", name = "zero_length_and_cross",
            args = list(x = list(list(0L, 0L, 0L, 0L), list(-10L,
                0L, 10L, 0L), list(0L, -10L, 0L, 10L))), native = list(
                points = list(list(0x0p+0, 0x0p+0)))), list(kind = "segment_map",
            name = "chain_axial_or_segment_0", args = list(coords = list(
                list(0L, 0L), list(10L, 0L), list(20L, 0L)),
                sections = list(3L), network_type = "axial_or_segment"),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+4, 0x0p+0)), base_id = list(0L), unlinks = list())),
        list(kind = "segment_map", name = "chain_axial_or_segment_1",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(20L, 0L)), sections = list(3L), network_type = "axial_or_segment",
                snap = 0L, tail = 0L, deviation = 0L, extrude = 0L),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+4, 0x0p+0)), base_id = list(0L), unlinks = list())),
        list(kind = "segment_map", name = "chain_axial_or_segment_2",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(20L, 0L)), sections = list(3L), network_type = "axial_or_segment",
                snap = 0x1p-1, tail = 2L, deviation = 0x1p-1,
                extrude = 2L), native = list(segments = list(
                list(0x0p+0, 0x0p+0, 0x1.4p+4, 0x0p+0)), base_id = list(
                0L), unlinks = list())), list(kind = "segment_map",
            name = "chain_axial_or_segment_3", args = list(coords = list(
                list(0L, 0L), list(10L, 0L), list(20L, 0L)),
                sections = list(3L), network_type = "axial_or_segment",
                snap = 0x1.028f5c28f5c29p+0, tail = 10L, deviation = 2L,
                extrude = 1L), native = list(segments = list(
                list(0x0p+0, 0x0p+0, 0x1.4p+4, 0x0p+0)), base_id = list(
                0L), unlinks = list())), list(kind = "segment_map",
            name = "chain_road_center_lines_0", args = list(coords = list(
                list(0L, 0L), list(10L, 0L), list(20L, 0L)),
                sections = list(3L), network_type = "road_center_lines"),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+4, 0x0p+0)), base_id = list(0L), unlinks = list())),
        list(kind = "segment_map", name = "chain_road_center_lines_1",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(20L, 0L)), sections = list(3L), network_type = "road_center_lines",
                snap = 0L, tail = 0L, deviation = 0L, extrude = 0L),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+4, 0x0p+0)), base_id = list(0L), unlinks = list())),
        list(kind = "segment_map", name = "chain_road_center_lines_2",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(20L, 0L)), sections = list(3L), network_type = "road_center_lines",
                snap = 0x1p-1, tail = 2L, deviation = 0x1p-1,
                extrude = 2L), native = list(segments = list(
                list(0x0p+0, 0x0p+0, 0x1.4p+4, 0x0p+0)), base_id = list(
                0L), unlinks = list())), list(kind = "segment_map",
            name = "chain_road_center_lines_3", args = list(coords = list(
                list(0L, 0L), list(10L, 0L), list(20L, 0L)),
                sections = list(3L), network_type = "road_center_lines",
                snap = 0x1.028f5c28f5c29p+0, tail = 10L, deviation = 2L,
                extrude = 1L), native = list(segments = list(
                list(0x0p+0, 0x0p+0, 0x1.4p+4, 0x0p+0)), base_id = list(
                0L), unlinks = list())), list(kind = "segment_map",
            name = "bent_axial_or_segment_0", args = list(coords = list(
                list(0L, 0L), list(10L, 1L), list(20L, 0L), list(
                  20L, 10L)), sections = list(4L), network_type = "axial_or_segment"),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+4, 0x0p+0), list(0x1.4p+4, 0x0p+0, 0x1.4p+4,
                0x1.4p+3)), base_id = list(0L, 0L), unlinks = list())),
        list(kind = "segment_map", name = "bent_axial_or_segment_1",
            args = list(coords = list(list(0L, 0L), list(10L,
                1L), list(20L, 0L), list(20L, 10L)), sections = list(
                4L), network_type = "axial_or_segment", snap = 0L,
                tail = 0L, deviation = 0L, extrude = 0L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+3,
                  0x1p+0), list(0x1.4p+3, 0x1p+0, 0x1.4p+4, 0x0p+0),
                  list(0x1.4p+4, 0x0p+0, 0x1.4p+4, 0x1.4p+3)),
                base_id = list(0L, 0L, 0L), unlinks = list())),
        list(kind = "segment_map", name = "bent_axial_or_segment_2",
            args = list(coords = list(list(0L, 0L), list(10L,
                1L), list(20L, 0L), list(20L, 10L)), sections = list(
                4L), network_type = "axial_or_segment", snap = 0x1p-1,
                tail = 2L, deviation = 0x1p-1, extrude = 2L),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+3, 0x1p+0), list(0x1.4p+3, 0x1p+0, 0x1.4p+4,
                0x0p+0), list(0x1.4p+4, 0x0p+0, 0x1.4p+4, 0x1.4p+3)),
                base_id = list(0L, 0L, 0L), unlinks = list())),
        list(kind = "segment_map", name = "bent_axial_or_segment_3",
            args = list(coords = list(list(0L, 0L), list(10L,
                1L), list(20L, 0L), list(20L, 10L)), sections = list(
                4L), network_type = "axial_or_segment", snap = 0x1.028f5c28f5c29p+0,
                tail = 10L, deviation = 2L, extrude = 1L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+4,
                  0x0p+0), list(0x1.4p+4, 0x0p+0, 0x1.4p+4, 0x1.4p+3)),
                base_id = list(0L, 0L), unlinks = list())), list(
            kind = "segment_map", name = "bent_road_center_lines_0",
            args = list(coords = list(list(0L, 0L), list(10L,
                1L), list(20L, 0L), list(20L, 10L)), sections = list(
                4L), network_type = "road_center_lines"), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+4,
                  0x0p+0), list(0x1.4p+4, 0x0p+0, 0x1.4p+4, 0x1.4p+3)),
                base_id = list(0L, 0L), unlinks = list())), list(
            kind = "segment_map", name = "bent_road_center_lines_1",
            args = list(coords = list(list(0L, 0L), list(10L,
                1L), list(20L, 0L), list(20L, 10L)), sections = list(
                4L), network_type = "road_center_lines", snap = 0L,
                tail = 0L, deviation = 0L, extrude = 0L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+3,
                  0x1p+0), list(0x1.4p+3, 0x1p+0, 0x1.4p+4, 0x0p+0),
                  list(0x1.4p+4, 0x0p+0, 0x1.4p+4, 0x1.4p+3)),
                base_id = list(0L, 0L, 0L), unlinks = list())),
        list(kind = "segment_map", name = "bent_road_center_lines_2",
            args = list(coords = list(list(0L, 0L), list(10L,
                1L), list(20L, 0L), list(20L, 10L)), sections = list(
                4L), network_type = "road_center_lines", snap = 0x1p-1,
                tail = 2L, deviation = 0x1p-1, extrude = 2L),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+3, 0x1p+0), list(0x1.4p+3, 0x1p+0, 0x1.4p+4,
                0x0p+0), list(0x1.4p+4, 0x0p+0, 0x1.4p+4, 0x1.4p+3)),
                base_id = list(0L, 0L, 0L), unlinks = list())),
        list(kind = "segment_map", name = "bent_road_center_lines_3",
            args = list(coords = list(list(0L, 0L), list(10L,
                1L), list(20L, 0L), list(20L, 10L)), sections = list(
                4L), network_type = "road_center_lines", snap = 0x1.028f5c28f5c29p+0,
                tail = 10L, deviation = 2L, extrude = 1L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+4,
                  0x0p+0), list(0x1.4p+4, 0x0p+0, 0x1.4p+4, 0x1.4p+3)),
                base_id = list(0L, 0L), unlinks = list())), list(
            kind = "segment_map", name = "cross_axial_or_segment_0",
            args = list(coords = list(list(0L, 0L), list(20L,
                0L), list(10L, -10L), list(10L, 10L)), sections = list(
                2L, 2L), network_type = "axial_or_segment"),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+3, 0x0p+0), list(0x1.4p+3, 0x0p+0, 0x1.4p+4,
                0x0p+0), list(0x1.4p+3, -0x1.4p+3, 0x1.4p+3,
                0x0p+0), list(0x1.4p+3, 0x0p+0, 0x1.4p+3, 0x1.4p+3)),
                base_id = list(0L, 0L, 1L, 1L), unlinks = list())),
        list(kind = "segment_map", name = "cross_axial_or_segment_1",
            args = list(coords = list(list(0L, 0L), list(20L,
                0L), list(10L, -10L), list(10L, 10L)), sections = list(
                2L, 2L), network_type = "axial_or_segment", snap = 0L,
                tail = 0L, deviation = 0L, extrude = 0L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+3,
                  0x0p+0), list(0x1.4p+3, 0x0p+0, 0x1.4p+4, 0x0p+0),
                  list(0x1.4p+3, -0x1.4p+3, 0x1.4p+3, 0x0p+0),
                  list(0x1.4p+3, 0x0p+0, 0x1.4p+3, 0x1.4p+3)),
                base_id = list(0L, 0L, 1L, 1L), unlinks = list())),
        list(kind = "segment_map", name = "cross_axial_or_segment_2",
            args = list(coords = list(list(0L, 0L), list(20L,
                0L), list(10L, -10L), list(10L, 10L)), sections = list(
                2L, 2L), network_type = "axial_or_segment", snap = 0x1p-1,
                tail = 2L, deviation = 0x1p-1, extrude = 2L),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+3, 0x0p+0), list(0x1.4p+3, 0x0p+0, 0x1.4p+4,
                0x0p+0), list(0x1.4p+3, -0x1.4p+3, 0x1.4p+3,
                0x0p+0), list(0x1.4p+3, 0x0p+0, 0x1.4p+3, 0x1.4p+3)),
                base_id = list(0L, 0L, 1L, 1L), unlinks = list())),
        list(kind = "segment_map", name = "cross_axial_or_segment_3",
            args = list(coords = list(list(0L, 0L), list(20L,
                0L), list(10L, -10L), list(10L, 10L)), sections = list(
                2L, 2L), network_type = "axial_or_segment", snap = 0x1.028f5c28f5c29p+0,
                tail = 10L, deviation = 2L, extrude = 1L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+3,
                  0x0p+0), list(0x1.4p+3, 0x0p+0, 0x1.4p+4, 0x0p+0),
                  list(0x1.4p+3, -0x1.4p+3, 0x1.4p+3, 0x0p+0),
                  list(0x1.4p+3, 0x0p+0, 0x1.4p+3, 0x1.4p+3)),
                base_id = list(0L, 0L, 1L, 1L), unlinks = list())),
        list(kind = "segment_map", name = "cross_road_center_lines_0",
            args = list(coords = list(list(0L, 0L), list(20L,
                0L), list(10L, -10L), list(10L, 10L)), sections = list(
                2L, 2L), network_type = "road_center_lines"),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+4, 0x0p+0), list(0x1.4p+3, -0x1.4p+3,
                0x1.4p+3, 0x1.4p+3)), base_id = list(0L, 1L),
                unlinks = list(list(0x1.4p+3, 0x0p+0), list(0x1.4p+3,
                  0x0p+0)))), list(kind = "segment_map", name = "cross_road_center_lines_1",
            args = list(coords = list(list(0L, 0L), list(20L,
                0L), list(10L, -10L), list(10L, 10L)), sections = list(
                2L, 2L), network_type = "road_center_lines",
                snap = 0L, tail = 0L, deviation = 0L, extrude = 0L),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+4, 0x0p+0), list(0x1.4p+3, -0x1.4p+3,
                0x1.4p+3, 0x1.4p+3)), base_id = list(0L, 1L),
                unlinks = list(list(0x1.4p+3, 0x0p+0), list(0x1.4p+3,
                  0x0p+0)))), list(kind = "segment_map", name = "cross_road_center_lines_2",
            args = list(coords = list(list(0L, 0L), list(20L,
                0L), list(10L, -10L), list(10L, 10L)), sections = list(
                2L, 2L), network_type = "road_center_lines",
                snap = 0x1p-1, tail = 2L, deviation = 0x1p-1,
                extrude = 2L), native = list(segments = list(
                list(0x0p+0, 0x0p+0, 0x1.4p+4, 0x0p+0), list(
                  0x1.4p+3, -0x1.4p+3, 0x1.4p+3, 0x1.4p+3)),
                base_id = list(0L, 1L), unlinks = list(list(0x1.4p+3,
                  0x0p+0), list(0x1.4p+3, 0x0p+0)))), list(kind = "segment_map",
            name = "cross_road_center_lines_3", args = list(coords = list(
                list(0L, 0L), list(20L, 0L), list(10L, -10L),
                list(10L, 10L)), sections = list(2L, 2L), network_type = "road_center_lines",
                snap = 0x1.028f5c28f5c29p+0, tail = 10L, deviation = 2L,
                extrude = 1L), native = list(segments = list(
                list(0x0p+0, 0x0p+0, 0x1.4p+4, 0x0p+0), list(
                  0x1.4p+3, -0x1.4p+3, 0x1.4p+3, 0x1.4p+3)),
                base_id = list(0L, 1L), unlinks = list(list(0x1.4p+3,
                  0x0p+0), list(0x1.4p+3, 0x0p+0)))), list(kind = "segment_map",
            name = "near_miss_axial_or_segment_0", args = list(
                coords = list(list(0L, 0L), list(20L, 0L), list(
                  10L, 1L), list(10L, 10L)), sections = list(
                  2L, 2L), network_type = "axial_or_segment"),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+4, 0x0p+0), list(0x1.4p+3, 0x1p+0, 0x1.4p+3,
                0x1.4p+3)), base_id = list(0L, 1L), unlinks = list())),
        list(kind = "segment_map", name = "near_miss_axial_or_segment_1",
            args = list(coords = list(list(0L, 0L), list(20L,
                0L), list(10L, 1L), list(10L, 10L)), sections = list(
                2L, 2L), network_type = "axial_or_segment", snap = 0L,
                tail = 0L, deviation = 0L, extrude = 0L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+4,
                  0x0p+0), list(0x1.4p+3, 0x1p+0, 0x1.4p+3, 0x1.4p+3)),
                base_id = list(0L, 1L), unlinks = list())), list(
            kind = "segment_map", name = "near_miss_axial_or_segment_2",
            args = list(coords = list(list(0L, 0L), list(20L,
                0L), list(10L, 1L), list(10L, 10L)), sections = list(
                2L, 2L), network_type = "axial_or_segment", snap = 0x1p-1,
                tail = 2L, deviation = 0x1p-1, extrude = 2L),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+4, 0x0p+0), list(0x1.4p+3, 0x1p+0, 0x1.4p+3,
                0x1.4p+3)), base_id = list(0L, 1L), unlinks = list())),
        list(kind = "segment_map", name = "near_miss_axial_or_segment_3",
            args = list(coords = list(list(0L, 0L), list(20L,
                0L), list(10L, 1L), list(10L, 10L)), sections = list(
                2L, 2L), network_type = "axial_or_segment", snap = 0x1.028f5c28f5c29p+0,
                tail = 10L, deviation = 2L, extrude = 1L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+4,
                  0x0p+0), list(0x1.4p+3, 0x1p+0, 0x1.4p+3, 0x1.4p+3)),
                base_id = list(0L, 1L), unlinks = list())), list(
            kind = "segment_map", name = "near_miss_road_center_lines_0",
            args = list(coords = list(list(0L, 0L), list(20L,
                0L), list(10L, 1L), list(10L, 10L)), sections = list(
                2L, 2L), network_type = "road_center_lines"),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+4, 0x0p+0), list(0x1.4p+3, 0x1p+0, 0x1.4p+3,
                0x1.4p+3)), base_id = list(0L, 1L), unlinks = list())),
        list(kind = "segment_map", name = "near_miss_road_center_lines_1",
            args = list(coords = list(list(0L, 0L), list(20L,
                0L), list(10L, 1L), list(10L, 10L)), sections = list(
                2L, 2L), network_type = "road_center_lines",
                snap = 0L, tail = 0L, deviation = 0L, extrude = 0L),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+4, 0x0p+0), list(0x1.4p+3, 0x1p+0, 0x1.4p+3,
                0x1.4p+3)), base_id = list(0L, 1L), unlinks = list())),
        list(kind = "segment_map", name = "near_miss_road_center_lines_2",
            args = list(coords = list(list(0L, 0L), list(20L,
                0L), list(10L, 1L), list(10L, 10L)), sections = list(
                2L, 2L), network_type = "road_center_lines",
                snap = 0x1p-1, tail = 2L, deviation = 0x1p-1,
                extrude = 2L), native = list(segments = list(
                list(0x0p+0, 0x0p+0, 0x1.4p+4, 0x0p+0), list(
                  0x1.4p+3, 0x1p+0, 0x1.4p+3, 0x1.4p+3)), base_id = list(
                0L, 1L), unlinks = list(list(0x1.4p+3, 0x0p+0)))),
        list(kind = "segment_map", name = "near_miss_road_center_lines_3",
            args = list(coords = list(list(0L, 0L), list(20L,
                0L), list(10L, 1L), list(10L, 10L)), sections = list(
                2L, 2L), network_type = "road_center_lines",
                snap = 0x1.028f5c28f5c29p+0, tail = 10L, deviation = 2L,
                extrude = 1L), native = list(segments = list(
                list(0x0p+0, 0x0p+0, 0x1.4p+4, 0x0p+0), list(
                  0x1.4p+3, 0x1p+0, 0x1.4p+3, 0x1.4p+3)), base_id = list(
                0L, 1L), unlinks = list())), list(kind = "segment_map",
            name = "tails_axial_or_segment_0", args = list(coords = list(
                list(0L, 0L), list(20L, 0L), list(10L, -1L),
                list(10L, 10L)), sections = list(2L, 2L), network_type = "axial_or_segment"),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+3, 0x0p+0), list(0x1.4p+3, 0x0p+0, 0x1.4p+4,
                0x0p+0), list(0x1.4p+3, 0x0p+0, 0x1.4p+3, 0x1.4p+3)),
                base_id = list(0L, 0L, 1L), unlinks = list())),
        list(kind = "segment_map", name = "tails_axial_or_segment_1",
            args = list(coords = list(list(0L, 0L), list(20L,
                0L), list(10L, -1L), list(10L, 10L)), sections = list(
                2L, 2L), network_type = "axial_or_segment", snap = 0L,
                tail = 0L, deviation = 0L, extrude = 0L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+3,
                  0x0p+0), list(0x1.4p+3, 0x0p+0, 0x1.4p+4, 0x0p+0),
                  list(0x1.4p+3, -0x1p+0, 0x1.4p+3, 0x0p+0),
                  list(0x1.4p+3, 0x0p+0, 0x1.4p+3, 0x1.4p+3)),
                base_id = list(0L, 0L, 1L, 1L), unlinks = list())),
        list(kind = "segment_map", name = "tails_axial_or_segment_2",
            args = list(coords = list(list(0L, 0L), list(20L,
                0L), list(10L, -1L), list(10L, 10L)), sections = list(
                2L, 2L), network_type = "axial_or_segment", snap = 0x1p-1,
                tail = 2L, deviation = 0x1p-1, extrude = 2L),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+3, 0x0p+0), list(0x1.4p+3, 0x0p+0, 0x1.4p+4,
                0x0p+0), list(0x1.4p+3, 0x0p+0, 0x1.4p+3, 0x1.4p+3)),
                base_id = list(0L, 0L, 1L), unlinks = list())),
        list(kind = "segment_map", name = "tails_axial_or_segment_3",
            args = list(coords = list(list(0L, 0L), list(20L,
                0L), list(10L, -1L), list(10L, 10L)), sections = list(
                2L, 2L), network_type = "axial_or_segment", snap = 0x1.028f5c28f5c29p+0,
                tail = 10L, deviation = 2L, extrude = 1L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+3,
                  0x0p+0), list(0x1.4p+3, 0x0p+0, 0x1.4p+4, 0x0p+0),
                  list(0x1.4p+3, 0x0p+0, 0x1.4p+3, 0x1.4p+3)),
                base_id = list(0L, 0L, 1L), unlinks = list())),
        list(kind = "segment_map", name = "tails_road_center_lines_0",
            args = list(coords = list(list(0L, 0L), list(20L,
                0L), list(10L, -1L), list(10L, 10L)), sections = list(
                2L, 2L), network_type = "road_center_lines"),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+4, 0x0p+0), list(0x1.4p+3, -0x1p+0, 0x1.4p+3,
                0x1.4p+3)), base_id = list(0L, 1L), unlinks = list(
                list(0x1.4p+3, 0x0p+0), list(0x1.4p+3, 0x0p+0)))),
        list(kind = "segment_map", name = "tails_road_center_lines_1",
            args = list(coords = list(list(0L, 0L), list(20L,
                0L), list(10L, -1L), list(10L, 10L)), sections = list(
                2L, 2L), network_type = "road_center_lines",
                snap = 0L, tail = 0L, deviation = 0L, extrude = 0L),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+4, 0x0p+0), list(0x1.4p+3, -0x1p+0, 0x1.4p+3,
                0x1.4p+3)), base_id = list(0L, 1L), unlinks = list(
                list(0x1.4p+3, 0x0p+0), list(0x1.4p+3, 0x0p+0)))),
        list(kind = "segment_map", name = "tails_road_center_lines_2",
            args = list(coords = list(list(0L, 0L), list(20L,
                0L), list(10L, -1L), list(10L, 10L)), sections = list(
                2L, 2L), network_type = "road_center_lines",
                snap = 0x1p-1, tail = 2L, deviation = 0x1p-1,
                extrude = 2L), native = list(segments = list(
                list(0x0p+0, 0x0p+0, 0x1.4p+4, 0x0p+0), list(
                  0x1.4p+3, -0x1p+0, 0x1.4p+3, 0x1.4p+3)), base_id = list(
                0L, 1L), unlinks = list(list(0x1.4p+3, 0x0p+0),
                list(0x1.4p+3, 0x0p+0)))), list(kind = "segment_map",
            name = "tails_road_center_lines_3", args = list(coords = list(
                list(0L, 0L), list(20L, 0L), list(10L, -1L),
                list(10L, 10L)), sections = list(2L, 2L), network_type = "road_center_lines",
                snap = 0x1.028f5c28f5c29p+0, tail = 10L, deviation = 2L,
                extrude = 1L), native = list(segments = list(
                list(0x0p+0, 0x0p+0, 0x1.4p+4, 0x0p+0), list(
                  0x1.4p+3, -0x1p+0, 0x1.4p+3, 0x1.4p+3)), base_id = list(
                0L, 1L), unlinks = list(list(0x1.4p+3, 0x0p+0),
                list(0x1.4p+3, 0x0p+0)))), list(kind = "segment_map",
            name = "large_closed_axial_or_segment_0", args = list(
                coords = list(list(0L, 0L), list(10L, 0L), list(
                  10L, 10L), list(0L, 10L), list(0L, 0L)), sections = list(
                  5L), network_type = "axial_or_segment"), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+3,
                  0x0p+0), list(0x1.4p+3, 0x0p+0, 0x1.4p+3, 0x1.4p+3),
                  list(0x1.4p+3, 0x1.4p+3, 0x0p+0, 0x1.4p+3),
                  list(0x0p+0, 0x1.4p+3, 0x0p+0, 0x0p+0)), base_id = list(
                  0L, 0L, 0L, 0L), unlinks = list())), list(kind = "segment_map",
            name = "large_closed_axial_or_segment_1", args = list(
                coords = list(list(0L, 0L), list(10L, 0L), list(
                  10L, 10L), list(0L, 10L), list(0L, 0L)), sections = list(
                  5L), network_type = "axial_or_segment", snap = 0L,
                tail = 0L, deviation = 0L, extrude = 0L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+3,
                  0x0p+0), list(0x1.4p+3, 0x0p+0, 0x1.4p+3, 0x1.4p+3),
                  list(0x1.4p+3, 0x1.4p+3, 0x0p+0, 0x1.4p+3),
                  list(0x0p+0, 0x1.4p+3, 0x0p+0, 0x0p+0)), base_id = list(
                  0L, 0L, 0L, 0L), unlinks = list())), list(kind = "segment_map",
            name = "large_closed_axial_or_segment_2", args = list(
                coords = list(list(0L, 0L), list(10L, 0L), list(
                  10L, 10L), list(0L, 10L), list(0L, 0L)), sections = list(
                  5L), network_type = "axial_or_segment", snap = 0x1p-1,
                tail = 2L, deviation = 0x1p-1, extrude = 2L),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+3, 0x0p+0), list(0x1.4p+3, 0x0p+0, 0x1.4p+3,
                0x1.4p+3), list(0x1.4p+3, 0x1.4p+3, 0x0p+0, 0x1.4p+3),
                list(0x0p+0, 0x1.4p+3, 0x0p+0, 0x0p+0)), base_id = list(
                0L, 0L, 0L, 0L), unlinks = list())), list(kind = "segment_map",
            name = "large_closed_axial_or_segment_3", args = list(
                coords = list(list(0L, 0L), list(10L, 0L), list(
                  10L, 10L), list(0L, 10L), list(0L, 0L)), sections = list(
                  5L), network_type = "axial_or_segment", snap = 0x1.028f5c28f5c29p+0,
                tail = 10L, deviation = 2L, extrude = 1L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+3,
                  0x0p+0), list(0x1.4p+3, 0x0p+0, 0x1.4p+3, 0x1.4p+3),
                  list(0x1.4p+3, 0x1.4p+3, 0x0p+0, 0x1.4p+3),
                  list(0x0p+0, 0x1.4p+3, 0x0p+0, 0x0p+0)), base_id = list(
                  0L, 0L, 0L, 0L), unlinks = list())), list(kind = "segment_map",
            name = "large_closed_road_center_lines_0", args = list(
                coords = list(list(0L, 0L), list(10L, 0L), list(
                  10L, 10L), list(0L, 10L), list(0L, 0L)), sections = list(
                  5L), network_type = "road_center_lines"), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+3,
                  0x0p+0), list(0x1.4p+3, 0x0p+0, 0x1.4p+3, 0x1.4p+3),
                  list(0x1.4p+3, 0x1.4p+3, 0x0p+0, 0x1.4p+3),
                  list(0x0p+0, 0x1.4p+3, 0x0p+0, 0x0p+0)), base_id = list(
                  0L, 0L, 0L, 0L), unlinks = list())), list(kind = "segment_map",
            name = "large_closed_road_center_lines_1", args = list(
                coords = list(list(0L, 0L), list(10L, 0L), list(
                  10L, 10L), list(0L, 10L), list(0L, 0L)), sections = list(
                  5L), network_type = "road_center_lines", snap = 0L,
                tail = 0L, deviation = 0L, extrude = 0L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+3,
                  0x0p+0), list(0x1.4p+3, 0x0p+0, 0x1.4p+3, 0x1.4p+3),
                  list(0x1.4p+3, 0x1.4p+3, 0x0p+0, 0x1.4p+3),
                  list(0x0p+0, 0x1.4p+3, 0x0p+0, 0x0p+0)), base_id = list(
                  0L, 0L, 0L, 0L), unlinks = list())), list(kind = "segment_map",
            name = "large_closed_road_center_lines_2", args = list(
                coords = list(list(0L, 0L), list(10L, 0L), list(
                  10L, 10L), list(0L, 10L), list(0L, 0L)), sections = list(
                  5L), network_type = "road_center_lines", snap = 0x1p-1,
                tail = 2L, deviation = 0x1p-1, extrude = 2L),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+3, 0x0p+0), list(0x1.4p+3, 0x0p+0, 0x1.4p+3,
                0x1.4p+3), list(0x1.4p+3, 0x1.4p+3, 0x0p+0, 0x1.4p+3),
                list(0x0p+0, 0x1.4p+3, 0x0p+0, 0x0p+0)), base_id = list(
                0L, 0L, 0L, 0L), unlinks = list())), list(kind = "segment_map",
            name = "large_closed_road_center_lines_3", args = list(
                coords = list(list(0L, 0L), list(10L, 0L), list(
                  10L, 10L), list(0L, 10L), list(0L, 0L)), sections = list(
                  5L), network_type = "road_center_lines", snap = 0x1.028f5c28f5c29p+0,
                tail = 10L, deviation = 2L, extrude = 1L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+3,
                  0x0p+0), list(0x1.4p+3, 0x0p+0, 0x1.4p+3, 0x1.4p+3),
                  list(0x1.4p+3, 0x1.4p+3, 0x0p+0, 0x1.4p+3),
                  list(0x0p+0, 0x1.4p+3, 0x0p+0, 0x0p+0)), base_id = list(
                  0L, 0L, 0L, 0L), unlinks = list())), list(kind = "segment_map",
            name = "same_base_sections_axial_or_segment_0", args = list(
                coords = list(list(0L, 0L), list(10L, 0L), list(
                  20L, 0L), list(20L, 0L), list(30L, 0L), list(
                  40L, 0L)), sections = list(-4L, 3L), network_type = "axial_or_segment"),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+5, 0x0p+0)), base_id = list(0L), unlinks = list())),
        list(kind = "segment_map", name = "same_base_sections_axial_or_segment_1",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(20L, 0L), list(20L, 0L), list(30L,
                0L), list(40L, 0L)), sections = list(-4L, 3L),
                network_type = "axial_or_segment", snap = 0L,
                tail = 0L, deviation = 0L, extrude = 0L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+5,
                  0x0p+0)), base_id = list(0L), unlinks = list())),
        list(kind = "segment_map", name = "same_base_sections_axial_or_segment_2",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(20L, 0L), list(20L, 0L), list(30L,
                0L), list(40L, 0L)), sections = list(-4L, 3L),
                network_type = "axial_or_segment", snap = 0x1p-1,
                tail = 2L, deviation = 0x1p-1, extrude = 2L),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+5, 0x0p+0)), base_id = list(0L), unlinks = list())),
        list(kind = "segment_map", name = "same_base_sections_axial_or_segment_3",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(20L, 0L), list(20L, 0L), list(30L,
                0L), list(40L, 0L)), sections = list(-4L, 3L),
                network_type = "axial_or_segment", snap = 0x1.028f5c28f5c29p+0,
                tail = 10L, deviation = 2L, extrude = 1L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+5,
                  0x0p+0)), base_id = list(0L), unlinks = list())),
        list(kind = "segment_map", name = "same_base_sections_road_center_lines_0",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(20L, 0L), list(20L, 0L), list(30L,
                0L), list(40L, 0L)), sections = list(-4L, 3L),
                network_type = "road_center_lines"), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+5,
                  0x0p+0)), base_id = list(0L), unlinks = list())),
        list(kind = "segment_map", name = "same_base_sections_road_center_lines_1",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(20L, 0L), list(20L, 0L), list(30L,
                0L), list(40L, 0L)), sections = list(-4L, 3L),
                network_type = "road_center_lines", snap = 0L,
                tail = 0L, deviation = 0L, extrude = 0L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+5,
                  0x0p+0)), base_id = list(0L), unlinks = list())),
        list(kind = "segment_map", name = "same_base_sections_road_center_lines_2",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(20L, 0L), list(20L, 0L), list(30L,
                0L), list(40L, 0L)), sections = list(-4L, 3L),
                network_type = "road_center_lines", snap = 0x1p-1,
                tail = 2L, deviation = 0x1p-1, extrude = 2L),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+5, 0x0p+0)), base_id = list(0L), unlinks = list())),
        list(kind = "segment_map", name = "same_base_sections_road_center_lines_3",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(20L, 0L), list(20L, 0L), list(30L,
                0L), list(40L, 0L)), sections = list(-4L, 3L),
                network_type = "road_center_lines", snap = 0x1.028f5c28f5c29p+0,
                tail = 10L, deviation = 2L, extrude = 1L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+5,
                  0x0p+0)), base_id = list(0L), unlinks = list())),
        list(kind = "segment_map", name = "different_base_sections_axial_or_segment_0",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(20L, 0L), list(20L, 0L), list(30L,
                0L), list(40L, 0L)), sections = list(3L, 3L),
                network_type = "axial_or_segment"), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+4,
                  0x0p+0), list(0x1.4p+4, 0x0p+0, 0x1.4p+5, 0x0p+0)),
                base_id = list(0L, 1L), unlinks = list())), list(
            kind = "segment_map", name = "different_base_sections_axial_or_segment_1",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(20L, 0L), list(20L, 0L), list(30L,
                0L), list(40L, 0L)), sections = list(3L, 3L),
                network_type = "axial_or_segment", snap = 0L,
                tail = 0L, deviation = 0L, extrude = 0L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+4,
                  0x0p+0), list(0x1.4p+4, 0x0p+0, 0x1.4p+5, 0x0p+0)),
                base_id = list(0L, 1L), unlinks = list())), list(
            kind = "segment_map", name = "different_base_sections_axial_or_segment_2",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(20L, 0L), list(20L, 0L), list(30L,
                0L), list(40L, 0L)), sections = list(3L, 3L),
                network_type = "axial_or_segment", snap = 0x1p-1,
                tail = 2L, deviation = 0x1p-1, extrude = 2L),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+4, 0x0p+0), list(0x1.4p+4, 0x0p+0, 0x1.4p+5,
                0x0p+0)), base_id = list(0L, 1L), unlinks = list())),
        list(kind = "segment_map", name = "different_base_sections_axial_or_segment_3",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(20L, 0L), list(20L, 0L), list(30L,
                0L), list(40L, 0L)), sections = list(3L, 3L),
                network_type = "axial_or_segment", snap = 0x1.028f5c28f5c29p+0,
                tail = 10L, deviation = 2L, extrude = 1L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+4,
                  0x0p+0), list(0x1.4p+4, 0x0p+0, 0x1.4p+5, 0x0p+0)),
                base_id = list(0L, 1L), unlinks = list())), list(
            kind = "segment_map", name = "different_base_sections_road_center_lines_0",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(20L, 0L), list(20L, 0L), list(30L,
                0L), list(40L, 0L)), sections = list(3L, 3L),
                network_type = "road_center_lines"), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+4,
                  0x0p+0), list(0x1.4p+4, 0x0p+0, 0x1.4p+5, 0x0p+0)),
                base_id = list(0L, 1L), unlinks = list())), list(
            kind = "segment_map", name = "different_base_sections_road_center_lines_1",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(20L, 0L), list(20L, 0L), list(30L,
                0L), list(40L, 0L)), sections = list(3L, 3L),
                network_type = "road_center_lines", snap = 0L,
                tail = 0L, deviation = 0L, extrude = 0L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+4,
                  0x0p+0), list(0x1.4p+4, 0x0p+0, 0x1.4p+5, 0x0p+0)),
                base_id = list(0L, 1L), unlinks = list())), list(
            kind = "segment_map", name = "different_base_sections_road_center_lines_2",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(20L, 0L), list(20L, 0L), list(30L,
                0L), list(40L, 0L)), sections = list(3L, 3L),
                network_type = "road_center_lines", snap = 0x1p-1,
                tail = 2L, deviation = 0x1p-1, extrude = 2L),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+4, 0x0p+0), list(0x1.4p+4, 0x0p+0, 0x1.4p+5,
                0x0p+0)), base_id = list(0L, 1L), unlinks = list())),
        list(kind = "segment_map", name = "different_base_sections_road_center_lines_3",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(20L, 0L), list(20L, 0L), list(30L,
                0L), list(40L, 0L)), sections = list(3L, 3L),
                network_type = "road_center_lines", snap = 0x1.028f5c28f5c29p+0,
                tail = 10L, deviation = 2L, extrude = 1L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+4,
                  0x0p+0), list(0x1.4p+4, 0x0p+0, 0x1.4p+5, 0x0p+0)),
                base_id = list(0L, 1L), unlinks = list())), list(
            kind = "segment_map", name = "empty_singleton_sections_axial_or_segment_0",
            args = list(coords = list(list(100L, 100L), list(
                0L, 0L), list(10L, 0L)), sections = list(0L,
                1L, 2L), network_type = "axial_or_segment"),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+3, 0x0p+0)), base_id = list(2L), unlinks = list())),
        list(kind = "segment_map", name = "empty_singleton_sections_axial_or_segment_1",
            args = list(coords = list(list(100L, 100L), list(
                0L, 0L), list(10L, 0L)), sections = list(0L,
                1L, 2L), network_type = "axial_or_segment", snap = 0L,
                tail = 0L, deviation = 0L, extrude = 0L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+3,
                  0x0p+0)), base_id = list(2L), unlinks = list())),
        list(kind = "segment_map", name = "empty_singleton_sections_axial_or_segment_2",
            args = list(coords = list(list(100L, 100L), list(
                0L, 0L), list(10L, 0L)), sections = list(0L,
                1L, 2L), network_type = "axial_or_segment", snap = 0x1p-1,
                tail = 2L, deviation = 0x1p-1, extrude = 2L),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+3, 0x0p+0)), base_id = list(2L), unlinks = list())),
        list(kind = "segment_map", name = "empty_singleton_sections_axial_or_segment_3",
            args = list(coords = list(list(100L, 100L), list(
                0L, 0L), list(10L, 0L)), sections = list(0L,
                1L, 2L), network_type = "axial_or_segment", snap = 0x1.028f5c28f5c29p+0,
                tail = 10L, deviation = 2L, extrude = 1L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+3,
                  0x0p+0)), base_id = list(2L), unlinks = list())),
        list(kind = "segment_map", name = "empty_singleton_sections_road_center_lines_0",
            args = list(coords = list(list(100L, 100L), list(
                0L, 0L), list(10L, 0L)), sections = list(0L,
                1L, 2L), network_type = "road_center_lines"),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+3, 0x0p+0)), base_id = list(2L), unlinks = list())),
        list(kind = "segment_map", name = "empty_singleton_sections_road_center_lines_1",
            args = list(coords = list(list(100L, 100L), list(
                0L, 0L), list(10L, 0L)), sections = list(0L,
                1L, 2L), network_type = "road_center_lines",
                snap = 0L, tail = 0L, deviation = 0L, extrude = 0L),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+3, 0x0p+0)), base_id = list(2L), unlinks = list())),
        list(kind = "segment_map", name = "empty_singleton_sections_road_center_lines_2",
            args = list(coords = list(list(100L, 100L), list(
                0L, 0L), list(10L, 0L)), sections = list(0L,
                1L, 2L), network_type = "road_center_lines",
                snap = 0x1p-1, tail = 2L, deviation = 0x1p-1,
                extrude = 2L), native = list(segments = list(
                list(0x0p+0, 0x0p+0, 0x1.4p+3, 0x0p+0)), base_id = list(
                2L), unlinks = list())), list(kind = "segment_map",
            name = "empty_singleton_sections_road_center_lines_3",
            args = list(coords = list(list(100L, 100L), list(
                0L, 0L), list(10L, 0L)), sections = list(0L,
                1L, 2L), network_type = "road_center_lines",
                snap = 0x1.028f5c28f5c29p+0, tail = 10L, deviation = 2L,
                extrude = 1L), native = list(segments = list(
                list(0x0p+0, 0x0p+0, 0x1.4p+3, 0x0p+0)), base_id = list(
                2L), unlinks = list())), list(kind = "segment_map",
            name = "zero_length_axial_or_segment_0", args = list(
                coords = list(list(0L, 0L), list(0L, 0L)), sections = list(
                  2L), network_type = "axial_or_segment"), native = list(
                segments = list(), base_id = list(), unlinks = list())),
        list(kind = "segment_map", name = "zero_length_axial_or_segment_1",
            args = list(coords = list(list(0L, 0L), list(0L,
                0L)), sections = list(2L), network_type = "axial_or_segment",
                snap = 0L, tail = 0L, deviation = 0L, extrude = 0L),
            native = list(segments = list(), base_id = list(),
                unlinks = list())), list(kind = "segment_map",
            name = "zero_length_axial_or_segment_2", args = list(
                coords = list(list(0L, 0L), list(0L, 0L)), sections = list(
                  2L), network_type = "axial_or_segment", snap = 0x1p-1,
                tail = 2L, deviation = 0x1p-1, extrude = 2L),
            native = list(segments = list(), base_id = list(),
                unlinks = list())), list(kind = "segment_map",
            name = "zero_length_axial_or_segment_3", args = list(
                coords = list(list(0L, 0L), list(0L, 0L)), sections = list(
                  2L), network_type = "axial_or_segment", snap = 0x1.028f5c28f5c29p+0,
                tail = 10L, deviation = 2L, extrude = 1L), native = list(
                segments = list(), base_id = list(), unlinks = list())),
        list(kind = "segment_map", name = "zero_length_road_center_lines_0",
            args = list(coords = list(list(0L, 0L), list(0L,
                0L)), sections = list(2L), network_type = "road_center_lines"),
            native = list(segments = list(), base_id = list(),
                unlinks = list())), list(kind = "segment_map",
            name = "zero_length_road_center_lines_1", args = list(
                coords = list(list(0L, 0L), list(0L, 0L)), sections = list(
                  2L), network_type = "road_center_lines", snap = 0L,
                tail = 0L, deviation = 0L, extrude = 0L), native = list(
                segments = list(), base_id = list(), unlinks = list())),
        list(kind = "segment_map", name = "zero_length_road_center_lines_2",
            args = list(coords = list(list(0L, 0L), list(0L,
                0L)), sections = list(2L), network_type = "road_center_lines",
                snap = 0x1p-1, tail = 2L, deviation = 0x1p-1,
                extrude = 2L), native = list(segments = list(),
                base_id = list(), unlinks = list())), list(kind = "segment_map",
            name = "zero_length_road_center_lines_3", args = list(
                coords = list(list(0L, 0L), list(0L, 0L)), sections = list(
                  2L), network_type = "road_center_lines", snap = 0x1.028f5c28f5c29p+0,
                tail = 10L, deviation = 2L, extrude = 1L), native = list(
                segments = list(), base_id = list(), unlinks = list())),
        list(kind = "segment_map", name = "duplicate_reverse_axial_or_segment_0",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(10L, 0L), list(0L, 0L)), sections = list(
                2L, 2L), network_type = "axial_or_segment"),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+3, 0x0p+0)), base_id = list(0L), unlinks = list())),
        list(kind = "segment_map", name = "duplicate_reverse_axial_or_segment_1",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(10L, 0L), list(0L, 0L)), sections = list(
                2L, 2L), network_type = "axial_or_segment", snap = 0L,
                tail = 0L, deviation = 0L, extrude = 0L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+3,
                  0x0p+0)), base_id = list(0L), unlinks = list())),
        list(kind = "segment_map", name = "duplicate_reverse_axial_or_segment_2",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(10L, 0L), list(0L, 0L)), sections = list(
                2L, 2L), network_type = "axial_or_segment", snap = 0x1p-1,
                tail = 2L, deviation = 0x1p-1, extrude = 2L),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+3, 0x0p+0)), base_id = list(0L), unlinks = list())),
        list(kind = "segment_map", name = "duplicate_reverse_axial_or_segment_3",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(10L, 0L), list(0L, 0L)), sections = list(
                2L, 2L), network_type = "axial_or_segment", snap = 0x1.028f5c28f5c29p+0,
                tail = 10L, deviation = 2L, extrude = 1L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+3,
                  0x0p+0)), base_id = list(0L), unlinks = list())),
        list(kind = "segment_map", name = "duplicate_reverse_road_center_lines_0",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(10L, 0L), list(0L, 0L)), sections = list(
                2L, 2L), network_type = "road_center_lines"),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+3, 0x0p+0)), base_id = list(0L), unlinks = list())),
        list(kind = "segment_map", name = "duplicate_reverse_road_center_lines_1",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(10L, 0L), list(0L, 0L)), sections = list(
                2L, 2L), network_type = "road_center_lines",
                snap = 0L, tail = 0L, deviation = 0L, extrude = 0L),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+3, 0x0p+0)), base_id = list(0L), unlinks = list())),
        list(kind = "segment_map", name = "duplicate_reverse_road_center_lines_2",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(10L, 0L), list(0L, 0L)), sections = list(
                2L, 2L), network_type = "road_center_lines",
                snap = 0x1p-1, tail = 2L, deviation = 0x1p-1,
                extrude = 2L), native = list(segments = list(
                list(0x0p+0, 0x0p+0, 0x1.4p+3, 0x0p+0)), base_id = list(
                0L), unlinks = list())), list(kind = "segment_map",
            name = "duplicate_reverse_road_center_lines_3", args = list(
                coords = list(list(0L, 0L), list(10L, 0L), list(
                  10L, 0L), list(0L, 0L)), sections = list(2L,
                  2L), network_type = "road_center_lines", snap = 0x1.028f5c28f5c29p+0,
                tail = 10L, deviation = 2L, extrude = 1L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+3,
                  0x0p+0)), base_id = list(0L), unlinks = list())),
        list(kind = "segment_map", name = "disconnected_axial_or_segment_0",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(100L, 0L), list(110L, 0L)), sections = list(
                2L, 2L), network_type = "axial_or_segment"),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+3, 0x0p+0), list(0x1.9p+6, 0x0p+0, 0x1.b8p+6,
                0x0p+0)), base_id = list(0L, 1L), unlinks = list())),
        list(kind = "segment_map", name = "disconnected_axial_or_segment_1",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(100L, 0L), list(110L, 0L)), sections = list(
                2L, 2L), network_type = "axial_or_segment", snap = 0L,
                tail = 0L, deviation = 0L, extrude = 0L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+3,
                  0x0p+0), list(0x1.9p+6, 0x0p+0, 0x1.b8p+6,
                  0x0p+0)), base_id = list(0L, 1L), unlinks = list())),
        list(kind = "segment_map", name = "disconnected_axial_or_segment_2",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(100L, 0L), list(110L, 0L)), sections = list(
                2L, 2L), network_type = "axial_or_segment", snap = 0x1p-1,
                tail = 2L, deviation = 0x1p-1, extrude = 2L),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+3, 0x0p+0), list(0x1.9p+6, 0x0p+0, 0x1.b8p+6,
                0x0p+0)), base_id = list(0L, 1L), unlinks = list())),
        list(kind = "segment_map", name = "disconnected_axial_or_segment_3",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(100L, 0L), list(110L, 0L)), sections = list(
                2L, 2L), network_type = "axial_or_segment", snap = 0x1.028f5c28f5c29p+0,
                tail = 10L, deviation = 2L, extrude = 1L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+3,
                  0x0p+0), list(0x1.9p+6, 0x0p+0, 0x1.b8p+6,
                  0x0p+0)), base_id = list(0L, 1L), unlinks = list())),
        list(kind = "segment_map", name = "disconnected_road_center_lines_0",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(100L, 0L), list(110L, 0L)), sections = list(
                2L, 2L), network_type = "road_center_lines"),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+3, 0x0p+0), list(0x1.9p+6, 0x0p+0, 0x1.b8p+6,
                0x0p+0)), base_id = list(0L, 1L), unlinks = list())),
        list(kind = "segment_map", name = "disconnected_road_center_lines_1",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(100L, 0L), list(110L, 0L)), sections = list(
                2L, 2L), network_type = "road_center_lines",
                snap = 0L, tail = 0L, deviation = 0L, extrude = 0L),
            native = list(segments = list(list(0x0p+0, 0x0p+0,
                0x1.4p+3, 0x0p+0), list(0x1.9p+6, 0x0p+0, 0x1.b8p+6,
                0x0p+0)), base_id = list(0L, 1L), unlinks = list())),
        list(kind = "segment_map", name = "disconnected_road_center_lines_2",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L), list(100L, 0L), list(110L, 0L)), sections = list(
                2L, 2L), network_type = "road_center_lines",
                snap = 0x1p-1, tail = 2L, deviation = 0x1p-1,
                extrude = 2L), native = list(segments = list(
                list(0x0p+0, 0x0p+0, 0x1.4p+3, 0x0p+0), list(
                  0x1.9p+6, 0x0p+0, 0x1.b8p+6, 0x0p+0)), base_id = list(
                0L, 1L), unlinks = list())), list(kind = "segment_map",
            name = "disconnected_road_center_lines_3", args = list(
                coords = list(list(0L, 0L), list(10L, 0L), list(
                  100L, 0L), list(110L, 0L)), sections = list(
                  2L, 2L), network_type = "road_center_lines",
                snap = 0x1.028f5c28f5c29p+0, tail = 10L, deviation = 2L,
                extrude = 1L), native = list(segments = list(
                list(0x0p+0, 0x0p+0, 0x1.4p+3, 0x0p+0), list(
                  0x1.9p+6, 0x0p+0, 0x1.b8p+6, 0x0p+0)), base_id = list(
                0L, 1L), unlinks = list())), list(kind = "segment_map",
            name = "cut_unlink_10", args = list(coords = list(
                list(0L, 0L), list(20L, 0L), list(10L, -10L),
                list(10L, 10L)), sections = list(2L, 2L), network_type = "axial_or_segment",
                snap = 0L, tail = 0L, deviation = 0L, unlinks = list(
                  list(10L, 0L))), native = list(segments = list(
                list(0x0p+0, 0x0p+0, 0x1.4p+4, 0x0p+0), list(
                  0x1.4p+3, -0x1.4p+3, 0x1.4p+3, 0x1.4p+3)),
                base_id = list(0L, 1L), unlinks = list())), list(
            kind = "segment_map", name = "cut_unlink_110", args = list(
                coords = list(list(0L, 0L), list(20L, 0L), list(
                  10L, -10L), list(10L, 10L)), sections = list(
                  2L, 2L), network_type = "axial_or_segment",
                snap = 0L, tail = 0L, deviation = 0L, unlinks = list(
                  list(110L, 0L))), native = list(segments = list(
                list(0x0p+0, 0x0p+0, 0x1.4p+3, 0x0p+0), list(
                  0x1.4p+3, 0x0p+0, 0x1.4p+4, 0x0p+0), list(0x1.4p+3,
                  -0x1.4p+3, 0x1.4p+3, 0x0p+0), list(0x1.4p+3,
                  0x0p+0, 0x1.4p+3, 0x1.4p+3)), base_id = list(
                0L, 0L, 1L, 1L), unlinks = list())), list(kind = "segment_map",
            name = "cut_unlink_109.99", args = list(coords = list(
                list(0L, 0L), list(20L, 0L), list(10L, -10L),
                list(10L, 10L)), sections = list(2L, 2L), network_type = "axial_or_segment",
                snap = 0L, tail = 0L, deviation = 0L, unlinks = list(
                  list(0x1.b7f5c28f5c28fp+6, 0L))), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+4,
                  0x0p+0), list(0x1.4p+3, -0x1.4p+3, 0x1.4p+3,
                  0x1.4p+3)), base_id = list(0L, 1L), unlinks = list())),
        list(kind = "segment_map", name = "cut_unlink_10000",
            args = list(coords = list(list(0L, 0L), list(20L,
                0L), list(10L, -10L), list(10L, 10L)), sections = list(
                2L, 2L), network_type = "axial_or_segment", snap = 0L,
                tail = 0L, deviation = 0L, unlinks = list(list(
                  10000L, 10000L))), native = list(segments = list(
                list(0x0p+0, 0x0p+0, 0x1.4p+3, 0x0p+0), list(
                  0x1.4p+3, 0x0p+0, 0x1.4p+4, 0x0p+0), list(0x1.4p+3,
                  -0x1.4p+3, 0x1.4p+3, 0x0p+0), list(0x1.4p+3,
                  0x0p+0, 0x1.4p+3, 0x1.4p+3)), base_id = list(
                0L, 0L, 1L, 1L), unlinks = list())), list(kind = "segment_map",
            name = "safe_unit_closed", args = list(coords = list(
                list(0L, 0L), list(1L, 0L), list(1L, 1L), list(
                  0L, 1L), list(0L, 0L)), sections = list(5L),
                network_type = "axial_or_segment", snap = 0L,
                tail = 0L, deviation = 0L), native = list(segments = list(
                list(0x0p+0, 0x0p+0, 0x1p+0, 0x0p+0), list(0x1p+0,
                  0x0p+0, 0x1p+0, 0x1p+0), list(0x1p+0, 0x1p+0,
                  0x0p+0, 0x1p+0), list(0x0p+0, 0x1p+0, 0x0p+0,
                  0x0p+0)), base_id = list(0L, 0L, 0L, 0L), unlinks = list())),
        list(kind = "segment_map", name = "trailing_negative_section",
            args = list(coords = list(list(0L, 0L), list(10L,
                0L)), sections = list(-3L), network_type = "axial_or_segment",
                snap = 0L, tail = 0L, deviation = 0L), native = list(
                segments = list(list(0x0p+0, 0x0p+0, 0x1.4p+3,
                  0x0p+0)), base_id = list(0L), unlinks = list())),
        list(kind = "segment_map", name = "large_world_map",
            args = list(coords = list(list(0x1.d1a94a2p+39, 0x1.d1a94a2p+39),
                list(0x1.d1a94a2014p+39, 0x1.d1a94a2p+39), list(
                  0x1.d1a94a2028p+39, 0x1.d1a94a2p+39)), sections = list(
                3L), network_type = "axial_or_segment", snap = 0L,
                tail = 0L, deviation = 1L), native = list(segments = list(
                list(0x1.d1a94a2p+39, 0x1.d1a94a2p+39, 0x1.d1a94a2028p+39,
                  0x1.d1a94a2p+39)), base_id = list(0L), unlinks = list()))))
