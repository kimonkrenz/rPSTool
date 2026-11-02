# Licensing and attribution

This is an assessment of the repository's licensing, **not legal advice and not a claim of formal compliance.** rPSTool-authored
code is licensed **LGPL-3.0-or-later** (`DESCRIPTION`: `License: LGPL (>= 3)`). Copyright in the rPSTool-authored code is held by
Kimon Krenz personally (`Copyright 2026 Kimon Krenz`, confirmed by the maintainer: independently developed, outside
employment duties, without grant funding); `DESCRIPTION` gives `cph` accordingly and `inst/COPYRIGHTS` records it. Upstream PST
attribution is unchanged. Per-file headers for rPSTool-authored sources are deliberately not added; the notices are in
`DESCRIPTION`, `inst/COPYRIGHTS`, `inst/licenses/` and the vendored files' own headers. Part of the rPSTool code was written with
AI coding assistance; this does not change the licence declared above.

## 1. Attribution matrix

| Component | Location | Copyright / holder as stated | Licence | Evidence | Modified? |
| --- | --- | --- | --- | --- | --- |
| rPSTool-authored code | `R/`, `src/*.c`, `src/*.cpp`, `src/*.h`, `src/portability/`, `tests/`, `tools/` | Kimon Krenz (Copyright 2026) | LGPL-3.0-or-later | `DESCRIPTION` | n/a |
| PST / pstalgo v3.3.2 | `src/vendor/pstalgo/` (121 files), `inst/upstream/PST_LICENSE`, `PST_README.txt` | "Copyright 2019 Meta Berghauser Pont" (119 files; the README names her "copyright owner") | LGPL-3-or-later ("either version 3 ... or (at your option) any later version") in all 119 headed files | file headers; `PST_README.txt` | Vendored bytes pristine; build-time copies are modified (`inst/upstream/PATCHES.md`) |
| PST files without a header | `src/vendor/pstalgo/CMakeLists.txt`, `include/pstalgo/utils/Concurrency.h` | none in file | Upstream distribution licence (`LICENSE`, LGPL-3 text with the 2019 notice), assumed to apply | absence of header | no (the CMake file is not used by R) |
| PST build inputs / patches | `inst/upstream/build-inputs/`, `inst/upstream/patches/` | as PST (original headers retained) | LGPL-3-or-later | headers | patches are rPSTool modifications of PST files |
| FlatBuffers 24.12.23 | `src/vendor/flatbuffers/` (15 headers) and `inst/upstream/flatbuffers/include/flatbuffers/base.h` | "Copyright 2014/2017/2021 Google Inc." (15 of 16 headers; `base.h` has none) | Apache-2.0 | headers; `LICENSE`; no upstream NOTICE file | vendored unmodified; the generated build copy of `base.h` has 14 lines removed |
| FlatGeobuf schema and generated headers | `src/vendor/flatgeobuf/` | "Copyright (c) 2018, Björn Harrtell" (in `LICENSE` only; generated headers carry no notice) | BSD-2-Clause | `LICENSE` | unmodified |
| Apache Arrow C data/stream declarations | `src/arrow-c-abi/arrow_c_abi.h` | Licensed to the ASF (header retained); NOTICE "Copyright 2016-2026 The Apache Software Foundation" (per `PROVENANCE.md`) | Apache-2.0 | header lines 1-16 | extraction of declarations, not a byte-identical file (`PROVENANCE.md`) |
| `src/portability/*`, `src/rpst-*.h`, `windows-aligned-allocator.cpp` | `src/` | rPSTool-authored shims; no third-party text found | rPSTool licence | grep for copyright/licence strings | n/a |
| Licence texts shipped | `inst/licenses/LGPL-3.txt`, `GPL-3.txt` (verbatim copies of the Debian common-licenses texts), `flatbuffers-Apache-2.0.txt`, `flatgeobuf-BSD-2-Clause.txt` | FSF / ASF | n/a | byte-compared where a local reference exists | no |
| Suggests (not bundled) | arrow, sf, jsonlite, testthat | not distributed | n/a | `DESCRIPTION` | n/a |

