# rPSTool build-input portability patches

The vendored PST v3.3.2 source is pristine. `FILES.md5` remains the authoritative
inventory; there are no digest overrides or exceptions for downstream edits.

## 0001 — qualify the isovist result return type in a build copy only

- Original upstream input: `src/vendor/pstalgo/src/analyses/CalculateIsovists.cpp`.
- Generated build input: `src/.rpst-build/analyses/CalculateIsovists.cpp`.
- Explicit patch record: `patches/0001-qualify-isovist-result.patch`.
- Application: `src/Makevars` and `src/Makevars.win` invoke the base-R
  helper `src/portability/qualify-isovist.R`. It verifies the complete pinned input checksum, the exact
  original line, exactly one changed line, and the expected complete output
  checksum before publishing the generated copy with the return type qualified as `CIsovistContext::Result&`.
- Reason: GCC 14 rejects `Result& Result()` because the method name changes
  the meaning of the unqualified nested type name (`-Wchanges-meaning`).
- Effects: no method names, ABI, storage, control flow, or numerical expressions
  change. Upstream headers, licensing notices, and original file bytes remain
  untouched. All objects are emitted outside the vendor tree.
- Verification: complete source installation/check, private native smoke tests,
  pristine inventory verification, and exact comparison of the generated copy
  against the single documented substitution.
- Upstream issue/PR: none; no upstream writes have been made.

Other build-only compatibility files outside the vendor tree supply missing
standard declarations and `using std::isnan`, override the read-only
struct-name macro to return `const char*`, and forward `pstalgo/Maths.h` to
upstream's lowercase `maths.h` via an explicit relative path into the vendor
tree. This bypasses include-path lookup, which would resolve back to the shim
on case-insensitive macOS/Windows filesystems. They do not edit upstream source.

Enum-switch warnings are preserved for review. No enum-switch patch is
applied, including to build copies. Floating-point `abs` behavior is unchanged.

## Windows aligned allocation adapter

`src/portability/windows-aligned-allocator.cpp` includes the pristine
`SimpleAlignedAllocator.cpp` after loading its headers. For this translation
unit alone it maps `posix_memalign` to an adapter using Rtools' `_aligned_malloc`
and maps `free` to the matching `_aligned_free`. Upstream selects its Windows
allocator using `_MSC_VER`, which Rtools does not define. The adapter validates
POSIX alignment, leaves the output pointer untouched on failure, and returns
`EINVAL`/`ENOMEM` as appropriate. Only `Makevars.win` uses this build input.
No upstream bytes, allocator class/block logic, or numerical expressions change.
The private native probe checks repeated aligned allocations, block growth,
writes, and destruction on every CI platform.

R CMD build adds a final newline to C++ files under src/. To avoid accepting
any changed checksum, the exact original CalculateIsovists.cpp is preserved
as inst/upstream/build-inputs/CalculateIsovists.cpp (byte-preserving Git
attributes). Makevars transforms that input into the generated build copy.
The offline verifier requires it to equal the pristine vendored file exactly.
R's source-packaging normalization never changes the repository vendor files.
The portable transformation accepts only the original pinned input checksum.

## 0002 — scoped ownership until axial/segment handle publication

- Pinned input: `src/vendor/pstalgo/src/analyses/CreateGraph.cpp`, PST v3.3.2
  commit `63df80a2cf3dd289be95ea3d91667c3490719b75`.
- Preserved input: `inst/upstream/build-inputs/CreateGraph.cpp`, identical original
  bytes, protected by the existing byte-preserving Git attributes. This file also
  lacks a final newline; using it avoids R CMD build's normalization under `src/`.
- Generated input: `src/.rpst-build/analyses/CreateGraph.cpp`, compiled on both
  Unix and Windows instead of the vendored translation unit.
- Patch record: `patches/0002-graph-constructor-raii.patch`.
- Input MD5: `0aea4b5325e2d3177ae91d2008da4f55`.
- Output MD5: `86b06c75896c119f3f3dc99fc0a901f9`.
- Application: `src/portability/harden-graph-constructors.R` requires the pinned
  checksum, exactly one occurrence of each of five original patterns and no
  corresponding transformed pattern, verifies that reversing precisely those
  edits restores every original byte, then verifies the complete output checksum
  and unchanged input before publishing a temporary build copy. Output paths and
  resolved ancestors cannot target the vendor tree. Repeated builds regenerate
  corrupt generated state; the offline verifier instead rejects any existing drift.
