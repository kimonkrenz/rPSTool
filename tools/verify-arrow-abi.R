#!/usr/bin/env Rscript
# Offline, fail-closed verification of the carried Arrow C ABI declarations
# (src/arrow-c-abi/arrow_c_abi.h) against their recorded
# provenance (src/arrow-c-abi/PROVENANCE.md). Run from the repository root.
#
# The wrapper header is an extraction of selected declarations from the fixed release
# apache-arrow-25.0.0, NOT a byte-identical copy of the complete upstream abi.h, so the
# checks are structural: exactly the three structs, exactly the two canonical guards, no other
# macros/includes/types, the Apache-2.0 header, and a recorded checksum of the wrapper itself.
# When the pristine upstream file is supplied (RPST_ARROW_ABI_UPSTREAM=<path to abi.h>), the
# upstream SHA-256 is checked against the recorded value and every declaration line of the
# wrapper is shown to occur, in order, in that file. No network access is ever used.

arrow_abi_expected <- list(
  tag = "apache-arrow-25.0.0",
  path = "cpp/src/arrow/c/abi.h",
  upstream_sha256 = "1828f1ce60368cd590d19595910fa19db09b30728f8a43b5f89933623f7a7276"
)

# SHA-256 of a file with whatever is available; NULL when no tool exists (the caller fails closed).
arrow_abi_sha256 <- function(path) {
  if (exists("sha256sum", envir = asNamespace("tools"), inherits = FALSE))
    return(unname(tools::sha256sum(path)))
  attempt <- function(command, args, field) {
    out <- tryCatch(suppressWarnings(system2(command, args, stdout = TRUE, stderr = FALSE)),
                    error = function(e) character())
    if (!length(out)) return(NULL)
    token <- regmatches(out, regexpr("[0-9a-fA-F]{64}", out))
    if (length(token)) tolower(token[[1L]]) else NULL
  }
  attempt("sha256sum", shQuote(path)) %||%
    attempt("shasum", c("-a", "256", shQuote(path))) %||%
    attempt("certutil", c("-hashfile", shQuote(path), "SHA256"))
}
`%||%` <- function(a, b) if (is.null(a)) b else a

# Lines of the wrapper that are verbatim upstream declarations (everything except the rPSTool
# note block, which sits between the licence header and `#pragma once`).
arrow_abi_declaration_lines <- function(header) {
  note_start <- which(startsWith(header, "// rPSTool NOTE:"))
  pragma <- which(header == "#pragma once")
  if (length(note_start) == 1L && length(pragma) == 1L && note_start < pragma)
    header <- header[-(note_start:(pragma - 1L))]
  header[nzchar(trimws(header))]
}

