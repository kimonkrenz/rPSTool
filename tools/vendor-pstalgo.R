#!/usr/bin/env Rscript

# Development only: never invoked by package installation or runtime.
# Run from the repository root. An optional argument supplies a local archive
# of the exact pinned commit; the extracted root is checked before copying.
main <- function() {
  pst_commit <- "63df80a2cf3dd289be95ea3d91667c3490719b75"
  pst_repo <- "SMoG-Chalmers/PST"
  root_name <- paste0("PST-", pst_commit)
  dest <- file.path("src", "vendor", "pstalgo")
  provenance <- file.path("inst", "upstream")
  if (!file.exists("DESCRIPTION") || !dir.exists("inst/upstream")) {
    stop("Run this helper from the rPSTool repository root")
  }
  dir.create(".local", showWarnings = FALSE)
  tmp <- tempfile("vendor-", tmpdir = ".local")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) > 1L) stop("Usage: Rscript tools/vendor-pstalgo.R [archive]")
  if (length(args)) {
    archive <- normalizePath(args[[1L]], mustWork = TRUE)
  } else {
    archive <- file.path(tmp, "pst.tar.gz")
    url <- sprintf("https://codeload.github.com/%s/tar.gz/%s", pst_repo, pst_commit)
    download.file(url, archive, mode = "wb")
  }
  entries <- untar(archive, list = TRUE)
  if (!length(entries) || any(!startsWith(entries, paste0(root_name, "/"))) ||
      any(grepl("(^|/)\\.\\.(/|$)", entries))) {
    stop("Archive paths do not match the pinned commit")
  }
  # Extract only the selected core and provenance, never Python or QGIS.
  selected <- entries[startsWith(entries, paste0(root_name, "/pstalgo/include/")) |
                        startsWith(entries, paste0(root_name, "/pstalgo/src/")) |
                        entries %in% paste0(root_name, c(
                          "/pstalgo/README.txt", "/pstalgo/CMakeLists.txt",
                          "/README.txt", "/LICENSE"))]
  # Selecting directories as well as their children makes GNU tar consume
  # entries twice. Select files only; parent directories are created by tar.
  selected <- selected[!endsWith(selected, "/")]
  if (untar(archive, files = selected, exdir = tmp) != 0L) stop("Extraction failed")
  upstream <- file.path(tmp, root_name)
  engine <- file.path(upstream, "pstalgo")
  required <- c(file.path(engine, c("include", "src", "README.txt", "CMakeLists.txt")),
                file.path(upstream, c("README.txt", "LICENSE")))
  if (!all(file.exists(required))) stop("Missing required upstream paths")
  files <- list.files(engine, recursive = TRUE, all.files = TRUE,
                      no.. = TRUE, full.names = FALSE)
  # Do not silently destroy a modified vendor tree when refreshing.
  existing <- list.files(dest, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  existing <- setdiff(existing, ".gitkeep")
  if (length(existing)) {
    if (!identical(sort(existing), sort(files)) ||
        !identical(unname(tools::md5sum(file.path(dest, files))),
                   unname(tools::md5sum(file.path(engine, files))))) {
      stop("Existing vendor tree differs; review and remove it explicitly before replacing")
    }
  }
  dir.create(dest, recursive = TRUE, showWarnings = FALSE)
  unlink(file.path(dest, ".gitkeep"))
  for (f in files) {
    target <- file.path(dest, f)
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(file.path(engine, f), target, overwrite = TRUE,
                   copy.mode = TRUE, copy.date = TRUE)) stop("Copy failed: ", f)
  }
  dir.create(provenance, recursive = TRUE, showWarnings = FALSE)
  for (f in c("README.txt", "LICENSE")) {
    target <- file.path(provenance, paste0("PST_", f))
    if (!file.copy(file.path(upstream, f), target, overwrite = TRUE)) stop("Copy failed: ", f)
  }
  copied <- tools::md5sum(file.path(dest, files))
  if (!identical(unname(copied), unname(tools::md5sum(file.path(engine, files))))) {
    stop("Vendored content does not match the extracted source")
  }
  # Portable content inventory, not an authentication/signature mechanism.
  inventory <- c(file.path("src", "vendor", "pstalgo", files),
                 file.path(provenance, c("PST_README.txt", "PST_LICENSE")))
  inventory <- sort(inventory, method = "radix")
  writeLines(paste(unname(tools::md5sum(inventory)), inventory),
             file.path(provenance, "FILES.md5"))
  message("Vendored ", length(files), " unchanged files from PST v3.3.2 / ", pst_commit)
  message("Python/QGIS excluded; no native build wiring added. Review git diff.")
}
main()
