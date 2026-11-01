# Exact diagnostic multisets, not warning-class suppression. Compiler output
# and R CMD check logs remain intact for review and CRAN hardening.
# Diagnostics emitted only by a specific macOS SDK's libc++ (pinned source discards
# the value of std::atomic::is_lock_free() under VERIFY in non-debug builds; the
# libc++ shipped with MacOSX27 marks it nodiscard). They are required exactly on
# that SDK, read from the R CMD check log, and forbidden on every other toolchain.
pst_macos_sdk27 <- function(check) {
  if (is.null(check)) return(FALSE)
  any(grepl("^\\* used SDK: .+MacOSX27(\\.[0-9]+)*\\.sdk.+$", check, useBytes = TRUE))
}

read_pst_warning_policy <- function(platform, policy_dir = "tools/ci", check = NULL) {
  if (!platform %in% c("ubuntu", "macos", "windows")) stop("Unsupported CI platform")
  if (platform == "ubuntu") {
    return(data.frame(phase = character(), count = integer(), signature = character()))
  }
  read_table <- function(path) read.delim(path, quote = "", comment.char = "",
                                          colClasses = "character", check.names = FALSE)
  policy <- read_table(file.path(policy_dir, paste0(platform, "-pst-warnings.tsv")))
  if (platform == "macos" && pst_macos_sdk27(check)) {
    policy <- rbind(policy, read_table(file.path(policy_dir, "macos-sdk27-pst-warnings.tsv")))
  }
  if (!identical(names(policy), c("phase", "count", "signature")) ||
      !nrow(policy) || any(!policy$phase %in% c("compiler", "check")) ||
      any(!grepl("^[1-9][0-9]*$", policy$count)) ||
      anyDuplicated(paste(policy$phase, policy$signature))) stop("Invalid warning policy")
  policy$count <- as.integer(policy$count)
  if (anyNA(policy$count)) stop("Invalid warning counts")
  # Only pinned PST files (including restored build-copy paths) qualify.
  inventory <- read.table("inst/upstream/FILES.md5", colClasses = "character")$V2
  for (signature in policy$signature) {
    path <- sub(":[0-9]+:[0-9]+: warning:.*$", "", signature)
    if (startsWith(path, "vendor/pstalgo/")) {
      path <- normalizePath(file.path("src", path), winslash = "/", mustWork = TRUE)
      if (!path %in% normalizePath(inventory, winslash = "/", mustWork = TRUE)) {
        stop("Warning signature is not from pinned inventory")
      }
    } else if (platform == "macos" && identical(signature, pst_libcpp_warning())) {
      # This diagnostic originates in the exact pinned template instantiation.
    } else stop("Warning signature outside pinned PST/build-copy source")
  }
  policy
}

pst_libcpp_origin <- function() {
  "vendor/pstalgo/src/analyses/AttractionReach.cpp:214:6: note: in instantiation of member function 'std::unique_ptr<(anonymous namespace)::CAttractionAlgo::CWorker>::reset' requested here"
}

pst_libcpp_warning <- function() {
  paste0("<libc++>/__memory/unique_ptr.h:77:5: warning: delete called on non-final ",
         "'(anonymous namespace)::CAttractionAlgo::CWorker' that has virtual functions ",
         "but non-virtual destructor [-Wdelete-non-abstract-non-virtual-dtor] ",
         "[instantiated at vendor/pstalgo/src/analyses/AttractionReach.cpp:214:6]")
}

