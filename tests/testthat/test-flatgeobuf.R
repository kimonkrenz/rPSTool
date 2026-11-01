# End-to-end FlatGeobuf path input for segment_graph() (docs/spatial-io/flatgeobuf-input.md). Needs only sf (CRS
# interpretation); skipped cleanly when sf is not installed. The fixtures in fixtures/flatgeobuf/ were written by
# GDAL; malformed variants are made by byte patching them in memory.

skip_flatgeobuf <- function() skip_if_not_installed("sf")
fgb_gdal_matrix <- function(name) {  # coordinates in GDAL's own read order (an independent oracle)
  x <- sf::st_read(fgb_fixture(name), quiet = TRUE)
  g <- sf::st_geometry(x)
  unname(t(vapply(g, function(l) c(l[1, ], l[2, ]), numeric(4))))
}

test_that("format identification is by content and covers FlatGeobuf, Parquet and the rest", {
  skip_flatgeobuf()
  sniff <- get(".pst_sniff_file_format", asNamespace("rPSTool"))
  as_file <- function(bytes) fgb_write(bytes)
  noindex <- fgb_bytes("lattice-utm-noindex")
  expect_identical(sniff(as_file(noindex)), "flatgeobuf")
  expect_identical(sniff(as_file(put(noindex, 7, as.raw(0)))), "flatgeobuf")   # patch byte 0
  expect_identical(sniff(as_file(put(noindex, 7, as.raw(1)))), "flatgeobuf")   # patch byte 1
  expect_identical(sniff(as_file(put(noindex, 7, as.raw(255)))), "flatgeobuf") # any patch byte
  expect_error(sniff(as_file(put(noindex, 3, as.raw(2)))), "major version 2")
  expect_error(sniff(as_file(put(noindex, 3, as.raw(4)))), "major version 4")
  expect_error(sniff(as_file(put(noindex, 0, as.raw(0)))), "Unsupported file format")
  expect_error(sniff(as_file(charToRaw(strrep("x", 64)))), "magic bytes 'PAR1'")
  expect_error(sniff(as_file(raw(0))), "too small")
  expect_error(sniff(as_file(noindex[1:7])), "too small")
  # Extension is never consulted, in either direction.
  copy <- tempfile(fileext = ".parquet"); writeBin(noindex, copy)
  expect_identical(sniff(copy), "flatgeobuf")
  parquet <- test_path("fixtures", "geoparquet", "lattice-binary.parquet")
  as_fgb <- tempfile(fileext = ".fgb"); file.copy(parquet, as_fgb)
  expect_identical(sniff(as_fgb), "geoparquet")
  # Parquet start with a bad footer stays a Parquet error; short files are too small.
  pq <- readBin(parquet, "raw", file.size(parquet))
  expect_error(sniff(as_file(put(pq, length(pq) - 1, as.raw(0)))), "Parquet magic bytes 'PAR1'")
  expect_error(sniff(as_file(pq[1:6])), "too small to be a Parquet file")
})

test_that("a valid FlatGeobuf whose last four bytes equal PAR1 is still FlatGeobuf", {
  skip_flatgeobuf()
  bytes <- fgb_bytes("lattice-utm-noindex")
  n <- length(bytes)
  # The last double of the last feature (y2) becomes 0x3152415000000000, a tiny finite number whose high bytes
  # spell "PAR1" at the very end of the file.
  bytes <- put(bytes, n - 8, as.raw(c(0, 0, 0, 0, 0x50, 0x41, 0x52, 0x31)))
  expect_identical(rawToChar(bytes[(n - 3):n]), "PAR1")
  path <- fgb_write(bytes)
  expect_identical(get(".pst_sniff_file_format", asNamespace("rPSTool"))(path), "flatgeobuf")
  expect_identical(segment_graph(path)$n_segments, 24L)
})

