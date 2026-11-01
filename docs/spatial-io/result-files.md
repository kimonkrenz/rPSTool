# Result files — direct Parquet persistence

`output_file` persists analysis results directly from native buffers to a Parquet file through the Arrow C stream, without building an
R data frame. It is implemented for `angular_integration()`, `angular_choice()` (§1–§10), the axial analyses without validity masks (§11),
`network_betweenness()` and `segment_group_integration()` with Arrow validity masks (§13) and `segment_grouping()` (§13.6).
`network_integration(junctions = TRUE)` is not offered (§14). Spatial GeoParquet/FlatGeobuf output is described in
[spatial output](spatial-output.md); the current status matrix for all analyses is in [spatial I/O](README.md). This document records
what the code does, how it is tested and what was measured. Nothing here changes a PST algorithm, a numerical result, the default return
value of any function, or any existing input route.

## 1. Public API

```r
angular_integration(graph, steps = NULL, radius = NULL, weigh_by_length = FALSE, normalization = "turner",
                        angle_threshold = 0, angle_precision = 1, weight_outputs = FALSE,
                        output_file = NULL, overwrite = FALSE)
angular_choice(graph, radius = analysis_radius(), weigh_by_length = FALSE, normalization = "none",
                   angle_threshold = 0, angle_precision = 1, output_file = NULL, overwrite = FALSE)
```

`output_file` and `overwrite` are **appended**; every earlier formal keeps its position and meaning.

* `output_file = NULL` (default): unchanged. The same code path produces the same data frame as before
  (the pre-existing 82,401-expectation angular regression suite passes unchanged).
* `output_file = "<path>"`: the analysis runs **once**; its result is written to one Parquet file (zstd) and an
  **invisible** `pst_result_file` descriptor is returned: `path` (absolute), `rows`, `columns` (in file order) and
  `format` (`"parquet"`). No R result vectors or data frames are built.
* `overwrite = FALSE` (default) refuses to replace anything that exists at `output_file`; `TRUE` replaces by a single rename (the old file is untouched if anything fails; see §5 item 6 for the Windows differences).
* The optional package `arrow (>= 25.0.0)` is required **only** when `output_file` is used (it stays in `Suggests`).

## 2. File contents

Exactly the columns, order and rows of the in-memory data frame for the same call (including the conditional
`total_weight`/`total_depth_weight` of Angular Integration and `total_depth_weight`/`normalized` of Angular Choice).

| Column | Parquet type | Source |
| --- | --- | --- |
| `segment_id` | int32 | one-based position in native graph order (generated per batch; no external IDs) |
| float results | **float32** | PST's native `float`, stored unchanged; reading into R widens exactly to the doubles the data frame holds |
| `node_count` | int32 | PST's native `unsigned int`; validated `<= INT32_MAX` (also bounded by the segment count, itself `<= INT_MAX`) — never reinterpreted |

All fields of these two families (and of the axial families, §11) are non-nullable; they have no missing-value policy and
none is introduced. Nullable columns exist only in the masked families (§13). Native Inf
(and NaN, `-0` and any other float bit pattern) are stored bit for bit. Metadata (Arrow schema key/value → Parquet
key/value): `rpst:schema`, `rpst:version`, `rpst:pst_version`, `rpst:pst_commit`, `rpst:function` (the public function name, for example `angular_choice`), `rpst:parameters`
(compact JSON of the resolved radius and every analysis argument), `rpst:graph_type`, `rpst:graph_rows`,
`rpst:crs_wkt`, `rpst:id_base` (`1`), `rpst:order` (native graph order), `rpst:float_columns`. The graph size comes from
the native graph, never from editable R metadata.

## 3. Data flow and the single finishing implementation

```
R: validate output_file/overwrite, arrow capability check          (nothing computed or created yet)
native: stream args validated (R errors only, no C++ owner yet)
native: angular_*_compute()  → PST call + native normalisation + count validation      ← the SAME function
        in-memory route: widen into the pre-allocated R vectors (unchanged)             as the file route
        file route:      move the finished arrays into a ResultTable (shared_ptr), export Arrow C stream
native: C++ owners unwind, THEN Rf_error if anything failed
R: temp file → import_from_c → read_table → write_parquet(zstd) → publish → descriptor
```

`angular_integration_compute()` and `angular_choice_compute()` (`src/pst-graph.cpp`) are the previous in-line bodies
extracted without change of order or content (PST call, the exported normalisers, the existing count check); the
in-memory wrappers call them, so no normalisation or numerical code exists twice. Column *names* are derived by two
tiny R helpers (`.pst_angular_integration_names`, `.pst_angular_choice_names`) that the tests compare with the
in-memory data frame for every parameter combination.

