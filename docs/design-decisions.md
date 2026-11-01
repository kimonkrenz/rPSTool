# Design decisions

Settled decisions that govern the implementation. The exact contract of each analysis family is in
[compatibility](compatibility/); this page records the decisions themselves and why they were taken.

## Foundations

| Decision | Rationale |
|---|---|
| rPSTool wraps PST rather than reimplementing algorithms | Preserve computational authority and upstream maintainability |
| Pinned PST v3.3.2, commit `63df80a2cf3dd289be95ea3d91667c3490719b75`; never a moving ref | Reproducibility and controlled upgrades |
| Vendor the complete C++ `pstalgo` core, pristine; adapt only verified generated build copies | Lower maintenance risk; no fork |
| Exclude QGIS and Python layers; compile PST as part of the R package | CRAN portability; no external binary |
| Registered base `.Call` bridge, no Rcpp | Exact ownership and exception boundaries |
| Reuse a PST graph across analyses; graph families are exact native types | Avoid redundant construction; no unsafe casts |
| `sf` is an optional adapter, never the canonical representation | Avoid large R object overhead for big networks |
| Worker-count control is required for check and shared environments | PST creates threads from hardware concurrency |
| Support macOS, Windows and Linux | CRAN and research computing expectations |

## Two authorities

The pinned **engine** is the authority for what a native routine computes (algorithms, outputs written or left unwritten,
radius and weighting semantics, exported normalisers, descriptor layout). The pinned **PST for QGIS** (`pstqgis`) source is the
authority for what the official application does with the engine (which buffers feed which normaliser, flags, defaults and
branch structure). Equivalence with PST for QGIS is claimed only for combinations covered by a documented source trace or a
recorded manual comparison, at the evidence level actually reached. Intentional differences are listed in
[QGIS differences](compatibility/qgis-differences.md); suspected application defects are never reproduced silently.

## Policies for unwritten or unsafe native behaviour

* **Segment Group Integration.** Genuinely unwritten outputs are typed `NA` (`integration = NA_real_`, `node_count = NA_integer_`,
  `total_depth = NA_real_`). The count/depth outputs alone establish the paired write mask (`UINT_MAX` counts and `-Inf` depths
  are native sentinels); a mask mismatch is an error. No integration sentinel or recomputation; every genuinely written value
  stays intact (`-1`, `0`, NaN, Inf). The policy resolves this family only and is not a blanket NA policy
  ([segment groups](compatibility/segment-groups.md)).
* **Segment Betweenness diagnostics** use the same paired-mask approach: slots PST does not write for skipped origins are `NA`;
  raw scores are untouched ([core analyses](compatibility/core-network-analyses.md)).
* **Attraction Distance.** Only straight-only Distance with point-group origins is rejected, before the native call, because PST
  never writes its group outputs on that path. No aggregation or recomputation is invented; group Reach and written network
  group Distance remain available ([attractions](compatibility/attractions.md)).
* **OD Betweenness** preserves signed weights, native overflow results and the angular final-destination-leg walking-depth
  omission, keeps its single worker, and **rejects `axmeter` radii** because the pinned algorithm ignores them, so accepting one
  would imply a restriction that has no effect ([OD Betweenness](compatibility/od-betweenness.md)).
* **Angular analyses.** Threshold is a strict less-than; precision quantises queue costs; zero precision is rejected before the
  native division; no UI-derived clamping. Length-weighted syntax normalisation of Angular Choice uses `total_depth_weight`, as
  the plugin does. `axmeter` is rejected (the engine ignores it) ([angular controls](compatibility/angular-controls.md)).
* **Network construction.** An empty first junction layer is rejected before the native call, and a conservative guard in a
  verified build copy converts a segment-map closure onto its own start into a native failure. The guard is broader than the
  memory hazard it prevents (it also rejects closures at junctions of degree three or more that pristine PST completes); no
  zero-length segments are published ([network construction](compatibility/network-construction.md)).
* **Isovist.** State-dependent guards in a verified build copy turn unsafe calculated cardinalities into controlled failures
  without rejecting inputs by radius or view heuristics and without inventing polygon, area or visibility outputs
  ([isovist](compatibility/isovist.md)).
