# rPSTool build-input portability patches

The vendored PST v3.3.2 source is pristine. `FILES.md5` is the authoritative inventory; there are no digest overrides or exceptions. Patches apply only to generated build copies under `src/.rpst-build/`, produced by base-R transformers in `src/portability/`. Each transformer accepts only the pinned input checksum, requires exactly one occurrence of each original pattern, verifies that reversing the edits restores every original byte, checks the complete output checksum and publishes the copy only if all checks pass; output paths cannot target the vendor tree. `R CMD build` adds a final newline to C++ files under `src/`, so the exact original bytes of patched inputs are kept in `inst/upstream/build-inputs/` (byte-preserving Git attributes) and the transformers read those. Diagnostic `#line` directives keep the original vendor paths and line numbers in compiler messages.

Build-only compatibility declarations live in `src/rpst-compat.h` (force-included): missing standard declarations, `using std::isnan`, and an override of PST's struct-name macro to return `const char*`. They do not edit upstream source.

## 0001 — qualify the isovist result return type in a build copy only

- Original input: `src/vendor/pstalgo/src/analyses/CalculateIsovists.cpp`.
- Generated build input: `src/.rpst-build/analyses/CalculateIsovists.cpp`.
- Patch record: `patches/0001-qualify-isovist-result.patch`.
- Application: The return-type qualification is incorporated into `src/portability/harden-isovist.R`, invoked by `src/Makevars` and `src/Makevars.win` as part of the combined 0009 transformation.
- Reason: GCC 14 rejects `Result& Result()` because the method name changes the meaning of the unqualified nested type name (`-Wchanges-meaning`).
- Effects: no method names, ABI, storage, control flow or numerical expressions change.

## Windows aligned allocation adapter

`src/portability/windows-aligned-allocator.cpp` includes the pristine `SimpleAlignedAllocator.cpp` after loading its headers. For this translation unit alone it maps `posix_memalign` to an adapter using Rtools' `_aligned_malloc` and maps `free` to the matching `_aligned_free`. Upstream selects its Windows allocator using `_MSC_VER`, which Rtools does not define. The adapter validates POSIX alignment, leaves the output pointer untouched on failure and returns `EINVAL`/`ENOMEM` as appropriate. Only `Makevars.win` uses it. No upstream bytes, allocator class/block logic or numerical expressions change.

## 0002 — scoped ownership until axial/segment handle publication

- Pinned input: `src/vendor/pstalgo/src/analyses/CreateGraph.cpp`, PST v3.3.2 commit `63df80a2cf3dd289be95ea3d91667c3490719b75`; preserved input `inst/upstream/build-inputs/CreateGraph.cpp` (identical bytes, no final newline).
- Generated input: `src/.rpst-build/analyses/CreateGraph.cpp`, compiled on Unix and Windows instead of the vendored translation unit.
- Patch record: `patches/0002-graph-constructor-raii.patch`; script `src/portability/harden-graph-constructors.R`.
- Input MD5: `0aea4b5325e2d3177ae91d2008da4f55`.
- Output MD5 after 0002 alone: `86b06c75896c119f3f3dc99fc0a901f9` (the current output includes the 0004 edits).
- Reason: both constructors allocate a raw owning graph before operations that can throw. The axial constructor additionally returns `0` after allocation on polygon-generation failure. The wrapper cannot free unpublished handles.
- Edits (five patterns): add `<memory>`, replace the two raw owners with `std::unique_ptr`, remove the segment failure branch's manual delete, and return `graph.release()` at each successful publication. Both existing `return 0` paths remain unchanged. Exceptions propagate while scoped ownership destroys the temporary graph. All other functions, including published-handle free functions, remain byte-for-byte unchanged.
- Effects: no algorithms, graph topology, numerical expressions, public C API, graph layouts, normal return values or success-path semantics change.

## 0003 — central worker cap for the exposed asynchronous engines

