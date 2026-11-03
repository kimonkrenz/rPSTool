# Core network analyses and parameters — PST v3.3.2

Source of truth: PST commit `63df80a2cf3dd289be95ea3d91667c3490719b75`.
All paths below are relative to that commit's `pstalgo/`. Authority includes the exact exported headers, implementations, corresponding
`python/pstalgo/*.py` ctypes wrappers and `test/tests/*.py` numerical tests.
The Python wrappers are reference material only; they are never a runtime dependency.

| R routine / exported call | Descriptor version | Required native graph | Radius fields consumed | Distance | Output in input row order | Execution |
| --- | --- | --- | --- | --- | --- | --- |
| `network_integration` / `PSTANetworkIntegration` | 1 | `HPSTAGraph` | native: all five through `LimitsFromSPSTARadii` / BFS; rPSTool accepts only `steps` (official interface), see [parity audit](parity-audit.md) | fixed topological steps | integration, node count, total step depth | synchronous, no workers |
| `network_reach` / `PSTAReach` | 1 | `HPSTAGraph` | all five through limits / BFS | no optimization distance | reached count, full reached-line length, area | synchronous, no workers |
| `network_betweenness` / `PSTASegmentBetweenness` | 1 | `HPSTAGraph` | all five | walking, steps (default), angular, axmeter | raw betweenness, node count, total depth; optional normalized score | synchronous caller, internal async workers |
| `angular_integration` / `PSTAAngularIntegration` | 2 | `HPSTASegmentGraph` | straight, walking, steps, angular | fixed angular | selected native integration, node count, total angular depth; optional weight diagnostics | synchronous caller, internal async workers |
| `angular_choice` / `PSTAAngularChoice` | 2 | `HPSTASegmentGraph` | straight, walking, steps, angular | fixed angular | raw choice, node count, total angular depth, depth weighted by length; optional normalized score | synchronous caller, internal async workers |
| Deferred `PSTAFastSegmentBetweenness` | 2 | `HPSTASegmentGraph` | header promises only walking | header promises only angular | header marks counts and depths unsupported | synchronous caller, internal async workers |

Each entry uses its descriptor's graph type, not its name. Native tags are
validated before graph access even when R class/type/count fields are forged.
PST's `void*` aliases are not interchangeable. Angular analyses share the
existing maximum of 32 endpoint incidences per coordinate: `AngularChoiceAlgo`
uses a 32-bit outgoing-path mask. Construction remains unchanged.

## Shared radius contract

`analysis_radius(straight=NULL, walking=NULL, steps=NULL, angular=NULL, axmeter=NULL)`
represents the five independent fields of `SPSTARadii` (`include/pstalgo/analyses/Common.h`,
`src/analyses/Common.cpp`, `python/pstalgo/common.py`). NULL means absent/unlimited;
zero is a real limit. Multiple limits are passed together, preserving the engine's
own traversal semantics. No automatic unit conversion, snapping or rescaling.
Straight/walking use coordinate length units; angular uses degrees. Axmeter is
PST's accumulated length with topological weighting, not another spelling for
walking (see `src/BFS.cpp` and `src/analyses/SegmentBetweenness.cpp`).

All specified fields must be finite nonnegative numeric scalars. Steps are whole
numbers at most INT_MAX (2147483647): despite unsigned setters and the Python
wrapper's unsigned field, the pinned C++ field and LIMITS storage are signed int.
Other fields are narrowed to native float, rejecting overflow and positive values
that underflow to zero. Straight must also have a finite native float square.
The conversion is checked again at the native boundary. Unsupported fields are
errors, particularly axmeter on either angular analysis, where the engine would
otherwise ignore it. Large finite values are not converted to infinity.

Existing `steps=` calls and positional step arguments in both integration routines
remain identical. Their additive `radius=` argument conflicts with a non-NULL
`steps` argument, avoiding silent precedence or merging. Defaults remain unchanged.

## Distance, settings and normalization

`CBetweennessAlgo::Run` explicitly accepts only walking, steps, angular and
axmeter. Straight and weights exist in the enum but are rejected by this
implementation. R uses these four full names and requires exact matches.
Angular total depth is converted by PST to syntax angle units (90 degrees = 1);
other total depths follow the chosen native distance. All node counts include
origin. Reach length includes whole lines, not clipped portions. Straight-only
Reach uses midpoint distance inclusively and reports pi times squared radius;
other Reach modes report the convex hull area of reached endpoints. These
behaviours come directly from `src/analyses/Reach.cpp`.

