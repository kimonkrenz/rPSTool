#!/usr/bin/env Rscript
# Fixtures are diagnostic/check excerpts from run 37528060812 at 6dcbefde5239.
# Reject regressions in every signature/count plus non-compiler failure paths.
source("tools/ci/pst-warning-policy.R")
# The excerpts below are OBSERVED logs from before the diagnostic build-copy fixes (patch 0011) removed the fixable
# diagnostics, so they are validated against the preserved earlier inventories. A scratch policy directory is
# the live tools/ci content with only the three warning inventories replaced by their earlier copies.
live_policy_dir <- "tools/ci"
earlier_policy_dir <- tempfile("pre-diagnostic-fix-inventories-"); dir.create(earlier_policy_dir)
invisible(file.copy(list.files(live_policy_dir, pattern = "[.](tsv|txt)$", full.names = TRUE), earlier_policy_dir))
stopifnot(file.copy(Sys.glob("tools/ci/fixtures/pre-diagnostic-fix-inventories/*.tsv"), earlier_policy_dir, overwrite = TRUE))
formals(read_pst_warning_policy)$policy_dir <- earlier_policy_dir
formals(validate_pst_check)$policy_dir <- earlier_policy_dir
read_fixture <- function(platform, suffix) {
  # The combined isovist safety copy restores the original vendor diagnostic
  # path with #line. Migrate only this spelling in the earlier excerpts;
  # diagnostic text, coordinates and counts remain exact and fully checked.
  lines <- sub(".rpst-build/analyses/CalculateIsovists.cpp",
      "vendor/pstalgo/src/analyses/CalculateIsovists.cpp",
      readLines(file.path("tools/ci/fixtures", paste0(platform, "-", suffix)), warn=FALSE),
      fixed=TRUE)
  # The earlier macOS install excerpt predates the pst-graph.cpp wrapper,
  # which includes pstalgo/graph/AxialGraph.h; every includer of that header
  # emits one exact diagnostic (13 translation units, not the earlier 12).
  if (platform == "macos" && suffix == "install.out") {
    axial <- grep("graph/AxialGraph.h:26:10: warning:", lines, fixed = TRUE)
    lines <- append(lines, lines[[axial[[1L]]]], after = axial[[1L]])
  }
  lines
}
rejections <- 0L
reject <- function(expression) {
  error <- NULL
  invisible(capture.output(error <- tryCatch({force(expression); NULL}, error = identity)))
  if (!inherits(error, "error")) stop("Warning policy accepted a forbidden result")
  rejections <<- rejections + 1L
}
for (platform in c("macos", "windows")) {
  install <- read_fixture(platform, "install.out")
  check <- read_fixture(platform, "check.log")
  tests <- read_fixture(platform, "tests.Rout")
  validate <- function(i = install, c = check, t = tests, status = 1L) {
    validate_pst_check(platform, i, c, t, status)
  }
  validate()
  # R CMD check may report one or two seconds/minutes fields in the successful header.
  for (timing in c("14s", "0.5s", "23s/23s", "0.5s/1.2s",
                   "0s", "0s/0s", "0s/1.2s", "0.5s/0s",
                   "13m", "0.5m", "13m/13m", "0.5m/1.2m", "0m", "0m/0m",
                   "13m/23s", "23s/13m", "0.5m/1.2s", "0.5s/1.2m",
                   "0m/1.2s", "0.5s/0m")) {
    timed <- sub("* checking tests ... OK",
                 paste0("* checking tests ... [", timing, "] OK"), check, fixed = TRUE)
    validate(c = timed)
    reject(validate(c = timed, t = sub("FAIL 0", "FAIL 1", tests, fixed = TRUE)))
    reject(validate(c = timed, t = sub("WARN 0", "WARN 1", tests, fixed = TRUE)))
    reject(validate(c = timed, t = character()))
  }
  malformed <- c("[14s]", "[14s] NOT OK", "[14s] ERROR", "[14s] WARNING",
                   "[14s] OK trailing", "[xs] OK", "[14] OK", "[-14s] OK",
                   "[0.5s/1.2s]", "[23s/23s] NOT OK", "[23s/23s] ERROR",
                   "[23s/23s] WARNING", "[0.5s/1.2s] OK trailing",
                   "[23s/23s OK", "23s/23s] OK", "[[23s/23s]] OK",
                   "[23/23s] OK", "[23s/23] OK", "[-23s/23s] OK",
                   "[23s/-23s] OK", "[1s/2s/3s] OK", "[/23s] OK",
                   "[23s/] OK", "[] OK", "[.5s/1.2s] OK", "[0.5s/1.s] OK",
                   "[1..2s/3s] OK", "[1s/2..3s] OK", "[1s//2s] OK",
                   "[1s /2s] OK", "[1e2s/3s] OK", "[+1s/2s] OK",
                   "[13h/13m] OK", "[13m/13h] OK", "[13ms/13m] OK",
                   "[13m/13ms] OK", "[13M/13m] OK", "[13m/13M] OK")
  # Apply the same malformed-number, delimiter and status mutations to minute
  # and mixed-unit forms; changing units must not broaden any other syntax.
  for (result in unique(c(malformed, gsub("s", "m", malformed, fixed = TRUE),
                         sub("s", "m", malformed, fixed = TRUE)))) {
    reject(validate(c = sub("* checking tests ... OK",
                            paste0("* checking tests ... ", result), check, fixed = TRUE)))
  }
  # Multiset validation is independent of parallel compiler ordering.
  policy <- read_pst_warning_policy(platform)
  diagnostics <- pst_compiler_warnings(install)
  assert_warning_multiset(rev(diagnostics), policy, "compiler")
  for (signature in unique(diagnostics)) {
    at <- match(signature, diagnostics)
    reject(assert_warning_multiset(diagnostics[-at], policy, "compiler"))
    reject(assert_warning_multiset(c(diagnostics, signature), policy, "compiler"))
  }
  significant <- sub("^  ", "", grep(": warning:", check, value = TRUE, fixed = TRUE))
  for (signature in unique(significant)) {
    at <- match(signature, significant)
    reject(assert_warning_multiset(significant[-at], policy, "check"))
    reject(assert_warning_multiset(c(significant, signature), policy, "check"))
  }
  first <- grep(": warning:", install, fixed = TRUE)[[1L]]
  for (replacement in c("native-smoke.cpp:1:1: warning: new rPSTool warning [-Wswitch]",
                        sub("\\[-W[^]]+\\]", "[-Wnew-warning]", install[[first]]),
                        sub(": warning:", ": warning: changed", install[[first]], fixed = TRUE),
                        sub(":([0-9]+):([0-9]+): warning:", ":999:999: warning:", install[[first]]))) {
    changed <- install
    changed[[first]] <- replacement
    reject(validate(i = changed))
  }
  reject(validate(i = c(install, "native-smoke.cpp:2:1: warning: new warning [-Wunused-variable]")))
  reject(validate(i = c(install, "WARNING: unrecognized compiler output")))
  reject(validate(i = c(install, "Warning message:", "rPSTool warning")))
  reject(validate(i = c(install, "native-smoke.cpp:1:1: error: failure")))
  reject(validate(i = install[!install %in% c("* DONE (rPSTool)", "* DONE (rPST)")]))
  reject(validate(c = check[check != "* DONE"]))
  reject(validate(c = c(check, "* checking rPSTool ... WARNING")))
  reject(validate(c = sub("Status: 1 WARNING", "Status: 2 WARNINGs", check, fixed = TRUE)))
  reject(validate(c = sub("Found the following significant warnings:", "Unknown warning", check, fixed = TRUE)))
  reject(validate(c = sub("can be installed", "can NOT be installed", check, fixed = TRUE)))
  reject(validate(c = sub("* checking tests ...", "* checking tests ... ERROR", check, fixed = TRUE)))
  reject(validate(t = sub("FAIL 0", "FAIL 1", tests, fixed = TRUE)))
  reject(validate(t = sub("WARN 0", "WARN 1", tests, fixed = TRUE)))
  reject(validate(t = sub("SKIP 0", "SKIP 1", tests, fixed = TRUE)))
  reject(validate(t = c(tests, "Warning in rPSTool(): new warning")))
  reject(validate(t = character()))
  reject(validate(status = 2L))
  reject(validate(status = NA_integer_))
  if (platform == "macos") {
    reject(validate(i = install[install != pst_libcpp_origin()]))
    reject(validate(i = sub("AttractionReach.cpp:214:6: note:",
                            "native-smoke.cpp:214:6: note:", install, fixed = TRUE)))
  }
}
# macOS SDK 27 (CommandLineTools libc++) compatibility: exact additions only.
macos_install <- read_fixture("macos", "install.out")
macos_check <- read_fixture("macos", "check.log")
macos_tests <- read_fixture("macos", "tests.Rout")
nodiscard <- c(
  "vendor/pstalgo/src/analyses/AngularChoiceAlgo.cpp:464:9: warning: ignoring return value of function declared with 'nodiscard' attribute [-Wunused-result]",
  "vendor/pstalgo/src/analyses/SegmentBetweenness.cpp:618:10: warning: ignoring return value of function declared with 'nodiscard' attribute [-Wunused-result]")
