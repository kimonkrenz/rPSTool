# GeoParquet path input — compatibility and contract

`segment_graph(<GeoParquet path>)` is implemented. This document records what the code does and how it is tested. There are no
`geometry=`/`format=` arguments, no external IDs, no GeoParquet 2.0, no native GeoArrow encodings, no directories, multi-file or cloud
paths, no splitting, snapping, reprojection or CRS override, and no change to any PST algorithm or to the matrix constructor's
semantics. The axial route is in [axial file input](axial-file-input.md).

## 1. Public API

```r
segment_graph(x)     # x: numeric matrix | sf/sfc | ONE character path to a GeoParquet file
```

A character vector without a `dim` attribute is the file route (a character *matrix* still takes
the unchanged matrix path and its unchanged error). The route is chosen by type only: there is no
`format=` argument and no file-extension requirement. The returned object is the ordinary
`pst_segment_graph` (same fields, same native owner, same tag/finaliser/lifecycle counters);
only `crs` is retained. Row order of the file is the graph segment order.

## 2. Optional dependencies and capability check

`Suggests: arrow (>= 25.0.0), jsonlite` (plus the existing `sf`). Nothing is `Imports`ed or
`LinkingTo`ed, rPSTool links no libarrow, uses no Arrow C++ ABI and no nanoarrow. Before any
native pointer exists, `.pst_geoparquet_capabilities()` requires `arrow`, `jsonlite` and `sf`
to be installed, `packageVersion("arrow") >= 25.0.0`, the exports `open_dataset`, `Scanner`,
`as_record_batch_reader`, `ParquetFileReader` and `RecordBatchReader` and
`RecordBatchReader$export_to_c`; otherwise it raises a clear error. Scanner compatibility is
established by the public `arrow::as_record_batch_reader(scanner)` call itself (still before any
native pointer exists), whose failure is reported as a clear rPSTool error. No `arrow:::` private API is used. The only use of `export_to_c()` is the single
helper `.pst_geoparquet_export_reader()`, which re-checks the reader class and method.
The first implementation and its tests target `arrow >= 25.0.0` (tested: 25.0.0); acceptance of
a newer version is not a claim that it was tested.

## 3. File contract

| Item | Behaviour |
| --- | --- |
| Path | one non-`NA`, non-empty local path to a **regular file** (checked with `stat` before anything opens it: directories, FIFOs and devices are errors); `PAR1` must be at both the beginning and the end of the file (extension irrelevant) |
| Rows | the footer row count must be ≥ 1 (a zero-row file is an error, as for matrices) |
| `geo` metadata | required; valid JSON object (`jsonlite::fromJSON(simplifyVector = FALSE)`); `version` matching `^1\.[01]\.[0-9]+$` (released 1.0/1.1 family); GeoParquet 2.0 and pre-release strings are rejected |
| Geometry column | `primary_column` (one non-empty string) which must be described in `columns`, have `encoding` exactly `"WKB"`, and exist in the file. Other geometry columns are ignored. `geometry_types` is **not** trusted |
| `edges` | absent or exactly `"planar"`; anything else (including `"spherical"`) is rejected |
| `crs` key absent | GeoParquet default OGC:CRS84 (geographic) → **rejected** |
| `"crs": null` | unknown CRS → allowed; the graph's `crs` attribute is `sf::st_crs(NA)`, the same value the sf route gives for unknown CRS |
| `crs` object | interpreted by `sf::st_crs()` after re-serialising the PROJJSON; unparseable/`NA` → rejected; `sf::st_is_longlat()` → rejected; otherwise retained unchanged (no transform, no override) |
| Rows | every row exactly a non-null, 2D `LineString` with exactly two finite vertices (WKB, either byte order per row, 41 bytes). Null / empty / Z / M / ZM / multipart (including one-part) / any other type / EWKB flags or SRID / non-finite → error naming the first offending **one-based** row. Polylines are never split |
| IDs | none read, retained or remapped; other columns are never read (the scan projects the geometry column only) |

Any failure — metadata, stream, producer or geometry — discards everything decoded and publishes
no graph.

## 4. Native decoder contract (`src/pst-geoparquet.cpp`)