pst_compiler_warnings <- function(install) {
  indices <- grep(": warning:", install, fixed = TRUE)
  diagnostics <- install[indices]
  # Exact observed spellings of the same system-header location, each bound
  # to its own lines: the Xcode SDK used by CI reports unique_ptr.h:77:5
  # (Xcode 26.x) or unique_ptr.h:81:5 (Xcode 16.4, MacOSX15.5 SDK), the
  # CommandLineTools SDK reports unique_ptr.h:75:5. Mixed pairs are rejected.
  # Nothing else is rewritten: the remaining warning text and the pinned
  # instantiation origin stay exact.
  sdk_spellings <- list(
    list(prefix = paste0("^/Applications/Xcode_[0-9.]+\\.app/Contents/Developer/Platforms/",
                         "MacOSX\\.platform/Developer/SDKs/MacOSX\\.sdk/usr/include/c\\+\\+/v1/"),
         lines = c("77", "81")),
    list(prefix = "^/Library/Developer/CommandLineTools/SDKs/MacOSX\\.sdk/usr/include/c\\+\\+/v1/",
         lines = "75"))
  for (i in seq_along(indices)) {
    spelling <- Filter(function(s) grepl(s$prefix, diagnostics[[i]]), sdk_spellings)
    if (!length(spelling)) next
    spelling <- spelling[[1L]]
    normalized <- sub(spelling$prefix, "<libc++>/", diagnostics[[i]])
    canonical <- paste0("<libc++>/__memory/unique_ptr.h:", spelling$lines, ":5: warning:")
    if (!any(startsWith(normalized, canonical))) stop("Unexpected SDK warning location")
    normalized <- sub("^<libc\\+\\+>/__memory/unique_ptr\\.h:[0-9]+:5: warning:",
                      "<libc++>/__memory/unique_ptr.h:77:5: warning:", normalized)
    attributed <- paste0(normalized,
                         " [instantiated at vendor/pstalgo/src/analyses/AttractionReach.cpp:214:6]")
    if (!identical(attributed, pst_libcpp_warning())) stop("Unexpected SDK warning")
    # Require attribution within this diagnostic, before the next warning.
    next_warning <- if (i < length(indices)) indices[[i + 1L]] - 1L else length(install)
    block <- install[indices[[i]]:min(next_warning, indices[[i]] + 12L)]
    if (sum(block == pst_libcpp_origin()) != 1L) stop("Missing pinned warning origin")
    diagnostics[[i]] <- attributed
  }
  diagnostics
}

assert_warning_multiset <- function(actual, policy, phase) {
  expected <- policy[policy$phase == phase, ]
  expected <- rep(expected$signature, expected$count)
  if (!identical(sort(actual), sort(expected))) {
    counts <- function(x) table(x)
    cat("Expected ", phase, " warning counts:\n", sep = "")
    print(counts(expected))
    cat("Observed ", phase, " warning counts:\n", sep = "")
    print(counts(actual))
    stop("Unexpected warning signature, source, type, or count in ", phase)
  }
}

# R CMD check NOTE sections. A NOTE is a "* checking <name> ... NOTE" line plus its body (every line up to the
# next "* ..." line). The Linux gate accepts only the two environmental NOTEs recorded below, each at most once, with
# the exact diagnostic body that identifies its cause, and requires the "Status:" summary to agree with the sections
# actually present. Anything else (for example "foreign function calls" registration problems, dependency, Rd or
# portability notes, or a changed body) is a package diagnostic and fails. Typographic quotes are normalised only.
pst_environmental_notes <- list(
  # No network: R cannot reach a time service to verify that file timestamps are not in the future.
  "for future file timestamps" = "unable to verify current time",
  # The conda-forge compiler toolchain injects -march=nocona into the compile flags (not set by rPSTool's Makevars).
  "compilation flags used" = c("Compilation used the following non-portable flag(s):", "  '-march=nocona'"))