Choice exposes upstream-tested `weigh_by_length=FALSE/TRUE`; threshold zero and precision one degree remain the defaults. Both settings are explicit controls.
Weighted choice includes origin/destination contributions (see the upstream
chain oracle); it is not a post-hoc multiplication of unweighted scores. The
weighted depth output is requested only in weighted mode, and is NULL/omitted
otherwise. Angular Integration also exposes length weighting and native syntax/Hillier normalization; see the angular controls contract.

New centrality routines retain raw scores and optionally append `normalized`
using `normalization="none"` (default), `"standard"`, `"turner"` (choice) /
`"freeman"` (betweenness), or `"syntax"`. These call `PSTAStandardNormalize`,
`PSTAAngularChoiceNormalize`, `PSTABetweennessNormalize`, and the corresponding
`*SyntaxNormalize` exports directly on the native arrays. Syntax normalization
receives `total_depth` for unweighted runs and, for length-weighted Angular Choice, `total_depth_weight`
(see the [QGIS differences](qgis-differences.md)). Network
Integration calculates its score internally and exports no separate normalizer.
Angular Integration calls the selected exported normalizer, including its matching length-weighted variants.

## Threading and lifetime

Reach and Network Integration loop on the caller thread. Segment Betweenness
and both angular analyses construct worker arrays from hardware concurrency,
launch `std::async(std::launch::async, ...)`, then wait before returning. The
bridge installs PST's progress callback only while console progress is active
([progress display](../progress.md)), otherwise the callback is null, and it uses no
R logging callbacks; workers never call R. Output R storage is allocated/materialized before C++ buffers exist;
errors are raised after those buffers unwind. The .Call roots its graph owner
and results are copied into independent R vectors.

A central build-only worker-count substitution covers the two engines used by
these public worker analyses. `RPST_NUM_THREADS` supplies a positive integer cap,
hardware concurrency (with a floor of one) is the fallback, and an active check cap
(`_R_CHECK_LIMIT_CORES_` non-empty and not `false`, case-insensitive; e.g. `true`,
`TRUE`, `warn`) is a ceiling of two that a larger explicit cap cannot lift. Invalid explicit limits fail closed before
workers start. Windows R removes an environment variable when assigned an
empty string; that platform operation selects the documented fallback, whereas
a present empty POSIX value is invalid. Explicit caps never exceed hardware concurrency. The generated
copies are checksum/pattern verified; pristine vendor bytes remain untouched.
No traversal, weighting, depth, accumulation or normalization equation changes.
The broader native worker adaptations are recorded in patch provenance; experimental engines remain unexposed.

## Pinned numerical oracles

| Analysis | Upstream test and fixtures | Comparison semantics |
| --- | --- | --- |
| Reach | `test/tests/testreach.py`: 3-line chain of length 3; square of side 3; straight/walking/steps/angular radii | exact counts and float lengths; area: actual denominator relative tolerance 0.0001, actual zero requires exact zero |
| Segment Betweenness | `test/tests/testsegmentbetweenness.py`: 5-line unit chain, symmetric split, split with shorter bottom path | exact native float raw scores: [0,3,4,3,0], [0,1.5,1.5,1.5,1.5,0], [0,1,1,2,2,0] |
| Angular Choice | `test/tests/testangularchoice.py`, `graphs.py`: 5-line length-3 chain and side-3 square; all four radii, length weighting | exact counts; `common.py` element predicate with actual denominator, 0.0001 relative tolerance and 0.0001 absolute when actual zero |
| Existing Integration | `testnetworkintegration.py`, `testangularintegration.py`; existing recorded rPSTool fixtures | preserve existing predicates and fixtures |

Tests also cover native/R widening, independently checked normalization values,
row permutation, graph reuse, lifetime, invalid parameters, and wrong handles in
both directions. Supplemental modes without a static upstream expected vector
are checked against direct pinned C API execution, not invented bridge equations.

## Exclusions

