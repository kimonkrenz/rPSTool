# Colour palettes

rPSTool offers eleven colour palettes for drawing ordered numerical results, as a small plotting layer on top of the analyses. It is
R code only: nothing here calls or changes the native PST engine, and no analysis result is altered. The API is `colour_palettes()`,
`colour_palette()` and `colour_map()` (no ggplot2 needed) and the optional ggplot2 scales `scale_colour_rpst_c()`,
`scale_fill_rpst_c()`, `scale_colour_rpst_b()` and `scale_fill_rpst_b()` (help: `?colour_palettes`, `?colour_map`, `?scale_rpst`).

## Palettes

| Identifier | Name | Discrete colours | Continuous design | Intended background |
| --- | --- | --- | --- | --- |
| `axmanesque` | Equal Ranges (3-Colour) | 10 native bands | band lookup | not stated |
| `axmanesque_hue` | Equal Ranges (3-Colour Hue Only) | 10 native bands | band lookup | not stated |
| `blue_red` | Equal Ranges (Blue-Red) | 7 native bands | band lookup | not stated |
| `purple_orange` | Equal Ranges (Purple-Orange) | 7 native bands | band lookup | not stated |
| `greyscale` | Equal Ranges (Greyscale) | 7 native bands | band lookup | not stated |
| `monochrome` | Equal Ranges (Monochrome) | the greyscale bands | band lookup | not stated |
| `depthmapx_classic` | depthmapX Classic | none | calculated 16-level rainbow | not stated |
| `coral_night` | Coral Night | 3, 5, 9 | selected curve (original generator) | black / dark |
| `coral_day` | Coral Day (H, earlier warmth) | 3, 5, 9 | selected curve (513-point table) | white / light |
| `axmanesque_white` | Axmanesque White (A, pale cyan start) | 3, 5, 9 | linear sRGB through nine anchors | white / light |
| `depthmapx_classic_white` | depthmapX Classic White (F, clearer yellow transition) | 3, 5, 9 | linear sRGB through nine anchors | white / light |

The palettes fall into three groups with different provenance:

1. **Seven reproduced depthmapX v0.9.1 colour modes** (`axmanesque`, `axmanesque_hue`, `blue_red`, `purple_orange`, `greyscale`,
   `monochrome`, `depthmapx_classic`): values reproduced from depthmapX `salalib/pafcolor.cpp` (GPL-3.0-or-later per its header),
   included for historical fidelity and **unchanged**. The Classic band mapping was reimplemented in R.
2. **Two white-background adaptations** (`axmanesque_white`, `depthmapx_classic_white`): additional palettes, not depthmapX modes,
   that reuse some depthmapX colours (see "Which values are reused from depthmapX" below).
3. **Two palettes designed for rPSTool** (`coral_night`, `coral_day`): not taken from depthmapX or any other palette family.

The white adaptations never replace the native modes (native Axmanesque has ten bands, the adaptation nine anchors; native Classic
uses its original numerical mapping, not an evenly spaced nine-stop gradient). The four palettes of groups 2 and 3 each have nine
anchors at positions `seq(0, 1, length.out = 9)` and nested discrete variants: the 3-colour variant is anchors 1, 5, 9, the 5-colour
variant anchors 1, 3, 5, 7, 9, the 9-colour variant all nine. Asking for any other size is an error: colours are never interpolated to fill a requested size.

## Definitions and provenance

The colour values of groups 2 and 3 are the approved design decisions of a "palette handoff" document of 29 October 2026 (SHA-256 of
its Markdown `f08cef4a7adb5d8528bdf83b7e4d89c14146ee3b3be09d063d05583c13d105fb`), transcribed into `R/palette-data.R` without editing
and checked mechanically against that document. That document and the "Python reference" generator named in it are **not part of this
repository**: the repository holds only the transcribed values and the static fixtures derived from the reference
(`tests/testthat/fixtures/palette-reference.R`); this file does not name who designed the palettes beyond recording that they are
rPSTool designs approved by the maintainer. The superseded Coral Day selection (earlier two-anchor refinement), "6 · H hues, mirrored", the
lifted-inverse variants, the earlier tentative Classic selection and the gentle/class-balance rainbow are not included.

