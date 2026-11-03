# Build and platforms

## Build model

The vendored `pstalgo` C++ source is compiled as part of the ordinary R package build. Users need no separate PST, Python,
QGIS or CMake. `src/Makevars` and `src/Makevars.win` compile the 48 pinned PST translation units, plus the rPSTool bridge, with
R's C++17 toolchain; threads use `-pthread`; no `-march=native` or other non-portable flag is used. Objects are emitted under
`src/.rpst-build/`, outside the vendor tree; that directory is excluded from Git and from source tarballs and is removed by R's
`shlib-clean` target (including `R CMD INSTALL --preclean --clean`).

Adaptations of pinned source (include case, read-only type names, standard headers, safety guards, worker caps, compiler
diagnostic fixes) exist only in generated build copies under `src/.rpst-build/`, produced by the transformations in
`src/portability/` from preserved exact inputs in `inst/upstream/build-inputs/`. Each transformation fails on checksum drift, a
missing or repeated exact signature, an unexpected changed-line count or an incorrect output checksum, and keeps `#line`
directives so diagnostic locations still name the pinned file. Every adaptation is recorded in `inst/upstream/PATCHES.md`; the
recipes are verified by `tools/verify-vendor.R`.

On Windows a translation-unit adapter pairs `_aligned_malloc` with `_aligned_free` for upstream's MSVC-only aligned allocator
selection.

```sh
Rscript tools/verify-vendor.R
R CMD INSTALL --preclean .
R CMD build .
R CMD check --no-manual rPSTool_0.1.0.tar.gz     # use the current version's tarball name
```

## Platforms

Targets are macOS (Apple clang), Windows (Rtools) and Linux (GCC or clang). The package has no runtime downloads, needs no
network access during checks, bounds thread use in check environments (see the worker policy in
[architecture](architecture.md#threading-and-progress)), and writes only to temporary or user-specified locations. Validation
status is in [KNOWN_LIMITATIONS.md](../KNOWN_LIMITATIONS.md).

`arrow` (>= 25.0.0), `jsonlite` and `sf` are optional (`Suggests`); none is imported, linked or required to build, and rPSTool
links no libarrow. Vendored third-party sources (FlatBuffers headers, FlatGeobuf generated headers, Arrow C data/stream interface
declarations) are byte-pinned and hash-verified; their provenance is in `src/vendor/*/PROVENANCE.md` and
`src/arrow-c-abi/PROVENANCE.md`. `.gitattributes` marks those trees `-text` so they stay byte-exact under `core.autocrlf` on
Windows (checked by `tools/test-checkout-attributes.R`).

## Validation

`Rscript tools/ci/check-local.R` is the full local gate. It runs the vendor-integrity, portability, Arrow C ABI,
FlatBuffers/FlatGeobuf hash, floating-point, diagnostic-fix, graph-constructor, worker, isovist, raster and network-construction
gates (each with its mutation tests), the warning-policy tests and the native build lifecycle gate, then `tools/ci/check-package.R`
for the detected platform (`ubuntu`, `macos` or `windows`), which runs `R CMD build` and `R CMD check --as-cran` and validates the
logs against the warning policy. It stops at the first failure and keeps logs under `.local/ci-check`. The full test suite runs
once, under `R CMD check` ([testing](testing.md)).

`.github/workflows/R-CMD-check.yaml` provides the macOS / Windows / Ubuntu matrix; it runs only on manual dispatch. Windows can
also be checked through [R win-builder](https://win-builder.r-project.org/).

## Compiler diagnostics

The pinned PST code produces compiler diagnostics under common flags. rPSTool suppresses no warning class and does not change
upstream numerical behaviour to silence them. Diagnostics that R classifies as significant are removed through the verified
build copies (patch 0011 in `inst/upstream/PATCHES.md`); changes are casts, explicit `case` labels and initialiser
permutations, with no change to arithmetic, evaluation order or memory layout. The remaining diagnostics are recorded as exact
inventories (`tools/ci/*-pst-warnings.tsv`), and any added, removed or changed diagnostic fails the gate. The full contract is in
[`tools/ci/README.md`](../tools/ci/README.md).

## GCC 15

With GCC 15 the pinned `CalculateIsovists.h` fails to compile because libstdc++ 15 no longer includes `<stdint.h>`
transitively; the force-included `src/rpst-compat.h` declares `<cstdint>`. No vendored byte or numerical behaviour changes.

## Installed size

On Linux the shared library is about 1 MiB without debug information and about 15 MiB with Debian's default `-g -O2`. `R CMD
check` raises an installed-size NOTE above 5 MB, so the NOTE appears with Debian-style flags only. The package neither strips nor
overrides toolchain flags (CRAN does not allow stripping); the NOTE is explained in `cran-comments.md`.