Point-origin Reach and weighted/attraction Betweenness are supported; see
[point origins and weighted modes](#point-origins-and-weightedattraction-modes). Angular controls and additional
Integration normalizers are supported; see [angular compatibility](angular-controls.md).

Fast Segment Betweenness is not exposed. Its experimental header restricts distance
to angular and radius to walking and marks weighting/count/depth unsupported, but
its tests request steps/angular radii, weighting and those outputs. The exported
implementation does not inspect `m_DistanceType` at all; traversal consults only
`radii.Walking()`. Implementation and descriptor/test promises do not establish a
coherent stable interface. A limited binding is not justified;
Angular Choice supplies the supported angular centrality surface.

Supplemental fixture `tests/testthat/fixtures/core-network-direct-v3.3.2.R` was
captured through the unchanged pinned official ctypes wrappers, loading the
compiled native C exports directly (no rPSTool `.Call` analysis). The generator
`tools/reference/core-network/generate-reference.py` verifies the reference Git blob hashes and
runs all 13 original Reach, Segment Betweenness, Angular Choice and integration
tests first. It records an asymmetric four-line endpoint-expanded graph across
all supported radius/distance combinations and exported normalization modes.
The fixture embeds the exact wrapper/test blob provenance. This supplements,
and does not replace, transcribed static upstream expectations above. It is
development-only; CI consumes R fixtures without Python. The native build has
only the previously documented build transformations and central worker
selection substitution. A `#line` directive keeps original diagnostic locations,
preserving the exact warning policy. Preserved worker source copies avoid source
package newline normalization, and are byte-verified against the vendor inventory.

## Integration outputs and upstream predicates

Network Integration preserves native `-1` for fewer than two reached lines,
NaN for the two-line formula and positive infinity for zero relative asymmetry.
Counts include the origin and depth sums topological transitions, including
collinear endpoint joins. Turner Angular Integration uses the exported native
normalizer; unweighted total depth uses syntax-angle units (90 degrees = 1).

Static integration fixtures transcribe pinned upstream tests, including the
five-line chain, single axial line and segment square. Rounded upstream scores
use the original per-element predicate: relative tolerance 0.0001 with the actual
value as denominator when nonzero, absolute tolerance 0.0001 when zero. Counts
and exactly representable integer-valued depths compare exactly. These static
fixtures supplement direct native references; no R formula replaces PST scoring.

## Point origins and weighted/attraction modes

Optional sf/sfc XY POINT supplied Reach origins and Betweenness attraction points
feed the unchanged native matrix path. Feature order and all Reach boundary/
missing-output and Betweenness weight/normalisation semantics are those of the
matrix route. See the [adapter contract](../spatial-io/sf-adapters.md) for graph-versus-analysis CRS checks.
### Public API and missing-output policy

`network_reach(graph, radius = analysis_radius(), origins = NULL)` adds optional finite
integer/double x/y matrix origins with at least one row. NULL retains every
established line-origin call and its `line_id`; supplied points produce `origin_id`
in input row order. PST receives `m_OriginCoords`/`m_OriginCount` directly, with
no graph reconstruction or R calculations.

`network_betweenness(graph, radius = analysis_radius(), distance = "steps",
normalization = "none", weights = NULL, attraction_points = NULL)` appends
optional arguments, preserving existing positional/named calls. Weights have
exactly native line count entries, or exactly the supplied attraction count.
Integer/double finite weights include zero/negative values, rejecting float
overflow and nonzero underflow to zero. Attraction coordinates use the same
minimal x/y matrix convention as Reach. PST assigns and accumulates them itself. XY POINT sf/sfc attraction points
are accepted in exact feature order and converted only to that matrix; weights
stay explicit and attributes are ignored ([sf contract](../spatial-io/sf-adapters.md#betweenness-attraction-points-and-integration-junction-output)).

Before PST, rPSTool fills count slots with UINT_MAX (impossible under signed graph
bounds) and depth slots with negative infinity (impossible for nonnegative native
distances). It detects paired actual writes after PST, fails closed on mismatched
masks, and exposes genuinely untouched slots as integer/double NA. Written
values are preserved, including nonfinite native values. Skipped origins are not
assigned replacement neighbourhood statistics. Raw scores are untouched.

Standard normalization calls `PSTAStandardNormalize` on all genuine scores.
Freeman/syntax compact only written rows into native arrays, call
`PSTABetweennessNormalize`/`PSTABetweennessSyntaxNormalize`, and scatter returned
values to their original rows. Undefined rows are NA; an empty defined set makes
no normalizer call. No normalization equations are reproduced. This explicitly
authorized wrapper policy gives a deterministic representation of missing PST
outputs without claiming zero-valued diagnostics were computed by PST.

Input safety checks precede all native allocations: shape, finite storage,
signed/descriptor counts, double-to-local-float conversion and squared-distance
extent relative to native graph geometry. Tag/liveness checks precede graph
inspection. R/ALTREP data are materialized and outputs allocated before C++
buffers exist; errors raised by native work occur only after unwinding buffers.
Inputs are not retained after synchronous calls. The earlier native entry-point arities also remain registered.

File output (`output_file`): the typed-NA policy above is persisted as Arrow nulls in `node_count`, `total_depth` and (Freeman/syntax) `normalized`;
the raw `betweenness` and the standard normalisation are never null. See [result files](../spatial-io/result-files.md).

### Other source-established semantics

- Both descriptors require the axial `HPSTAGraph`; names do not imply segment
  graph compatibility. Existing native tags/liveness checks must remain.
- Reach accepts double x/y origin pairs and unsigned origin count; its result
  loop preserves point order without changing the graph. Point indices are
  stored internally in signed int, so descriptor limits alone are insufficient.
- Straight-only point Reach tests squared midpoint distance with strict `<`;
  line Reach uses inclusive `<=`. Both return native `straightSqr * 3.1415927f`
  area even when no line is reached. A point at zero straight radius reaches no
  midpoint, unlike a line origin.
- Other point Reach modes use PST's closest-line projection. Initial walking and
  axmeter distances include the offset from the network; walking target inclusion
  adds distance along the line to its midpoint. BFS tests walking/steps/angular/
  axmeter inclusively. Combined straight limits constrain crossings, rather than
  applying the straight-only midpoint selection. Point convex-hull area includes
  the origin point as well as reached endpoints. No harmonization is warranted.
- The reproduction checks point x coordinates `-0.4999`, `-0.5`, `-0.5001` against
  the first midpoint `0.5` at straight radius 1: counts `[1, 0, 0]`, lengths
  `[1, 0, 0]`, all areas `3.1415927410125732`.
- Without attractions, weights are per line. With attractions, PST converts each
  double world point to float local coordinates, calls `getClosestLine`, and
  sums the supplied float weight (or unit weight) on the assigned line in input
  order. Closest-line ties follow PST's sphere-tree iteration and strict distance
  improvement, not an R nearest-feature rule. Float accumulation need not be
  invariant under arbitrary permutations.
- Weighted dependency accumulation includes endpoint and self contributions;
  unit weights are not generally identical to unweighted betweenness. Nonpositive
  origins are skipped, but signed destination weights enter dependencies. QGIS
  passes attribute values without a general sign restriction; attraction null
  attributes become zero. The source does not justify silently clamping weights.
- Radius restrictions remain independent of the four primary distances.
  Standard, Freeman and syntax normalization remain exported PST calls; raw
  scores must remain available. Their input metrics follow the paired-write policy above.
- World-to-local conversion subtracts the graph's double origin then narrows to
  float. Input validation checks local coordinates and squared
  distances, with graph tags checked before native storage access and R errors
  raised only after live C++ allocations unwind.

### Reference fixture and regression coverage

`tools/reference/reach-betweenness/generate-reference.py` first verifies the 23 pinned source blobs and
runs five unchanged upstream tests, then records
`tests/testthat/fixtures/reach-betweenness-direct-v3.3.2.R`. The 147 cases use three
small networks: a three-line unit chain, an asymmetric four-line bent network,
and one isolated line. Before recording weighted outputs it repeats each call
with two different impossible count/depth initializations and checks identical
scores, paired write masks and written diagnostics. Every numerical score,
depth, length, area and normalization value comes from the pinned exported C API;
only genuinely untouched diagnostics receive the adopted NA representation.
Fixtures regenerate byte-for-byte. Python remains development-only.

Coverage includes point input order, on/off-network origins, the strict straight
boundary and zero radius, all five radius fields and meaningful combinations;
unit/fractional/nonuniform/zero/negative line weights; omitted/unit/unequal/zero/
negative attraction weights, cancellation, repeated assignment, off-network
assignment and exact paired permutations; all four primary distances; standard
normalization, compact Freeman/syntax normalization with mixed/all missing rows,
and written normalizer NaN distinguished from missing NA. Obvious three-line
and isolated-line assertions supplement the direct oracle. Signed inputs retain
PST's signed accumulation semantics rather than a new positivity restriction.

R/native regression tests also cover shape/storage/finite-value failures,
zero-row input, integer NA, positive/negative coordinate overflow, weight length
mismatch and float overflow/underflow, valid subnormal weights, integer/ALTREP
input, large world offsets with safe local coordinates, ignored column names,
wrong graph families, forged metadata, dead/deserialized external pointers,
repeated release, repeated mixed analyses, GC/finalizer counts and output lifetime
independent of both inputs and graphs. The existing core fixtures and tests
remain present, with explicit NULL-mode/legacy-native comparisons as well.