* **Coral Day, nine anchors and 513-point curve** are the approved tables. A continuous value uses nearest-index lookup,
  `round(t * 512)` with ties to even, after clipping `t` to `[0, 1]`.
* **Coral Night** continuous values come from the original generator, ported to R (`R/palette-mapping.R`): a monotone piecewise
  cubic Hermite (PCHIP, Fritsch-Butland derivatives) lightness curve, a hue-ordered rainbow dimmed in linear light at the target
  luminance, luminance-aware choice among the eight neighbouring 8-bit corners, then the local orange correction centred on
  `t = 0.875`, rounded to even. Evidence: the port reproduces all 513 table entries exactly, and 200,005 random positions identically to
  the Python reference generator of the handoff (numpy 2.5.3, scipy 1.18.1; a development-time check against code that is not in the
  repository, and not a runtime or test dependency); the
  installed tests use the 513-point curve and 160 dyadic positions of that reference as static fixtures
  (`tests/testthat/fixtures/palette-reference.R`).
* **White adaptations**: piecewise linear interpolation of the encoded 8-bit sRGB channels between neighbouring anchors, clip `t`,
  round to the nearest integer with ties to even. Ties are decided in double arithmetic on the encoded channel values; no Lab, LCh, HSV
  or linear-light interpolation is used.
* **Historical modes** follow depthmapX v0.9.1 `salalib/pafcolor.cpp` (arrays at lines 22-77, dispatch in `makeColor` lines 91-148,
  band lookup lines 154-184, Classic lines 188-250) and `salalib/displayparams.h`, read from the tagged source (evidence S).
  Equal-range modes use band index `int((field - 1e-9) * bands)`: truncation towards zero with an epsilon of `1e-9`, so band `k` covers
  `((k-1)/bands, k/bands]` (plus `1e-9`) and the first band includes 0. Classic is `makeDepthmapClassic` with `htmlByte`, i.e.
  `trunc((c + 0.0333) * 15) * 17` per channel (sixteen levels), landmarks `blue = 0`, `green = 0.1`, `red = 1` (blue at 0, cyan at
  0.05, green at 0.10, yellow at 0.55, red at 1). The depthmapX arrays and algorithm are the only source of the historical definitions. The
  depthmapX Classic colour mapping was reimplemented in R to reproduce depthmapX behaviour (see Licensing below).

### Which values are reused from depthmapX (checked against `R/palette-data.R` and `salalib/pafcolor.cpp` at v0.9.1)

* `axmanesque_white` anchors 3 to 9 (`#22CCDD`, `#22CCBB`, `#22DD88`, `#BBCC22`, `#DDCC22`, `#DD8833`, `#DD3333`) are entries of
  depthmapX's `g_nicecolor` array (the `axmanesque` palette: its entries 3, 4, 5, 7, 8, 9 and 10 in 1-based order); the array's entry
  `#88DD22` is not used. Anchors 1 and 2 (`#C4F0F4`, `#79DFE8`) are not depthmapX values.
* `depthmapx_classic_white` anchors 3, 5 and 9 (`#00FFFF`, `#00FF00`, `#FF0000`) equal the colours of Classic's cyan, green and red
  landmarks. Anchors 4, 6 and 8 (`#00FF77`, `#77FF00`, `#FF7700`) are saturated intermediate hues between landmarks, not the output
  of the Classic mapping at those positions (which at t = 0.375, 0.625 and 0.875 gives `#99FF00`, `#FFCC00` and `#FF4400`).
  Anchor 7 (`#DFD33A`) is a darkened yellow replacing Classic's `#FFFF00` for visibility on white, and anchors 1 and 2 are pale cyans;
  neither is a depthmapX value.
