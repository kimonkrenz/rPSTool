#!/usr/bin/env Rscript
# Writes the GitHub Actions job summary (Markdown). It only reports what the logs and step outcomes show:
# a stage is PASS only when its step outcome is "success" (and, where a log line is expected, that line is present);
# a failed stage is FAIL; a stage that did not run is NOT RUN. Nothing here changes any gate decision.
# Usage: write-summary.R <title>   (step outcomes come in via STEP_ENV, STEP_VENDOR, STEP_TOOLS, STEP_GATE, STEP_EXTRA)
args <- commandArgs(trailingOnly = TRUE)
title <- if (length(args)) args[[1L]] else "Release-candidate gate"
out <- Sys.getenv("GITHUB_STEP_SUMMARY", unset = "")
rd <- function(path) if (file.exists(path)) readLines(path, warn = FALSE) else character()
env <- function(name) Sys.getenv(name, unset = "")
status <- function(outcome) switch(outcome, success = "PASS", failure = "**FAIL**", cancelled = "**CANCELLED**", "NOT RUN")
first <- function(x, default = "not recorded") if (length(x)) x[[1L]] else default

environment_txt <- rd(".local/rc/environment.txt")
gate_log <- rd(".local/rc/gate.log")
tools_log <- rd(".local/rc/tool-tests.log")
check_log <- rd(".local/ci-check/rPSTool.Rcheck/00check.log")
install_out <- rd(".local/ci-check/rPSTool.Rcheck/00install.out")
test_dir <- ".local/ci-check/rPSTool.Rcheck/tests"
tests_out <- c(rd(file.path(test_dir, "testthat.Rout")), rd(file.path(test_dir, "testthat.Rout.fail")))

commit <- sub("^commit: ", "", first(grep("^commit: ", environment_txt, value = TRUE), env("GITHUB_SHA")))
runner <- first(grep("^runner: ", environment_txt, value = TRUE), paste("runner:", env("RUNNER_OS"), env("RUNNER_ARCH")))
rver <- first(grep("^R version", environment_txt, value = TRUE))
pkgs <- grep("^(arrow|sf|testthat) [0-9]", environment_txt, value = TRUE)

s_env <- env("STEP_ENV"); s_vendor <- env("STEP_VENDOR"); s_tools <- env("STEP_TOOLS"); s_gate <- env("STEP_GATE")

n_expect <- sub("^Package tests: (.*) suite, ([0-9]+) expectations passed$", "\\2 (\\1)", first(grep("^Package tests: ", gate_log, value = TRUE), ""))
if (!nzchar(n_expect)) n_expect <- "not reported"
test_line <- first(grep("^\\[ *FAIL [0-9]+ \\|", tests_out, value = TRUE), "not reported")
check_status <- first(grep("^Status: ", check_log, value = TRUE), "not reported")
compiler_n <- sum(grepl(": warning:", install_out, fixed = TRUE))
policy_line <- first(grep("^Exact PST warning policy passed on ", gate_log, value = TRUE), "")
live_policy <- if (identical(s_gate, "success") && nzchar(policy_line)) "PASS" else if (identical(s_gate, "success")) "**FAIL** (success line missing)" else status(s_gate)
hist_line <- first(grep("^Exact warning-policy tests passed", tools_log, value = TRUE), "")
hist_policy <- if (identical(s_tools, "success") && nzchar(hist_line)) "PASS" else if (identical(s_tools, "success")) "**FAIL** (success line missing)" else status(s_tools)
rcmd <- if (identical(s_gate, "success") && grepl("^Status: OK", check_status)) {
  "PASS"
} else if (identical(s_gate, "success") && grepl("^Status: ", check_status)) {
  "PASS (policy-accepted)"
} else status(s_gate)
vendor <- status(s_vendor)

all_ok <- identical(s_env, "success") && identical(s_vendor, "success") && identical(s_tools, "success") &&
  identical(s_gate, "success") && nzchar(policy_line) && nzchar(hist_line)
overall <- if (all_ok) "PASS" else if (any(c(s_env, s_vendor, s_tools, s_gate) %in% "failure")) "**FAIL**" else "**INCOMPLETE**"

md <- c(
  paste0("## ", title, ": ", overall), "",
  "| Item | Value |", "|---|---|",
  paste0("| Commit | `", commit, "` |"),
  paste0("| Runner | ", sub("^runner: ", "", runner), " |"),
  paste0("| R | ", rver, " |"),
  if (length(pkgs)) paste0("| Dependencies | ", paste(gsub(" +$", "", sub(" ", " ", pkgs)), collapse = "; "), " |"),
  paste0("| Full test count | ", n_expect, " |"),
  paste0("| Test summary line | `", gsub("|", "\\|", test_line, fixed = TRUE), "` |"),
  paste0("| `R CMD check` | ", rcmd, " — ", check_status, " |"),
  paste0("| Vendor integrity | ", vendor, " |"), "",
  "### Live validation (this run, this compiler)", "",
  "| Stage | Result |", "|---|---|",
  paste0("| Compiler diagnostics in `00install.out` | ", if (length(install_out)) compiler_n else "no install log", " |"),
  paste0("| Exact warning policy on live diagnostics | ", live_policy, if (nzchar(policy_line)) paste0(" — ", sub("^Exact PST warning policy passed on ", "", policy_line)) else "", " |"), "",
  "### Historical-fixture regression checks (archived logs, not this run's compiler)", "",
  "| Stage | Result |", "|---|---|",
  paste0("| Warning-policy regression suite and build-time tool tests | ", hist_policy, if (nzchar(hist_line)) paste0(" — ", sub("^Exact warning-policy tests passed: ", "", hist_line)) else "", " |"), "")
extra <- env("STEP_EXTRA")
if (nzchar(extra)) md <- c(md, extra, "")
if (!all_ok) {
  md <- c(md, "### Failure detail", "")
  for (src in list(list("Gate", gate_log), list("Tool tests", tools_log))) {
    bad <- grep("Error|error:|FAIL|rejected|Unexpected|policy", src[[2L]], value = TRUE)
    if (length(bad)) md <- c(md, paste0("**", src[[1L]], "** (last matching lines):"), "```", tail(bad, 15L), "```", "")
  }
}
md <- c(md, "Artifacts (`.local/rc`, `.local/ci-check`) are attached to the run.")
if (nzchar(out)) cat(md, file = out, sep = "\n", append = TRUE) else cat(md, sep = "\n")
