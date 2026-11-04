
# cran-comments.md

## Submission

New submission of rPSTool 0.1.0.
Maintainer: Kimon Krenz <k.krenz@ucl.ac.uk>.

## Test environments

GitHub Actions runners, each with R 4.6.2, the full development
test suite (`RPST_FULL_TESTS=true`), `arrow` 26.0.0 and `sf` 1.1.3,
at commit `39c0d66d2529cf6d4d4ff51a4f7ee5e6f3fa37af`:

* Linux x86-64 (Ubuntu 26.04, GCC 15.2.0): 161,539 test
  expectations passed; `R CMD check --as-cran` Status: OK.
* macOS ARM64 (macos-15, Apple clang 17.0.0): 161,539 test
  expectations passed; `R CMD check --as-cran` Status: OK.
* Windows x86-64 (Windows Server 2022, Rtools GCC 14.3.0):
  161,484 test expectations passed; `R CMD check --as-cran`
  Status: OK. Four tests requiring POSIX-only facilities are
  intentionally skipped (`tools/ci/windows-test-skips.tsv`).

All three platform runs completed successfully on 4 November 2026.
The results apply to the commit identified above. Validation will
be repeated at the final release commit before submission.

The file-backed GeoParquet example in
`vignettes/getting-started.Rmd` runs when its optional dependencies
(`arrow` >= 25.0.0, `jsonlite` and `sf`) and required CRS metadata
are available.

## R CMD check results

A separate Linux `R CMD check --as-cran` was run with
`_R_CHECK_CRAN_INCOMING_`, `_R_CHECK_CRAN_INCOMING_REMOTE_` and
`_R_CHECK_FORCE_SUGGESTS_` enabled, at commit
`39c0d66d2529cf6d4d4ff51a4f7ee5e6f3fa37af`.

Results: 0 errors, 0 warnings, 1 NOTE.

* NOTE: CRAN incoming feasibility, "New submission".

CRAN incoming checks were run on Linux only.

## Notes for the reviewer

* The package bundles the pinned PST/pstalgo C++ engine
  (LGPL-3-or-later), FlatBuffers headers (Apache-2.0),
  FlatGeobuf generated headers (BSD-2-Clause) and Apache Arrow
  C-interface declarations (Apache-2.0). Copyright and licence
  notices are provided in `inst/COPYRIGHTS`.
* PST creates worker threads internally. rPSTool limits their
  number to two when `_R_CHECK_LIMIT_CORES_` is active and
  supports an explicit cap through `RPST_NUM_THREADS`.
* Result files (`output_file`, `spatial_output_file`) are written
  using POSIX file operations on Unix-alikes and the Win32 API
  (`MoveFileExW`) on Windows.
* `arrow`, `sf` and `jsonlite` are optional dependencies
  (`Suggests`). Tests and examples requiring these packages
  are skipped when they are unavailable.
