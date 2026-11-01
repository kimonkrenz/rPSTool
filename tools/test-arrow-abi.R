#!/usr/bin/env Rscript
# Fail-closed / mutation tests for tools/verify-arrow-abi.R. Run from the repository root.
env <- new.env()
sys.source("tools/verify-arrow-abi.R", envir = env)
header <- readLines("src/arrow-c-abi/arrow_c_abi.h", warn = FALSE)
provenance <- readLines("src/arrow-c-abi/PROVENANCE.md", warn = FALSE)
sha <- env$arrow_abi_sha256("src/arrow-c-abi/arrow_c_abi.h")
md5 <- unname(tools::md5sum("src/arrow-c-abi/arrow_c_abi.h"))
check <- function(h = header, p = provenance, sha_value = sha, md5_value = md5, ...)
  env$arrow_abi_violations(h, p, header_sha256 = sha_value, header_md5 = md5_value, ...)
rejected <- function(violations, pattern) {
  if (!any(grepl(pattern, violations))) stop("Expected a violation matching '", pattern, "', got: ",
                                             paste(violations, collapse = " | "))
}

stopifnot(length(check()) == 0L)
stopifnot(!is.null(sha), nchar(sha) == 64L)

# The recorded checksum binds the exact wrapper bytes.
rejected(check(sha_value = paste(rep("0", 64), collapse = "")), "SHA-256 differs")
rejected(check(md5_value = paste(rep("0", 32), collapse = "")), "MD5 differs")
rejected(check(sha_value = NULL), "no SHA-256 tool")
rejected(check(p = sub("Wrapper header SHA-256", "Wrapper header SHA", provenance, fixed = TRUE)), "no valid 'Wrapper header SHA-256'")
# Provenance record must keep naming the fixed release, path and source checksum.
for (item in c("apache-arrow-25.0.0", "cpp/src/arrow/c/abi.h", env$arrow_abi_expected$upstream_sha256, "Apache-2.0"))
  rejected(check(p = gsub(item, "REDACTED", provenance, fixed = TRUE)), "does not record")
# Structural drift in the wrapper.
rejected(check(h = c(header, "#  define ARROW_FLAG_NULLABLE 2")), "unexpected preprocessor|beyond the three")
rejected(check(h = sub("#include <stdint.h>", "#include <stdint.h>\n#include <stdlib.h>", header, fixed = TRUE)), "unexpected preprocessor")
rejected(check(h = header[header != "#ifndef ARROW_C_STREAM_INTERFACE"]), "guard ARROW_C_STREAM_INTERFACE")
rejected(check(h = sub("#  define ARROW_C_DATA_INTERFACE", "#  define ARROW_C_DATA_INTERFACE_X", header, fixed = TRUE)), "guard ARROW_C_DATA_INTERFACE|unexpected preprocessor")
rejected(check(h = sub("#endif  // ARROW_C_STREAM_INTERFACE", "#endif", header, fixed = TRUE)), "guard ARROW_C_STREAM_INTERFACE")
rejected(check(h = c(header[-length(header)], "struct ArrowDeviceArray {", "};")), "exactly ArrowSchema")
rejected(check(h = header[!grepl("^struct ArrowSchema", header)]), "exactly ArrowSchema")
rejected(check(h = c(header, "typedef int32_t ArrowDeviceType;")), "beyond the three")
rejected(check(h = c(header, "#  define ARROW_STATISTICS_KEY_ROW_COUNT_EXACT \"x\"")), "unexpected preprocessor|beyond")
rejected(check(h = header[-(1:4)]), "licence header")
rejected(check(h = sub("Apache License, Version 2.0", "Some Licence", header, fixed = TRUE)), "licence header")
rejected(check(h = header[header != "}"]), "extern")

# Comparison with the pristine upstream file (here: a synthetic superset in which the wrapper's
# declaration lines occur in order, standing in for the real file that is not committed).
declarations <- env$arrow_abi_declaration_lines(header)
upstream <- as.vector(rbind(declarations, "// interleaved upstream-only line"))
good <- check(upstream = upstream, upstream_sha256 = env$arrow_abi_expected$upstream_sha256)
stopifnot(length(good) == 0L)
rejected(check(upstream = upstream, upstream_sha256 = "deadbeef"), "recorded SHA-256")
changed <- sub("int64_t null_count;", "int32_t null_count;", header, fixed = TRUE)
stopifnot(!identical(changed, header))
rejected(check(h = changed, upstream = upstream, upstream_sha256 = env$arrow_abi_expected$upstream_sha256),
         "not an in-order upstream line|SHA-256 differs")
reordered <- header
reordered[match("  int64_t length;", reordered) + 0:1] <- rev(reordered[match("  int64_t length;", reordered) + 0:1])
rejected(check(h = reordered, upstream = upstream, upstream_sha256 = env$arrow_abi_expected$upstream_sha256),
         "not an in-order upstream line|SHA-256 differs")

# The real offline entry point passes on the committed files.
stopifnot(length(env$arrow_abi_verify(upstream_path = "")) == 0L)
message("Arrow C ABI verifier tests passed (structure, guards, provenance, checksums, upstream comparison)")
