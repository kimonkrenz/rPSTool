#!/usr/bin/env Rscript
# Fail-closed / mutation tests for tools/verify-flatgeobuf-vendor.R. Run from the repository root.
env <- new.env()
sys.source("tools/verify-flatgeobuf-vendor.R", envir = env)
stopifnot(length(env$fgb_vendor_violations(".")) == 0L)

rejected <- function(mutate, pattern, what) {
  tmp <- tempfile("fgbvendor-"); dir.create(file.path(tmp, "src"), recursive = TRUE)
  dir.create(file.path(tmp, "inst", "upstream"), recursive = TRUE)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  file.copy(c("src/vendor", "src/portability", "src/Makevars", "src/Makevars.win"), file.path(tmp, "src"), recursive = TRUE)
  file.copy("inst/upstream/flatbuffers", file.path(tmp, "inst", "upstream"), recursive = TRUE)
  mutate(tmp)
  v <- env$fgb_vendor_violations(tmp)
  if (!any(grepl(pattern, v))) stop("mutation not rejected (", what, "): ", paste(v, collapse = " | "))
}
p <- function(...) file.path(...)
fb <- "src/vendor/flatbuffers/include/flatbuffers/verifier.h"
rejected(function(r) { f <- p(r, fb); x <- readBin(f, "raw", file.size(f)); x[100] <- as.raw(bitwXor(as.integer(x[100]), 1L)); writeBin(x, f) },
         "verifier.h differs", "flipped bit in a FlatBuffers header")
rejected(function(r) unlink(p(r, fb)), "missing file", "deleted header")
rejected(function(r) writeLines("x", p(r, "src/vendor/flatbuffers/include/flatbuffers/extra.h")), "unexpected file", "stray header")
rejected(function(r) writeLines("x", p(r, "src/vendor/flatgeobuf/notes.txt")), "unexpected file", "stray file in flatgeobuf")
rejected(function(r) { f <- p(r, "src/vendor/flatgeobuf/header_generated.h"); writeLines(c(readLines(f), "// edit"), f) },
         "header_generated.h differs", "edited generated header")
rejected(function(r) { f <- p(r, "src/vendor/flatgeobuf/feature.fbs"); writeLines(sub("xy:", "xyz:", readLines(f), fixed = TRUE), f) },
         "feature.fbs differs", "edited schema")
rejected(function(r) unlink(p(r, "src/vendor/flatgeobuf/LICENSE")), "missing file LICENSE", "deleted licence")
rejected(function(r) writeLines("MIT", p(r, "src/vendor/flatbuffers/LICENSE")), "LICENSE differs|not the Apache", "replaced licence")
rejected(function(r) { f <- p(r, "src/vendor/flatgeobuf/SHA256SUMS"); writeLines(sub("^[0-9a-f]{8}", "00000000", readLines(f)), f) },
         "SHA256SUMS does not match", "tampered manifest")
rejected(function(r) writeLines("no pins here", p(r, "src/vendor/flatbuffers/PROVENANCE.md")), "does not record", "provenance without pins")
rejected(function(r) unlink(p(r, "src/vendor/flatbuffers/PROVENANCE.md")), "missing file PROVENANCE.md", "deleted provenance")
rejected(function(r) unlink(p(r, "src/vendor/flatgeobuf"), recursive = TRUE), "directory is missing", "deleted directory")

# --- canonical upstream base.h, the exact generated copy, and the build recipes ---------------------------
ub <- "inst/upstream/flatbuffers/include/flatbuffers/base.h"
sc <- "src/portability/strip-flatbuffers-diagnostics.R"
edit <- function(rel, from, to, all = FALSE) function(r) {
  f <- p(r, rel); x <- readLines(f, warn = FALSE)
  if (!any(grepl(from, x, fixed = TRUE))) stop("test bug: pattern not found in ", rel, ": ", from)
  x <- if (all) gsub(from, to, x, fixed = TRUE) else { i <- grep(from, x, fixed = TRUE)[1]; x[i] <- sub(from, to, x[i], fixed = TRUE); x }
  writeLines(x, f)
}
rejected(function(r) { f <- p(r, ub); x <- readBin(f, "raw", file.size(f)); x[200] <- as.raw(bitwXor(as.integer(x[200]), 1L)); writeBin(x, f) },
         "upstream base.h differs", "flipped bit in the canonical upstream base.h")
rejected(function(r) unlink(p(r, ub)), "missing canonical upstream", "deleted upstream base.h")
rejected(function(r) writeLines("x", p(r, "inst/upstream/flatbuffers/extra.h")), "unexpected file", "stray upstream file")
rejected(function(r) writeLines("0", p(r, "inst/upstream/flatbuffers/SHA256SUMS")), "upstream SHA256SUMS", "tampered upstream manifest")
rejected(function(r) file.copy(p(r, ub), p(r, "src/vendor/flatbuffers/include/flatbuffers/base.h")), "exists under src/vendor", "pristine base.h back under src/")
rejected(function(r) { f <- p(r, ub); writeLines(c(readLines(f), "// drift"), f) }, "differs from the pinned|generation failed", "drifted upstream (generator refuses)")
# transformation script alterations: each must be caught by the verifier
rejected(edit(sc, "Wstringop-overflow", "Wstringop-overflow2", all = TRUE), "generation failed", "changed first targeted block")
rejected(edit(sc, "-Wfloat-equal", "-Wfloat-equal2", all = TRUE), "generation failed", "changed second targeted block")
rejected(edit(sc, "e32af5dbf0f85239ad10c7009d0cb1c9", "00000000000000000000000000000000"),
         "generation failed|accepted a drifted", "altered upstream hash in the generator")