test_that("GDAL-written FlatGeobuf files give the same graph and results as matrix and sf input", {
  skip_flatgeobuf()
  expected <- gp_lattice()
  # No index: file order is the writer's order; the committed lattice CSV is the independent source.
  noindex <- segment_graph(fgb_fixture("lattice-utm-noindex"))
  expect_s3_class(noindex, "pst_segment_graph")
  expect_identical(noindex$type, "segment")
  expect_identical(noindex$n_segments, 24L)
  expect_identical(noindex$pst_version, "3.3.2")
  expect_null(noindex$coordinates)
  expect_identical(segment_analyses(noindex), segment_analyses(segment_graph(expected)))
  expect_equal(fgb_gdal_matrix("lattice-utm-noindex"), expected * 1, ignore_attr = TRUE)
  # Spatially indexed: file order is Hilbert order. The independent oracle is GDAL's own read order.
  indexed <- segment_graph(fgb_fixture("lattice-utm-indexed"))
  oracle <- fgb_gdal_matrix("lattice-utm-indexed")
  expect_false(isTRUE(all.equal(oracle, expected * 1, check.attributes = FALSE)))  # writer order is NOT preserved
  expect_identical(sort(apply(oracle, 1, paste, collapse = ",")), sort(apply(expected * 1, 1, paste, collapse = ",")))
  expect_identical(segment_analyses(indexed), segment_analyses(segment_graph(oracle)))
  # sf route on the same coordinates
  expect_identical(segment_analyses(segment_graph(sf::st_sf(geometry = gp_lines(oracle)))), segment_analyses(indexed))
  # Smaller files, indexed and not
  expect_identical(segment_graph(fgb_fixture("three-segments-noindex"))$n_segments, 3L)
  expect_identical(segment_graph(fgb_fixture("three-segments-indexed"))$n_segments, 3L)
})

test_that("FlatGeobuf, GeoParquet, matrix and sf graphs agree on the same coordinates", {
  skip_flatgeobuf()
  skip_if_not_installed("arrow", "25.0.0"); skip_if_not_installed("jsonlite")
  expected <- gp_lattice()
  fgb <- segment_graph(fgb_fixture("lattice-utm-noindex"))
  parquet <- segment_graph(test_path("fixtures", "geoparquet", "lattice-binary.parquet"))
  reference <- segment_analyses(segment_graph(expected))
  expect_identical(segment_analyses(fgb), reference)
  expect_identical(segment_analyses(parquet), reference)
  expect_identical(attr(fgb, "crs") == attr(parquet, "crs"), TRUE)
})

test_that("CRS: projected retained, geographic rejected, unknown maps to NA exactly as designed", {
  skip_flatgeobuf()
  projected <- segment_graph(fgb_fixture("lattice-utm-noindex"))
  expect_identical(attr(projected, "crs")$epsg, 32630L)
  expect_true(attr(projected, "crs") == sf::st_crs(32630))
  expect_true(attr(projected, "crs") == sf::st_crs(sf::st_read(fgb_fixture("lattice-utm-noindex"), quiet = TRUE)))
  expect_error(segment_graph(fgb_fixture("lattice-geographic-4326")), "Geographic longitude/latitude CRS is unsupported")
  # GDAL's unknown-CRS file (Crs table with the exact ENGCRS) and a file with no Crs table both mean "unknown".
  for (name in c("lattice-unknown-crs", "no-crs-table")) {
    g <- segment_graph(fgb_fixture(name))
    expect_true(is.na(attr(g, "crs")), info = name)
    expect_identical(attr(g, "crs"), sf::st_crs(NA), info = name)
  }
  # Near misses must NOT map to NA: same ENGCRS retained through sf (non-NA, not geographic, not rejected).
  unknown <- fgb_bytes("lattice-unknown-crs")
  find_last <- function(bytes, text) { m <- which(bytes == charToRaw(text)[1]); hit <- NA
    for (i in m) if (identical(bytes[i + seq_along(charToRaw(text)) - 1], charToRaw(text))) hit <- i
    hit - 1 }
  name_at <- find_last(unknown, "Undefined Cartesian SRS with unknown unit")        # last occurrence = Crs.name
  near_name <- put(unknown, name_at, charToRaw("u"))                                # name differs only in case
  axis_at <- which(vapply(seq_len(length(unknown) - 8), function(i) identical(unknown[i:(i + 7)], charToRaw('AXIS["x"')), logical(1)))[1] - 1
  near_wkt <- put(unknown, axis_at + 6, charToRaw("X"))                            # AXIS["X" instead of AXIS["x"
  for (near in list(near_name, near_wkt)) {
    g <- segment_graph(fgb_write(near))
    expect_false(is.na(attr(g, "crs")))
    expect_s3_class(attr(g, "crs"), "crs")
    expect_false(isTRUE(sf::st_is_longlat(attr(g, "crs"))))
  }
  expect_identical(segment_graph(fgb_write(near_name))$n_segments, 24L)
})

