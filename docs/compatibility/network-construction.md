# Explicit network construction compatibility

Authority: PST v3.3.2 / `63df80a2cf3dd289be95ea3d91667c3490719b75`.
Junction creation and segment-map construction are implemented together.
The native hazards that motivate the failure policy below (an unwritten empty first junction layer and
cyclic detail reduction) were reproduced by direct execution of the pinned engine; the scripts are in
`tools/reference/network-construction/`.

## Public contracts and native computation

`create_junctions(x, line_indices = NULL, y = NULL,
line_indices_y = NULL, unlinks = NULL, output = "native")` returns a copied double `x,y` matrix.
Each layer accepts packed endpoint rows or coordinate rows plus one-based index
pairs. Indexed first-layer world centering uses the native coordinate prefix
through its highest index; no compaction/recentering changes that contract.
Two layers retain unique inter-layer intersections; one layer retains repeated
pairwise points with the native .02 interior-tail rule. A shared endpoint of two
lines need not qualify in one-layer mode. Native sorting and the source-defined
unlink nearest-point/leading-survivor compaction behaviour remain unchanged.
An explicitly empty second layer is kept nonnull to preserve two-layer mode.

`create_segment_map(coords, sections = NULL, network_type, snap, tail, deviation,
extrude, unlinks, output = "native")` returns `segments` (double endpoint rows), `source_id`
(one-based native base IDs) and `unlinks` (double coordinate rows). It calls
PST once; no R calculation reconstructs cuts, merges, snaps or trims. Endpoint
copying follows the pinned QGIS caller because native results provide segment
indices but no coordinate-array count, and can retain unreferenced points.
Native segment order, direction, repeated/skipped IDs and duplicate unlinks
are preserved. IDs associate results with input objects, not persistent IDs.

Sections are signed native counts: negative `-(n + 1)` sections continue the
same base object; nonnegative `n` sections advance its ID. Empty and one-point
sections are valid alongside actual edges. A final negative section is accepted:
its edges have the current native ID even without a subsequent positive section.
Both native network types are exposed. Axial/segment mode splits at cuts and
supports unlinks with the strict native 100-unit radius. Center-line mode emits
cuts as unlinks and clears them before splitting. All four native thresholds
are explicit; defaults match Python, including independent extrude 0 rather
than QGIS's incidental extrude=snap choice. No graph is silently constructed;
users may pass endpoint rows to the appropriate graph constructor explicitly.

## Approved hazards and boundary safety

The contract applies these source-grounded failure policies:

- Reject an empty first junction layer before PST, in R and independently at the
  registered native boundary. It otherwise succeeds without writing its fields.
  No seeded/initialized coordinates, NA policy or synthetic successful empty
  point set is introduced. Nonempty inputs producing written zero-row results
  remain supported and typed as double matrices.
- Throw before any detail-reduction merge closes a segment onto its own start
  (`p2_index == s0.m_P0`). The native exported catch returns null and the bridge
  raises an R error without reading result fields. Do not skip merging,
  manufacture partial topology or change thresholds.
  **Scope of the guard (ASan/UBSan, pristine PST).** The memory-unsafe
  state is only a closure at a start junction whose segment count is at most two (a
  fully degree-two ring: the merge writes a self-referencing junction and a later
  iteration indexes `points[UINT_MAX]`). The implemented condition is broader: it
  also rejects a closure at a junction of degree three or more (for example a
  cul-de-sac loop, a figure-eight, or a ring whose spur was trimmed), which pristine PST
  completes without a memory error as a zero-length self-loop. The broader rejection
  is retained as an explicit policy: rPSTool does not publish zero-length self-loop
  segments, which downstream angular analyses would count as extra nodes. A narrower
  `count <= 2` guard was evaluated (no crash-to-OK in about 80,000 fuzz cases) and
  declined; it would need an approved policy for zero-length segments. A closure
  needs every intermediate vertex of the chain to pass the deviation test against
  the chord, which for ordinary vertex spacing requires a large detail-reduction
  threshold (an inference from the algorithm and constructed examples, not a
  measured prevalence on real street data).
  The guard can therefore reject inputs that unmodified PST would process (it never
  alters a result): numerical and structural preservation holds for the inputs rPSTool
  accepts, whose output equals the unmodified PST computation, not for every input
  that pristine PST completes. The successful unit square (zero deviation) and large
  square (deviation one) retain their original native endpoint order and values exactly.

