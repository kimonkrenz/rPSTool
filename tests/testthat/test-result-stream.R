# docs/spatial-io/result-files.md: the rPSTool result owner and its Arrow C stream producer, tested with a synthetic
# producer and a scripted consumer so ownership, release order and failure paths are exercised independently of any
# PST analysis. The R `arrow` package is only needed by the tests that import the stream.

skip_result_arrow <- function() {
  skip_if_not_installed("arrow", "25.0.0")
}
settle <- function() { invisible(gc()); invisible(gc()) }

# Expected checksum of rows [from, to] of rs_default_table(): native checksum = length + sum of every child buffer.
default_cols <- function(rows = 10) {
  f <- rs_bits(rep_len(rs_special_bits, rows))
  list(f = f, d = rev_bytes(f), i = rep_len(c(0L, 1L, 2147483647L, 5L), rows))
}
batch_sum <- function(from, to, cols = default_cols()) {
  seg <- function(bytes) bytes[((from - 1) * 4 + 1):(to * 4)]
  (to - from + 1) + rs_sum_bytes(rs_id_bytes(from, to)) + rs_sum_bytes(seg(cols$f)) + rs_sum_bytes(seg(cols$d)) +
    rs_sum_bytes(rs_int_bytes(cols$i[from:to]))
}
child_sum <- function(bytes, from, to) (to - from + 1) + rs_sum_bytes(bytes[((from - 1) * 4 + 1):(to * 4)])

test_that("the arrow stream exports zero-copy batches and arrow reads them back bit-exactly", {
  skip_result_arrow()
  before <- rs_baseline()
  cols <- default_cols()
  stream <- rs_default_table(10, meta = c("rpst:a" = "1", "rpst:b" = "two"), batch = 4)
  reader <- arrow::RecordBatchReader$import_from_c(stream)
  expect_identical(reader$schema$names, c("id", "score", "depth", "count"))
  types <- vapply(reader$schema$fields, function(f) f$type$ToString(), "")
  expect_identical(unname(types), c("int32", "float", "float", "int32"))
  expect_false(any(vapply(reader$schema$fields, function(f) f$nullable, NA)))
  expect_identical(reader$schema$metadata[c("rpst:a", "rpst:b")], list("rpst:a" = "1", "rpst:b" = "two"))
  table <- reader$read_table()
  expect_identical(table$num_rows, 10L)
  expect_identical(table$num_columns, 4L)
  expect_identical(table$column(0)$num_chunks, 3L)                            # 4 + 4 + 2 rows
  expect_identical(as.vector(table$column(0)), 1:10)
  expect_identical(as.vector(table$column(3)), cols$i)                       # includes INT32_MAX
  expected <- function(raw) readBin(raw, "numeric", n = 10L, size = 4L)
  for (k in 1:2) {
    got <- as.vector(table$column(k))
    want <- expected(list(cols$f, cols$d)[[k]])
    expect_identical(writeBin(got, raw()), writeBin(want, raw()))            # every double byte, incl. -0 and NaN
  }
  file <- tempfile(fileext = ".parquet")
  arrow::write_parquet(table, file, compression = "zstd", chunk_size = 3L)
  back <- rs_read(file)
  expect_identical(writeBin(back$score, raw()), writeBin(expected(cols$f), raw()))
  expect_identical(back$count, cols$i)
  expect_identical(rs_pq(file)$GetSchema()$metadata[["rpst:b"]], "two")
  rm(table, reader); settle()
  rs_native("arrow_stream_free", stream)
  expect_true(rs_balanced(before))
})

