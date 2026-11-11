#!/usr/bin/env Rscript
# Negative and idempotence tests of the SphereTree radius-query transformer (patch 0012).
main <- function() {
  env <- new.env(parent = baseenv())
  sys.source("src/portability/fix-sphere-tree.R", envir = env)
  transform <- env$fix_sphere_tree
  bytes <- function(path) readBin(path, "raw", n = file.info(path)$size)
  dir.create(".local", showWarnings = FALSE)
  tmp <- tempfile("sphere-tree-", tmpdir = ".local")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE))
  rejects <- function(expr, pattern) {
    e <- tryCatch({ force(expr); NULL }, error = identity)
    stopifnot(inherits(e, "error"), grepl(pattern, conditionMessage(e), fixed = TRUE))
  }
  input <- "inst/upstream/build-inputs/SphereTree.cpp"
  original <- bytes(input)
  output <- file.path(tmp, ".rpst-build", "SphereTree.cpp")
  transform(input, output); expected <- bytes(output)
  transform(input, output); stopifnot(identical(bytes(output), expected))                    # idempotent
  writeBin(charToRaw("corrupt output"), output)
  transform(input, output); stopifnot(identical(bytes(output), expected))                    # a corrupt copy is replaced
  mutant <- file.path(tmp, "SphereTree.cpp")
  for (mutation in list(c(original, charToRaw("\n// drift")), expected,
                        charToRaw(sub("return nResult;", "return 0;", rawToChar(original), fixed = TRUE)))) {
    writeBin(mutation, mutant)
    rejects(transform(mutant, output), "pinned original checksum")
    stopifnot(identical(bytes(output), expected))
  }
  rejects(transform(input, input), "Output must be")
  rejects(transform(input, file.path(tmp, "vendor", "pstalgo", ".rpst-build", "SphereTree.cpp")), "Refusing to write into the vendor tree")
  stopifnot(!dir.exists(file.path(tmp, "vendor")), identical(bytes(input), original))
  message("SphereTree transformer negative tests passed")
}
main()
