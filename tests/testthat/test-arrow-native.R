# Native Arrow C boundary tests that need NO R arrow / pyarrow / Python / libarrow: the decoder
# in src/pst-geoparquet.cpp is driven by the internal synthetic stream producer in
# src/pst-arrow-test-stream.cpp. Malformed cases only lie about fields the decoder must reject
# BEFORE it dereferences a buffer (the producer is trusted for real buffer sizes).

# Decode one synthetic stream. Always frees the stream, asserts it is no longer live afterwards
# and that every schema, array and stream the producer created was released exactly once.
decode_case <- function(rows, expected = length(rows), column = "geometry", ...) {
  before <- stream_counters()
  stream <- synthetic_stream(rows, ...)
  result <- tryCatch(decode_stream(stream, expected, column), error = function(e) e)
  expect_false(native_arrow("arrow_stream_is_live", stream))
  native_arrow("arrow_stream_free", stream)
  delta <- counter_delta(before)
  expect_identical(unname(delta[c("schemas_made", "arrays_made", "streams_made")]),
                   unname(delta[c("schemas_released", "arrays_released", "streams_released")]))
  result
}
expect_decodes <- function(rows, .want, ...) {
  result <- decode_case(rows, ...)
  if (inherits(result, "error")) fail(conditionMessage(result))
  else expect_identical(result, unname(.want))
}
expect_rejects <- function(regex, rows, ...) {
  result <- decode_case(rows, ...)
  expect_s3_class(result, "error")
  expect_match(conditionMessage(result), regex)
}

with_address_limit <- function(limit, code) {
  native_arrow("arrow_set_addressable_limit", limit)
  on.exit(native_arrow("arrow_set_addressable_limit", NULL))
  force(code)
}

test_that("the stream external pointer has an exact tag and idempotent ownership", {
  for (bad in list(NULL, 1, "a", new("externalptr"), native_arrow("segment_graph_new_pointer"))) {
    expect_error(native_arrow("arrow_stream_is_live", bad), "Invalid rPSTool Arrow stream native pointer")
    expect_error(native_arrow("arrow_stream_release", bad), "Invalid rPSTool Arrow stream")
    expect_error(native_arrow("arrow_stream_free", bad), "Invalid rPSTool Arrow stream")
    expect_error(decode_stream(bad, 1), "Invalid rPSTool Arrow stream")
  }
  before <- stream_counters()
  stream <- native_arrow("arrow_stream_new")
  expect_type(stream, "externalptr")
  # A fresh (zeroed, unexported) stream is correctly tagged but not live.
  expect_false(native_arrow("arrow_stream_is_live", stream))
  expect_error(decode_stream(stream, 1), "not been exported or is already released")
  native_arrow("arrow_test_export", stream, list(rows = valid_rows(2)))
  expect_true(native_arrow("arrow_stream_is_live", stream))
  expect_error(native_arrow("arrow_test_export", stream, list(rows = valid_rows(2))), "already live")
  # Release is idempotent; the struct stays allocated until freed.
  expect_null(native_arrow("arrow_stream_release", stream))
  expect_false(native_arrow("arrow_stream_is_live", stream))
  expect_null(native_arrow("arrow_stream_release", stream))
  expect_null(native_arrow("arrow_stream_free", stream))
  expect_null(native_arrow("arrow_stream_free", stream))
  expect_false(native_arrow("arrow_stream_is_live", stream))
  expect_null(native_arrow("arrow_stream_release", stream))
  expect_error(decode_stream(stream, 1), "already been freed")
  expect_error(native_arrow("arrow_test_export", stream, list(rows = valid_rows(2))), "already been freed")
  delta <- counter_delta(before)
  expect_identical(delta[["streams_made"]], 1)
  expect_identical(delta[["streams_released"]], 1)
})

test_that("serialised and garbage-collected stream pointers are safe", {
  stream <- synthetic_stream(valid_rows(2))
  copy <- unserialize(serialize(stream, NULL))
  expect_false(native_arrow("arrow_stream_is_live", copy))
  expect_error(decode_stream(copy, 2), "already been freed")
  native_arrow("arrow_stream_free", stream)
  before <- stream_counters()
  local({
    unused <- synthetic_stream(valid_rows(3), plan = batch_plan(c(0, 3)))
    expect_true(native_arrow("arrow_stream_is_live", unused))
  })
  invisible(gc())  # the finaliser releases an exported-but-never-consumed stream exactly once
  delta <- counter_delta(before)
  expect_identical(delta[["streams_made"]], 1)
  expect_identical(delta[["streams_released"]], 1)
})

