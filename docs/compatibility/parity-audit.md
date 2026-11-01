# rPSTool interface-parity and parameter-compatibility audit

Pinned upstream: PST v3.3.2 (`63df80a2cf3dd289be95ea3d91667c3490719b75`). Evidence labels follow the internal engineering rules, section 3 (S source, N native execution, E rPSTool
execution); no Q-level (QGIS-run) evidence exists. Rows cite upstream files and lines in the evidence files below.

> **Former name.** This audit and its evidence files under `parity/` were written when the package was called `rPST`; the evidence files keep that name unchanged as historical records. The package is now `rPSTool` (see the [release checklist](../release-checklist.md)).

## 1. Deliverables in this directory

| file | content |
|---|---|
| [parity/parity-matrix.csv](parity/parity-matrix.csv) | 253 rows, 18 columns incl. `decision` (function, parameter, native / Python / rPSTool exposure, defaults, evidence, classification, tests, risk, recommendation) |
| [parity/evidence-axial.md](parity/evidence-axial.md), [evidence-segment.md](parity/evidence-segment.md), [evidence-points-misc.md](parity/evidence-points-misc.md) | row-by-row evidence behind the matrix |
| [parity/walking-radius-diagnosis.md](parity/walking-radius-diagnosis.md) | walking-radius investigation (research record; no native change planned) |

## 2. Governing principle and decision table

rPSTool is an R interface to the supported PST software, not a fork or a development project for the engine. The official Python/QGIS
implementation is the primary reference; the native API is the secondary reference. Where the official execution code deliberately
excludes a capability, rPSTool ordinarily respects that boundary; GUI-only simplifications and established, validated rPSTool extensions
are retained. The matrix has a `decision` column (Retain, Restrict, Correct, Document, Defer) added to the original A-G
classification, which is retained as the evidence record.

| decision | rows | meaning |
|---|---|---|
| Retain | 228 | legitimate, safe, useful behaviour or established extension (all 89 remaining class-D and 6 class-C rows, and the class-G rows) |
| Restrict | 5 | NI-004 to NI-008: Network Integration steps-only (implemented, section 3) |
| Correct | 3 | SG-010, SGR-011 (zero-length guard), SGR-018 (message); implemented |
| Document | 8 | inherited PST behaviour explained, no implementation change |
| Defer | 9 | optional convenience outside this PR (multi-valued radius for NI/NR/NB, area opt-out, MULTILINESTRING relaxation, orientation check, raster size warning, weight normalisation vector) |

Reassessment of class C and D (summary; row evidence in `parity/`):

* **Deliberate in the official Python execution code:** Network Integration steps-only (`networkintegrationanalysis.py` builds
  `Radii(steps=...)`, wizard `RadiusPage(radius_types=[STEPS])`, commit `5f3f70f`, present in v3.3.2). Implemented as a restriction.
* **GUI-only simplifications (the Python API and execution path accept them):** walking/straight/axmeter radius types and angular
  distance in several wizards, hidden controls (Isovist `perimeter_segments`, buffer mode and floor `m`), junction-output options.
  Retained.
* **Features removed from the plugin in later versions but never recorded as prohibited:** Network Betweenness angular distance and
  Turner/NACH normalisations (`1c166e8`), buffer `relative_percent` (`c0fb690`). Native-supported, fixture-covered rPSTool extensions.
  Retained; listed for maintainer review only.
* **rPSTool combines limits that the plugin runs one type at a time (`Radii.split`):** Reach, Network and Attraction Betweenness, OD
  Betweenness, Attraction Reach, Segment Group Integration. Combined limits are legitimate rPSTool functionality (the native API takes
  them together). Retained. Some combinations are slow or memory-hungry in PST (section 4); recorded, not restricted.
* **Unsafe native combinations:** zero-length segments in `segment_group_graph()` (guarded, section 3); inherited recursion depth
  (AI-018, AC-017, documented).
* **Python-only post-processing** (class C: mean depth, area units, point centroids): not reproduced; documented.

## 3. Corrections implemented