test_that("the CRS decision function covers every branch of the contract", {
  decide <- get(".pst_flatgeobuf_crs", asNamespace("rPSTool"))
  skip_flatgeobuf()
  name <- get(".pst_flatgeobuf_unknown_crs_name", asNamespace("rPSTool"))
  wkt <- get(".pst_flatgeobuf_unknown_crs_wkt", asNamespace("rPSTool"))
  unknown <- list(org = NULL, code = 0L, name = name, description = NULL, wkt = wkt, code_string = NULL)
  expect_true(is.na(decide(NULL)))
  expect_true(is.na(decide(unknown)))
  expect_true(is.na(decide(modifyList(unknown, list(org = "")))))                # empty org still matches
  expect_false(is.na(decide(modifyList(unknown, list(org = "EPSG", code = 32630L)))))   # authority present: not unknown
  expect_false(is.na(decide(modifyList(unknown, list(code = 7L, wkt = sf::st_as_text(sf::st_crs(32630)))))))
  expect_false(is.na(decide(modifyList(unknown, list(name = "Other local grid")))))  # near miss: name
  expect_false(is.na(decide(modifyList(unknown, list(description = "x")))))          # near miss: description
  expect_false(is.na(decide(modifyList(unknown, list(code_string = "x")))))          # near miss: code_string
  expect_false(is.na(decide(modifyList(unknown, list(wkt = sub("unknown", "metre", wkt, fixed = TRUE))))))
  # Custom engineering CRS with code 0 is interpreted, not mapped to NA.
  custom <- 'ENGCRS["My site grid",EDATUM["Site datum"],CS[Cartesian,2],AXIS["x",east],AXIS["y",north],LENGTHUNIT["metre",1]]'
  expect_false(is.na(decide(list(org = NULL, code = 0L, name = "My site grid", wkt = custom))))
  expect_equal(decide(list(org = "EPSG", code = 32630L, name = "x", wkt = NULL))$epsg, 32630L)
  expect_equal(decide(list(org = NULL, code = 0L, name = "UTM", wkt = sf::st_as_text(sf::st_crs(32630))))$epsg, 32630L)
  expect_error(decide(list(org = "EPSG", code = 4326L, name = "WGS 84", wkt = NULL)), "Geographic")
  expect_error(decide(list(org = NULL, code = 0L, name = "junk", wkt = "NOT A CRS")), "could not be interpreted")
  expect_error(decide(list(org = NULL, code = 0L, name = "empty", wkt = NULL)), "could not be interpreted")
})

test_that("geometry and header contract: every unsupported shape is rejected, naming the feature", {
  skip_flatgeobuf()
  cases <- list(
    "heterogeneous" = "Feature 2: geometry type 1 is not LineString",
    "linestring-empty" = "Feature 1: null or empty geometry",
    "null-geometry" = "Feature 2: null or empty geometry",
    "mixed-2pt-3pt" = "Feature 2: the LineString has 3 vertices",
    "multilinestring-one-part" = "geometry type 5",
    "point" = "geometry type 1",
    "polygon" = "geometry type 3",
    "linestring-z" = "Z, M or T dimensions",
    "linestring-m" = "Z, M or T dimensions",
    "linestring-zm" = "Z, M or T dimensions",
    "patched-first-x-nan" = "Feature 1: non-finite coordinate",
    "patched-first-x-inf" = "Feature 1: non-finite coordinate",
    "patched-first-x-neg-inf" = "Feature 1: non-finite coordinate",
    "zero" = "no features")
  for (name in names(cases)) expect_fgb_rejected(fgb_bytes(name), cases[[name]], info = name)
})