* **Raster comparison.** Normalised comparison selects the floating absolute value of the extrema consistently across toolchains;
  the rest of PST's formula, Relative Percent arithmetic and native non-finite results are untouched
  ([raster](compatibility/raster.md)).
* **Axial inputs and junctions.** Indexed coordinate IDs are one-based and neither compacted nor reordered; the native point-group
  count comes from the pinned getter because the exported graph info reports zero; junction scores use fresh zeroed buffers and
  keep PST's pairwise multiplicity ([axial inputs](compatibility/axial-inputs-junctions.md)).
* **Angular Choice recursion depth.** The pinned traversal (`CollectScores`, `ClearProcessedFlags`) recurses once per segment
  along shortest-path steps, so a very long chain can exhaust a worker thread's stack. This is documented in
  `angular_choice()` and the angular controls record, not changed: neither an iterative traversal (10–50 % slower in a
  prototype) nor a stack-headroom guard (9–11 % overhead on macOS) was accepted, and PST's traversal is not modified.
* **Fast Segment Betweenness** is not exposed (experimental, inconsistent upstream contract; see [PST coverage](pst-coverage.md)).

## Intentional rPSTool choices

* **Public API.** Idiomatic names without a `pst_` prefix; new optional arguments are appended, never inserted into positional
  signatures; the five radius fields of `analysis_radius()` stay independent. S3 class names (`pst_graph`, `pst_segment_graph`,
  `pst_segment_group_graph`, `pst_radius`, `pst_isovist_context`, `pst_raster`, `pst_result_file`) are stable.
* **Defaults that differ from the plugin** (segment-map `extrude = 0`, all polygon rings, unweighted Angular Choice honouring
  supplied angle settings, combined radii) and the Attraction Reach decay-constant default are recorded with their reasons in
  [QGIS differences](compatibility/qgis-differences.md).
* **Multi-radius and multi-normalisation** for Angular Choice and Angular Integration: `analysis_radius()` fields accept vectors
  (at most one varying field, no Cartesian product) and `normalization` accepts several names; PST runs once per radius and one
  combined table is returned or published once ([multi-radius](compatibility/multi-radius.md)).
* **sf adapters.** `Suggests: sf` with runtime checks; faithful sf/sfc geometry in existing arguments, converted to the established
  matrices; geographic CRS rejected, unknown CRS allowed on the user's responsibility, mixed inputs require compatible CRS;
  only CRS metadata is retained; geometry output only on explicit `output = "sf"` ([sf adapters](spatial-io/sf-adapters.md)).
* **File input.** One GeoParquet or FlatGeobuf path in `segment_graph()` and `axial_graph()`, decoded natively through the Arrow C
  stream or a vendored FlatBuffers verifier; physical file order is the segment order (indexed FlatGeobuf files are stored in
  Hilbert order, so no other ordering contract is honest). External IDs are not retained
  ([spatial I/O](spatial-io/README.md)).
* **File output.** Result persistence to Parquet and spatial output to a new GeoParquet/FlatGeobuf file use temp-file publication (POSIX `link(2)` no-clobber or `rename(2)` replace; Windows `MoveFileExW` without or with
  replacement; no durability claim). The Windows layer passed the development test suite on Windows; validation of the final release candidate on Windows is still outstanding. `network_integration(junctions = TRUE)`
  persistence is not offered: two result tables published as independent files could be left inconsistent by an interrupted
  overwrite ([result files](spatial-io/result-files.md)).
* **Test suite modes.** A CRAN mode (thinned fixture loops, no skips) and a full development mode guarded by an expectation-count
  floor ([testing](testing.md)).
* **Direct fixtures use exact hexadecimal numeric literals**, because decimal literals are not parsed identically on all R builds.
* **Deterministic floating point.** `-ffp-contract=off` in every translation unit plus a fixed set of eight `std::` overloads; only
  isovist polygon coordinates get a one-binary32-ULP allowance ([floating-point policy](compatibility/floating-point-policy.md)).
* **Test hooks** (angular instrumentation, synthetic Arrow producer, address-limit hook) stay in the shipped library with
  validated arguments, so tests run against the installed binary ([architecture](architecture.md)).
* **Licence:** LGPL-3-or-later for rPSTool-authored code ([licensing](licensing.md)).