test_that("a valid stream decodes in source order for BINARY and LARGE_BINARY", {
  rows <- valid_rows(7, big = c(2, 5))  # mixed per-row byte order
  for (large in c(FALSE, TRUE)) {
    expect_decodes(rows, valid_matrix(7), large = large)
    expect_decodes(rows, valid_matrix(7), large = large,
                   plan = batch_plan(c(0, 3), c(3, 4)))
  }
  # Zero rows is a legal empty stream for the decoder (the R route rejects it earlier).
  expect_decodes(list(), matrix(numeric(), 0, 4), expected = 0)
})

test_that("the stream is released before the PST graph is built", {
  for (large in c(FALSE, TRUE)) {
    graph <- native_arrow("segment_graph_new_pointer")
    stream <- synthetic_stream(valid_rows(6), large = large)
    returned <- .Call(get("C_rpst_geoparquet_segment_graph", asNamespace("rPSTool")), graph, stream,
                      "geometry", 6)
    expect_identical(returned, graph)
    expect_false(native_arrow("arrow_stream_is_live", stream))
    expect_identical(.Call(get("C_rpst_segment_graph_info", asNamespace("rPSTool")), graph), 6L)
    native_arrow("arrow_stream_free", stream)
  }
})

test_that("a failed decode or build leaves the graph unpublished", {
  call <- function(graph, stream, rows) {
    .Call(get("C_rpst_geoparquet_segment_graph", asNamespace("rPSTool")), graph, stream, "geometry", rows)
  }
  info <- function(graph) .Call(get("C_rpst_segment_graph_info", asNamespace("rPSTool")), graph)
  before <- stream_counters()
  for (spec in list(list(rows = c(valid_rows(3), list(raw(2)))),
                    list(rows = valid_rows(4), flags = c(null_offsets = TRUE)),
                    list(rows = valid_rows(4), numeric = c(fail_next_at = 1)))) {
    graph <- native_arrow("segment_graph_new_pointer")
    stream <- do.call(synthetic_stream, spec)
    expect_error(call(graph, stream, 4), ".")
    expect_false(native_arrow("arrow_stream_is_live", stream))
    expect_error(info(graph), "no longer live")
    native_arrow("arrow_stream_free", stream)
  }
  # A build failure (extent overflow) after a successful decode also publishes nothing.
  huge <- list(wkb_line(-1e300, 0, 1e300, 1))
  graph <- native_arrow("segment_graph_new_pointer")
  stream <- synthetic_stream(huge)
  expect_error(call(graph, stream, 1), "overflows PST")
  expect_false(native_arrow("arrow_stream_is_live", stream))
  expect_error(info(graph), "no longer live")
  native_arrow("arrow_stream_free", stream)
  delta <- counter_delta(before)
  expect_identical(unname(delta[c("schemas_made", "arrays_made", "streams_made")]),
                   unname(delta[c("schemas_released", "arrays_released", "streams_released")]))
  # Wrong or already-built graph pointers are rejected before the stream is touched.
  stream <- synthetic_stream(valid_rows(2))
  built <- native_arrow("segment_graph_new_pointer")
  call(built, stream, 2)
  stream2 <- synthetic_stream(valid_rows(2))
  expect_error(call(built, stream2, 2), "not empty")
  expect_true(native_arrow("arrow_stream_is_live", stream2))
  expect_error(call(NULL, stream2, 2), "Invalid pst_segment_graph native pointer")
  expect_error(call(native_arrow("arrow_stream_new"), stream2, 2), "Invalid pst_segment_graph")
  expect_true(native_arrow("arrow_stream_is_live", stream2))
  native_arrow("arrow_stream_free", stream2)
  native_arrow("arrow_stream_free", stream)
})