test_that("batches may outlive the stream and be released in any order", {
  before <- rs_baseline()
  cols <- default_cols()
  stream <- rs_default_table(10, batch = 4)
  # get three batches, release the STREAM, then release the batches out of order, checksumming each first
  res <- rs_drive(stream, c(3, 0), c(3, 1), c(3, 2), c(3, 3), c(5, 0),
                  c(6, 2), c(6, 0), c(6, 1), c(4, 1), c(6, 0), c(4, 2), c(6, 0), c(4, 0), c(6, 0))
  expect_identical(res[1:4], c(0, 0, 0, 100))                                 # 3 batches then end of stream
  expect_identical(res[6:8], c(batch_sum(9, 10), batch_sum(1, 4), batch_sum(5, 8)))
  expect_identical(res[c(10, 12)], rep(batch_sum(1, 4), 2))                  # still valid after the others are gone
  expect_identical(res[14], -1)                                               # a released slot reports released
  expect_true(rs_balanced(before))
  # the stream struct itself was released exactly once
  expect_identical(rs_counters()[["streams_made"]] - before[["streams_made"]],
                   rs_counters()[["streams_released"]] - before[["streams_released"]])
  rs_native("arrow_stream_free", stream)                                      # repeated cleanup is a no-op
  rs_native("arrow_stream_free", stream)
})

test_that("a child array moved out of its batch stays valid after the batch and the stream are released", {
  before <- rs_baseline()
  cols <- default_cols()
  stream <- rs_default_table(10, batch = 4)
  res <- rs_drive(stream, c(3, 0), c(7, 1), c(4, 0), c(5, 0), c(9, 1), c(8, 1), c(9, 1))
  expect_identical(res[5], child_sum(cols$f, 1, 4))
  expect_identical(res[7], -1)
  expect_true(rs_balanced(before))
  rs_native("arrow_stream_free", stream)
})

test_that("schemas are independent of the stream and repeatable; the stream releases cleanly before any batch", {
  before <- rs_baseline()
  stream <- rs_default_table(10, batch = 4)
  res <- rs_drive(stream, c(1, 0), c(1, 1), c(5, 0), c(2, 0))                 # two schemas, release stream, release schema
  expect_identical(res[1:2], c(0, 0))
  expect_true(rs_balanced(before))
  stream2 <- rs_default_table(3, batch = 4)
  rs_native("arrow_stream_release", stream2)                                  # premature, before any consumer call
  rs_native("arrow_stream_release", stream2)
  expect_false(rs_native("arrow_stream_is_live", stream2))
  expect_true(rs_balanced(before))
})

test_that("end of stream is repeatable and an empty result has a schema but no batches", {
  before <- rs_baseline()
  stream <- rs_synth(0, floats = list(a = raw()), ints = list(n = integer()))
  res <- rs_drive(stream, c(1, 0), c(3, 0), c(3, 1), c(2, 0), c(5, 0))
  expect_identical(res[2:3], c(100, 100))
  expect_true(rs_balanced(before))
})

test_that("injected producer failures report errors, set last_error and leak nothing", {
  before <- rs_baseline()
  s1 <- rs_default_table(10, batch = 4, faults = c(5L, -1L, 0L, -1L))        # get_schema fails with 5
  res <- rs_drive(s1, c(1, 0), c(10, 0), c(5, 0))
  expect_identical(res[1], 5)
  expect_gt(res[2], 0)
  s2 <- rs_default_table(10, batch = 4, faults = c(0L, 1L, 71L, -1L))        # second batch fails with 71
  res <- rs_drive(s2, c(3, 0), c(3, 1), c(10, 0), c(4, 0), c(5, 0))
  expect_identical(res[1:2], c(0, 71))
  expect_gt(res[3], 0)
  s3 <- rs_default_table(10, batch = 4, faults = c(0L, -1L, 0L, 0L))         # first batch: allocation failure
  res <- rs_drive(s3, c(3, 0), c(10, 0), c(5, 0))
  expect_identical(res[1], 12)                                                # ENOMEM
  expect_gt(res[2], 0)
  settle()
  expect_true(rs_balanced(before))
})

