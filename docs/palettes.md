# Colour palettes

rPSTool offers eleven colour palettes for drawing ordered numerical results. Palettes are an R plotting layer; analysis results are not changed. The API is `colour_palettes()`, `colour_palette()` and `colour_map()` (no ggplot2 needed) and the optional ggplot2 scales `scale_colour_rpst_c()`, `scale_fill_rpst_c()`, `scale_colour_rpst_b()` and `scale_fill_rpst_b()` (help: `?colour_palettes`, `?colour_map`, `?scale_rpst`).

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
| `coral_day` | Coral Day | 3, 5, 9 | selected curve (513-point table) | white / light |
| `axmanesque_white` | Axmanesque White | 3, 5, 9 | linear sRGB through nine anchors | white / light |
| `depthmapx_classic_white` | depthmapX Classic White | 3, 5, 9 | linear sRGB through nine anchors | white / light |

The palettes fall into three groups:

1. **Seven reproduced depthmapX v0.9.1 colour modes** (`axmanesque`, `axmanesque_hue`, `blue_red`, `purple_orange`, `greyscale`, `monochrome`, `depthmapx_classic`): values reproduced unchanged from depthmapX `salalib/pafcolor.cpp` (GPL-3.0-or-later). The Classic band mapping was reimplemented in R.
2. **Two white-background adaptations** (`axmanesque_white`, `depthmapx_classic_white`): rPSTool palettes, not depthmapX modes, that reuse some depthmapX colours (see below). They never replace the native modes.
3. **Two palettes designed for rPSTool** (`coral_night`, `coral_day`).

The four palettes of groups 2 and 3 each have nine anchors at positions `seq(0, 1, length.out = 9)` and nested discrete variants: the 3-colour variant is anchors 1, 5, 9, the 5-colour variant anchors 1, 3, 5, 7, 9, the 9-colour variant all nine. Any other size is an error: colours are never interpolated to fill a requested size.

## Continuous mapping definitions

- **Coral Day**: nearest-index lookup in the 513-point curve, `round(t * 512)` with ties to even, after clipping `t` to `[0, 1]`.
- **Coral Night** (`R/palette-mapping.R`): a monotone piecewise cubic Hermite (PCHIP, Fritsch-Butland derivatives) lightness curve and a hue-ordered rainbow dimmed in linear light at the target luminance, with a local orange correction centred on `t = 0.875`, rounded to even. The 513-point curve and 160 dyadic positions used as test fixtures are in `tests/testthat/fixtures/palette-reference.R`.
- **White adaptations**: piecewise linear interpolation of the encoded 8-bit sRGB channels between neighbouring anchors, `t` clipped, rounded to the nearest integer with ties to even in double arithmetic. No Lab, LCh, HSV or linear-light interpolation is used.
- **Historical modes** follow depthmapX v0.9.1 `salalib/pafcolor.cpp` (arrays at lines 22-77, dispatch in `makeColor` lines 91-148, band lookup lines 154-184, Classic lines 188-250) and `salalib/displayparams.h`. Equal-range modes use band index `int((field - 1e-9) * bands)`: truncation towards zero with an epsilon of `1e-9`, so band `k` covers `((k-1)/bands, k/bands]` (plus `1e-9`) and the first band includes 0. Classic is `makeDepthmapClassic` with `htmlByte`, i.e. `trunc((c + 0.0333) * 15) * 17` per channel (sixteen levels), with landmarks blue at 0, cyan at 0.05, green at 0.10, yellow at 0.55 and red at 1.

### Values reused from depthmapX

