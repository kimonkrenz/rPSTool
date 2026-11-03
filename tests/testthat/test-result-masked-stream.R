# docs/spatial-io/result-files.md §7: nullable columns with Arrow validity bitmaps in the shared result stream. Driven by the
# synthetic producer and the scripted consumer, independent of any PST analysis. Valid native NaN/Inf must never be
# confused with null, nulls must be exact per batch (including batches that start mid-byte), and the bitmaps must follow
# the same shared ownership as the value arrays.

skip_masked_arrow <- function() skip_if_not_installed("arrow", "25.0.0")
float_bits <- function(rows, bits = 0x3F800000) rs_bits(rep_len(bits, rows))
bit_pattern <- function(rows, null_rows) { v <- rep(TRUE, rows); v[null_rows] <- FALSE; v }
batches_of <- function(rows, batch) { from <- seq(1L, rows, by = as.integer(batch)); list(from = from, to = pmin(from + batch - 1L, rows)) }

test_that("validity bits are LSB-first and null counts are exact per batch, for byte-aligned and unaligned batches", {
  skip_masked_arrow()
  before <- rs_baseline()
  rows <- 29L
  patterns <- list(single = bit_pattern(rows, 1L), boundaries = bit_pattern(rows, c(1, 8, 9, 16, 17, 24, 25, 29)),
                   none = bit_pattern(rows, integer()), all = bit_pattern(rows, seq_len(rows)))
  for (pattern in names(patterns)) {
    valid <- patterns[[pattern]]
    for (batch in c(1, 3, 7, 8, 9, 13, 29, 64)) {
      stream <- rs_synth(rows, floats = list(f = float_bits(rows)), ints = list(i = 1:rows), signed = list(s = -(1:rows)),
                         batch = batch, valid = list(f = valid, i = valid, s = valid))
      reader <- arrow::RecordBatchReader$import_from_c(stream)
      table <- reader$read_table()
      expect_identical(table$num_rows, rows)
      for (k in 1:3) {
        expected <- list(rep(1, rows), 1:rows, -(1:rows))[[k]]
        expected[!valid] <- NA
        expect_identical(as.vector(table$column(k)), expected, info = paste(pattern, batch, k))
        chunks <- batches_of(rows, batch)
        expect_identical(table$column(k)$num_chunks, length(chunks$from))
        for (j in seq_along(chunks$from)) {
          chunk <- table$column(k)$chunk(j - 1L)
          expect_identical(chunk$null_count, sum(!valid[chunks$from[j]:chunks$to[j]]), info = paste(pattern, batch, k, j))
        }
        rm(chunk)
      }
      # the id column and the schema: only the declared columns are nullable
      expect_identical(unname(vapply(reader$schema$fields, function(f) f$nullable, NA)), c(FALSE, TRUE, TRUE, TRUE))
      rm(reader, table)
    }
  }
  invisible(gc()); invisible(gc())
  expect_true(rs_balanced(before))
})

test_that("bitmap contents and presence follow the Arrow convention (set bit = valid; absent when a batch has no null)", {
  before <- rs_baseline()
  valid <- bit_pattern(24L, 2L)                       # one null, in the first batch only
  stream <- rs_synth(24, floats = list(f = float_bits(24)), batch = 8, valid = list(f = valid))
  res <- rs_drive(stream, c(3, 0), c(3, 1), c(3, 2), c(12, 1), c(12, 101), c(12, 201), c(15, 1), c(15, 101), c(15, 201), c(5, 0),
                  c(4, 0), c(4, 1), c(4, 2))
  expect_identical(res[4:6], c(1 * 2 + 1, 0, 0))     # null_count 1 with a bitmap; later batches: no nulls, no bitmap
  # checksum sum(valid(i) * (i + 1)) over the batch: row 2 (i = 2) is cleared in the first batch only
  expect_identical(res[7:9], c(sum(1:8) - 2, sum(1:8), sum(1:8)))
  # an all-null batch has an all-zero bitmap and null_count == length
  stream <- rs_synth(25, floats = list(f = float_bits(25)), batch = 8, valid = list(f = rep(FALSE, 25)))
  res <- rs_drive(stream, c(3, 0), c(3, 1), c(3, 2), c(3, 3), c(12, 1), c(12, 301), c(15, 1), c(15, 301), c(5, 0),
                  c(4, 0), c(4, 1), c(4, 2), c(4, 3))
  expect_identical(res[1:4], c(0, 0, 0, 0))
  expect_identical(res[5:8], c(8 * 2 + 1, 1 * 2 + 1, 0, 0))     # first batch: 8 nulls; last batch: 1 row, 1 null; checksums 0
  expect_true(rs_balanced(before))
})

