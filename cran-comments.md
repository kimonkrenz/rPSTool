# cran-comments.md

This file records the validation completed so far. It is finalised at submission time (see `docs/release-checklist.md`); sections
marked *pending* have no results recorded yet.

## Submission

New submission of rPSTool 0.1.0. Maintainer: Kimon Krenz <k.krenz@ucl.ac.uk>.

## Test environments

Validated at commit `4119f2b847bafedff84f6d6fbf357196aed77add` on GitHub Actions runners, each with R 4.6.2 and the full development
test suite (`RPST_FULL_TESTS=true`, with `arrow` 26.0.0 and `sf` 1.1.3):

* Linux x86-64 (Ubuntu, GCC 15.2.0): 160,814 test expectations; `R CMD check` `Status: OK`.
* macOS ARM64 (macos-15, Apple clang 17.0.0): 160,814 test expectations; `R CMD check` `Status: OK`.
* Windows x86-64 (Windows Server 2022, Rtools GCC 14.3.0): 160,759 test expectations; `R CMD check` `Status: OK`. The count is 55 lower than on the other
  platforms; this has not been independently explained. Four tests that need POSIX-only facilities are skipped on Windows by
  design (`tools/ci/windows-test-skips.tsv`).

*Pending:* win-builder and R-hub, if used. The final tarball is to be rebuilt and re-checked from the frozen release commit.

## R CMD check results

Linux, `R CMD check --as-cran` with `_R_CHECK_CRAN_INCOMING_`, `_R_CHECK_CRAN_INCOMING_REMOTE_` and `_R_CHECK_FORCE_SUGGESTS_` enabled
(commit `4119f2b`): 0 errors, 0 warnings, 1 note.

* NOTE: CRAN incoming feasibility, "New submission".

`R CMD check` was not run with CRAN incoming checks enabled on macOS or Windows. Items that must be explained if they remain in
the final submission checks:

* Compiler diagnostics from the bundled, pinned PST C++ engine: every diagnostic that R classes as significant is removed through
  verified build copies; the remaining non-significant diagnostics (unused variables and functions, sign comparisons) are inventoried
  exactly (`docs/build-and-platforms.md`). The Linux run recorded none.
* An installed-size NOTE may appear on some Linux toolchains: the shared library then contains debug symbols from the platform's
  default compiler flags (about 15 MB with Debian's flags, about 1 MB without); the package does not strip symbols itself.

## Notes for the reviewer

* The package bundles, and compiles into its shared library, the pinned `pstalgo` engine (LGPL-3-or-later), FlatBuffers (Apache-2.0),
  FlatGeobuf generated headers (BSD-2-Clause) and Apache Arrow C-interface declarations (Apache-2.0). Attribution: `inst/COPYRIGHTS`.
* PST creates worker threads internally. rPSTool limits them to two when `_R_CHECK_LIMIT_CORES_` is set (any non-empty value other than `false`,
  as R's parallel package does) and honours `RPST_NUM_THREADS`.
* Result files (`output_file`, `spatial_output_file`) are written through POSIX calls on Unix-alikes and through the Win32 API
  (`MoveFileExW`) on Windows; the Windows implementation is covered by the full test suite run above.
* `arrow`, `sf` and `jsonlite` are optional (Suggests); tests and examples that need them are skipped when they are unavailable.
