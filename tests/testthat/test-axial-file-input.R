# axial_graph(<file path>) for GeoParquet and FlatGeobuf (docs/spatial-io/axial-file-input.md). The fixtures hold the line
# geometry of the direct pinned-PST axial reference cases, so every file-backed graph is checked against values
# PST itself produced as well as against the matrix and sf routes in the file's actual physical order.

skip_axial_fgb <- function() skip_if_not_installed("sf")
skip_axial_parquet <- function() {
  skip_if_not_installed("arrow", "25.0.0"); skip_if_not_installed("jsonlite"); skip_if_not_installed("sf")
}

test_that("FlatGeobuf-backed axial graphs match the direct pinned-PST reference for the selected non-indexed cases (all of them in the full suite)", {
  skip_axial_fgb()
  cases <- ax_file_cases()
  expect_gte(length(cases), 20L)
  # CRAN mode: every case is still built from the file and its structure compared; the eight radius integrations of a case are
  # visited as a deterministic subset that still includes every radius class (all of them in full mode).
  for (case in rpst_thin_items(cases, "integrations", every = 4L, by = list(rpst_radius_class))) {
    g <- do.call(axial_graph, c(list(ax_fixture(case$name, "fgb")), ax_case_args(case)))
    expect_s3_class(g, "pst_graph"); expect_identical(g$type, "axial"); expect_identical(g$pst_version, "3.3.2")
    ax_expect_reference(g, case)
    ax_native("graph_release", g$ptr)
  }
})

test_that("GeoParquet-backed axial graphs match the direct pinned-PST reference for the selected non-indexed cases (all of them in the full suite)", {
  skip_axial_parquet()
  for (case in rpst_thin_items(ax_file_cases(), "integrations", every = 5L, by = list(rpst_radius_class))) {
    g <- do.call(axial_graph, c(list(ax_fixture(case$name, "parquet")), ax_case_args(case)))
    expect_identical(g$type, "axial")
    ax_expect_reference(g, case)
    ax_native("graph_release", g$ptr)
  }
})

test_that("file, matrix and sf routes build identical graphs from the same coordinates in file order", {
  skip_axial_parquet()
  for (name in c("expanded", "chain", "coincident", "points", "polygons_3", "rings")) {
    case <- Filter(function(k) identical(k$name, name), ax_file_cases())[[1L]]
    args <- ax_case_args(case)
    lines <- ax_case_lines(case)
    from_matrix <- do.call(axial_graph, c(list(lines), args))
    from_fgb <- do.call(axial_graph, c(list(ax_fixture(name, "fgb")), args))
    from_parquet <- do.call(axial_graph, c(list(ax_fixture(name, "parquet")), args))
    sfc <- sf::st_sfc(lapply(seq_len(nrow(lines)), function(i) sf::st_linestring(rbind(lines[i, 1:2], lines[i, 3:4]))),
                      crs = 32630)
    from_sf <- do.call(axial_graph, c(list(sf::st_sf(geometry = sfc)), args))
    ax_expect_same_graph(from_matrix, from_fgb)
    ax_expect_same_graph(from_matrix, from_parquet)
    ax_expect_same_graph(from_matrix, from_sf)
    expect_identical(sf::st_crs(attr(from_fgb, "crs")), sf::st_crs(32630))
    expect_identical(attr(from_fgb, "crs") == attr(from_parquet, "crs"), TRUE)
    expect_identical(attr(from_fgb, "crs") == attr(from_sf, "crs"), TRUE)
  }
})