`src/portability/limit-workers.R` generates build copies for the pinned `AngularChoiceAlgo.cpp`, `SegmentBetweenness.cpp`, `SegmentGroupIntegration.cpp`, `AttractionReach.cpp`, `AttractionDistance.cpp` and `ODBetweenness.cpp`. The changes to the first two sources are recorded in `patches/0003-central-worker-limit.patch`; the additional modifications are documented in sections 0004–0007. The preserved `inst/upstream/build-inputs/` copies match the vendor bytes exactly (`AngularChoiceAlgo.cpp` has no final newline). The current original/generated MD5 pairs for `AngularChoiceAlgo.cpp` and `SegmentBetweenness.cpp` are `f518e8c71d6c1607723564238692de62` / `ec0db906b35e28c7e6077df18255b685` and `287ec62e7e28f9955740e89545b11b13` / `b98f83d994cb1f07d0b49ed9b280e369`, respectively. These generated checksums include the subsequent 0007 and 0011 modifications and are verified by `src/portability/limit-workers.R`.

Each copy substitutes the single hardware concurrency call with the central `rpst_worker_count()` function.

Worker policy, implemented solely in rPSTool-owned `src/rpst-workers.cpp`:

- An explicit positive integer `RPST_NUM_THREADS` caps the count (at most `UINT_MAX`); otherwise hardware concurrency is used (minimum one).
- An active `_R_CHECK_LIMIT_CORES_` (non-empty, not `false`, case-insensitive) additionally limits the result to two.
- Caps cannot exceed hardware concurrency. Invalid explicit settings fail closed.
- No R API or callback participates in worker selection. The public caller waits until PST workers finish.
- Network Integration creates no workers. The other worker engines are covered by 0004 to 0010; unexposed experimental engines are unchanged.

This changes worker allocation/partitioning only. PST's algorithms, float calculations, sum accumulation loops and normalization routines remain unchanged.

## 0004 — extend existing build safety to segment groups

This extends 0002 and 0003 without touching vendor bytes or computations.

- `harden-graph-constructors.R` keeps input MD5 `0aea4b5325e2d3177ae91d2008da4f55` and adds exactly two patterns: `new CSegmentGroupGraph()` becomes a scoped `unique_ptr` and its successful publication uses `release()`. Seven edits in total produce the combined output MD5 `6ae192582ff4bafaf7f03a189c7c10f5`. No graph algorithms, layout, return values, successful geometry or free functions change.
- `limit-workers.R` adds `SegmentGroupIntegration.cpp` (original MD5 `b5b603d44a91fc8af3b769ca2e6361c6`, generated MD5 `bfa367c70db800c0586884a462e43276`). Its single unqualified `thread::hardware_concurrency()` call becomes `rpst_worker_count()`. Preserved input: `inst/upstream/build-inputs/SegmentGroupIntegration.cpp`.
- Patch record: `patches/0004-segment-groups-build-safety.patch`.
- The native bridge validates caps before calling PST on valid no-node graphs, which return before native worker creation. No worker invokes R.

Missing-output policy: paired count/depth write masks are implemented only in the rPSTool bridge. These build adaptations do not initialize PST outputs, alter step traversal, fix PST's isolated-group semantics or recompute scores. See `docs/compatibility/segment-groups.md`.

## 0005 — attraction worker caps, scratch safety and exception propagation

`limit-workers.R` includes `AttractionReach.cpp` and `AttractionDistance.cpp` (preserved build inputs match the vendor bytes). Original/generated MD5:

| Source | Original | Generated (including diagnostic prefix) |
| --- | --- | --- |
| AttractionReach | `d62cb47abf4284376936a032de4ee90b` | `0656b38e1ee2d3be74bf84aeb1acffc4` |
| AttractionDistance | `07a228e44f51d47c8f3980b1854bb0a0` | `58ee7467cb3ca8090b2d4e176ea6b271` |

- Each single hardware concurrency call becomes `rpst_worker_count()` (so Reach and Distance follow the worker policy above).
- Each ready-wait loop is followed by `task.get()`, propagating worker exceptions instead of returning partially computed output; other futures join before native owners unwind. Reach propagates to the bridge's catch/unwind/error boundary; Distance's exported try/catch returns failure.
- Reach's finite straight-line branch uses `CAxialGraph::getLinesFromPoint`, whose `m_tmpLineIdx` buffer is documented as not thread-safe. A scoped unique lock on the algorithm's existing mutex protects the query and consumption of that buffer. Point fetching releases the same mutex before this branch, so no nested acquisition occurs.
- Patch record: `patches/0005-attraction-worker-safety.patch`; the generator prefixes `#line 1` for original diagnostic paths. No score formula, traversal, polygon sample, collection or numerical output changes.
- The straight-only group Distance error belongs to the R/native bridge, not this transformation. See `docs/compatibility/attractions.md`.

