# Segment groups

Computed by PST v3.3.2 (commit `63df80a2cf3dd289be95ea3d91667c3490719b75`). PST leaves some Group Integration outputs unwritten; the
missing-output policy below defines how they are reported. rPSTool recomputes nothing.

## Public interface

| R interface | Pinned export / version | Input and result |
| --- | --- | --- |
| `segment_grouping(graph, angle_threshold=1, split_at_junctions=FALSE)` | `PSTASegmentGrouping`, descriptor 1 | Segment graph; data frame `segment_id`, `group_id`, `color` in source segment order, integer `n_groups` / `n_colors` attributes |
| `segment_group_graph(graph, group_id)` | `PSTACreateSegmentGroupGraph`, descriptor 1; `PSTAFreeSegmentGroupGraph` | Segment graph and integer/double group IDs; returns a distinct segment-group graph |
| `segment_group_integration(graph, radius=analysis_radius())` | `PSTASegmentGroupIntegration`, descriptor 1 | Group graph; group-ID ordered data frame `group_id`, `gi_<radius>`, `nc_<radius>`, `td_<radius>` |

Native zero-based group and color indices become one-based R IDs without reordering or relabeling; float results are widened to double. Grouping uses
PST's angular-deviation pairing and graph coloring; colors are labels, not RGB.
Split mode continues through degree-two intersections only. The threshold (default 1 degree; PST's own descriptor default of 0 is not used) must be a finite non-negative float (overflow and non-zero underflow are rejected). Values up to 180 are supported, and larger values are passed on unchanged.

Group graph IDs have exactly one whole value per native segment in
`1..n_segments`. Group count is their maximum. Gaps define empty native groups,
as supported by PST; IDs are not silently compacted.
Only walking and step radii actually constrain Group Integration. Straight,
angular and axmeter radius fields are rejected rather than silently ignored.
Walking limits use input coordinate units; total depth sums group transitions.
Integration and normalization are computed inside PST.

## Missing-output policy


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
   including score `-1`, zero, NaN and Inf; nothing is recomputed or imputed.

A whole group graph with zero native nodes therefore returns typed NA for every
group. An isolated/empty group in a graph with native nodes receives actual PST
writes of `-1,0,0`, which are preserved. Count one is not invented for isolated
groups. Missing NA and genuinely written NaN are distinguishable in R.

File output (`output_file`): the paired-mask policy above is persisted as Arrow nulls shared by `gi_...`, `nc_...` and `td_...`;
written `NaN`/`Inf`/`-1`/`0` stay valid. See [result files](../spatial-io/result-files.md).

## Zero-length segments

A source graph containing a zero-length segment (identical endpoints) is rejected by `segment_group_graph()` before PST is called,
because PST's group-graph construction does not terminate on it. `segment_graph()`, `segment_grouping()` and the angular analyses accept
the same graph; remove or repair zero-length segments first.

## Lifetime and limits

The group graph is a different object from segment and axial graphs and only `segment_group_integration()` accepts it. It stores the group
data by value, so it stays valid after the source segment graph is freed. Like other graphs it lives in native memory and cannot be saved
or passed to another R process. Dead, deserialised or wrong-family pointers are errors; results are independent R vectors. Worker threads
follow the cap described in [core network analyses](core-network-analyses.md#threading). Junctions with 40 incident segments are
supported (the 32-incidence limit of the angular analyses does not apply).

Reference fixtures: [`tools/reference/README.md`](../../tools/reference/README.md). Current coverage: [PST coverage](../pst-coverage.md).
