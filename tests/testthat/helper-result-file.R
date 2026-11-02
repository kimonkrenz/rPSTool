# Helpers for the result-persistence tests (docs/spatial-io/result-files.md). The Arrow producer/consumer harness is driven
# through registered native test entry points, independent of any PST analysis.
rs_native <- function(name, ...) .Call(get(paste0("C_rpst_", name), asNamespace("rPSTool")), ...)
rs_counters <- function() rs_native("result_counters")
# Counters after collecting garbage, so objects left over from earlier tests cannot be released inside a later test.
rs_baseline <- function() { invisible(gc()); invisible(gc()); rs_counters() }
rs_have_arrow <- function() {
  requireNamespace("arrow", quietly = TRUE) && utils::packageVersion("arrow") >= "25.0.0"
}

# float32 bit patterns -> raw vector (little-endian host assumed by the whole package)
rs_bits <- function(bits) {
  bits <- as.numeric(bits)  # exact for values below 2^32
  as.raw(as.vector(vapply(bits, function(b) (b %/% 256^(0:3)) %% 256, numeric(4))))
}
# Exceptional float32 values by exact bit pattern: +0, -0, 1, -1, +Inf, -Inf, quiet NaN, NaN with payload,
# negative NaN, smallest subnormal, largest subnormal, smallest normal, largest finite.
rs_special_bits <- c(0x00000000, 0x80000000, 0x3F800000, 0xBF800000, 0x7F800000, 0xFF800000, 0x7FC00000,
                     0x7FC00123, 0xFFC00001, 0x00000001, 0x007FFFFF, 0x00800000, 0x7F7FFFFF)

# The native checksum of a batch/child, replicated in R from the expected raw bytes.
rs_sum_bytes <- function(bytes) {
  if (!length(bytes)) return(0)
  sum(as.numeric(as.integer(bytes)) * ((seq_along(bytes) - 1) %% 7 + 1))
}
rs_id_bytes <- function(from, to) writeBin(as.integer(seq.int(from, to)), raw(), size = 4L)
rs_int_bytes <- function(x) writeBin(as.integer(x), raw(), size = 4L)

# Synthetic native result: float32 columns given as raw vectors, int32 columns as integers. Returns the stream pointer.
rs_synth <- function(rows, floats = list(), ints = list(), id = "id", meta = character(), batch = 4,
                     faults = c(0L, -1L, 0L, -1L), signed = list(), valid = list()) {
  stream <- rs_native("arrow_stream_new")
  names_ <- c(names(floats), names(ints), names(signed))
  kinds <- c(rep(0L, length(floats)), rep(1L, length(ints)), rep(2L, length(signed)))
  columns <- c(unname(floats), unname(ints), unname(signed))
  # `valid`: named list of logical vectors (TRUE = valid); naming a column makes it nullable with that validity.
  for (nm in names(valid)) attr(columns[[match(nm, names_)]], "valid") <- valid[[nm]]
  rs_native("result_test_export", stream, id, names_, kinds, columns, as.character(names(meta)), as.character(unname(meta)), as.double(rows),
            as.double(batch), as.integer(faults))
  stream
}
rs_default_table <- function(rows = 10, ...) {
  f <- rs_bits(rep_len(rs_special_bits, rows))
  i <- rep_len(c(0L, 1L, 2147483647L, 5L), rows)
  rs_synth(rows, floats = list(score = f, depth = rev_bytes(f)), ints = list(count = i), ...)
}
# reverse the float order of a raw float32 vector (keeps bit patterns intact)
rev_bytes <- function(x) {
  n <- length(x) %/% 4
  if (n < 2) return(x)
  idx <- as.vector(sapply(rev(seq_len(n)), function(k) (k - 1) * 4 + 1:4))
  x[idx]
}