test_that("declared feature counts are honoured exactly or treated as unknown when zero", {
  skip_flatgeobuf()
  expect_fgb_rejected(fgb_bytes("patched-declared-30"), "holds 24 features but declares 30")
  expect_fgb_rejected(fgb_bytes("patched-declared-10"), "bytes after the 10 declared features")
  expect_identical(segment_graph(fgb_fixture("patched-declared-0-unknown"))$n_segments, 24L)
  base <- fgb_bytes("lattice-utm-noindex")
  at <- fgb_count_offset(base)
  expect_false(is.na(at))
  # Extreme declared counts are rejected against the file size before any allocation or index arithmetic.
  for (count in list(le64_max(), le64_2pow63(), le64_2pow53(), le64(2^32), le64(2^32 - 1), le64(1e9), le64(1e6), le64(100))) {
    expect_fgb_rejected(put(base, at, count), "more than the file can hold")
  }
  expect_fgb_rejected(put(base, at, le64(1)), "bytes after the 1 declared features")
  # Count near the largest the file could hold is a count mismatch (not an allocation or overflow problem).
  room <- length(base) - fgb_data_start(base)
  expect_fgb_rejected(put(base, at, le64(floor(room / 40))), "holds 24 features but declares")
  expect_fgb_rejected(put(base, at, le64(floor(room / 40) + 1)), "more than the file can hold")
})

test_that("index node sizes are validated and cannot run the index past the file", {
  skip_flatgeobuf()
  base <- fgb_bytes("lattice-utm-noindex")           # index_node_size serialised as 0 (differs from the default 16)
  at <- fgb_node_size_offset(base)
  expect_false(is.na(at))
  expect_identical(u16le(base, at), 0L)
  expect_fgb_rejected(put(base, at, as.raw(c(1, 0))), "index node size 1 is invalid")
  # An index claimed over the real records misparses them: rejected, never read past the end.
  for (size in list(c(2, 0), c(16, 0), c(255, 255))) expect_fgb_rejected(put(base, at, as.raw(size)), ".", info = paste(size, collapse = " "))
  # Index requested with an unknown (zero) count cannot be sized.
  with_zero <- put(put(base, fgb_count_offset(base), le64(0)), at, as.raw(c(16, 0)))
  expect_fgb_rejected(with_zero, "spatial index but gives no feature count")
  # Huge counts combined with every node size: always the count bound, never an overflow or allocation.
  for (size in list(c(2, 0), c(16, 0), c(255, 255)))
    expect_fgb_rejected(put(put(base, fgb_count_offset(base), le64_max()), at, as.raw(size)), "more than the file can hold")
})

test_that("oversized or lying size prefixes and truncated files fail before allocation", {
  skip_flatgeobuf()
  base <- fgb_bytes("lattice-utm-noindex")
  hs <- 8   # header size prefix offset
  expect_fgb_rejected(put(base, hs, le32(2^32 - 1)), "exceeds the 64 MiB limit")                  # 0xFFFFFFFF
  expect_fgb_rejected(put(base, hs, le32(64 * 2^20 + 1)), "exceeds the 64 MiB limit")             # just over the cap
  expect_fgb_rejected(put(base, hs, le32(length(base))), "exceeds the bytes remaining")             # within cap, beyond file
  expect_fgb_rejected(put(base, hs, le32(7)), "too small")                                          # impossible header size
  record <- fgb_data_start(base)                                                                   # first feature's size prefix
  expect_fgb_rejected(put(base, record, le32(2^32 - 1)), "Feature 1: the size prefix .* exceeds the 64 MiB limit")
  expect_fgb_rejected(put(base, record, le32(64 * 2^20 + 1)), "exceeds the 64 MiB limit")
  expect_fgb_rejected(put(base, record, le32(64 * 2^20)), "exceeds the bytes remaining")          # at the cap, beyond the file
  expect_fgb_rejected(put(base, record, le32(length(base))), "exceeds the bytes remaining")
  # A valid prefix over a short payload (truncated file) and cuts at every structural boundary.
  n <- length(base)
  for (cut in c(0, 4, 7, 8, 11, 12, 20, fgb_header_total(base) + 8 - 1, fgb_header_total(base) + 8, record + 2, record + 4, record + 30, n - 40, n - 1))
    expect_fgb_rejected(base[seq_len(cut)], ".", info = paste("cut at", cut))
  # Truncation inside the header with the (now lying) size prefix intact.
  expect_fgb_rejected(base[seq_len(8 + 4 + 100)], "exceeds the bytes remaining")
})