test_that("a valid NaN or infinity is a value and a null is never a number, in both directions", {
  skip_masked_arrow()
  before <- rs_baseline()
  # NaN payloads, +/-Inf, -0, 1: first seven valid, the same seven patterns again as nulls
  special <- c(0x7FC00000, 0x7FC00123, 0xFFC00001, 0x7F800000, 0xFF800000, 0x80000000, 0x3F800000)
  valid <- rep(c(TRUE, FALSE), each = length(special))
  stream <- rs_synth(14, floats = list(f = rs_bits(rep(special, 2))), batch = 5, valid = list(f = valid))
  table <- arrow::RecordBatchReader$import_from_c(stream)$read_table()
  x <- as.vector(table$column(1))
  expect_identical(rs_null_kind(x), !valid)                                     # nulls are NA but not NaN
  expect_identical(is.nan(x), c(TRUE, TRUE, TRUE, rep(FALSE, 4), rep(FALSE, 7)))  # valid NaN stays NaN
  expect_identical(x[4:5], c(Inf, -Inf))
  expect_identical(rs_bytes(x[6]), rs_bytes(-0))
  # the bytes under a null are not contractual, but a valid slot is bit-exact
  expect_identical(rs_bytes(x[1:7][!is.nan(x[1:7])]), rs_bytes(c(Inf, -Inf, -0, 1)))
  rm(table); invisible(gc()); invisible(gc())
  expect_true(rs_balanced(before))
})

test_that("the int32 range check applies to valid slots only, so a native sentinel may sit under a null", {
  before <- rs_baseline()
  rows <- 6L
  sentinel <- c(5L, -1L, 7L, -1L, 2147483647L, 0L)       # -1L is UINT_MAX as a native unsigned count
  ok <- c(TRUE, FALSE, TRUE, FALSE, TRUE, TRUE)
  expect_no_error(stream <- rs_synth(rows, ints = list(n = sentinel), valid = list(n = ok)))
  rs_native("arrow_stream_free", stream)
  stream <- rs_native("arrow_stream_new")
  expect_error(rs_native("result_test_export", stream, "id", "n", 1L, list(structure(sentinel, valid = c(TRUE, TRUE, rep(FALSE, 4)))),
                         character(), character(), as.double(rows), 4, c(0L, -1L, 0L, -1L)),
               "above the Arrow int32 range")           # -1L is a valid slot here: still rejected, never reinterpreted
  expect_false(rs_native("arrow_stream_is_live", stream))
  rs_native("arrow_stream_free", stream)
  expect_error(rs_synth(rows, ints = list(n = sentinel)), "above the Arrow int32 range")   # not nullable: unchanged behaviour
  expect_true(rs_balanced(before))
})

test_that("all-null, all-valid, mixed and zero-row nullable columns have the declared schema and valid buffers", {
  skip_masked_arrow()
  before <- rs_baseline()
  rows <- 25L
  stream <- rs_synth(rows, floats = list(none = float_bits(rows), all = float_bits(rows)), ints = list(plain = 1:rows),
                     batch = 8, valid = list(none = rep(TRUE, rows), all = rep(FALSE, rows)))
  reader <- arrow::RecordBatchReader$import_from_c(stream)
  expect_identical(unname(vapply(reader$schema$fields, function(f) f$nullable, NA)), c(FALSE, TRUE, TRUE, FALSE))
  table <- reader$read_table()
  expect_identical(table$column(1)$null_count, 0L)           # all valid but declared nullable
  expect_identical(table$column(2)$null_count, rows)
  expect_identical(as.vector(table$column(2)), rep(NA_real_, rows))   # all-null keeps its numeric type
  expect_identical(typeof(as.vector(table$column(2))), "double")
  expect_identical(table$column(3)$null_count, 0L)
  rm(reader, table)
  # zero rows: no batch, but the nullable flag and a readable table
  stream <- rs_synth(0, floats = list(f = raw()), ints = list(i = integer()), valid = list(f = logical(), i = logical()))
  reader <- arrow::RecordBatchReader$import_from_c(stream)
  expect_identical(unname(vapply(reader$schema$fields, function(f) f$nullable, NA)), c(FALSE, TRUE, TRUE))
  expect_identical(reader$read_table()$num_rows, 0L)
  # a Parquet round trip keeps the schema (nullable) and the null pattern across row groups, even with no null at all
  # (arrow::write_parquet itself is portable; only rPSTool's file-publication primitives are POSIX-only)
  file <- tempfile(fileext = ".parquet"); on.exit(unlink(file), add = TRUE)
  valid <- bit_pattern(rows, c(3, 11, 12, 20))
  stream <- rs_synth(rows, floats = list(f = float_bits(rows)), ints = list(i = 1:rows), batch = 7, valid = list(f = valid, i = valid))
  table <- arrow::RecordBatchReader$import_from_c(stream)$read_table()
  arrow::write_parquet(table, file, compression = "zstd", chunk_size = 7L)
  reader <- rs_pq(file)
  expect_identical(reader$num_row_groups, 4L)
  back <- as.data.frame(rs_read_parquet(file))
  expect_identical(rs_null_kind(back$f), !valid); expect_identical(is.na(back$i), !valid)
  expect_true(all(vapply(reader$GetSchema()$fields[-1], function(f) f$nullable, NA)))
  expect_false(reader$GetSchema()$fields[[1]]$nullable)
  rm(table, reader); invisible(gc()); invisible(gc())
  expect_true(rs_balanced(before))
})

