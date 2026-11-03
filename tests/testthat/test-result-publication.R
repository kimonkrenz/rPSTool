# docs/spatial-io/result-files.md §3: publication of result files. The Parquet file is written under a unique temporary name in the
# destination directory and published only when complete: a kernel-checked no-clobber step with overwrite = FALSE (POSIX
# link(2); Windows MoveFileExW without replacement), a single rename with overwrite = TRUE. These tests cover existing files, symlinks, inaccessible and invalid locations,
# write failures and interruptions (simulated at the arrow writer), races and cleanup. Failures that cannot be
# provoked safely (a full disk, a crash between rename and flush) are simulated or documented, never claimed.

skip_pub <- function() {
  skip_if_not_installed("arrow", "25.0.0")
}
pub_dir <- function() { d <- tempfile("rpst-pub-"); dir.create(d); d }
pub_call <- function(path, overwrite = FALSE, g = NULL) {
  angular_choice(g, output_file = path, overwrite = overwrite)
}
# Originals captured at load time, before any test installs a mock over the base binding.
real_getExportedValue <- base::getExportedValue
real_requireNamespace <- base::requireNamespace
real_getNamespaceVersion <- base::getNamespaceVersion
with_mocked_writer <- function(writer, code) {
  testthat::local_mocked_bindings(
    getExportedValue = function(ns, name) if (identical(ns, "arrow") && identical(name, "write_parquet")) writer
                                          else real_getExportedValue(ns, name),
    .package = "base")
  force(code)
}

test_that("overwrite = FALSE never replaces an existing file, symlink or dangling symlink", {
  skip_pub()
  dir <- pub_dir(); on.exit(unlink(dir, recursive = TRUE))
  g <- rf_graph(); on.exit(rs_native("segment_graph_release", g$ptr), add = TRUE)
  target <- file.path(dir, "out.parquet")
  writeLines("precious", target)
  before <- rs_md5(target)
  expect_error(pub_call(target, FALSE, g), "already exists")
  expect_identical(rs_md5(target), before)
  if (rs_can_symlink(dir)) {   # Windows: only with Developer Mode or the symlink privilege
    link <- file.path(dir, "link.parquet")
    expect_true(rs_symlink(target, link))
    expect_error(pub_call(link, FALSE, g), "already exists")
    dangling <- file.path(dir, "dangling.parquet")
    expect_true(rs_symlink(file.path(dir, "nowhere"), dangling))
    expect_error(pub_call(dangling, FALSE, g), "already exists")
    expect_false(file.exists(file.path(dir, "nowhere")))
  }
  expect_identical(rs_md5(target), before)
  expect_identical(rs_leftovers(dir), character())
})

test_that("a new file is published complete, with ordinary permissions and no leftovers", {
  skip_pub()
  dir <- pub_dir(); on.exit(unlink(dir, recursive = TRUE))
  g <- rf_graph(); on.exit(rs_native("segment_graph_release", g$ptr), add = TRUE)
  target <- file.path(dir, "new.parquet")
  r <- pub_call(target, FALSE, g)
  expect_identical(r$path, rs_norm(target))
  rs_expect_same(rs_read(target), angular_choice(g))
  reference <- file.path(dir, "plain"); file.create(reference)
  expect_identical(file.mode(target), file.mode(reference))      # 0666 & ~umask, not a private 0600 temp file
  expect_identical(rs_leftovers(dir), character())
  expect_identical(sort(list.files(dir)), c("new.parquet", "plain"))
})

test_that("overwrite = TRUE replaces atomically; the old file survives every failure", {
  skip_pub()
  dir <- pub_dir(); on.exit(unlink(dir, recursive = TRUE))
  g <- rf_graph(); on.exit(rs_native("segment_graph_release", g$ptr), add = TRUE)
  target <- file.path(dir, "out.parquet")
  angular_choice(g, output_file = target)
  old <- rs_md5(target)
  angular_choice(g, weigh_by_length = TRUE, normalization = "syntax", output_file = target, overwrite = TRUE)
  expect_false(identical(rs_md5(target), old))
  rs_expect_same(rs_read(target), angular_choice(g, weigh_by_length = TRUE, normalization = "syntax"))
  published <- rs_md5(target)
  # analysis failures stop before any file is created
  expect_error(angular_choice(g, weigh_by_length = NA, output_file = target, overwrite = TRUE), "TRUE or FALSE")
  expect_error(angular_choice(g, normalization = "bogus", output_file = target, overwrite = TRUE), "normalization")
  expect_error(angular_choice(g, radius = analysis_radius(axmeter = 1), output_file = target, overwrite = TRUE), "axmeter")
  expect_identical(rs_md5(target), published)
  expect_identical(rs_leftovers(dir), character())
})

