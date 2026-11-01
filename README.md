# rPSTool: Space Syntax and Spatial Network Analysis

rPSTool brings the spatial network analysis engine of the **Place Syntax Tool (PST)** to R. It lets you build street-network graphs
from line geometry and run PST analyses such as network integration, reach, betweenness and angular choice from R scripts, with
results returned as ordinary R data frames.

## What rPSTool does

* Builds a PST graph once, in native memory, from a numeric matrix, an `sf` object or a GeoParquet/FlatGeobuf file, and reuses it
  across analyses.
* Runs the PST analyses listed [below](#supported-analyses) on axial (crossing-aware line) graphs, endpoint-connected segment graphs and
  segment-group graphs, plus network construction, isovist and raster-comparison routines.
* Keeps PST's distinct distance limits (straight, walking, steps, angular, axmeter) separate through `analysis_radius()`.
* Ships a Barnsbury (London) example network and eleven colour palettes for mapping results.

## rPSTool, PST and PST for QGIS

* **PST** is developed by KTH School of Architecture, Chalmers School of Architecture (SMoG) and Spacescape AB. Its analysis engine
  is the C++ library `pstalgo`.
* **PST for QGIS** is the official QGIS plugin built on that engine.
* **rPSTool** binds the engine directly: the pinned upstream release, **PST v3.3.2** (commit
  `63df80a2cf3dd289be95ea3d91667c3490719b75`), is compiled into the package. No separate PST, QGIS, Python or `reticulate`
  installation is needed. rPSTool does not use the plugin and does not reimplement PST's algorithms; numerical results come from the
  engine.
* Where PST for QGIS exposes the same analysis, rPSTool's input selection and defaults were checked against the plugin's code
  (evidence levels S, N and E; see [PST coverage](https://github.com/kimonkrenz/rPSTool/blob/main/docs/pst-coverage.md)). **No comparison
  with a real QGIS run (level Q) has been recorded.** Intentional differences are listed in
  [QGIS differences](https://github.com/kimonkrenz/rPSTool/blob/main/docs/compatibility/qgis-differences.md).

## Acknowledgements and upstream software

rPSTool is an R interface to the **Place Syntax Tool (PST)** and its `pstalgo` C++ analysis engine. PST provides the spatial network analysis algorithms; rPSTool makes these available through R and adds R interfaces, data handling and visualisation.

PST was developed by **KTH School of Architecture, Chalmers School of Architecture (SMoG) and Spacescape AB**. The PST for QGIS plugin metadata for version 3.3.2 credits Alexander Ståhle, Lars Marcus, Daniel Koch, Martin Fitger, Anders Karlström, Tobias Nordström, Ann Legeby, Gianna Stavroulaki, Meta Berghauser Pont and Pablo Miranda. The upstream README names Pablo Miranda Carranza. The original Place Syntax approach was introduced by Ståhle, Marcus and Karlström (2005), *Place Syntax: Geographic Accessibility with Axial Lines in GIS*.

rPSTool bundles the pinned PST v3.3.2 engine under LGPL-3-or-later. We gratefully acknowledge the original PST developers, whose work makes rPSTool possible. rPSTool is not affiliated with or endorsed by the PST authors.

## Installation

rPSTool contains compiled C++ code and needs a **C++17 toolchain** (Rtools on Windows, Xcode command-line tools on macOS, `g++` or
`clang++` on Linux). The first installation compiles the bundled engine from source, which takes a few minutes.

Once the public release repository is available, install from GitHub:

```r
# install.packages("remotes")
remotes::install_github("kimonkrenz/rPSTool")
# or
# install.packages("pak")
pak::pak("kimonkrenz/rPSTool")
```

From a source checkout or tarball: `install.packages("path/to/rPSTool", repos = NULL, type = "source")`.

Everything needed for matrix workflows is installed with the package. Optional packages enable further features:

| Package | Enables |
| --- | --- |
| `sf` | `sf` input and output, the Barnsbury example data, FlatGeobuf files |
| `arrow` (>= 25.0.0) | GeoParquet input, Parquet result files, GeoParquet output |
| `jsonlite` | GeoParquet metadata (with `arrow`) |
| `ggplot2` | the `scale_*_rpst_*()` colour scales |
| `classInt` | class breaks for mapping (rPSTool itself does not classify) |
| `knitr`, `rmarkdown` | building the vignettes |

## Quick start

A graph is built once in native memory and reused across analyses.

```r
library(rPSTool)

# Endpoint-connected segment graph: five collinear segments (x1, y1, x2, y2 per row)
s <- segment_graph(cbind(0:4 * 3, 0, 1:5 * 3, 0))
angular_choice(s, radius = analysis_radius(walking = 8))
angular_integration(s)

# Axial (crossing-aware line) graph: two crossing lines
a <- axial_graph(rbind(c(0, 0, 2, 0), c(1, -1, 1, 1)))
network_integration(a, junctions = TRUE)
network_reach(a)
```

## Example: Barnsbury, London

`load_example_data()` takes no arguments and returns a list of `sf` objects (British National Grid, EPSG:27700): the Barnsbury
axial map (`axial`, 1915 lines), `unlinks` and gate observations (`gates`).

```r
ex <- load_example_data()
g <- axial_graph(ex$axial, unlinks = ex$unlinks)
g

# Network integration within three direction changes (steps)
res <- network_integration(g, radius = analysis_radius(steps = 3))
head(res, 3)

# Results are in input row order: row i of `res` belongs to row i of ex$axial
cols <- colour_map(res$integration, "coral_day", limits = range(res$integration))
plot(sf::st_geometry(ex$axial), col = cols, lwd = 2)
```

`head(res, 3)` prints:

```text
  line_id integration node_count total_depth
1       1    3.249486        180         452
2       2    2.896899        152         397
3       3    3.173414        161         402
```

The Barnsbury axial map is from Hillier and Iida (2005); the movement observations were originally used by Penn, Hillier, Banister and
Xu (1998). The coordinates are **not the original coordinates**: the geometry was georeferenced and spatially transformed by Kimon
Krenz. See [example data](https://github.com/kimonkrenz/rPSTool/blob/main/docs/example-data.md).

## Supported analyses

An analysis accepts only the graph family of its PST routine; families are never converted into one another.

| Graph family | Constructor | Analyses and helpers |
| --- | --- | --- |
| Axial (crossing-aware lines) | `axial_graph()` | `network_integration()`, `network_reach()`, `network_betweenness()`, `attraction_reach()`, `attraction_distance()`, `od_betweenness()`, `axial_line_lengths()`, `axial_crossing_coords()` |
| Endpoint-connected segments | `segment_graph()` | `angular_integration()`, `angular_choice()`, `segment_grouping()` |
| Segment groups | `segment_group_graph()` (from a segment graph and group ids) | `segment_group_integration()` |
| No graph | | `create_junctions()`, `create_segment_map()` (network construction) |
| Isovist context | `isovist_context()` | `isovist()`, `isovist_context_free()` |
| Raster comparison | | `compare_line_results()`, `raster_data()`, `raster_to_polygons()`, `raster_free()` |

`analysis_radius()` builds the radius argument. Normalised scores are computed by PST's exported normalisers. The full function
list is in the [API overview](https://github.com/kimonkrenz/rPSTool/blob/main/docs/api.md).

## Spatial inputs and outputs

* **Matrix**: a numeric matrix with `x1 y1 x2 y2` per line or segment is the canonical input and needs no extra package.
* **`sf`**: `sf` objects are accepted by the graph constructors, and some analyses can return `sf` output. A known geographic CRS is
  rejected; rPSTool never reprojects, snaps, splits or reorders geometry.
* **Files**: `segment_graph()` and `axial_graph()` also accept one GeoParquet path (needs `arrow`, `jsonlite`, `sf`) or one
  FlatGeobuf path (needs `sf`).
* **Result files**: `output_file` writes results to Parquet and `spatial_output_file` writes a new GeoParquet or FlatGeobuf file with
  geometry, attributes and results (`arrow` required). The call returns a `pst_result_file` handle.

Details: [spatial I/O](https://github.com/kimonkrenz/rPSTool/blob/main/docs/spatial-io/README.md).

## Colour palettes

`colour_palettes()` lists eleven palettes in three categories:

* **seven reproduced depthmapX v0.9.1 colour modes**: `axmanesque`, `axmanesque_hue`, `blue_red`, `purple_orange`, `greyscale`,
  `monochrome`, `depthmapx_classic`;
* **two white-background adaptations**: `axmanesque_white`, `depthmapx_classic_white`;
* **two palettes designed for rPSTool**: `coral_night` (dark background) and `coral_day` (light background).

`colour_palette()` returns colours, `colour_map()` maps numeric values to colours (base graphics), and the optional ggplot2 scales are
`scale_colour_rpst_c()`, `scale_fill_rpst_c()`, `scale_colour_rpst_b()` and `scale_fill_rpst_b()`. Class boundaries are supplied by
you. See [palettes](https://github.com/kimonkrenz/rPSTool/blob/main/docs/palettes.md).

## Limitations

* Fast Segment Betweenness (experimental upstream) and Visual Connectivity (an upstream stub) are not exposed, nor are progress and
  log callbacks ([PST coverage](https://github.com/kimonkrenz/rPSTool/blob/main/docs/pst-coverage.md)).
* **Angular Choice** inherits a recursion-depth limitation from PST: very long chains of shortest-path steps can exhaust the process
  stack and terminate the R process (see `?angular_choice` and
  [angular controls](https://github.com/kimonkrenz/rPSTool/blob/main/docs/compatibility/angular-controls.md)).
* Windows result-file support passed the development suite on Windows; final release-candidate validation is outstanding. No
  comparison with real QGIS runs (level Q) has been recorded.
* File input reads two-vertex line geometry in physical file order; polylines are never split, snapped or repaired, and external
  identifiers are not retained.
* PST creates worker threads internally; rPSTool caps them (`RPST_NUM_THREADS`, and a ceiling of two under R's check limit).

Package information: https://kimonkrenz.com/rPSTool/; bug reports: https://github.com/kimonkrenz/rPSTool/issues.

## Documentation and citation

* Vignettes: `vignette("getting-started", package = "rPSTool")` and `vignette("pst-capabilities", package = "rPSTool")`.
* Function reference: `help(package = "rPSTool")`, or the [API overview](https://github.com/kimonkrenz/rPSTool/blob/main/docs/api.md).
* [Documentation index](https://github.com/kimonkrenz/rPSTool/blob/main/docs/README.md) and
  [contributing](https://github.com/kimonkrenz/rPSTool/blob/main/CONTRIBUTING.md).
* Please credit PST when you use rPSTool. Run `citation("rPSTool")` for the package and PST references.

## Licence

rPSTool is licensed under the **GNU Lesser General Public License, version 3 or later** (`LGPL (>= 3)`). It compiles the PST/pstalgo
engine (Copyright 2019 Meta Berghauser Pont, LGPL-3-or-later) and some other third-party components; attribution is recorded in
`inst/COPYRIGHTS`, and the Barnsbury example data is not covered by the package licence. See
[licensing](https://github.com/kimonkrenz/rPSTool/blob/main/docs/licensing.md).