- Reason: both constructors allocate a raw owning graph before operations that
  can throw. The axial constructor additionally returns `0` after allocation
  on polygon-generation failure. The wrapper cannot free unpublished handles.
- Edits: add `<memory>`, replace the two raw owners with `std::unique_ptr`, remove
  the segment failure branch's manual delete, and return `graph.release()` at
  each successful publication. Both existing `return 0` paths remain unchanged.
  Exceptions propagate unchanged while scoped ownership destroys the temporary
  graph. The existing public destructors support ordinary deletion of partially
  built graphs. All other functions, including segment group construction and
  published-handle free functions, remain byte-for-byte unchanged.
- Effects: no algorithms, graph topology, numerical expressions, public C API,
  graph object layouts, normal return values or success-path semantics change.
  All established ownership, pointer-type and numerical guarantees remain intact.
- Verification: exact preserved/vendor comparison, exact generated-copy and
  build-recipe checks, offline mutation/path rejection tests, full existing
  ownership/GC and numerical regression suite, clean installation/regeneration,
  and strict source-package checks on Ubuntu/macOS/Windows with the unchanged
  exact warning policy. No allocation fault injection or upstream writes.

## 0003 — central worker cap for the exposed asynchronous engines

`src/portability/limit-workers.R` transforms only the pinned `AngularChoiceAlgo.cpp`
and `SegmentBetweenness.cpp` into generated `.rpst-build/analyses/` sources.
The preserved `inst/upstream/build-inputs/` copies exactly match vendor bytes,
including AngularChoiceAlgo's missing final newline. The original/generated MD5
pairs are respectively `f518e8c71d6c1607723564238692de62` /
`c60ee85a2bf676f718b8b4a14b743597` and `287ec62e7e28f9955740e89545b11b13` /
`6fc7be945c0774e4f932974c290d115d` (the transformer is the checksum authority).
The patch record is `patches/0003-central-worker-limit.patch`.

Each copy substitutes the single hardware concurrency call with the central
`rpst_worker_count()` function. A `#line` directive retains the original warning
paths and line numbers, so the exact warning inventory/policy is unchanged.
The transformation verifies input checksum, exactly one old/no new pattern,
reversal to original bytes, complete output checksum and unchanged input before
safe publication. Resolved output paths cannot target vendor files. Verification
rejects existing generated drift; builds regenerate corrupt generated state.

The policy lives solely in rPSTool-owned `src/rpst-workers.cpp`: explicit positive
integer `RPST_NUM_THREADS` cap (at most UINT_MAX), else hardware concurrency (floor one);
an active `_R_CHECK_LIMIT_CORES_` (non-empty, not `false`, case-insensitive) additionally
limits the result to two. Caps cannot exceed hardware concurrency. Invalid explicit settings fail closed;
no R API or callback participates in worker selection. The public caller waits
until PST workers finish. Network Integration/Reach create no workers.

This changes worker allocation/partitioning only. PST's algorithms, float
calculations, sum accumulation loops and normalization routines remain unchanged.
Numerical tests compare caps one/two/fallback; upstream numerical predicates
remain unchanged. All exposed asynchronous analyses of the first two engines share this cap; the
other worker engines are covered by patches 0005 to 0010 and unexposed experimental engines remain unchanged. Offline tests cover
checksums, patterns, output verification, regeneration and unsafe/symlink paths.
The verifier checks pristine and preserved inputs, generated output and both OS
build recipes; CI runs this gate and the native cap tests on every platform.

## 0004 — extend existing build safety to segment groups

This extends 0002/0003 without touching pristine vendor bytes or computations.
The historical 0002 patch/checksum above remains provenance of the original
axial/segment adaptation; its current generated source now also includes the
segment-group owner adaptation described here.

