# Intentional differences from PST for QGIS

rPSTool computes with the pinned PST v3.3.2 engine (commit `63df80a2cf3dd289be95ea3d91667c3490719b75`) and aims to give the
same results as PST for QGIS for equivalent inputs and parameters, except where listed here. No comparison has been run inside QGIS;
the manual procedure is in [`tools/validation/qgis-comparison/`](../../tools/validation/qgis-comparison/README.md). Plugin behaviour
below is taken from the plugin source (file names and functions given; the plugin is not part of this repository).

User-facing examples with explicit settings are in the vignette *PST capabilities and QGIS compatibility*
(`vignettes/pst-capabilities.Rmd`).

## Alignments (rPSTool follows the application)

| Item | Plugin behaviour | rPSTool |
|---|---|---|
| Length-weighted Angular Choice, syntax (NACH) normalisation | passes `total_depth_weights`; unweighted passes `total_depths` | `PSTAAngularChoiceSyntaxNormalize` receives the length-weighted total depth (`tdw_..._wl`) when `weigh_by_length = TRUE`, the total depth (`td_...`) otherwise; identical for scalar, multi-radius, multi-normalisation, Parquet and spatial outputs |
| Attraction Reach decay constant when a nonconstant function is selected | wizard default `C = 1` | `decay_constant = NULL` means 1 for `"power"`, `"curve"`, `"divide"` (and 0 for `"constant"`); explicit values (including 0) unchanged. **The default decay function itself still differs:** the wizard defaults to `pow`, rPSTool to `"constant"`; state `decay =` explicitly to reproduce the wizard. See [attractions](attractions.md). |
| Network Integration radius types | steps only: wizard `RadiusPage(radius_types=[STEPS])` and Python execution code `Radii(steps=...)` (commit `5f3f70f`, present in v3.3.2) | steps only; straight, walking, angular and axmeter limits, alone or mixed with steps, are rejected before the native call |

## Deliberate departures (rPSTool differs and keeps its behaviour)

| Item | Plugin | rPSTool | How to obtain the plugin result in R |
|---|---|---|---|
| Unweighted Angular Choice angle settings | dialog collects `angle_threshold` / `angle_precision` but the unweighted branch does not forward them, so the engine defaults (0, 1) are used; the weighted branch forwards them | explicitly supplied values are honoured in both modes; no compatibility flag | pass `angle_threshold = 0, angle_precision = 1` for the unweighted run |
| Segment-map `extrude` | always `extrude = snap` | default `extrude = 0` (engine and wrapper default) | pass `extrude = <snap value>` |
| Polygon rings | outer ring only | all rings, holes included | supply polygons without holes (or outer rings only); compare results only after the geometry submitted to PST is shown identical |
| Radius combinations | depends on the analysis family. Split into one run per ticked limit type (`Radii.split`): Reach, Network Betweenness, Attraction Betweenness, OD Betweenness, Segment Group Integration, and Attraction Reach (one run per radius type, or per distance mode when decay-weighted). Not split: Angular Integration and Angular Choice (one combined `Radii`); Network Integration offers only a steps radius (its split call is commented out) | where an analysis accepts several radius types, `analysis_radius()` applies the supplied limits together in one run, for Reach, Network Betweenness, Attraction Betweenness, OD Betweenness and Attraction Reach (Segment Group Integration accepts walking and steps only). Network Integration takes a `steps` radius or none. Attraction Distance accepts walking, steps and angular radii with a network distance, ignores a straight radius there, and rejects some combinations ([attractions](attractions.md)). A radius field with several values (for example `walking = c(500, 1000)`) is supported only by Angular Choice and Angular Integration, where it produces one calculation per value rather than one combined run; at most one field may vary ([multi-radius](multi-radius.md)) | for the splitting families call once per limit |
| Reach area | rescaled to km²/ha after the native call | native value in squared coordinate units | multiply by the factor in float32 if the same rounding is wanted |
| Unsupported `axmeter` in angular analyses | selectable; the engine ignores it | rejected | none (the plugin value equals the unrestricted result) |
| Segment Group Graph with zero-length segments | not guarded; native construction does not terminate | rejected before the native call | none (the native call would hang) |
| Strict validation, Attraction Distance filtering, multipart handling, raster defaults | various silent conversions | explicit errors / documented defaults | see the compatibility documents for each family |

The plugin's undefined names (`networkintegrationanalysis.py`, `createjunctionsanalysis.py`) and uninitialised buffers are not reproduced.

## Not exposed by QGIS but exposed by rPSTool

Listed in [PST coverage](../pst-coverage.md).
