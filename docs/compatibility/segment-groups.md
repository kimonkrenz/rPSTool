# Segment-group family: implemented contract

Authority: PST v3.3.2, commit `63df80a2cf3dd289be95ea3d91667c3490719b75`.
PST leaves some Group Integration outputs unwritten; the adopted typed-NA policy below defines how they are reported. No PST computations are
reimplemented; no pristine vendor byte changes.

## Public interface and native authority

| R interface | Pinned export / version | Input and result |
| --- | --- | --- |
| `segment_grouping(graph, angle_threshold=1, split_at_junctions=FALSE)` | `PSTASegmentGrouping`, descriptor 1 | Live `HPSTASegmentGraph`; data frame `segment_id`, `group_id`, `color` in source segment order, integer `n_groups` / `n_colors` attributes |
| `segment_group_graph(graph, group_id)` | `PSTACreateSegmentGroupGraph`, descriptor 1; `PSTAFreeSegmentGroupGraph` | Live segment source, integer/double group IDs; distinct owned `HPSTASegmentGroupGraph` |
| `segment_group_integration(graph, radius=analysis_radius())` | `PSTASegmentGroupIntegration`, descriptor 1 | Live group graph; group-ID ordered data frame `group_id`, `integration`, `node_count`, `total_depth` |

Native zero-based group/color indices become one-based R IDs without reordering,
compaction or relabeling. Native float results widen to R doubles. Grouping uses
PST's angular-deviation pairing and graph coloring; colors are labels, not RGB.
Split mode continues through degree-two intersections only. Thresholds are
finite non-negative native floats, rejecting overflow and nonzero underflow.
The pinned header's 0–90 comment is narrower than implementation/upstream tests:
100/180-degree cases are supported; values above 180 are also passed directly.

Group graph IDs have exactly one whole value per native segment in
`1..n_segments`. Group count is their maximum. Gaps define empty native groups,
as supported by PST; IDs are not silently compacted. Native group count is kept
in owner storage, independent of editable R list fields and grouping attributes.
Group count is at most segment count, itself bounded by signed R/native counts.
No full geometry or group-ID vector is duplicated in the R graph wrapper.

Only walking and step radii actually constrain Group Integration. Straight,
angular and axmeter radius fields are rejected rather than silently ignored.
Walking limits use input coordinate units; total depth sums group transitions.
The native traversal is preserved, including multi-origin group traversal and
its walking-radius behavior; it is not replaced with a new shortest-path method.
Native Integration computation/normalization occurs inside PST, with no R formula.

## Missing-output policy

The following family-specific policy was adopted after direct output-write reproduction. PST remains the computational authority.

1. Initialize native count outputs with `UINT_MAX`. It exceeds every legitimate
   reached-group count because group count <= segment count <= `INT_MAX`.
2. Initialize native depth outputs with negative infinity. Pinned depth derives
   from non-negative unsigned step counts, so it cannot be negative infinity.
3. After native success, derive both diagnostic write masks independently and
   demand identical written/unwritten masks. Mismatch errors after native
   temporaries unwind; partial output is never returned.
4. For paired **unwritten** diagnostics, return score `NA_real_`, count
   `NA_integer_`, depth `NA_real_`.
5. For paired **written** diagnostics, preserve native score/count/depth values,
   including score `-1`, zero, NaN and Inf. There is **no integration sentinel**,
   no nonfinite-score classification, no recomputation or imputation.

A whole group graph with zero native nodes therefore returns typed NA for every
group. An isolated/empty group in a graph with native nodes receives actual PST
writes of `-1,0,0`, which are preserved. Count one is not invented for isolated
groups. Missing NA and genuinely written NaN are distinguishable in R.
The implementation shares one native conversion routine with a private synthetic
buffer test hook, allowing both directions of mask disagreement to be tested
without fault injection into PST or mutable graph state.

File output (`output_file`): the paired-mask policy above is persisted as Arrow nulls shared by `integration`, `node_count` and `total_depth`;
written `NaN`/`Inf`/`-1`/`0` stay valid. See [docs/37 §13](../spatial-io/result-files.md).