sdk27 <- function(install = macos_install, check = macos_check, extras = nodiscard, sdk = "MacOSX27.0.sdk",
                  clt = TRUE, line = "75") {
  if (clt) {
    install <- sub("^/Applications/Xcode_[0-9.]+[.]app/Contents/Developer/Platforms/MacOSX[.]platform/Developer/SDKs/MacOSX[.]sdk/",
                   "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/", install)
    install <- sub("__memory/unique_ptr.h:77:5: warning:", paste0("__memory/unique_ptr.h:", line, ":5: warning:"), install, fixed = TRUE)
  }
  install <- c(install, extras)
  significant <- grep("^  vendor/", check)
  check <- append(check, paste0("  ", extras), after = max(significant))
  check <- sub("^(\\* used SDK: .)MacOSX[0-9.]+[.]sdk", paste0("\\1", sdk), check)
  list(install = install, check = check)
}
accepted <- sdk27()
bad <- function(x) validate_pst_check("macos", x$install, x$check, macos_tests, 1L)
validate_pst_check("macos", accepted$install, accepted$check, macos_tests, 1L)
# Exactly two libc++ spellings: Xcode root + line 77, CommandLineTools root + line 75.
validate_pst_check("macos", macos_install, macos_check, macos_tests, 1L)
validate_pst_check("macos", sdk27(clt = TRUE, line = "75")$install, accepted$check, macos_tests, 1L)
validate_pst_check("macos", sdk27(clt = FALSE)$install, accepted$check, macos_tests, 1L)
# Mixed pairs are rejected in both directions.
xcode_75 <- sdk27(clt = FALSE); xcode_75$install <- sub("unique_ptr.h:77:5: warning:", "unique_ptr.h:75:5: warning:", xcode_75$install, fixed = TRUE)
reject(bad(xcode_75))
clt_77 <- sdk27(clt = TRUE, line = "77")
reject(bad(clt_77))
# The nodiscard pair is required on SDK 27 and forbidden on every other toolchain.
reject(bad(sdk27(sdk = "MacOSX26.5.sdk")))
reject(bad(list(install = c(macos_install, nodiscard), check = macos_check)))
reject(bad(sdk27(extras = nodiscard[1L])))
reject(bad(sdk27(extras = rep(nodiscard[1L], 2L))))
reject(bad(sdk27(extras = sub(":464:9:", ":465:9:", nodiscard, fixed = TRUE))))
reject(bad(sdk27(extras = sub("nodiscard", "deprecated", nodiscard, fixed = TRUE))))
reject(bad(sdk27(extras = sub("-Wunused-result", "-Wother", nodiscard, fixed = TRUE))))
reject(bad(sdk27(extras = c(nodiscard, "vendor/pstalgo/src/Limits.cpp:1:1: warning: x [-Wunused-result]"))))
# SDK 27 additions cannot hide a missing earlier diagnostic or a count change.
missing <- accepted; missing$install <- missing$install[-grep("AxialGraph.h:26:10", missing$install)[[1L]]]
reject(bad(missing))
extra_axial <- accepted
extra_axial$install <- c(extra_axial$install, grep("AxialGraph.h:26:10", extra_axial$install, value = TRUE)[[1L]])
reject(bad(extra_axial))
# The CommandLineTools unique_ptr normaliser stays exact: line, prefix, text, origin.
reject(bad(sdk27(line = "76")))
reject(bad(sdk27(line = "78")))
broken <- accepted
broken$install <- sub("/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/", "/Library/Developer/CommandLineTools/SDKs/Other.sdk/", broken$install, fixed = TRUE)
reject(bad(broken))
broken <- accepted
broken$install <- sub("non-virtual destructor", "virtual destructor", broken$install, fixed = TRUE)
reject(bad(broken))
broken <- accepted
broken$install <- broken$install[broken$install != pst_libcpp_origin()]
reject(bad(broken))
broken <- accepted
broken$install <- sub("AttractionReach.cpp:214:6: note:", "AttractionReach.cpp:215:6: note:", broken$install, fixed = TRUE)
reject(bad(broken))
ubuntu_install <- "* DONE (rPSTool)"
ubuntu_check <- c("* checking whether package 'rPSTool' can be installed ... OK",
                  "* checking tests ... OK", "* DONE", "Status: OK")