# Scripted consumer ops
rs_ops <- function(...) {
  m <- do.call(rbind, list(...))
  storage.mode(m) <- "integer"
  m
}
rs_drive <- function(stream, ...) rs_native("result_test_drive", stream, rs_ops(...))
rs_balanced <- function(before, after = { invisible(gc()); invisible(gc()); rs_counters() }) {
  d <- after - before
  all(d[c("tables_made", "streams_made", "schemas_made", "batches_made", "children_made")] ==
        d[c("tables_freed", "streams_released", "schemas_released", "batches_released", "children_released")])
}

# Read a Parquet file as plain R vectors (no tibble/data.frame class differences).
rs_read <- function(path) {
  b <- as.data.frame(rs_read_parquet(path))   # owned, non-mapped handle: the file can be replaced straight away on Windows
  setNames(lapply(names(b), function(n) as.vector(b[[n]])), legacy_names(names(b)))   # legacy role names: see helper-legacy-schema.R
}
rs_bytes <- function(x) if (is.double(x)) writeBin(x, raw()) else writeBin(as.integer(x), raw())
# Exact comparison of a persisted table with the in-memory data frame: names, order, rows, R types, values and,
# for doubles, the 8 bytes of every value (so -0/+0 and NaN payloads cannot hide behind ordinary equality).
rs_expect_same <- function(persisted, memory) {
  testthat::expect_identical(names(persisted), names(memory))
  for (n in names(memory)) {
    testthat::expect_identical(typeof(persisted[[n]]), typeof(memory[[n]]), info = n)
    testthat::expect_identical(length(persisted[[n]]), length(memory[[n]]), info = n)
    testthat::expect_identical(rs_bytes(persisted[[n]]), rs_bytes(memory[[n]]), info = n)
  }
}
rs_leftovers <- function(dir) list.files(dir, pattern = "^\\.rpst-", all.files = TRUE)
rs_md5 <- function(path) unname(tools::md5sum(path))

# A small, lightly irregular 60-segment network for persistence tests (graph pointers are released by the tests).
rf_graph <- function() {
  i <- rep(1:5, times = 6); j <- rep(1:6, each = 5)
  x <- rbind(cbind(i * 10, j * 10, (i + 1) * 10, j * 10), cbind(j * 10, i * 10, j * 10, (i + 1) * 10))
  # a lightly irregular network: shift every third segment so angles differ
  x[seq(3, nrow(x), by = 3), c(2, 4)] <- x[seq(3, nrow(x), by = 3), c(2, 4)] + 3
  segment_graph(x)
}

# An export closure for .pst_write_result_file() backed by the synthetic producer (no PST analysis), optionally faulty.
rs_synthetic_export <- function(rows = 10, faults = c(0L, -1L, 0L, -1L)) {
  cols <- default_cols_for_export(rows)
  function(stream, batch_rows) {
    rs_native("result_test_export", stream, "id", c("score", "depth", "count"), c(0L, 0L, 1L),
              list(cols$f, cols$d, cols$i), character(), character(), as.double(rows), as.double(batch_rows),
              as.integer(faults))
  }
}
default_cols_for_export <- function(rows) {
  f <- rs_bits(rep_len(rs_special_bits, rows))
  list(f = f, d = rev_bytes(f), i = rep_len(c(0L, 1L, 2147483647L, 5L), rows))
}

# Lean variants for large sweeps: no testthat expectations, a description of the first difference ("" = identical).
rs_diff_tables <- function(persisted, memory) {
  if (!identical(names(persisted), names(memory))) return("column names or order differ")
  for (n in names(memory)) {
    if (!identical(typeof(persisted[[n]]), typeof(memory[[n]]))) return(paste(n, "type"))
    if (!identical(rs_bytes(persisted[[n]]), rs_bytes(memory[[n]]))) return(paste(n, "values"))
  }
  ""
}
# Same comparison as the in-memory reference tests: non-finite classes exactly, finite values to a tolerance.
rs_diff_reference <- function(actual, expected, tolerance = 3e-6) {
  expected <- as.double(unlist(expected))
  if (length(actual) != length(expected)) return("length")
  if (!identical(is.nan(actual), is.nan(expected)) || !identical(is.infinite(actual), is.infinite(expected))) return("non-finite classes")
  if (!identical(actual[!is.finite(expected)], expected[!is.finite(expected)])) return("non-finite values")
  f <- is.finite(expected)
  if (anyNA(actual[f])) return("null where a value is expected")
  if (any(abs(actual[f] - expected[f]) > tolerance * pmax(abs(expected[f]), 1e-300) + 0)) {
    ok <- isTRUE(all.equal(actual[f], expected[f], tolerance = tolerance))
    if (!ok) return("finite values")
  }
  ""
}