test_that("the .Call argument contract is validated before native work", {
  stream <- synthetic_stream(valid_rows(2))
  for (column in list(NULL, 1, NA_character_, character(), c("a", "b"), "",
                      strrep("a", 2000))) {
    expect_error(native_arrow("arrow_decode_matrix", stream, column, 2), "column name")
  }
  for (rows in list(NULL, "2", NA_real_, Inf, -1, 1.5, c(1, 2), 2^60)) {
    expect_error(native_arrow("arrow_decode_matrix", stream, "geometry", rows), "row count")
  }
  expect_true(native_arrow("arrow_stream_is_live", stream))
  expect_error(.Call(get("C_rpst_geoparquet_segment_graph", asNamespace("rPSTool")),
                     native_arrow("segment_graph_new_pointer"), stream, "geometry", 0),
               "row count")
  expect_error(.Call(get("C_rpst_geoparquet_segment_graph", asNamespace("rPSTool")),
                     native_arrow("segment_graph_new_pointer"), stream, "geometry", 2^31),
               "Too many segments")
  native_arrow("arrow_stream_free", stream)
})

test_that("missing or failing stream callbacks are rejected and the stream released", {
  rows <- valid_rows(3)
  expect_rejects("not been exported or is already released", rows, flags = c(missing_release = TRUE))
  for (flag in c("missing_get_schema", "missing_get_next", "missing_get_last_error"))
    expect_rejects("required callback", rows, flags = structure(TRUE, names = flag))
  expect_rejects("get_schema failed \\(code 5\\): synthetic get_schema failure", rows,
                 numeric = c(fail_get_schema = 5))
  expect_rejects("get_schema failed \\(code 7\\)", rows, numeric = c(fail_get_schema = 7))
  expect_rejects("get_next failed \\(code 5\\): synthetic get_next failure", rows,
                 plan = batch_plan(c(0, 1), c(1, 1), c(2, 1)), numeric = c(fail_next_at = 2))
  expect_rejects("no description available", rows, numeric = c(fail_next_at = 1),
                 flags = c(null_last_error = TRUE))
})

test_that("the schema is validated field by field", {
  rows <- valid_rows(3)
  expect_rejects("struct \\(format \"\\+s\"\\), found \"\\+l\"", rows, top_format = "+l")
  expect_rejects("exactly one \\(geometry\\) column is required, found 0", rows, numeric = c(top_n_children = 0))
  expect_rejects("exactly one \\(geometry\\) column is required, found 2", rows, numeric = c(top_n_children = 2))
  expect_rejects("geometry child schema is missing", rows, flags = c(null_child_schema = TRUE))
  expect_rejects("column is named \"other\"", rows, child_name = "other")
  expect_rejects("format \"u\"", rows, child_format = "u")
  expect_rejects("dictionary-encoded geometry column", rows, flags = c(child_dictionary_schema = TRUE))
  expect_rejects("dictionary-encoded top-level", rows, flags = c(top_dictionary = TRUE))
  expect_rejects("geometry column must not have children", rows, numeric = c(child_n_children_schema = 1))
  expect_rejects("returned schema is already released", rows, flags = c(released_top_schema = TRUE))
  expect_rejects("child schema is already released", rows, flags = c(released_child_schema = TRUE))
  # A legal non-NULL children pointer with n_children == 0 is accepted, never dereferenced.
  expect_decodes(rows, valid_matrix(3), flags = c(unused_children_schema = TRUE))
  expect_decodes(rows, valid_matrix(3), large = TRUE, flags = c(unused_children_schema = TRUE))
})

test_that("array layouts are validated field by field", {
  rows <- valid_rows(5)
  with <- function(...) list(...)
  cases <- list(
    list("negative length or offset", numeric = c(parent_length = -1)),
    list("negative length or offset", numeric = c(parent_offset = -1)),
    list("exactly one \\(validity\\) buffer, found 2", numeric = c(parent_n_buffers = 2)),
    list("buffer array is missing", flags = c(null_parent_buffers = TRUE)),
    list("exactly one geometry child array is required, found 2", numeric = c(parent_n_children = 2)),
    list("exactly one geometry child array is required, found 0", numeric = c(parent_n_children = 0)),
    list("geometry child array is missing", flags = c(null_child = TRUE)),
    list("dictionary arrays are unsupported", flags = c(parent_dictionary = TRUE)),
    list("geometry array: negative length or offset", numeric = c(child_length = -1)),
    list("geometry array: negative length or offset", numeric = c(child_offset = -1)),
    list("exactly three buffers, found 2", numeric = c(child_n_buffers = 2)),
    list("exactly three buffers, found 4", numeric = c(child_n_buffers = 4)),
    list("buffer array is missing", flags = c(null_child_buffers = TRUE)),
    list("dictionary arrays are unsupported", flags = c(child_dictionary = TRUE)),
    list("must not have children", numeric = c(child_n_children = 1)),
    list("already released", flags = c(released_child_array = TRUE)))
  for (large in c(FALSE, TRUE)) for (case in cases) {
    args <- c(list(regex = case[[1]], rows = rows, large = large), case[-1])
    do.call(expect_rejects, args)
  }
  # A legal non-NULL children pointer with n_children == 0 is accepted and never dereferenced.
  expect_decodes(rows, valid_matrix(5), flags = c(unused_children_array = TRUE))
  expect_decodes(rows, valid_matrix(5), large = TRUE, flags = c(unused_children_array = TRUE))
  # Offsets buffer missing for a non-empty array.
  expect_rejects("offsets buffer is missing", rows, flags = c(null_offsets = TRUE))
})