No other bundled third-party source was found (no copyright or licence strings in `src/portability`, `tools/` other than the
licence-verification scripts and CI log fixtures quoting R's own banner). Test fixtures contain no third-party data.

## 2. Combined-work assessment (LGPL-3 §4)

rPSTool compiles all of PST/pstalgo into the package's single shared library, so the installed library is a Combined Work in the
LGPL sense, and rPSTool's own code is itself LGPL-3-or-later.

**Satisfied (assessment)**

* The source package ships the complete corresponding source of the library, including the PST source, the build recipes and the
  patch records; installation is by `R CMD INSTALL`, so recipients can modify PST and rebuild.
* Because rPSTool code is itself LGPL-3+, the combined work carries no terms narrower than the LGPL.
* PST's headers and licence text are retained unchanged in the vendored tree.
* Apache-2.0 components are one-way compatible with (L)GPL-3 and BSD-2-Clause is compatible; the Apache requirements (licence copy,
  retained notices) are met by `inst/licenses/` and the retained headers. Arrow is a `Suggests` only; no Arrow implementation is
  linked or bundled.
* `DESCRIPTION` states the licence by name, with `Copyright: inst/COPYRIGHTS` and `cph` entries for Kimon Krenz, Meta Berghauser
  Pont, Google Inc., Björn Harrtell and The Apache Software Foundation; Martin Fitger is `ctb` (programmer, as named in the PST
  README). The developing organisations (KTH School of Architecture, Chalmers School of Architecture (SMoG), Spacescape AB) and
  the authors named in the PST for QGIS plugin metadata are credited in `inst/CITATION` and `inst/COPYRIGHTS`, while the upstream README acknowledgements remain in `inst/COPYRIGHTS`; no copyright or authorship role
  is asserted for them without evidence. No `LICENSE` file is needed for `LGPL (>= 3)`; `tools:::analyze_license("LGPL (>= 3)")`
  reports it canonical and non-restricting.

**Technical notes**

* GPL §5(a) / Apache §4(b) modification notices: the *generated build copies* of PST files (`#line` plus patches) and of
  FlatBuffers `base.h` carry no in-file change comment. The changes are documented in `inst/upstream/PATCHES.md`, the patch files
  and `src/vendor/flatbuffers/PROVENANCE.md`, and the copies are not themselves distributed (they live in an ignored build
  directory). Adding an in-file comment would require changing the transformation scripts and re-pinning their hashes.
* `inst/upstream/build-inputs/` and the FlatBuffers `base.h` input are installed with the package and keep their original headers.
* The generated worker-cap copies call the rPSTool-supplied `rpst_worker_count()`; the pattern for conveying modified versions
  (LGPL/GPL §2) with such copies has not been reviewed by anyone qualified.

## 3. Resolved maintainer decisions (2026-11-01)

1. **LGPL binary redistribution:** The maintainer considers the existing LGPL-3-or-later combined-work arrangement and source distribution/rebuild documentation sufficient for the intended rPSTool distribution. Official builds pin PST v3.3.2 for reproducibility; the pin does not purport to prohibit recipients from modifying PST and adapting build checks. This closes the internal release-review item, without asserting a formal legal opinion or guaranteeing every third-party redistribution route.
2. **PST authorship and citation:** Existing `Authors@R` copyright-holder roles are retained. The PST software citation and prominent README acknowledgement credit the ten authors named in the PST for QGIS v3.3.2 `metadata.txt` supplied by the maintainer; the upstream README's fuller spelling “Pablo Miranda Carranza” is separately preserved. Ståhle, Marcus and Karlström (2005), *Place Syntax: Geographic Accessibility with Axial Lines in GIS*, is identified as the introduction of the approach, not substituted for software authorship. The software citation is constructed by rPSTool, not an officially endorsed upstream citation.
3. **Headerless PST files:** Upstream `CMakeLists.txt` and `include/pstalgo/utils/Concurrency.h` remain pristine and are covered as part of the upstream PST distribution for rPSTool attribution purposes. No individual headers are inserted.
4. **depthmapX and ColorBrewer:** By explicit maintainer decision, retain LGPL (>= 3), reproduce the historical depthmapX colour values and R mapping behaviour, and prominently attribute depthmapX v0.9.1 and Tasos Varoudis. Matching ColorBrewer values are documented as provenance observations; no separate speculative clearance investigation is required for this release. This is a maintainer decision, not a legal opinion.

## 3A. Further recorded items


   combined library. Providing the Corresponding Source next to the source package on the same channel is the usual route and the
   combined work is itself LGPL, but nobody qualified has confirmed that this satisfies §4(d) (relinking or recombination, and the
   "clear directions" of GPL §6(d)) for every redistribution route, including whether the checksum-locked build scripts impair
   recombining with a modified PST. The obligation falls on whoever distributes a binary; self-built binaries (GitHub releases,
   r-universe, R-hub) make the maintainer a conveyor, so the source tarball should accompany each binary.

   invented). `inst/CITATION` has the rPSTool manual entry and a software reference for PST v3.3.2 constructed from the upstream
   README, dated `n.d.` because the README's 2019 is the copyright year, not a release date; it says it is not an officially
   endorsed upstream citation. The "Misc" entry prints "(n.d.)".

   licence. Confirmation could be sought from upstream out of band by a human; no write to upstream is made. If upstream named a
   different author or licence, that would be a licence stop condition.
