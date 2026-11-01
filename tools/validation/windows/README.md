# Windows validation of result-file writing

Result-file writing (`output_file`, `spatial_output_file`) is implemented on Windows with the Win32 API (`src/pst-fs-core.h`; design and
guarantees in [result files](../../../docs/spatial-io/result-files.md) §5 item 6). The quick procedure and full development test suite
passed on real Windows x86-64 at `8ead7e4`; the strict full gate rejected one documentation NOTE. See the recorded results below.
**Windows support remains pending validation** until the remaining evidence has been reviewed.

## Requirements

* Windows 10/11 x86-64, a recent R (4.3 or later; 4.6 UCRT matches earlier validation) and the matching Rtools (`g++` on `PATH` through
  Rtools, as for any package build).
* Packages: `arrow` (>= 25.0.0), `sf`, `jsonlite`, `testthat` (>= 3.2.0); `knitr` and `rmarkdown` for the full gate.
* Optional but recommended: **Developer Mode** (Settings, For developers) or an elevated prompt, so symbolic links can be created and the
  symbolic-link assertions run. `run-validation.R` records whether they can.
* Run the procedure once on the system drive (NTFS) and, if possible, once with `TMPDIR`/`TEMP` on another volume type (a second NTFS
  volume, a network share, exFAT): `set TEMP=D:\tmp` before starting. Report which file system each run used. Paths with spaces (`C:\Users\First Last\...`) are supported.

## Procedure

From a checkout of the commit under test, in a Windows terminal (`cmd` or PowerShell), at the repository root:

```bat
Rscript tools\validation\windows\run-validation.R
Rscript tools\validation\windows\run-validation.R --full
```

The first command is the quick check (about ten minutes with `arrow` installed): it records the environment, builds and runs the
filesystem harness on its own, installs the package into a scratch library, and runs the sixteen result-file, spatial-output, multi-radius and
file-input test files. The second additionally runs `tools\ci\check-local.R` (all gates, `R CMD check --as-cran`, the Windows skip
inventory); it takes much longer and needs the complete set of suggested packages. Both write `windows-validation-<timestamp>\`; `SUMMARY.txt`
there lists every step as PASS/FAIL.

To run only the filesystem harness by hand (an empty directory on the volume under test):

```bat
g++ -std=c++17 -I src tools\validation\windows\fs-harness.cpp -o fs-harness.exe
mkdir D:\harness-work
fs-harness.exe D:\harness-work
```

## What to return

Zip the `windows-validation-<timestamp>` directory (it contains `SUMMARY.txt`, `environment.txt`, `fs-harness-run.log`, `install.log`,
`tests.log`, `tests-summary.txt` and, with `--full`, `check-local.log` and the copied `.local\ci-check` logs) and send it for review. If a
step fails, also send the output of `Rscript -e "sessionInfo()"` and the directory listing of the temporary directory (leftover
`.rpst-*.partial` files are informative).

## Expected result

* `fs-harness`: 0 failed. `SKIP` lines are acceptable only for symbolic or hard links the account or file system cannot create. The
  `INFO replace while a reader ...` line shows how the system answers a replacement while a reader without `FILE_SHARE_DELETE` holds the
  target (the old file must be intact when it is refused).
* Tests (the runner enforces this): the test subprocess exits 0, all 16 files report a summary with tests, no failures or errors, and the only skips are the four inventoried in `tools/ci/windows-test-skips.tsv` (device/FIFO path
  checks, two `ulimit -f` tests). Symbolic-link assertions print `NOTE: symbolic-link assertions were not run` when links cannot be made.
* With `--full`: `Local full check passed (windows)`.

## Recorded results

| Commit | Result |
| --- | --- |
| `8ead7e4` | Quick procedure passed. Full development suite passed (160,438 expectations). `R CMD check` completed with one NOTE (Rd line widths: `man/pst_result_file.Rd` examples comment wider than 100 characters); the strict full gate rejected it, so the full gate did not pass. |
| `338a36a` | Only wraps that comment (R source and Rd). Targeted Linux checks passed (`tools::checkRd`, `\examples` line-width scan, roxygen/Rd sync). **A clean Windows check at this commit is not yet established**; the 28-minute test suite was deliberately not rerun for the wrapping alone. |

### Follow-up results and merge decision (2026-10-28)

The maintainer reported these additional results at `7681c0528142673e345434efb01414307eed66c8`:
- Windows package/documentation check with `--no-tests`: exit 0, `Status: OK`. The Rd NOTE is resolved.
  Review this alongside the 160,438-expectation Windows pass at `8ead7e4`; it is not a new strict full-gate pass.
- macOS Arrow-enabled full gate: 160,493 expectations, `Status: OK`, exact warning policy passed
  (17 inventoried compiler diagnostics, 0 significant diagnostics), vendor/provenance verification passed.

These are user-reported console results; detailed archives remain with the maintainer and have not been independently reviewed here.
The earlier table records the historical state at each commit; the Windows follow-up is now complete.

The maintainer authorised merging PR #66 on this evidence. The Arrow-enabled Linux gate has **not run**:
Arrow was unavailable and CRAN unreachable in the Linux environment, while GitHub Actions capacity is exhausted.
Linux validation is deferred to the final pre-CRAN checks when Actions becomes available, rather than blocking this merge.
No workflow was launched and no warning policy, test assertion or skip inventory was relaxed.

The all-platform frozen-release matrix in [release checklist](../../../docs/release-checklist.md) item 1 remains required
before submission. Conservative pending-validation wording and the POSIX example guard remain until final release review.
Any subsequent code or test changes require validation appropriate to those changes.

## What is deliberately not covered

A genuinely full disk and permission-denied directories cannot be provoked portably on Windows; the write-failure paths are covered by the
mocked-writer tests in `test-result-publication.R` (identical code path after a failed write: temporary removed, old destination intact).