ubuntu_tests <- "[ FAIL 0 | WARN 0 | SKIP 0 | PASS 13 ]"
validate_pst_check("ubuntu", ubuntu_install, ubuntu_check, ubuntu_tests, 0L)
reject(validate_pst_check("ubuntu", c(ubuntu_install,
       "vendor/pstalgo/src/Limits.cpp:161:16: warning: enumeration value '_DIST_COUNT' not handled in switch [-Wswitch]"),
       ubuntu_check, ubuntu_tests, 0L))
reject(validate_pst_check("other", ubuntu_install, ubuntu_check, ubuntu_tests, 0L))

# Linux NOTE policy. The excerpts are the verbatim NOTE sections of the retained Linux R CMD check logs of an earlier run
# (R 4.4, conda-forge toolchain, no network); every other section is an ordinary "... OK" line.
time_note <- c("* checking for future file timestamps ... NOTE", "unable to verify current time")
flag_note <- c("* checking compilation flags used ... NOTE", "Compilation used the following non-portable flag(s):",
               "  \u2018-march=nocona\u2019")
registration_note <- c(
  "* checking foreign function calls ... NOTE", "Registration problems:",
  "  call includes ..., expected 15 parameters:",
  "   .Call(C_rpst_attraction_distance_stream, ptr, radius, origin, ",
  "       distance, attraction_points, points_per_polygon, polygon_point_interval, ",
  "       line_weights, point_edge_weight, destination_indices, stream, ", "       ...)",
  "  call includes ..., expected 17 parameters:",
  "   .Call(C_rpst_attraction_reach_stream, ptr, radius, origin, distance, ",
  "       attraction_points, points_per_polygon, polygon_point_interval, ",
  "       attraction_values, decay, decay_constant, distribution, collection, ", "       stream, ...)",
  "  call includes ..., expected 7 parameters:", "   .Call(C_rpst_network_integration_stream, ptr, steps, stream, ",
  "       ...)",
  "  call includes ..., expected 12 parameters:",
  "   .Call(C_rpst_od_betweenness_stream, ptr, origins, radius, distance, ",
  "       destination_mode, origin_weights, destination_weights, stream, ", "       ...)",
  "  call includes ..., expected 8 parameters:", "   .Call(C_rpst_reach_points_stream, ptr, radius, origins, stream, ",
  "       ...)", "See chapter \u2018System and foreign language interfaces\u2019 in the \u2018Writing R",
  "Extensions\u2019 manual.")
# A Linux check log with the given NOTE sections in R's order and the given summary (default: the correct one).
linux_check <- function(time = FALSE, registration = FALSE, flags = FALSE, extra = list(), status = NULL) {
  sections <- c(if (time) list(time_note), if (registration) list(registration_note), if (flags) list(flag_note), extra)
  n <- length(sections)
  if (is.null(status)) status <- if (n == 0L) "Status: OK" else sprintf("Status: %d NOTE%s", n, if (n == 1L) "" else "s")
  c("* using log directory \u2018/tmp/rPST.Rcheck\u2019", "* checking whether package \u2018rPST\u2019 can be installed ... OK",
    if (time) time_note else "* checking for future file timestamps ... OK",
    "* checking DESCRIPTION meta-information ... OK",
    if (registration) registration_note else "* checking foreign function calls ... OK",
    "* checking R code for possible problems ... OK",
    if (flags) flag_note else "* checking compilation flags used ... OK",
    unlist(extra), "* checking compiled code ... OK", "* checking tests ... OK",
    "* checking for detritus in the temp directory ... OK", "* DONE", "", status,
    if (!identical(status, "Status: OK")) c("See", "  \u2018/tmp/rPST.Rcheck/00check.log\u2019", "for details."))
}
linux <- function(check) validate_pst_check("ubuntu", ubuntu_install, check, ubuntu_tests, 0L)
# Accepted: no NOTE; each verified environmental NOTE alone; both together; ASCII quotes; timing field.
linux(linux_check())
linux(linux_check(time = TRUE))
linux(linux_check(flags = TRUE))
linux(linux_check(time = TRUE, flags = TRUE))
linux(sub("\u2018-march=nocona\u2019", "'-march=nocona'", linux_check(flags = TRUE), fixed = TRUE))
linux(sub("flags used ... NOTE", "flags used ... [1s] NOTE", linux_check(flags = TRUE), fixed = TRUE))
# An earlier defect: the foreign-function registration NOTE is rejected on its own and inside the exact report
# that was wrongly accepted ("Status: 3 NOTEs": registration + both environmental NOTEs).
reject(linux(linux_check(registration = TRUE)))
reject(linux(linux_check(time = TRUE, registration = TRUE, flags = TRUE)))
reject(linux(linux_check(time = TRUE, registration = TRUE, flags = TRUE, status = "Status: 2 NOTEs")))
# Unknown NOTEs, even with a consistent count.
for (unknown in list(c("* checking CRAN incoming feasibility ... NOTE", "Maintainer: 'A <a@b.c>'"),
                     c("* checking dependencies in R code ... NOTE", "Namespace in Imports field not imported from: 'x'"),
                     c("* checking for missing documentation entries ... NOTE", "Undocumented code objects:", "  'f'"),
                     c("* checking installed package size ... NOTE", "  installed size is 7.0Mb"),
                     c("* checking for portable file names ... NOTE", "Found the following non-portable file path:"),
                     c("* checking for future file timestamps ... NOTE", "unable to verify current time", "extra line"))) {
  reject(linux(linux_check(extra = list(unknown))))
  reject(linux(linux_check(time = TRUE, flags = TRUE, extra = list(unknown))))
}
# Changed names or contents of the two accepted sections.
mutate <- function(check, from, to) { out <- sub(from, to, check, fixed = TRUE); stopifnot(!identical(out, check)); out }
reject(linux(mutate(linux_check(time = TRUE), "unable to verify current time", "unable to verify the current time")))
reject(linux(mutate(linux_check(time = TRUE), "unable to verify current time",
                    "Found the following files/directories:")))
