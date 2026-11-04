# rPSTool: Space Syntax and Spatial Network Analysis in R

Developed by [**Kimon Krenz**](https://kimonkrenz.com), rPSTool brings the spatial network analysis engine of the [**Place Syntax Tool (PST)**](https://smog.chalmers.se/projects/pst-plugin-for-qgis/) to R. The original PST software was developed by KTH School of Architecture, Chalmers School of Architecture (SMoG) and Spacescape AB (see [Acknowledgements](#acknowledgements-and-upstream-software)). rPSTool provides an independent R interface to this engine, building street-network graphs from line geometry and running analyses such as network integration, reach, betweenness and angular choice, with results returned as ordinary data frames. No separate PST, QGIS or Python installation is needed.

## What rPSTool does

* Builds a graph once from a numeric matrix, an `sf` object or a GeoParquet/FlatGeobuf file and reuses it across analyses.
* Runs PST's axial, segment and segment-group analyses (see [Analyses](#analyses)), plus network preparation, isovist and
  raster-comparison routines.
* Keeps PST's distance limits (straight, walking, steps, angular, axmeter) separate through `analysis_radius()`.
* Includes a Barnsbury (London) example network and eleven colour palettes for mapping results.

rPSTool compiles the pinned PST release v3.3.2 into the package and calls its engine directly. It does not reimplement PST's
algorithms: the numerical results come from the engine. It is not the PST plugin for QGIS and is not affiliated with or endorsed by
the PST authors.

## Installation

rPSTool contains compiled C++ code and needs a **C++17 toolchain** (Rtools on Windows, the Xcode command-line tools on macOS,
`g++` or `clang++` on Linux). The first installation compiles the bundled engine and takes a few minutes. rPSTool is not on CRAN
yet; install it from GitHub:

```r
install.packages("pak")
pak::pak("kimonkrenz/rPSTool")
```

`remotes::install_github("kimonkrenz/rPSTool")` works equally well. Optional packages enable further features:

| Package | Enables |
| --- | --- |
| `sf` | `sf` input and output, the Barnsbury example data, FlatGeobuf files |
| `arrow` (>= 25.0.0) | GeoParquet input, Parquet result files, GeoParquet output |
| `jsonlite` | GeoParquet metadata (with `arrow`) |
| `ggplot2` | the `scale_*_rpst_*()` colour scales |
| `classInt` | class breaks for mapping (rPSTool itself does not classify values) |

## Quick start

```r
library(rPSTool)

# Segment graph: five collinear segments (x1, y1, x2, y2 per row)
s <- segment_graph(cbind(0:4 * 3, 0, 1:5 * 3, 0))
angular_choice(s, radius = analysis_radius(walking = 8))

# Axial graph: two crossing lines
a <- axial_graph(rbind(c(0, 0, 2, 0), c(1, -1, 1, 1)))
network_integration(a, junctions = TRUE)
```

With the Barnsbury example network (needs `sf`):

```r
ex <- load_example_data()
g <- axial_graph(ex$axial, unlinks = ex$unlinks)

# Network integration within three direction changes; row i of the result belongs to row i of ex$axial
res <- network_integration(g, radius = analysis_radius(steps = 3))
head(res, 3)
#>   line_id  ni_s_rs3 nc_s_rs3 td_s_rs3
#> 1       1  3.249486      180      452
#> 2       2  2.896899      152      397
#> 3       3  3.173414      161      402

plot(sf::st_geometry(ex$axial),
     col = colour_map(res$ni_s_rs3, "coral_day", limits = range(res$ni_s_rs3)), lwd = 2)
```

The vignette [Getting started with rPSTool: the Barnsbury example](vignettes/getting-started.Rmd) covers two workflows: an in-memory
Angular Choice analysis on `sf` objects with a mapped result, and a file-backed Angular Integration that reads a GeoParquet network
(FlatGeobuf works the same way) and writes a spatial GeoParquet result with `spatial_output_file`. Open it from R with
`vignette("getting-started", package = "rPSTool")` once the package is installed with vignettes.

## Analyses

An analysis accepts only the graph family of its PST routine; families are never converted into one another.

| Graph | Constructor | Analyses and helpers |
| --- | --- | --- |
| Axial (crossing-aware lines) | `axial_graph()` | `network_integration()`, `network_reach()`, `network_betweenness()`, `attraction_reach()`, `attraction_distance()`, `od_betweenness()`, `axial_line_lengths()`, `axial_crossing_coords()` |
| Endpoint-connected segments | `segment_graph()` | `angular_integration()`, `angular_choice()`, `segment_grouping()` |
| Segment groups | `segment_group_graph()` | `segment_group_integration()` |
| No graph | | `create_junctions()`, `create_segment_map()` |
| Isovists | `isovist_context()` | `isovist()`, `isovist_context_free()` |
| Raster comparison | | `compare_line_results()`, `raster_data()`, `raster_to_polygons()`, `raster_free()` |

Every function is documented in its help page (`help(package = "rPSTool")`). Technical reference: [docs/](docs/README.md).

## Spatial inputs and outputs

* **Matrices** with columns `x1 y1 x2 y2` need no extra package.
* **`sf` objects** are accepted by the graph constructors. A known geographic CRS is rejected, and rPSTool never reprojects, snaps,
  splits or reorders geometry.
* **Files:** `segment_graph()` and `axial_graph()` also read one GeoParquet or FlatGeobuf path.
* **Result files:** `spatial_output_file` writes a new GeoParquet or FlatGeobuf file containing source geometry, attributes and results. The graph must have been constructed from a corresponding spatial file.

## Colour palettes

`colour_palettes()` lists eleven palettes: seven historical colour modes (following Axman and Depthmap), two white-background adaptations and
two designed for rPSTool (`coral_night` for dark and `coral_day` for light backgrounds). `colour_map()` maps values to colours in
base graphics, and optional ggplot2 scales are provided. Class boundaries are supplied by you. See `?colour_palettes`.

## Limitations

The main restrictions are summarised below. See [Known limitations](KNOWN_LIMITATIONS.md) for further details.

* **Combined radius limits:** Combining walking, angular or axmeter limits with other limits, without a `steps` restriction, can substantially increase computation time and memory use.
* **Network Integration:** `network_integration()` supports unrestricted analysis or a `steps` radius only.
* **Coordinates:** Input coordinates must use a projected coordinate system where a CRS is specified. PST operates in single precision relative to a centre point.

rPSTool has been validated on Linux, macOS (ARM64) and Windows. Its numerical results have been extensively tested against direct calls to the original PST v3.3.2 engine.

Report bugs and request features at <https://github.com/kimonkrenz/rPSTool/issues>.

## Acknowledgements and upstream software

rPSTool is an R interface to the **Place Syntax Tool (PST)** and its `pstalgo` C++ analysis engine. PST provides the spatial network
analysis algorithms; rPSTool makes them available through R and adds R interfaces, data handling and visualisation. PST was
developed by **KTH School of Architecture, Chalmers School of Architecture (SMoG) and Spacescape AB**; the PST for QGIS plugin
metadata for version 3.3.2 credits Alexander Ståhle, Lars Marcus, Daniel Koch, Martin Fitger, Anders Karlström, Tobias Nordström,
Ann Legeby, Gianna Stavroulaki, Meta Berghauser Pont and Pablo Miranda, and the upstream README names Pablo Miranda Carranza. The
original Place Syntax approach was introduced by Ståhle, Marcus and Karlström (2005), *Place Syntax: Geographic Accessibility with
Axial Lines in GIS*. We gratefully acknowledge the original PST developers, whose work makes rPSTool possible. The Barnsbury example
is derived from Hillier and Iida (2005); the movement gate-count observations are redistributed with the authors' permission, and the
counts were originally reported by Penn, Hillier, Banister and Xu (1998).

Development of rPSTool was supported by OpenAI's ChatGPT and Anthropic's Claude for code optimisation, review, debugging and documentation. 
All contributions were reviewed and validated by the package author, who retains responsibility for the software.

## Citation and licence

If you use rPSTool in your research, please cite **Krenz, K. (2026). rPSTool: Space Syntax and Spatial Network Analysis in R. R package, version 0.1.0**, 
alongside the original **Place Syntax Tool (PST)** software on which its analyses are based. Run `citation("rPSTool")` for the recommended references.

rPSTool is licensed under the **GNU Lesser General Public License, version 3 or later** (`LGPL (>= 3)`). It compiles the PST/pstalgo
engine (Copyright 2019 Meta Berghauser Pont, LGPL-3-or-later) and some other third-party components, whose attribution is recorded in
`inst/COPYRIGHTS`. The LGPL applies to rPSTool's software. The Barnsbury example is derived from Hillier and Iida (2005); the movement gate-count observations are redistributed with the
authors' permission, and the data remain attributable to their authors. The LGPL does not relicense the example data. See [example data](docs/example-data.md) and [licensing](docs/licensing.md).