## 4. Native ownership and Arrow release invariants (`src/pst-result-stream.{h,cpp}`)

* A `ResultTable` owns the complete finished arrays (`std::vector<float>` / `<unsigned int>`) and the metadata. It
  is held by `std::shared_ptr`; the **stream**, every **batch array** and every **child array** each hold a
  reference. The buffers therefore stay valid until the last Arrow consumer has released its object, in any order.
* Batches are zero-copy slices (`buffers[1]` points into the owned array at the batch offset); only the id column is
  generated per batch (4 B/row, bounded by the batch size). Default batch = 1,048,576 rows = the Parquet row group.
* Release callbacks only drop references and free memory; they never call the R API, are safe to run on any
  thread, and are idempotent (`release == NULL` afterwards). A parent releases only the children a consumer has not
  moved away; a moved child owns its own reference and may outlive its parent and the stream.
* `get_next` after the end returns an empty (released) array repeatedly. Errors set `get_last_error`; allocation
  failures are caught and returned as `ENOMEM`; no exception crosses the C interface.
* An export that fails (validation, allocation) leaves the target stream untouched; a failed or partial analysis
  never publishes a stream. The only R-side owner is the existing `rPST::ArrowArrayStream/v1` external pointer
  (`rpst_arrow_stream_new`), whose finaliser releases a still-live stream once.

**Arrow R entry points (evidence).** The route needs `arrow::RecordBatchReader$import_from_c(stream)`. In arrow
25.0.0 it exists (a function of one argument), but **it is not documented** (no Rd topic mentions it; arrow's NEWS
describes the C interface methods as exposed "to facilitate their use in other packages"). GeoParquet input depends on the
equally undocumented `export_to_c`. rPSTool therefore checks `is.function(RecordBatchReader$import_from_c)` at run time
and fails with a clear error before anything is computed; only 25.0.0 was tested. `arrow::write_dataset(<reader>)` is
**not** used: it needs `dplyr`. The documented `write_parquet(<Table>, compression = "zstd", chunk_size)` is used,
with `codec_is_available("zstd")` checked first.

## 5. File publication contract (`src/pst-output-file.cpp`, `R/result-file.R`)

1. The destination is validated (single non-empty string, existing directory, not a directory, not existing unless
   `overwrite`); the arrow capability is checked; the **analysis then runs**; only after it succeeds is anything
   created on disk.
2. A uniquely named hidden temporary (`.rpst-<random>.partial`) is created **exclusively** (`open(O_CREAT|O_EXCL)`,
   mode `0666 & ~umask`; never reuses a file or follows a symlink) in the destination directory, so it is on the same
   filesystem.
3. The Parquet writer is closed (by `write_parquet`) before publication; the row count and a non-empty size are
   verified; a short or failed write raises an error and the temporary is removed (`on.exit`, also on interrupt).
4. Publication: `overwrite = FALSE` → `link(2)` temporary→target, then `unlink` of the temporary. The kernel
   **atomically refuses if the target exists** (also if another process created it after validation), so such a
   file is never replaced. A filesystem without hard links gives an explicit error; there is no racy
   check-then-rename fallback. `overwrite = TRUE` → `rename(2)`: atomic replacement on one filesystem (POSIX; the Windows visibility semantics are not claimed, §5 item 6); observers see
   the old or the new complete file; if it fails the old destination is untouched. A symlink destination is replaced
   by a regular file (the link itself, not its target).
5. Not guaranteed: **crash durability** (no `fsync` is issued; after power loss the file may be absent or empty);
   concurrent writers to one path (with `overwrite = TRUE` the last rename wins); cleanup after `SIGKILL` (a hidden
   `.rpst-*.partial` can remain). Interrupts during the native analysis are deferred as before (PST cannot be
   interrupted); the R-level write is interruptible and cleans up.