reject(linux(mutate(linux_check(time = TRUE), "for future file timestamps ... NOTE", "for future timestamps ... NOTE")))
reject(linux(mutate(linux_check(flags = TRUE), "-march=nocona", "-march=native")))
reject(linux(mutate(linux_check(flags = TRUE), "-march=nocona\u2019", "-march=nocona -mtune=generic\u2019")))
reject(linux(mutate(linux_check(flags = TRUE), "non-portable flag(s):", "non-portable flags:")))
reject(linux(mutate(linux_check(flags = TRUE), "compilation flags used ... NOTE", "compilation flags ... NOTE")))
reject(linux(append(linux_check(flags = TRUE), "  \u2018-Ofast\u2019", after = grep("nocona", linux_check(flags = TRUE)))))
# Count mismatches, wrong plurals, missing/duplicate/zero summaries.
for (wrong in c("Status: OK", "Status: 1 NOTE", "Status: 3 NOTEs", "Status: 2 NOTE", "Status: 0 NOTEs", "Status: 2 NOTEs ",
                "Status: 1 NOTEs", "Status: 1 WARNING", "Status: 2 WARNINGs", "Status: 1 NOTE, 1 WARNING"))
  reject(linux(linux_check(time = TRUE, flags = TRUE, status = wrong)))
for (wrong in c("Status: 1 NOTE", "Status: 2 NOTEs", "Status: 1 WARNING"))
  reject(linux(linux_check(status = wrong)))                          # summary claims a NOTE that is not there
reject(linux(linux_check(time = TRUE, status = "Status: OK")))        # NOTE section without its summary
reject(linux(grep("^Status:", linux_check(time = TRUE), value = TRUE, invert = TRUE)))   # no summary at all
reject(linux(c(linux_check(time = TRUE), "Status: 1 NOTE")))          # duplicate summaries
# Duplicate NOTE sections, with the count agreeing.
reject(linux(linux_check(time = TRUE, extra = list(time_note))))
reject(linux(linux_check(flags = TRUE, extra = list(flag_note))))
# Warnings and errors still fail on Linux, alone or beside accepted NOTEs.
base <- linux_check(time = TRUE, flags = TRUE)
for (bad_section in list("* checking Rd files ... WARNING", "* checking for hidden files and directories ... ERROR",
                         c("* checking S3 generic/method consistency ... WARNING", "Warning: foo"))) {
  with_bad <- append(base, bad_section, after = grep("checking compiled code", base) - 1L)
  for (status in c("Status: 2 NOTEs", "Status: 1 WARNING", "Status: 1 ERROR", "Status: 1 WARNING, 2 NOTEs", "Status: OK"))
    reject(linux(replace(with_bad, grep("^Status:", with_bad), status)))
}
# The environmental NOTE allowances never apply to the other platforms: neither as a bare section nor with a
# plausible "WARNING + NOTE" summary.
for (platform in c("macos", "windows")) {
  check <- read_fixture(platform, "check.log")
  at <- grep("^\\* DONE$", check)
  for (note in list(time_note, flag_note, registration_note)) {
    with_note <- append(check, note, after = at - 1L)
    reject(validate_pst_check(platform, read_fixture(platform, "install.out"), with_note,
                              read_fixture(platform, "tests.Rout"), 1L))
    with_note[grep("^Status:", with_note)] <- "Status: 1 WARNING, 1 NOTE"
    reject(validate_pst_check(platform, read_fixture(platform, "install.out"), with_note,
                              read_fixture(platform, "tests.Rout"), 1L))
  }
}