The R side exports a geometry-only, single-threaded `Scanner` (via the documented
`arrow::as_record_batch_reader()`) into an rPSTool-owned `ArrowArrayStream` and then drops the
reader (exporting does *not* move it; consuming it later would steal batches). The native
side decodes into one `std::vector<double2>` of two endpoints per row and passes it to the
**same** shared builder as the matrix route, `rpst::segment_graph_build` (extracted from the
matrix constructor with identical validation, descriptor and PST call; it additionally
enforces the native count bound itself before any narrowing).

**Ownership.** The stream external pointer (tag `rPST::ArrowArrayStream/v1`) owns one calloc'd
struct; the tagged pointer and finaliser exist *before* the calloc. The finaliser clears the
pointer, calls `release` once only if still live, and frees. Exact-tag validation happens
before any dereference; a correctly tagged dead (freed/deserialised) pointer is an ordinary
state for `is_live`/`release`/`free`. The empty graph pointer and the stream pointer are
allocated and `on.exit` cleanup installed before the reader is exported. The decoder releases
the stream **before** PST builds the graph.

**Trust boundary.** The producer is trusted for physical buffer sizes and for buffer lifetime
while an Arrow object is live. The C Data Interface exposes no buffer byte lengths and none are
invented. Everything that *is* exposed is validated before use with checked arithmetic:

* callbacks `release`, `get_schema`, `get_next`, `get_last_error` required; `get_last_error` is
  called only after a failed operation and its text is copied into rPSTool storage before anything
  else;
* schema: struct `+s`, exactly one non-NULL child, no dictionaries, the child live, named exactly
  as the primary column, format `z` (BINARY) or `Z` (LARGE_BINARY), no children (a legal non-NULL
  `children` pointer with `n_children == 0` is accepted and never dereferenced);
* arrays: non-negative lengths/offsets, buffer counts (parent 1, geometry 3), `n_children`,
  no dictionaries; slicing is `physical = child.offset + parent.offset + i` and the child must
  cover `parent.offset + parent.length`; all of `offset + length`, the combined offset, the
  offsets-buffer index `k`/`k+1` (scaled by the offset width) and each value's end offset are
  checked against the addressable range (`PTRDIFF_MAX`; a fail-closed test hook can only lower it
  to simulate a smaller address space); `start ≥ 0` and `end ≥ start`;
* nulls: `null_count ≥ -1` and ≤ length; a missing bitmap is allowed only for `null_count == 0`
  (so `-1` and positive counts need a bitmap); a known count must equal the bitmap's nulls over a
  complete range and may not be exceeded over a sliced range; parent and geometry nulls are
  row-specific errors;
* a NULL data buffer is accepted only for a zero-length value, which then fails WKB validation
  by length before anything is read;
* WKB is validated in stages (length before every read): truncation (`<5`, `<9`, `<41`), byte
  order marker, type exactly 2 (ISO Z/M/ZM, EWKB bits and every other type rejected), point count
  exactly 2, overlong (`>41`), finite coordinates;
* the number of streamed rows must equal the footer row count (more and fewer both fail).

**R/C++ safety.** All R-facing checks run before any C++ owner; once Arrow guards (`StreamGuard`,
`SchemaGuard`, `ArrayGuard`) and the coordinate vector are live there is no R API call and no
`Rf_error`: failures are captured in a fixed char buffer, all owners unwind, then `Rf_error`.
No C++ exception leaves `.Call`.

## 5. Test layers

| Layer | File | Needs `arrow`? |
| --- | --- | --- |
| Native Arrow boundary: ownership/lifecycle, callbacks, schema, array layout, slicing, nulls, offsets/addressability, NULL data, WKB staging, row counts, lifecycle counters (made == released for schemas, arrays and streams in every case) driven by the internal synthetic producer `src/pst-arrow-test-stream.cpp` | `test-arrow-native.R` | no |
| Real `arrow` end-to-end with committed pyarrow-written fixtures (`tests/testthat/fixtures/geoparquet/`, provenance in `MANIFEST.tsv`, generator `tools/make-geoparquet-fixtures.py`, development only) incl. BINARY and LARGE_BINARY, mixed endianness, row-group boundaries, extra columns, two geometry columns, non-sequential IDs, every metadata/CRS/edges rejection, row-level errors, path/magic-byte validation, capability checks, lifecycle | `test-geoparquet.R` | yes (skipped cleanly only when `arrow >= 25.0.0`, `jsonlite` or `sf` is not installed; not skipped under CRAN-mode local harnesses) |
| Computational equivalence: path vs matrix vs sf for **every** currently bound segment-graph analysis (a test derives the list of consumers from the namespace so it cannot go stale), compared with `expect_identical` | `test-geoparquet.R` | yes |
| Arrow ABI declarations | `tools/verify-arrow-abi.R`, `tools/test-arrow-abi.R` (in `tools/ci/check-local.R`) | no |
| FP policy / object inventory for the two new translation units | `tools/test-fp-policy.R`, `tools/verify-vendor.R` | no |

