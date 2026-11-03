# Exact pinned PST warning policy

The pinned PST sources (v3.3.2, commit `63df80a2cf3dd289be95ea3d91667c3490719b75`) emit compiler diagnostics that rPSTool does
not suppress. The policy permits their exact observed diagnostics in development CI. No warning flags, upstream statements or
numerical behaviour are changed.

## Inventories

- [macOS](macos-pst-warnings.tsv): 17 compiler diagnostic occurrences (17 distinct signatures), 0 R CMD check significant
  diagnostics.
- [Windows](windows-pst-warnings.tsv): 20 compiler diagnostic occurrences (20 distinct signatures), 0 significant diagnostics.
- [macOS SDK 27](macos-sdk27-pst-warnings.tsv): empty (header only).
- Ubuntu permits zero compiler or R CMD check warnings.

Every `-Wswitch`, `-Wbitwise-instead-of-logical`, `-Wreorder`/`-Wreorder-ctor`, `-Wclass-memaccess`,
`-Wnonportable-include-path` and SDK 27 `-Wunused-result` diagnostic is eliminated through reversible build-copy
transformations (`src/portability/fix-diagnostics.R` and extensions of `harden-raster.R`, `harden-isovist.R`, `limit-workers.R`;
patch 0011 in `inst/upstream/PATCHES.md`). A log with an unexpected remaining or missing signature fails the gate and is
reviewed. With no check-phase rows, macOS and Windows must report a clean installation check (`Status: OK`).

Each TSV entry records the phase (`compiler` or `check`), the exact occurrence count and the complete signature (source path,
line, column, message, template type where present, warning option). Counts are multisets, so parallel compiler scheduling
cannot change the result. R CMD check removes some repeated diagnostics and classifies only some as significant, so the
`check` inventory is distinct from the complete `compiler` inventory.

| Diagnostic option | macOS count | Windows count | Source |
|---|---:|---:|---|
| `-Wdelete-non-abstract-non-virtual-dtor` | 1 | 0 | Worker with virtual methods and non-virtual destructor |
| `-Wsign-compare` | 0 | 7 | Signed/unsigned comparisons |
| `-Wunused-variable` | 10 | 9 | Unused upstream locals |
| `-Wunused-but-set-variable` | 2 | 2 | Assigned but unused upstream locals |
| `-Wunused-lambda-capture` | 2 | 0 | Unused upstream captures |
| `-Wunused-function` | 2 | 2 | Unused upstream helpers |

The libc++ diagnostic in `__memory/unique_ptr.h` for `CAttractionAlgo::CWorker` qualifies only with the exact accompanying
instantiation note at pinned `AttractionReach.cpp:214:6`. Only the SDK root is normalised: the Xcode root pairs only with
`unique_ptr.h:77:5` and the CommandLineTools root (`/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/c++/v1/`)
only with `:75:5`. Every other allowed source must resolve to a file in the pinned inventory or the generated
`CalculateIsovists.cpp`.

## Enforcement

`check-package.R` runs `R CMD build --no-manual` and `R CMD check --no-manual --as-cran`. `pst-warning-policy.R` then requires:

1. Offline vendor and provenance verification before and after checking.
2. A successful source build without warnings, and a completed installation and R CMD check.
3. Exact compiler signature/count equality, including warnings omitted from R CMD check's significant-warning summary. Any
   additional installation warning or unrecognised warning output fails.
4. On macOS/Windows, no R CMD check warning or error and no NOTE. Ubuntu admits zero warnings and only two environmental
   NOTEs, each at most once and with its exact body: *checking for future file timestamps* (`unable to verify current time`)
   and *checking compilation flags used* (`Compilation used the following non-portable flag(s):` followed by exactly
   `-march=nocona`, injected by the conda-forge toolchain, not by rPSTool's Makevars). Any other NOTE, a duplicate section, or
   a `Status:` line that is absent or disagrees with the NOTE count fails. A new environmental NOTE must be added to
   `pst_environmental_notes` with its evidence.
5. Successful package tests with a positive pass count and zero failures and warnings. Skips: none on Linux/macOS; on
   Windows exactly the inventory in [`windows-test-skips.tsv`](windows-test-skips.tsv) (4 tests: the two POSIX-only
   device/FIFO path checks and the two `ulimit -f` full-disk tests). `test-warning-policy.R` re-derives the inventory from the
   test sources, so adding a Windows-only skip requires a reviewed inventory change. A skip for any other reason fails.
6. A passing run leaves `tests/testthat.Rout`; a failing run leaves `tests/testthat.Rout.fail`, which is printed in full.

Previous results are removed before each invocation so stale artifacts cannot be validated.

`Rscript tools/check-wrapper-warnings.R [unit ...]` (developer aid, not a gate) compiles the rPSTool-owned C++ units with the
compiler and flags R is configured with plus `-Wall` and reports any non-vendor diagnostic, so warnings in rPSTool's own code
can be found without a full `R CMD check`.

CI runs `test-warning-policy.R` on every platform. Its fixtures and mutation tests exercise added, removed, repeated and
changed diagnostics, source drift, unknown check warnings, test failures, missing results, abnormal exit status and realistic
Linux NOTE excerpts. No warning class is suppressed and no R CMD check warning is globally ignored. A compiler upgrade, a
changed warning count (including fewer warnings), a new warning source or changed wording fails for review. Baseline updates
require an explicit review against the pinned source and new raw artifacts; CI never regenerates or broadens the allow-list.

## Fixtures

`fixtures/*-check.log`, `*-install.out` and `*-tests.Rout` are excerpts of observed macOS and Windows logs of a recorded manual
cross-platform run (GitHub Actions run 37528060812, rPSTool commit `6dcbefde5239054d9e364821af880d48d12a5610`), with LF line
endings. They predate the diagnostic fixes, so the tests check them against the earlier inventories preserved in
[`fixtures/pre-diagnostic-fix-inventories/`](fixtures/pre-diagnostic-fix-inventories).
