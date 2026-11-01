# Manual QGIS run (evidence level Q) - NOT YET PERFORMED

**No Q-level validation has been performed.** This is the procedure for it. Until a maintainer has run it and archived the exports, the record of
settings and the comparison output, nobody may write "rPSTool matches PST for QGIS".

## 1. Record the environment

Use Windows or macOS (the plugin's bundled engine library exists only for those; the plugin does not run on Linux). Record: QGIS version and the Python/GDAL/GEOS/PROJ versions
(Help > About), OS and architecture, plugin name and version (must read 3.3.2) and how it was installed, `packageVersion("rPSTool")` and the rPSTool git commit
(the build must include the weighted-Choice correction and, for the decay default, the decay-default change if you extend the cases), and this repository's commit.
Save these in `tools/validation/qgis-comparison/qgis-exports/run-info.txt` (create the folder).

## 2. Prepare the data

```sh
Rscript tools/validation/qgis-comparison/make-test-network.R   # run from the repository root; writes tools/validation/qgis-comparison/data/pst-qgis-test.gpkg and stops with an error if its content hashes differ from the tracked manifest
```

Load the layers `axial` and `segment` of `tools/validation/qgis-comparison/data/pst-qgis-test.gpkg` into a new QGIS project (all are EPSG:27700; the id field `seg_id` is not equal to the feature id on purpose).
Use a fresh copy of the GeoPackage for each case, so result columns from one case cannot collide with another's.

## 3. Run the cases

For each case in `cases/cases.json` (field `qgis` gives the settings; `layer` says where the columns appear):

1. Open the analysis from the Vector > PST menu and set exactly the listed options. Do not change anything else.
2. Run it. Write down any warning or error the plugin shows (a failed analysis is a result, not a reason to skip the case).
3. Open the layer's attribute table and check the new column names against the names listed in the case's `rpst` code (for example `ACwlC`). If the plugin names a column differently,
   write the actual name down: the case file is then corrected, the export is not edited.
4. Export the layer: right-click > Export > Save Features As... > CSV, keep **all** fields (including `seg_id`), save as `tools/validation/qgis-comparison/qgis-exports/<case id>.csv`.
   For decimal precision choose the full-precision option if offered; the default comparison tolerance (relative 1e-6) is set for exports with fewer digits.

## 4. Compare

```sh
Rscript tools/validation/qgis-comparison/run-rpst-cases.R
Rscript tools/validation/qgis-comparison/compare-exports.R --qgis-dir tools/validation/qgis-comparison/qgis-exports --rpst-dir tools/validation/qgis-comparison/rpst --cases tools/validation/qgis-comparison/cases/cases.json
```

Exit status 0 only if every case was compared and matched. All paths are relative to the repository root. Never point `--qgis-dir` at the `rpst/` folder: comparing rPSTool with its own output proves nothing, and the comparer reports identical files as a self-comparison and does not count them. Only CSVs exported from your QGIS session are QGIS evidence. A missing QGIS export counts as not run. Analyse every finding; do not suppress it. If a tolerance looser than the default is needed,
say why in the record and give the maximum difference the comparer printed.

## 5. What to archive

`run-info.txt`, the CSV exports, the `rpst/` CSVs, the comparer output, any plugin warnings, and a short note listing every deviation from this procedure. Only then may the result be
described as a Q-level comparison, and only for the cases and settings actually run.
