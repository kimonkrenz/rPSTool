# Angular controls and native normalizers

Authority: PST v3.3.2, commit `63df80a2cf3dd289be95ea3d91667c3490719b75`.

## Source authority and implemented contract

Authority includes both exported version-2 descriptors, complete AngularIntegration.cpp,
AngularChoice.cpp and shared AngularChoiceAlgo.cpp/header, the discrete queue,
segment representation, official ctypes wrappers, unchanged upstream tests and
both QGIS analyses/wizards. Native traversal and exported normalization routines
remain the sole computational authority. There is no new missing-output policy.

Existing positional calls/defaults and output columns remain unchanged. Angular
Integration appends `weigh_by_length=FALSE`, `normalization="turner"`,
`angle_threshold=0`, `angle_precision=1`, `weight_outputs=FALSE` after graph/steps/
radius. Choice appends threshold/precision after its existing arguments.
Registered extended native entries coexist with the original arities and defaults.

| Control/output | Exact native meaning |
| --- | --- |
| Threshold | Turns strictly below the float threshold in degrees become zero. Equality is preserved. Finite negative thresholds have no effect; values above 180 zero every turn. |
| Precision | Positive unsigned whole degrees through UINT_MAX. The queue rounds each thresholded turn to integer precision units. Zero divides by zero in queue initialization and is rejected before native execution. No divisibility-of-360 restriction or clamping is added. |
| Depth/radius | Depth sums and angular limits use unrounded thresholded angles; depths use syntax units (90 degrees = 1). Precision affects shortest-path priority/ties, not reported degree conversion. |
| Node count | Reached segment count includes the origin. |
| Total weight | Sum over other reached segments, excluding the origin; unit counts when unweighted, segment lengths when weighted. It is not an invented origin-inclusive count/length. |
| Depth weight | Native sum of depth times segment weight, in syntax units; includes no invented origin contribution. |
| Integration | Select Turner, syntax/NAIN or Hillier. Weighted mode calls the corresponding length-weighted export using native total weight and depth weight; unweighted mode uses count and depth. |
| Optional columns | Weighted Integration always exposes total_weight/total_depth_weight; weight_outputs exposes both in unweighted mode too. Defaults avoid those buffers/columns. |
| Choice | Raw scores, weighting and the standard and Turner normalizations are unchanged. **Syntax (NACH) normalization of a length-weighted run now uses the native `total_depth_weight` (the array the pinned PST for QGIS plugin passes: `pstqgis/src/pst/analyses/angularchoiceanalysis.py` line 128, weighted branch); the unweighted run keeps `total_depth` (line 177).** The exported `PSTAAngularChoiceSyntaxNormalize(scores, TD, ...)` computes `log10(score + 1) / log10(2 + TD)` and is agnostic to which depth array it receives, so this is a wrapper-policy choice aligned with the pinned caller, not a PST computational change. This replaces the earlier development behaviour (unweighted `total_depth` in weighted mode, kept "as in the existing API"); scalar, multi-radius, in-memory and file-output paths all follow it. |
| Native exceptional values | Written finite/zero/NaN/Inf values are widened without clipping, NA conversion or R recomputation. Large valid geometry can yield native overflow. |

The additional five normalization exports bound through Integration are:
`PSTAAngularIntegrationNormalizeLengthWeight`,
`PSTAAngularIntegrationSyntaxNormalize`,
`PSTAAngularIntegrationSyntaxNormalizeLengthWeight`,
`PSTAAngularIntegrationHillierNormalize`, and
`PSTAAngularIntegrationHillierNormalizeLengthWeight`.
Existing `PSTAAngularIntegrationNormalize` remains the default Turner path.
No redundant standalone score calculation is introduced.

## Validation, ownership and build safety

Both extended entries require exact live HPSTASegmentGraph tags and authoritative
native owner counts. Axial and group pointers, including misleading R wrappers,
are rejected; the established 32-incidence outgoing-mask limit remains intact.
Straight/walking/steps/angular radii remain supported and axmeter rejected.
Thresholds require finite numeric native-float values without overflow/nonzero
underflow; precision is validated before narrowing/division. Flags and exact
normalization names are validated natively. R output buffers precede owning C++
buffers; exceptions unwind owners before an R error. Returned storage survives
input mutation, graph release/GC and serialization rejection; graphs are reusable.

The existing verified AngularChoiceAlgo generated-source transformation adds
future.get() before publishing results. It preserves PST worker partitions and
central caps while propagating late failures even if all processed counters were
incremented. Exact hashes, inverse-byte checks, mutation tests and deterministic
publication remain fail-closed. Pristine source and preserved inputs remain
unchanged; see [patch provenance](../../inst/upstream/PATCHES.md).

## Direct numerical authority and regressions