* The anchors are placed at equal spacing, which is not the placement of Classic's landmarks (`0, .05, .10, .55, 1`).
* The Blue-Red and Purple-Orange arrays are reproduced from depthmapX. Their values coincide with the 7-class ColorBrewer
  RdYlBu (`#D73027 #FC8D59 #FEE090 #FFFFBF #E0F3F8 #91BFDB #4575B4`) and PuOr (`#B35806 #F1A340 #FEE0B6 #F7F7F7 #D8DAEB #998EC3
  #542788`) schemes (Brewer et al.), in reversed order. The depthmapX v0.9.1 source comments do not mention ColorBrewer (they call
  the arrays red-green colour-blind safe). ColorBrewer's licence terms were not verified; this is recorded as an open item in
  [licensing](licensing.md), and no clearance is asserted.

No application trace in the sense of the internal engineering rules, section 3 applies: the palettes are an R plotting layer, not an analysis that PST
for QGIS exposes, and no real depthmapX or QGIS run has been recorded (no Q-level claim).

## Mapping rules (`colour_map()` and the scales)

* **Continuous**: `t = (x - lo) / (hi - lo)` with `limits = c(lo, hi)` (default: range of the finite values), `reverse` maps `t` to
  `1 - t`. No quantile transform or histogram equalisation is ever applied. Values outside explicit limits are squished to the ends
  by default (as depthmapX clamps) or censored with `oob = "censor"`. If all finite values are equal and no limits are given, every
  value is placed at `t = 0.5` (depthmapX does the same for an empty range).
* **Classes** (`breaks`): the user supplies the boundaries, `k + 1` for `k` classes. Class `i` receives colour `i` of the discrete
  palette with `k` colours. `right = TRUE` (default): `[b1, b2]`, `(b2, b3]`, ..., `(bk, bk+1]`; `right = FALSE`: `[b1, b2)`, ...,
  `[bk, bk+1]`; the outer boundaries are always included. Values outside the outer boundaries are censored by default (never placed
  silently in a class they do not belong to) or squished to the end classes with `oob = "squish"`.
* **Missing values**: `NA`, `NaN` and infinite values are missing. They receive the palette's default missing colour, `#7F7F7F`
  (depthmapX's grey for colour modes), except `greyscale` and `monochrome`, which hide missing values as depthmapX does (no colour,
  `NA`; transparent when drawn). `na_colour` / `na.value` override it.
* **Legends**: the binned scales use `ggplot2::binned_scale()` with a palette that returns the exact class colour for each class, so
  the legend steps show the exact discrete colours for equal and unequal widths (a gradient such as `scale_colour_stepsn()` would
  interpolate and not guarantee them).

### Differences from depthmapX (not defects of rPSTool)

| Behaviour | depthmapX v0.9.1 | rPSTool |
| --- | --- | --- |
| Input range | normalised field with "blue"/"red" display sliders | `limits` (default: data range); the sliders are not exposed (equal to 0 and 1) and Classic's landmarks are fixed at their defaults |
| Missing marker | NaN, or exactly -1.0 | `NA`, `NaN`, `Inf`, `-Inf`; a value of -1 is an ordinary value |
| Infinite values | clamp like out-of-range numbers | missing |
| Monochrome | greyscale colours plus line thickness | greyscale colours only; line thickness is not reproduced |
| Classic at `field == red` with `red = 1` | `htmlByte(NaN)`: an undefined cast to `unsigned char` | 0 (what x86-64 and AArch64 produce), i.e. pure red `#FF0000` |
| Display | alpha 255 (or fully transparent for hidden missing values) | colours are opaque hexadecimal strings or `NA` |

### Classification is left to other packages

rPSTool does not classify. There is no equal-interval, quantile, natural-breaks or other classification function, no classification
dependency, and no data transformation. Pass boundaries calculated elsewhere to `breaks` (nine classes need ten boundaries).
`classInt` appears only in optional examples and in `Suggests`; it is never required.