test_that("a signed int32 column (native destination indices) exports unchanged, negatives and extremes included", {
  skip_result_arrow()
  before <- rs_baseline()
  idx <- c(-1L, 0L, 5L, -2147483647L, 2147483647L, -1L, 7L)            # NA_integer_ (INT_MIN) is not used: R reads it as NA
  stream <- rs_synth(7, signed = list(index = idx), batch = 3)
  reader <- arrow::RecordBatchReader$import_from_c(stream)
  types <- vapply(reader$schema$fields, function(f) f$type$ToString(), "")
  expect_identical(unname(types), c("int32", "int32"))
  expect_false(any(vapply(reader$schema$fields, function(f) f$nullable, NA)))
  table <- reader$read_table()
  expect_identical(table$num_rows, 7L)
  expect_identical(table$column(0)$num_chunks, 3L)                       # 3 + 3 + 1
  expect_identical(as.vector(table$column(1)), idx)
  rm(reader, table); settle()
  expect_true(rs_balanced(before))
})

test_that("arrow reports producer failures as errors without crashing or leaking", {
  skip_result_arrow()
  before <- rs_baseline()
  expect_error(arrow::RecordBatchReader$import_from_c(rs_default_table(10, faults = c(5L, -1L, 0L, -1L))))
  reader <- arrow::RecordBatchReader$import_from_c(rs_default_table(10, batch = 4, faults = c(0L, 1L, 71L, -1L)))
  expect_error(reader$read_table(), "injected get_next failure")
  rm(reader); settle()
  reader <- arrow::RecordBatchReader$import_from_c(rs_default_table(10, batch = 4, faults = c(0L, -1L, 0L, 1L)))
  expect_error(reader$read_table(), "out of memory")
  rm(reader); settle()
  # a stream that was never exported (or already released) cannot be imported
  empty <- rs_native("arrow_stream_new")
  expect_error(arrow::RecordBatchReader$import_from_c(empty))
  rs_native("arrow_stream_free", empty)
  expect_true(rs_balanced(before))
})

test_that("partial consumption and abandoned readers release the native result after garbage collection", {
  skip_result_arrow()
  before <- rs_baseline()
  reader <- arrow::RecordBatchReader$import_from_c(rs_default_table(10, batch = 4))
  first <- reader$read_next_batch()
  expect_identical(first$num_rows, 4L)
  rm(reader); settle()                                                        # stream gone, first batch still alive
  expect_identical(as.vector(first$column(0)), 1:4)
  expect_false(rs_balanced(before))                                           # the batch still holds the native arrays
  rm(first); settle()
  expect_true(rs_balanced(before))
  # a reader that is never consumed at all
  reader <- arrow::RecordBatchReader$import_from_c(rs_default_table(10, batch = 4))
  rm(reader); settle()
  expect_true(rs_balanced(before))
})

test_that("garbage collection between ownership transitions never frees a buffer in use", {
  skip_result_arrow()
  before <- rs_baseline()
  stream <- rs_default_table(10, batch = 4)
  settle()
  reader <- arrow::RecordBatchReader$import_from_c(stream); settle()
  b1 <- reader$read_next_batch(); settle()
  b2 <- reader$read_next_batch(); settle()
  rm(reader); settle()
  b3 <- NULL
  expect_identical(as.vector(b1$column(1)), readBin(default_cols()$f, "numeric", n = 10L, size = 4L)[1:4])
  expect_identical(as.vector(b2$column(0)), 5:8)
  rm(b1); settle()
  expect_identical(as.vector(b2$column(3)), default_cols()$i[5:8])
  rm(b2); settle()
  expect_true(rs_balanced(before))
})

