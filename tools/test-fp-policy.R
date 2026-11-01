#!/usr/bin/env Rscript
# Offline fail-closed tests for the deterministic floating-point policy.
env <- new.env(parent = baseenv())
sys.source("tools/fp-policy.R", envir = env)
check <- env$fp_policy_violations
header <- readLines("src/rpst-float-overloads.h")
for (makevars in c("src/Makevars", "src/Makevars.win")) {
  lines <- readLines(makevars)
  stopifnot(length(check(lines, header, makevars)) == 0L)
  mutate <- function(f) check(f(lines), header, makevars)
  rejected <- function(violations, pattern) stopifnot(any(grepl(pattern, violations)))
  first_compile <- which(grepl("^\t\\$\\(CXX\\) ", lines))[1L]
  rejected(mutate(function(l) sub("-ffp-contract=off", "-ffp-contract=on", l, fixed = TRUE)), "RPST_FP_FLAGS")
  rejected(mutate(function(l) l[l != "RPST_FP_FLAGS = -ffp-contract=off"]), "RPST_FP_FLAGS")
  rejected(mutate(function(l) {l[first_compile] <- sub(" $(RPST_FP_FLAGS)", "", l[first_compile], fixed = TRUE); l}), "compile rule")
  rejected(mutate(function(l) {l[first_compile] <- sub("$(ALL_CXXFLAGS) $(RPST_FP_FLAGS)", "$(RPST_FP_FLAGS) $(ALL_CXXFLAGS)", l[first_compile], fixed = TRUE); l}), "compile rule")
  rejected(mutate(function(l) sub("PKG_CXXFLAGS = -pthread", "PKG_CXXFLAGS = -pthread -ffp-contract=off", l, fixed = TRUE)), "PKG_CXXFLAGS")
  rejected(mutate(function(l) l[!grepl("^pst-graph[.]o: ", l)]), "wrapper pst-graph")
  for (wrapper in c("pst-geoparquet", "pst-flatgeobuf", "pst-result-stream", "pst-output-file", "pst-arrow-test-stream")) {
    # The new Arrow wrappers are covered exactly like every other wrapper: an explicit rule,
    # with $(RPST_FP_FLAGS) directly after $(ALL_CXXFLAGS).
    pattern <- paste0("^", wrapper, "[.]o: ", wrapper, "[.]cpp( [^ ]+)*$")
    stopifnot(sum(grepl(pattern, lines)) == 1L)
    rejected(mutate(function(l) l[!grepl(pattern, l)]), paste("wrapper", wrapper))
    rule <- lines[endsWith(lines, paste0(" -c ", wrapper, ".cpp -o $@")) & startsWith(lines, "\t$(CXX) ")]
    stopifnot(length(rule) == 1L, grepl("$(ALL_CPPFLAGS) $(ALL_CXXFLAGS) $(RPST_FP_FLAGS) -c ", rule, fixed = TRUE))
    rejected(mutate(function(l) {
      l[l == rule] <- sub(" $(RPST_FP_FLAGS)", "", rule, fixed = TRUE); l
    }), paste("wrapper", wrapper))
    rejected(mutate(function(l) {
      l[l == rule] <- sub("$(ALL_CXXFLAGS) $(RPST_FP_FLAGS)", "$(RPST_FP_FLAGS) $(ALL_CXXFLAGS)", rule, fixed = TRUE); l
    }), "compile rule")
  }
  rejected(mutate(function(l) sub("pst-raster.cpp -o", "pst-raster.cpp -o", sub("$(RPST_FP_FLAGS) -c pst-raster.cpp", "-c pst-raster.cpp", l, fixed = TRUE), fixed = TRUE)), "wrapper pst-raster")
  rejected(mutate(function(l) sub("-include rpst-float-overloads.h ", "", l, fixed = TRUE)), "force-include")
  rejected(mutate(function(l) sub("-include rpst-float-overloads.h -include rpst-compat.h", "-include rpst-compat.h -include rpst-float-overloads.h", l, fixed = TRUE)), "force-include")
  rejected(mutate(function(l) c(l, "PKG_CXXFLAGS += -ffp-contract=fast")), "ffp-contract must appear only")
  rejected(mutate(function(l) sub(" rpst-float-overloads.h", "", l, fixed = TRUE)), "depend on")
}
lines <- readLines("src/Makevars")
rejected <- function(violations, pattern) stopifnot(any(grepl(pattern, violations)))
rejected(check(lines, header[header != "using std::sin;"], "m"), "eight using-declarations")
rejected(check(lines, c(header, "using std::abs;"), "m"), "eight using-declarations")
rejected(check(lines, c(header, "using std::atan2;"), "m"), "eight using-declarations")
rejected(check(lines, c(header, "using std::sin;"), "m"), "eight using-declarations")
rejected(check(lines, c(header, "using ::sin;"), "m"), "not 'using std")
rejected(check(lines, header[!grepl('RPST_ASSERT_FLOAT_OVERLOAD\\(round', header)], "m"), "static_assert")
rejected(check(lines, header[!grepl("static_assert(std::is_same", header, fixed = TRUE)], "m"), "static_assert")
rejected(check(lines, c(header, "inline float abs(float);"), "m"), "abs")