## 0006 — OD Betweenness scratch safety and exception propagation

`limit-workers.R` adds `ODBetweenness.cpp` (preserved at `inst/upstream/build-inputs/ODBetweenness.cpp`). Original MD5 `cd14c1edb6b42f5b20ae5d48ce92959f`; generated MD5 including the `#line` prefix `e1abcacb8448be2aaa67b21120b4d846`. Patch record: `patches/0006-od-betweenness-safety.patch`, five edits (four items; the `SStep` item covers two declarations):

- Replace the active `workers.resize(1)` with `workers.resize(std::min(rpst_worker_count(), 1u))`; the upstream multi-core branch stays disabled and traversal is unchanged. OD Betweenness uses exactly one worker at caps 1, 2 and 8.
- Value-initialize both `SStep` declarations. Walking mode otherwise evaluates an indeterminate direction flag, which its crossing-distance helper ignores; meaningful step fields are assigned before use. No numerical field or priority ordering changes.
- Call `task.get()` after each ready wait, so worker exceptions reach the native exported catch and return failure; no worker calls R.
- Reject trace sizes at `INT_MAX` before narrowing to a signed index and appending. Supported traces are unchanged.

No score formula, topology or traversal is altered. See `docs/compatibility/od-betweenness.md`.

## 0007 — shared angular worker exception propagation

The AngularChoiceAlgo worker-cap transformation additionally calls `task.get()` after each ready wait, before publishing/accumulating scores. This applies to Integration and Choice and leaves caps, partitioning, traversal and accumulation unchanged. Propagated exceptions reach the bridge's catch/unwind/error boundary; the original graph remains reusable. No worker invokes R.

Original MD5 remains `f518e8c71d6c1607723564238692de62`. Combined generated MD5 including the original diagnostic prefix is `3072dd613d7e1da7998b8d9af9f5915e` (later `ec0db906b35e28c7e6077df18255b685` with 0011). Patch record: `patches/0007-angular-worker-exceptions.patch`. See `docs/compatibility/angular-controls.md`.

## 0008 — network construction safety

Preserved raw inputs `CreateJunctions.cpp` and `CreateSegmentMap.cpp` are byte-identical to the vendor source. Original MD5s: `f73b874843ccf5e16524d9a72ecf4d6d` and `b530a721b7d0351fdadd099d893a8546`; generated MD5s: `3e5712f2cd08fd5eda64edf0a0d61eff` and `98c988a98f1587bf431e120436563827`, respectively. `src/portability/harden-network-construction.R` applies only the reversible safety guards below, an explicit standard exception include and diagnostic line/path restoration. Patch record: `patches/0008-network-construction-safety.patch`.

- **Cycle guard (difference from PST).** A guard throws before `RemoveDetail` merges a segment back to its starting point. The exported catch returns null and the bridge reports failure before reading result fields. This prevents self-merging/removed-index access without skipping detail reduction or returning partial topology. The implemented condition is broader than the unsafe degree-two state: it also rejects closures at junctions of degree three or more that pristine PST completes. See `docs/compatibility/network-construction.md`. Unit- and large-square controls remain exact.
- Raw junction intersections must fit the unsigned duplicate-removal loop; final junction output counts must fit signed indexing before the unlink loop and public matrix allocation. An empty first layer is rejected in R and independently by the native bridge before the call, with no synthetic empty result.
- Discovered cut counts and generated point counts must fit signed/index bounds before narrowing and Snap's high-bit marker. Road-center mode checks actual cut/unlink counts independently from its unsplit point count.

Pristine and adapted PST structural outputs are byte-identical for 124 supported cases, with two caller-buffer seeds per case; reproduction scripts are under `tools/reference/network-construction/`.

## 0009 — Isovist post-calculation memory-safety guards

`patches/0009-isovist-safety.patch` documents the combined generated-copy edits for pinned `CalculateIsovists.cpp`: the 0001 type-name qualification plus four checks immediately before unsafe calculated-state accesses.

