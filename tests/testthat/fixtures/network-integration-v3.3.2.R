list(
  pst_version = "3.3.2",
  pst_commit = "63df80a2cf3dd289be95ea3d91667c3490719b75",
  oracle_path = "pstalgo/test/tests/testnetworkintegration.py",
  oracle_blob = "2654a0f39a633de1b489a811b9146e9c171192ac",
  geometry_path = "pstalgo/test/tests/graphs.py",
  geometry_blob = "30337ddfc24f80e425a41029839c7d1c2e08d997",
  comparison_path = "pstalgo/test/tests/common.py",
  comparison_blob = "5012bc7a7f907f63c30def1278e079889ec768bb",
  # Endpoint pairs expanded from CreateChainGraph(5, 3), in the same order.
  lines = matrix(c(0, 0, 3, 0,
                   3, 0, 6, 0,
                   6, 0, 9, 0,
                   9, 0, 12, 0,
                   12, 0, 15, 0), ncol = 4L, byrow = TRUE),
  # Literal expectations from test_NInt_chain; never generated using rPSTool.
  integration = c(0.352, 0.704, 1.056, 0.704, 0.352),
  node_count = c(5L, 5L, 5L, 5L, 5L),
  total_depth = c(10, 7, 6, 7, 10),
  # Upstream IsRoughlyEqual uses actual-denominator relative error <= 0.0001,
  # or absolute error <= 0.0001 when the actual value is zero.
  integration_relative_tolerance = 0.0001,
  steps = list(
    list(limit = 0L, node_count = c(1L, 1L, 1L, 1L, 1L)),
    list(limit = 1L, node_count = c(2L, 3L, 3L, 3L, 2L)),
    list(limit = 2L, node_count = c(3L, 4L, 5L, 4L, 3L))
  ),
  # test_NInt_single uses one line of length 3, Radii(), and exact expectations.
  single_line = matrix(c(0, 0, 3, 0), nrow = 1L),
  single_integration = -1,
  single_node_count = 1L,
  single_total_depth = 0
)
