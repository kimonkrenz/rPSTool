#!/usr/bin/env Rscript
# Offline fail-closed tests, executed on every CI operating system.
env <- new.env(parent = baseenv())
sys.source("src/portability/qualify-isovist.R", envir = env)
qualify <- env$qualify_isovist
read_bytes <- function(path) readBin(path, "raw", n = file.info(path)$size)
original_file <- "src/vendor/pstalgo/src/analyses/CalculateIsovists.cpp"
original <- read_bytes(original_file)
dir.create(".local", showWarnings = FALSE)
tmp <- tempfile("portability-tests-", tmpdir = ".local")
dir.create(tmp)
run_tests <- function() {
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  output <- file.path(tmp, ".rpst-build", "analyses", "CalculateIsovists.cpp")
  qualify(original_file, output)
  expected <- charToRaw(sub("\t\tResult& Result() { return m_Result; }",
                           "\t\tCIsovistContext::Result& Result() { return m_Result; }",
                           rawToChar(original), fixed = TRUE))
  stopifnot(identical(read_bytes(output), expected))
  qualify(original_file, output)
  stopifnot(identical(read_bytes(output), expected))
  writeBin(charToRaw("tampered generated state"), output)
  qualify(original_file, output)
  stopifnot(identical(read_bytes(output), expected))
  mutations <- list(
    charToRaw(sub("Result& Result()", "Result& Renamed()", rawToChar(original), fixed = TRUE)),
    c(original, charToRaw("\n// unrelated upstream change\n")),
    c(original, charToRaw("\n\t\tResult& Result() { return m_Result; }\n")),
    expected
  )
  for (mutated in mutations) {
    input <- file.path(tmp, "mutated.cpp")
    writeBin(mutated, input)
    error <- tryCatch({qualify(input, output); NULL}, error = identity)
    stopifnot(inherits(error, "error"),
              grepl("pinned original checksum", conditionMessage(error), fixed = TRUE),
              identical(read_bytes(output), expected))
  }
  # A failing first-generation request must leave no output file behind.
  unlink(output)
  error <- tryCatch({qualify(input, output); NULL}, error = identity)
  stopifnot(inherits(error, "error"), !file.exists(output))
  # A valid source cannot redirect output into the original vendor tree.
  error <- tryCatch({qualify(original_file, original_file); NULL}, error = identity)
  stopifnot(inherits(error, "error"), identical(read_bytes(original_file), original))
  qualify(original_file, output)
  stopifnot(identical(read_bytes(output), expected))
  message("Portability tests passed: exact change, repeat/regeneration, corrupted-output regeneration, four checksum rejections, no partial output, vendor write rejection")
}
run_tests()
