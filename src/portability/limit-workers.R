# Build-only central worker policy transformation for the exact pinned PST source.
limit_workers <- function(source_file, output_file) {
  checksums <- list(
    AngularChoiceAlgo = c("f518e8c71d6c1607723564238692de62", "ec0db906b35e28c7e6077df18255b685"),
    SegmentBetweenness = c("287ec62e7e28f9955740e89545b11b13", "b98f83d994cb1f07d0b49ed9b280e369"),
    SegmentGroupIntegration = c("b5b603d44a91fc8af3b769ca2e6361c6", "bfa367c70db800c0586884a462e43276"))
  checksums$AttractionReach <- c("d62cb47abf4284376936a032de4ee90b", "0656b38e1ee2d3be74bf84aeb1acffc4")
  checksums$AttractionDistance <- c("07a228e44f51d47c8f3980b1854bb0a0", "58ee7467cb3ca8090b2d4e176ea6b271")
  checksums$ODBetweenness <- c("cd14c1edb6b42f5b20ae5d48ce92959f", "e1abcacb8448be2aaa67b21120b4d846")
  key <- sub("[.]cpp$", "", basename(source_file))
  if (!(key %in% names(checksums))) stop("Unsupported worker source")
  original_md5 <- checksums[[key]][[1L]]
  hardened_md5 <- checksums[[key]][[2L]]
  worker_calls <- c(AngularChoiceAlgo = "std::thread::hardware_concurrency()",
                    SegmentBetweenness = "std::thread::hardware_concurrency()",
                    SegmentGroupIntegration = "thread::hardware_concurrency()")
  if (key %in% c("AttractionReach", "AttractionDistance"))
    worker_calls[[key]] <- "std::thread::hardware_concurrency()"
  if (key == "ODBetweenness") worker_calls[[key]] <- "workers.resize(1);"
  old <- worker_calls[[key]]
  new <- "rpst_worker_count()"
  if (key %in% c("AttractionReach", "AttractionDistance")) {
    old <- c(old, "} while (std::future_status::ready != task.wait_for(std::chrono::milliseconds(100)));")
    new <- c(new, paste0(old[[2L]], "\n\t\t\ttask.get();"))
  }
  if (key == "AngularChoiceAlgo") {
    old <- c(old, "\t\t// Update progress\n")
    new <- c(new, "\t\ttask.get();\n\n\t\t// Update progress\n")
  }
  if (key %in% c("AngularChoiceAlgo", "SegmentBetweenness")) {
    # SDK 27 libc++ marks is_lock_free() [[nodiscard]]; in release builds VERIFY(x) is just x. Keep the call, discard its value.
    old <- c(old, "VERIFY(num_processed_segments.is_lock_free());")
    new <- c(new, "(void)VERIFY(num_processed_segments.is_lock_free());")
  }
  if (key == "AttractionReach") {
    old <- c(old, "const float radius = sqrtf(m_lim.straightSqr);")
    new <- c(new, paste0("std::unique_lock<std::mutex> scratch_lock(m_Algo.m_CriticalSection);\n\t\t\t\t\t", old[[3L]]))
  }
  if (key == "ODBetweenness") {
    old <- c(old, "SStep step;", "SStep next_step;",
      "} while (std::future_status::ready != task.wait_for(std::chrono::milliseconds(100)));")
    new <- c("workers.resize(std::min(rpst_worker_count(), 1u));", "SStep step{};", "SStep next_step{};",
      paste0(old[[4L]], "\n\t\t\ttask.get();"))
    old <- c(old, "next_step.m_PrevTrace = (int)m_Trace.size();")
    new <- c(new, paste0("if (m_Trace.size() >= static_cast<size_t>(std::numeric_limits<int>::max()))\n",
      "\t\t\t\tthrow std::runtime_error(\"OD trace count exceeds native signed index bounds\");\n\t\t\t", old[[5L]]))
  }
  read_bytes <- function(path) readBin(path, "raw", n = file.info(path)$size)
  if (!file.exists(source_file) ||
      !identical(unname(tools::md5sum(source_file)), original_md5)) {
    stop("PST source does not match the pinned original checksum")
  }
  original <- read_bytes(source_file)
  text <- rawToChar(original)
  count <- function(pattern, text) {
    matches <- gregexpr(pattern, text, fixed = TRUE)[[1L]]
    if (matches[[1L]] == -1L) 0L else length(matches)
  }
  transformed <- text
  for (i in seq_along(old)) {
    if (count(old[[i]], transformed) != 1L || count(new[[i]], transformed) != 0L) {
      stop("Expected exactly one original pattern and no transformed pattern: ", i)
    }
    transformed <- sub(old[[i]], new[[i]], transformed, fixed = TRUE)
  }
  # Preserve original diagnostic paths and line numbers for the exact warning policy.
  prefix <- paste0('#line 1 "vendor/pstalgo/src/analyses/', key, '.cpp"\n')
  transformed <- paste0(prefix, transformed)
  # Undo only the documented edit and demand the complete original bytes.
  restored <- substring(transformed, nchar(prefix) + 1L)
  for (i in rev(seq_along(old))) {
    if (count(new[[i]], restored) != 1L) stop("Unexpected intended edit count")
    restored <- sub(new[[i]], old[[i]], restored, fixed = TRUE)
  }
  if (!identical(charToRaw(restored), original)) {
    stop("Worker transformation changed more than the intended edits")
  }
  # Output is restricted to generated build state, never the vendor tree.
  portable_path <- gsub("\\", "/", output_file, fixed = TRUE)
  if (!grepl("(^|/)[.]rpst-build/", portable_path) ||
      basename(output_file) != basename(source_file)) {
    stop("Output must be a generated .rpst-build worker source")
  }
  # Resolve existing ancestors before creating directories, so a symlink
  # cannot redirect even directory creation into the pristine vendor tree.
  parent <- dirname(output_file)
  missing <- character()
  while (!dir.exists(parent)) {
    missing <- c(basename(parent), missing)
    next_parent <- dirname(parent)
    if (identical(next_parent, parent)) stop("Cannot resolve output directory")
    parent <- next_parent
  }
  resolved <- do.call(file.path, as.list(c(
      normalizePath(parent, winslash = "/"), missing, basename(output_file))))
  if (grepl("/vendor/pstalgo/", resolved, fixed = TRUE) ||
      identical(normalizePath(source_file, winslash = "/"), resolved)) {
    stop("Refusing to write into the vendor tree")
  }
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  candidate <- tempfile("worker-limit-", tmpdir = dirname(output_file))
  on.exit(unlink(candidate), add = TRUE)
  bytes <- charToRaw(transformed)
  writeBin(bytes, candidate)
  if (!identical(read_bytes(candidate), bytes) ||
      !identical(unname(tools::md5sum(candidate)), hardened_md5) ||
      !identical(read_bytes(source_file), original)) {
    stop("Generated copy or original source failed verification")
  }
  if (file.exists(output_file) && identical(read_bytes(output_file), bytes)) {
    return(invisible(output_file))
  }
  if (file.exists(output_file) && unlink(output_file) != 0L) {
    stop("Cannot replace the generated build copy")
  }
  if (!file.rename(candidate, output_file)) stop("Cannot publish the verified build copy")
  invisible(output_file)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) != 2L) stop("Usage: limit-workers.R original generated-copy")
  limit_workers(args[[1L]], args[[2L]])
}
