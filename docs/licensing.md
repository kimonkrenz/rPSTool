# Licensing and attribution

rPSTool-authored code is licensed **LGPL-3.0-or-later** (`DESCRIPTION`: `License: LGPL (>= 3)`). Copyright 2026 Kimon Krenz, who developed rPSTool independently, outside university employment duties and without grant funding. `DESCRIPTION` gives `cph` accordingly; notices are in `inst/COPYRIGHTS`, `inst/licenses/` and the vendored files' own headers.

## 1. Attribution matrix

| Component | Location | Copyright / holder as stated | Licence | Modified? |
| --- | --- | --- | --- | --- |
| rPSTool-authored code | `R/`, `src/*.c`, `src/*.cpp`, `src/*.h`, `src/portability/`, `tests/`, `tools/` | Kimon Krenz (Copyright 2026) | LGPL-3.0-or-later | n/a |
| PST / pstalgo v3.3.2 | `src/vendor/pstalgo/` (121 files), `inst/upstream/PST_LICENSE`, `PST_README.txt` | "Copyright 2019 Meta Berghauser Pont" (119 files; the README names her "copyright owner") | LGPL-3-or-later in all 119 headed files | Vendored bytes pristine; build-time copies are modified (`inst/upstream/PATCHES.md`) |
| PST files without a header | `src/vendor/pstalgo/CMakeLists.txt`, `include/pstalgo/utils/Concurrency.h` | none in file | Upstream distribution licence (`PST_LICENSE`) | no (the CMake file is not used by R) |
| PST build inputs / patches | `inst/upstream/build-inputs/`, `inst/upstream/patches/` | as PST (original headers retained) | LGPL-3-or-later | patches are rPSTool modifications of PST files |
| FlatBuffers 24.12.23 | `src/vendor/flatbuffers/` (15 headers), `inst/upstream/flatbuffers/include/flatbuffers/base.h` | "Copyright 2014/2017/2021 Google Inc." (15 of 16 headers; `base.h` has none) | Apache-2.0; no upstream NOTICE file | vendored unmodified; the generated build copy of `base.h` has 14 lines removed |
| FlatGeobuf schema and generated headers | `src/vendor/flatgeobuf/` | "Copyright (c) 2018, Björn Harrtell" (in `LICENSE`) | BSD-2-Clause | unmodified |
| Apache Arrow C data/stream declarations | `src/arrow-c-abi/arrow_c_abi.h` | Licensed to the ASF (header retained); NOTICE "Copyright 2016-2026 The Apache Software Foundation" | Apache-2.0 | extraction of declarations, not a byte-identical file |
| Licence texts | `inst/licenses/` (LGPL-3, GPL-3, Apache-2.0, BSD-2-Clause) | FSF / ASF | n/a | no |
| Suggests (not bundled) | arrow, sf, jsonlite, testthat | not distributed | n/a | n/a |

The Arrow NOTICE concerns Arrow's implementation, none of which is included.

## 2. Combined work (LGPLv3 §4)

rPSTool compiles all of PST/pstalgo into the package's single shared library, so the installed library is a Combined Work in the LGPL sense, and rPSTool's own code is itself LGPL-3-or-later. The source package ships the complete corresponding source, including the PST source, build recipes and patch records; recipients can modify PST and rebuild with `R CMD INSTALL`. Distribution of compiled builds incorporating PST is subject to the applicable requirements of LGPLv3 §4 (Combined Works), including licence notices, corresponding source and provisions for recombination with a modified library. Official builds pin PST v3.3.2 and check its hashes; that is a reproducibility safeguard, not a restriction on users who modify PST (see `inst/COPYRIGHTS`).

`DESCRIPTION` lists `cph` for Kimon Krenz, Meta Berghauser Pont, Google Inc., Björn Harrtell and The Apache Software Foundation, and Martin Fitger as `ctb` (programmer, as named in the PST README). The developing organisations (KTH School of Architecture, Chalmers School of Architecture (SMoG), Spacescape AB) are credited in `inst/CITATION` and `inst/COPYRIGHTS`; no copyright role is asserted for them.

**Modification notices.** The generated build copies of PST files (`#line` plus patches) and of FlatBuffers `base.h` carry no in-file change comment. The changes are documented in `inst/upstream/PATCHES.md`, the patch files and `src/vendor/flatbuffers/PROVENANCE.md`. `inst/upstream/build-inputs/` and the FlatBuffers `base.h` input keep their original headers.

## 3. PST authorship and citation

The PST software citation and README acknowledgement credit the ten authors named in the PST for QGIS v3.3.2 `metadata.txt`; the upstream README's fuller spelling "Pablo Miranda Carranza" is preserved in `inst/COPYRIGHTS`. Ståhle, Marcus and Karlström (2005), *Place Syntax: Geographic Accessibility with Axial Lines in GIS*, introduced the approach. `inst/CITATION` has the rPSTool entry and a PST v3.3.2 reference (commit `63df80a2cf3dd289be95ea3d91667c3490719b75`, repository SMoG-Chalmers/PST), dated `n.d.` because the README's 2019 is the copyright year, not a release date. It is constructed by rPSTool and is not an officially endorsed upstream citation.

## 4. Palettes

The historical palette colour values and the depthmapX Classic mapping reproduce depthmapX v0.9.1 `salalib/pafcolor.cpp` and `displayparams.h` (tag `v0.9.1`; GPL-3.0-or-later, Copyright (C) 2011-2012 Tasos Varoudis), reimplemented in R and attributed in `inst/COPYRIGHTS` and [palettes](palettes.md). The reuse of depthmapX values and behaviour in an LGPL (>= 3) package has not been legally reviewed. The depthmapX Blue-Red and Purple-Orange values coincide with the 7-class ColorBrewer RdYlBu and PuOr schemes (reversed order); ColorBrewer's licence terms were not verified.

## 5. Example data

The Barnsbury example data (`inst/extdata/hillier_iida/`) are derived from Hillier and Iida (2005) and include the axial network, unlinks and observed movement gate counts. The geometries were georeferenced and spatially transformed by Kimon Krenz, so the coordinates are not the original coordinates. The data are included and redistributed with permission from the authors; the original research and data remain attributable to them. The movement gate counts were originally reported by Penn, Hillier, Banister and Xu (1998, Environment and Planning B 25(1), 59-84, DOI 10.1068/b250059). The Clerkenwell and Kensington data are not distributed. The LGPL (>= 3) licence applies to rPSTool's software, not to these data. See [example data](example-data.md).
