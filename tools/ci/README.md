# Exact pinned PST warning policy

The pinned PST sources emit compiler diagnostics that rPSTool does not suppress. The policy permits their exact observed diagnostics in
development CI; it does not make the package warning-free or claim CRAN acceptance. No warning flags, upstream statements or numerical
behaviour are changed.

The source remains PST v3.3.2, commit `63df80a2cf3dd289be95ea3d91667c3490719b75`. The inventories are:

- [macOS exact inventory](macos-pst-warnings.tsv): 17 compiler diagnostic occurrences (17 distinct signatures) and **0** R CMD check
  significant diagnostics.
- [Windows exact inventory](windows-pst-warnings.tsv): 20 compiler diagnostic occurrences (20 distinct signatures) and **0** significant
  diagnostics.
- [macOS SDK 27 inventory](macos-sdk27-pst-warnings.tsv): empty (header only; see below).
- Ubuntu permits zero compiler or R CMD check warnings.

Every `-Wswitch`, `-Wbitwise-instead-of-logical`, `-Wreorder`/`-Wreorder-ctor`, `-Wclass-memaccess`, `-Wnonportable-include-path` and
SDK 27 `-Wunused-result` diagnostic is eliminated through reversible build-copy transformations only (`src/portability/fix-diagnostics.R`
and extensions of `harden-raster.R`, `harden-isovist.R`, `limit-workers.R`; patch 0011 in `inst/upstream/PATCHES.md`). Before those fixes the
inventories were macOS 70 compiler / 8 significant plus 2 for SDK 27, and Windows 56 / 29. The earlier inventories are preserved verbatim in
[`fixtures/pre-diagnostic-fix-inventories/`](fixtures/pre-diagnostic-fix-inventories) because the observed macOS/Windows logs in `fixtures/`
predate the fixes; they remain tested against those copies. The current inventories were derived from the removed signature classes, verified on
Linux GCC 13 / Clang 18, and confirmed by real macOS and Windows runs of the full local gate (`Status: OK`, 0 significant diagnostics). A log with
an unexpected remaining or missing signature must fail this gate and be reviewed, never allowlisted blindly.

With no check-phase rows, macOS and Windows must report a clean installation check (`... OK`, no significant-warning block, `Status: OK`); the
earlier `WARNING` block is rejected.

Each TSV entry records the phase (`compiler` or `check`), exact occurrence count, and complete signature:
source path, line, column, message, template type where present, and warning option.
The counts are multisets so parallel compiler scheduling cannot change the result.
R CMD check removes some repeated diagnostics and classifies only some warnings as
significant; its separate `check` inventory is therefore deliberately distinct
from the complete `compiler` inventory. The inventories are authoritative, not
the following category summary:

| Diagnostic option | macOS compiler count | Windows compiler count | Upstream debt |
|---|---:|---:|---|
| `-Wdelete-non-abstract-non-virtual-dtor` | 1 | 0 | Worker with virtual methods and non-virtual destructor |
| `-Wsign-compare` | 0 | 7 | Signed/unsigned comparisons |
| `-Wunused-variable` | 10 | 9 | Unused upstream locals |
| `-Wunused-but-set-variable` | 2 | 2 | Assigned but unused upstream locals |
| `-Wunused-lambda-capture` | 2 | 0 | Unused upstream captures |
| `-Wunused-function` | 2 | 2 | Unused upstream helpers |

The single libc++ diagnostic is emitted in `__memory/unique_ptr.h:77:5` for
`CAttractionAlgo::CWorker`. It qualifies only with the exact accompanying
instantiation note at pinned `AttractionReach.cpp:214:6`. Only the Xcode SDK root
is normalized; the header suffix, line/column, message/type/option and pinned
instantiation site must match. Every other allowed source must resolve to a file
in the pinned inventory or the documented generated `CalculateIsovists.cpp`.
Compatibility adjustments (each verified against an exact current build):

- The `pstalgo/graph/AxialGraph.h:26:10` count is 13: every translation unit that
  includes the header emits one diagnostic, and the `pst-graph.cpp` wrapper (added
  after the frozen run) is the thirteenth includer. The earlier macOS install
  fixture is migrated by one exact line in `test-warning-policy.R`.
- The libc++ diagnostic may also be spelled with the CommandLineTools SDK root
  (`/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/c++/v1/`), which pairs only with
  `unique_ptr.h:75:5` (the Xcode root pairs only with `:77:5`); both pairs are normalized to the single canonical form above and no
  other line is accepted.
- [`macos-sdk27-pst-warnings.tsv`](macos-sdk27-pst-warnings.tsv) is now empty (header
  only). It formerly held two `-Wunused-result` diagnostics for the pinned
  `VERIFY(x.is_lock_free())` statements (`nodiscard` in the SDK 27 libc++); the build copies
  discard that value explicitly in the generated `AngularChoiceAlgo.cpp` /
  `SegmentBetweenness.cpp` copies, so those diagnostics are forbidden on every SDK.
- rPSTool-owned wrapper diagnostics are removed in source, not allowlisted: the unused
  `segment_graph_handle()` was deleted and the raster bound uses an explicit
  `static_cast<float>` of the same integer expression.