# An Arrow null read back by R: NA that is not NaN (a valid native NaN stays NaN).
rs_null_kind <- function(x) is.na(x) & !is.nan(x)

# Absolute path with forward slashes, as result descriptors report it (normalizePath() alone uses backslashes on Windows).
rs_norm <- function(x) normalizePath(x, winslash = "/", mustWork = FALSE)

# Remove one file or symbolic link WITHOUT following it (its target is untouched). R's unlink() cannot remove a symbolic link on
# Windows: for any reparse point it sends a junction-only FSCTL_DELETE_REPARSE_POINT (platform.c delReparsePoint), which fails with a
# reparse-tag mismatch. A failed removal is reported as a warning, never hidden.
rs_remove_entry <- function(path) {
  message <- rs_native("output_remove_entry", rPSTool:::.pst_native_path(path))
  if (nzchar(message)) warning("could not remove ", path, ": ", message, call. = FALSE)
  invisible(!nzchar(message))
}
# Create a symbolic link and arrange for exactly that link to be removed (natively) when the calling test ends.
rs_symlink <- function(target, link, envir = parent.frame()) {
  made <- suppressWarnings(isTRUE(file.symlink(target, link)))
  # registered with on.exit() in the test's own frame (run first, before the directory is unlinked); no extra package is needed
  if (made) do.call(base::on.exit, list(bquote(rs_remove_entry(.(link))), add = TRUE, after = FALSE), envir = envir)
  made
}
# Can this session create symbolic links in `dir`? Always on POSIX; on Windows only with the symbolic-link privilege or
# Developer Mode. The probe removes its own link natively, so it leaves nothing behind.
rs_can_symlink <- function(dir) {
  target <- file.path(dir, ".rpst-probe-target"); link <- file.path(dir, ".rpst-probe-link")
  file.create(target)
  made <- suppressWarnings(isTRUE(file.symlink(target, link)))
  if (made) rs_remove_entry(link)
  unlink(target)
  made
}
# Run `code` (assertions that need symbolic links) when links can be created. Where they cannot (Windows without Developer Mode or the
# symlink privilege) the assertions are not run, the test records that they were not, and it still holds one expectation; no
# testthat skip is raised, because the Windows skip policy admits only the approved inventory (tools/ci/windows-test-skips.tsv).
rs_if_symlinks <- function(dir, code) {
  if (rs_can_symlink(dir)) return(force(code))
  testthat::expect_identical(.Platform$OS.type, "windows")
  message("NOTE: symbolic-link assertions were not run (symbolic links cannot be created here).")
  invisible(NULL)
}
# Directory permissions that deny file creation can only be provoked portably on POSIX as a non-root user.
rs_can_deny_directory <- function() .Platform$OS.type == "unix" && !identical(Sys.info()[["user"]], "root")

# Parquet files for inspection are read through an owned handle that is closed before returning (Arrow never opens files with
# FILE_SHARE_DELETE, so on Windows a reader that is merely unreachable still blocks replacing or deleting the file until it is
# garbage collected). `rs_pq()` snapshots the facts tests need; `rs_read_parquet()` reads without memory mapping.
rs_pq <- function(path) {
  file <- arrow::ReadableFile$create(path)
  on.exit(file$close())
  reader <- arrow::ParquetFileReader$create(file, mmap = FALSE)
  schema <- reader$GetSchema()
  list(num_rows = reader$num_rows, num_row_groups = reader$num_row_groups, num_columns = reader$num_columns,
       GetSchema = function() schema)
}
rs_read_parquet <- function(file, ...) arrow::read_parquet(file, ..., mmap = FALSE)