test_that("a symlink destination is replaced by a regular file and its former target is untouched", {
  skip_pub()
  dir <- pub_dir(); on.exit(unlink(dir, recursive = TRUE))
  g <- rf_graph(); on.exit(rs_native("segment_graph_release", g$ptr), add = TRUE)
  rs_if_symlinks(dir, {
    real <- file.path(dir, "real"); writeLines("keep", real)
    link <- file.path(dir, "link.parquet"); rs_symlink(real, link)
    angular_choice(g, output_file = link, overwrite = TRUE)
    expect_identical(readLines(real), "keep")
    expect_identical(Sys.readlink(link), "")                       # the rename replaced the link itself
    rs_expect_same(rs_read(link), angular_choice(g))
  })
})

test_that("invalid or unusable destinations are rejected before anything is computed or created", {
  skip_pub()
  dir <- pub_dir(); on.exit({ Sys.chmod(dir, "755"); unlink(dir, recursive = TRUE) })
  g <- rf_graph(); on.exit(rs_native("segment_graph_release", g$ptr), add = TRUE)
  expect_error(pub_call(NA_character_, FALSE, g), "one non-empty")
  expect_error(pub_call("", FALSE, g), "one non-empty")
  expect_error(pub_call(c("a", "b"), FALSE, g), "one non-empty")
  expect_error(pub_call(1L, FALSE, g), "one non-empty")
  expect_error(pub_call(file.path(dir, "missing", "x.parquet"), FALSE, g), "directory of output_file does not exist")
  expect_error(pub_call(dir, TRUE, g), "is a directory")
  blocker <- file.path(dir, "afile"); writeLines("x", blocker)
  expect_error(pub_call(file.path(blocker, "x.parquet"), FALSE, g), "directory of output_file does not exist")
  if (rs_can_deny_directory()) {   # root bypasses directory permissions, and Sys.chmod() cannot deny a directory on Windows
    locked <- file.path(dir, "locked"); dir.create(locked); Sys.chmod(locked, "555")
    expect_error(pub_call(file.path(locked, "x.parquet"), FALSE, g), "Cannot create a temporary file")
    expect_identical(list.files(locked, all.files = TRUE, no.. = TRUE), character())
    Sys.chmod(locked, "755")
  }
  expect_identical(rs_leftovers(dir), character())
})

test_that("write failures and interruptions remove the temporary file and keep the old destination", {
  skip_pub()
  dir <- pub_dir(); on.exit(unlink(dir, recursive = TRUE))
  g <- rf_graph(); on.exit(rs_native("segment_graph_release", g$ptr), add = TRUE)
  target <- file.path(dir, "out.parquet")
  angular_choice(g, output_file = target)
  old <- rs_md5(target)
  before <- rs_baseline()
  # a disk-full style failure part-way through writing
  disk_full <- function(table, sink, ...) { writeBin(as.raw(1:100), sink); stop("No space left on device") }
  with_mocked_writer(disk_full, expect_error(pub_call(target, TRUE, g), "No space left on device"))
  expect_identical(rs_md5(target), old); expect_identical(rs_leftovers(dir), character())
  fresh <- file.path(dir, "fresh.parquet")
  with_mocked_writer(disk_full, expect_error(pub_call(fresh, FALSE, g), "No space left on device"))
  expect_false(file.exists(fresh)); expect_identical(rs_leftovers(dir), character())
  # a writer that "succeeds" but leaves nothing behind is not published
  with_mocked_writer(function(table, sink, ...) invisible(NULL), expect_error(pub_call(target, TRUE, g), "empty"))
  expect_identical(rs_md5(target), old); expect_identical(rs_leftovers(dir), character())
  # a writer that produces a table of the wrong size is not published
  # (simulated through the synthetic producer: 10 rows exported, 60 expected)
  expect_error(rPSTool:::.pst_write_result_file(target, TRUE, rs_synthetic_export(10), c("id", "score"), 60),
               "unexpected number of rows")
  expect_identical(rs_md5(target), old); expect_identical(rs_leftovers(dir), character())
  # an interrupt (user cancellation) while writing
  interrupted <- function(table, sink, ...) { writeBin(as.raw(1:10), sink)
    stop(structure(class = c("interrupt", "condition"), list(message = "", call = NULL))) }
  result <- with_mocked_writer(interrupted, tryCatch(pub_call(target, TRUE, g), interrupt = function(c) "interrupted"))
  expect_identical(result, "interrupted")
  expect_identical(rs_md5(target), old); expect_identical(rs_leftovers(dir), character())
  # the real writer failing while consuming the stream (producer error mid-stream, then at get_schema)
  expect_error(rPSTool:::.pst_write_result_file(target, TRUE, rs_synthetic_export(10, c(0L, 1L, 71L, -1L)), c("id"), 10,
                                             batch_rows = 4), "injected get_next failure")
  expect_error(rPSTool:::.pst_write_result_file(target, TRUE, rs_synthetic_export(10, c(5L, -1L, 0L, -1L)), c("id"), 10,
                                             batch_rows = 4))
  expect_error(rPSTool:::.pst_write_result_file(target, TRUE, rs_synthetic_export(10, c(0L, -1L, 0L, 0L)), c("id"), 10,
                                             batch_rows = 4), "out of memory")
  expect_identical(rs_md5(target), old); expect_identical(rs_leftovers(dir), character())
  invisible(gc()); invisible(gc())
  expect_true(rs_balanced(before))                      # every native result was released after the failures
  # and a clean run afterwards still works and publishes normally
  expect_s3_class(pub_call(target, TRUE, g), "pst_result_file")
  rs_expect_same(rs_read(target), angular_choice(g))
})

