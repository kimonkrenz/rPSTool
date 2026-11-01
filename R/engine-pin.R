# The pinned PST engine release this package compiles (PST v3.3.2). Internal: recorded in result-file metadata and
# checked by the tests against inst/upstream/PST_VERSION.
.pst_engine_pin <- function() {
  c(
    pst_version = "3.3.2",
    pst_commit = "63df80a2cf3dd289be95ea3d91667c3490719b75"
  )
}
