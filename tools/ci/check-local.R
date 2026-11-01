#!/usr/bin/env Rscript
# Run from the repository root with the same R/toolchain and test dependencies
# required by the cross-platform workflow. Keep each existing gate in its own process.
if (length(commandArgs(trailingOnly = TRUE))) {
  stop("Usage: Rscript tools/ci/check-local.R (from the repository root)")
}
source("tools/ci/gate-mode.R")
pst_enforce_full_suite_mode()   # the local gate is ALWAYS the full development suite, whatever the parent environment says
platform <- if (.Platform$OS.type == "windows") "windows" else
  if (Sys.info()[["sysname"]] == "Darwin") "macos" else "ubuntu"
rscript <- file.path(R.home("bin"),
                     if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
gates <- c("tools/verify-vendor.R", "tools/test-checkout-attributes.R", "tools/test-portability.R", "tools/verify-arrow-abi.R", "tools/test-arrow-abi.R", "tools/verify-flatgeobuf-vendor.R", "tools/test-flatgeobuf-vendor.R", "tools/test-fp-policy.R", "tools/test-isovist-safety.R", "tools/test-raster-safety.R", "tools/test-diagnostic-fixes.R",
           "tools/test-graph-constructors.R", "tools/test-network-construction.R", "tools/test-worker-limits.R", "tools/test-fs-layer.R",
           "tools/ci/test-warning-policy.R", "tools/test-build-lifecycle.R",
           "tools/ci/check-package.R")
for (script in gates) {
  message("Running ", script)
  arguments <- if (script == "tools/ci/check-package.R") c(script, platform) else script
  status <- system2(rscript, shQuote(arguments))
  if (status != 0L) quit(status = status)
}
message("Local full check passed (", platform, ")")