- An empty vertex vector fails before `back()`.
- A nonempty attraction-point queue in a partial view requires at least two vertices before its second-vertex read.
- A nonempty attraction-polygon edge queue in a partial view requires at least three calculated vertices before frustum/indexed iterator accesses.
- A full-circle view with a nonempty polygon-edge queue requires at least two vertices before its loop iterator advances.

The four guards check specified degenerate native states before unsafe accesses without modifying PST's numerical expressions. If a guard fails, temporary resources are released and the R interface reports an error without returning a partial result. Successful outputs are copied into R-managed memory before the native result is freed.

`src/portability/harden-isovist.R` verifies pristine MD5 `42c16aa243ccc11e2b2e95692407ebb7` and the complete output MD5 `f03bb50a1abf2111af63e626940267d7` (later `fd1f956a159c1d136bae53acf75227bc` with 0011). See `docs/compatibility/isovist.md` and `tools/reference/isovist/`.

## 0010 — raster safety and floating normalization

`patches/0010-raster-safety-normalization.patch` records four generated copies; preserved build inputs equal the vendor bytes. `src/portability/harden-raster.R` is the checksum authority:

| Source | Original MD5 | Generated MD5 |
| --- | --- | --- |
| Raster.cpp | `6ca93a531343e8245d6a5b8ed5da5d78` | `1685eda467e3c6724f6c86c3bca842fa` |
| gfx/Blur.cpp | `823b9af062cc27c899bbf860a0d62b92` | `707474991a984757ccf00190ce51c0a6` |
| utils/Arr2d.h | `18a0ede6363657c22c9b7bf86b7e6cb6` | `4e38f713f232f19820c5aa60fad4df75` |
| analyses/CreateBufferPolygons.cpp | `856c3252a9b756f7717161ce174f6879` | `3c24aa86b332ed2a38b69a68f654ed94` |

Numerical policy: Raster normalisation replaces `std::max(abs(min), abs(max))` with `std::max(std::abs(min), std::abs(max))` to ensure consistent floating-point calculations across toolchains. This may produce different results from unmodified PST where the original call resolves to an integer overload. All other comparison arithmetic remains unchanged, and zero denominators retain PST's native floating-point behaviour.

Raster allocation guards pitch/byte overflow and malloc failure. Blur replaces kernel `alloca` with a scoped vector, selects the central worker cap and calls `future get()` instead of `wait()` to propagate worker exceptions. The generated header overlay is selected only for the comparison translation unit; `FlipY` returns before zero/single-row pointer arithmetic and checks its row buffer before mutation. These changes preserve successful numerical and structural results: 79 direct cases cover the floating contract and all 41 Relative Percent controls remain exact. See `docs/compatibility/raster.md` and `tools/reference/raster/`.

## 0011 — compiler diagnostics

Build-copy only; `src/vendor/pstalgo/` is unchanged (121 files). Removes the diagnostics `-Wswitch`, `-Wbitwise-instead-of-logical`, `-Wreorder`/`-Wreorder-ctor`, `-Wclass-memaccess`, macOS SDK 27 `-Wunused-result` and `-Wnonportable-include-path` (the last from the former `Maths.h` include-case shim) from the generated copies. No suppression flag or pragma is used. Every edit stays within its original line, is verified by input MD5, unique pattern, full inverse-byte restoration, output MD5 and vendor/symlink guards, and is reproduced by `tools/verify-vendor.R` / `tools/test-diagnostic-fixes.R`.