rejected(edit(sc, "9bbb6aef93eeab1d6f6617c880fc667e", "00000000000000000000000000000000"), "generation failed", "altered expected generated hash")

# Generator-level mutations: re-pin the generator to a MUTATED input (so the hash gate passes) and prove the
# block-count / residual-pragma / exactness checks still refuse it.
gen_script <- paste(readLines(sc, warn = FALSE), collapse = "\n")
# Temporary inputs are written as explicit LF bytes: writeLines() would emit CRLF on Windows, and the generator (correctly)
# matches the pinned LF blocks exactly, so a CRLF fixture would be refused before reaching the intended mutation.
write_lf <- function(lines, path) writeBin(charToRaw(paste0(paste(lines, collapse = "\n"), "\n")), path)
gen_refuses <- function(mutated_lines, pattern, what) {
  dir <- tempfile("fgbmut-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  input <- file.path(dir, "base.h"); write_lf(mutated_lines, input)
  if (any(readBin(input, "raw", file.size(input)) == as.raw(13L))) stop("temporary fixture contains CR bytes (", what, ")")
  src <- sub("e32af5dbf0f85239ad10c7009d0cb1c9", unname(tools::md5sum(input)), gen_script, fixed = TRUE)
  e <- new.env(parent = globalenv()); eval(parse(text = src), e)
  msg <- tryCatch({ e$strip_flatbuffers_diagnostics(input, file.path(dir, ".rpst-build", "base.h")); "ACCEPTED" },
                  error = function(err) conditionMessage(err))
  if (!grepl(pattern, msg)) stop("generator did not refuse (", what, "): ", msg)
}
up <- readLines(ub, warn = FALSE)
# The fixture writer must reproduce the pinned upstream bytes exactly, on every platform (no CR, same final newline).
faithful <- tempfile("fgbfaithful-"); write_lf(up, faithful)
if (!identical(unname(tools::md5sum(faithful)), unname(tools::md5sum(ub)))) stop("LF fixture writer does not reproduce the pinned base.h bytes")
unlink(faithful)
first <- which(up == "  #pragma GCC diagnostic ignored \"-Wstringop-overflow\"")
stopifnot(length(first) == 1L)
block1 <- (first - 2):(first + 1)
gen_refuses(up[-block1], "Expected exactly one upstream diagnostic block", "missing block")
gen_refuses(append(up, up[block1], after = first + 1), "Expected exactly one upstream diagnostic block", "duplicated block")
gen_refuses(append(up, "#pragma clang diagnostic ignored \"-Wfoo\"", after = 10L), "diagnostic pragma remains", "additional clang suppression")
gen_refuses(append(up, "  #pragma GCC diagnostic ignored \"-Wbar\"", after = 10L), "diagnostic pragma remains", "additional GCC suppression")
gen_refuses(sub("  #pragma GCC diagnostic pop", "  #pragma GCC diagnostic  pop", up, fixed = TRUE), "Expected exactly one upstream diagnostic block", "changed block text")

# Build-recipe mutations (Unix and Windows).
for (mk in c("src/Makevars", "src/Makevars.win")) {
  gen <- ".rpst-build/flatbuffers/include/flatbuffers/base.h"
  rejected(edit(mk, "-I.rpst-build/flatbuffers/include -Ivendor/flatbuffers/include", "-Ivendor/flatbuffers/include -I.rpst-build/flatbuffers/include"),
           "must precede", paste(mk, "include order swapped"))
  rejected(edit(mk, "pst-flatgeobuf.o: pst-flatgeobuf.cpp ", "pst-flatgeobuf.o: pst-flatgeobuf.cpp #"),
           "must depend on the generated", paste(mk, "generation dependency removed"))
  rejected(edit(mk, "portability/strip-flatbuffers-diagnostics.R rpst-prepare", "rpst-prepare"), "generation rule", paste(mk, "generation rule altered"))
  rejected(edit(mk, "-I.rpst-build/flatbuffers/include", "-isystem .rpst-build/flatbuffers/include"), "isystem|must precede", paste(mk, "-isystem"))
  rejected(edit(mk, "\trm -rf .rpst-build", "\ttrue"), "rpst-clean", paste(mk, "clean no longer removes .rpst-build"))
  rejected(edit(mk, "PKG_CPPFLAGS = ", "PKG_CPPFLAGS = -Ivendor/flatbuffers/include "), "PKG_CPPFLAGS must not", paste(mk, "pristine dir exposed globally"))
}
# The approved generated output itself is pinned independently of the generator.
orig_spec <- env$fgb_upstream_base
bad_spec <- orig_spec; bad_spec$generated_sha256 <- strrep("0", 64)
if (!any(grepl("approved output", env$fgb_build_copy_violations(".", spec = bad_spec)))) stop("altered expected output was not rejected")
bad_spec <- orig_spec; bad_spec$removed_lines <- bad_spec$removed_lines[-1]
if (!length(env$fgb_build_copy_violations(".", spec = bad_spec))) stop("altered removed-line list was not rejected")
message("FlatBuffers/FlatGeobuf vendor verifier tests passed (bytes, file set, manifest, licences, provenance, base.h build copy, recipes)")
