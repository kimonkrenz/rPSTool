#!/usr/bin/env Rscript
# Offline, fail-closed verification of the vendored FlatBuffers headers and FlatGeobuf schema/generated
# headers. Run from the repository root. These files must stay byte-for-byte pristine
# (like src/vendor/pstalgo); any drift, addition or removal is an error. Nothing is downloaded.
#   src/vendor/flatbuffers : google/flatbuffers tag v24.12.23, commit a2cd1ea3b6d3fee220106b5fed3f7ce8da9eb757
#                            (15 headers; the 16th, base.h, is the canonical upstream build input below)
#   inst/upstream/flatbuffers : the byte-exact upstream base.h. R CMD check scans src/ and inst/include for
#                            diagnostic-suppression pragmas, so base.h lives outside them and the compiler sees a
#                            verified generated copy (src/.rpst-build/flatbuffers/...) with only the two
#                            upstream GCC diagnostic-suppression blocks (4 conditional blocks) removed.
#   src/vendor/flatgeobuf  : flatgeobuf/flatgeobuf master d8b6d6afcfe25b7898ddd721be0cb85c3be276ea
#                            (header.fbs/feature.fbs, flatc-generated header_generated.h/feature_generated.h)
sys.source("tools/verify-arrow-abi.R", envir = (sha_env <- new.env()))  # shared arrow_abi_sha256()
fgb_sha256 <- sha_env$arrow_abi_sha256

fgb_vendor_expected <- list(
  flatbuffers = list(
    dir = "src/vendor/flatbuffers",
    files = c(
    "LICENSE" = "cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30",
    "include/flatbuffers/allocator.h" = "19b1e7e9439ed7c7fdc61c04c99a14d33fc11295b590b6d0b1557ffcae4e4a59",
    "include/flatbuffers/array.h" = "7a2111cc9670a5ed62502e5cc89216867e81df952dbfb7b3179c17ed2d5425fd",
    "include/flatbuffers/buffer.h" = "10c1e7db57f0a291eb48fbfc718a0ff0ee3b7a3f226c38168a361c1d9c32a39c",
    "include/flatbuffers/buffer_ref.h" = "e846dd9096c4c66b649811e63797770e240b0d2a8d5e7cfdd9be805f956080ba",
    "include/flatbuffers/default_allocator.h" = "51bd4a216a795323af2cf98811bc2910264081a2eac7e6cc980b25e7d54c47fb",
    "include/flatbuffers/detached_buffer.h" = "85dfd3113aad26671e8e9a39cc922b1b0ee2725d7fb298f2fecd1e62da71528b",
    "include/flatbuffers/flatbuffer_builder.h" = "8ebd8cd6d32889f957d6bc7c17d1e21c0eb500c00f206a2fa3d28c76dde7993f",
    "include/flatbuffers/flatbuffers.h" = "dee86570da5c2a6f1bbf090f7717d3279d8d7a94691ae20626c552673a766b39",
    "include/flatbuffers/stl_emulation.h" = "a6a8033b4738e18b1e0fc0fb4a1e18b446d25799b9769e6d20ffe25395051882",
    "include/flatbuffers/string.h" = "b2ce182c22bae4b85ab9593c0c4969b1ed2eabd606063b5df3198a16ba60b7fe",
    "include/flatbuffers/struct.h" = "6a799f26e99ca576ef2c9f4b06ce1993eccfe43821025a041224d3c7c2b11bda",
    "include/flatbuffers/table.h" = "6e08518accda07f5abba53fc86132264a579597b97f02dcfa4b9130188e1c6ee",
    "include/flatbuffers/vector.h" = "1af3513e1e4ce81947411588ecbc508bb4bcc20c02467dcd9912615712ee412b",
    "include/flatbuffers/vector_downward.h" = "7bccddc6f48718a9457f71ece5542f90f7f8674134c92e8f5f5261d5333d3f33",
    "include/flatbuffers/verifier.h" = "9eaf61e1d68f67545b816ef3c92f4ee7d88b582cfeca0f178dd024dab73d4a0e")),
  flatgeobuf = list(
    dir = "src/vendor/flatgeobuf",
    files = c(
    "LICENSE" = "82b5250889974b120ef38428a73982e1d1054ea778e2b54312d8721ead5bfd93",
    "feature.fbs" = "5bb05a68da45f52d3e34a97b47120bddf8b62ce58400299bd4842cf680ee4d7c",
    "feature_generated.h" = "2d6604ec048280ba097b460535b3373eb3b149848421d583359055e19b7117cf",
    "header.fbs" = "dfe4f97b1a7e8f447b4b7849757325c7b285a8dc146c3a30dbf82198cdb46be0",
    "header_generated.h" = "487db792551538ba3833912dd95b98d9568d95e17e239c2778cc56227f1f48f6")))