| Source (generated copy) | Original MD5 | Generated MD5 | Edit |
| --- | --- | --- | --- |
| Limits.cpp | `199550e4110215e07a8ecb586a91ea5c` | `9141bd3c5e7ba646df0c81173bca7c72` | explicit empty `case _DIST_COUNT: break;` / `case EPSTADistanceType_Weights: break;` (both switches already fall out of the switch to the unchanged default return) |
| ProgressUtil.cpp | `7267986bf47780d4bbfa94553ec4f231` | `afb57f9342358c33d8a3bed02aaab813` | mem-initialiser list written in member declaration order (initialisers are constants; construction order was already declaration order) |
| AABSPTree.cpp | `d834bf5274a74b61eaa9876ed07a1490` | `2e6282e00e69ef91736df2b6f15684ad` | move-constructor initialiser order (same) |
| experimental/ShortestPathTraversal.cpp | `1a4093aa7fa0508e44356ed4fc77f813` | `70903d9e6a44683706beee1ae130ff37` | initialiser order (same) |
| include/pstalgo/geometry/IsovistCalculator.h (overlay, two TUs only) | `138e76cac9a4b608dad8f9fd7830a263` | `55f6d9bae92db7da3b227194c095230d` | initialiser order of `EdgeEndPoint` (same); selected by `-I.rpst-build/include-isovist` for `IsovistCalculator.cpp` and `CalculateIsovists.cpp`, the only includers |
| analyses/CalculateIsovists.cpp (extends 0009) | `42c16aa243ccc11e2b2e95692407ebb7` | `fd1f956a159c1d136bae53acf75227bc` | initialiser order of `CIsovistEdgeIterator` (same) |
| geometry/SignedDistanceField.cpp | `0a8942a1868d72cc7ad52d92bb73cafd` | `8cec4ab9c78d746857e7b25036a9c0ed` | `(int)` cast on each `bool` operand of four bitwise AND/OR expressions (bool promotes to int either way: identical value, both operands still evaluated — no short-circuit introduced) |
| Raster.cpp (extends 0010) | `6ca93a531343e8245d6a5b8ed5da5d78` | `3c4144d04d1f89ed25851625edeaa31c` | `case RasterFormat_Undefined: break;` after `RasterFormat_Float` in `RasterFormatPixelSize` (falls to the unchanged tail) |
| analyses/CreateBufferPolygons.cpp (extends 0010) | `856c3252a9b756f7717161ce174f6879` | `4f540cf92e30dcef34170880ee8b044a` | `(int)` casts in the bitwise bounds test (as above) |
| analyses/NetworkIntegration.cpp | `5f58c8cf6279a2c1dcaaf8cd637749fe` | `4d8fdb209ea95e16c1c569b55c81b22f` | `memset((void*)…)` (same bytes written; PST's trivial-use memset of a vector-2 array is preserved) |
| graph/AxialGraph.cpp | `8b72e64b2721ed2a53b7c9fe07511de4` | `1a2c23b55c8cd3ebfda7a7209f4f55e3` | `memset((void*)…)` of the `NETWORKLINE`/`POINT` vectors (same) |
| analyses/AngularChoiceAlgo.cpp, SegmentBetweenness.cpp (extend 0003/0007) | `f518e8c7…` / `287ec62e…` | `ec0db906b35e28c7e6077df18255b685` / `b98f83d994cb1f07d0b49ed9b280e369` | `(void)VERIFY(num_processed_segments.is_lock_free());` — the call is kept, its `nodiscard` value is discarded explicitly (valid for both `VERIFY(x) x` and `assert`) |
| geometry/Geometry.cpp | `2e33fab7ee47fe92b1cf148b1522b4b8` | `b9aff27c96b4a9a538f7ebc0e31231da` | `<pstalgo/Maths.h>` -> `<pstalgo/maths.h>`, the real file name; no include-case shim is needed |

`ProgressUtil.o` additionally receives `-Ivendor/pstalgo/src` because the generated copy no longer sits next to `Platform.h`. Object-code evidence (Linux, GCC 13 and Clang 18, identical `-O2 -ffp-contract=off`): `.text` (via `objdump -dr`) and `.rodata` are identical for all 14 changed translation units except GCC's `Raster.cpp`, whose function layout differs after the new empty `case` while Clang's output is identical.

## Build-layer floating-point evaluation policy (no source transformation)

No vendored or generated-copy bytes change. `src/Makevars` and `src/Makevars.win` append `-ffp-contract=off` (via `RPST_FP_FLAGS`) after `$(ALL_CXXFLAGS)` in every PST compile rule and in the explicit rules of the rPSTool C++ wrappers, and force-include `src/rpst-float-overloads.h`, which brings exactly eight `std::` libm overload sets (`sin cos sqrt fmod log log10 pow round`) into the global namespace with fail-closed `static_assert`s. Purpose: identical evaluation of PST's unchanged float expressions on every supported toolchain. See `docs/compatibility/floating-point-policy.md`; checked by `tools/verify-vendor.R` and `tools/test-fp-policy.R`.