test_that("random corruption of any header or record byte never crashes and never publishes a graph", {
  skip_flatgeobuf()
  base <- fgb_bytes("three-segments-indexed")
  set.seed(20261014)
  invisible(gc())
  before <- segment_balance()
  accepted <- 0L
  for (i in 1:300) {
    mutated <- base
    pos <- sample.int(length(base), sample(1:3, 1))
    mutated[pos] <- as.raw(sample(0:255, length(pos), replace = TRUE))
    path <- fgb_write(mutated)
    result <- tryCatch(segment_graph(path), error = function(e) NULL)
    if (!is.null(result)) { accepted <- accepted + 1L; expect_identical(result$n_segments, 3L) }
  }
  invisible(gc())
  expect_identical(segment_balance(), before)  # only accepted loads were ever graphs, all collected
})

test_that("the decode step revalidates the inspected header and publishes nothing otherwise", {
  skip_flatgeobuf()
  ns <- asNamespace("rPSTool")
  inspect <- function(path) .Call(get("C_rpst_fgb_inspect", ns), path)
  decode <- function(ptr, path, header) .Call(get("C_rpst_fgb_segment_graph", ns), ptr, path, header)
  new_ptr <- function() .Call(get("C_rpst_segment_graph_new_pointer", ns))
  info <- inspect(fgb_fixture("lattice-utm-noindex"))
  expect_type(info$header, "raw")
  expect_identical(info$features_count, 24)
  expect_identical(info$index_node_size, 0L)
  expect_identical(info$geometry_type, 2L)
  expect_identical(info$crs$org, "EPSG")
  expect_identical(info$crs$code, 32630L)
  ptr <- new_ptr()
  expect_identical(decode(ptr, fgb_fixture("lattice-utm-noindex"), info$header), ptr)
  expect_identical(.Call(get("C_rpst_segment_graph_info", ns), ptr), 24L)
  # Same file, header from a different file / a one-byte-different CRS: refused, graph stays empty.
  base <- fgb_bytes("lattice-utm-noindex")
  crs_at <- which(vapply(seq_len(length(base) - 4), function(i) identical(base[i:(i + 3)], charToRaw("EPSG")), logical(1)))[1]
  swapped <- fgb_write(put(base, crs_at - 1 + 4, charToRaw("X")))   # EPSG -> EPSX-ish (same size, other bytes)
  for (other in list(fgb_fixture("lattice-unknown-crs"), fgb_fixture("lattice-geographic-4326"), swapped)) {
    ptr <- new_ptr()
    expect_error(decode(ptr, other, info$header), "changed between inspection and decoding|failed FlatBuffers verification|header")
    expect_error(.Call(get("C_rpst_segment_graph_info", ns), ptr), "no longer live")
  }
  # A header that is not the raw header, and a non-empty / foreign graph pointer, are rejected up front.
  expect_error(decode(new_ptr(), fgb_fixture("lattice-utm-noindex"), raw(3)), "raw header")
  expect_error(decode(new_ptr(), fgb_fixture("lattice-utm-noindex"), "x"), "raw header")
  built <- new_ptr(); decode(built, fgb_fixture("lattice-utm-noindex"), info$header)
  expect_error(decode(built, fgb_fixture("lattice-utm-noindex"), info$header), "not empty")
  expect_error(decode(NULL, fgb_fixture("lattice-utm-noindex"), info$header), "Invalid pst_segment_graph native pointer")
  for (bad in list(NULL, NA_character_, c("a", "b"), 1, "")) expect_error(inspect(bad), "path")
  expect_error(inspect(tempfile(fileext = ".fgb")), "Cannot open")
})