```r
library(rPSTool)
x <- c(2, 3, 5, 8, 13, 21, 34, 55)
brks <- classInt::classIntervals(x, n = 5, style = "fisher")$brks   # classification by classInt (optional)
colour_map(x, "coral_day", breaks = brks)                             # exact colours 1..5 of the 5-colour Coral Day
```

Ties can make a classifier return fewer distinct boundaries than requested; the number of classes is always `length(breaks) - 1`,
and a palette is selected only if it offers that number (3, 5 or 9 for the Coral and white-adaptation palettes, the native band count for depthmapX
palettes), otherwise `colour_map()` stops. Choose the number of classes accordingly rather than relying on a silent adjustment.

## Backgrounds and what is (not) claimed

The intended backgrounds are recorded in `colour_palettes()$background` and the help pages. **No rPSTool function sets or changes a plot
background or theme**: `scale_*_rpst_*()` only supplies the colour or fill mapping, so a plot with a dark-background palette needs a
dark background chosen by the user (tests assert that adding a scale leaves the theme untouched).

All stated aims are visual design intentions; none has been demonstrated by an observer study or by an impairment evaluation of the final
selected designs.

* Coral Night: rainbow-style progression through blue, teal, green, yellow-green, orange and coral with an overall dark-to-light
  progression for black backgrounds. Anchors are ordered in lightness but the rounded continuous curve has small lightness dips; it is
  neither strictly monotonic nor perceptually uniform.
* Coral Day: an overall light-to-dark progression for white backgrounds (pale blue to dark coral); H was chosen for visual smoothness.
  Its pale-blue endpoint `#DFF0FF` can be faint for thin lines on white, and no darker replacement was approved.
* White adaptations: reduce the competing emphasis of dark blues and strong reds on white while keeping recognisable legacy hue sequences;
  bright cyan and green and uneven lightness remain. Classic White's yellow was adjusted for visibility.

rPSTool does **not** claim that any palette is colour-blind safe, perceptually uniform, more visually accessible than another, or that it
improves reading accuracy. (The depthmapX source comments describe its Blue-Red and Purple-Orange arrays as red-green colour-blind
safe; rPSTool neither verifies nor repeats that statement.) Coral Night's development used simulated colour-vision comparisons; that
does not make the palette colour-blind safe.

## Licensing and attribution

rPSTool is licensed LGPL (>= 3). The historical colour modes and the Classic mapping reproduce depthmapX v0.9.1 (`salalib/pafcolor.cpp` and
`salalib/displayparams.h`, tagged `v0.9.1`; GPL-3.0-or-later, Copyright (C) 2011-2012 Tasos Varoudis), and depthmapX is credited
as their source in the help pages, here and in `inst/COPYRIGHTS`. The depthmapX Classic colour mapping was reimplemented in R to
reproduce depthmapX behaviour. This was not a clean-room development: the depthmapX source was read and its colour values, equations
and branch structure are followed.

The maintainer has decided to retain the LGPL (>= 3) licence for the package and to retain the attribution to depthmapX. This is a
maintainer decision, not a legal opinion, and it has not been formally verified or cleared by anyone qualified; it is recorded in
[licensing](licensing.md). The Coral palettes are rPSTool designs; the white adaptations are rPSTool adaptations that reuse some depthmapX
colours as described above, so the same attribution applies to those colours.

## Validation

`tests/testthat/test-palettes.R` (exact anchors of all palettes, nested sets, curves, ties, band boundaries, Classic landmarks,
limits/reversal/NA/out-of-range, class boundaries and closure, error handling, no classification dependency) and
`tests/testthat/test-palette-scales.R` (built colours equal `colour_map()`, legend steps equal the exact class colours, background and
theme untouched). The ggplot2 scales were exercised in the development session with ggplot2 3.4.4 only. **Maintainer-supplied validation evidence**
(not run or observed by the development session): rPSTool installed successfully on macOS ARM64 with R 4.6.1 and ggplot2 4.0.3, and
`test-palette-scales.R` and `test-palettes.R` completed there with no reported failures, warnings or skips. Other ggplot2 versions between
3.4.4 and 4.0.3 have not been exercised.
