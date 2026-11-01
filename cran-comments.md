# cran-comments.md

This file is completed from the final validation matrix at submission time (see `docs/release-checklist.md`); the sections marked
*pending* have no results recorded yet.

## Submission

New submission of rPSTool 0.1.0. Maintainer: Kimon Krenz <k.krenz@ucl.ac.uk>.

## Pre-submission dependencies (all open)

* Repository public: `URL` and `BugReports` in `DESCRIPTION` (`https://github.com/kimonkrenz/rPSTool` and `/issues`) must resolve
  publicly before submission; the URL check has not been re-run.
* CRAN incoming check: one `R CMD check --as-cran` with `_R_CHECK_CRAN_INCOMING_` enabled has not been run.
* Frozen-commit validation: the full gate on one frozen commit on macOS, Windows and Linux with `arrow`, and a re-check of the tarball
  built from that commit, have not been run. Earlier states passed on macOS and Windows; Windows validation of the release candidate
  and the Arrow-enabled Linux gate are outstanding.

## Test environments

*Pending:* local `R CMD check --as-cran` on macOS (Apple Silicon), Windows (Rtools) and Linux; win-builder or R-hub if used.

## R CMD check results

*Pending.* Items that must be explained if they remain:

* Compiler diagnostics from the bundled, pinned PST C++ engine: every diagnostic that R classes as significant is removed through verified
  build copies; the remaining non-significant diagnostics (unused variables and functions, sign comparisons) are inventoried exactly
  (`docs/build-and-platforms.md`).
* Installed-size NOTE on some Linux toolchains: the shared library contains debug symbols from the platform's default compiler flags (about
  15 MB with Debian's flags, about 1 MB without); the package does not strip symbols itself.

## Notes for the reviewer

* The package bundles, and compiles into its shared library, the pinned `pstalgo` engine (LGPL-3-or-later), FlatBuffers (Apache-2.0),
  FlatGeobuf generated headers (BSD-2-Clause) and Apache Arrow C-interface declarations (Apache-2.0). Attribution: `inst/COPYRIGHTS`.
* PST creates worker threads internally. rPSTool limits them to two when `_R_CHECK_LIMIT_CORES_` is set (any non-empty value other than `false`,
  as R's parallel package does) and honours `RPST_NUM_THREADS`.
* Result files (`output_file`, `spatial_output_file`) are written through POSIX calls on Unix-alikes and through the Win32 API
  (`MoveFileExW`) on Windows. The Windows implementation passed the development test suite on Windows; validation of the final release
  candidate on Windows is still outstanding (to be updated from the frozen-commit results).
* `arrow`, `sf` and `jsonlite` are optional (Suggests); tests and examples that need them are skipped when they are unavailable.
