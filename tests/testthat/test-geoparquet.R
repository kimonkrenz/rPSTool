# End-to-end GeoParquet path input for segment_graph() with the optional R `arrow`
# package (>= 25.0.0), jsonlite and sf. Skipped cleanly when any is absent. The tiny fixtures
# in fixtures/geoparquet/ are written by tools/make-geoparquet-fixtures.py (development-only
# pyarrow); see MANIFEST.tsv. The Arrow-independent native boundary is covered separately in
# test-arrow-native.R.

skip_geoparquet <- function() {
  skip_if_not_installed("arrow", "25.0.0")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("sf")
}
gp_fixture <- function(name) test_path("fixtures", "geoparquet", paste0(name, ".parquet"))

test_that("the analyses compared below are every segment-graph analysis currently bound", {
  ns <- asNamespace("rPSTool")
  consumers <- Filter(function(name) {
    f <- get(name, envir = ns)
    is.function(f) && any(grepl("pst_segment_graph\"|\\.pst_analysis_graph\\(graph, TRUE\\)",
                                paste(deparse(body(f)), collapse = " ")))
  }, getNamespaceExports(ns))
  expect_setequal(consumers, c("angular_integration", "angular_choice",
                               "segment_grouping", "segment_group_graph"))
  # segment_group_integration consumes the group graph derived from a segment graph.
  expect_true(all(c("segment_group_integration") %in% ls(ns)))
})

test_that("GeoParquet files give the same graph and results as matrix and sf input", {
  skip_geoparquet()
  expected <- gp_lattice()
  matrix_graph <- segment_graph(expected)
  reference <- segment_analyses(matrix_graph)
  # BINARY + projected CRS, LARGE_BINARY in a single row group, a file whose primary column is
  # the second of two geometry columns, planar edges + null CRS, and 5-row groups.
  cases <- c("lattice-binary", "lattice-large-binary", "lattice-two-geoms",
             "lattice-planar-null-crs", "lattice-multi-batch")
  for (case in cases) {
    graph <- segment_graph(gp_fixture(case))
    expect_s3_class(graph, "pst_segment_graph")
    expect_identical(graph$type, "segment")
    expect_identical(graph$n_segments, 24L)
    expect_identical(graph$pst_version, "3.3.2")
    expect_null(graph$coordinates)
    expect_identical(segment_analyses(graph), reference, info = case)
    sf_graph <- segment_graph(sf::st_sf(geometry = gp_lines(expected)))
    expect_identical(segment_analyses(sf_graph), reference)
  }
  # CRS: projected retained (equal to the sf route's), null CRS is the unknown crs.
  projected <- segment_graph(gp_fixture("lattice-binary"))
  sf_projected <- segment_graph(sf::st_set_crs(gp_lines(expected), 32630))
  expect_identical(attr(projected, "crs")$epsg, 32630L)
  expect_true(attr(projected, "crs") == attr(sf_projected, "crs"))
  unknown <- segment_graph(gp_fixture("lattice-large-binary"))
  expect_true(is.na(attr(unknown, "crs")))
  expect_identical(attr(unknown, "crs"), attr(segment_graph(gp_lines(expected)), "crs"))
  expect_null(attr(matrix_graph, "crs"))
})

test_that("fixtures cover both Arrow binary widths and mixed WKB byte order", {
  skip_geoparquet()
  binary <- rs_read_parquet(gp_fixture("lattice-binary"), as_data_frame = FALSE)
  large <- rs_read_parquet(gp_fixture("lattice-large-binary"), as_data_frame = FALSE)
  expect_true(binary$schema$geometry$type == arrow::binary())
  expect_true(large$schema$geometry$type == arrow::large_binary())
  expect_gt(rs_pq(gp_fixture("lattice-binary"))$num_row_groups, 2L)
  expect_identical(rs_pq(gp_fixture("lattice-large-binary"))$num_row_groups, 1L)
  bytes <- unlist(lapply(binary$geometry$as_vector(), function(w) w[[1L]]))
  expect_setequal(as.integer(bytes), c(0L, 1L))  # both byte-order markers occur in one column
  # Row order is the file's row order, not feature_id order (ids are not sequential).
  ids <- as.numeric(binary$feature_id$as_vector())
  expect_true(is.unsorted(ids))
  graph <- segment_graph(gp_fixture("lattice-binary"))
  expect_identical(angular_integration(graph)$segment_id, 1:24)
})

test_that("rejected metadata is reported before any native pointer is created", {
  skip_geoparquet()
  invisible(gc())
  before <- segment_balance()
  rejected <- c("lattice-crs-absent" = "no 'crs' key.*OGC:CRS84",
                "lattice-geographic-crs84" = "Geographic longitude/latitude CRS is unsupported",
                "lattice-geographic-4326" = "Geographic longitude/latitude CRS is unsupported",
                "lattice-invalid-crs" = "could not be interpreted as PROJJSON",
                "lattice-spherical" = "spherical edges are rejected",
                "lattice-no-geo" = "no GeoParquet 'geo' metadata",
                "lattice-bad-json" = "not valid JSON",
                "lattice-missing-primary" = "'primary_column' must be one non-empty string",
                "lattice-bad-primary" = "primary column 'nope' is not described",
                "lattice-primary-not-in-file" = "'ghost' is not a column of the file",
                "lattice-encoding-point" = "only \"WKB\" is supported",
                "lattice-version-2" = "Unsupported GeoParquet version '2.0.0'",
                "empty" = "no rows")
  for (name in names(rejected))
    expect_error(segment_graph(gp_fixture(name)), rejected[[name]], info = name)
  expect_identical(segment_balance(), before)
})