arrow_abi_violations <- function(header, provenance, header_sha256 = NULL, header_md5 = NULL,
                                 upstream = NULL, upstream_sha256 = NULL, expected = arrow_abi_expected) {
  bad <- character()
  add <- function(...) bad <<- c(bad, paste0(...))
  # --- Licence --------------------------------------------------------------------------
  if (length(header) < 16L || !identical(header[1L], "// Licensed to the Apache Software Foundation (ASF) under one") ||
      !any(grepl("Apache License, Version 2.0", header[1:16], fixed = TRUE)) ||
      !any(grepl("http://www.apache.org/licenses/LICENSE-2.0", header[1:16], fixed = TRUE)))
    add("the Apache-2.0 licence header is missing or altered")
  # --- Exactly the three structs ----------------------------------------------------------
  structs <- sub("^struct (\\w+) \\{.*$", "\\1", header[grepl("^struct \\w+ \\{", header)])
  if (!setequal(structs, c("ArrowSchema", "ArrowArray", "ArrowArrayStream")) || anyDuplicated(structs))
    add("header must declare exactly ArrowSchema, ArrowArray and ArrowArrayStream (found: ",
        paste(structs, collapse = ", "), ")")
  # --- Canonical guards, kept exactly ---------------------------------------------------------
  for (guard in c("ARROW_C_DATA_INTERFACE", "ARROW_C_STREAM_INTERFACE")) {
    if (sum(header == paste0("#ifndef ", guard)) != 1L || sum(header == paste0("#  define ", guard)) != 1L ||
        sum(header == paste0("#endif  // ", guard)) != 1L)
      add("guard ", guard, " must appear exactly as upstream (#ifndef, #  define, #endif  // comment)")
  }
  # --- Nothing else ------------------------------------------------------------------------------
  directives <- header[grepl("^\\s*#", header)]
  allowed <- c("#pragma once", "#include <stdint.h>", "#ifdef __cplusplus", "#endif",
               "#ifndef ARROW_C_DATA_INTERFACE", "#  define ARROW_C_DATA_INTERFACE",
               "#endif  // ARROW_C_DATA_INTERFACE", "#ifndef ARROW_C_STREAM_INTERFACE",
               "#  define ARROW_C_STREAM_INTERFACE", "#endif  // ARROW_C_STREAM_INTERFACE")
  extra <- setdiff(trimws(directives), allowed)
  if (length(extra)) add("unexpected preprocessor directive(s): ", paste(unique(extra), collapse = "; "))
  code <- header[!grepl("^\\s*(//|#)", header) & nzchar(trimws(header))]
  if (any(grepl("ARROW_FLAG|ARROW_STATISTICS|DEVICE|ASYNC|ArrowDevice|typedef|\\binline\\b|\\bstatic\\b",
                paste(header[!grepl("^\\s*//", header)], collapse = "\n"))))
    add("header contains declarations beyond the three selected structs")
  if (!identical(sum(grepl("^extern \"C\" \\{$", code)), 1L) || sum(code == "}") != 1L)
    add("header must contain the single canonical extern \"C\" block")
  # --- Provenance record -------------------------------------------------------------------------
  has <- function(text) any(grepl(text, provenance, fixed = TRUE))
  for (item in c(expected$tag, expected$path, expected$upstream_sha256, "Apache-2.0", "apache/arrow"))
    if (!has(item)) add("PROVENANCE.md does not record: ", item)
  recorded <- function(label) {
    line <- provenance[startsWith(provenance, paste0("- ", label, ":"))]
    if (length(line) != 1L) return(NA_character_)
    tolower(trimws(gsub("`", "", sub("^[^:]*:", "", line))))
  }
  recorded_sha <- recorded("Wrapper header SHA-256")
  recorded_md5 <- recorded("Wrapper header MD5")
  if (is.na(recorded_sha) || !grepl("^[0-9a-f]{64}$", recorded_sha)) add("PROVENANCE.md has no valid 'Wrapper header SHA-256' entry")
  if (is.na(recorded_md5) || !grepl("^[0-9a-f]{32}$", recorded_md5)) add("PROVENANCE.md has no valid 'Wrapper header MD5' entry")
  if (is.null(header_sha256)) add("no SHA-256 tool is available to check the wrapper header")
  else if (!identical(tolower(header_sha256), recorded_sha)) add("wrapper header SHA-256 differs from the value in PROVENANCE.md")
  if (!is.null(header_md5) && !identical(tolower(header_md5), recorded_md5))
    add("wrapper header MD5 differs from the value in PROVENANCE.md")
  # --- Optional comparison with the pristine upstream file ------------------------------------------
  if (!is.null(upstream)) {
    if (!identical(upstream_sha256, expected$upstream_sha256))
      add("the supplied upstream abi.h does not have the recorded SHA-256")
    wanted <- arrow_abi_declaration_lines(header)
    position <- 0L
    for (line in wanted) {
      hit <- which(upstream == line)
      hit <- hit[hit > position]
      if (!length(hit)) { add("not an in-order upstream line: ", line); break }
      position <- hit[[1L]]
    }
  }
  bad
}

arrow_abi_verify <- function(header_path = "src/arrow-c-abi/arrow_c_abi.h",
                             provenance_path = "src/arrow-c-abi/PROVENANCE.md",
                             upstream_path = Sys.getenv("RPST_ARROW_ABI_UPSTREAM", "")) {
  upstream <- NULL
  upstream_sha <- NULL
  if (nzchar(upstream_path)) {
    upstream <- readLines(upstream_path, warn = FALSE)
    upstream_sha <- arrow_abi_sha256(upstream_path)
  }
  arrow_abi_violations(readLines(header_path, warn = FALSE), readLines(provenance_path, warn = FALSE),
                       header_sha256 = arrow_abi_sha256(header_path),
                       header_md5 = unname(tools::md5sum(header_path)),
                       upstream = upstream, upstream_sha256 = upstream_sha)
}

if (sys.nframe() == 0L && !interactive() && identical(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)),
                                                      "tools/verify-arrow-abi.R")) {
  violations <- arrow_abi_verify()
  if (length(violations)) stop("Arrow C ABI verification failed:\n  ", paste(violations, collapse = "\n  "), call. = FALSE)
  message("Verified Arrow C ABI declarations against PROVENANCE.md",
          if (nzchar(Sys.getenv("RPST_ARROW_ABI_UPSTREAM", ""))) " and the pristine upstream abi.h" else " (offline; no upstream file supplied)")
}