## Ownership, native safety and worker policy

The group external pointer has its own exact tag and native owner containing only
handle/count. `PSTAFreeSegmentGroupGraph` runs exactly once. Aliases share the
owner; dead/deserialized pointers error; repeated private release is harmless.
Group creation stores nodes/group IDs/distances by value and retains neither
source segment handle nor input ID storage. Analysis remains valid after the
source segment graph is explicitly freed. Results remain ordinary independent
R vectors after all graph owners are collected.

Both public wrappers and private native entry points are tested for invalid
storage, lengths, numeric bounds, integer NA, nonfinite IDs/thresholds, wrong
families and liveness. Source native count is authoritative. R/ALTREP inputs are
materialized before native allocations. Output/owner R objects are allocated
and protected before C++ owning temporaries. Native exceptions are caught;
`Rf_error` runs only after unwinding. No R APIs or callbacks execute in workers.

The existing constructor transformation now scopes the unpublished group graph
until successful publication, avoiding leaks if `Create` throws. Group
Integration's single hardware concurrency call uses the existing central cap.
Caps are validated even when a no-node graph returns before worker creation.
These exact, checksum-verified build-copy edits are documented in
`inst/upstream/PATCHES.md` / patch 0004. Native topology, score calculation,
traversal and output writes are unchanged. Both OS recipes and mutation tests
cover the extended transforms; the pristine vendor remains untouched.

## Structural/numerical oracle and production regressions

`tools/reference/segment-groups/generate-reference.py` verifies **29 exact pinned
header/source/wrapper/traversal/color/test/caller Git blobs**, including the
19 blobs of the output-write check. Hashes were checked independently
against the pinned GitHub recursive tree. It runs all six unchanged upstream
Segment Grouping/Integration tests, then records
`tests/testthat/fixtures/segment-groups-direct-v3.3.2.R` without any rPSTool analysis
or numerical equation.

The fixture contains **28 grouping cases and 280 integration cases**. Every
integration uses two different count/depth seeds (`UINT_MAX/-Inf` and
`UINT_MAX-1/-1`) plus score seeds 17 and NaN. Only diagnostic masks determine
missing rows. Written values and masks agree between calls, including native
NaN/Inf; fixtures regenerate byte-for-byte. The raw native observations of the
output-write check are in `tools/reference/segment-groups/output-write-results.json`.

Coverage includes pinned chain, square and crosshair tests; thresholds 89/90,
100/180/181; split modes; explicit multi-segment groups; reversed group-ID and
segment order/direction; empty group labels; isolated/disconnected no-node
networks; mixed connected/isolated groups; finite/NaN/Inf connected results;
walking/step zero and boundary limits plus combinations; translated coordinates;
and a 40-incidence junction (no angular engine's 32-bit path-mask restriction
is incorrectly imported into this family).

Production tests compare exact counts/structure and missing/nonfinite classes.
Finite fixture comparisons use tolerance `1e-7` for cross-toolchain native float
math; no discrepancy is hidden by rewriting values. Synthetic conversion tests
check exact preservation and score-seed independence. Lifecycle tests exercise
source release, alias retention, repeated create/release/GC, error after handle
acquisition, failed-input paths, and output lifetime. Native mask disagreement
fails closed in both directions. Worker tests compare cap 1/2/hardware and invalid
caps on connected/no-node graphs. Existing Reach/Betweenness and core APIs remain intact.

## Reproduction

After repository validation, with development R/Python/reference paths adapted:

```sh
RPST_NUM_THREADS=2 LD_LIBRARY_PATH="$R_HOME/lib:$LD_LIBRARY_PATH" python3 \
  tools/reference/segment-groups/generate-reference.py \
  "$PINNED_ROOT" \
  "$LIBR_PATH" "$PST_DLL" \
  work/segment-groups/regenerated.R
cmp tests/testthat/fixtures/segment-groups-direct-v3.3.2.R \
  work/segment-groups/regenerated.R
```

Python, the reference checkout and network access are development-only. Installed
package tests load checked-in fixtures offline. Current status is in [PST coverage](../pst-coverage.md).
