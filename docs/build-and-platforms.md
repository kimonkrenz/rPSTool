# Build, platforms and continuous integration

## Build model

The vendored `pstalgo` C++ source is compiled as part of the ordinary R package build. Users need no separate PST, Python,
QGIS or CMake. `src/Makevars` and `src/Makevars.win` explicitly compile all 48 pinned PST translation units, plus the rPSTool
bridge, with R's C++17 toolchain; threads use `-pthread`; no `-march=native` or other non-portable flag is used. Objects are
emitted under `src/.rpst-build/`, outside the vendor tree; that directory is excluded from Git and from source tarballs and is
removed by R's `shlib-clean` target (including `R CMD INSTALL --preclean --clean`).

Adaptations of pinned source (include case, read-only type names, standard headers, safety guards, worker caps, diagnostic fixes)
live only in generated build copies under `src/.rpst-build/`, produced by the fail-closed transformations in `src/portability/`
from preserved exact inputs in `inst/upstream/build-inputs/`. Every transformation fails closed on checksum drift, a missing or
repeated exact signature, an unexpected changed-line count or an incorrect output checksum, publishes its output only after all
checks pass, and keeps `#line` directives so diagnostic locations still name the pinned file. The record of each adaptation is
`inst/upstream/PATCHES.md`; the exact recipes are verified by `tools/verify-vendor.R`.

On Windows a translation-unit adapter pairs `_aligned_malloc` with `_aligned_free` for upstream's MSVC-only aligned allocator
selection. `src/rpst-compat.h` is force-included into every C++ unit (it declares `<cstdint>`, which pinned
`CalculateIsovists.h` needs under GCC 15).

```sh
Rscript tools/verify-vendor.R
R CMD INSTALL --preclean .
R CMD build .
R CMD check --no-manual rPSTool_0.1.0.tar.gz     # use the current version's tarball name
```

## Platforms and CRAN constraints

Targets: macOS / Apple clang, Windows / Rtools, Linux / GCC or clang. The package has no runtime downloads, no required
network access during checks, bounded thread use in check environments (see the worker policy in
[architecture](architecture.md)), deterministic tests, lightweight examples, portable compilation flags, and writes only to
temporary or user-specified locations.

`arrow` (>= 25.0.0), `jsonlite` and `sf` are optional (`Suggests`); none is imported, linked or required to build, and rPSTool
links no libarrow. Vendored third-party sources (FlatBuffers headers, FlatGeobuf generated headers, Arrow C data/stream interface
declarations) are byte-pinned and hash-verified; their provenance is in `src/vendor/*/PROVENANCE.md` and
`src/arrow-c-abi/PROVENANCE.md`. `tools/test-checkout-attributes.R` guards that `.gitattributes` keeps those trees (`-text`)
byte-exact under `core.autocrlf` on Windows.

## Validation

`Rscript tools/ci/check-local.R` is the full local gate. It sequentially runs the pristine-vendor, portability, Arrow C ABI,
FlatBuffers/FlatGeobuf vendor-hash, floating-point, diagnostic-fix, graph-constructor, worker, isovist, raster and network
construction safety gates (each with its mutation tests), the exact warning-policy tests and the native build lifecycle gate, then
runs `tools/ci/check-package.R` for the detected platform (`ubuntu`, `macos` or `windows`), which performs `R CMD build` and
`R CMD check --as-cran` and validates the logs against the warning policy. It stops at the first failure and keeps logs under
`.local/ci-check`. The lifecycle gate smoke-tests the installed package after cleanup and regeneration but does not run testthat;
the full suite runs once, under `R CMD check`.

`.github/workflows/R-CMD-check.yaml` provides the complete macOS / Windows / Ubuntu matrix. It is `workflow_dispatch` only (manual
cross-platform validation); pushes and pull requests do not launch it. Windows can additionally be checked through
[R win-builder](https://win-builder.r-project.org/).

## Compiler diagnostics and the exact warning policy

The pinned PST code produces compiler diagnostics under common flags. rPSTool does not suppress any warning class and does not
modify upstream numerical behaviour to silence them. Instead:

* `R CMD check` reports "1 WARNING" in the installation step only for diagnostics R classes as *significant* (`-Wswitch`,
  `-Wclass-memaccess`, GCC `-Wreorder`, `-Wbitwise-instead-of-logical`, `-Wunused-result`, `ISO C` pedantic messages). Every such
  site in the pinned source is removed through verified, reversible build copies (patch 0011 in `inst/upstream/PATCHES.md`;
  `src/portability/fix-diagnostics.R` and extensions of the raster, isovist and worker transformations; tests
  `tools/test-diagnostic-fixes.R`). The changes are casts, explicit `case` labels, initialiser permutations and the like; no
  arithmetic, evaluation order, enum mapping, memory layout or lifetime changes, verified by the exact-restoration check of every
  transformation and by the unchanged numerical suite. The include-case shim that caused 33 macOS diagnostics was removed.
* The remaining non-significant diagnostics (`-Wunused-variable`, `-Wunused-but-set-variable`, `-Wunused-function`,
  `-Wunused-lambda-capture`, `-Wsign-compare`, `-Wdelete-non-abstract-non-virtual-dtor`) are recorded as exact inventories
  (`tools/ci/*-pst-warnings.tsv`) and enforced as multisets, so any added, removed, changed or rPSTool-owned diagnostic fails for
  review. Ubuntu permits none. The full contract of the gate — environmental NOTE handling, the Windows skip inventory, log
  validation — is in [`tools/ci/README.md`](../tools/ci/README.md).
* Possible further cleanup (not required for a clean install log): annotating the remaining unused entities, explicit casts for
  the sign comparisons, `final` on the attraction worker class, and header overlays for `-pedantic` anonymous-struct diagnostics
  (`__extension__ union`). None would touch an algorithm. Real defects noticed in pinned code (a `%d`/`%s` mismatch in an
  unreachable `LOG_ERROR`, an unchecked `fopen` in an unreferenced function, a non-virtual destructor in a class with virtual
  methods) are upstream matters and are not changed.

The internal warning policy accepting the inventoried diagnostics is not a statement that CRAN accepts them; on the last real
macOS and Windows runs the install step reported `Status: OK` with 0 significant diagnostics.

## GCC 15 and installed size

With GCC 15 the pinned `CalculateIsovists.h` fails to compile because libstdc++ 15 no longer includes `<stdint.h>` transitively; the
force-included `src/rpst-compat.h` declares `<cstdint>` (no vendor byte, transformation or numerical behaviour changes).

On Linux the shared library is about 1 MiB without debug information and about 15 MiB with Debian's default `-g -O2`. `R CMD check`
raises an installed-size NOTE above 5 MB, so the NOTE appears with Debian-style flags only. R's *Writing R Extensions* states that
CRAN does not allow stripping, so the package neither strips nor overrides toolchain flags; the NOTE is explained in
`cran-comments.md`.
