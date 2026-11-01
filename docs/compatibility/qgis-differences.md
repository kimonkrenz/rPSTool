# Intentional differences from PST for QGIS

Authority model: the pinned C++ engine is authoritative for native computations; the pinned PST for QGIS plugin establishes the
application-level reference behaviour (which arrays, flags and defaults the original application passes); the documented rPSTool public
API defines rPSTool's own defaults and supported options. rPSTool aims to give the plugin's results for equivalent native inputs and
parameters, and departs from it where the departure is deliberate, documented and tested. This document does not claim complete
numerical equivalence with PST for QGIS. Evidence labels: **S** static source, **N** direct native call, **E** plugin logic run
outside QGIS, **Q** real QGIS run. **No Q-level validation has been performed**; the manual procedure is in
[`tools/validation/qgis-comparison/`](../../tools/validation/qgis-comparison/README.md).

User-facing examples with explicit settings are in the vignette *PST capabilities and QGIS compatibility*
(`vignettes/pst-capabilities.Rmd`).

## Alignments (rPSTool follows the application)

| Item | Plugin behaviour (S/E) | rPSTool | Record |
|---|---|---|---|
| Length-weighted Angular Choice, syntax (NACH) normalisation | passes `total_depth_weights` (`angularchoiceanalysis.py` l.128); unweighted passes `total_depths` (l.177) | `PSTAAngularChoiceSyntaxNormalize` receives `total_depth_weight` when `weigh_by_length = TRUE`, `total_depth` otherwise; identical for scalar, multi-radius, multi-normalisation, Parquet and spatial outputs | `test-angular-controls.R` |
| Attraction Reach decay constant when a nonconstant function is selected | wizard default `C = 1` (`attractionreachwiz.py` l.85) | `decay_constant = NULL` means 1 for `"power"`, `"curve"`, `"divide"` (and 0 for `"constant"`); explicit values (including 0) unchanged. **The default decay function itself still differs:** the wizard defaults to `pow` (l.84), rPSTool to `"constant"`; state `decay =` explicitly to reproduce the wizard | `test-attraction-decay-default.R`, [attractions](attractions.md) |
| Network Integration radius types | steps only: wizard `RadiusPage(radius_types=[STEPS])` and Python execution code `Radii(steps=...)` (commit `5f3f70f`, present in v3.3.2) | steps only; straight, walking, angular and axmeter limits, alone or mixed with steps, are rejected before the native call | `test-network-integration.R` |

## Deliberate departures (rPSTool differs and keeps its behaviour)

| Item | Plugin | rPSTool | How to obtain the plugin result in R |
|---|---|---|---|
| Unweighted Angular Choice angle settings | dialog collects `angle_threshold` / `angle_precision` but the unweighted branch does not forward them (l.154-161), so the engine defaults (0, 1) are used; the weighted branch forwards them | explicitly supplied values are honoured in both modes; no compatibility flag | pass `angle_threshold = 0, angle_precision = 1` for the unweighted run |
| Segment-map `extrude` | always `extrude = snap` (`createsegmentmapanalysis.py` l.85) | default `extrude = 0` (engine and wrapper default) | pass `extrude = <snap value>` |
| Polygon rings | outer ring only (`model.py` l.340-368) | all rings, holes included | supply polygons without holes (or outer rings only); compare results only after the geometry submitted to PST is shown identical |
| Radius combinations | depends on the analysis family. Split into one run per ticked limit type (`Radii.split`): Reach, Network Betweenness, Attraction Betweenness, OD Betweenness, Segment Group Integration, and Attraction Reach (one run per radius type, or per distance mode when decay-weighted). Not split: Angular Integration and Angular Choice (one combined `Radii`); Network Integration offers only a steps radius (its split call is commented out) | all supplied limits apply together in one run, for every analysis | for the splitting families call once per limit |
| Reach area | rescaled to km²/ha after the native call | native value in squared coordinate units | multiply by the factor in float32 if the same rounding is wanted |
| Unsupported `axmeter` in angular analyses | selectable; the engine ignores it | rejected | none (the plugin value equals the unrestricted result) |
| Segment Group Graph with zero-length segments | not guarded; native construction does not terminate | rejected before the native call | none (the native call would hang) |
| Strict validation, Attraction Distance filtering, multipart handling, raster defaults | various silent conversions | explicit errors / documented defaults | see the compatibility documents for each family |

Upstream defects are not copied: undefined names (`networkintegrationanalysis.py` l.128, `createjunctionsanalysis.py` l.83),
uninitialised buffers, silently dropped data.

## Not exposed by QGIS but exposed by rPSTool

Listed and classified in [PST coverage](../pst-coverage.md).