The validator still recognizes Clang's `-Wbitwise-instead-of-logical` advisory notes
only when the matching diagnostic is in the inventory; the inventory no longer contains
any, so none is admitted.

## Enforcement

`check-package.R` runs ordinary `R CMD build --no-manual` and
`R CMD check --no-manual --as-cran`, leaving compiler output and check logs
unchanged. `pst-warning-policy.R` then requires:

1. Pristine offline vendor/provenance verification before and after checking.
2. A successful source build without warnings; supported check exit status;
   completed installation and R CMD check.
3. Exact compiler signature/count equality, including warnings omitted from
   R CMD check's significant-warning summary. Any additional installation warning
   or unrecognized warning output fails.
4. Exactly the known installation-warning block, including its diagnostic multiset
   and single-warning status summary, on macOS/Windows. Every other R CMD check
   warning/error fails. Ubuntu retains zero-warning checking.
   **NOTE sections** are validated individually. macOS/Windows admit none. Ubuntu
   admits only two environmental NOTEs, each at most once and only with its exact
   diagnostic body (typographic quotes normalised, nothing else): *checking for
   future file timestamps* with the single line `unable to verify current time`
   (R could not verify the time; no network), and *checking compilation flags used*
   with `Compilation used the following non-portable flag(s):` followed by exactly
   `-march=nocona` (injected by the conda-forge compiler toolchain, not by rPSTool's
   Makevars). Any other NOTE — for example the foreign-function registration
   problems seen in an earlier run, dependency, documentation, size or portability notes — or a
   changed name/body, a duplicate section, or a `Status:` line that is absent,
   duplicated or disagrees with the number of NOTE sections actually present
   (`Status: OK`, `Status: 1 NOTE`, `Status: N NOTEs`) fails. A new environmental
   NOTE must be added to `pst_environmental_notes` together with its evidence.
5. Successful package test checks with a positive pass count and zero failures
   and warnings. Skips: **none** on Linux/macOS. On Windows exactly the approved
   inventory in [`windows-test-skips.tsv`](windows-test-skips.tsv) (4 tests whose
   source calls `skip_on_os("windows")`, directly or via a helper defined with it:
   the two POSIX-only device/FIFO path checks and the two `ulimit -f` full-disk tests). Each skip testthat reports as `'file:line:col'` under
   the reason `On Windows` is resolved against the test source to its enclosing
   `test_that()` description, which must sit on a skip call; the resulting multiset
   must equal the inventory exactly and agree with the summary line and section
   count. A skip for any other reason (e.g. a missing dependency), a test outside
   the inventory, a missing, extra or repeated entry, or a skip section without a
   matching summary fails. `test-warning-policy.R` re-derives the inventory from
   the test sources, so adding a Windows-only skip requires a reviewed inventory
   change. All rPSTool warnings, compilation/installation failures, and errors fail.
   Previous results are removed before each invocation so failures cannot be
   validated using stale artifacts.
6. Test logs: a passing run leaves `tests/testthat.Rout`; a failing run leaves
   `tests/testthat.Rout.fail`. `check-package.R` prints the complete failing log and
   stops with the original failure (a `.Rout.fail` is never validated as a result,
   both logs present or neither is an error, and a missing artifact reports the tail
   of `check.out` instead of a secondary "cannot open the connection").

`Rscript tools/check-wrapper-warnings.R [unit ...]` (developer aid, not a gate) compiles the rPSTool-owned C++ units with the
compiler and flags R is configured with plus `-Wall` and reports any non-vendor diagnostic in minutes, so Windows or macOS
warnings in rPSTool's own code (which the exact inventories deliberately do not admit) can be found without a full `R CMD check`.

CI runs `test-warning-policy.R` on every platform. Its saved CI fixtures and
mutation tests exercise added, removed, repeated and changed diagnostics, source
drift, missing/changed attribution, unknown check warnings, test failures/warnings,
missing completion/results, and abnormal exit status, plus realistic Linux NOTE
excerpts (accepted: none, each environmental NOTE, both; rejected: the foreign-function
registration NOTE alone and within its former `Status: 3 NOTEs` report, unknown or
changed or duplicated NOTEs, count/summary mismatches, and any NOTE on macOS/Windows). Raw check artifacts are
uploaded even when the gate fails.

No whole warning class is suppressed and no R CMD check warning is globally
ignored. A compiler upgrade, changed warning count (including fewer warnings),
new warning source/type, or changed diagnostic wording fails for review. Baseline
updates require an explicit, documented review against the pinned source and new
raw artifacts; CI never regenerates or broadens the allow-list automatically.

Fixture provenance: `fixtures/*-check.log`, `*-install.out` and `*-tests.Rout` are excerpts of the observed macOS and Windows logs of
a recorded manual cross-platform run (GitHub Actions run 37528060812, rPSTool commit `6dcbefde5239054d9e364821af880d48d12a5610`), with LF
line endings; `*-install.out` retains the warning lines, the exact libc++ attribution block and the successful installation marker.