- `harden-graph-constructors.R` keeps input MD5
  `0aea4b5325e2d3177ae91d2008da4f55` and adds exactly two patterns:
  `new CSegmentGroupGraph()` becomes a scoped `unique_ptr` and its successful
  publication uses `release()`. The constructor's `Create` may allocate/throw;
  the wrapper cannot free an unpublished graph. Seven reversible edits now
  produce combined output MD5 `6ae192582ff4bafaf7f03a189c7c10f5`. No graph
  algorithms, layout, return values, successful geometry or free functions change.
- `limit-workers.R` adds `SegmentGroupIntegration.cpp` with exact original MD5
  `b5b603d44a91fc8af3b769ca2e6361c6` and generated MD5
  `bfa367c70db800c0586884a462e43276`. Its single unqualified
  `thread::hardware_concurrency()` call becomes `rpst_worker_count()`. The
  preserved input at `inst/upstream/build-inputs/SegmentGroupIntegration.cpp`
  exactly matches vendor bytes, protected against packaging normalization.
  A `#line` prefix retains pinned diagnostic paths and line numbers.
- Patch record: `patches/0004-segment-groups-build-safety.patch` records the
  incremental constructor extension relative to 0002 and worker-source edit.
- Existing fail-closed transforms retain checksum/pattern/reversal/output/input
  checks, safe temporary publication, path/symlink rejection and deterministic
  regeneration. Mutation suites, offline verifier, clean-build lifecycle and both
  Unix/Windows recipes now cover the added source path.
- The existing worker function handles explicit and check caps centrally; the
  native bridge also validates caps before calling PST on valid no-node graphs,
  which return before native worker creation. No worker invokes R.

The approved missing-output policy is implemented only in the rPSTool bridge using
paired count/depth write masks. These build adaptations do not initialize PST
outputs, alter step traversal, fix its isolated-group semantics, recompute scores,
or change the pristine source. See `docs/compatibility/segment-groups.md`.

## 0005 — attraction worker caps, scratch safety and exception propagation

`limit-workers.R` now includes `AttractionReach.cpp` and `AttractionDistance.cpp`.
Preserved build inputs match the pristine vendor bytes exactly. Both Unix and
Windows compile only verified generated copies. Original/generated MD5:

| Source | Original | Generated (including diagnostic prefix) |
| --- | --- | --- |
| AttractionReach | `d62cb47abf4284376936a032de4ee90b` | `0656b38e1ee2d3be74bf84aeb1acffc4` |
| AttractionDistance | `07a228e44f51d47c8f3980b1854bb0a0` | `58ee7467cb3ca8090b2d4e176ea6b271` |

Each single hardware concurrency call becomes the existing `rpst_worker_count()`
policy. Each ready-wait loop is followed by `task.get()`, propagating worker
exceptions instead of promising partially computed output; other futures join
before native owners unwind. Reach propagates to the bridge's catch/unwind/error
boundary; Distance's existing exported try/catch returns failure. Both behaviours
are exercised using development-only fault injection into owned generated copies.

Reach's finite straight line branch uses `CAxialGraph::getLinesFromPoint`, whose
`m_tmpLineIdx` header explicitly says it is not thread-safe. A scoped unique lock
on the algorithm's existing mutex protects the query **and consumption** of that
shared buffer. This permits concurrent workers without buffer reallocation races
or another worker replacing the line list before consumption. Point fetching
releases the same mutex before this branch, so no nested acquisition occurs.
Worker stress tests compare repeated cap-two calls with cap-one native results.

The source edits are recorded in `patches/0005-attraction-worker-safety.patch`;
the generator additionally prefixes `#line 1` for original diagnostic paths.
Original known compiler-warning locations precede the new statements and remain
unchanged. Exact source/output checksums, per-pattern counts, full inverse byte
checks, deterministic publication, mutation/rejection tests, offline vendor checks
and native clean-build regeneration cover both sources. No pristine byte,
score formula, traversal, polygon sample, collection or numerical output changes.
The approved straight-only group Distance error belongs to the R/native bridge,
not this build transformation. See `docs/compatibility/attractions.md`.

Exact-path `.gitattributes` whitespace exceptions cover these two pristine
preserved inputs and the unified-diff record, matching 0004's existing policy.
All rPSTool-authored sources retain normal whitespace checking; no upstream byte is
stripped merely to satisfy a formatting check.

## 0006 — OD Betweenness scratch safety and exception propagation

