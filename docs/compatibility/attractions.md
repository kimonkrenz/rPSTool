# Attraction Reach and Attraction Distance — PST v3.3.2 compatibility

Computed by PST v3.3.2 (commit `63df80a2cf3dd289be95ea3d91667c3490719b75`): `PSTAttractionReach` and `PSTAttractionDistance` through
`attraction_reach()` and `attraction_distance()`. Optional sf/sfc XY POINT/POLYGON attractions are converted to the x/y matrix form
(polygon closure removed, NaN ring separators); see the [adapter contract](../spatial-io/sf-adapters.md) for graph-versus-analysis CRS
checks. PST generates all polygon samples itself.

## Rejected combination

Attraction Distance with point-group origins and a straight-only distance (no radius, or only a straight radius) is rejected with an error
before the native call, with or without indices: PST does not write those outputs. No other mode is restricted, and nothing is aggregated
or recomputed by rPSTool.

| Control | Reach | Distance |
| --- | --- | --- |
| Graph | Axial `HPSTAGraph` | Same |
| Origins | Lines, junctions, retained graph points, retained point groups | Same; documented straight-only group rejection only |
| Primary distance | Straight, walking, steps, angular, axmeter, none (`Undefined` / native zero cost) | Straight-only fast path, walking, steps, angular, weights |
| Independent radius | Shared five native limits | Network path supports walking/steps/angular, with straight accepted but natively ignored; axmeter unsupported by builder. Straight primary with another radius is natively unsupported, rejected explicitly. |
| Attractions | Double world points or automatically closed region edges; ring separators NaN/NaN | Same input; sampling occurs in local floats rather than Reach's world doubles |
| Values / weights | Optional native floats per point/polygon; omitted = native units; nonpositive values skipped | Custom distance requires one finite non-negative native float per line; zero weights valid; point-edge cost per coordinate unit is explicit |
| Decay | Constant, power, curve, divide; finite native float constant (default `NULL`: 0 for constant decay, 1 for power, curve and divide, the PST for QGIS wizard default `C = 1`; an explicit constant, including 0, is passed unchanged) | Native minima only |
| Polygons / groups | Copy/divide distribution; mean/sum/min/max collection | Native minimum aggregation in supported network group modes; never rPSTool aggregation |
| Outputs | Origin-row ID and native score widened to double | Origin-row ID, widened native distance, optional **raw native** integer destination index |

Origins follow native graph order; origin IDs are one-based row numbers. Destination indices keep PST's zero-based values and `-1`
for unreachable, without NA substitution, and do not index the same objects in every mode. Distance scores keep native `-1` for
unreachable. Finite, negative, zero, NaN and Inf scores are widened to double unchanged.

## Behaviour inherited from PST

- With `distance = "axmeter"`, the decay scale of Attraction Reach is the radius plus 1 (PST adds one when the axmeter distance type is
  selected).
- Power and curve decay can write NaN (for example with a zero primary radius); divide can write Inf.
- Finite straight line Reach queries the nearest line distance but applies decay at the radius. Unrestricted straight line Reach uses the
  actual line distance; straight Distance uses line midpoints.
- Reach's group collector reads each worker's point prefix, so unevenly sized groups give PST's result, not a corrected one; groups of
  size zero return -1.
- Attraction Distance with a network distance ignores a supplied straight radius (a straight radius of zero does not filter anything).
- Finite straight Distance updates the destination index for each eligible attraction even when it is not the minimum.
- Straight polygon Distance returns generated sample indices; network non-group Distance maps samples to polygon indices; network group
  Distance returns sample indices.

## Input checks

Inputs must be numeric with matching row counts and finite, float-representable values. Polygon separators must be NaN/NaN (never NA);
counts may be zero but must sum to the number of corner rows. Empty attraction matrices give zero Reach and unreachable Distance. Sample
spacing (`polygon_point_interval`) must be positive and finite, and must advance at each edge length. Negative custom distances are
rejected. Combined walking or axmeter limits, or walking in attraction reach with the default `distance = "steps"`, can be very slow and
exhaust memory; see [KNOWN_LIMITATIONS.md](../../KNOWN_LIMITATIONS.md).