pst_check_note_sections <- function(check) {
  starts <- grep("^\\* ", check)
  header <- "^\\* checking (.*) \\.\\.\\. (\\[[0-9.]+[sm](/[0-9.]+[sm])?\\] )?NOTE$"
  at <- starts[grepl(header, check[starts])]
  sections <- lapply(at, function(i) {
    end <- c(starts[starts > i], length(check) + 1L)[[1L]] - 1L
    body <- if (end > i) check[(i + 1L):end] else character()
    body <- gsub("[\u2018\u2019]", "'", sub("[[:space:]]+$", "", body))
    while (length(body) && !nzchar(body[[length(body)]])) body <- body[-length(body)]
    list(name = sub(header, "\\1", check[[i]]), body = body)
  })
  sections
}
validate_check_notes <- function(platform, check) {
  sections <- pst_check_note_sections(check)
  status <- grep("^Status:", check, value = TRUE)
  if (platform != "ubuntu") {
    if (length(sections)) stop("Unexpected R CMD check NOTE section")
    return(invisible(0L))
  }
  names <- vapply(sections, function(x) x$name, "")
  if (anyDuplicated(names)) stop("Duplicate R CMD check NOTE section")
  for (section in sections) {
    expected <- pst_environmental_notes[[section$name]]
    if (is.null(expected) || !identical(section$body, expected)) {
      stop("Unrecognised R CMD check NOTE: ", section$name)
    }
  }
  n <- length(sections)
  summary <- if (n == 0L) "Status: OK" else sprintf("Status: %d NOTE%s", n, if (n == 1L) "" else "s")
  if (!identical(status, summary)) stop("R CMD check summary does not match its NOTE sections")
  invisible(n)
}

