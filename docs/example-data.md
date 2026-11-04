# Example data: Hillier and Iida (2005)

`load_example_data()` returns the bundled Barnsbury (London) spatial data. It takes no arguments, needs `sf`, and assigns nothing globally. Schemas: `?load_example_data`, `?hillier_iida`.

```r
example <- rPSTool::load_example_data()   # list(axial, unlinks, gates)
example$axial                              # sf LINESTRING, original axial identifiers
g <- rPSTool::axial_graph(example$axial, unlinks = example$unlinks)
```

The list holds `axial` (1915 axial lines), `unlinks` (2) and `gates` (109 gate observations).

## Attribution

The Barnsbury example is derived from Hillier and Iida (2005). The movement gate-count observations are redistributed with the authors' permission. The axial network and unlinks are adapted from the source material, with geometries georeferenced and spatially transformed by Kimon Krenz. **The coordinates are therefore not the original coordinates.** The original research and data remain attributable to their respective authors. The movement gate counts were originally reported by Penn et al. (1998). The LGPL licence of rPSTool's software does not relicense the example data. Only the Barnsbury network is distributed.

The LGPL (>= 3) licence applies to rPSTool's software, not to these data, which are not relicensed ([licensing](licensing.md)).

Sources:

- Hillier, B. and Iida, S. (2005), *Network and Psychological Effects in Urban Movement*, Spatial Information Theory, LNCS 3693, pp. 475-490 (DOI 10.1007/11556114_30); original data from UCL Discovery (<https://discovery.ucl.ac.uk/id/eprint/1232/>).
- Penn, A., Hillier, B., Banister, D. and Xu, J. (1998), *Configurational modelling of urban movement networks*, Environment and Planning B: Planning and Design, 25(1), 59-84 (DOI 10.1068/b250059). This attribution concerns the movement observations only.

## What is stored

The objects are stored in one xz-compressed RDS file under `extdata/hillier_iida/` (about 78 kB), saved with `version = 2` so that it carries no R >= 3.5.0 serialization requirement. The loader returns them as stored, including the `metadata` attribute, which states the Penn et al. attribution and that the geometry was georeferenced and spatially transformed. Preserved as supplied:

- geometry and CRS;
- original axial identifiers and the parent-line associations of unlinks and gates;
- the historical connectivity, control, integration and local integration values (not recalculated);
- movement observations and reported physical attributes, with `NA` for unavailable vehicle observations (not zero);
- both Barnsbury gate-42 assignments (axial lines 16 and 20).

Nothing is segmented, aggregated, repaired, reordered or recalculated. The file's checksum, the component fingerprints and the metadata text are pinned in `tests/testthat/test-example-data.R`.