| # | discrepancy | evidence | correction | behaviour change |
|---|---|---|---|---|
| 1 | NI-004 to NI-008: `network_integration()` accepted straight, walking, angular and axmeter radii, alone or mixed with steps | upstream `networkintegrationwiz.py:34`, `networkintegrationanalysis.py:45-48`, commit `5f3f70f` (17 Oct 2024); executed native runs show the engine accepts them | `network_integration()` accepts no radius or a steps-only radius (argument `steps` or a `pst_radius` that sets only `steps`); any other limit, alone or mixed, is rejected with an error before the native call that cites the official v3.3.2 interface. Public argument names, the shared radius code and all numerical results for supported calls are unchanged. The previous unrestricted body is kept as the internal `.pst_network_integration_run()` so native-oracle regression tests still exercise every radius field | non-steps radii now error |
| 2 | SG-010 / SGR-011: `segment_group_graph()` on a segment graph with a zero-length segment (both endpoints identical) never terminates (CPU-bound, not interruptible) | executed in an isolated process under timeout | the rPSTool bridge counts zero-length segments when the segment graph is built (matrix and GeoParquet routes) and `segment_group_graph()` raises an error naming the count before the native call. `segment_graph()`, `segment_grouping`, Angular Integration and Angular Choice are unchanged | an input that hung now errors |
| 3 | SGR-018: wrong-graph error named a class (`pst_segment_graph()`) | R source | message names the constructor; the tested substring is unchanged | message only |
| 4 | documentation | rows NI-004, AR-005, AR-007, AR-008, AD-008 | roxygen, regenerated Rd, vignette and compatibility notes now describe the steps-only Network Integration and the cost of mismatched `attraction_reach()` distance and radius | none |

Tests: `test-network-integration.R` (accepted: unrestricted, steps, steps-only `pst_radius`, equality with the unrestricted
implementation; rejected: every non-steps field alone and mixed with steps, with junction output, graph still usable);
`test-segment-groups.R` (zero-length guard). Existing tests that fed non-steps radii to Network Integration as native oracles
(`helper-axial-file.R`, `test-axial-inputs.R`, `test-core-network-analyses.R`, `test-sf-betweenness-integration.R`) call the internal
unrestricted implementation, so the pinned native numerical fixtures are compared exactly as before; `test-result-axial.R`
metadata test uses a steps radius.

## 4. Other combinations: recorded, not changed

The following are not restricted here. Each needs a separate, evidence-based decision (section 5).

* **Performance of BFS-based analyses with several limits.** Network Reach with walking + axmeter, and Attraction Reach with default
  `distance = "steps"` plus a walking radius, can be extremely slow or exhaust memory in PST's native search
  ([diagnosis](parity/walking-radius-diagnosis.md)). The official wizards run one radius type per analysis, so these combined limits
  never occur in the plugin. They are rPSTool's combined-limit extension (retained, documented).
* **AR-007.** `attraction_reach()` default `distance = "steps"` follows the native struct default; no change without source-grounded
  justification.
* **AD-008.** `attraction_distance()` ignores a straight radius for network distances (native limit; the existing documentation
  states it). A fixture uses a straight radius of zero, so rejection would change tested behaviour.
* **AR-016.** A decay that does not match the radius/metric silently yields no decay (engine-defined).
* Recursion depth (AI-018, AC-017) and the missing interrupt path are inherited native limitations (documented).

## 5. Native BFS: no change

No native BFS modification was implemented, proposed for implementation or authorised. `src/vendor`, `src/portability` and
`inst/upstream` are unchanged. The earlier prototype patch was removed from the repository; the diagnosis
([parity/walking-radius-diagnosis.md](parity/walking-radius-diagnosis.md)) is kept as a research record only. The upstream motive
for the Network Integration restriction is not documented, and this audit does not claim that the BFS behaviour caused it.

## 6. Verification performed

| check | result |
|---|---|
| `src/vendor`, `src/portability`, `inst/upstream` diff against PR #70 | empty |
| `Rscript tools/verify-vendor.R` | passes (all stages print "Verified") |
| Rd regenerated with roxygen2 7.3.1 and `checkRd` | 30 files, no problems |
| `R CMD build` and `R CMD check --no-manual --ignore-vignettes` (`RPST_FULL_TESTS=false`, `_R_CHECK_FORCE_SUGGESTS_=false`, R 4.3.3, Linux) | Status: 1 WARNING (this sandbox cannot set the `en_US.UTF-8` locale), 2 NOTEs (suggested package `arrow` absent; installed size 16.2 Mb) ; examples and tests OK |
| full testthat run, `RPST_FULL_TESTS=true`, installed build | 372 test blocks, 0 failures, 0 errors, 106 skipped (all because `arrow` cannot be loaded); includes the pinned native Network Integration oracles for every radius field, which call the internal unrestricted implementation |
| new Network Integration radius tests and segment-group zero-length tests | all pass |

Limitations: no `--as-cran` (no CRAN network access), `arrow` absent so GeoParquet paths were not exercised, Linux only (no
macOS or Windows validation), vignettes not rebuilt, GitHub Actions not run. The numerical results of every analysis are unchanged:
no native or vendored code except the rPSTool bridge `src/pst-graph.cpp` (zero-length guard) was modified. The verification was repeated after the Network Integration change (check and full tests above).