# Package-test skips. Linux/macOS permit none. Windows permits exactly the approved inventory in
# tools/ci/windows-test-skips.tsv: the tests whose source calls skip_on_os("windows") (directly or through a helper
# defined with it), i.e. the POSIX-only result-file/publication tests and two Windows-specific path-validation
# cases. Each skip reported by testthat as 'file:line:col' under the reason "On Windows" is resolved against the
# test source to its enclosing test_that() description, which must be a skip call, and the resulting multiset must
# equal the inventory exactly. A skip for any other reason (e.g. a missing dependency), a test outside the
# inventory, a missing or extra entry, or counts that disagree with testthat's own summary fails.
read_windows_test_skips <- function(policy_dir = "tools/ci") {
  inventory <- read.delim(file.path(policy_dir, "windows-test-skips.tsv"), quote = "", comment.char = "",
                          colClasses = "character", check.names = FALSE)
  if (!identical(names(inventory), c("file", "test")) || !nrow(inventory) ||
      anyDuplicated(inventory) || any(!nzchar(unlist(inventory))) ||
      any(!grepl("^test-[A-Za-z0-9._-]+[.]R$", inventory$file))) stop("Invalid Windows skip inventory")
  inventory
}
pst_test_skip_description <- function(test_dir, file, line) {
  path <- file.path(test_dir, file)
  if (!grepl("^test-[A-Za-z0-9._-]+[.]R$", file) || !file.exists(path)) stop("Skipped test file is not a package test file: ", file)
  source <- readLines(path, warn = FALSE)
  if (line < 1L || line > length(source)) stop("Skipped test location outside its file: ", file, ":", line)
  if (!grepl("skip", source[[line]], fixed = TRUE)) stop("Skipped test location is not a skip call: ", file, ":", line)
  starts <- grep("^test_that\\(", source)
  starts <- starts[starts <= line]
  if (!length(starts)) stop("Skipped test location is outside any test_that(): ", file, ":", line)
  description <- sub("^test_that\\(\"(.*)\",[[:space:]]*(\\{.*)?$", "\\1", source[[max(starts)]])
  if (identical(description, source[[max(starts)]])) stop("Cannot read the test description at ", file, ":", max(starts))
  description
}
validate_test_skips <- function(platform, tests, skipped, policy_dir = "tools/ci", test_dir = "tests/testthat") {
  header <- grep("Skipped tests \\([0-9]+\\)", tests, useBytes = TRUE)
  if (skipped == 0L) {
    if (length(header)) stop("A skipped-test section appeared although the summary reports no skips")
    return(invisible(0L))
  }
  if (platform != "windows") stop("Skipped package tests are not permitted on ", platform)
  if (length(header) != 1L) stop("Missing or repeated skipped-test section")
  if (as.integer(sub(".*Skipped tests \\(([0-9]+)\\).*", "\\1", tests[header], useBytes = TRUE)) != skipped)
    stop("The skipped-test section disagrees with the summary count")
  rest <- tests[(header + 1L):length(tests)]
  rest <- rest[seq_len(min(c(grep("^\\[ *FAIL ", rest, useBytes = TRUE), length(rest) + 1L)) - 1L)]
  rest <- rest[nzchar(trimws(rest))]
  # testthat wraps long location lists onto indented continuation lines.
  entries <- character()
  for (line in rest) {
    if (grepl("^[[:space:]]+'", line, useBytes = TRUE) && length(entries)) entries[[length(entries)]] <- paste(entries[[length(entries)]], trimws(line))
    else entries <- c(entries, line)
  }
  pattern <- "^(.*?) \\(([0-9]+)\\): ('[^']+'(?:, '[^']+')*)$"
  if (!length(entries) || any(!grepl(pattern, entries, perl = TRUE, useBytes = TRUE))) stop("Unreadable skipped-test section")
  reasons <- sub(pattern, "\\1", entries, perl = TRUE, useBytes = TRUE)
  counts <- as.integer(sub(pattern, "\\2", entries, perl = TRUE, useBytes = TRUE))
  per_entry <- strsplit(sub(pattern, "\\3", entries, perl = TRUE, useBytes = TRUE), "', '", fixed = TRUE)
  # Only the reason "On Windows" (skip_on_os), after testthat's bullet decoration, is recognised.
  # (testthat's bullet is U+2022 in UTF-8 sessions and "*" otherwise; matched as bytes so the locale cannot matter.)
  if (any(!grepl("^(\\xe2\\x80\\xa2|[*-])? *On Windows$", reasons, perl = TRUE, useBytes = TRUE)))
    stop("Skipped tests with a reason other than 'On Windows'")
  locations <- gsub("^'|'$", "", unlist(per_entry))
  if (sum(counts) != skipped || length(locations) != skipped || any(lengths(per_entry) != counts))
    stop("Skipped-test counts are inconsistent")
  if (any(!grepl("^[^:]+:[0-9]+:[0-9]+$", locations))) stop("Malformed skipped-test location")
  file <- sub(":.*$", "", locations); line <- as.integer(sub("^[^:]+:([0-9]+):.*$", "\\1", locations))
  observed <- paste(file, mapply(pst_test_skip_description, file, line, MoreArgs = list(test_dir = test_dir)), sep = "\t")
  inventory <- read_windows_test_skips(policy_dir)
  approved <- paste(inventory$file, inventory$test, sep = "\t")
  if (!identical(sort(observed), sort(approved))) {
    stop("Skipped tests differ from the approved Windows inventory; unexpected: ",
         paste(setdiff(observed, approved), collapse = " | "), "; missing: ", paste(setdiff(approved, observed), collapse = " | "),
         if (anyDuplicated(observed)) "; duplicated entries" else "")
  }
  invisible(skipped)
}
# The package-test log of an R CMD check run: testthat.Rout on success, testthat.Rout.fail when the tests failed.
# A failed log is never returned as a result to validate; callers report it and stop.
# Test-suite mode (tests/testthat/helper-suite-mode.R, docs/testing.md). The local gate runs the FULL development suite
# (RPST_FULL_TESTS=true); RPST_FULL_TESTS=false runs the thinned CRAN-mode suite. The expectation count of the testthat summary
# line is the witness that the requested mode really ran: full must reach the recorded floor, CRAN mode must stay below it.
pst_suite_expectations <- function(tests) {
  summary <- grep("^\\[ *FAIL +[0-9]+ \\| WARN +[0-9]+ \\| SKIP +[0-9]+ \\| PASS +[0-9]+ *\\]", tests, value = TRUE)
  if (!length(summary)) stop("No testthat summary line with an expectation count in the package-test log")
  as.integer(sub(".*PASS +([0-9]+) *\\].*", "\\1", summary[[length(summary)]]))
}
pst_check_suite_mode <- function(tests, full, policy_dir = "tools/ci") {
  floor <- as.integer(readLines(file.path(policy_dir, "full-suite-floor.txt"), warn = FALSE)[[1L]])
  if (is.na(floor) || floor < 1L) stop("Invalid full-suite floor")
  passed <- pst_suite_expectations(tests)
  if (full && passed < floor)
    stop("Full development suite requested but only ", passed, " expectations passed (floor ", floor, "): cases were not all run")
  if (!full && passed >= floor)
    stop("CRAN-mode suite requested but ", passed, " expectations passed (floor ", floor, "): the suite was not thinned")
  invisible(passed)
}
pst_read_test_log <- function(check_dir) {
  ok <- file.path(check_dir, "tests", "testthat.Rout")
  fail <- file.path(check_dir, "tests", "testthat.Rout.fail")
  if (file.exists(ok) && file.exists(fail)) stop("Both testthat.Rout and testthat.Rout.fail exist; refusing to choose")
  if (file.exists(fail)) return(list(failed = TRUE, path = fail, lines = readLines(fail, warn = FALSE)))
  if (file.exists(ok)) return(list(failed = FALSE, path = ok, lines = readLines(ok, warn = FALSE)))
  stop("R CMD check produced no package-test log (neither testthat.Rout nor testthat.Rout.fail) in ", file.path(check_dir, "tests"))
}

