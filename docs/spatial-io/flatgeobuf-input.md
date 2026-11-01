# FlatGeobuf path input — compatibility and contract

`segment_graph(<FlatGeobuf path>)` is implemented through the same shared segment-graph builder as GeoParquet. This document records
what the code does and how it is tested. There is no `format=`/`geometry=` argument, no attribute or ID retention, no spatial
filter, no splitting, snapping, reprojection or CRS override, and no change to any PST algorithm or to the matrix, sf and GeoParquet
routes. The axial route is in [axial file input](axial-file-input.md).

## 1. Public API and dispatch

```r
segment_graph(x)    # x: numeric matrix | sf/sfc | ONE character path to a GeoParquet OR FlatGeobuf file
```

The file format is identified from the file's **content only** (never extension; no `format=`):

1. first four bytes `PAR1` → GeoParquet (the trailing `PAR1` is then required);
2. else first seven bytes `66 67 62 03 66 67 62` (any eighth, patch-level, byte) → FlatGeobuf major version 3;
3. else the FlatGeobuf family marker with another major version → explicit "unsupported major version" error;
4. else "unsupported file format".

A valid FlatGeobuf file whose last bytes happen to be `PAR1` is FlatGeobuf (the trailer is examined only on the
Parquet branch). Path validation (single non-empty string, existing, non-directory, readable, regular local file) is
shared with GeoParquet in `R/file-input.R`. The returned object is the ordinary `pst_segment_graph`.
`sf` is required (CRS parsing); `arrow`/`jsonlite` are **not** needed for FlatGeobuf.

## 2. File contract

| Item | Behaviour |
| --- | --- |
| Geometry | header `geometry_type` Unknown(0) or LineString(2); every feature a non-null, single-part LineString with exactly two finite XY vertices; header or feature Z/M/T/TM rejected |
| Row order | **physical file order** (an indexed FlatGeobuf is Hilbert-ordered; writer order is not recoverable) |
| `features_count` | 0 = unknown; otherwise must equal the decoded count exactly; bounded by file size / minimum record before any arithmetic or `reserve` |
| Index | `index_node_size` default 16, 0 = none, 1 invalid; index byte size computed with checked 64-bit arithmetic and must fit inside the file |
| CRS | §4 |
| Empty file (0 features) | rejected |
| Big-endian host | rejected |

## 3. Parser, ownership and bounds

Production parser: pinned header-only FlatBuffers 24.12.23 `Verifier` plus the FlatGeobuf-generated headers
(vendored pristine under `src/vendor/flatbuffers/` and `src/vendor/flatgeobuf/`, each with `SHA256SUMS`,
`PROVENANCE.md` and licence text; notices in `inst/COPYRIGHTS` and `inst/licenses/`; guarded by
`tools/verify-flatgeobuf-vendor.R` with mutation tests in `tools/test-flatgeobuf-vendor.R`, both part of
`tools/ci/check-local.R`). The Verifier is structural only (alignment on, depth 64, 1e6 tables).

* Streaming with `fread`/`fseek` (no mmap); one record in memory at a time; coordinates go straight into the
  contiguous `std::vector<double2>` consumed by the shared `rpst::segment_graph_build()`.
* Bounds: header ≤ 64 MiB, record ≤ 64 MiB, each size prefix ≤ remaining bytes, all offsets 64-bit and checked.
* Two native calls: `rpst_fgb_inspect(path)` (header only; returns facts + raw CRS strings) and
  `rpst_fgb_segment_graph(graph, path, header)`; the second **revalidates** that the header bytes are unchanged since
  inspection and re-derives all bounds. No persistent handle exists between them.
* Native safety: R arguments are staged and the output list is built before/after the C++ scope; errors go to a fixed
  buffer and `Rf_error` is raised only after all C++ owners have unwound. No exception crosses into R.

## 4. CRS

Only GDAL's exact unknown-CRS representation maps to `sf::st_crs(NA)`: org absent/empty, code absent/0, name exactly
`Undefined Cartesian SRS with unknown unit`, WKT exactly GDAL's ENGCRS string, description/code_string absent/empty.
An absent Crs table → `NA`. Anything else is passed to `sf` (EPSG code first, as GDAL does, then WKT): projected CRS
retained, geographic and uninterpretable CRS rejected.

