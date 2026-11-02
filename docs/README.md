# Documentation

| Topic | Document |
| --- | --- |
| Overview, installation, quick start | [README](../README.md) |
| Worked example with the Barnsbury data | [Getting started vignette](../vignettes/getting-started.Rmd) |
| Restrictions that affect use and interpretation | [KNOWN_LIMITATIONS.md](../KNOWN_LIMITATIONS.md) |
| Public API and usage | [api.md](api.md) |
| Architecture, native ownership, threading, pinned upstream source | [architecture.md](architecture.md) |
| PST surface bound by rPSTool, relation to PST for QGIS, exclusions | [pst-coverage.md](pst-coverage.md) |
| Numerical and semantic compatibility with PST, per analysis family | [compatibility/](compatibility/) |
| Design decisions and intentional differences | [design-decisions.md](design-decisions.md) |
| Spatial file input and output, `sf` adapters | [spatial-io/](spatial-io/README.md) |
| Colour palettes and ggplot2 scales | [palettes.md](palettes.md) |
| Bundled Barnsbury example data (Hillier-Iida) | [example-data.md](example-data.md) |
| Build, platforms, compiler diagnostics, CI | [build-and-platforms.md](build-and-platforms.md), [exact warning policy](../tools/ci/README.md) |
| Testing, reproducibility, reference fixtures | [testing.md](testing.md), [reference tools](../tools/reference/README.md), [QGIS comparison procedure](../tools/validation/qgis-comparison/README.md) |
| Licensing and attribution | [licensing.md](licensing.md), [source provenance](../inst/upstream/PROVENANCE.md), [patch records](../inst/upstream/PATCHES.md) |
| Release readiness | [release-checklist.md](release-checklist.md) |
| Contributing | [CONTRIBUTING.md](../CONTRIBUTING.md) |

### Compatibility records

| Family | Record |
| --- | --- |
| Network Integration, Reach, Segment Betweenness, shared radii | [core-network-analyses.md](compatibility/core-network-analyses.md) |
| Angular Integration and Choice controls and normalisers | [angular-controls.md](compatibility/angular-controls.md), [multi-radius.md](compatibility/multi-radius.md) |
| Segment grouping and group integration | [segment-groups.md](compatibility/segment-groups.md) |
| Axial inputs and junction outputs | [axial-inputs-junctions.md](compatibility/axial-inputs-junctions.md) |
| Attraction Reach and Distance | [attractions.md](compatibility/attractions.md) |
| OD Betweenness | [od-betweenness.md](compatibility/od-betweenness.md) |
| Network construction | [network-construction.md](compatibility/network-construction.md) |
| Isovist | [isovist.md](compatibility/isovist.md) |
| Raster comparison | [raster.md](compatibility/raster.md) |
| Floating-point evaluation policy | [floating-point-policy.md](compatibility/floating-point-policy.md) |
| Intentional differences from PST for QGIS | [qgis-differences.md](compatibility/qgis-differences.md) |
