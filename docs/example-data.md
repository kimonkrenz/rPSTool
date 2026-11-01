# Example data: Hillier and Iida (2005)

`load_example_data()` returns the bundled Barnsbury (London) spatial data distributed with Hillier, B. and Iida, S. (2005), *Network and
Psychological Effects in Urban Movement*, Spatial Information Theory, LNCS 3693, pp. 475-490 (DOI 10.1007/11556114_30), obtained from UCL
Discovery (<https://discovery.ucl.ac.uk/id/eprint/1232/>). The pedestrian and vehicular movement observations were originally used in
Penn, A., Hillier, B., Banister, D. and Xu, J. (1998), *Configurational modelling of urban movement networks*, Environment and Planning
B: Planning and Design, 25(1), 59-84 (DOI 10.1068/b250059), as documented in the README of the original dataset. That attribution
concerns the movement observations only; it does not imply that every axial map, network metric or other attribute originated in the
1998 study.

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
Section 5 (p. 483). That verification was supplied by the maintainer; those sources were not accessible from the development session
(the README and paper were not provided to it and discovery.ucl.ac.uk is blocked there). The bibliographic details of Penn et al. (1998)
(authors, title, journal, volume, pages, DOI) were additionally checked against public bibliographic records.

The loader is adapted from the supplied one only as far as repository conventions require: the `directory`, `package` and case-selection
arguments were removed (it always reads the one installed rPSTool file).

## Licensing and provenance of the data

* No explicit redistribution licence was located in the supplied material.
* The movement observations were originally used in the 1998 study. The attribution does not establish a collection date.
* The age of the material is relevant to any database-right assessment, but expiry and other rights have not been formally
  established.
* The maintainer has elected to retain the attributed dataset in the package.

The dataset is not labelled public domain, Creative Commons or LGPL: the package licence (LGPL >= 3) covers rPSTool code, not this data, and neither
attribution nor open availability on UCL Discovery is taken to establish unrestricted redistribution. See [licensing](licensing.md) (open
item 7).