test_that("parent and child offsets compose and child coverage is enforced", {
  # Pool rows 1-3 are garbage that must never be decoded; rows 4-9 are the valid ones.
  pool <- c(list(raw(3), as.raw(c(7, 7)), raw(0)), valid_rows(6))
  want <- function(rows) unname(valid_matrix(6))[rows, , drop = FALSE]
  for (large in c(FALSE, TRUE)) {
    # plan columns: first (0-based pool row), count, parent_offset, child_offset, tail
    expect_decodes(pool, want(1:3), expected = 3, large = large, plan = batch_plan(c(3, 3)))
    expect_decodes(pool, want(1:3), expected = 3, large = large, plan = batch_plan(c(3, 3, 3)))        # parent offset only
    expect_decodes(pool, want(1:3), expected = 3, large = large, plan = batch_plan(c(3, 3, 0, 3)))     # child offset only
    expect_decodes(pool, want(1:3), expected = 3, large = large, plan = batch_plan(c(3, 3, 2, 1)))     # both
    expect_decodes(pool, want(1:3), expected = 3, large = large, plan = batch_plan(c(3, 3, 2, 1, 2)))  # + tail
    # Source row order is preserved across batches, including zero-length ones.
    expect_decodes(pool, want(1:6), expected = 6, large = large,
                   plan = batch_plan(c(3, 2, 1, 2, 1), c(5, 0), c(5, 1, 0, 0, 3), c(6, 0, 2, 2, 0),
                                     c(6, 3, 1, 0, 0)))
    # Child logical coverage must reach parent.offset + parent.length.
    expect_rejects("does not cover the parent's logical range", pool, expected = 3, large = large,
                   plan = batch_plan(c(3, 3, 2, 1, 2)), numeric = c(child_length = 4))
    expect_decodes(pool, want(1:3), expected = 3, large = large,
                   plan = batch_plan(c(3, 3, 2, 1, 2)), numeric = c(child_length = 5))
    # Checked arithmetic on offsets and lengths (rejected before any buffer is read).
    expect_rejects("offset \\+ length overflows", pool, expected = 3, large = large,
                   plan = batch_plan(c(3, 3)), numeric = c(parent_offset = 2^62, parent_length = 2^62))
    expect_rejects("combined parent and child offset overflows", pool, expected = 3, large = large,
                   plan = batch_plan(c(3, 3)),
                   numeric = c(parent_offset = 2^61, parent_length = 2^61, child_length = 2^62,
                               child_offset = 1.5 * 2^62))
  }
})

test_that("row counts must match the file footer exactly", {
  rows <- valid_rows(5)
  expect_decodes(rows, valid_matrix(5), expected = 5)
  expect_rejects("produced 5 rows but the file reports 6", rows, expected = 6)
  expect_rejects("more rows than the file reports \\(4\\)", rows, expected = 4)
  expect_rejects("more rows than the file reports \\(4\\)", rows, expected = 4,
                 plan = batch_plan(c(0, 2), c(2, 3)))
})

