# Angular controls and native normalizers

Computed by PST v3.3.2 (commit `63df80a2cf3dd289be95ea3d91667c3490719b75`). Traversal and normalization are PST's; rPSTool does not
recompute scores.

## Contract

`angular_integration()` takes, after graph, `steps` and `radius`: `weigh_by_length = FALSE`, `normalization = "turner"`,
`angle_threshold = 0`, `angle_precision = 1`, `weight_outputs = FALSE`. `angular_choice()` takes `angle_threshold` and `angle_precision`
after its other arguments. Both require a segment graph with at most 32 endpoint incidences per coordinate. Straight, walking, steps and
angular radii are supported; `axmeter` is rejected.

| Control/output | Exact native meaning |
| --- | --- |
| Threshold | Turns strictly below the float threshold in degrees become zero. Equality is preserved. Finite negative thresholds have no effect; values above 180 zero every turn. |
| Precision | Positive unsigned whole degrees through UINT_MAX. The queue rounds each thresholded turn to integer precision units. Zero divides by zero in queue initialization and is rejected before native execution. No divisibility-of-360 restriction or clamping is added. |
| Depth/radius | Depth sums and angular limits use unrounded thresholded angles; depths use syntax units (90 degrees = 1). Precision affects shortest-path priority/ties, not reported degree conversion. |
| Node count | Reached segment count includes the origin. |
| Total weight | Sum over other reached segments, excluding the origin; unit counts when unweighted, segment lengths when weighted. It is not an invented origin-inclusive count/length. |
| Depth weight | Native sum of depth times segment weight, in syntax units; includes no invented origin contribution. |
| Integration | Select Turner, syntax/NAIN or Hillier. Weighted mode calls the corresponding length-weighted export using native total weight and depth weight; unweighted mode uses count and depth. |
| Optional columns | Weighted Integration always exposes the weight and depth-weight columns (`tw_...`, `tdw_...`); weight_outputs exposes both in unweighted mode too. Defaults avoid those buffers/columns. |
| Choice | Raw scores, weighting and the standard and Turner normalizations follow PST. Syntax (NACH) normalization of a length-weighted run uses the native length-weighted total depth (returned as `tdw_..._wl`), as the PST for QGIS plugin does; the unweighted run uses the total depth (`td_...`). `PSTAAngularChoiceSyntaxNormalize` computes `log10(score + 1) / log10(2 + TD)` for whichever depth array it receives. Scalar, multi-radius, in-memory and file outputs all follow this rule. |
| Native exceptional values | Written finite/zero/NaN/Inf values are widened without clipping, NA conversion or R recomputation. Large valid geometry can yield native overflow. |

Integration normalizers use PST's exports: `PSTAAngularIntegrationNormalize` (Turner, default), `...SyntaxNormalize` and
`...HillierNormalize`, and the matching `...LengthWeight` variants for weighted runs.

Thresholds must be finite numbers representable as float (no overflow, no non-zero underflow); precision is validated before use.
Invalid flags and normalization names are errors.

## Known limitation: recursion depth in Angular Choice (inherited from PST)

PST's `CollectScores` and `ClearProcessedFlags` (in `AngularChoiceAlgo.cpp`) recurse without a depth bound along chains of shortest-path
steps, on worker-thread stacks of default size. `ClearProcessedFlags` also runs in Angular Integration. The recursion depth is about the longest such chain, so it depends
on topology and radius, not on network size. A `steps` radius bounds the depth (about steps + 1); `walking` and `straight` radii limit the
reachable area; an `angular` radius does not bound runs of near-collinear segments.

The point at which the stack runs out depends on the platform, the thread stack size and the build; the process terminates when it does.
Long collinear chains are the typical trigger; no realistic street network is known to reach such depths. Workaround: restrict the
analysis with a `steps` (or walking) radius. See also [KNOWN_LIMITATIONS.md](../../KNOWN_LIMITATIONS.md).
