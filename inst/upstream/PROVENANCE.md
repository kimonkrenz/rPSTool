# PST source provenance

The vendored source is PST v3.3.2 from
https://github.com/SMoG-Chalmers/PST at commit
`63df80a2cf3dd289be95ea3d91667c3490719b75`.
The annotated tag object is `517bd88ba12a67558cbd8db2d6472e84bb54d7b0`.

`src/vendor/pstalgo/` contains all 119 files from upstream `pstalgo/include/`
and `pstalgo/src/`, plus its unchanged `README.txt` and `CMakeLists.txt`.
Upstream root `README.txt` and `LICENSE` are preserved here as
`PST_README.txt` and `PST_LICENSE`. All selected files remain byte-for-byte identical to the pinned archive,
including copyright/license headers. `FILES.md5` verifies the complete
pristine vendor tree without exclusions or patched fingerprints.
Python bindings, QGIS,
prebuilt libraries, and deployment tooling are excluded.

Refresh from the repository root with `Rscript tools/vendor-pstalgo.R`.
The helper accepts an optional local pinned-commit archive, validates its
paths, and refuses to overwrite a vendor tree with local differences.
`FILES.md5` is a portable content inventory, not a cryptographic signature.
Run `Rscript tools/verify-vendor.R` for an offline inventory check.
For an independent upstream comparison, compare the selected paths against
an archive fetched via HTTPS at the exact commit; never substitute master.

The native build compiles the complete core through `src/Makevars` and
`src/Makevars.win`, using the R C++17 toolchain. The source is included in
R source tarballs. Build-time adaptations are applied only to verified generated copies; see
[PATCHES.md](PATCHES.md). Compilation outputs are kept outside the vendor tree. The upstream CMake file is
reference metadata only and is not invoked by R installation.

## Licensing

Every PST file that carries a licence header (119 of the 121 vendored files) reads "Copyright 2019
Meta Berghauser Pont ... GNU Lesser General Public License ... either version 3 of the License, or
(at your option) any later version", i.e. LGPL-3-or-later. `CMakeLists.txt` and
`include/pstalgo/utils/Concurrency.h` have no header and are covered by the upstream distribution
licence (`PST_LICENSE`; `PST_README.txt` names Meta Berghauser Pont as copyright owner).
rPSTool-authored code is licensed LGPL-3-or-later (`DESCRIPTION`: `License: LGPL (>= 3)`); the LGPL-3 and
GPL-3 texts are in `inst/licenses/`. Attribution: `inst/COPYRIGHTS`; component matrix:
[`../../docs/licensing.md`](../../docs/licensing.md).
