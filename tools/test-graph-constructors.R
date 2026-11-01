#!/usr/bin/env Rscript
# Offline build/provenance tests; no native allocation fault injection.
main <- function() {
  env <- new.env(parent = baseenv())
  sys.source("src/portability/harden-graph-constructors.R", envir = env)
  harden <- env$harden_graph_constructors
  read_bytes <- function(path) readBin(path, "raw", n = file.info(path)$size)
  source <- "inst/upstream/build-inputs/CreateGraph.cpp"
  original <- read_bytes(source)
  dir.create(".local", showWarnings = FALSE)
  tmp <- tempfile("graph-constructor-tests-", tmpdir = ".local")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  output <- file.path(tmp, ".rpst-build", "analyses", "CreateGraph.cpp")
  rejects <- function(expression, message) {
    error <- tryCatch({force(expression); NULL}, error = identity)
    stopifnot(inherits(error, "error"),
              grepl(message, conditionMessage(error), fixed = TRUE))
  }
  harden(source, output)
  expected <- read_bytes(output)
  stopifnot(identical(unname(tools::md5sum(output)), "6ae192582ff4bafaf7f03a189c7c10f5"),
            identical(read_bytes(source), original))
  harden(source, output)
  stopifnot(identical(read_bytes(output), expected))
  writeBin(charToRaw("corrupted build state"), output)
  harden(source, output)
  stopifnot(identical(read_bytes(output), expected))
  mutations <- list(
    charToRaw(sub("new CAxialGraph()", "new CAxialGraph", rawToChar(original), fixed = TRUE)),
    charToRaw(sub("new CSegmentGraph()", "new CSegmentGraph", rawToChar(original), fixed = TRUE)),
    c(original, charToRaw("\n\tauto graph = new CAxialGraph();\n")),
    charToRaw(sub("new CSegmentGroupGraph()", "new CSegmentGroupGraph", rawToChar(original), fixed = TRUE)),
    c(original, charToRaw("\n// unrelated source drift\n")),
    expected,
    c(original, charToRaw("\n")) # R source packaging adds this newline.
  )
  input <- file.path(tmp, "mutated.cpp")
  for (bytes in mutations) {
    writeBin(bytes, input)
    rejects(harden(input, output), "pinned original checksum")
    stopifnot(identical(read_bytes(output), expected))
  }
  unlink(output)
  rejects(harden(input, output), "pinned original checksum")
  stopifnot(!file.exists(output))
  rejects(harden(source, source), "Output must be")
  vendor <- "src/vendor/pstalgo/src/analyses/CreateGraph.cpp"
  rejects(harden(source, vendor), "Output must be")
  rejects(harden(source, file.path(tmp, "vendor", "pstalgo", ".rpst-build", "CreateGraph.cpp")),
          "Refusing to write into the vendor tree")
  stopifnot(!dir.exists(file.path(tmp, "vendor")),
            identical(read_bytes(vendor), original), identical(read_bytes(source), original))
  # Exercise the pattern and output checks independently of the input digest.
  missing_pattern <- harden
  body(missing_pattern) <- parse(text = sub(
    "auto graph = new CAxialGraph();", "auto missing = new CAxialGraph();",
    paste(deparse(body(harden)), collapse = "\n"), fixed = TRUE))[[1L]]
  rejects(missing_pattern(source, output), "Expected exactly one original pattern")
  wrong_output <- harden
  body(wrong_output) <- parse(text = sub(
    "6ae192582ff4bafaf7f03a189c7c10f5", "00000000000000000000000000000000",
    paste(deparse(body(harden)), collapse = "\n"), fixed = TRUE))[[1L]]
  rejects(wrong_output(source, output), "Generated copy or original source failed verification")
  stopifnot(!file.exists(output), !length(list.files(dirname(output))))
  # Resolve symlinks before making directories (Windows may forbid symlinks).
  if (.Platform$OS.type != "windows") {
    alias <- file.path(tmp, ".rpst-build")
    unlink(alias, recursive = TRUE)
    stopifnot(file.symlink(normalizePath("src/vendor/pstalgo"), alias))
    rejects(harden(source, file.path(alias, "forbidden-directory", "CreateGraph.cpp")),
            "Refusing to write into the vendor tree")
    stopifnot(!dir.exists("src/vendor/pstalgo/forbidden-directory"))
    unlink(alias)
  }
  # The verifier must reject a corrupt generated copy, rather than repairing it.
  copy <- "src/.rpst-build/analyses/CreateGraph.cpp"
  saved <- if (file.exists(copy)) read_bytes(copy) else NULL
  on.exit(if (is.null(saved)) unlink(copy) else writeBin(saved, copy), add = TRUE)
  harden(source, copy)
  sys.source("tools/verify-vendor.R", envir = new.env(parent = baseenv()))
  writeBin(c(expected, charToRaw("\n")), copy)
  rejects(sys.source("tools/verify-vendor.R", envir = new.env(parent = baseenv())),
          "Unexpected graph constructor build-copy changes")
  stopifnot(identical(read_bytes(copy), c(expected, charToRaw("\n"))))
  message("Graph constructor tests passed: exact output, regeneration, checksum/pattern/output rejection, no partial publication, vendor/path/symlink rejection and verifier drift rejection")
}
main()