# ---- Package-test skips (Windows inventory) --------------------------------------------------------------------
# The approved inventory is derived from the test SOURCES (tests calling skip_on_os("windows"), directly or through a
# helper defined with it) and must equal tools/ci/windows-test-skips.tsv: a new Windows-only skip cannot be added
# without a reviewed inventory change, and a stale entry cannot linger.
windows_skip_scan <- function(test_dir = "tests/testthat") {
  out <- NULL
  skip_os <- "skip_on_os\\(.*windows"   # skip_on_os("windows"), skip_on_os('windows'), skip_on_os(c("windows", "mac")), ...
  helper_def <- "^[A-Za-z.][A-Za-z0-9._]* <- function"
  # A helper is ANY top-level function definition whose body calls skip_on_os() for Windows, whatever it is called and
  # whichever file defines it (helper-*.R included): a helper that merely avoids a `skip_` name prefix cannot hide its tests.
  # Its call sites must still contain "skip", which pst_test_skip_description() verifies, so an unrecognisable helper name fails
  # closed instead of passing.
  files <- list.files(test_dir, "^(test|helper)-.*[.]R$", full.names = TRUE)
  helpers <- character()
  for (path in files) {
    source <- readLines(path, warn = FALSE)
    starts <- grep(helper_def, source)
    boundary <- c(starts, grep("^test_that\\(", source), length(source) + 1L)
    for (h in starts) {
      body <- source[h:(min(boundary[boundary > h]) - 1L)]
      if (any(grepl(skip_os, body))) helpers <- c(helpers, sub(" <- function.*$", "", source[[h]]))
    }
  }
  call_pattern <- c(skip_os, if (length(helpers)) paste0("(^|[^A-Za-z0-9._])", gsub(".", "[.]", helpers, fixed = TRUE), "\\("))
  for (path in grep("/test-", files, value = TRUE)) {
    source <- readLines(path, warn = FALSE)
    helper_starts <- grep(helper_def, source)
    tests <- grep("^test_that\\(", source)
    for (t in tests) {
      # a test body ends at the next test or at the next top-level helper definition (a helper's own skip_on_os line is a
      # definition, not a call, and must not be charged to the test above it)
      next_test <- c(tests[tests > t], helper_starts[helper_starts > t], length(source) + 1L)
      body_lines <- t:(min(next_test) - 1L)
      hit <- body_lines[vapply(body_lines, function(i) any(vapply(call_pattern, grepl, NA, source[[i]])), NA)]
      if (length(hit)) {
        line <- hit[[1L]]
        col <- regexpr("skip", source[[line]], fixed = TRUE)[[1L]]
        out <- rbind(out, data.frame(file = basename(path), line = line, col = col,
                                     test = pst_test_skip_description(test_dir, basename(path), line)))
      }
    }
  }
  out
}
scan <- windows_skip_scan()
inventory <- read_windows_test_skips()
expected_windows_skips <- 4L   # the POSIX-only device/FIFO path checks (2) and the two RLIMIT_FSIZE full-disk tests (2); a change must be a reviewed edit
stopifnot(nrow(scan) == expected_windows_skips, nrow(inventory) == expected_windows_skips,
          identical(sort(paste(scan$file, scan$test, sep = "\t")), sort(paste(inventory$file, inventory$test, sep = "\t"))))
stopifnot(!any(duplicated(scan[c("file", "test")])))
# Result-file writing is implemented on Windows, so none of the multi-radius file-output tests may be Windows-skipped any more
# (their skip helpers no longer call skip_on_os()): a reintroduced Windows skip there would be a regression of the feature.
for (file in c("test-multi-radius.R", "test-multi-radius-direct.R", "test-multi-radius-parquet.R", "test-result-file.R", "test-result-axial.R",
               "test-result-grouping.R", "test-result-masked-analyses.R", "test-result-publication.R", "test-result-stream.R",
               "test-angular-controls.R", "test-attraction-decay-default.R"))
  stopifnot(sum(scan$file == file) == 0L)
# The scanner itself: a helper is recognised by its body whatever it is called; an unrecognisable call site fails closed;
# a helper's own definition line is not charged to the test above it.
scan_dir <- function(lines) {
  dir <- tempfile("scan-"); dir.create(dir); writeLines(lines, file.path(dir, "test-x.R")); dir
}
scan_case <- function(name, call = paste0(name, "()"), helper_first = TRUE) {
  helper <- sprintf('%s <- function() { skip_on_os("windows"); skip_if_not_installed("sf") }', name)
  test <- c('test_that("hidden skip", {', paste0("  ", call), "  expect_true(TRUE)", "})")
  other <- c('test_that("plain test", {', "  expect_true(TRUE)", "})")
  scan_dir(if (helper_first) c(helper, "", test, other) else c(other, helper, "", test))
}
for (name in c("skip_x", "mr_skip_fgb", "skip_multi_parquet")) for (first in c(TRUE, FALSE)) {
  found <- windows_skip_scan(scan_case(name, helper_first = first))
  stopifnot(nrow(found) == 1L, identical(found$test, "hidden skip"))
}
reject(windows_skip_scan(scan_case("guard_fgb")))                 # a call site without "skip" in it cannot be classified: fail closed
# more shapes the scan must recognise: call arguments, vector/single-quoted OS lists, helpers in helper-*.R, name look-alikes
shape_dir <- function(test_lines, helper_lines = NULL) {
  dir <- scan_dir(test_lines)
  if (!is.null(helper_lines)) writeLines(helper_lines, file.path(dir, "helper-x.R"))
  dir
}
stopifnot(nrow(windows_skip_scan(shape_dir(c('skip_a <- function(x) { skip_on_os("windows") }', 'test_that("t", {', "  skip_a(1)", "})")))) == 1L,
          nrow(windows_skip_scan(shape_dir(c('test_that("t", {', "  skip_on_os(c('windows', 'mac'))", "})")))) == 1L,
          nrow(windows_skip_scan(shape_dir(c('test_that("t", {', "  skip_on_os('windows')", "})")))) == 1L,
          nrow(windows_skip_scan(shape_dir(c('test_that("t", {', "  skip_shared()", "})"), 'skip_shared <- function() skip_on_os("windows")'))) == 1L,
          is.null(windows_skip_scan(shape_dir(c('test_that("t", {', "  my_skip_shared()", "})"), 'skip_shared <- function() skip_on_os("windows")'))),
          is.null(windows_skip_scan(shape_dir(c('test_that("t", {', "  skip_on_os(\"mac\")", "})")))))
reject(windows_skip_scan(shape_dir(c('test_that("t", {', "  guard_shared()", "})"), 'guard_shared <- function() skip_on_os("windows")')))  # unrecognisable call site
stopifnot(is.null(windows_skip_scan(scan_dir(c('skip_x <- function() { skip_on_os("windows") }', 'test_that("a", {', "  expect_true(TRUE)", "})")))))