test_that("physical file order drives the graph: an indexed FlatGeobuf is NOT in writer order", {
  skip_axial_fgb()
  path <- ax_fixture("order-indexed", "fgb")
  physical <- ax_fgb_matrix(path)                                     # GDAL's read order = physical order
  csv <- utils::read.csv(ax_fixture("lines", "csv"))
  written <- as.matrix(csv[csv$case == "order-indexed", c("x1", "y1", "x2", "y2")]); dimnames(written) <- NULL
  expect_identical(sort(apply(physical, 1, paste, collapse = ",")), sort(apply(written, 1, paste, collapse = ",")))
  expect_false(isTRUE(all.equal(physical, written)))                  # Hilbert order differs from writer order
  # The T junction at (40, 0): line A (0,0)-(100,0) has it in its interior, B (40,0)-(40,60) ends on it.
  unlink <- matrix(c(40, 0), 1)
  from_file <- axial_graph(path, unlinks = unlink)
  in_file_order <- axial_graph(physical, unlinks = unlink)
  in_writer_order <- axial_graph(written, unlinks = unlink)
  ax_expect_same_graph(from_file, in_file_order)                      # file route == matrix in PHYSICAL order
  ax_expect_same_graph(axial_graph(path), axial_graph(physical))
  # Unlink eligibility depends on which line of a pair comes first, so the two orders really differ.
  expect_false(identical(from_file$n_crossings, in_writer_order$n_crossings))
  expect_false(identical(axial_crossing_coords(from_file), axial_crossing_coords(in_writer_order)))
  # The order-sensitive reference cases: swapping which line is first changes eligibility (docs/compatibility/axial-inputs-junctions.md).
  skip_axial_parquet()
  interior <- axial_graph(ax_fixture("T_interior_first", "parquet"), unlinks = matrix(c(0, 0), 1))
  endpoint <- axial_graph(ax_fixture("T_endpoint_first", "parquet"), unlinks = matrix(c(0, 0), 1))
  expect_s3_class(interior, "pst_graph"); expect_s3_class(endpoint, "pst_graph")
})

test_that("CRS metadata is retained and reconciled with sf unlinks and points exactly like the sf route", {
  skip_axial_parquet()
  fgb <- ax_fixture("expanded", "fgb"); parquet <- ax_fixture("expanded", "parquet")
  utm <- sf::st_crs(32630)
  point_in <- function(crs) sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(1, 0)), crs = crs))
  for (path in c(fgb, parquet)) {
    expect_true(attr(axial_graph(path), "crs") == utm)
    # matching sf unlinks/points are accepted, with the same result as matrix auxiliaries
    ok <- axial_graph(path, unlinks = point_in(32630), points = point_in(32630))
    ax_expect_same_graph(ok, axial_graph(path, unlinks = matrix(c(1, 0), 1), points = matrix(c(1, 0), 1)))
    expect_true(attr(ok, "crs") == utm)
    # a different known CRS, an unknown CRS, and a geographic CRS cannot be mixed with the file's CRS
    expect_error(axial_graph(path, unlinks = point_in(32631)), "compatible CRS")
    expect_error(axial_graph(path, points = point_in(sf::NA_crs_)), "compatible CRS")
    expect_error(axial_graph(path, unlinks = point_in(4326)), "Geographic")
    # matrices carry no CRS and are used on the caller's responsibility
    expect_s3_class(axial_graph(path, unlinks = matrix(c(1, 0), 1)), "pst_graph")
  }
  # Unknown file CRS: sf inputs must also be unknown; known sf CRS is rejected, matrices are fine.
  unknown <- list(fgb = test_path("fixtures", "flatgeobuf", "lattice-unknown-crs.fgb"),
                  parquet = test_path("fixtures", "geoparquet", "lattice-planar-null-crs.parquet"))
  for (path in unknown) {
    g <- axial_graph(path)
    expect_true(is.na(attr(g, "crs")))
    expect_s3_class(axial_graph(path, unlinks = point_in(sf::NA_crs_)), "pst_graph")
    expect_error(axial_graph(path, unlinks = point_in(32630)), "compatible CRS")
  }
  # Geographic files are rejected by the readers before any native work.
  expect_error(axial_graph(test_path("fixtures", "flatgeobuf", "lattice-geographic-4326.fgb")), "Geographic")
  expect_error(axial_graph(test_path("fixtures", "geoparquet", "lattice-geographic-4326.parquet")), "Geographic")
})