`limit-workers.R` adds `ODBetweenness.cpp`, preserved byte-for-byte at
`inst/upstream/build-inputs/ODBetweenness.cpp`. Original MD5 is
`cd14c1edb6b42f5b20ae5d48ce92959f`; generated MD5 including the diagnostic
`#line` prefix is `e1abcacb8448be2aaa67b21120b4d846`.
Both Unix/Windows recipes compile only the verified generated copy.
`patches/0006-od-betweenness-safety.patch` records five reversible edits:

- Replace the active `workers.resize(1)` with
  `workers.resize(std::min(rpst_worker_count(), 1u))`. Validate central policy
  without enabling the disabled upstream multi-core branch or changing traversal.
- Value-initialize both `SStep` declarations. Walking mode otherwise evaluates an
  indeterminate direction flag, which its crossing-distance helper ignores;
  meaningful step fields are assigned before use. Angular mode already writes
  direction. No meaningful numerical field or priority ordering changes.
- Call `task.get()` after each ready wait. Worker exceptions now reach the native
  exported catch and return failure. Remaining futures join before native owners
  unwind; no worker calls R.
- Reject trace sizes at `INT_MAX` before narrowing to a signed index and appending.
  This also bounds the final signed-size loop. Supported traces are unchanged;
  impossible allocations are not required to exercise the guard.

Exact checksums, pattern counts, inverse bytes, deterministic/safe publication,
mutation tests, vendor verification and clean-build lifecycle cover this source.
Existing Windows warning lines 68/70 precede the edits and retain diagnostic
locations. Narrow exact-path whitespace exceptions preserve upstream input and
patch bytes; authored sources retain ordinary whitespace checks.

Development-only owned-copy fault probes demonstrate exception propagation,
trace-bound failure and exactly one worker at caps 1/2/8 for both costs.
The direct oracle also compares pristine OD and adapted OD outputs byte-for-byte.
No pristine vendor byte, score formula, topology or traversal is altered.
See `docs/compatibility/od-betweenness.md`.

## 0007 — shared angular worker exception propagation

The existing exact AngularChoiceAlgo worker-cap transformation additionally calls
`task.get()` after each ready wait, before publishing/accumulating scores.
This applies to both Integration and Choice and keeps their caps, worker
partitioning, traversal and numerical accumulation unchanged. Futures join before
algorithm owners unwind; propagated exceptions reach the bridge's existing
catch/unwind/error boundary. No worker invokes R.

Original MD5 remains `f518e8c71d6c1607723564238692de62`. Combined generated MD5,
including the original diagnostic prefix, is now
`3072dd613d7e1da7998b8d9af9f5915e` (the 0003 generated checksum remains historical
provenance). `patches/0007-angular-worker-exceptions.patch` records the additional
edit relative to the previously generated worker-capped source. Existing exact
checksum/pattern/inverse-byte/publication/mutation and clean-build gates cover
both edits. No preserved input or pristine vendor byte changes. Existing known
warning sites precede this added statement and retain diagnostic locations.

Development-only faults in owned verified copies test exceptions at worker entry
and after the worker has incremented every processed counter. The latter proves
that completed-count success cannot hide a late worker failure. Both analyses,
weight modes, caps 1/2/8 and precision 1/7/UINT_MAX propagate the failure and join
workers; the original graph remains reusable. No runtime probe is installed.
See `docs/compatibility/angular-controls.md`.

## 0008 — network construction safety (explicit cycle policy approved)

Preserved raw inputs `CreateJunctions.cpp` and `CreateSegmentMap.cpp` remain
byte-identical to the pinned vendor source. Their original MD5s are
`f73b874843ccf5e16524d9a72ecf4d6d` and `b530a721b7d0351fdadd099d893a8546`;
verified generated MD5s are `3e5712f2cd08fd5eda64edf0a0d61eff` and
`98c988a98f1587bf431e120436563827`, respectively.
`src/portability/harden-network-construction.R` applies only these reversible
safety guards, an explicit standard exception include, and diagnostic line/path
restoration. Both platform recipes compile the verified copies; pristine vendor
bytes and known warning locations are unchanged.

