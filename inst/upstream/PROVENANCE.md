
# PST source provenance

The vendored source is PST v3.3.2 from
https://github.com/SMoG-Chalmers/PST at commit
`63df80a2cf3dd289be95ea3d91667c3490719b75`.
The annotated tag object is `517bd88ba12a67558cbd8db2d6472e84bb54d7b0`.

`src/vendor/pstalgo/` contains all 119 files from upstream `pstalgo/include/`
and `pstalgo/src/`, plus its unchanged `README.txt` and `CMakeLists.txt`.
Upstream root `README.txt` and `LICENSE` are preserved here as
`PST_README.txt` and `PST_LICENSE`. All selected files are preserved
byte-for-byte from the pinned upstream archive. `FILES.md5` records
checksums for the complete vendored PST source and preserved upstream
documents. `tools/verify-vendor.R` checks file contents and the vendored
file set against this inventory. Python bindings, QGIS, prebuilt
libraries and deployment tooling are excluded.

Refresh from the repository root with `Rscript tools/vendor-pstalgo.R`.
The helper accepts an optional local pinned-commit archive, validates its
paths, and refuses to overwrite a vendor tree with local differences.
`FILES.md5` is a portable content inventory, not a cryptographic signature.
Run `Rscript tools/verify-vendor.R` for an offline inventory check.
For an independent upstream comparison, use an archive of the pinned
commit rather than a moving branch.

The native build compiles the complete core through `src/Makevars` and
`src/Makevars.win`, using the R C++17 toolchain. The source is included in
R source tarballs. Build-time adaptations are applied only to verified
generated copies; see [PATCHES.md](PATCHES.md). Compilation outputs are
kept outside the vendor tree. The upstream CMake file is reference
metadata only and is not invoked by R installation.

## Licensing

The vendored PST source files include copyright and licence notices
identifying Meta Berghauser Pont (2019) and the GNU Lesser General Public
License, version 3 or later (LGPL-3-or-later). `CMakeLists.txt` and
`include/pstalgo/utils/Concurrency.h` have no individual licence headers;
the upstream `README.txt` contains a separate licence statement.
The upstream distribution licence is preserved in `PST_LICENSE`, and
`PST_README.txt` identifies Meta Berghauser Pont as the copyright owner.

rPSTool-authored code is licensed LGPL-3-or-later (`DESCRIPTION`:
`License: LGPL (>= 3)`); the LGPL-3 and GPL-3 texts are in `inst/licenses/`.
Attribution: `inst/COPYRIGHTS`; component matrix:
[`../../docs/licensing.md`](../../docs/licensing.md).