test_that("the axial_graph() file contract: line_indices is rejected, other inputs keep their validation", {
  skip_axial_fgb()
  path <- ax_fixture("expanded", "fgb")
  before <- ax_lifecycle()
  expect_error(axial_graph(path, line_indices = matrix(1:2, 1)), "line_indices must be NULL when x is a file path")
  expect_error(axial_graph(path, unlinks = matrix(1:3, 1)), "unlinks must have")
  expect_error(axial_graph(path, points = matrix(c(1, NA), 1)), "finite")
  expect_error(axial_graph(path, points_per_polygon = 1), "points_per_polygon")
  expect_error(axial_graph(path, polygon_point_interval = 1), "requires points_per_polygon")
  expect_error(axial_graph(path, points = matrix(c(0, 0, 1, 1, 2, 0), 3, byrow = TRUE), points_per_polygon = 3),
               "polygon_point_interval")
  expect_error(axial_graph(path, points = matrix(c(0, 0, 1, 1, 2, 0), 3, byrow = TRUE), points_per_polygon = 3,
                         polygon_point_interval = 1e300), "positive finite native float")
  expect_error(axial_graph(c(path, path)), "single")
  expect_error(axial_graph(NA_character_), "single")
  expect_error(axial_graph(file.path(tempdir(), "no-such-file.fgb")), "does not exist")
  expect_error(axial_graph(tempdir()), "directory")
  # a character MATRIX keeps the established matrix error
  expect_error(axial_graph(matrix(c("a", "b", "c", "d"), 1)), "numeric matrix")
  # none of the failures above created a native graph
  expect_identical(ax_lifecycle()[[1]], before[[1]])
  # format identification is by content and names the right API
  junk <- tempfile(fileext = ".fgb"); writeBin(as.raw(1:20), junk)
  expect_error(axial_graph(junk), "Unsupported file format")
  expect_error(axial_graph(ax_fixture("lines", "csv")), "Unsupported file format")
})

test_that("malformed and unsupported files are rejected by axial_graph() without publishing a graph", {
  skip_axial_fgb()
  before <- ax_lifecycle()
  fgb <- function(name) test_path("fixtures", "flatgeobuf", paste0(name, ".fgb"))
  expect_error(axial_graph(fgb("zero")), "axial graph needs at least one line")
  expect_error(axial_graph(fgb("point")), "geometry_type|LineString")
  expect_error(axial_graph(fgb("polygon")), "geometry_type|LineString")
  expect_error(axial_graph(fgb("linestring-z")), "Z|M|dimension|geometry_type")
  expect_error(axial_graph(fgb("mixed-2pt-3pt")), "exactly 2|two vertices|vertices")
  expect_error(axial_graph(fgb("null-geometry")), "null|geometry")
  expect_error(axial_graph(fgb("patched-first-x-inf")), "finite|non-finite")
  expect_error(axial_graph(fgb("patched-declared-30")), "declare")
  expect_error(axial_graph(fgb("lattice-geographic-4326")), "Geographic")
  expect_identical(ax_lifecycle()[[1]], before[[1]])        # no failure above created a native graph
  # Random single-byte corruption of a valid file: always an error or a graph, never a crash.
  bytes <- readBin(ax_fixture("chain", "fgb"), "raw", file.size(ax_fixture("chain", "fgb")))
  set.seed(42)
  for (k in seq_len(150)) {
    mutated <- bytes; i <- sample(length(bytes), 1L); mutated[i] <- as.raw(sample(0:255, 1L))
    p <- tempfile(fileext = ".fgb"); writeBin(mutated, p)
    r <- tryCatch(axial_graph(p), error = function(e) conditionMessage(e))
    expect_true(is.character(r) || inherits(r, "pst_graph"))
    unlink(p)
  }
  invisible(gc())
})

test_that("malformed GeoParquet files are rejected by axial_graph() with accurate messages", {
  skip_axial_parquet()
  gp <- function(name) test_path("fixtures", "geoparquet", paste0(name, ".parquet"))
  before <- ax_lifecycle()
  expect_error(axial_graph(gp("empty")), "axial graph needs at least one line")
  for (bad in c("bad-multilinestring", "bad-null-geometry", "bad-polyline", "bad-iso-z", "bad-nan"))
    expect_error(axial_graph(gp(bad)), "[Rr]ow|row")
  expect_error(axial_graph(gp("lattice-no-geo")), "geo")
  expect_error(axial_graph(gp("lattice-crs-absent")), "CRS84|crs")
  expect_error(axial_graph(gp("lattice-spherical")), "planar")
  expect_error(axial_graph(gp("lattice-version-2")), "version")
  expect_identical(ax_lifecycle()[[1]], before[[1]])        # nothing was published
  # Required optional packages are named for the calling API.
  testthat::local_mocked_bindings(requireNamespace = function(package, ..., quietly = FALSE) FALSE, .package = "base")
  expect_error(axial_graph(gp("lattice-binary")), "axial_graph\\(\\)")
})

