#!/usr/bin/env Rscript
# Byte-pinned upstream files must survive a Git checkout with line-ending conversion (Windows default
# core.autocrlf=true) unchanged. Two checks, both runnable on any OS with git on the PATH:
#   1. Static: every tracked file of each byte-pinned tree has the `text` attribute unset (-text).
#   2. Dynamic: the working tree's .gitattributes and pinned files are committed into a scratch repository, cloned with
#      core.autocrlf=true, and every pinned file must have exactly the committed bytes. A control with no attribute
#      rules must change those bytes, proving the check is able to detect the conversion.
# Run from the repository root.
git <- Sys.which("git")
if (!nzchar(git)) stop("git is required to verify checkout line-ending protection")
run <- function(args, dir = ".", ...) {
  old <- setwd(dir); on.exit(setwd(old), add = TRUE)
  out <- suppressWarnings(system2(git, shQuote(args), stdout = TRUE, stderr = TRUE, ...))
  status <- attr(out, "status"); if (is.null(status)) status <- 0L
  if (status != 0L) stop("git ", paste(args, collapse = " "), " failed: ", paste(out, collapse = "\n"))
  out
}

# Trees whose bytes are hash-pinned (by FILES.md5, SHA256SUMS, PROVENANCE.md or an in-script digest).
pinned_roots <- c("src/vendor", "inst/upstream/build-inputs", "inst/upstream/flatbuffers",
                  "src/arrow-c-abi/arrow_c_abi.h", "inst/upstream/PST_LICENSE", "inst/upstream/PST_README.txt")
pinned <- run(c("-c", "core.quotepath=false", "ls-files", "--", pinned_roots))
if (any(grepl("[\"\\\\]", pinned))) stop("unexpected quoting in tracked pinned paths")
if (length(pinned) < 100L) stop("expected the byte-pinned trees to hold many tracked files, found ", length(pinned))
for (required in c("src/vendor/flatbuffers/include/flatbuffers/verifier.h", "inst/upstream/flatbuffers/include/flatbuffers/base.h",
                   "src/vendor/flatgeobuf/header_generated.h", "src/vendor/pstalgo/src/Raster.cpp",
                   "src/arrow-c-abi/arrow_c_abi.h"))
  if (!required %in% pinned) stop("byte-pinned file is not tracked: ", required)

# 1. Static: `text: unset` for every pinned file.
attrs <- run(c("check-attr", "text", "--", pinned))
unprotected <- pinned[!grepl(": text: unset$", attrs)]
if (length(unprotected)) stop("byte-pinned files without the -text attribute:\n  ", paste(unprotected, collapse = "\n  "))

# 2. Dynamic: simulate a conversion-prone checkout.
identity_config <- c("-c", "user.name=rPSTool", "-c", "user.email=rpst@example.invalid", "-c", "commit.gpgsign=false")
checkout_bytes <- function(attributes_text) {
  base <- tempfile("rpst-attr-"); dir.create(base)
  on.exit(unlink(base, recursive = TRUE), add = TRUE)
  origin <- file.path(base, "origin"); dir.create(origin)
  for (f in pinned) {
    dir.create(file.path(origin, dirname(f)), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(f, file.path(origin, f))) stop("cannot copy ", f)
  }
  writeBin(charToRaw(attributes_text), file.path(origin, ".gitattributes"))
  run(c("init", "-q"), origin)
  run(c("config", "core.autocrlf", "false"), origin)       # the origin stores the exact working-tree bytes
  run(c("add", "-A"), origin)
  run(c(identity_config, "commit", "-q", "-m", "pinned files"), origin)
  clone <- file.path(base, "clone")
  run(c("-c", "core.autocrlf=true", "-c", "core.eol=crlf", "clone", "-q", "--no-hardlinks",
        normalizePath(origin, winslash = "/"), normalizePath(clone, winslash = "/", mustWork = FALSE)))
  unname(tools::md5sum(file.path(clone, pinned)))
}
expected <- unname(tools::md5sum(pinned))
if (anyNA(expected)) stop("cannot hash the working-tree pinned files")
rules <- paste0(paste(readLines(".gitattributes", warn = FALSE), collapse = "\n"), "\n")
changed <- pinned[checkout_bytes(rules) != expected]
if (length(changed)) stop("a core.autocrlf=true checkout changes byte-pinned files:\n  ", paste(changed, collapse = "\n  "))
control <- pinned[checkout_bytes("") != expected]
if (!"inst/upstream/flatbuffers/include/flatbuffers/base.h" %in% control)
  stop("control failure: without attribute rules the converting checkout did not change the pinned FlatBuffers base.h, ",
       "so this test could not detect a missing protection")
message("Checkout protection verified: ", length(pinned), " byte-pinned files are -text and unchanged by a core.autocrlf=true clone ",
        "(control without rules changes ", length(control), ")")