test_that("validity bitmaps and null counts are enforced", {
  rows <- valid_rows(5)
  for (large in c(FALSE, TRUE)) {
    expect_rejects("Row 2: null geometry", rows, large = large, nulls_child = 2)
    expect_rejects("Row 4: null feature record", rows, large = large, nulls_parent = 4)
    # The earliest offending row is reported, whichever level it is at.
    expect_rejects("Row 1: null feature record", rows, large = large, nulls_parent = 1, nulls_child = 3)
    # null_count == -1 (unknown) needs a usable bitmap; a present, all-valid one is accepted.
    expect_decodes(rows, valid_matrix(5), large = large, numeric = c(child_null_count = -1),
                   flags = c(force_child_bitmap = TRUE))
    expect_decodes(rows, valid_matrix(5), large = large, numeric = c(parent_null_count = -1),
                   flags = c(force_parent_bitmap = TRUE))
    expect_rejects("requires a validity bitmap", rows, large = large, numeric = c(child_null_count = -1))
    expect_rejects("requires a validity bitmap", rows, large = large, numeric = c(parent_null_count = -1))
    # A positive null_count with no bitmap at all is malformed.
    expect_rejects("requires a validity bitmap", rows, large = large, nulls_child = 2,
                   flags = c(drop_bitmaps = TRUE))
    # Known counts that contradict the bitmap.
    expect_rejects("contradicts the validity bitmap", rows, large = large,
                   numeric = c(child_null_count = 2), flags = c(force_child_bitmap = TRUE))
    expect_rejects("contradicts the validity bitmap", rows, large = large,
                   numeric = c(parent_null_count = 1), flags = c(force_parent_bitmap = TRUE))
    expect_rejects("contradicts the validity bitmap", rows, large = large, nulls_child = 2,
                   numeric = c(child_null_count = 0))
    expect_rejects("null_count 9 is invalid for length", rows, large = large, numeric = c(child_null_count = 9))
    expect_rejects("null_count -2 is invalid", rows, large = large, numeric = c(parent_null_count = -2))
    # Sliced range: observed nulls may not exceed the known total ...
    expect_rejects("contradicts the validity bitmap", rows, large = large, nulls_child = c(2, 3), expected = 3,
                   plan = batch_plan(c(0, 3, 0, 0, 2)), numeric = c(child_null_count = 1))
    # ... but nulls outside the inspected slice are fine (decoded rows 1-3 are all valid).
    expect_decodes(rows, valid_matrix(5)[1:3, , drop = FALSE], large = large, nulls_child = 5, expected = 3,
                   plan = batch_plan(c(0, 3, 0, 0, 2)))
  }
})

test_that("offsets, data buffers and addressability fail closed", {
  rows <- valid_rows(5)
  for (large in c(FALSE, TRUE)) {
    expect_rejects("malformed Arrow offsets", rows, large = large,
                   numeric = c(offset_corrupt_mode = 1, offset_corrupt_row = 2))   # decreasing
    expect_rejects("Row 2: malformed Arrow offsets \\(start 41, end -1\\)", rows, large = large,
                   numeric = c(offset_corrupt_mode = 2, offset_corrupt_row = 3))   # negative start
    # A NULL data buffer for a non-empty value is malformed; a zero-length value with a NULL
    # data buffer reaches WKB validation and is a truncation error, never a crash.
    expect_rejects("NULL data buffer", rows, large = large, flags = c(null_data = TRUE))
    expect_rejects("Row 1: truncated WKB \\(0 bytes\\) before the geometry type", list(raw(0)), large = large)
    expect_rejects("Row 2: truncated WKB \\(0 bytes\\)", list(wkb_line(1, 2, 3, 4), raw(0)), large = large)
  }
  # LARGE_BINARY-only corruption is not accepted for ordinary BINARY test specs.
  expect_error(synthetic_stream(rows, large = FALSE, numeric = c(offset_corrupt_mode = 3, offset_corrupt_row = 1)),
               "require large = TRUE")
  expect_error(synthetic_stream(rows, large = FALSE, numeric = c(offset_corrupt_mode = 4, offset_corrupt_row = 1)),
               "require large = TRUE")
  # A huge LARGE_BINARY end offset is not a valid 41-byte value ...
  expect_rejects("Row 2: overlong WKB", rows, large = TRUE,
                 numeric = c(offset_corrupt_mode = 3, offset_corrupt_row = 2))
  # ... and with a simulated small address space it is not addressable at all.
  with_address_limit(2^31 - 1, {
    expect_rejects("Row 2: the WKB value end offset .* is not addressable", rows, large = TRUE,
                   numeric = c(offset_corrupt_mode = 3, offset_corrupt_row = 2))
    expect_rejects("Row [12]: the WKB value end offset .* is not addressable", rows, large = TRUE,
                   numeric = c(offset_corrupt_mode = 4, offset_corrupt_row = 2))
    expect_decodes(rows, valid_matrix(5), large = TRUE)
  })
  # A tiny limit also catches ordinary data (end offset 82 > limit 60) and the index k, k + 1.
  with_address_limit(60, {
    expect_rejects("Row 2: the WKB value end offset 82 is not addressable", rows)
    expect_rejects("offsets buffer index .* is not addressable", rows, large = TRUE,
                   plan = batch_plan(c(0, 5)), numeric = c(child_offset = 2^40, child_length = 5))
  })
  expect_rejects("offsets buffer index .* is not addressable", rows, large = TRUE,
                 numeric = c(child_offset = 2^62, child_length = 5))
  expect_decodes(rows, valid_matrix(5), large = TRUE)  # the limit was restored
})