test_that("extent and overflow checks run against the file's lines and the auxiliary inputs", {
  skip_axial_fgb()
  path <- ax_fixture("expanded", "fgb")
  before <- ax_lifecycle()
  # The unlink is far outside the file's bounding box: PST's float local range would overflow.
  expect_error(axial_graph(path, unlinks = matrix(c(1e39, 0), 1)), "overflows")
  expect_error(axial_graph(path, points = matrix(c(1e39, 0), 1)), "overflows")
  # A file whose own extent cannot be held in PST's float distances.
  big <- tempfile(fileext = ".fgb")
  geom <- sf::st_sfc(sf::st_linestring(rbind(c(-3e38, 0), c(3e38, 0))), sf::st_linestring(rbind(c(0, -3e38), c(0, 3e38))), crs = 32630)
  suppressWarnings(sf::st_write(sf::st_sf(id = 1:2, geometry = geom), big, driver = "FlatGeobuf", quiet = TRUE))
  expect_error(axial_graph(big), "overflows")
  # Polygon sampling bounds still apply to file graphs.
  ring <- matrix(c(0, 0, 1e12, 0, 1e12, 1e12), ncol = 2, byrow = TRUE)
  expect_error(axial_graph(path, points = ring, points_per_polygon = 3, polygon_point_interval = 1), "exceeds PST's native signed point-count")
  if (requireNamespace("arrow", quietly = TRUE) && requireNamespace("jsonlite", quietly = TRUE)) {
    parquet <- ax_fixture("expanded", "parquet")
    expect_error(axial_graph(parquet, unlinks = matrix(c(1e39, 0), 1)), "overflows")
    expect_error(axial_graph(parquet, points = matrix(c(1e39, 0), 1)), "overflows")
  }
  # Failures after decode leave an empty, finalisable pointer and publish nothing.
  expect_identical(ax_lifecycle()[[1]], before[[1]])
  invisible(gc())
})

test_that("file-backed graphs follow the established axial lifecycle", {
  skip_axial_parquet()
  base <- ax_lifecycle()
  g <- axial_graph(ax_fixture("chain", "fgb")); h <- axial_graph(ax_fixture("chain", "parquet"))
  after <- ax_lifecycle()
  expect_identical(after[[1]] - base[[1]], 2)
  expect_identical(after[[3]] - base[[3]], 2)
  # exact tag / liveness / aliases / explicit release
  alias <- g
  expect_identical(axial_line_lengths(alias), axial_line_lengths(g))
  lengths <- axial_line_lengths(g); crossings <- axial_crossing_coords(g)
  ax_native("graph_release", g$ptr)
  expect_error(axial_line_lengths(g), "no longer live")
  expect_error(axial_line_lengths(alias), "no longer live")
  ax_native("graph_release", g$ptr)                                   # repeated release is safe
  expect_identical(lengths, axial_line_lengths(h))                # outputs outlive the released graph
  expect_identical(crossings, axial_crossing_coords(h))
  # a segment graph pointer is not an axial graph
  segment <- segment_graph(ax_fixture("chain", "fgb"))
  expect_error(axial_line_lengths(list(ptr = segment$ptr, type = "axial", class = "pst_graph")), "Invalid|axial")
  # serialisation produces a dead pointer
  copy <- unserialize(serialize(h, NULL))
  expect_error(axial_line_lengths(copy), "no longer live")
  # GC finalises abandoned file graphs
  rm(h, alias, copy, segment); invisible(gc()); invisible(gc())
  final <- ax_lifecycle()
  expect_identical(final[[3]], base[[3]])
})

test_that("a pointer made for a file route cannot be reused and the segment route is unchanged", {
  skip_axial_fgb()
  ptr <- ax_native("axial_graph_new_pointer")
  info <- ax_native("fgb_inspect", ax_fixture("chain", "fgb"))
  none <- function(...) NULL
  ax_native("fgb_axial_graph", ptr, ax_fixture("chain", "fgb"), info$header, none(), none(), none(), none())
  expect_error(ax_native("fgb_axial_graph", ptr, ax_fixture("chain", "fgb"), info$header, none(), none(), none(), none()),
               "not empty")
  expect_error(ax_native("fgb_axial_graph", ax_native("segment_graph_new_pointer"), ax_fixture("chain", "fgb"),
                         info$header, none(), none(), none(), none()), "Invalid pst_graph native pointer")
  expect_error(ax_native("fgb_segment_graph", ptr, ax_fixture("chain", "fgb"), info$header), "Invalid pst_segment_graph")
  expect_identical(segment_graph(ax_fixture("chain", "fgb"))$n_segments, 5L)
  expect_error(segment_graph(matrix(c("a", "b", "c", "d"), 1)), "numeric matrix")
})