- `axmanesque_white` anchors 3 to 9 (`#22CCDD`, `#22CCBB`, `#22DD88`, `#BBCC22`, `#DDCC22`, `#DD8833`, `#DD3333`) are entries of depthmapX's `g_nicecolor` array (the `axmanesque` palette: its entries 3, 4, 5, 7, 8, 9 and 10 in 1-based order); the array's entry `#88DD22` is not used. Anchors 1 and 2 (`#C4F0F4`, `#79DFE8`) are not depthmapX values.
- `depthmapx_classic_white` anchors 3, 5 and 9 (`#00FFFF`, `#00FF00`, `#FF0000`) equal the colours of Classic's cyan, green and red landmarks. Anchors 4, 6 and 8 (`#00FF77`, `#77FF00`, `#FF7700`) are saturated intermediate hues, not the output of the Classic mapping at those positions (at t = 0.375, 0.625 and 0.875 it gives `#99FF00`, `#FFCC00` and `#FF4400`). Anchor 7 (`#DFD33A`) is a darkened yellow replacing Classic's `#FFFF00` for visibility on white; anchors 1 and 2 are pale cyans. Neither is a depthmapX value. The anchors are equally spaced, unlike Classic's landmarks (`0, .05, .10, .55, 1`).
- The Blue-Red and Purple-Orange arrays are reproduced from depthmapX. Their values coincide with the 7-class ColorBrewer RdYlBu (`#D73027 #FC8D59 #FEE090 #FFFFBF #E0F3F8 #91BFDB #4575B4`) and PuOr (`#B35806 #F1A340 #FEE0B6 #F7F7F7 #D8DAEB #998EC3 #542788`) schemes (Brewer et al.), in reversed order. The depthmapX source comments do not mention ColorBrewer. The colours are attributed to ColorBrewer (Cynthia Brewer) as well as to depthmapX ([licensing](licensing.md#4-palettes)).

## Mapping rules (`colour_map()` and the scales)

* **Continuous**: `t = (x - lo) / (hi - lo)` with `limits = c(lo, hi)` (default: range of the finite values); `reverse` maps `t` to `1 - t`. No quantile transform or histogram equalisation is applied. Values outside explicit limits are squished to the ends by default (as depthmapX clamps) or censored with `oob = "censor"`. If all finite values are equal and no limits are given, every value is placed at `t = 0.5` (as in depthmapX).
* **Classes** (`breaks`): the user supplies the boundaries, `k + 1` for `k` classes. Class `i` receives colour `i` of the discrete palette with `k` colours. `right = TRUE` (default): `[b1, b2]`, `(b2, b3]`, ..., `(bk, bk+1]`; `right = FALSE`: `[b1, b2)`, ..., `[bk, bk+1]`; the outer boundaries are always included. Values outside the outer boundaries are censored by default or squished to the end classes with `oob = "squish"`.
* **Missing values**: `NA`, `NaN` and infinite values are missing. They receive the palette's default missing colour, `#7F7F7F` (depthmapX's grey), except `greyscale` and `monochrome`, which hide missing values as depthmapX does (no colour, `NA`; transparent when drawn). `na_colour` / `na.value` override it.
* **Legends**: the binned scales use `ggplot2::binned_scale()` with a palette that returns the exact class colour for each class, so legend steps show the exact discrete colours (a gradient such as `scale_colour_stepsn()` would interpolate).

### Differences from depthmapX

| Behaviour | depthmapX v0.9.1 | rPSTool |
| --- | --- | --- |
| Input range | normalised field with "blue"/"red" display sliders | `limits` (default: data range); the sliders are not exposed (equal to 0 and 1) and Classic's landmarks are fixed at their defaults |
| Missing marker | NaN, or exactly -1.0 | `NA`, `NaN`, `Inf`, `-Inf`; a value of -1 is an ordinary value |
| Infinite values | clamp like out-of-range numbers | missing |
| Monochrome | greyscale colours plus line thickness | greyscale colours only; line thickness is not reproduced |
| Classic at `field == red` with `red = 1` | `htmlByte(NaN)`: an undefined cast to `unsigned char` | 0 (what x86-64 and AArch64 produce), i.e. pure red `#FF0000` |
| Display | alpha 255 (or fully transparent for hidden missing values) | colours are opaque hexadecimal strings or `NA` |

### Classification is left to other packages

rPSTool does not classify: there is no equal-interval, quantile, natural-breaks or other classification function. Pass boundaries calculated elsewhere to `breaks` (nine classes need ten boundaries). `classInt` appears only in optional examples and in `Suggests`.

```r
library(rPSTool)
x <- c(2, 3, 5, 8, 13, 21, 34, 55)
brks <- classInt::classIntervals(x, n = 5, style = "fisher")$brks   # classification by classInt (optional)
colour_map(x, "coral_day", breaks = brks)                             # exact colours 1..5 of the 5-colour Coral Day
```

Ties can make a classifier return fewer distinct boundaries than requested. The number of classes is always `length(breaks) - 1`, and a palette can be used only if it offers that number (3, 5 or 9 for the Coral and white-adaptation palettes, the native band count for depthmapX palettes); otherwise `colour_map()` stops.

## Backgrounds and accessibility

The intended backgrounds are in `colour_palettes()$background` and the help pages. No rPSTool function sets or changes a plot background or theme: `scale_*_rpst_*()` only supplies the colour or fill mapping, so a dark-background palette needs a dark background chosen by the user.

* Coral Night: rainbow-style progression through blue, teal, green, yellow-green, orange and coral, dark to light, for black backgrounds. The rounded continuous curve has small lightness dips; it is neither strictly monotonic nor perceptually uniform.
* Coral Day: light to dark (pale blue to dark coral) for white backgrounds. Its pale-blue endpoint `#DFF0FF` can be faint for thin lines on white.
* White adaptations: reduce the emphasis of dark blues and strong reds on white while keeping recognisable legacy hue sequences; bright cyan and green and uneven lightness remain. Classic White's yellow is darkened for visibility.

No palette has been tested with observers or evaluated for colour-vision deficiency; colour-blind safety, perceptual uniformity and reading accuracy are not claimed. The depthmapX source comments describe its Blue-Red and Purple-Orange arrays as red-green colour-blind safe; rPSTool does not verify that statement.

## Licensing and attribution

rPSTool is licensed LGPL (>= 3). The historical colour modes and the Classic mapping reproduce depthmapX v0.9.1 (`salalib/pafcolor.cpp` and `salalib/displayparams.h`, tag `v0.9.1`; GPL-3.0-or-later, Copyright (C) 2011-2012 Tasos Varoudis), credited in the help pages, here and in `inst/COPYRIGHTS`. The implementation follows the depthmapX source (colour values, equations and branch structure). The depthmapX colour values are retained with this attribution; the package licence is unchanged. This is an attribution statement, not a legal opinion on licence compatibility ([licensing](licensing.md#4-palettes)). The Coral palettes are rPSTool designs; the white adaptations reuse some depthmapX colours as described above, so the same attribution applies to those colours.

## Validation

`tests/testthat/test-palettes.R` checks exact anchors of all palettes, nested sets, curves, ties, band boundaries, Classic landmarks, limits, reversal, NA and out-of-range handling, class boundaries and error handling. `tests/testthat/test-palette-scales.R` checks that built colours equal `colour_map()`, that legend steps equal the exact class colours, and that background and theme are untouched. The scale tests need the suggested package ggplot2 and are skipped when it is not installed.
