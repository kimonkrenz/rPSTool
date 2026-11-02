# Spatial output — a new GeoParquet / FlatGeobuf dataset with geometry, attributes and results

`spatial_output_file` is implemented for the analyses whose result has exactly one row per source feature. It never changes a PST
algorithm or a numerical result, and `output_file` stays the attribute-only Parquet route ([result files](result-files.md)).
Spatial output is implemented on POSIX systems and on Windows; the full development test suite and `R CMD check` passed on
Windows x86-64 at commit `4119f2b`.

## 1. Public API

```r
g <- segment_graph("roads.fgb")                  # or "roads.parquet" (GeoParquet); axial_graph(path) for axial analyses
angular_choice(g, radius = analysis_radius(steps = 3), spatial_output_file = "roads_choice.fgb")
```

`spatial_output_file = NULL` is **appended after `overwrite`** in `angular_integration()`, `angular_choice()`,
`network_integration()`, `network_reach()`, `network_betweenness()`, `od_betweenness()`, `attraction_reach()` and
`attraction_distance()`. Every earlier argument keeps its position, default and meaning.

* The analysis runs **once**. A NEW file is written and an invisible `pst_result_file` is returned (`path`, `rows`,
  `columns` = the non-geometry columns in file order, `format` = `"flatgeobuf"`/`"geoparquet"`, plus `spatial = TRUE`,
  `source`, `geometry_column`, `replaced`, `appended`).
* `output_file` and `spatial_output_file` are **mutually exclusive** (an error).
* `overwrite` applies to the destination file and, as of the output-naming scheme, to result columns that already exist in the source (they are replaced only in the new file). The source network is never written, replaced or touched.
* The graph must have been built **from a file path**. A matrix- or `sf`-built graph has no source file and gives an
  explicit error (reconstructing geometry from the graph is deliberately not offered).
* **Intentional contract, not a temporary restriction:** the output format equals the source format (GeoParquet →
  GeoParquet, FlatGeobuf → FlatGeobuf), the destination must end in `.parquet` (GeoParquet source) or `.fgb` (FlatGeobuf source) in any letter case — a missing, other or mismatched extension is rejected before anything is computed or created and nothing is renamed — the CRS is carried over
  unchanged and no reprojection or CRS inference is performed; cross-format conversion is out of scope.

Eligible (rows one-to-one with the source features): both angular analyses (`pst_segment_graph`), and on a `pst_graph`:
`network_integration(junctions = FALSE)`, `network_reach(origins = NULL)`, `network_betweenness()`, `od_betweenness()`,
`attraction_reach()`/`attraction_distance()` with `origin = "lines"`. Rejected before anything is computed:
`network_reach(origins=)`, junction results, other attraction origins. Segment Group Integration is per group, not per
segment, and has no `spatial_output_file`; projecting group scores onto their segments (as the Chalmers plugin's
`MapGroupValues` does) would be a separate, explicitly specified capability.

## 2. Source-to-result association (no join)

Result row `i` is source feature `i`, in the **physical record order** the graph reader used (rows of a GeoParquet file in
file order; records of a FlatGeobuf in file order — for a Hilbert-indexed FlatGeobuf that is the on-disk record order, not
the order of the writer that produced it). The readers reject rather than drop features, so the native count equals the
source count ([GeoParquet](geoparquet-input.md), [FlatGeobuf](flatgeobuf-input.md)). No spatial join, geometry
matching, external-ID lookup or R data-frame join exists. The implicit positional id column (`segment_id`, `line_id`,
…) is **not** written: position is the correspondence and the source keeps its own identifiers.