fgb_upstream_base <- list(
  dir = "inst/upstream/flatbuffers",
  path = "include/flatbuffers/base.h",
  sha256 = "3f28edd053106cfe229f3887b6f36153785afb347867c55b403da5eff3a88ef8",
  generated_sha256 = "1ef073aaafca01ccd944911ff4678a413884fa8dfb1eb42fecd9b405ad63f693",
  # Exactly the lines the approved transformation removes, in file order.
  removed_lines = c(
    "#if (FLATBUFFERS_GCC >= 100000) && (FLATBUFFERS_GCC < 110000)",
    "  #pragma GCC diagnostic push",
    "  #pragma GCC diagnostic ignored \"-Wstringop-overflow\"",
    "#endif",
    "#if (FLATBUFFERS_GCC >= 100000) && (FLATBUFFERS_GCC < 110000)",
    "  #pragma GCC diagnostic pop",
    "#endif",
    "#if !defined(_MSC_VER)",
    "  #pragma GCC diagnostic push",
    "  #pragma GCC diagnostic ignored \"-Wfloat-equal\"",
    "#endif",
    "#if !defined(_MSC_VER)",
    "  #pragma GCC diagnostic pop",
    "#endif"))

fgb_vendor_pins <- c(flatbuffers_tag = "v24.12.23",
                     flatbuffers_commit = "a2cd1ea3b6d3fee220106b5fed3f7ce8da9eb757",
                     flatgeobuf_commit = "d8b6d6afcfe25b7898ddd721be0cb85c3be276ea")

# Returns a character vector of violations (empty when the vendored trees are exactly as pinned).
fgb_vendor_violations <- function(root = ".", expected = fgb_vendor_expected, pins = fgb_vendor_pins,
                                  sha256 = fgb_sha256) {
  bad <- character()
  add <- function(...) bad <<- c(bad, paste0(...))
  for (name in names(expected)) {
    dir <- file.path(root, expected[[name]]$dir)
    want <- expected[[name]]$files
    if (!dir.exists(dir)) { add(name, ": directory is missing"); next }
    present <- sort(list.files(dir, recursive = TRUE, all.files = TRUE, no.. = TRUE))
    allowed_extra <- c("SHA256SUMS", "PROVENANCE.md")
    stray <- setdiff(present, c(names(want), allowed_extra))
    if (length(stray)) add(name, ": unexpected file(s): ", paste(stray, collapse = ", "))
    for (f in c(names(want), allowed_extra)) if (!(f %in% present)) add(name, ": missing file ", f)
    for (f in intersect(names(want), present)) {
      actual <- sha256(file.path(dir, f))
      if (is.null(actual)) { add("no SHA-256 tool is available to verify ", f); next }
      if (!identical(tolower(actual), unname(want[[f]]))) add(name, ": ", f, " differs from the pinned bytes")
    }
    # The recorded manifest must agree with the pinned table (it is a human-readable record).
    sums <- file.path(dir, "SHA256SUMS")
    if (file.exists(sums)) {
      lines <- readLines(sums, warn = FALSE)
      recorded <- setNames(sub("^([0-9a-f]{64})  \\./(.*)$", "\\1", lines), sub("^([0-9a-f]{64})  \\./(.*)$", "\\2", lines))
      if (!identical(sort(names(recorded)), sort(names(want))) ||
          !all(recorded[names(want)] == unlist(want)[names(want)]))
        add(name, ": SHA256SUMS does not match the pinned file table")
    }
    prov <- file.path(dir, "PROVENANCE.md")
    if (file.exists(prov)) {
      text <- paste(readLines(prov, warn = FALSE), collapse = "\n")
      for (pin in pins[startsWith(names(pins), name)]) if (!grepl(pin, text, fixed = TRUE))
        add(name, ": PROVENANCE.md does not record ", pin)
    }
  }
  # Licence texts must be the real ones, and the generated headers must demand the vendored FlatBuffers.
  lic <- function(path) { p <- file.path(root, path); if (file.exists(p)) readLines(p, warn = FALSE) else character() }
  if (!any(grepl("Apache License", head(lic("src/vendor/flatbuffers/LICENSE"), 5)) ) ||
      !any(grepl("Version 2.0", head(lic("src/vendor/flatbuffers/LICENSE"), 5), fixed = TRUE)))
    add("flatbuffers: LICENSE is not the Apache License 2.0 text")
  if (!any(grepl("Copyright (c) 2018, Bj", lic("src/vendor/flatgeobuf/LICENSE")[1:2], fixed = TRUE)) ||
      !any(grepl("Redistributions in binary form must reproduce", lic("src/vendor/flatgeobuf/LICENSE"), fixed = TRUE)))
    add("flatgeobuf: LICENSE is not the BSD-2-Clause text with the FlatGeobuf copyright line")
  base <- paste(lic("inst/upstream/flatbuffers/include/flatbuffers/base.h"), collapse = "\n")
  version <- vapply(c("MAJOR", "MINOR", "REVISION"), function(k)
    sub(paste0(".*#define FLATBUFFERS_VERSION_", k, " ([0-9]+).*"), "\\1", base), "")
  if (!identical(unname(version), c("24", "12", "23"))) add("flatbuffers: base.h is not version 24.12.23")
  gen <- paste(lic("src/vendor/flatgeobuf/header_generated.h"), collapse = " ")
  if (!grepl("FLATBUFFERS_VERSION_MAJOR == 24", gen, fixed = TRUE) || !grepl("FLATBUFFERS_VERSION_MINOR == 12", gen, fixed = TRUE) ||
      !grepl("FLATBUFFERS_VERSION_REVISION == 23", gen, fixed = TRUE))
    add("flatgeobuf: generated header does not require FlatBuffers 24.12.23")
  bad <- c(bad, fgb_build_copy_violations(root, sha256))
  bad
}