test_that("the whole offsets element must lie within a non-aligned lowered limit", {
  # Index physical_end (n) is the last offset read; its bytes end at (n + 1) * width. With
  # limit 62: width 4 admits n <= 14, width 8 admits n <= 6 (an index-only check would admit one more).
  with_address_limit(62, {
    expect_rejects("Row 2: the WKB value end offset 82 is not addressable", valid_rows(14))
    expect_rejects("offsets buffer index 15 is not addressable", valid_rows(15))
    expect_rejects("Row 2: the WKB value end offset 82 is not addressable", valid_rows(6), large = TRUE)
    expect_rejects("offsets buffer index 7 is not addressable", valid_rows(7), large = TRUE)
  })
})

test_that("synthetic producer controls are bounded individually and fail closed", {
  rows <- valid_rows(3)
  bad <- function(regex, ...) expect_error(synthetic_stream(rows, ...), regex)
  # Allocation / count / loop controls are small.
  for (control in c("parent_n_buffers", "child_n_buffers", "parent_n_children", "child_n_children",
                    "top_n_children", "child_n_children_schema"))
    bad("whole number in \\[0, 8\\]", numeric = structure(9, names = control))
  bad("whole number in \\[1, 255\\]", numeric = c(fail_get_schema = 256))
  bad("whole number in \\[1, 255\\]", numeric = c(fail_get_schema = 2^40))  # would truncate as int
  bad("whole number in \\[1, 255\\]", numeric = c(fail_get_schema = 0))
  bad("whole number in", numeric = c(fail_next_at = 0))
  bad("whole number in", numeric = c(offset_corrupt_mode = 5))
  bad("whole number in", numeric = c(parent_n_buffers = 2^40))
  for (value in list(NA_real_, NaN, Inf, -Inf, 1.5))
    bad("whole number in", numeric = c(parent_length = value))
  bad("whole number in", numeric = c(parent_length = 1e19))
  # Intentional overflow controls keep their wide range.
  expect_s3_class(decode_case(rows, numeric = c(child_offset = 2^62), expected = 3), "error")
  # Index controls are checked against the plan and pool.
  bad("fail_next_at exceeds", numeric = c(fail_next_at = 2))
  bad("override_batch exceeds", numeric = c(override_batch = 2))
  bad("offset_corrupt_row exceeds", numeric = c(offset_corrupt_row = 4, offset_corrupt_mode = 1))
  bad("duplicate numeric control", numeric = c(fail_next_at = 1, fail_next_at = 1))
  bad("unknown numeric control", numeric = c(nonsense = 1))
  bad("unknown flag", flags = c(nonsense = TRUE))
  # Pool, plan and index vectors.
  bad("more rows than were supplied", plan = batch_plan(c(2, 3)))
  bad("plan first", plan = batch_plan(c(-1, 1)))
  bad("plan child_offset", plan = batch_plan(c(0, 1, 0, 2e5)))
  bad("plan tail", plan = batch_plan(c(0, 1, 0, 0, 2e5)))
  bad("invalid pool row index", nulls_child = 4L)
  bad("invalid pool row index", nulls_parent = 0L)
  bad("lists more rows than the pool holds", nulls_child = rep(1L, 4))
  expect_error(native_arrow("arrow_test_export", native_arrow("arrow_stream_new"), list(rows = list(1))),
               "raw vector")
  # A plan whose rows sum beyond the cap is rejected before anything is built.
  pool <- rep(list(raw(0)), 1e5)
  many <- do.call(batch_plan, rep(list(c(0, 1e5)), 101))
  expect_error(synthetic_stream(pool, plan = many), "accumulates too many rows")
})

