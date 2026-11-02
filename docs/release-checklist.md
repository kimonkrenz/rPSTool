# Release readiness (rPSTool 0.1.0)

Technical readiness and legal/distribution clearance are separate, and neither is claimed here. rPSTool's internal warning policy is
not the CRAN check. Statements about CRAN policy below are assumptions unless they cite R's own *Writing R Extensions* or R's check
code.


## Package name: rPST to rPSTool

The package was developed under the name `rPST`. The Linux CRAN-oriented run on 2026-11-01 reported `Conflicting package names (submitted: rPST, existing: rpst [CRAN archive])`. The archived `rpst` package is *Recursive Partitioning Survival Trees* by Yewei Li (version 1.0.0, published 2017, archived 2021). CRAN Repository Policy requires names not to conflict irrespective of case with current **or past** CRAN packages (https://cran.r-project.org/web/packages/policies.html), so `rPST` was not safely available for a new submission.

**Decision (maintainer):** the CRAN package, brand and R identifier are now `rPSTool`, the mixed-case spelling is intentional, and the future public locations are the website `https://kimonkrenz.com/rPSTool/` and the repository `https://github.com/kimonkrenz/rPSTool`. The maintainer reports that `pak::pkg_name_check("rPSTool")` returned a valid name with no CRAN or Bioconductor conflict. That is preliminary evidence only; it does not replace the CRAN incoming checks, which have not been run for `rPSTool`.

**State of the rename.** The internal rename was completed before this repository was created: `DESCRIPTION`, `NAMESPACE` (`useDynLib(rPSTool)`), `R_init_rPSTool`, tests, documentation, vignettes, citation, CI scripts and metadata URLs. Internal technical identifiers (`rpst_*` native routines, `RPST_*` environment variables, `rpst:*` metadata keys, native pointer tags, `.rpst-build`, the `*_rpst_*` palette scales) are intentionally unchanged. Historical records still use the former name where they describe past work: the 2026-11-01 run below, the archived Windows/macOS logs under `tools/ci/fixtures/` and the parity-audit evidence files. The renamed package has since been validated on Linux, macOS ARM64 and Windows x86-64 at commit `4119f2b` (item 1 below).

**Public URLs.** `https://github.com/kimonkrenz/rPSTool` and `https://github.com/kimonkrenz/rPSTool/issues` returned HTTP 200 anonymously when checked from the documentation session. `DESCRIPTION` now lists only the GitHub repository (`URL`) and its issues page (`BugReports`); the website `https://kimonkrenz.com/rPSTool/` has not been created and is not referenced there.

## CRAN incoming findings (2026-11-01; Linux Gate 2, run under the name rPST)

The manual Linux CRAN-oriented run (under the former name) built and installed the package successfully but finished with two ERRORs and one NOTE (plus the name conflict above). The missing `testthat` package was a CI dependency omission; the workflow now installs it. Two overlong Rd example lines were wrapped in their Roxygen sources and generated Rd files. These changes have not yet been revalidated by a fresh run.

The incoming URL checks returned HTTP 404 because the then-intended repository URLs were not public. The metadata now points to the `rPSTool` repository, which is public. The later Linux incoming run (item 2) is the current evidence.

## Outstanding before submission

| # | Item | What is needed |
|---|---|---|
| 1 | Clean validation of one frozen commit | **Done for `4119f2b847bafedff84f6d6fbf357196aed77add`** (manual workflows, one gate per platform, no cancelled or repeated jobs): the full development gate (`RPST_FULL_TESTS=true`, `arrow` 26.0.0, `sf` 1.1.3, R 4.6.2) passed on Linux x86-64 (GCC 15.2.0, 160,814 expectations, [run](https://github.com/kimonkrenz/rPSTool/actions/runs/41354755085)), macOS ARM64 (Apple clang 17.0.0, 160,814, [run](https://github.com/kimonkrenz/rPSTool/actions/runs/41355944070)) and Windows x86-64 (GCC 14.3.0, 160,759, [run](https://github.com/kimonkrenz/rPSTool/actions/runs/41357774023)), each with `R CMD check` `Status: OK`, vendor integrity and the exact warning policy. The 55-expectation difference on Windows has not been independently explained. The final tarball must still be built and checked from the frozen release commit (item 6). |
| 2 | CRAN incoming checks | **Done on Linux at `4119f2b`:** `R CMD check --as-cran` with `_R_CHECK_CRAN_INCOMING_`, `_R_CHECK_CRAN_INCOMING_REMOTE_` and `_R_CHECK_FORCE_SUGGESTS_` enabled exited 0 with `Status: 1 NOTE` (CRAN incoming feasibility: "New submission"), 0 compiler-diagnostic lines and 90 registered routines after installation ([run](https://github.com/kimonkrenz/rPSTool/actions/runs/41354755085)). Not run on macOS or Windows. Spelling and URL checks (item 5) were not part of that run. |
| 3 | Public URLs | `URL` and `BugReports` in `DESCRIPTION` point to the GitHub repository and its issues page, which resolve publicly (see above). No project website is referenced. |
| 4 | `cran-comments.md` | Complete the test-environment list and check results from item 1; list every remaining NOTE with its explanation (installed size on Debian-style `-g` toolchains; see [build and platforms](build-and-platforms.md)). |
| 5 | Spelling, URLs, version | `spelling::spell_check_package()` (aspell is needed), `urlchecker::url_check()` once URLs exist, final `Version` and `Date`. |
| 6 | Frozen tarball | Build the tarball with `R CMD build` from the frozen commit and re-check that exact tarball. |
| 7 | Licensing items | Permission to redistribute the Barnsbury pedestrian and vehicle gate count data was granted by the authors. (Barnsbury gate count data only; see [licensing](licensing.md) §3, item 7). The LGPL binary redistribution, PST authorship/citation, headerless upstream files and depthmapX/ColorBrewer review items have been closed by explicit maintainer decisions recorded in [licensing](licensing.md) §3; this is not a formal legal opinion. Other licensing items remain documented there. |
| 8 | README in the tarball | `README.md` is excluded from the tarball (`.Rbuildignore`) because it links to repository files that are not shipped. Keep the exclusion or ship a CRAN-facing README. |
| 9 | `arrow >= 25.0.0` | Re-verify at submission that it resolves from CRAN. Tests and examples skip when it is absent; the development gate requires it. |
| 10 | Windows result-file writing | Superseded by item 1: the full development suite and `R CMD check` passed on Windows x86-64 at `4119f2b`, including the result-file tests. History: PR #66 was merged on 2026-10-28 on the basis of earlier Windows runs at `8ead7e4` (160,438 expectations) and a package check at `7681c05`. |

## Resolved and verified

* Licence declared (`LGPL (>= 3)`), `inst/COPYRIGHTS`, `inst/CITATION` and third-party licence texts in place.
* Worker cap under `R CMD check --as-cran`: `_R_CHECK_LIMIT_CORES_` handled case-insensitively as a ceiling of two.
* Two-mode test suite (CRAN mode thinned, full mode guarded by an expectation-count floor); see [testing](testing.md).
* Compiler diagnostics that R classes as significant removed through verified build copies; remaining non-significant diagnostics
  exactly inventoried ([build and platforms](build-and-platforms.md)).
* GCC 15 build fix (`<cstdint>` in the force-included `src/rpst-compat.h`).
* Version `0.1.0`, `Language: en-GB`, `testthat (>= 3.2.0)`, maintainer address, package-level and function help, `NEWS.md`.
* The single `\dontrun` example is guarded (POSIX and `arrow`) and cleans up.
* Build properties verified: parallel install, byte-identical generated build copies, `--preclean --clean` leaves `src` clean,
  no network needed, tarballs differ only in `Packaged:`.
* Test-only instrumentation stays in the shipped library with validated arguments ([architecture](architecture.md)).

## Documented limitations (not blockers)

* **Angular Choice recursion depth** (inherited from PST): a very long chain of shortest-path steps can exhaust a worker thread's
  stack and terminate R. Reproduced only on synthetic collinear chains (macOS ARM64: an unrestricted 8,000-segment chain; Linux
  with an 8 MB stack: about 64,000 segments). PST's traversal is not modified; the limitation is documented in `angular_choice()`
  and [angular controls](compatibility/angular-controls.md). If CRAN requires a correction it will be addressed then with minimum
  impact on performance.
* **Windows file output:** implemented with the Win32 API and covered by the full development suite on Windows at `4119f2b` (item 1). On Windows a replacement with `overwrite = TRUE` fails, leaving the old file intact, while another process holds the destination open without sharing it for deletion.
* **No Q-level evidence:** no real PST for QGIS comparison has been recorded; see
  [`tools/validation/qgis-comparison/`](../tools/validation/qgis-comparison/README.md) and
  [QGIS differences](compatibility/qgis-differences.md).
* **Not exposed:** Fast Segment Betweenness, Visual Connectivity and progress/log callbacks ([PST coverage](pst-coverage.md)).
* **Deferred I/O:** file-backed `unlinks`/`points`, explicit geometry-column selection, native GeoArrow encodings, GeoParquet 2.0,
  directories and multi-file datasets, external-ID retention, other formats, and persistence of `network_integration(junctions =
  TRUE)` ([spatial I/O](spatial-io/README.md)).

## Optional

* `-fvisibility=hidden` (about 381 exported symbols reduced to 48; needs Windows verification).
* Remaining non-significant compiler-diagnostic cleanup through further build copies.
* Whether to keep roxygen as the source of truth (`Roxygen:` fields in `DESCRIPTION`) given that `NAMESPACE` and `man/` are
  maintained in the repository.