- The explicitly approved cycle guard throws before `RemoveDetail` merges a
  segment back to its starting point. The existing exported catch returns null;
  the bridge reports failure before reading result fields. It prevents self-
  merging/removed-index access without skipping detail reduction, returning
  partial topology or (as originally intended) rejecting safe closed geometry; the implemented condition is in fact broader than the unsafe degree-two state and
  also rejects closures at junctions of degree three or more that pristine PST completes (see `docs/compatibility/network-construction.md`). Original successful unit-
  and large-square controls remain exact.
- Raw junction intersections must fit the unsigned duplicate-removal loop;
  final junction output counts must fit signed indexing before the unlink loop and
  public matrix allocation. A source-confirmed empty first layer is rejected in
  R and independently by the native bridge before the call, with no synthetic
  successful empty result.
- Actual discovered cut counts and generated point counts must fit signed/index
  bounds before narrowing and Snap's high-bit marker. Road-center mode checks
  actual cut/unlink counts independently from its unsplit point count. This
  avoids a hypothetical quadratic-input cap on large sparse networks.

Checksum/pattern/inverse-byte/safe-publication tests reject source drift,
partially transformed inputs, unexpected output, wrong paths and symlink
redirection. Vendor verification rejects corrupt generated copies without repair;
clean-build lifecycle checks regeneration. Direct pristine/adapted PST structural
fixtures are byte-identical for 124 supported cases, with two caller-buffer seeds
per case. The approved failure path and transient owner cleanup are covered in
R, including non-local result-copy errors. The implemented compatibility contract is in
`docs/compatibility/network-construction.md`; the reproduction scripts are under `tools/reference/network-construction/`.

## 0009 — Isovist post-calculation memory-safety guards

`patches/0009-isovist-safety.patch` documents the combined generated-copy edits
for pinned `CalculateIsovists.cpp`: existing type-name qualification plus four
explicitly approved checks immediately before unsafe calculated-state accesses.
An empty vertex vector fails before `back()`; a nonempty attraction-point queue
in a partial view requires at least two vertices before its second-vertex read;
a nonempty attraction-polygon edge queue in a partial view requires at least
three calculated vertices before frustum/indexed iterator accesses; a full-circle
view with a nonempty polygon-edge queue requires at least two vertices before
its loop iterator advances. No algorithm, epsilon, clipping, ordering or
numerical expression is changed. Safely written degenerate outputs remain native.

The borrowed local vector returns to its pool before throwing; an acquired
result returns through RAII. Existing C-export exception handling leaves its
result handle null. The R binding checks publication, copies every successful
output while owned, then frees the result before returning independent R storage.
The context is the sole persistent public owner.

`src/portability/harden-isovist.R` verifies pristine MD5
`42c16aa243ccc11e2b2e95692407ebb7`, exact unique patterns, inverse restoration and
complete output MD5 `f03bb50a1abf2111af63e626940267d7`. It uses the existing
byte-identical packaging input, rejects vendor/symlink redirection and publishes
only verified generated state. Diagnostic `#line` directives restore pinned
vendor paths/lines; strict macOS/Windows warning inventories change only those
path spellings. The earlier qualification transformer remains independently
tested as provenance; production uses this combined transformation on both OS
recipes. Mutation, pattern/output/checksum/path, symlink, drift and clean-build
regeneration tests cover it. The evidence and the complete binding contract
are in `docs/compatibility/isovist.md`; the reproduction scripts are under `tools/reference/isovist/`.

## 0010 — raster safety and explicitly authorised floating normalization

`patches/0010-raster-safety-normalization.patch` records four verified generated
copies. Preserved build inputs remain identical to pristine vendor bytes.
`src/portability/harden-raster.R` is the exact checksum authority:

| Source | Original MD5 | Generated MD5 |
| --- | --- | --- |
| Raster.cpp | `6ca93a531343e8245d6a5b8ed5da5d78` | `1685eda467e3c6724f6c86c3bca842fa` |
| gfx/Blur.cpp | `823b9af062cc27c899bbf860a0d62b92` | `707474991a984757ccf00190ce51c0a6` |
| utils/Arr2d.h | `18a0ede6363657c22c9b7bf86b7e6cb6` | `4e38f713f232f19820c5aa60fad4df75` |
| analyses/CreateBufferPolygons.cpp | `856c3252a9b756f7717161ce174f6879` | `3c24aa86b332ed2a38b69a68f654ed94` |