win_install <- read_fixture("windows", "install.out"); win_check <- read_fixture("windows", "check.log")
win_tests <- read_fixture("windows", "tests.Rout")
locations <- sprintf("%s:%d:%d", scan$file, scan$line, scan$col)
summary_line <- function(skip, fail = 0, warn = 0) sprintf("[ FAIL %d | WARN %d | SKIP %d | PASS 149322 ]", fail, warn, skip)
# A windows test log with testthat's skipped-test section (wrapped like testthat does), then the summary again.
skip_log <- function(locs = locations, reason = "On Windows", bullet = "•", count = length(locs),
                     declared = length(locs), summary = length(locs), twice = TRUE, fail = 0, warn = 0, extra = character(),
                     decoration = "══") {
  entry <- strwrap(sprintf("%s %s (%d): %s", bullet, reason, count, paste0("'", locs, "'", collapse = ", ")),
                   width = 78, exdent = 2)
  section <- c(if (twice) summary_line(summary, fail, warn), "",
               sprintf("%s Skipped tests (%d) %s", decoration, declared, strrep(decoration, 20)), entry, extra, "",
               summary_line(summary, fail, warn))
  at <- grep("^\\[ FAIL", win_tests)
  c(win_tests[seq_len(at - 1L)], section, win_tests[-seq_len(at)])
}
winval <- function(tests, ...) validate_pst_check("windows", win_install, win_check, tests, 1L, ...)
# Accepted: the exact approved inventory, in any order, with testthat's decoration variants and one or two summaries.
winval(skip_log())
winval(skip_log(rev(locations)))
winval(skip_log(bullet = "*", decoration = "=="))
winval(skip_log(bullet = "-", decoration = ""))
winval(skip_log(twice = FALSE))
# Rejected: counts, content and reasons that deviate from the approved inventory.
reject(winval(skip_log(summary = length(locations) - 1L)))                                   # summary disagrees with the section
reject(winval(skip_log(declared = length(locations) + 1L)))
reject(winval(skip_log(count = length(locations) - 1L)))
reject(winval(skip_log(locations[-1L])))                                  # a skip missing from the inventory
reject(winval(skip_log(locations[-(1:5)])))
reject(winval(skip_log(c(locations, locations[[1L]]))))                    # a repeated location
reject(winval(skip_log(c(locations[-1L], locations[[2L]]))))               # one test twice, another absent
extra_skip <- grep("skip_flatgeobuf()", readLines("tests/testthat/test-flatgeobuf.R"), fixed = TRUE)[[1L]]
reject(winval(skip_log(c(locations, sprintf("test-flatgeobuf.R:%d:3", extra_skip)))))            # a new skip, reason "On Windows"
reject(winval(skip_log(c(locations[-1L], sprintf("test-flatgeobuf.R:%d:3", extra_skip)))))       # swapped for a different test
reject(winval(skip_log(c(locations[-1L], "test-flatgeobuf.R:1:1"))))                              # not a skip call
reject(winval(skip_log(c(locations[-1L], "test-flatgeobuf.R:99999:1"))))                          # outside the file
reject(winval(skip_log(c(locations[-1L], "test-nonexistent.R:3:3"))))
reject(winval(skip_log(c(locations[-1L], "../DESCRIPTION:3:3"))))
reject(winval(skip_log(c(locations[-1L], "test-flatgeobuf.R:three:3"))))
for (reason in c("On Linux", "On Windows and Linux", "{arrow} is not installed", "On macOS", "On Windows (ARM)", "", "Windows"))
  reject(winval(skip_log(reason = reason)))
reject(winval(skip_log(extra = "• {sf} is not installed (1): 'test-flatgeobuf.R:5:3'")))     # extra reason group
reject(winval(skip_log(extra = "• On Windows (1): 'test-flatgeobuf.R:5:3'")))                # extra group, same reason
reject(winval(skip_log()[-grep("Skipped tests", skip_log())]))                                  # SKIP 31 without the section
reject(winval(sub("SKIP 0", paste("SKIP", length(locations)), win_tests, fixed = TRUE)))
reject(winval(sub(paste("SKIP", length(locations)), "SKIP 0", skip_log(), fixed = TRUE)))                              # section without skips
reject(winval(skip_log(fail = 1L)))
reject(winval(skip_log(warn = 1L)))
reject(winval(c(skip_log(), summary_line(length(locations)))))                                              # three summary lines
reject(winval(c(skip_log(), sprintf("[ FAIL 0 | WARN 0 | SKIP %d | PASS 149322 ]", length(locations) - 1L))))                  # conflicting summaries
# Linux and macOS never permit a skip, with or without an inventory-shaped section.
for (platform in c("ubuntu", "macos")) {
  check <- if (platform == "macos") macos_check else ubuntu_check
  install <- if (platform == "macos") macos_install else ubuntu_install
  tests <- if (platform == "macos") macos_tests else ubuntu_tests
  line <- grep("^\\[ FAIL", tests)[[1L]]
  with_skips <- c(tests[seq_len(line - 1L)], skip_log()[grep("Skipped tests", skip_log()) + 0:2], summary_line(length(locations)), tests[-seq_len(line)])
  reject(validate_pst_check(platform, install, check, with_skips, if (platform == "ubuntu") 0L else 1L))
  reject(validate_pst_check(platform, install, check, sub("SKIP 0", "SKIP 1", tests, fixed = TRUE), if (platform == "ubuntu") 0L else 1L))
  reject(validate_pst_check(platform, install, check, c(tests, "══ Skipped tests (0) ══"), if (platform == "ubuntu") 0L else 1L))
}
# Inventory file integrity: removal, addition, duplication, renaming and a malformed header are all rejected.
inventory_dir <- function(mutate) {
  dir <- tempfile("skipinv-"); dir.create(dir)
  file.copy(Sys.glob(file.path(earlier_policy_dir, "*-warnings.tsv")), dir)  # the (earlier) warning inventories
  lines <- readLines("tools/ci/windows-test-skips.tsv", warn = FALSE)
  if (!is.null(mutate)) writeLines(mutate(lines), file.path(dir, "windows-test-skips.tsv"))
  dir
}
for (mutate in list(function(l) l[-2L], function(l) c(l, "test-flatgeobuf.R\tsome other test"), function(l) c(l, l[[2L]]),
                    function(l) sub("path validation", "path checking", l, fixed = TRUE), function(l) sub("^file", "path", l),
                    function(l) l[1L], function(l) c(l, "test-x.R\t"), function(l) c(l, "../x.R\tbad file"))) {
  dir <- inventory_dir(mutate)
  reject(winval(skip_log(), policy_dir = dir))
  unlink(dir, recursive = TRUE)
}
dir <- inventory_dir(NULL)                                          # no inventory file at all
reject(suppressWarnings(winval(skip_log(), policy_dir = dir)))
unlink(dir, recursive = TRUE)
dir <- inventory_dir(function(l) l)                                 # an identical copy is accepted
winval(skip_log(), policy_dir = dir)
unlink(dir, recursive = TRUE)