## 5. Tests and evidence

* `tests/testthat/test-flatgeobuf.R` with GDAL-written fixtures (`tests/testthat/fixtures/flatgeobuf/`, hashes and
  provenance in its README) and R-level byte patches for declared-count and non-finite cases (a native test producer
  was not needed). Covers dispatch, equivalence with matrix/sf/GeoParquet results, CRS branches, every unsupported
  geometry shape, declared counts, index bounds, lying size prefixes, truncation, random corruption (no crash, no
  graph published), header revalidation, lifecycle, path validation and regression of matrix/sf behaviour.
* Shared helpers moved to `helper-segment-equivalence.R` (used by GeoParquet tests too).
* During development the production parser was compared with an independent minimal reader: 0 result differences, and 7 inputs accepted only by
  the production parser, all explained by the independent reader's extra "bad table size" check.
* Valgrind on the FlatGeobuf tests: no report in `rPSTool.so` (all third-party: libarrow allocator init, small sf/GDAL leaks).
* Indicative decode scale on one Linux machine: 5M segments ≈ 156 MiB / 1.5 s; 10M ≈ 309 MiB / 2.5 s (not a guarantee).

## 6. Platform status

The FlatGeobuf path passed the complete local validation on Linux x86-64 and on native macOS Apple Silicon (R 4.6.1, Apple clang)
when it was added, and the later full validation on Windows 11 x64 (R 4.6.1, Rtools GCC 14.3.0) covered it as well; the Windows-specific
code (`_wfopen` path handling, `_fseeki64` seeking, the Rtools `Rscript` generation of the `base.h` build copy) is therefore exercised
there. The final release state still needs the clean three-platform run listed in the [release checklist](../release-checklist.md).
The translation unit uses the established FP policy (`-ffp-contract=off`) and plain `-I` (R CMD check rejects `-isystem`) for the
third-party vendor directories in both `Makevars` and `Makevars.win`.

## 7. `base.h` and the R CMD check pragma rule

`R CMD check --as-cran` (`_R_CHECK_PRAGMAS_`) scans `src/` and `inst/include/` and rejects
`#pragma GCC diagnostic ignored`. Upstream FlatBuffers 24.12.23 `base.h` has two such suppressions
(`-Wstringop-overflow` for GCC 10 only, `-Wfloat-equal` for non-MSVC), each as a push/ignored block plus a matching
pop block. rPSTool follows its pristine-source → verified-generated-copy model:

* the exact upstream `base.h` is retained byte-for-byte (SHA-256 `3f28edd053106cfe229f3887b6f36153785afb347867c55b403da5eff3a88ef8`) at
  `inst/upstream/flatbuffers/include/flatbuffers/base.h`; the other 15 FlatBuffers headers and the FlatGeobuf files stay
  pristine in `src/vendor/`;
* `src/portability/strip-flatbuffers-diagnostics.R` generates `src/.rpst-build/flatbuffers/include/flatbuffers/base.h`
  (SHA-256 `1ef073aaafca01ccd944911ff4678a413884fa8dfb1eb42fecd9b405ad63f693`) by deleting exactly those four complete conditional blocks
  (14 lines); the MSVC `#pragma warning` handling and all code are untouched;
* `pst-flatgeobuf.o` depends on the generated file and compiles with `-I.rpst-build/flatbuffers/include` before
  `-Ivendor/flatbuffers/include` (portable `-I`; the pristine tree no longer contains `base.h`); `rpst-clean` removes it;
* `tools/verify-flatgeobuf-vendor.R` and `tools/test-flatgeobuf-vendor.R` fail closed on upstream hash, block count,
  duplicated/changed/additional suppressions, exact output, include order, generation dependency and clean recipe
  (Unix and Windows). The generated copy is a build compatibility artefact, not vendored source; FlatBuffers 24.12.23
  remains the parser authority.

## 8. Not implemented

External IDs/attributes, spatial filtering, z/m, multi-part/split, directories or
remote paths, cached/persistent file handles, big-endian hosts.