test_that("a file created by another process during the write is never replaced (overwrite = FALSE)", {
  skip_pub()
  dir <- pub_dir(); on.exit(unlink(dir, recursive = TRUE))
  g <- rf_graph(); on.exit(rs_native("segment_graph_release", g$ptr), add = TRUE)
  target <- file.path(dir, "race.parquet")
  racing <- function(table, sink, ...) {
    real_getExportedValue("arrow", "write_parquet")(table, sink, ...)   # a complete, valid temporary file
    writeLines("someone else's file", file.path(dir, "race.parquet"))     # ...then the "other process" wins the race
  }
  with_mocked_writer(racing, expect_error(pub_call(target, FALSE, g), "created by another process"))
  expect_identical(readLines(target), "someone else's file")
  expect_identical(rs_leftovers(dir), character())
  # with overwrite = TRUE the same race simply publishes our result (documented: last writer wins)
  with_mocked_writer(racing, pub_call(target, TRUE, g))
  rs_expect_same(rs_read(target), angular_choice(g))
})

test_that("the publication primitives behave as documented", {
  dir <- pub_dir(); on.exit(unlink(dir, recursive = TRUE))
  expect_true(rs_native("output_supported"))
  a <- file.path(dir, "a"); b <- file.path(dir, "b")
  expect_identical(rs_native("output_create_exclusive", a), "")
  expect_true(file.exists(a)); expect_identical(file.size(a), 0)
  expect_match(rs_native("output_create_exclusive", a), "exist", ignore.case = TRUE)   # never reuses a file
  if (rs_can_symlink(dir)) {
    dangling <- file.path(dir, "dangling"); rs_symlink(file.path(dir, "target"), dangling)
    expect_match(rs_native("output_create_exclusive", dangling), "exist", ignore.case = TRUE)
    expect_false(file.exists(file.path(dir, "target")))                                  # symlink never followed
    expect_true(rs_native("output_entry_exists", dangling))                              # ... and it is an existing entry
  }
  expect_false(rs_native("output_entry_exists", file.path(dir, "missing")))
  expect_true(rs_native("output_entry_exists", a))
  expect_match(rs_native("output_create_exclusive", file.path(dir, "no", "such", "x")), "No such file")
  writeLines("A", a); writeLines("B", b)
  expect_identical(rs_native("output_publish", a, b, FALSE), "exists")                   # no-clobber
  expect_identical(readLines(a), "A"); expect_identical(readLines(b), "B")
  expect_identical(rs_native("output_publish", a, b, TRUE), "")                          # replace
  expect_false(file.exists(a)); expect_identical(readLines(b), "A")
  c_ <- file.path(dir, "c")
  writeLines("C", c_)
  expect_identical(rs_native("output_publish", c_, file.path(dir, "d"), FALSE), "")      # link + unlink
  expect_false(file.exists(c_)); expect_identical(readLines(file.path(dir, "d")), "C")
  expect_true(nzchar(rs_native("output_publish", file.path(dir, "gone"), b, TRUE)))     # failure leaves target intact
  expect_identical(readLines(b), "A")
  expect_true(nzchar(rs_native("output_publish", file.path(dir, "gone"), file.path(dir, "e"), FALSE)))
  expect_error(rs_native("output_publish", "a", "b", NA), "TRUE or FALSE")
  expect_error(rs_native("output_publish", NA_character_, "b", TRUE), "non-empty")
  expect_error(rs_native("output_create_exclusive", c("a", "b")), "non-empty")
})