# ---- Failed / missing / successful package-test logs (check-package.R reads them through pst_read_test_log) ----------
log_dir <- function(ok = NULL, fail = NULL) {
  dir <- tempfile("checkdir-"); dir.create(file.path(dir, "tests"), recursive = TRUE)
  if (!is.null(ok)) writeLines(ok, file.path(dir, "tests", "testthat.Rout"))
  if (!is.null(fail)) writeLines(fail, file.path(dir, "tests", "testthat.Rout.fail"))
  dir
}
failed_tests <- sub("FAIL 0", "FAIL 1", ubuntu_tests, fixed = TRUE)
dir <- log_dir(ok = ubuntu_tests)
stopifnot(identical(pst_read_test_log(dir), list(failed = FALSE, path = file.path(dir, "tests", "testthat.Rout"), lines = ubuntu_tests)))
unlink(dir, recursive = TRUE)
dir <- log_dir(fail = failed_tests)                                      # a failed run: reported, never a result to validate
result <- pst_read_test_log(dir)
stopifnot(result$failed, identical(result$lines, failed_tests), endsWith(result$path, "testthat.Rout.fail"))
reject(validate_pst_check("ubuntu", ubuntu_install, ubuntu_check, result$lines, 1L))
unlink(dir, recursive = TRUE)
# Even a .fail file containing a "passing" log is never returned as a success.
dir <- log_dir(fail = ubuntu_tests); stopifnot(pst_read_test_log(dir)$failed); unlink(dir, recursive = TRUE)
reject(pst_read_test_log(log_dir()))                                      # neither log (no tests ran / stale-free directory)
reject(pst_read_test_log(log_dir(ok = ubuntu_tests, fail = failed_tests))) # ambiguous: refuse to choose
reject(pst_read_test_log(file.path(tempdir(), "no-such-check-directory")))

# ---- Test-suite mode witness (full development suite versus thinned CRAN-mode suite) --------------------------------------
mode_log <- function(pass) c("some output", sprintf("[ FAIL 0 | WARN 0 | SKIP 0 | PASS %d ]", pass), "", "> proc.time()")
floor_value <- as.integer(readLines("tools/ci/full-suite-floor.txt", warn = FALSE)[[1L]])
stopifnot(identical(pst_check_suite_mode(mode_log(floor_value), TRUE), floor_value),
          identical(pst_check_suite_mode(mode_log(floor_value + 5000L), TRUE), floor_value + 5000L),
          identical(pst_check_suite_mode(mode_log(floor_value - 1L), FALSE), floor_value - 1L),
          identical(pst_suite_expectations(c(mode_log(1L), mode_log(77L))), 77L))      # the last summary line counts
reject(pst_check_suite_mode(mode_log(floor_value - 1L), TRUE))                         # a full run that was thinned
reject(pst_check_suite_mode(mode_log(floor_value), FALSE))                             # a CRAN-mode run that ran everything
reject(pst_check_suite_mode(c("no summary here"), TRUE))
reject(pst_check_suite_mode(mode_log(floor_value), TRUE, policy_dir = file.path(tempdir(), "no-such-policy-dir")))
dir <- tempfile("floor-"); dir.create(dir)
for (bad in c("", "abc", "0", "-5")) { writeLines(bad, file.path(dir, "full-suite-floor.txt")); reject(suppressWarnings(pst_check_suite_mode(mode_log(10L), FALSE, dir))) }
unlink(dir, recursive = TRUE)

# ---- The local gate always selects the FULL suite; CRAN mode stays selectable through check-package.R ---------------------------
source("tools/ci/gate-mode.R")
with_env <- function(value, code) {
  old <- Sys.getenv("RPST_FULL_TESTS", unset = NA_character_)
  on.exit(if (is.na(old)) Sys.unsetenv("RPST_FULL_TESTS") else Sys.setenv(RPST_FULL_TESTS = old), add = TRUE)
  if (is.na(value)) Sys.unsetenv("RPST_FULL_TESTS") else Sys.setenv(RPST_FULL_TESTS = value)
  force(code)
}
for (parent in c("false", "FALSE", "False", "true", "", "0", NA_character_)) {
  stopifnot(identical(with_env(parent, {pst_enforce_full_suite_mode(); Sys.getenv("RPST_FULL_TESTS")}), "true"))
}
# the enforced value is what a SUBPROCESS of the local gate really sees (the gates are separate Rscript processes)
child <- function() system2(file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"),
                            c("-e", shQuote("cat(Sys.getenv('RPST_FULL_TESTS', 'unset'))")), stdout = TRUE)
stopifnot(identical(with_env("false", {pst_enforce_full_suite_mode(); child()}), "true"),
          identical(with_env("false", child()), "false"))                       # without the enforcement the child would inherit false
# check-package.R keeps CRAN mode selectable: explicit false (any case) -> CRAN mode; unset or anything else -> full
stopifnot(!pst_full_tests_requested("false"), !pst_full_tests_requested("FALSE"), !pst_full_tests_requested("False"),
          pst_full_tests_requested("true"), pst_full_tests_requested(""), pst_full_tests_requested("1"),
          identical(with_env(NA_character_, pst_full_tests_requested()), TRUE),
          identical(with_env("false", pst_full_tests_requested()), FALSE))