6. **Windows** uses the same protocol through the Win32 API (`src/pst-fs-core.h`; the platform layer has no R dependency and is
   exercised on its own by `tools/validation/windows/fs-harness.cpp`):

   | Step | POSIX | Windows |
   | --- | --- | --- |
   | exclusive temporary file | `open(O_CREAT\|O_EXCL)` | `CreateFileW(CREATE_NEW, FILE_FLAG_OPEN_REPARSE_POINT)`; a (dangling) symbolic link counts as existing and is never followed |
   | no-clobber publication | `link(2)` then `unlink(2)` | `MoveFileExW` **without** `MOVEFILE_REPLACE_EXISTING`: one operation that fails with `ERROR_ALREADY_EXISTS` when the destination exists; same volume only (no `MOVEFILE_COPY_ALLOWED`), so it is a rename, never a copy; needs no hard-link support |
   | replacement | `rename(2)` | `MoveFileExW` with `MOVEFILE_REPLACE_EXISTING`: one rename call; if it fails the old destination is untouched. A symbolic-link destination is replaced, not followed |
   | open for the FlatGeobuf writer | `open(O_NOFOLLOW)` | `CreateFileW(OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT)`, then refused if the handle is a reparse point or directory |
   | paths | native bytes | UTF-8 from R, converted to UTF-16; `/` becomes `\`; long absolute paths get the `\\?\` prefix |
   | file identity | `st_dev`, `st_ino` (decimal strings) | volume serial number and file ID from `GetFileInformationByHandleEx(FileIdInfo)` (hexadecimal strings; 64-bit volume and 128-bit file ID), falling back to `GetFileInformationByHandle` |

   Differences from POSIX, stated plainly: (a) the Win32 documentation promises that `MoveFileExW` replaces the destination, not
   that observers never see an intermediate state; the single-rename behaviour on NTFS is an implementation property that the recorded Windows test runs
   (see the [release checklist](../release-checklist.md)) do not establish separately. (b) A replacement fails (old file intact) while another process holds the destination
   open without `FILE_SHARE_DELETE`, where POSIX would succeed; the R error says the file is in use or access is denied.
   Transient sharing violations (virus scanners, indexers) are retried for up to half a second; a persistent one is an error.
   (c) Neither platform offers crash durability or protects against `SIGKILL`/process termination leaving a hidden
   `.rpst-*.partial` file. (d) File identity is a check at one moment, not a lock: a race between the check and the publication
   is not excluded on either platform.
   `ReplaceFileW` was rejected: on some failures it leaves the destination missing or renamed, which breaks "the old file survives".
   Open handles on Windows: Apache Arrow opens every local file it reads, maps or writes with `FILE_SHARE_READ | FILE_SHARE_WRITE`
   and never `FILE_SHARE_DELETE` (`arrow/util/io_util.cc`), and `ParquetFileReader$create(<path>)` memory-maps the file and keeps
   it open until the reader is garbage collected. Any such live reader therefore blocks replacing or deleting that file (and R's
   `Sys.setFileTime()`, which asks for exclusive access, fails silently). rPSTool opens the Parquet sources it reads (graph
   construction, spatial-output preflight and writer) through an explicit `ReadableFile` without memory mapping and closes it as
   soon as it is done, before anything is published; it never holds the destination open. Code that inspects a result file with
   Arrow should do the same (the tests use `rs_pq()` / `rs_read_parquet()`).
   The Windows implementation passed the development test suite on Windows; validation of the final release candidate on Windows is
   still outstanding; see the [release checklist](../release-checklist.md).

## 6. Tests

* `test-result-stream.R` (Stage A; synthetic producer + scripted consumer, independent of PST): zero-copy export and
  bit-exact read-back through arrow (including `±0`, ±Inf, NaN payloads, subnormals, `INT32_MAX`); batches outliving
  the stream, any release order, moved child arrays, repeated and premature release, schemas independent of the
  stream, repeatable end-of-stream, empty results; injected schema/batch/allocation failures; arrow-side failed
  imports and read errors; partial consumption and abandoned readers; garbage collection at every ownership
  transition; malformed specifications; object counters balanced after every scenario.
* `test-result-file.R` (Stages B–C): every one of the 1,344 direct-PST angular control cases (all graphs, radii,
  length weighting, thresholds, precisions and normalisations of the pinned reference) is persisted and compared
  with the in-memory data frame (names, order, rows, types, and the 8 bytes of every double) **and** with the
  pinned reference values; a 320-run sweep (160 per worker setting) of weights/normalisation/radius/threshold/precision for both
  functions at 1 and 3 workers; schema types; descriptor and visibility; argument positions; metadata (with forged
  `n_segments`); multi-batch/row-group layouts; native argument validation; graph reuse, release, serialisation.
* `test-result-publication.R` (Stage D): no-clobber for files, symlinks and dangling symlinks; replacement and
  symlink replacement; invalid and inaccessible destinations; disk-full and interrupt simulation at the writer;
  wrong row count; producer faults mid-stream; a file created by another process during the write; the publication
  primitives; the strict capability check; temporaries always removed; native result counters balanced.
* Valgrind (success and failure paths of both functions, the synthetic harness, scripted consumer, abandoned
  readers): 0 bytes definitely lost, no invalid access and no `rPSTool.so` frame; the single uninitialised-value report
  and the "possibly lost" blocks are libarrow's start-up (mimalloc/protobuf), as for the GeoParquet input.

## 7. Measurements (observed, Linux x86-64, 4 cores; single-machine, not a guarantee)

Workload: Angular Choice, length-weighted, syntax normalisation, `steps = 3`; segment lattices (`jitter` = random
node displacement ±3 so that angles and values are irregular). "peak" = process peak RSS above the graph's
resident size (measured after `clear_refs`); 3 repetitions per cell (ranges shown); every persisted result was read
back and compared with the in-memory data frame (`same = TRUE` in all runs). A = existing analysis, then
`arrow::write_parquet(df, zstd)` (float64 columns); B = `output_file`; C = analysis only.

| Workload | C (no persistence) | A (data frame, then arrow) | B (new direct path) |
| --- | --- | --- | --- |
| 0.98 M segments, regular: time | 1.55–1.81 s | 1.88–2.13 s (write 0.36–0.41) | 1.88–2.15 s |
| … peak above graph | 193 MiB | 239 MiB | 204 MiB |
| 0.98 M segments, irregular: time | 2.38–2.53 s | 3.11–3.19 s (write 0.75–0.82) | 2.86–3.29 s |
| … peak / file / read-back | 193 MiB / – / – | 263 MiB / 17.5 MiB / 0.09–0.15 s | 218 MiB / 17.2 MiB / 0.04–0.06 s |
| 0.98 M segments, irregular, Angular Integration: peak | 163 MiB | 237 MiB | 188 MiB |
| 3.9 M segments, irregular: time | 10.5–11.0 s | 12.2–12.7 s (write 1.4–1.5) | 11.8–12.3 s |
| … peak above graph | 673 MiB | 673 MiB | 658 MiB |
| … RSS retained after the call | 255 MiB | 335–337 MiB | 229–242 MiB |
| … file size / read-back | – | 70.0 MiB / 0.40–0.43 s | 68.7 MiB / 0.12–0.30 s |
| 5 M segments from a FlatGeobuf file (1 run): time | 10.0 s | 10.6 s | 11.0 s |
| … peak above graph | 859 MiB | 859 MiB | 859 MiB |
| … RSS retained after the call | 174 MiB | 252 MiB | 46 MiB |

What this does and does not show:

* **The projected ~15 % peak-memory reduction is not demonstrated at scale.** B lowers the peak against A by
  12–17 % at ~1 M segments (the data frame and the writer's input copy are avoided), but only by 0–2 % at 3.9 M and
  not at all at 5 M. There the peak occurs **inside PST's analysis** (native working memory plus the native result
  arrays); a separate run that only exports the native result to an unconsumed stream shows the same 658 MiB peak at
  3.9 M. R vectors allocated before the PST call are not resident until the widening copy, so they never add to that peak.
* B is **not faster**: total time is within noise of A (the file is written by the same arrow writer), and slightly
  above C by the Parquet encoding time. Float32 storage does not shrink files noticeably after zstd (17.2 vs 17.5 MiB).
* What B reliably removes is the **retained R result**: memory after the call is 46 MiB (5 M segments) against
  174 MiB (C) and 252 MiB (A), and read-back is faster.
* Not measured: repetitions at 5 M, sparse versus dense crossing structures (segment graphs have none), macOS,
  Windows, real-world networks, nanoparquet or other writers.

## 8. Dependencies and compatibility

No new mandatory dependency, no vendored file, no build-copy or warning-policy change. `arrow` stays in `Suggests`
(only 25.0.0 tested). New translation units `pst-result-stream.cpp` and `pst-output-file.cpp` use the established
compile rules (`-ffp-contract=off`) and are registered in `Makevars`, `Makevars.win`, `tools/fp-policy.R` and
`tools/verify-vendor.R`. The vendored Arrow C ABI declarations (`src/arrow-c-abi`) are reused.

## 9. Platform status and limitations

* The machinery passed the complete local validation on Linux x86-64 and macOS Apple Silicon. The Windows implementation (§5 item 6)
  is complete. Before the Windows runs it was exercised on the Win32 API only under Wine (`tools/validation/windows/`), which does not
  reproduce NTFS or symbolic-link semantics. The development test suite has since passed on Windows (see the
  [release checklist](../release-checklist.md) item 10); validation of the final release candidate on Windows is still outstanding,
  and the procedure in `tools/validation/windows/README.md` has not been repeated on it.
* Result persistence needs the optional `arrow`; the undocumented `import_from_c` is a version-sensitive dependency.
* The native result arrays must be fully resident until the write finishes: this is **not** a streaming or
  bounded-memory computation (PST fills complete caller-supplied arrays).
* Row identity is positional only; external feature IDs are not retained (deferred).

## 10. Not implemented (deferred)

Network Integration with `junctions = TRUE` (two tables; §14), graph inspection outputs; Arrow IPC/Feather; compression choice; external IDs; Final release-candidate validation on Windows (the Windows implementation is complete; see §5 item 6). Spatial GeoParquet/FlatGeobuf output is implemented, see [spatial output](spatial-output.md).

## 11. Mask-free axial-graph analyses

`output_file = NULL, overwrite = FALSE` are appended (after every earlier formal) to:

| Function | File route | Columns (after the int32 positional id, in data-frame order) |
| --- | --- | --- |
| `network_integration()` | `junctions = FALSE` only (`junctions = TRUE` is rejected before anything runs: it has a second table) | `line_id`, `integration` f32, `node_count` i32, `total_depth` f32 |
| `network_reach()` | lines and supplied origins | `line_id` or `origin_id`, `reached_count` i32, `reached_length` f32, `reached_area` f32 |
| `od_betweenness()` | all | `line_id`, `od_betweenness` f32 |
| `attraction_reach()` | every origin kind and mode | `origin_id`, `attraction_reach` f32 |
| `attraction_distance()` | every origin kind and mode, with or without `destination_indices` | `origin_id`, `attraction_distance` f32, optional `destination_index` **signed** i32 |

**Classification (verified against the exact implementation and the compatibility records).** None of these has a
missing-output policy: PST writes every output element (Reach/Integration/OD: all `n` outputs; Attraction Reach/Distance:
every supported mode writes its final native outputs, the one unwritten combination being rejected before the call —
`docs/21`). Native `-1` (unreachable distance, fewer than two lines reached), `NaN` and `Inf` are ordinary values and are
stored as such; no validity mask is needed and none is created.

**Shared infrastructure, minimal changes.**

* One column kind was added to the shared `ResultTable`: `SignedInt32` (PST's native `int`, exported unchanged as Arrow
  int32). It is required because Attraction Distance's destination index is a signed `int` whose `-1` means "none";
  the existing `Int32` kind (native `unsigned int`, validated `<= INT32_MAX`) must never reinterpret a negative. No
  Float64 column was needed: every output is a native `float` or integer, widened only when read into R.
* Each analysis keeps **one** native implementation. Its argument validation, PST call and any native
  post-processing run once; only the destination of the finished arrays differs. The previous `.Call` entry points
  delegate to the same function with no stream request (the file route allocates no R result vectors), and a second,
  thin `.Call` entry point (`rpst_<analysis>_stream`) supplies the stream arguments. The finished `std::vector`s are
  **moved** into the `ResultTable`: no extra native copy. The stream/ownership/publication code is unchanged;
  `result_stream_args`, `result_add_*` and `result_finish_and_export` (moved earlier in `src/pst-graph.cpp`) are used by
  all seven file-capable analyses.
* On the R side every wrapper builds only its column names, its parameter list and its native call and hands them to
  one helper, `.pst_axial_result_file()`, which builds the metadata and calls the single `.pst_write_result_file()`. The
  native call returns the row count (a native property for origin-dependent analyses); the writer verifies the Parquet
  table against it.

**Metadata** (additions to §2): `rpst:graph_type = axial`; `rpst:graph_rows` is the native **line** count; `rpst:order`
now states the row convention (native line order; supplied origin row order for `network_reach(origins=)`; native
point/junction/line/point-group order for the attraction origin kinds); `rpst:parameters` holds every analysis
argument, with large inputs (attraction points, weights, origin rows) recorded **by size only**, never copied into the
file.

**Tests** (`test-result-axial.R`, plus a synthetic signed-column test in `test-result-stream.R`): every pinned
attraction case (reach and distance, with and without indices; NaN/Inf included), every pinned OD case, the pinned
upstream Network Integration oracle with every step limit, every radius combination of the integration/reach
official-wrapper oracle, Reach from supplied origins against the pinned optional-mode oracle — each persisted file compared
with the in-memory data frame (names, order, rows, types, 8 bytes of every double) **and** with the pinned reference;
unreachable `-1` values; zero-row results; signatures; rejection of bad arguments, wrong graph family, released and
deserialised graphs before any file exists; an existing file is never replaced; PST-side failures; metadata incl. forged
R-side counts; graph reuse (no graph created or freed) and balanced native result counters; multi-batch files from the
new entry points; native stream-argument validation per entry point.

**Memory.** Same as §7: the saving is the R-side result (data frame and writer input copy), not PST's working memory.
Observations are in §12.

## 12. Observations for the axial analyses (single machine; not a guarantee)

Linux x86-64, conda-forge R with arrow 25.0.0, 4 cores; a 2,000,000-line irregular axial lattice (jittered
endpoint-connected edges; `x` was released before the measurement). "peak" = process peak RSS above the graph's resident size
(`VmHWM` after `clear_refs`); two runs per cell (identical to the rounding shown unless a range is given). A = existing
analysis, then `arrow::write_parquet(<data frame>, "zstd")`; B = `output_file`; C = analysis only.

| Analysis (2 M lines) | C: time / peak | A: time / peak | B: time / peak | file |
| --- | --- | --- | --- | --- |
| `network_integration(steps = 3)` | 18.0–18.1 s / 62 MiB | 19.0–19.4 s / 158 MiB | 18.5–18.8 s / 127–128 MiB | 8.5 MiB |
| `network_reach(walking = 200)` | 17.4–17.7 s / 62 MiB | 19.9 s / 168 MiB | 19.3–19.4 s / 127 MiB | 19.3–19.6 MiB |

Reading: B lowers the extra peak against A by about 20–25 % here because the R data frame (plus the writer's input
copy) is not built; it is **not faster** than C or A beyond the Parquet encoding time, and the 127 MiB above C's 62 MiB is
Arrow's own table/writer memory. Memory retained by the process after the call was not lower for B in this measurement
(Arrow's allocator keeps its pages; the §7 measurement at larger scale showed lower retention after the call). PST's own working memory is the
C column and is unchanged. The OD and Attraction analyses were validated for equivalence, not benchmarked: their cost is
dominated by PST. Not measured: macOS, Windows, other graph shapes, repeated large runs.

Memory-safety evidence: valgrind (`R -d valgrind`, success and failure paths of all five file routes incl. a zero-row
result, native validation errors, a dead graph and an existing target; the graph then collected) reports 0 bytes
definitely and 0 indirectly lost, no invalid access and no `rPSTool.so` frame; the only reports are libarrow start-up
code (mimalloc/abseil/protobuf), as for the angular routes.

## 13. Arrow validity masks: Segment Betweenness and Segment Group Integration

`output_file = NULL, overwrite = FALSE` are appended to `network_betweenness()` and `segment_group_integration()`. Both reuse
the existing writer, ownership model, publication protocol and metadata helper; only the Arrow producer gained nullable
columns. The in-memory results are unchanged, and each analysis still has **one** native compute path (one PST call and one
set of normaliser calls) feeding either the R vectors or the table.

### 13.1 Missing-value contract (the adopted typed-NA policies, now expressed as Arrow nulls)

Nullability is declared by the function and its parameters, never by whether a given run happens to contain a null, so the
files of one analysis share one schema (and the Parquet writer, which rejects nulls in a non-nullable field, cannot fail
on a data-dependent null). A null means exactly "PST wrote no value for this slot"; a written `NaN`, `Inf`, `-Inf`, `-1`
or `0` is an ordinary valid value, and no numeric sentinel is substituted for a null.

| Function / column | Native → Parquet | Nullable | A row is null exactly when | Relationship to the in-memory result |
| --- | --- | --- | --- | --- |
| `network_betweenness` `line_id` | positional → int32 | no | never | `seq_along` |
| `betweenness` | float → float32 | **no** | never: PST writes the raw score of every line, including the lines of skipped origins | identical doubles |
| `node_count` | unsigned → int32 | **yes** (every call) | PST skipped the origin (weighted/attraction modes only): native count left at `UINT_MAX` | `NA_integer_` ↔ null |
| `total_depth` | float → float32 | **yes** (every call) | same mask as `node_count` (the two native masks must agree, else the call fails) | `NA_real_` ↔ null |
| `normalized`, `"standard"` | float → float32 | no | never: PST's standard normaliser runs over all raw scores | identical doubles |
| `normalized`, `"freeman"`/`"syntax"` | float → float32 | **yes** | the diagnostics of that row are unwritten (the exported normalisers only see written rows) | `NA_real_` ↔ null; a written normaliser `NaN` stays a valid `NaN` |
| `normalized`, `"none"` | – | column absent | – | – |
| `segment_group_integration` `group_id` | positional → int32 | no | never | `seq_along` (gaps are empty groups: real rows) |
| `integration` | float → float32 | **yes** | PST wrote neither count nor depth (the score is never consulted) | `NA_real_` ↔ null |
| `node_count` | unsigned → int32 | **yes** | same single mask | `NA_integer_` ↔ null |
| `total_depth` | float → float32 | **yes** | same single mask | `NA_real_` ↔ null |

Group integration: PST writes all three outputs for every group or none (a graph without native nodes), so real files are
all-null or all-valid per column; an isolated group in a graph with nodes holds a written `-1, 0, 0`, which is valid. A mixed
mask is only reachable through the synthetic test hook. Under a null the data buffer keeps the native sentinel (`UINT_MAX`,
`-Inf`) that no consumer reads; it is not contractual and was deliberately not rewritten, to avoid a pass and a copy.

### 13.2 Arrow mechanics (`src/pst-result-stream.{h,cpp}`)

* `ResultColumn` gained `nullable` and `validity`, the **full-column**, bit-packed (`(rows+7)/8` bytes: one eighth of a
  byte per row) Arrow validity bitmap: bit `i` set = row `i` valid, least-significant bit first (Arrow's convention, also
  verified against the Arrow C++ importer and Parquet writer). The value arrays and their ownership are untouched.
* Each batch child gets its **own** bitmap, rebuilt from the full-column bits with `array.offset` kept at 0 and the value
  pointer advanced as before. Every batch start (byte-aligned or not) is therefore handled by one code path, and the
  `null_count` of each batch is exact (Arrow trusts it). When a batch has no null, `buffers[0]` is `NULL` and `null_count`
  is 0. The bitmap is owned by the child (`ChildPriv`), so it follows the same shared ownership and any release order as the
  value arrays; release callbacks still never touch R.
* The schema sets `ARROW_FLAG_NULLABLE` per column (the id column and all angular and axial columns remain non-nullable; the vendored
  Arrow header deliberately omits the flag constants, so a local constant is used).
* `export_result_stream` additionally requires `validity.size() == (rows+7)/8` for nullable columns and an empty mask for the
  others, and its int32 range check ignores rows marked null (the `UINT_MAX` sentinel) while still rejecting a valid
  out-of-range value. Failure atomicity is unchanged. Child allocation is now exception safe (a `unique_ptr` until the
  child owns it), which also closes a latent leak window.
* Test-only: the synthetic producer accepts `attr(column, "valid")`, a fifth fault (`oom_validity_at_batch`) and scripted
  ops 12–15 (null count/bitmap presence and validity checksum of a batch child or a moved child).

### 13.3 Metadata

As §2, with `rpst:graph_type` `axial` (betweenness: `rpst:graph_rows` = native line count, order = native line order) or
`segment_group` (group integration: `rpst:graph_rows` = native group count, `rpst:order` = group id order; no source CRS is
retained by a group graph). `rpst:parameters` records the radius, distance, normalization and the *sizes* of weights and
attraction points, never their values.

### 13.4 Tests

`test-result-masked-stream.R` (synthetic producer, no PST analysis): LSB-first bit order and exact per-batch null counts
for batch sizes 1, 3, 7, 8, 9, 13, 29, 64 over four null patterns, bitmap presence and checksum through the scripted
consumer, valid-vs-null for NaN/Inf/-0 bit patterns in both directions, the int32 range rule for masked and valid slots, all-null/all-valid/zero-row columns and the
Parquet round trip, malformed masks, release in every order after the batch and stream are gone, validity-buffer allocation
failure with balanced counters. `test-result-masked-analyses.R`: every betweenness fixture case of the pinned reach/betweenness reference
× {none, standard, freeman, syntax} (> 500 files) and all 280 pinned group-integration cases, each compared with the
in-memory result (names, types, 8 bytes of every double) **and** with the pinned reference, with the null pattern derived from
the fixture's own NA positions; named discriminators (written NaN, skipped-origin raw score, standard normalisation, the
`-1` sentinel trap, empty groups, isolated groups, no-node graphs); weighted/thread/batch-layout sweeps; sf attraction
points; schema determinism; early rejection, protection of an existing file, dead pointers and wrong graph families;
metadata with forged R-side counts; the synthetic mask-disagreement hook through the production file conversion.

The analysis tests run on every platform; only the file-size-limit (`ulimit -f`) tests need POSIX and are in the strict
Windows skip inventory (`tools/ci/windows-test-skips.tsv`). Symbolic-link assertions run where the account can create links.

Mutation controls applied locally (each made the named tests fail, then was reverted): nulling every `NaN` in `normalized`
(6 failures), making the raw score nullable (42), treating `-1` as missing in group integration (35), MSB-first bit order
(51), a constant per-batch null count (132), omitting the nullable flag (36 failures/errors in the stream tests, 12 in the
analysis tests) and not skipping masked rows in the int32 range check (12 errors/failures across both files).

### 13.5 Observations (single machine; not a guarantee)

Linux x86-64, conda R 4.5.3 / arrow 25.0.0, a 320,000-line lattice (betweenness: jittered axial lattice, `steps = 2`,
Freeman, 40 % zero weights; group integration: exact segment lattice, one group per segment, `steps = 2`); peak RSS above
the graph, two runs each. A = analysis, then `arrow::write_parquet(<data frame>, "zstd")`; B = `output_file`; C = analysis only.

| Analysis | C | A | B |
| --- | --- | --- | --- |
| `network_betweenness` | 1.5–1.6 s / 37 MiB | 2.3 s / 138 MiB | 2.3 s / 129 MiB |
| `segment_group_integration` | 0.2 s / 1–2 MiB | 0.7 s / 88 MiB | 0.8–0.9 s / 81 MiB |

The saving of B over A is the R data frame (about 7–9 % of the peak here); the bulk of the 80–90 MiB above C is Arrow's own
library and writer, not rPSTool. The masks cost `rows/8` bytes per nullable column plus a short per-batch pass; the value
arrays are moved into the table and exported as slices, never copied per batch (by construction: the code moves the vectors
and only the id and bitmap buffers are generated per batch; not separately benchmarked against the unmasked routes). B is
not faster than A (the file is written by the same arrow writer, and rPSTool collects garbage after large results). This is not
bounded-memory computation.

### 13.6 Segment Grouping

`segment_grouping()` has **no** missing values (every segment gets an id and a colour), so it needs no validity mask. The
scalar attributes `n_groups`/`n_colors` cannot live in a data-only file, and the in-memory `group_id`/`color` are native + 1. The options
(a) keep the scalars out of the file, (b) repeat them as columns and (c) store them as file metadata were weighed, and (c) was chosen:

* `segment_grouping(graph, angle_threshold = 1, split_at_junctions = FALSE, output_file = NULL, overwrite = FALSE)` — the two
  new arguments are appended; with `output_file = NULL` the data frame, its columns, values, types and `n_groups`/`n_colors`
  attributes are unchanged.
* With `output_file` the grouping runs **once** (one `PSTASegmentGrouping` call; the in-memory and file routes share one native
  compute function with the same range validation), and the result is written to one Parquet file (zstd) with the columns
  `segment_id`, `group_id`, `color`, all **non-nullable int32**, in native segment order. `group_id` and `color` are **one-based**
  exactly as in the data frame (native + 1); `segment_id` is the usual implicit one-based positional id. Nothing is compacted,
  reordered or relabelled, and no NA/validity mask exists for this family.
* The two scalars, known only after PST has run, are appended natively as Parquet schema metadata **`rpst:n_groups`** and
  **`rpst:n_colors`** (decimal strings), before the usual `rpst:*` provenance keys (`rpst:function = segment_grouping`,
  `rpst:parameters` = `angle_threshold` and `split_at_junctions`, `rpst:graph_type = segment`, `rpst:graph_rows`,
  `rpst:id_base = 1`, `rpst:order` stating that all ids and colours are one-based, …). They equal `max(group_id)` and
  `max(color)` by PST's construction and are validated natively (`1 <= colours <= groups <= segments`).
* Memory: the native zero-based `unsigned int` vectors are moved into the Arrow-owned result table and shifted to one-based **in
  place** (no second buffer, no R vectors, no second PST call); the table is released by the existing shared-ownership
  protocol. Windows is handled as for every `output_file` (§5 item 6).
* `spatial_output_file` is **not** offered for this family: the spatial writers merge only the R-side provenance metadata, so
  the late native keys would be silently dropped. Per-segment grouping results could be written spatially later under an explicit
  decision.
* Tests (`tests/testthat/test-result-grouping.R`): file == in-memory == the pinned direct-PST fixture for every grouping case;
  metadata keys (once each, equal to the attributes and to `max(group_id)`/`max(color)`); a sweep of 5 networks × 7 thresholds × both
  split modes including one segment, disconnected and 20+ groups; small batch sizes that do not divide the result; early rejection
  of bad arguments, axial/dead/deserialised graphs and unusable destinations with no result table ever built; protection of an
  existing destination on a failed write; no-clobber/overwrite; stream-level validation; graph reuse and balanced native owners.

## 14. Network Integration with junctions — not offered

`network_integration(junctions = TRUE)` returns two related tables from **one** native call (`PSTANetworkIntegration`): the lines
(`line_id`, `integration`, `node_count`, `total_depth`, one row per line) and the junctions (`junction_id`, `x`, `y`, `integration`, one
row per crossing; with `junction_output = "sf"` the junctions become POINT features in the graph CRS). The file machinery here is
single-table and single-file: one `ResultTable` per stream, one temporary file, one `link(2)` / `rename(2)` publication. Persisting both
tables would need a new durable storage contract (two files, a dataset directory or a tagged long table), and that contract is not
approved. `junctions = TRUE` combined with `output_file` fails with an explicit message; the in-memory junction functionality is
unchanged.

The reason is that two sequential renames are **not** an atomic transaction: a crash or error between them can leave one new file and one
old or missing file (with `overwrite = TRUE`, new lines with old junctions). The alternatives examined were: a second, independently
published junction file via an appended argument (honest guarantee: each file complete or absent, the pair not atomic); a junction-only
file; two files from one stem (implicit naming, same non-atomicity); one long/tagged Parquet table (nullable union columns, overloaded id,
new schema version); a Parquet dataset directory published by directory `rename` (atomic only to an absent or empty destination); and
GeoParquet junction POINTs (the spatial writer is source-feature-keyed and not reusable). Future work must either solve pair consistency or
propose a narrower junction-only contract.