The numerical policy adopted on 2026-10-09 is: disambiguate
only `std::max(abs(min), abs(max))` as
`std::max(std::abs(min), std::abs(max))`. This implements PST's existing formula
using floating absolute values consistently across toolchains. It is not
preservation of the prior Linux integer-overload result. No other comparison
arithmetic changes; zero float denominators retain native floating behavior.

Raster allocation guards pitch/byte overflow and malloc failure. Blur replaces
kernel alloca with a scoped vector, selects the central worker cap, and calls
future get() instead of wait() to propagate worker exceptions. The generated
header overlay is selected only for the comparison TU; FlipY returns before
zero/single-row pointer arithmetic and checks its row buffer before mutation.
These safety changes preserve successful numerical/structural results. Diagnostic
#line directives restore pinned paths and lines for the strict warning policy.

Input/output MD5, unique patterns, full inverse bytes, original reread, safe
publication and vendor/symlink rejection are fail-closed. Portable tests cover
all four sources, pattern mutations, generated drift without repair, recipe and
header-selection mutations, and deterministic clean-build regeneration. Both
Unix/Windows recipes select generated sources; vendor bytes stay pristine.
Development-only native fault probes cover allocation and late worker exceptions;
79 direct cases prove the floating contract and all 41 Relative Percent controls
remain exact. The ambiguity and sanitizer evidence and the implemented contract are in
`docs/compatibility/raster.md`; the reproduction scripts are under `tools/reference/raster/`. No upstream write or installed Python dependency.

## 0011 — CRAN-significant compiler diagnostics

Build-copy only; `src/vendor/pstalgo/` is unchanged (121 files). Purpose: remove every diagnostic that
makes `R CMD check` report a significant installation WARNING on macOS/Windows (`-Wswitch`,
`-Wbitwise-instead-of-logical`, `-Wreorder`/`-Wreorder-ctor`, `-Wclass-memaccess`, macOS SDK 27
`-Wunused-result`) and the rPSTool-owned `Maths.h` include-case shim (33 `-Wnonportable-include-path`
on macOS). No suppression flag or pragma is used. Every edit stays within its original line (the
`#line 1 "vendor/pstalgo/…"` prefix keeps all other diagnostic coordinates), is verified by input MD5,
unique pattern, full inverse-byte restoration, output MD5 and vendor/symlink guards, and is reproduced
by `tools/verify-vendor.R` / `tools/test-diagnostic-fixes.R`.

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
| geometry/Geometry.cpp | `2e33fab7ee47fe92b1cf148b1522b4b8` | `b9aff27c96b4a9a538f7ebc0e31231da` | `<pstalgo/Maths.h>` -> `<pstalgo/maths.h>`, the real file name; allows deleting `src/compat/pstalgo/Maths.h` and `-Icompat` |

`ProgressUtil.o` additionally receives `-Ivendor/pstalgo/src` because the generated copy no longer sits
next to `Platform.h`. Object-code evidence (Linux, GCC 13 and Clang 18, identical `-O2
-ffp-contract=off`): `.text` (via `objdump -dr`) and `.rodata` are identical for all 14 changed
translation units except GCC's `Raster.cpp`, whose function layout differs after the new empty `case`
while Clang's output is identical. The resulting diagnostic inventories were confirmed by real macOS and Windows runs of the
full local gate.

## Build-layer floating-point evaluation policy (no source transformation)

Not a source patch: no vendored or generated-copy byte changes. `src/Makevars` and
`src/Makevars.win` append `-ffp-contract=off` (via `RPST_FP_FLAGS`) after `$(ALL_CXXFLAGS)` in every
PST compile rule and in the explicit rules of the rPSTool C++ wrappers, and force-include `src/rpst-float-overloads.h`, which brings
exactly eight `std::` libm overload sets (`sin cos sqrt fmod log log10 pow round`) into the global
namespace with fail-closed `static_assert`s. Purpose: identical evaluation of PST's unchanged float
expressions on every supported toolchain. Record and evidence: `docs/compatibility/floating-point-policy.md`;
verified by `tools/verify-vendor.R` and `tools/test-fp-policy.R`.