# the scripts really use the helpers, and check-local.R enforces the mode BEFORE it launches its first gate
local_lines <- readLines("tools/ci/check-local.R", warn = FALSE)
enforce_at <- grep("^pst_enforce_full_suite_mode\\(\\)", local_lines)
launch_at <- grep("system2\\(", local_lines)
stopifnot(length(enforce_at) == 1L, length(launch_at) >= 1L, enforce_at < min(launch_at),
          any(grepl('source("tools/ci/gate-mode.R")', local_lines, fixed = TRUE)),
          !any(grepl("RPST_FULL_TESTS", sub("#.*$", "", local_lines))))          # check-local.R reads no mode from the environment itself
package_lines <- readLines("tools/ci/check-package.R", warn = FALSE)
stopifnot(any(grepl("pst_full_tests_requested()", package_lines, fixed = TRUE)),
          any(grepl('source("tools/ci/gate-mode.R")', package_lines, fixed = TRUE)))

# ---- Live inventories (after the diagnostic build-copy fixes) -------------------------------------------------------------------------------
# The logs below are DERIVED, not observed: the earlier
# excerpts with every diagnostic of the eliminated classes removed (and the clean installation-check summary R would
# print). They prove only that the live inventories are the exact complement of the eliminated classes and that the
# validator rejects any regression; real runs must still be compared with them (see docs/build-and-platforms.md).
formals(read_pst_warning_policy)$policy_dir <- live_policy_dir
formals(validate_pst_check)$policy_dir <- live_policy_dir
eliminated <- paste0("\\[-W(nonportable-include-path|switch|bitwise-instead-of-logical|reorder-ctor|reorder|",
                     "class-memaccess|unused-result)\\]")
derive_install <- function(lines) lines[!grepl(eliminated, lines)]
derive_check <- function(lines) {
  header <- grep("^\\* checking whether package .rPST(ool)?. can be installed \\.\\.\\.", lines)
  see <- grep("^See .+/00install[.]out. for details[.]$", lines)
  lines[[header]] <- sub("WARNING$", "OK", lines[[header]])
  lines <- lines[-seq.int(header + 1L, see)]
  sub("^Status: 1 WARNING$", "Status: OK", lines)
}
for (platform in c("macos", "windows")) {
  old_install <- read_fixture(platform, "install.out")
  old_check <- read_fixture(platform, "check.log")
  tests <- read_fixture(platform, "tests.Rout")
  derived_install <- derive_install(old_install)
  derived_check <- derive_check(old_check)
  stopifnot(length(derived_install) < length(old_install))
  validate_pst_check(platform, derived_install, derived_check, tests, 0L)
  # a clean log with the WARNING exit status 1 is rejected; exit status 0 is required
  reject(validate_pst_check(platform, derived_install, derived_check, tests, 1L))
  # earlier (pre-fix) observed logs must now be rejected
  reject(validate_pst_check(platform, old_install, derived_check, tests, 0L))
  reject(validate_pst_check(platform, derived_install, old_check, tests, 0L))
  # a stale significant-warning block or WARNING summary on an otherwise clean log
  reject(validate_pst_check(platform, derived_install, sub("Status: OK", "Status: 1 WARNING", derived_check, fixed = TRUE), tests, 0L))
  # every eliminated signature, if reintroduced, is rejected both as a compiler diagnostic and as a significant one
  for (signature in unique(grep(eliminated, old_install, value = TRUE))) {
    reject(validate_pst_check(platform, c(derived_install, signature), derived_check, tests, 0L))
  }
  earlier_block <- old_check[seq.int(grep("can be installed", old_check) + 1L,
                                        grep("^See .+00install", old_check))]
  header <- grep("can be installed", derived_check)
  reintroduced <- append(derived_check, earlier_block, after = header)
  reintroduced[[header]] <- sub("OK$", "WARNING", reintroduced[[header]])
  reject(validate_pst_check(platform, derived_install, sub("Status: OK", "Status: 1 WARNING", reintroduced, fixed = TRUE), tests, 0L))
  # no suppression of unrelated remaining signatures: dropping or duplicating any remaining diagnostic fails
  remaining <- grep(": warning:", derived_install, value = TRUE)
  for (signature in unique(remaining)) {
    at <- match(signature, derived_install)
    reject(validate_pst_check(platform, derived_install[-at], derived_check, tests, 0L))
    reject(validate_pst_check(platform, c(derived_install, signature), derived_check, tests, 0L))
  }
}
# macOS SDK 27: the formerly SDK-specific nodiscard diagnostics are gone, so the SDK27 inventory is empty and the
# diagnostics are rejected even on an SDK 27 log.
macos_derived_install <- derive_install(read_fixture("macos", "install.out"))
macos_derived_check <- sub("^(\\* used SDK: .)MacOSX[0-9.]+[.]sdk", "\\1MacOSX27.0.sdk", derive_check(read_fixture("macos", "check.log")))
stopifnot(any(grepl("MacOSX27.0.sdk", macos_derived_check, fixed = TRUE)))
validate_pst_check("macos", macos_derived_install, macos_derived_check, macos_tests, 0L)
unused_result <- "vendor/pstalgo/src/analyses/AngularChoiceAlgo.cpp:464:9: warning: ignoring return value of function declared with 'nodiscard' attribute [-Wunused-result]"
reject(validate_pst_check("macos", c(macos_derived_install, unused_result), macos_derived_check, macos_tests, 0L))
reject(validate_pst_check("macos", macos_derived_install, macos_derived_check, macos_tests, 1L))
stopifnot(nrow(read.delim("tools/ci/macos-sdk27-pst-warnings.tsv", quote = "", colClasses = "character")) == 0L)
# the live inventories contain none of the eliminated classes and are a strict subset of the preserved ones
for (platform in c("macos", "macos-sdk27", "windows")) {
  live <- readLines(file.path(live_policy_dir, paste0(platform, "-pst-warnings.tsv")))
  old <- readLines(file.path("tools/ci/fixtures/pre-diagnostic-fix-inventories", paste0(platform, "-pst-warnings.tsv")))
  stopifnot(!any(grepl(eliminated, live)), identical(live, old[!grepl(eliminated, old)]))
}

message("Exact warning-policy tests passed: known inventories accepted; ",
        rejections, " signature/count/origin, check, test, and execution mutations rejected")