test_that("graphs from FlatGeobuf files follow the established segment-graph lifecycle", {
  skip_flatgeobuf()
  invisible(gc())
  before <- segment_balance()
  graph <- segment_graph(fgb_fixture("lattice-utm-noindex"))
  expect_type(graph$ptr, "externalptr")
  expect_identical(segment_balance(), before + 1)
  copy <- unserialize(serialize(graph, NULL))
  expect_error(angular_integration(copy), "live")
  native_segment("release", graph$ptr)
  native_segment("release", graph$ptr)
  expect_error(angular_integration(graph), "live")
  expect_identical(segment_balance(), before)
  graph <- segment_graph(fgb_fixture("lattice-utm-noindex"))
  result <- angular_integration(graph)
  rm(graph); invisible(gc())
  expect_identical(segment_balance(), before)
  expect_identical(nrow(result), 24L)
  for (i in 1:3) segment_graph(fgb_fixture("lattice-utm-indexed"))
  invisible(gc())
  expect_identical(segment_balance(), before)
})

test_that("path validation applies to FlatGeobuf input too", {
  skip_flatgeobuf()
  skip_on_os("windows")
  for (bad in list(NA_character_, "", character(), c("a", "b")))
    expect_error(segment_graph(bad), "single non-empty, non-missing character string")
  expect_error(segment_graph(tempfile(fileext = ".fgb")), "does not exist")
  expect_error(segment_graph(tempdir()), "directory")
  expect_error(segment_graph("/dev/null"), "not a regular local file")
  copy <- tempfile(); writeBin(fgb_bytes("lattice-utm-noindex"), copy)       # no extension needed
  expect_identical(segment_graph(copy)$n_segments, 24L)
  expect_identical(segment_graph(path.expand(fgb_fixture("lattice-utm-noindex")))$n_segments, 24L)
})

test_that("matrix and sf behaviour is unchanged and arrow is not needed for FlatGeobuf", {
  expect_error(segment_graph(matrix("a", 1, 4)), "numeric matrix")
  expect_error(segment_graph(NULL), "numeric matrix")
  expect_identical(segment_graph(rbind(c(0, 0, 3, 0), c(3, 0, 3, 3)))$n_segments, 2L)
  skip_flatgeobuf()
  # The FlatGeobuf route must not touch the optional GeoParquet packages.
  local_mocked_bindings(.pst_geoparquet_capabilities = function() stop("arrow must not be needed"), .package = "rPSTool")
  expect_identical(segment_graph(fgb_fixture("lattice-utm-noindex"))$n_segments, 24L)
})

test_that("little-endian test encoders are exact and refuse out-of-contract values", {
  expect_identical(le64_words(0, 2^31), as.raw(c(0, 0, 0, 0, 0, 0, 0, 0x80)))
  expect_identical(le64_words(2^32 - 1, 2^32 - 1), as.raw(rep(255L, 8)))
  expect_identical(le64_max(), as.raw(rep(255L, 8)))
  expect_identical(le64_2pow63(), as.raw(c(0, 0, 0, 0, 0, 0, 0, 0x80)))
  expect_identical(le64_2pow53(), as.raw(c(0, 0, 0, 0, 0, 0, 0x20, 0)))
  expect_identical(le64_words(1, 2), as.raw(c(1, 0, 0, 0, 2, 0, 0, 0)))
  expect_identical(le64(0), raw(8))
  expect_identical(le64(2^32), as.raw(c(0, 0, 0, 0, 1, 0, 0, 0)))
  expect_identical(le64(2^53 - 1), as.raw(c(rep(255L, 6), 0x1f, 0)))
  expect_identical(le32(2^32 - 1), as.raw(rep(255L, 4)))
  for (bad in list(-1, 2^32, 1.5, NA_real_, Inf, NaN, c(1, 2), "1", NULL)) {
    expect_error(le32(bad), "le32 value")
    expect_error(le64_words(bad, 0), "lo")
    expect_error(le64_words(0, bad), "hi")
  }
  for (bad in list(-1, 2^53, 2^63, 2^64, 1.5, NA_real_, Inf, c(1, 2)))
    expect_error(le64(bad), "le64 value")
  expect_no_warning(le64(2^53 - 1))
})