# Canonical upstream base.h, the generated build copy, and the build recipes that use it.
fgb_build_copy_violations <- function(root = ".", sha256 = fgb_sha256, spec = fgb_upstream_base) {
  bad <- character()
  add <- function(...) bad <<- c(bad, paste0(...))
  up_dir <- file.path(root, spec$dir)
  upstream <- file.path(up_dir, spec$path)
  if (!dir.exists(up_dir)) return(paste0("base.h: ", spec$dir, " is missing"))
  present <- sort(list.files(up_dir, recursive = TRUE, all.files = TRUE, no.. = TRUE))
  stray <- setdiff(present, c(spec$path, "SHA256SUMS"))
  if (length(stray)) add("base.h: unexpected file(s) in ", spec$dir, ": ", paste(stray, collapse = ", "))
  if (!file.exists(upstream)) { add("base.h: missing canonical upstream file"); return(bad) }
  if (!identical(tolower(sha256(upstream) %||% ""), spec$sha256)) add("base.h: upstream base.h differs from the pinned bytes")
  sums <- file.path(up_dir, "SHA256SUMS")
  if (!file.exists(sums) || !identical(readLines(sums, warn = FALSE), paste0(spec$sha256, "  ./", spec$path)))
    add("base.h: upstream SHA256SUMS does not match the pinned hash")
  if (file.exists(file.path(root, "src/vendor/flatbuffers", spec$path)))
    add("base.h: a copy of base.h exists under src/vendor (R CMD check would scan its pragmas)")
  if (dir.exists(file.path(root, "inst/include")) &&
      length(list.files(file.path(root, "inst/include"), pattern = "base[.]h$", recursive = TRUE)))
    add("base.h: a copy of base.h exists under inst/include")
  # The transformation: run the real generator on the canonical file and compare with the approved output.
  script <- file.path(root, "src/portability/strip-flatbuffers-diagnostics.R")
  if (!file.exists(script)) { add("base.h: strip-flatbuffers-diagnostics.R is missing"); return(bad) }
  out <- file.path(tempfile("fgbgen-"), ".rpst-build", "flatbuffers", "include", "flatbuffers", "base.h")
  on.exit(unlink(dirname(dirname(dirname(dirname(dirname(out))))), recursive = TRUE), add = TRUE)
  env <- new.env(parent = globalenv())
  ran <- tryCatch({ sys.source(script, envir = env); env$strip_flatbuffers_diagnostics(upstream, out); TRUE },
                  error = function(e) { add("base.h: generation failed: ", conditionMessage(e)); FALSE })
  if (ran) {
    if (!identical(tolower(sha256(out) %||% ""), spec$generated_sha256)) add("base.h: generated copy is not the approved output")
    a <- readLines(upstream, warn = FALSE); b <- readLines(out, warn = FALSE)
    if (length(a) - length(b) != length(spec$removed_lines)) add("base.h: generated copy removes the wrong number of lines")
    # Subsequence check: every generated line appears in order in upstream, and the skipped lines are exactly the approved ones.
    j <- 1L; skipped <- character()
    for (line in a) if (j <= length(b) && identical(line, b[[j]])) j <- j + 1L else skipped <- c(skipped, line)
    if (j <= length(b) || !identical(skipped, spec$removed_lines)) add("base.h: generated copy differs from upstream by more than the approved blocks")
    if (any(grepl("#pragma[[:space:]]+(GCC|clang)[[:space:]]+diagnostic", b))) add("base.h: generated copy still has a GCC/clang diagnostic pragma")
    if (!any(grepl("#pragma warning", b, fixed = TRUE))) add("base.h: generated copy lost the MSVC pragma handling")
    # Rejection: any other input must be refused (fail closed on upstream drift).
    drift <- tempfile("fgbdrift-"); writeLines(c(a, "// drift"), drift)
    on.exit(unlink(drift), add = TRUE)
    refused <- tryCatch({ env$strip_flatbuffers_diagnostics(drift, sub("base[.]h$", "drift/base.h", out)); FALSE },
                        error = function(e) TRUE)
    if (!refused) add("base.h: generator accepted a drifted upstream file")
  }
  # Build recipes (Unix and Windows).
  gen <- ".rpst-build/flatbuffers/include/flatbuffers/base.h"
  up <- "../inst/upstream/flatbuffers/include/flatbuffers/base.h"
  for (mk in c("src/Makevars", "src/Makevars.win")) {
    f <- file.path(root, mk)
    if (!file.exists(f)) { add(mk, ": missing"); next }
    lines <- readLines(f, warn = FALSE); text <- paste(lines, collapse = "\n")
    if (grepl("-isystem", text, fixed = TRUE)) add(mk, ": must not use -isystem")
    recipe <- grep("^\t\\$\\(CXX\\).* -c pst-flatgeobuf[.]cpp ", lines, value = TRUE)
    if (length(recipe) != 1L) { add(mk, ": expected exactly one pst-flatgeobuf compile recipe"); next }
    g <- regexpr("-I.rpst-build/flatbuffers/include", recipe, fixed = TRUE)
    v <- regexpr("-Ivendor/flatbuffers/include", recipe, fixed = TRUE)
    if (g < 0 || v < 0 || g > v) add(mk, ": generated FlatBuffers include dir must precede the pristine one")
    if (!(paste0("pst-flatgeobuf.o: pst-flatgeobuf.cpp ", gen) %in% lines)) add(mk, ": pst-flatgeobuf.o must depend on the generated base.h")
    if (any(grepl("^PKG_CPPFLAGS.*flatbuffers", lines))) add(mk, ": PKG_CPPFLAGS must not expose FlatBuffers to other units")
    rule <- paste0(gen, ": ", up, " portability/strip-flatbuffers-diagnostics.R rpst-prepare")
    k <- match(rule, lines)
    expected_cmd <- c("\tmkdir -p .rpst-build/flatbuffers/include/flatbuffers",
      paste0("\t\"$(R_HOME)/bin$(R_ARCH_BIN)/Rscript\" portability/strip-flatbuffers-diagnostics.R ", up, " ", gen))
    if (is.na(k) || !identical(lines[k + 1:2], expected_cmd)) add(mk, ": generation rule is missing or altered")
    if (!("\trm -rf .rpst-build" %in% lines) || !("shlib-clean: rpst-clean" %in% lines)) add(mk, ": rpst-clean must remove .rpst-build")
  }
  bad
}
`%||%` <- function(a, b) if (is.null(a)) b else a

if (sys.nframe() == 0L && !interactive() &&
    identical(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)), "tools/verify-flatgeobuf-vendor.R")) {
  violations <- fgb_vendor_violations()
  if (length(violations))
    stop("FlatBuffers/FlatGeobuf vendor verification failed:\n  ", paste(violations, collapse = "\n  "), call. = FALSE)
  message("Verified pristine FlatBuffers v24.12.23 headers (incl. canonical upstream base.h), FlatGeobuf schema/generated headers, the exact generated base.h build copy and its recipes (offline)")
}