validate_pst_check <- function(platform, install, check, tests, exit_status,
                               policy_dir = "tools/ci", test_dir = "tests/testthat", report = TRUE) {
  policy <- read_pst_warning_policy(platform, policy_dir, check)
  if (length(exit_status) != 1L || is.na(exit_status) || !exit_status %in% c(0L, 1L)) {
    stop("R CMD check execution failed")
  }
  if (any(grepl("(^ERROR|: (fatal )?error:|^Error( in|:)|^Execution halted|^make:.*Error)",
                c(install, check, tests)))) stop("Installation, check, or test error")
  # "rPST" is the former package name; the archived Windows/macOS validation logs predate the rename.
  if (sum(trimws(install) %in% c("* DONE (rPSTool)", "* DONE (rPST)")) != 1L) stop("Installation did not complete")
  if (sum(check == "* DONE") != 1L) stop("R CMD check did not complete")
  if (any(grepl("^Warning( in|:| message|s:)", c(install, tests)))) {
    stop("Unallowlisted R warning")
  }
  assert_warning_multiset(pst_compiler_warnings(install), policy, "compiler")
  other_output <- install[!grepl(": warning:", install, fixed = TRUE) &
                            !grepl("^[0-9]+ warnings? generated[.]$", install)]
  # Clang's advisory notes mention the word "warning"; admit only the exact
  # notes tied to the five already-validated pinned boolean-bitwise diagnostics.
  bitwise <- policy$signature[policy$phase == "compiler" &
                               endsWith(policy$signature, "[-Wbitwise-instead-of-logical]")]
  notes <- sub(": warning:.*$", ": note: cast one or both operands to int to silence this warning",
               bitwise)
  other_output <- other_output[!other_output %in% notes]
  if (any(grepl("(^|[[:space:]])warning(s| message(s)?)?:|^warning in|[[:space:]]WARNING$",
                other_output, ignore.case = TRUE))) {
    stop("Unrecognized installation warning output")
  }

  # Validate the entire installation-warning block, rather than dropping the
  # installation check wholesale. Any other WARNING/ERROR check still fails.
  starts <- grep("^\\* ", check)
  install_header <- grep("^\\* checking whether package .rPST(ool)?. can be installed \\.\\.\\.", check)
  if (length(install_header) != 1L) stop("Missing or repeated installation check")
  next_section <- starts[starts > install_header][[1L]]
  block <- check[install_header:(next_section - 1L)]
  # Linux and any platform whose inventory has no significant (check-phase) rows must report a clean
  # installation check; otherwise the exact significant-warning block is required.
  significant_expected <- platform != "ubuntu" && any(policy$phase == "check")
  expected_status <- if (significant_expected) "WARNING" else "OK"
  if (!endsWith(block[[1L]], paste0(" ", expected_status))) stop("Unexpected installation check status")
  if (significant_expected) {
    if (length(block) < 4L || block[[2L]] != "Found the following significant warnings:" ||
        !grepl("^See .+/00install[.]out. for details[.]$", tail(block, 1L))) {
      stop("Unexpected installation warning block")
    }
    diagnostics <- block[3L:(length(block) - 1L)]
    if (any(!startsWith(diagnostics, "  "))) stop("Unexpected check warning text")
    assert_warning_multiset(sub("^  ", "", diagnostics), policy, "check")
  } else if (length(block) != 1L) stop("Unexpected installation check output")
  # A clean macOS/Windows check (no significant warnings admitted) must also exit 0; exit status 1 is the
  # WARNING exit and is only legitimate while the inventory still admits significant diagnostics.
  if (platform != "ubuntu" && !significant_expected && exit_status != 0L) {
    stop("Clean macOS/Windows check requires exit status 0")
  }
  remaining <- check[-seq.int(install_header, next_section - 1L)]
  # The only permitted WARNING outside the validated block is its exact status summary. On Linux the summary must
  # also agree with the NOTE sections actually present, and only the recorded environmental NOTEs are admitted
  # (validate_check_notes); on macOS/Windows no NOTE section is admitted at all.
  validate_check_notes(platform, check)
  status <- grep("^Status:", remaining, value = TRUE)
  if (length(status) != 1L || (significant_expected && status != "Status: 1 WARNING") ||
      (platform != "ubuntu" && !significant_expected && status != "Status: OK")) {
    stop("Unexpected R CMD check summary")
  }
  summary <- status  # on Linux already proven equal to "Status: OK" / "Status: N NOTE(s)" by validate_check_notes
  remaining <- remaining[remaining != summary]
  if (any(grepl("(^|[[:space:]])(warning(s| message(s)?)?|error)(:|$)|^warning in",
                remaining, ignore.case = TRUE))) {
    stop("Unallowlisted R CMD check warning/error")
  }
  test_header <- grep("^\\* checking tests \\.\\.\\.", check)
  if (length(test_header) != 1L) stop("Missing or repeated package test check")
  end <- starts[starts > test_header][[1L]]
  test_block <- trimws(check[test_header:(end - 1L)])
  if (!any(test_block == "OK" |
           grepl("^\\* checking tests \\.\\.\\. (\\[[0-9]+([.][0-9]+)?[sm](/[0-9]+([.][0-9]+)?[sm])?\\] )?OK$", test_block))) {
    stop("Package tests did not pass")
  }
  summary_pattern <- "^\\[ *FAIL 0 \\| *WARN 0 \\| *SKIP ([0-9]+) \\| *PASS [1-9][0-9]* *\\]$"
  passed <- grep(summary_pattern, tests, value = TRUE)
  # testthat prints its summary line once, and again after a skipped-test section.
  if (!length(passed) %in% c(1L, 2L) || length(unique(passed)) != 1L ||
      any(grepl("\\[ *FAIL [1-9]|\\| *WARN [1-9]", tests))) {
    stop("Package test failures/warnings or missing test results")
  }
  skipped <- as.integer(sub(summary_pattern, "\\1", passed[[1L]]))
  validate_test_skips(platform, tests, skipped, policy_dir, test_dir)
  if (isTRUE(report)) {
    message("Exact PST warning policy passed on ", platform, ": ",
            sum(policy$count[policy$phase == "compiler"]), " compiler diagnostics; ",
            sum(policy$count[policy$phase == "check"]), " significant diagnostics; all other checks strict")
  }
  invisible(TRUE)
}