`tools/reference/angular/generate-reference.py` verifies 145 pinned Git blobs before
loading a DLL, runs all six unchanged upstream angular tests and calls official
ctypes/exported C routines. Its 1,344 two-seed cases cover seven graphs, both
analyses/weights, eight angle-control combinations and six radius combinations.
Graphs include unequal lengths, branching, fractional turns, loops, disconnected/
isolated and zero-length segments, and large finite coordinates. Controls include
negative/equal/just-above thresholds, coarse precision, non-divisors of 360 and
UINT_MAX. Every requested output agrees across seeds. Each case also records all
three exported normalizations, including exceptional native values.

The fixture is generated from a DLL without the worker-exception edit.
Regeneration against the adapted DLL is byte-identical; neither generator
calls rPSTool .Call or calculates replacement scores. Installed tests compare every
case/normalizer at cap one and all unrestricted controls at cap two, preserve
legacy native arities/default outputs and verify exact origin-weight exclusion.
Boundary/lifetime tests cover malformed storage, count/float bounds, invalid
settings/flags, wrong/dead/serialized tags, release, GC and independent outputs.

`tools/reference/angular/check-worker-safety.py` builds only owned verified copies
with entry and completed-worker faults; both analyses/weights at caps 1/2/8 and
precision 1/7/UINT_MAX propagate exceptions and leave no active worker before
return. These probes are development-only; Python is not a package dependency.

## Known limitation: recursion depth in Angular Choice (inherited from PST)

**Source facts** (pinned `AngularChoiceAlgo.cpp`, all verified): `CAngularChoiceAlgo::CWorker::CollectScores` (line 325; recursive call at
line 345) and `ClearProcessedFlags(segment, forwards)` (line 380; recursive call at line 396) recurse without a depth bound. Both follow
the out-segment bits (`m_OutSegmentBits`) that `ProcessTraversalState` sets for every step that reaches a segment state with an
accumulated discretised angle not larger than its lowest so far (equal-cost ties therefore also set bits). `CollectScores` enters a
(segment, direction) state only while its `m_Score` is negative and sets it to 0 on entry, so each state is entered at most once per origin
and root direction; depth is therefore at most the number of such states along a chain of out-steps and, when the out-step structure is acyclic,
at most its longest path. The depth actually reached depends on the depth-first visiting order and can be smaller. `ClearProcessedFlags`
runs for every origin in both Angular Choice and Angular Integration (`Run`, line 76); `CollectScores` only for Angular Choice (line 71).
Workers are `std::async(std::launch::async)` tasks (even with one worker), created with default thread-stack attributes; rPSTool's worker policy
caps their number only. Out-steps are only recorded inside the radius: a `steps` radius stops expansion when `m_AccSteps` reaches the limit
(depth about steps + 1); `walking` accumulates (length + next length) / 2 per step; a `straight` radius limits the reachable area; an `angular`
radius limits accumulated turning and therefore does not bound runs of near-collinear segments.

**Measurements** (not source facts; they depend on compiler, flags and platform). Linux x86-64, GCC 13, 8 MB thread stack: depth equals the
chain length n for chains, cycles and winding chains; unrestricted collinear chains passed 64,140 and crashed at 64,531 segments with rPSTool's
-O2 build (about 128 bytes per `CollectScores` level, about 32 for `ClearProcessedFlags`), and passed 97,500 but crashed at 100,000 with an
unmodified stock CMake Release build of PST; measured depths were about 3 x sqrt(n/2) for square grids (270 at 16,020 segments), about
the diameter for trees, the main-chain length for chains with side spurs, and 46 for a 100,800-segment grid with a 15-step radius. A thread
stack of 512 KB failed Choice at about 2,800 segments and Integration at about 11,000 segments.
**macOS ARM64 (LLDB, maintainer-confirmed):** an unrestricted 8,000-segment chain crashes while a radius-limited 8,000-segment control
succeeds; both failing worker threads show repeated `CAngularChoiceAlgo::CWorker::CollectScores()` frames (`AngularChoiceAlgo.cpp:345`),
and both fault on the function-entry stack allocation `stp x28, x27, [sp, #-0x60]!` at an address exactly 96 bytes below the stack pointer,
which identifies worker-thread stack exhaustion. The default secondary-thread stack size on macOS and Windows has not been measured by us.

The failure has so far been reproduced only on synthetic collinear chains; no realistic street network is known to reach such depths, and we
have no evidence either way. The risk therefore depends on topology and radius (the longest chain of shortest-path steps), not on total
network size, and on the platform's thread stack. rPSTool keeps PST's computation unchanged and does not add a guard; the condition is documented here and in the
`angular_choice()` help. Two mitigations were evaluated and not adopted: an iterative `CollectScores` (10–50 % slower in a prototype; `ClearProcessedFlags` unchanged) and
a stack-headroom guard (about 9–11 % overhead on macOS); neither satisfies the requirement of leaving PST's traversal, numerics and
ordinary-case performance unchanged. A larger worker stack would need platform-specific thread creation inside PST and only raises the
threshold; a Linux user-level workaround (`ulimit -s`) is not portable.