## 6. Indicative Linux measurements

Measured once per row in a fresh process on a Linux x86-64 container (4 cores, R 4.5.3, `arrow` 25.0.0 from conda-forge, default mimalloc
pool) with a synthetic, perfectly regular endpoint-connected lattice (WKB, zstd, `crs: null`, a non-sequential id column), so timings carry
ordinary noise and the files compress unrealistically well. "Matrix" rows build the same coordinates as an `n x 4` matrix in the same process
before the window and call `segment_graph(<matrix>)`, for context only. These are observations, not guarantees; the measurement scripts were
development-only and are not retained.

| Segments | Row groups (size) | File | Route | Peak RSS (VmHWM) | Peak above start | Arrow pool max | Wall time |
| ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: |
| 5 000 000 | 77 (65 536) | 22.3 MiB | path | 1156 MiB | 1025 MiB (~205 B/seg) | 102 MiB | 5.65 s |
| 5 000 000 | 77 (65 536) | 22.3 MiB | matrix | 1077 MiB | (matrix 153 MiB held) | n/a | 5.70 s |
| 5 000 000 | 5 (1 048 576) | 11.4 MiB | path | 1216 MiB | 1085 MiB | 195 MiB | 5.42 s |
| 10 000 000 | 153 (65 536) | 44.1 MiB | path | 1959 MiB | 1828 MiB (~183 B/seg) | 194 MiB | 12.72 s |
| 10 000 000 | 153 (65 536) | 44.1 MiB | matrix | 2031 MiB | (matrix 305 MiB held) | n/a | 12.82 s |

The path route's peak is of the same order as the in-memory matrix route's *total* peak while needing no `sf` object and no R coordinate
matrix (the `sf` route measured about 900 B/feature and about 44 s per million features). PST's construction itself dominates. Arrow's own memory
is row-group-sensitive (the pool maximum roughly doubles from 65 536- to 1 048 576-row groups), and a share of it stays resident after the scan
because the allocator retains freed pages: at 5 M rows with 65 536-row groups the process peak was 1144 MiB (mimalloc, the default here),
1066 MiB (`ARROW_DEFAULT_MEMORY_POOL=system`) and 855 MiB (`jemalloc`). The pool and allocator belong to `arrow`, not to rPSTool; no claim is made
that peak memory is bounded by a scanner batch size. A single giant row group at 10 M rows and sizes above 10 M were not measured.

## 7. Evidence and limits

* The Arrow C stream boundary was demonstrated for R 4.5.3 / `arrow` 25.0.0 / libarrow 25.0.0 on Linux x86-64 (conda-forge), and the
  end-to-end tests ran there. The complete local harness, including the real-`arrow` GeoParquet tests (zero failures, warnings or skips), has
  also passed on native macOS Apple Silicon (R 4.6.1, Apple clang 21.0.0) and, in a later full validation, on Windows 11 x64. Other
  platforms and `arrow` builds are not claimed; the final release state still needs the clean three-platform run in the
  [release checklist](../release-checklist.md).
* The decoder cannot detect storage corruption beyond what the Parquet reader detects.
* Peak Arrow memory is **row-group-sensitive**: it is not bounded by a scanner batch size, and files with large row groups are not rejected.
* Real networks are mostly polylines; this route serves only pre-segmented two-vertex networks (no implicit splitting).
* The decode is not interruptible (no R callback may run while Arrow objects are live).

Vendored PST bytes are unchanged. The Arrow ABI declarations and their provenance are recorded in
[`src/arrow-c-abi/PROVENANCE.md`](../../src/arrow-c-abi/PROVENANCE.md).