test_that("the strict arrow capability check runs before anything is computed", {
  skip_pub()
  dir <- pub_dir(); on.exit(unlink(dir, recursive = TRUE))
  g <- rf_graph(); on.exit(rs_native("segment_graph_release", g$ptr), add = TRUE)
  target <- file.path(dir, "x.parquet")
  no_arrow <- function(package, ..., quietly = FALSE) !identical(package, "arrow") && real_requireNamespace(package, ..., quietly = quietly)
  testthat::local_mocked_bindings(requireNamespace = no_arrow, .package = "base")
  expect_error(pub_call(target, FALSE, g), "requires the optional package 'arrow'")
  testthat::local_mocked_bindings(requireNamespace = real_requireNamespace, .package = "base")
  testthat::local_mocked_bindings(getNamespaceVersion = function(ns) c(version = "24.0.0"), .package = "base")
  expect_error(pub_call(target, FALSE, g), "arrow >= 25.0.0")
  testthat::local_mocked_bindings(getNamespaceVersion = real_getNamespaceVersion, .package = "base")
  real <- real_getExportedValue
  testthat::local_mocked_bindings(
    getExportedValue = function(ns, name) if (identical(name, "RecordBatchReader")) list() else real(ns, name), .package = "base")
  expect_error(pub_call(target, FALSE, g), "import_from_c")
  testthat::local_mocked_bindings(
    getExportedValue = function(ns, name) if (identical(name, "codec_is_available")) function(...) FALSE else real(ns, name),
    .package = "base")
  expect_error(pub_call(target, FALSE, g), "zstd")
  testthat::local_mocked_bindings(getExportedValue = real, .package = "base")
  expect_false(file.exists(target)); expect_identical(rs_leftovers(dir), character())
  expect_s3_class(pub_call(target, FALSE, g), "pst_result_file")   # and everything is fine again once restored
})

test_that("file identity is an exact pair of strings; hard links and path spellings share it, other files do not", {
  dir <- pub_dir(); on.exit(unlink(dir, recursive = TRUE))
  a <- file.path(dir, "a.bin"); b <- file.path(dir, "b.bin"); writeLines("x", a); writeLines("x", b)
  id <- function(p) rs_native("file_identity", enc2native(p))
  expect_type(id(a), "character"); expect_length(id(a), 2L)
  expect_true(all(nzchar(id(a)))); expect_false(anyNA(id(a)))
  expect_identical(id(a), id(a))
  expect_false(identical(id(a), id(b)))                                  # same content, different file
  expect_identical(id(a), id(file.path(dir, ".", "a.bin")))            # another spelling of the same path
  expect_identical(id(file.path(dir, "missing")), c(NA_character_, NA_character_))
  hard <- file.path(dir, "hard.bin")
  if (suppressWarnings(file.link(a, hard))) expect_identical(id(hard), id(a))
  if (.Platform$OS.type == "windows") {                                    # the file system is case-insensitive
    expect_identical(id(toupper(a)), id(a))
    expect_identical(id(gsub("/", "\\", a, fixed = TRUE)), id(a))
  }
})

test_that("result files are written to and replaced in directories and files with non-ASCII names", {
  skip_pub()
  skip_if(!l10n_info()[["UTF-8"]] && .Platform$OS.type != "windows", "needs a UTF-8 session")
  base <- pub_dir(); on.exit(unlink(base, recursive = TRUE))
  dir <- file.path(base, "r\u00e9sum\u00e9-\u0416-\u65e5\u672c"); dir.create(dir)
  g <- rf_graph(); on.exit(rs_native("segment_graph_release", g$ptr), add = TRUE)
  target <- file.path(dir, "r\u00e9sultat-\u0416.parquet")
  r <- pub_call(target, FALSE, g)
  expect_true(file.exists(target)); expect_identical(r$rows, 60L)
  rs_expect_same(rs_read(target), angular_choice(g))
  expect_error(pub_call(target, FALSE, g), "already exists")
  old <- rs_md5(target)
  angular_choice(g, weigh_by_length = TRUE, normalization = "syntax", output_file = target, overwrite = TRUE)
  expect_false(identical(rs_md5(target), old))
  expect_identical(rs_leftovers(dir), character())
})

test_that("a destination held open by another reader is either replaced or left intact, never damaged", {
  skip_pub()
  dir <- pub_dir(); on.exit(unlink(dir, recursive = TRUE))
  g <- rf_graph(); on.exit(rs_native("segment_graph_release", g$ptr), add = TRUE)
  target <- file.path(dir, "held.parquet")
  angular_choice(g, output_file = target)
  old <- rs_md5(target)
  con <- file(target, "rb")                     # R opens it for reading; Windows denies deleting/renaming it meanwhile
  outcome <- tryCatch({ angular_choice(g, weigh_by_length = TRUE, output_file = target, overwrite = TRUE); "replaced" },
                      error = function(e) "refused")
  close(con)
  if (outcome == "refused") expect_identical(rs_md5(target), old)       # failed safely: the old file is intact
  expect_identical(rs_leftovers(dir), character())
  angular_choice(g, weigh_by_length = TRUE, output_file = target, overwrite = TRUE)   # and works once the reader is gone
  expect_false(identical(rs_md5(target), old))
})
