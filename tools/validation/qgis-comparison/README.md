# Manual comparison of rPSTool with PST for QGIS

**Development-only; not part of the installed package.** No QGIS, Python or `reticulate` is, or becomes, a dependency of rPSTool.

**Status: no Q-level validation has been performed.** This folder provides the means for the maintainer to run PST for QGIS (v3.3.2, the plugin
in `pstqgis/` of the pinned PST commit `63df80a2cf3dd289be95ea3d91667c3490719b75`) by hand on a small network, export the result tables, and compare
them with rPSTool. Until such a run has been done and archived, nobody may state that rPSTool matches PST for QGIS in QGIS. Source-level evidence is in [MAPPING.md](MAPPING.md) and
[QGIS differences](../../../docs/compatibility/qgis-differences.md).

## Files

| File | Purpose |
|---|---|
| `GUI-PROCEDURE.md` | The manual protocol: what to record, how to load the data, how to run each case, how to export, how to compare |
| `MAPPING.md` | Corrected map of QGIS analyses/options to the plugin's engine calls, rPSTool calls and output columns; column-name rules |
| `make-test-network.R` | Writes `data/pst-qgis-test.gpkg` deterministically (axial lines, segment map, polylines, points, regions, obstacles; ids deliberately differ from row numbers) |
| `data/pst-qgis-test.manifest.tsv` | Expected layer names, feature counts, id fields and content hashes; `make-test-network.R` compares the generated network with it and fails on any difference |
| `cases/cases.json` | Five small cases: the QGIS settings in words, and the exact R code for the rPSTool side |
| `run-rpst-cases.R` | Runs the rPSTool code of each case and writes `rpst/<case>.csv` (id column + columns named as the plugin names them) |
| `compare-exports.R` | Standalone comparer of a QGIS CSV export with an rPSTool CSV; matches rows by id; reports missing rows/columns, differences, non-finite values |
| `selftest/smoke-test.R` | A few positive and negative checks of the comparer itself |

## Quick start

Convention: **run every command from the repository root.** Generated and exported files live inside this folder
(`tools/validation/qgis-comparison/`): `data/pst-qgis-test.gpkg` (generated, git-ignored), `rpst/` (rPSTool results, generated) and
`qgis-exports/` (your QGIS CSV exports, created by you).

```sh
Rscript tools/validation/qgis-comparison/make-test-network.R          # needs sf; fails if the content hashes differ from the tracked manifest
Rscript tools/validation/qgis-comparison/run-rpst-cases.R             # needs rPSTool (a build that includes the weighted-Choice correction), sf, jsonlite
# ... run the cases in QGIS and export CSVs to tools/validation/qgis-comparison/qgis-exports/<case id>.csv  (see GUI-PROCEDURE.md) ...
Rscript tools/validation/qgis-comparison/compare-exports.R --qgis-dir tools/validation/qgis-comparison/qgis-exports --rpst-dir tools/validation/qgis-comparison/rpst --cases tools/validation/qgis-comparison/cases/cases.json
Rscript tools/validation/qgis-comparison/selftest/smoke-test.R        # checks the comparer itself
```

Maintenance only: `Rscript tools/validation/qgis-comparison/make-test-network.R --update-manifest` rewrites the tracked manifest after an intentional change to the generator.

## Cases and what they probe

| Case | Probes |
|---|---|
| C01 | Angular Choice, weighted and unweighted, four normalisations; `ACwlC` uses `total_depth_weight` in the plugin and, since the weighted-Choice correction, in rPSTool |
| C02 | Weighted Angular Choice with a walking radius and non-default angle threshold/precision (forwarded by the plugin in the weighted branch) |
| C03 | Unweighted Angular Choice with non-default angle settings: the source reading says the plugin does not forward them; the case compares against threshold 0 / precision 1. A mismatch here would mean the source reading is wrong and must be reported |
| C04 | Network Integration, steps radius 2, node count and total depth |
| C05 | Reach, steps radius 2: count, length and area in m² |

Further analyses (betweenness, attraction, OD, segment maps) can be added by writing the QGIS settings and the rPSTool code in the same form; use `MAPPING.md`
for equivalent settings and column names.

## Interpreting results

The comparer prints the tolerance used and the maximum observed differences for every column, so a pass states how close the match was. Float32
results exported from QGIS as text may carry fewer digits than the 9 that identify a float32, which is why the default relative tolerance is 1e-6; use `--rtol 0`
for exact comparison where the export has full precision. A difference is a finding to analyse, not something to suppress. Known sources of difference that are *not*
rPSTool defects: QGIS field types and number formatting, NULL handling, feature-id order (rows are matched by id here), polygon centroid computation.
