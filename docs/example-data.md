# Example data: Hillier and Iida (2005)

`load_example_data()` returns the bundled Barnsbury (London) spatial data.

The Barnsbury example data are derived from Hillier and Iida (2005) and include the axial network, unlinks and observed movement gate counts. The geometries were georeferenced and spatially transformed by Kimon Krenz. The data are included and redistributed with permission from the authors. The original research and data remain attributable to their respective authors. The movement gate counts were originally reported by Penn et al. (1998).

Sources: Hillier, B. and Iida, S. (2005), *Network and Psychological Effects in Urban Movement*, Spatial Information Theory, LNCS 3693,
pp. 475-490 (DOI 10.1007/11556114_30), with the original data obtained from UCL Discovery
(<https://discovery.ucl.ac.uk/id/eprint/1232/>); and Penn, A., Hillier, B., Banister, D. and Xu, J. (1998), *Configurational modelling of
urban movement networks*, Environment and Planning B: Planning and Design, 25(1), 59-84 (DOI 10.1068/b250059). The Penn et al.
attribution concerns the movement observations only.

**The coordinates are not the original coordinates.** The Barnsbury geometry was subsequently georeferenced to British National Grid
(EPSG:27700) and spatially transformed with a best-fit transformation supplied by Kimon Krenz, so it must not be represented as the
original, unmodified geometry of the source data. Only the Barnsbury network is distributed; the Clerkenwell and Kensington networks of
the source dataset are not part of the package. The schemas are documented in the help pages `?load_example_data` and `?hillier_iida`.

```r
example <- rPSTool::load_example_data()               # list(axial, unlinks, gates); nothing is assigned globally
example$axial                                      # sf LINESTRING, original axial identifiers
g <- rPSTool::axial_graph(example$axial, unlinks = example$unlinks)
```

The list holds `axial`, `unlinks` and `gates` (1915 axial lines, 2 unlinks, 109 gate observations); `load_example_data()` takes no arguments.

## What is stored, and what is not done

The objects are returned exactly as stored in one compressed RDS file installed under `extdata/hillier_iida/` (about 78 kB; no other data file, raw input, GeoPackage, transformation script or archive is installed). The loader only reads them (`sf`
is needed to use the objects) and returns the stored list, which carries the metadata text. Preserved as supplied:
geometry and CRS; the original axial identifiers and the parent-line associations of unlinks and gates; the historical connectivity,
control, integration and local integration values (no recalculation); the movement observations, reported physical attributes and
`NA` values (unavailable vehicle observations are `NA`, not zero); both Barnsbury gate-42 assignments (axial lines 16 and 20); and
the descriptive `metadata` attribute. Nothing is segmented, aggregated, repaired, reordered or recalculated.

## Provenance and checks

The RDS file holds the supplied Barnsbury objects with two authorised changes to its `metadata` attribute: a sentence attributing the
movement observations to Penn et al. (1998), and (when the Clerkenwell and Kensington data were removed before the first release) the
rewording of the text to describe the Barnsbury dataset alone and to state that the geometry was georeferenced and spatially
transformed. `axial`, `unlinks` and `gates` (values, identifiers, geometry, CRS, categories, `NA`s) and the attribute order are unchanged
(checked with `identical()` against the previous file, and by the component fingerprints pinned in `tests/testthat/test-example-data.R`,
which were computed on the files as first supplied). The file was saved with `compress = "xz", version = 2`, so that it carries no R >= 3.5.0
serialization requirement; its checksum and the MD5 of the metadata text are pinned in the same test. The tests load the installed package
and compare the loader output with `readRDS()` of the installed file, and check shapes, CRS, identifiers, `NA` counts, the gate-42 rows,
the area label and that the example map builds an axial graph.

The Penn et al. attribution was verified by the maintainer against the supplied README (`SATC_readme1`, p. 1; the original dataset README) and Hillier and Iida (2005),
Section 5 (p. 483). The bibliographic details of Penn et al. (1998) (authors, title, journal, volume, pages, DOI) were additionally checked against public bibliographic records.

The loader is adapted from the supplied one only as far as repository conventions require: the `directory`, `package` and case-selection
arguments were removed (it always reads the one installed rPSTool file).

## Permission, attribution and licence

* The data are included and redistributed with permission from the authors, and the original research and data remain attributable to
  them.
* The georeferencing and spatial transformation are by Kimon Krenz; the coordinates are not the original coordinates.
* The LGPL (>= 3) licence applies to rPSTool's software. The Barnsbury data are included with the authors' permission and are not
  relicensed under the package licence. See [licensing](licensing.md).