# Fail closed at compile time: without the using-declarations a libstdc++ (or
# any toolchain whose global namespace lacks float overloads) must refuse to
# build. Skipped where no C++ compiler is configured.
cxx <- tryCatch(system2(file.path(R.home("bin"), "R"), c("CMD", "config", "CXX17"), stdout = TRUE, stderr = FALSE), error = function(e) "")
std <- tryCatch(system2(file.path(R.home("bin"), "R"), c("CMD", "config", "CXX17STD"), stdout = TRUE, stderr = FALSE), error = function(e) "")
if (length(cxx) == 1L && nzchar(cxx)) {
  dir.create(".local", showWarnings = FALSE)
  tmp <- tempfile("fp-policy-", tmpdir = ".local"); dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  # Portable invocation: the compiler is run through system2() with its output captured in a log file (no shell
  # redirection, which a Windows compiler would read as an input file named "2>&1"). `R CMD config` may return the
  # program together with leading options.
  words <- function(x) Filter(nzchar, strsplit(trimws(x), "[[:space:]]+")[[1L]])
  cxx_words <- words(cxx)
  log <- file.path(tmp, "compiler.log")
  compile <- function(header_lines) {
    writeLines(header_lines, file.path(tmp, "h.h"))
    writeLines(c('#include "h.h"', "int main() { return 0; }"), file.path(tmp, "t.cpp"))
    program <- cxx_words[[1L]]
    status <- suppressWarnings(system2(if (grepl("[[:space:]]", program)) shQuote(program) else program,
                                       c(cxx_words[-1L], words(std), "-fsyntax-only", shQuote(file.path(tmp, "t.cpp"))),
                                       stdout = log, stderr = log))
    diagnostics <<- readLines(log, warn = FALSE)
    identical(as.integer(status), 0L)
  }
  diagnostics <- character()
  if (!compile(header)) stop("the approved float-overload header does not compile:\n", paste(diagnostics, collapse = "\n"))
  broken <- header[!grepl("^using std::(sin|cos|sqrt|fmod|log|log10|pow|round);", header)]
  # Only meaningful on toolchains that do not already provide global overloads.
  if (!compile(broken)) {
    message("compile gate: removing the using-declarations is rejected at build time")
  } else {
    message("compile gate: this toolchain already provides global float overloads; mutation not applicable")
  }
  # A broken return type must always be rejected.
  wrong <- sub("decltype(expr), float", "decltype(expr), double", header, fixed = TRUE)
  stopifnot(!compile(wrong))
  # ... and it must be rejected by the header's own assertion, not by an unrelated compiler or invocation problem.
  if (!any(grepl("rPSTool float-overload convention", diagnostics, fixed = TRUE)))
    stop("the corrupted header was rejected, but not by the float-overload static_assert:\n", paste(diagnostics, collapse = "\n"))
}
message("Floating-point policy tests passed: flag placement, header contents, abs exclusion, fail-closed compile gate")