test_that("malformed result specifications and unrepresentable tables are rejected before anything is exported", {
  before <- rs_baseline()
  f <- rs_bits(c(0, 1))
  fresh <- function() rs_native("arrow_stream_new")
  call <- function(...) {
    s <- fresh()
    on.exit(rs_native("arrow_stream_free", s))
    args <- modifyList(list(rows = 2, floats = list(a = f), ints = list(n = c(1L, 2L)), id = "id"), list(...))
    r <- tryCatch(do.call(rs_synth_into, c(list(stream = s), args)), error = function(e) conditionMessage(e))
    list(message = r, live = rs_native("arrow_stream_is_live", s))
  }
  rs_synth_into <- function(stream, rows, floats, ints, id, meta = character(), batch = 4, faults = c(0L, -1L, 0L, -1L)) {
    rs_native("result_test_export", stream, id, c(names(floats), names(ints)),
              c(rep(0L, length(floats)), rep(1L, length(ints))), c(unname(floats), unname(ints)),
              as.character(names(meta)), as.character(unname(meta)), as.double(rows), as.double(batch), as.integer(faults))
  }
  r <- call(floats = list(a = f), ints = list(a = c(1L, 2L)))                  # duplicate column name
  expect_match(r$message, "Duplicate result column name"); expect_false(r$live)
  r <- call(id = "a", floats = list(a = f))                                    # id collides with a column
  expect_match(r$message, "Duplicate result column name")
  r <- call(floats = list(a = rs_bits(1)))                                     # wrong float length
  expect_match(r$message, "4 \\* rows"); expect_false(r$live)
  r <- call(ints = list(n = 1L))                                               # wrong int length
  expect_match(r$message, "length rows"); expect_false(r$live)
  r <- call(ints = list(n = c(-1L, 2L)))                                       # negative = huge unsigned: never reinterpreted
  expect_match(r$message, "above the Arrow int32 range"); expect_false(r$live)
  r <- call(floats = list(a = f), ints = list(n = c(1L, 2L)), meta = stats::setNames("x", ""))
  expect_match(r$message, "metadata keys must be non-empty"); expect_false(r$live)
  r <- call(batch = 0); expect_match(r$message, "sizes"); expect_false(r$live)
  r <- call(rows = -1); expect_match(r$message, "sizes"); expect_false(r$live)
  # a live stream is never overwritten
  live <- rs_default_table(4)
  expect_error(rs_synth_into(live, 2, list(a = f), list(n = c(1L, 2L)), "id"), "already live")
  rs_native("arrow_stream_free", live)
  settle()
  expect_true(rs_balanced(before))
})

test_that("the consumer harness itself rejects malformed scripts", {
  stream <- rs_default_table(4)
  expect_error(rs_native("result_test_drive", stream, matrix(1:3, 1)), "two columns")
  expect_error(rs_native("result_test_drive", stream, rs_ops(c(99, 0))), "Unknown op")
  expect_error(rs_native("result_test_drive", stream, rs_ops(c(3, 800))), "Bad op")
  rs_native("arrow_stream_free", stream)
  expect_error(rs_native("result_test_drive", stream, rs_ops(c(3, 0))), "already been freed")
})

test_that("an R error while translating a string cannot strand a native result owner", {
  # Rf_translateCharUTF8() signals an R error for "bytes"-encoded strings. That must happen before any native
  # owner exists, so no table is created (let alone leaked) and the stream stays unused.
  bad <- "\xff"; Encoding(bad) <- "bytes"
  f <- rs_bits(c(0, 1))
  before <- rs_baseline()
  export <- function(id = "id", name = "a", meta = character()) {
    s <- rs_native("arrow_stream_new")
    on.exit(rs_native("arrow_stream_free", s))
    err <- tryCatch(
      rs_native("result_test_export", s, id, name, 0L, list(f), as.character(names(meta)), as.character(unname(meta)),
                2, 4, c(0L, -1L, 0L, -1L)),
      error = function(e) conditionMessage(e))
    list(error = err, live = rs_native("arrow_stream_is_live", s))
  }
  for (r in list(export(id = bad), export(name = bad), export(meta = c(k = bad)), export(meta = stats::setNames("v", bad)))) {
    expect_type(r$error, "character")
    expect_false(r$live)
  }
  after <- rs_counters()
  expect_identical(unname(after["tables_made"] - before["tables_made"]), 0)
  expect_true(rs_balanced(before))
})