test_that("malformed validity specifications are rejected before any export", {
  before <- rs_baseline()
  stream <- rs_native("arrow_stream_new")
  call <- function(valid) rs_native("result_test_export", stream, "id", "f", 0L, list(structure(float_bits(4), valid = valid)),
                                    character(), character(), 4, 4, c(0L, -1L, 0L, -1L))
  expect_error(call(c(TRUE, FALSE, TRUE)), "logical vector of length rows")            # wrong length
  expect_error(call(c(TRUE, NA, TRUE, TRUE)), "must not contain NA")
  expect_error(call(c(1L, 0L, 1L, 1L)), "logical vector of length rows")               # not logical
  expect_false(rs_native("arrow_stream_is_live", stream))
  expect_no_error(call(c(TRUE, FALSE, TRUE, TRUE)))
  rs_native("arrow_stream_free", stream)
  expect_true(rs_balanced(before))
})

test_that("nullable children keep working in every release order and after the batch and stream are gone", {
  skip_masked_arrow()
  rows <- 20L
  valid <- bit_pattern(rows, c(2, 9, 10, 18))
  first_batch_sum <- sum((1:8) * valid[1:8])             # validity checksum of batch 0 (rows 1..8): row 2 is null
  release <- function(code) switch(as.character(code), "5" = c(5, 0), "4" = c(4, 0), "8" = c(8, 1))  # stream, batch, moved child
  for (order in list(c(5, 4, 8), c(4, 5, 8), c(8, 4, 5), c(4, 8, 5), c(5, 8, 4), c(8, 5, 4))) {
    before <- rs_baseline()
    stream <- rs_synth(rows, floats = list(f = float_bits(rows)), batch = 8, valid = list(f = valid))
    ops <- list(c(3, 0), c(7, 1))                         # batch 0 into slot 0; move its column (child 1) to children[1]
    for (code in order) ops <- c(ops, list(release(code), c(14, 1), c(13, 1)))   # release, then re-check the moved child
    res <- do.call(rs_drive, c(list(stream), ops))
    expect_identical(res[1:2], c(0, 0))
    child_released <- FALSE
    for (step in seq_along(order)) {
      at <- 2 + 3 * (step - 1)
      expect_identical(res[at + 1], 0)
      if (order[step] == 8) child_released <- TRUE
      # the moved child keeps its bitmap and null count until it is itself released, whatever happened to the rest
      expect_identical(res[at + 2:3], if (child_released) c(-1, -1) else c(first_batch_sum, 1 * 2 + 1),
                       info = paste(order, collapse = "-"))
    }
    expect_true(rs_balanced(before))
  }
})

test_that("a failure while building a nullable child's bitmap releases everything built so far", {
  skip_masked_arrow()
  before <- rs_baseline()
  valid <- bit_pattern(20L, 3L)
  stream <- rs_synth(20, floats = list(a = float_bits(20), b = float_bits(20)), batch = 8,
                     valid = list(a = valid, b = valid), faults = c(0L, -1L, 0L, -1L, 1L))   # second batch's bitmap fails
  reader <- arrow::RecordBatchReader$import_from_c(stream)
  expect_error(reader$read_table(), "out of memory")
  rm(reader); invisible(gc()); invisible(gc())
  expect_true(rs_balanced(before))
  # the scripted consumer sees ENOMEM (12), the error text, and unchanged progress
  stream <- rs_synth(20, floats = list(a = float_bits(20)), batch = 8, valid = list(a = valid), faults = c(0L, -1L, 0L, -1L, 0L))
  res <- rs_drive(stream, c(3, 0), c(10, 0), c(5, 0))
  expect_identical(res[1], 12)
  expect_gt(res[2], 0)
  expect_true(rs_balanced(before))
})

test_that("value buffers stay zero-copy next to nullable columns (batches are slices of the native arrays)", {
  skip_masked_arrow()
  rows <- 4096L
  valid <- bit_pattern(rows, seq(1, rows, by = 5))
  stream <- rs_synth(rows, floats = list(f = float_bits(rows)), ints = list(i = 1:rows), batch = 1024, valid = list(f = valid))
  table <- arrow::RecordBatchReader$import_from_c(stream)$read_table()
  expect_identical(table$column(1)$num_chunks, 4L)
  expect_identical(sum(vapply(0:3, function(j) table$column(1)$chunk(j)$null_count, 0L)), sum(!valid))
  expect_identical(as.vector(table$column(2)), 1:rows)              # the non-nullable int column is untouched
  expect_identical(table$column(2)$null_count, 0L)
})