**The source must not be modified or reordered between graph construction and the completion of the spatial output.**
rPSTool records only lightweight provenance on file-built graphs (`attr(graph, "source")`: normalised path, format, row
count, size, modification time and, on POSIX, device/inode, on Windows volume serial number and file ID, held as exact strings; never geometry) and re-checks size, mtime and identity before
the analysis and again before publication, and the native row count against the source. These checks catch an obviously
changed file; they do **not** prove content identity (a same-size, same-mtime rewrite would pass; a corrupt record is
still caught by the writer's own validation). The source is never hashed.

## 3. Column semantics (the Chalmers PST add-or-replace rule, applied to the new file)

* A result column whose name equals a source column is a **collision**. With `overwrite = FALSE` (the default) the call stops
  before the analysis runs, with an error naming the conflicting columns, and nothing is written. With `overwrite = TRUE` the
  source column is **replaced** in place in the new file (same position, new type and nullability); the source file is never
  modified. The same `overwrite` argument also governs an existing destination file.
* Any other result column is **appended** (result order). Unrelated source columns, their types, nulls and values are
  preserved. Re-running the same analysis on its own output therefore needs `overwrite = TRUE`; no duplicate is ever written.
  Because result names identify the calculation (`docs/output-naming.md`), analyses of different radii or measures do not collide
  and accumulate in one dataset.
* Rejected, with nothing written: duplicate source column names; a result name equal to the GeoParquet geometry column;
  duplicate result names; for FlatGeobuf, source columns, or a source column and a result column, that differ only by ASCII
  letter case (GDAL looks fields up case-insensitively); a source column of unknown FlatGeobuf type; more than 65,535
  columns.

## 4. Writers

| | FlatGeobuf | GeoParquet |
|---|---|---|
| Mechanism | native, one sequential pass (`src/pst-flatgeobuf.cpp`), vendored FlatBuffers builder, no new dependency | R `arrow` (>= 25.0.0, optional) `ParquetFileWriter`, one `WriteTable` per source row group |
| Result input | the analysis' Arrow C stream is consumed directly: zero-copy float32/int32 slices of native memory | `RecordBatchReader$import_from_c` → table; zero-copy `Slice` per row group |
| Geometry | decoded source tables (type, ends, xy) re-encoded unchanged; header CRS, name, title, description, envelope, metadata carried over | the geometry column and the `geo` metadata pass through unchanged (CRS, bbox, covering stay valid) |
| Attributes | source property bytes copied byte for byte except replaced columns | Arrow columns pass through (types incl. uint64, dictionary, nested) |
| Nulls | a null result is an **omitted property** (the FlatGeobuf convention); native NaN, ±Inf, -0, -1 are ordinary values | exact Arrow nullability of the result fields |
| Index | **none, deliberately** (`index_node_size = 0`): a packed Hilbert R-tree reorders features and would break the correspondence | n/a; the source row-group layout is kept, except that an empty row group is dropped and a group larger than the writer's 1,048,576-row maximum is split |
| Compression | n/a | zstd (see §6) |
| Memory | one record + one builder + a 1 MiB output buffer | a few source row groups (garbage is collected every 4 row groups) + the result slice; Arrow pool observed in §6 |

Header metadata: GeoParquet keeps the source schema metadata (including `geo`) and adds/replaces the `rpst:*` provenance keys
of `output_file`. FlatGeobuf has **one** free-form header metadata string, so the header always describes the *latest*
calculation where that can be done safely: (a) the source has none → rPSTool's provenance object (`rpst:*` keys) is written;
(b) the source metadata is a flat JSON object of string values that already holds `rpst:*` keys (an earlier rPSTool analysis wrote
it) → every other pair is kept byte for byte, the old `rpst:*` pairs are dropped and the current ones appended (an earlier
calculation's parameters never survive); (c) anything else — non-JSON text, arrays, nested or non-string JSON, or an object
without `rpst:*` keys — is **preserved unchanged and no provenance is added** (it cannot be extended safely; the returned
descriptor and the data columns still describe the new calculation). Only (b) is recognised as rPSTool-owned; foreign metadata
is never parsed beyond that strict check or rewritten. Repeated analyses on rPSTool output, with replaced columns, are tested.

## 5. Safety and publication

The same primitives as `output_file` ([result files](result-files.md) §5): validation before anything is computed, an
exclusively created hidden same-directory temporary, no-clobber (`link(2)` / Windows `MoveFileExW` without replacement) or single-rename
publication, removal of the temporary on any error or interrupt, and a previous valid output left untouched by a failed write. The
Windows details and differences are in [result files](result-files.md) §5 item 6.

* The destination may not be the source: the same path, a symbolic link or a hard link to it (path comparison everywhere;
  `(device, inode)` where the platform provides it — a bind mount with a different device number is not detected) is
  rejected even with `overwrite = TRUE`.
* Native FlatGeobuf writing follows the established R/C++ error boundary: arguments are validated before any C++ owner exists,
  failures are captured in a buffer, the result stream is released and every owner unwinds before `Rf_error`; no exception
  crosses `.Call`; no R API is called from native code that owns resources. The source is read with the existing verifier
  discipline (header and every record verified before use, 64 MiB bounds, checked 64-bit arithmetic); property buffers are
  walked with explicit bounds checks; the temporary is opened with `O_NOFOLLOW`.
* The writer re-validates every source record with the graph reader's own geometry rules and fails (no output) if the
  source no longer matches.

## 6. Observed performance (indicative)

Observed once on a Linux x86-64 machine with 4 cores; not guarantees. Workload: Angular Choice with `syntax` normalisation on a jittered
segment lattice (7 mixed-width attributes including strings and nullable integers). The measurement scripts were development-only and
are not retained. "Writer" is the time inside the format writer (re-read of the source, encoding, disk write); peak RSS is above the
graph's resident size.

* **FlatGeobuf (native writer):** 1,000,000 features: PST calculation 3.1–3.3 s, calculation plus write 3.8–4.8 s, writer alone
  1.0–1.6 s, peak above the graph 172–206 MiB, output 177 MiB. 5,000,000 features: writer alone 6.3–6.6 s, peak above the graph
  858 MiB (PST's own arrays dominate), output 884 MiB. The conventional baseline (`sf::st_read`, attach columns, `sf::st_write`,
  unindexed) took 16.8–17.6 s and 1184 MiB at 1M (no PST in the process), so the native writer is roughly 11–17x faster for the
  writer-only time; the figures measure different things and are indicative only.
* **GeoParquet at 1,000,000 rows (zstd):** whole table (`read_table`, add columns, `write_parquet`) 0.53–0.72 s, 309–325 MiB, Arrow pool
  147 MiB; per-row-group streaming 1.23–1.63 s, 354–374 MiB, pool 136 MiB. At this size streaming is about 2x *slower* and uses no less
  memory. At 5,000,000 rows the whole table path peaked at 936–943 MiB (pool 652 MiB) against 659–671 MiB (pool 231 MiB) for streaming:
  streaming's Arrow footprint grows more slowly with size. **Streaming was chosen for its smaller Arrow memory footprint at scale, not
  because it is the fastest option at 1M.**
* **Codec:** a single 1M profile had the streamed `WriteTable` calls take 1.46 s (zstd), 0.78 s (snappy), 0.81 s (lz4) and 0.55 s
  (uncompressed) for 66.4/74.3/74.2/90.8 MiB files; a repeated comparison was inconclusive. Spatial output therefore uses **zstd**, as
  `output_file` does (smaller files, no unproven speed claim); `.pst_spatial_parquet_codec` is the single switch.

## 7. Tests

`tests/testthat/test-spatial-output.R` (all platforms; the `ulimit -f` full-disk tests are POSIX-only and in the Windows skip inventory): provenance and serialisation; argument
positions, mutual exclusion and ineligible modes; every eligible analysis × both formats × unindexed and Hilbert-indexed
FlatGeobuf (verified permuted on disk) × segment and axial graphs, each compared with the in-memory result, with an
independent graph built from the geometry matrix in physical order, with byte-identical source WKB read by GDAL/arrow, and
with unchanged source attributes (identifiers that do not match positions, NA, non-ASCII text, duplicate/reversed/zero-length
segments); CRS/header/`geo` preservation; replacement, repeated analyses and rejected names; GeoParquet row-group layout,
types and a batch size that does not divide the row groups; native NaN/±Inf/-0/INT32 bounds and nulls through the synthetic
native producer; no-clobber/overwrite/invalid destinations; source = destination (path, symlink, hard link); source drift,
corruption and truncation; stream faults, an interrupt and a real full disk (`RLIMIT_FSIZE`); graph reuse and balanced native
owners.

## 8. Deferred / out of scope

Cross-format output; reprojection or CRS inference; an indexed FlatGeobuf (or Hilbert-sorted twin); preserving source Parquet
page-level properties; group-level results projected onto segments; a content hash or
coordinate checksum of the source; writing back to the source; GeoPackage/Shapefile output.

## 9. Platforms

Developed and tested on Linux x86-64 (R 4.3.3, GDAL 3.8.4, R `arrow` 25.0.0) and passed the complete local validation on **macOS Apple
Silicon** (R 4.6.1). Windows: the publication and identity layer is implemented (`src/pst-fs-core.h`, see
[result files](result-files.md) §5 item 6) and the spatial-output tests are enabled on Windows, but **the implementation has not been
validated on a Windows machine**; the procedure is `tools/validation/windows/README.md`. Only the two `ulimit -f` tests are skipped
on Windows (no per-process file-size limit there). On Debian-style Linux toolchains the strict gate meets an installed-size NOTE
caused by the platform's debug-info flags ([build and platforms](../build-and-platforms.md)).