test_that("the address-limit test hook is itself fail-closed", {
  set <- function(x) native_arrow("arrow_set_addressable_limit", x)
  platform <- set(NULL)
  expect_gt(platform, 2^31)
  for (bad in list(NA_real_, NaN, Inf, -1, 1.5, "a", 1L, c(1, 2), platform * 2))
    expect_error(set(bad), "address limit")
  expect_identical(set(100), 100)
  expect_identical(set(NULL), platform)
  expect_identical(set(platform), platform)  # can only lower or equal, never raise
  expect_identical(set(NULL), platform)
})

wkb_decode_cases <- function() {
  le <- function(...) wkb_line(...)
  int32 <- function(v, endian = "little") writeBin(as.integer(v), raw(), size = 4L, endian = endian)
  list(
    list("Row 1: truncated WKB \\(4 bytes\\) before the geometry type", as.raw(c(1, 2, 0, 0))),
    list("Row 1: truncated WKB \\(8 bytes\\) before the point count", le(0, 0, 1, 1)[1:8]),
    list("Row 1: truncated WKB \\(40 bytes; a two-point 2D LineString has 41\\)", le(0, 0, 1, 1)[1:40]),
    list("Row 1: overlong WKB \\(42 bytes", c(le(0, 0, 1, 1), as.raw(0))),
    list("invalid WKB byte-order marker 2", c(as.raw(2), le(0, 0, 1, 1)[-1])),
    list("empty LineString \\(zero points\\)", le(npoints = 0L, coords = numeric())),
    list("LineString has 1 points; exactly two are required", le(npoints = 1L, coords = c(0, 0))),
    list("LineString has 3 points; exactly two are required", le(npoints = 3L, coords = c(0, 0, 1, 1, 2, 2))),
    list("unsupported WKB geometry type 1;", le(type = 1L, npoints = 2L, coords = c(0, 0, 1, 1))[1:21]),
    list("unsupported WKB geometry type 3;", le(type = 3L, npoints = 1L, coords = c(0, 0, 1, 0, 1, 1, 0, 0))),
    list("unsupported WKB geometry type 5;", c(as.raw(1), int32(5), int32(1), le(0, 0, 1, 1))),
    list("Z LineString \\(ISO type 1002\\)", le(type = 1002L, npoints = 2L, coords = c(0, 0, 0, 1, 1, 1))),
    list("M LineString \\(ISO type 2002\\)", le(type = 2002L, npoints = 2L, coords = c(0, 0, 0, 1, 1, 1))),
    list("ZM LineString \\(ISO type 3002\\)", le(type = 3002L, npoints = 2L, coords = c(0, 0, 0, 0, 1, 1, 1, 1))),
    list("EWKB geometry flags .* 0x20000002", c(as.raw(1), int32(2 + 536870912), int32(4326), int32(2), le(0, 0, 1, 1)[-(1:9)])),
    list("EWKB geometry flags .* 0x20000002", c(as.raw(0), int32(2 + 536870912, "big"), int32(4326, "big"), int32(2, "big"),
                                                  writeBin(c(0, 0, 1, 1), raw(), endian = "big"))),
    list("non-finite coordinate", le(NaN, 0, 1, 1)),
    list("non-finite coordinate", le(0, Inf, 1, 1)),
    list("non-finite coordinate", le(0, 0, -Inf, 1)),
    list("non-finite coordinate", le(0, 0, 1, NA_real_)),
    list("non-finite coordinate", wkb_line(0, 0, NaN, 1, endian = "big")))
}

test_that("WKB rows are validated in stages", {
  # An ISO/EWKB type code is encoded as an unsigned 32-bit value: writeBin(as.integer(...))
  # cannot hold 2^31 + 2, so build those type codes bytewise.
  ewkb_z <- c(as.raw(1), as.raw(c(2, 0, 0, 128)), writeBin(2L, raw(), size = 4L), writeBin(c(0, 0, 0, 1, 1, 1), raw()))
  for (large in c(FALSE, TRUE)) {
    for (case in wkb_decode_cases())
      expect_rejects(case[[1]], list(case[[2]]), large = large)
    expect_rejects("EWKB geometry flags .* 0x80000002", list(ewkb_z), large = large)
    # Row number is one-based and names the first offending row.
    expect_rejects("Row 3: ", c(valid_rows(2), list(as.raw(c(1, 2, 0, 0)))), large = large)
  }
  # Both byte orders, mixed within one column.
  expect_decodes(list(wkb_line(1.5, -2.25, 3, 4, endian = "big"), wkb_line(-5, 6, 7.125, 8)),
                 rbind(c(1.5, -2.25, 3, 4), c(-5, 6, 7.125, 8)))
})