The guard is applied only to exact verified generated copies. Original vendor
bytes remain pristine. Narrow guards also bound raw intersection loops and actual junction/cut/native-point
counts before signed narrowing/high-bit Snap indexing, rather than limiting
inputs by theoretical pair counts. Exact checksums, inverse edits, output-path
protection and line/path directives preserve source integrity and warning policy.
See [patch provenance](../../inst/upstream/PATCHES.md#0008--network-construction-safety-explicit-cycle-policy-approved).

The bridge validates storage/dimensions, finite coordinates, one-based indices,
section encoding and exact coordinate partitioning, native counts, local float
narrowing, world-center arithmetic and distance extents. At least one edge is
required for segment-map construction before the native zero-edge underflow
path. Thresholds are finite nonnegative native floats, with squared values
representable where PST squares them; no silent clamping is performed. Supplied
unlinks are allowed only in axial mode when nonempty, matching PST's own check.
No Python, QGIS, `sf` or new system dependency is required by the installed API.

## Ownership and evidence

Both native exports return `IPSTAlgo*` owners whose vectors back result pointers.
The bridge protects a privately tagged external pointer before native work,
transfers the owner without R allocation, and unwinds input C++ vectors before
allocating result arrays. `R_UnwindProtect` frees and clears the pointer after
successful copying or any R non-local jump. The registered finalizer is an
idempotent fallback. C++ exceptions are captured and raised only after owners
unwind; null results are checked before any field read. No native handle escapes
and returned R arrays survive input GC, serialization and later graph release.
Both native utilities run synchronously; their progress callback is installed only
while console progress is active ([progress display](../progress.md)) and is otherwise
null. No R API call occurs inside native algorithm execution or a worker thread.

The [oracle generator](../../tools/reference/network-construction/generate-reference.py) verifies
[153 pinned blobs](../../tools/reference/network-construction/source-blobs.json) against the
pinned recursive tree and calls exported PST directly. All four unchanged
upstream tests pass. Its 124 supported fixtures include one/two/indexed layers,
empty written outputs, sorted intersections, .02 thresholds, unlink quirks,
large world offsets, signed/multipart/empty/singleton sections, duplicates,
zero-length inputs, disconnected networks, safe closed loops, both network
modes, snapping, tail/deviation/extrude controls and cut-unlink radius boundaries.
Every fixture agrees across seeds 17/29; pristine and adapted DLL output JSON
is byte-identical. Installed tests use the static R fixture, with no network
or Python runtime dependency. Regenerate with:

```sh
python3 tools/reference/network-construction/generate-reference.py PINNED_ROOT LIBR_PATH PST_DLL OUTPUT_JSON
Rscript tools/reference/network-construction/write-r-fixture.R OUTPUT_JSON tests/testthat/fixtures/network-construction-direct-v3.3.2.R
```

Regression tests cover approved pre-call rejection, three formerly crashing
cycles (including snapping and zero deviation), exact successful closed controls,
malformed direct `.Call` inputs, typed output shapes/order/IDs and owner cleanup.
Thirty-two successful/failing-copy invocations create and free exactly thirty-two
transient owners; native counters remain at zero live owners after GC. Injected
R errors after partial allocation exercise the actual non-local cleanup path,
not a replacement algorithm. Failed native cycle calls return no result owner.

## Optional sf representation

The [construction contract](../spatial-io/sf-adapters.md#explicit-construction-adapters)
defines sf/sfc inputs and explicit `output="sf"`. Junction packed/indexed/unlink
inputs reuse the shared LINESTRING/POINT converters. Segment-map features derive
signed sections: LINESTRING supplies every vertex; MULTILINESTRING supplies
ordered parts with negative earlier counts and a nonnegative final count, never
an edge between parts. Empty and singleton features/parts preserve source-ID
advancement; at least one edge remains required. For sf coords, sections must
be NULL; existing positional matrix calls are unchanged.

Junction sf output contains POINT geometry and one-based junction_id. Segment-map
sf output retains the three-component list: LINESTRING sf segments with source_id,
the unchanged source_id vector, and geometry-only POINT sf unlinks. Outputs use
only copied native arrays and compatible supplied sf CRS metadata. Matrix-only
sf output has unknown CRS. No algorithm, guard, ownership, fixture or vendor byte
changes accompany these adapters. All 124 direct fixtures are compared exactly
through the sf conversion and output paths; the existing matrix fixture tests
remain the independent direct-PST authority.
