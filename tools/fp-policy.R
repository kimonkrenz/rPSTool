# Deterministic floating-point evaluation policy: fail-closed structural check.
# Sourced by tools/verify-vendor.R and tools/test-fp-policy.R. Returns a
# character vector of violations (empty when the policy holds exactly).
fp_policy_allowed_names <- c("sin", "cos", "sqrt", "fmod", "log", "log10", "pow", "round")

fp_policy_violations <- function(makevars_lines, header_lines, label = "Makevars") {
  bad <- character()
  add <- function(...) bad <<- c(bad, paste0(label, ": ", ...))
  if (!identical(sum(makevars_lines == "RPST_FP_FLAGS = -ffp-contract=off"), 1L))
    add("RPST_FP_FLAGS must be defined exactly once as -ffp-contract=off")
  if (sum(grepl("^RPST_FP_FLAGS\\b", makevars_lines)) != 1L)
    add("RPST_FP_FLAGS must have a single definition")
  if (!any(makevars_lines == "PKG_CXXFLAGS = -pthread"))
    add("PKG_CXXFLAGS must stay free of floating-point flags (R CMD check portability)")
  for (w in c("native-smoke", "pst-construction", "pst-graph", "pst-geoparquet", "pst-flatgeobuf", "pst-result-stream", "pst-output-file", "pst-arrow-test-stream",
             "pst-isovist", "pst-raster", "rpst-workers")) {
    # A wrapper unit may add -I include directories before $(ALL_CPPFLAGS) (as pst-flatgeobuf does for the
    # generated FlatBuffers base.h) and extra prerequisites after its source; the flag order is unchanged.
    rule <- paste0("^\t\\$\\(CXX\\) (-I[^ ]+ )*\\$\\(ALL_CPPFLAGS\\) \\$\\(ALL_CXXFLAGS\\) \\$\\(RPST_FP_FLAGS\\) -c ", w, "[.]cpp -o \\$@$")
    if (!any(grepl(paste0("^", w, "[.]o: ", w, "[.]cpp( [^ ]+)*$"), makevars_lines)) || !any(grepl(rule, makevars_lines)))
      add("wrapper ", w, " needs an explicit compile rule with $(RPST_FP_FLAGS)")
  }
  cpp <- makevars_lines[grepl("^PKG_CPPFLAGS\\b", makevars_lines)]
  if (length(cpp) != 1L ||
      !grepl("-include rpst-float-overloads.h -include rpst-compat.h", cpp, fixed = TRUE))
    add("PKG_CPPFLAGS must force-include rpst-float-overloads.h before rpst-compat.h")
  compile <- makevars_lines[grepl("^\t\\$\\(CXX\\) ", makevars_lines)]
  if (length(compile) < 1L) add("no PST compile rules found")
  ok <- grepl("^\t\\$\\(CXX\\) (-I[^ ]+ )*\\$\\(ALL_CPPFLAGS\\) \\$\\(ALL_CXXFLAGS\\) \\$\\(RPST_FP_FLAGS\\) -c ", compile)
  if (!all(ok)) add(sum(!ok), " compile rule(s) do not append $(RPST_FP_FLAGS) immediately after $(ALL_CXXFLAGS)")
  if (any(grepl("ffp-contract", makevars_lines[!grepl("^RPST_FP_FLAGS = ", makevars_lines) &
                                              !grepl("^#", makevars_lines)])))
    add("-ffp-contract must appear only in the RPST_FP_FLAGS definition")
  if (!any(grepl("^\\$\\(OBJECTS\\): .*rpst-float-overloads[.]h", makevars_lines)))
    add("objects must depend on rpst-float-overloads.h")

  uses <- sub("^using std::(\\w+);.*$", "\\1", header_lines[grepl("^using ", header_lines)])
  if (!setequal(uses, fp_policy_allowed_names) || anyDuplicated(uses))
    add("header must contain exactly the eight using-declarations: ",
        paste(fp_policy_allowed_names, collapse = ", "))
  if (any(grepl("^using ", header_lines) & !grepl("^using std::\\w+;", header_lines)))
    add("header contains a using-declaration that is not 'using std::<name>;'")
  asserts <- sub('^RPST_ASSERT_FLOAT_OVERLOAD\\((\\w+)\\(.*$', "\\1",
                 header_lines[grepl("^RPST_ASSERT_FLOAT_OVERLOAD\\(", header_lines)])
  if (!setequal(asserts, fp_policy_allowed_names) || anyDuplicated(asserts))
    add("header must carry one float-return static_assert per name")
  if (!any(grepl("static_assert(std::is_same<decltype(expr), float>::value", header_lines, fixed = TRUE)))
    add("static_assert float-return check is missing")
  if (any(grepl("\\babs\\b", header_lines[!grepl("^\\s*//", header_lines)])))
    add("header must not touch abs")
  bad
}
