# Arrow opens local files without FILE_SHARE_DELETE and ParquetFileReader$create(<path>) / read_parquet(<path>) memory-map the file
# and keep it open until garbage collection, so on Windows an unreachable reader still blocks replacing or deleting the file. These
# structural checks (they need no arrow) keep every reader in rPSTool and in its tests on an owned, explicitly closed handle:
# `.pst_parquet_source_open()` in the package, `rs_pq()` / `rs_read_parquet()` in the tests.

test_that("no test opens a Parquet file through Arrow's path-based, memory-mapping readers", {
  files <- list.files(test_path(), pattern = "^(test|helper)-.*[.]R$", full.names = TRUE)
  skip_if(!length(files), "test sources are not available")
  offenders <- character()
  for (path in files) {
    lines <- readLines(path, warn = FALSE)
    lines <- lines[!grepl("^\\s*#", lines)]
    bad <- grepl("arrow::ParquetFileReader\\$create\\(", lines) |
      (grepl("arrow::read_parquet\\(", lines) & !grepl("mmap\\s*=\\s*FALSE", lines))
    if (basename(path) == "helper-result-file.R")   # the two helpers that wrap them are the only allowed sites
      bad <- bad & !grepl("ParquetFileReader\\$create\\(file, mmap = FALSE\\)|read_parquet\\(file, \\.\\.\\., mmap = FALSE\\)", lines)
    if (any(bad)) offenders <- c(offenders, paste0(basename(path), ":", which(!grepl("^\\s*#", readLines(path, warn = FALSE)))[bad]))
  }
  expect_identical(offenders, character())
})

test_that("the package opens Parquet files only through its owned, non-mapped reader helper", {
  ns <- asNamespace("rPSTool")
  sites <- character()
  for (name in ls(ns, all.names = TRUE)) {
    f <- get(name, ns)
    if (!is.function(f)) next
    text <- paste(deparse(f), collapse = "\n")
    if (grepl("\"ParquetFileReader\"\\)\\$create\\(|ParquetFileReader\\$create\\(|read_parquet\\(", text)) sites <- c(sites, name)
  }
  expect_identical(sites, ".pst_parquet_source_open")
  text <- paste(deparse(get(".pst_parquet_source_open", ns)), collapse = "\n")
  expect_match(text, "mmap = FALSE", fixed = TRUE)
  expect_match(text, "ReadableFile", fixed = TRUE)
})