1. **Arrow NOTICE:** whether the Arrow NOTICE entries pertain to the extracted declarations (the header's own Apache-2.0 notice is
   retained).
2. **AI-assisted contributions:** the rights position of AI-assisted portions, and the coding tool's terms, have not been legally
   assessed; a qualified review is optional and a maintainer decision.

   reproduce depthmapX v0.9.1 `salalib/pafcolor.cpp` and `displayparams.h` (tag `v0.9.1`; GPL-3.0-or-later, Copyright (C) 2011-2012
   Tasos Varoudis). The depthmapX Classic colour mapping was reimplemented in R to reproduce depthmapX behaviour; it was not
   developed clean-room. **Maintainer decision: the package licence stays LGPL (>= 3) and the attribution to depthmapX and to its tagged
   source is retained** (`inst/COPYRIGHTS`, `docs/palettes.md`). This records a decision, not a legal opinion or a formally verified
   clearance; the matching colour values, equations or behaviour alone are not asserted to establish a licensing conflict, and whether
   a qualified review would reach the same view has not been tested.
3. **Hillier-Iida example data (resolved).** `inst/extdata/hillier_iida/` holds the Barnsbury example data, which are derived from Hillier and Iida
   (2005) and include the axial network, unlinks and observed movement gate counts. The geometries were georeferenced and spatially
   transformed by Kimon Krenz, so the coordinates are not the original, unmodified coordinates. The data are included and redistributed
   with permission from the authors; the original research and data remain attributable to their respective authors. The movement gate
   counts were originally reported by Penn, Hillier, Banister and Xu (1998, Environment and Planning B 25(1), 59-84,
   DOI 10.1068/b250059). The Clerkenwell and Kensington data are not distributed. The LGPL (>= 3) licence applies to rPSTool's
   software, not to these data. See [example data](example-data.md).
4. **CRAN's own review** of bundled third-party code and of the `Copyright:` field is not predictable.

   hex values, in reversed order, as the published 7-class ColorBrewer RdYlBu and PuOr schemes (Brewer et al.; compared with the
   published values as recalled by the reviewer, not with a retrieved copy: colorbrewer.org was unreachable). The depthmapX source
   comments do not name ColorBrewer. ColorBrewer's licence terms (and whether any attribution is required) were not verified; no
   clearance is asserted. Open: obtain and read the current ColorBrewer terms and decide on attribution.

## 4. Citation

`inst/CITATION` has (a) the rPSTool package entry (built from `meta$Title`, `meta$Version`) and (b) a software reference for PST
v3.3.2 (commit `63df80a2cf3dd289be95ea3d91667c3490719b75`, repository SMoG-Chalmers/PST) naming the programmer (Martin Fitger) and
the copyright owner (Meta Berghauser Pont) with the developing organisations as in the PST README. Citation is voluntary and
separate from the legal notices; the maintainer should supply an authoritative PST reference if one exists.
