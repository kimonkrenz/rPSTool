# OD Betweenness compatibility and provenance

Optional sf/sfc XY POINT supplied origins now feed the unchanged native matrix
path, preserving feature order. Explicit origin weights remain per feature;
destination weights remain per retained native point, including polygon samples.
See the [adapter contract](../spatial-io/sf-adapters.md) for graph-versus-analysis CRS checks.
No numerical fixtures or native algorithms changed.

Authority: PST v3.3.2, commit `63df80a2cf3dd289be95ea3d91667c3490719b75`.
## Native contract and public API

`od_betweenness(graph, origins, radius = analysis_radius(), distance = "walking",
destination_mode = "all", origin_weights = NULL, destination_weights = NULL)`
calls exported `PSTAODBetweenness`, descriptor `SPSTAODBetweenness` version 1.
It requires the exact live axial `HPSTAGraph` tag. Segment and group graphs are
rejected without casting. Supplied x/y origin rows remain ordered. Destinations
are retained native graph points: polygon-generated samples each require their
own weight, not one weight per polygon/group. No duplicate R geometry is stored.

The result is independent R storage: one-based `line_id` and native float
`od_betweenness` widened to double, in native input-line order. The graph remains
reusable; results survive mutation/collection/release of graph and input storage.
Empty origin/destination sets return native written zeros. No Group Integration
NA policy is applied; this routine clears every score on successful computation.

| Choice | Pinned behaviour preserved |
| --- | --- |
| Primary cost | Walking or angular only; enum names alone do not establish support for other costs. |
| All destinations | Native flow uses positive reached destination weights and their sum. |
| Closest | Stops at the first destination reached by the native priority queue; ties follow that queue, with no equal-path redistribution guarantee. |
| Origin weights | NULL means unit; finite native-float signed values are passed unchanged. Nonpositive traces contribute no positive score under the native filter. |
| Destination weights | NULL means unit; nonpositive values are excluded by PST before queueing. |
| Limits | Straight, walking, steps and angular checks remain independent of primary cost. Axmeter is accepted and ignored by pinned OD. |
| Walking depth | Walking primary includes off-network origin/destination legs. Angular primary omits the final destination leg from walking-depth checks. |
| Extreme values | Valid finite weights may overflow intermediate native float operations, producing Inf or filtered zero scores. Written values are preserved without clipping or missing-value substitution. |
| Normalization | The descriptor provides raw scores; no new normalization or R formula is introduced. |
| Workers | The upstream multi-core branch is disabled. OD retains exactly one asynchronous worker even with a higher central cap. |

Source authority inspected: exported header, complete OD implementation, official
Python wrapper, unchanged upstream tests, QGIS analysis and processing caller.
Primary-cost restrictions follow implemented distance updates/checks, not UI
labels. These semantics do not require a new human numerical-policy decision.

## Boundary, safety and lifetime

The registered seven-argument `.Call` validates pointer tags/liveness, numeric
matrix storage/dimensions, finite world/local coordinates, native counts and
squared-distance bounds against the complete graph extent. Weights must fit
native floats without overflow or nonzero underflow, and match native counts
rather than mutable R metadata. Modes and radii are validated again natively.
Outputs are allocated before owning buffers. Exceptions are caught and owners
unwind before raising an R error; callbacks are null and workers never call R.

Verified generated copies initialize an otherwise ignored walking direction flag,
propagate worker exceptions with `future.get()`, guard signed trace indexing and
validate central worker caps while retaining one worker. Pristine vendor sources
remain unchanged. [Patch provenance](../../inst/upstream/PATCHES.md) records exact
input/output checksums, five reversible edits and diagnostic-line preservation.

## Numerical and structural evidence

`tools/reference/od-betweenness/generate-reference.py` verifies 137 pinned Git blobs before loading
any library and executes the official ctypes wrapper/export directly. Python is
development-only. All five unchanged upstream OD tests run as part of generation.
The fixture contains 2,110 cases across seven graphs: indexed chains, directional
and disconnected topology, unlinks, polygon-generated native samples, translated
coordinates, same-line destinations and empty sets. It covers both costs/modes,
independent and mixed limits, unit/asymmetric/signed weights, zero limits and
native overflow. Distinct caller score seeds prove successful writes.

Fixtures originate from a DLL with the pristine OD implementation.
Regeneration against the safely adapted OD implementation matches byte-for-byte;
no rPSTool `.Call`, reconstructed algorithm or guessed expected values generates
these results. Installed R tests compare all cases, including native Inf/NaN
classification, row order and cardinality. The fixture's axmeter cases remain
native evidence that the pinned algorithm ignores that limit; the R wrapper rejects
axmeter radii (below), so wrapper-level tests use the supported cases. Dedicated
controls preserve the angular final-leg depth omission.

Boundary tests cover malformed storage, float/coordinate bounds, wrong/dead/
serialized tags, repeated release, GC, independent result storage, native point
counts despite forged metadata, worker-policy failure/recovery and established
Integration regression. `tools/reference/od-betweenness/check-native-safety.py` compiles only
owned verified copies with development-only injected faults. Worker-entry failure
and a lowered trace bound return native failure without publishing scores;
worker-count instrumentation confirms one worker at caps 1/2/8 for both costs.
No production fault-injection interface is installed.

## axmeter radius rejected (maintainer decision)

`od_betweenness()` raises an error for any `analysis_radius(axmeter = )` before OD Betweenness calculation (after the graph liveness check and the shared radius validation, which itself calls native validation), on the in-memory, `output_file` and `spatial_output_file` paths alike (the check sits in the single R entry
point). Reason: the pinned OD Betweenness implementation never reads the axmeter limit, so the axmeter restriction has no effect and the result is identical to the same call without it
(evidence N in the fixture; S in the implementation). Straight, walking, steps and angular limits and all native results are unchanged.
`analysis_radius()` still accepts axmeter and other analyses that honour it are unaffected.