test_that("row-level geometry errors name the first offending one-based row", {
  skip_geoparquet()
  invisible(gc())
  before <- segment_balance()
  bad <- c("bad-null-geometry" = "Row 3: null geometry",
           "bad-polyline" = "Row 4: LineString has 3 points",
           "bad-multilinestring" = "Row 5: unsupported WKB geometry type 5",
           "bad-iso-z" = "Row 2: Z LineString \\(ISO type 1002\\)",
           "bad-nan" = "Row 6: non-finite coordinate")
  for (name in names(bad))
    expect_error(segment_graph(gp_fixture(name)), bad[[name]], info = name)
  invisible(gc())
  expect_identical(segment_balance(), before)  # no graph was published or leaked
})

test_that("path validation fails before the reader is created", {
  skip_geoparquet()
  fixture <- gp_fixture("lattice-binary")
  for (bad in list(NA_character_, "", character(), c(fixture, fixture)))
    expect_error(segment_graph(bad), "single non-empty, non-missing character string")
  expect_error(segment_graph(tempfile(fileext = ".parquet")), "does not exist")
  expect_error(segment_graph(tempdir()), "directory")
  # Magic bytes at both ends, no .parquet extension required.
  bytes <- readBin(fixture, "raw", file.size(fixture))
  write <- function(raw) { p <- tempfile(); writeBin(raw, p); p }
  expect_error(segment_graph(write(raw(0))), "too small")
  head_bad <- bytes; head_bad[1] <- as.raw(0)
  expect_error(segment_graph(write(head_bad)), "magic bytes 'PAR1'")
  tail_bad <- bytes; tail_bad[length(tail_bad)] <- as.raw(0)
  expect_error(segment_graph(write(tail_bad)), "magic bytes 'PAR1'")
  expect_error(segment_graph(write(charToRaw(strrep("x", 64)))), "magic bytes 'PAR1'")
  copy <- write(bytes)
  expect_false(grepl("[.]parquet$", copy))
  expect_identical(segment_graph(copy)$n_segments, 24L)
  expect_identical(segment_graph(path.expand(fixture))$n_segments, 24L)
})

test_that("only local regular files are accepted, before anything opens them", {
  skip_geoparquet()
  skip_on_os("windows")
  expect_error(segment_graph("/dev/null"), "not a regular local file")
  fifo <- tempfile()
  if (system2("mkfifo", shQuote(fifo), stderr = FALSE) == 0L) {
    on.exit(unlink(fifo), add = TRUE)
    expect_error(segment_graph(fifo), "not a regular local file")  # would block if opened
  }
  expect_error(segment_graph(tempdir()), "directory")
  # The native helper itself is strict.
  is_regular <- function(p) .Call(get("C_rpst_path_is_regular_file", asNamespace("rPSTool")), p)
  expect_true(is_regular(gp_fixture("lattice-binary")))
  expect_false(is_regular(tempdir()))
  expect_false(is_regular("/dev/null"))
  expect_false(is_regular(tempfile()))
  for (bad in list(NULL, 1, NA_character_, c("a", "b")))
    expect_error(is_regular(bad), "one non-missing string")
})

test_that("capability checks are explicit and isolated", {
  skip_geoparquet()
  expect_true(rPSTool:::.pst_geoparquet_capabilities())
  invisible(gc())
  before <- segment_balance()
  local_mocked_bindings(.pst_arrow_minimum = "99.0.0", .package = "rPSTool")
  expect_error(segment_graph(gp_fixture("lattice-binary")), "requires arrow >= 99.0.0")
  expect_identical(segment_balance(), before)
  stream <- native_arrow("arrow_stream_new")
  on.exit(native_arrow("arrow_stream_free", stream), add = TRUE)
  export <- get(".pst_geoparquet_export_reader", asNamespace("rPSTool"))
  open_reader <- get(".pst_geoparquet_open_reader", asNamespace("rPSTool"))
  expect_error(open_reader(1), "could not convert a Scanner to a RecordBatchReader")
  expect_error(export(list(), stream), "did not return a RecordBatchReader")
  expect_error(export(structure(list(), class = "RecordBatchReader"), stream), "export_to_c")
})

test_that("graphs from files follow the established segment-graph lifecycle", {
  skip_geoparquet()
  invisible(gc())
  before <- segment_balance()
  graph <- segment_graph(gp_fixture("lattice-binary"))
  expect_type(graph$ptr, "externalptr")
  expect_identical(segment_balance(), before + 1)
  # Serialisation yields a dead pointer, which analyses reject.
  copy <- unserialize(serialize(graph, NULL))
  expect_error(angular_integration(copy), "no longer live|live")
  # Explicit release is idempotent; the graph is then dead.
  native_segment("release", graph$ptr)
  native_segment("release", graph$ptr)
  expect_error(angular_integration(graph), "live")
  expect_identical(segment_balance(), before)
  # Result lifetime is independent of the file and of the graph.
  graph <- segment_graph(gp_fixture("lattice-binary"))
  result <- angular_integration(graph)
  rm(graph); invisible(gc())
  expect_identical(segment_balance(), before)
  expect_identical(nrow(result), 24L)
  # Repeated loads do not leak.
  for (i in 1:3) segment_graph(gp_fixture("lattice-large-binary"))
  invisible(gc())
  expect_identical(segment_balance(), before)
})

test_that("matrix and sf constructors and error messages are unchanged", {
  expect_error(segment_graph(matrix("a", 1, 4)), "numeric matrix")
  expect_error(segment_graph(NULL), "numeric matrix")
  expect_identical(segment_graph(rbind(c(0, 0, 3, 0), c(3, 0, 3, 3)))$n_segments, 2L)
})
