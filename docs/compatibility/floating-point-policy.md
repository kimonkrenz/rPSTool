# Deterministic floating-point evaluation policy

rPSTool compiles pinned PST v3.3.2 (`63df80a2cf3dd289be95ea3d91667c3490719b75`) unchanged. This
document records the build-layer policy that removes two known toolchain-dependent evaluation
differences (FMA contraction and unqualified libm overload resolution) from PST's unchanged float
arithmetic. System libm implementations remain outside its control; the one residual found
(`sinf`, below) is documented and given an explicit isovist-only allowance. It changes no PST algorithm, normalisation or
vendored byte. Direct-PST fixtures are produced by **pinned PST v3.3.2 under this adopted
deterministic rPSTool floating-point evaluation policy**; no platform is the normative mathematical
oracle.

## Why

Native macOS testing and a Linux proxy comparison separated three causes of last-bit differences
between otherwise identical PST builds:

| Cause | Mechanism | Affected |
| --- | --- | --- |
| FMA contraction | Apple clang on arm64 contracts `a*b+c` by default; GCC on x86-64 does not | Raster blur (`Blur.cpp`) |
| Unqualified libm overload resolution | `sin(float)` etc. resolve to the `double` function under libstdc++ (depending on include order and GCC version) and to the `float` overload under libc++/MSVC | Isovist, Network Integration (`log`), `log10` normalisers, segment-group/axial/attraction/angular scores |
| System `sinf` rounding | in the investigated comparison, glibc 2.39 `sinf` was not correctly rounded at some angles, while the macOS result matched the correctly rounded sine (other libms were not surveyed) | Isovist polygon coordinates only (22 y-coordinates, exactly 1 binary32 ULP, in the investigated comparison) |

Fixture *parsing* differences are a separate, already-resolved problem (hexadecimal fixtures,
decision log "Exact hexadecimal serialization").

## Policy

1. **`-ffp-contract=off` is authoritative for every translation unit.** `src/Makevars` and
   `src/Makevars.win` define `RPST_FP_FLAGS = -ffp-contract=off`, append `$(RPST_FP_FLAGS)` directly
   after `$(ALL_CXXFLAGS)` in every explicit PST compile rule (so a user `CXXFLAGS` cannot re-enable
   contraction), and in explicit compile rules for the rPSTool C++ wrappers (`PKG_CXXFLAGS` is avoided: `R CMD check` flags `-ffp-contract` there as non-portable). `init.c` is plain C registration code with no floating-point arithmetic.
2. **Eight-name float-overload convention.** `src/rpst-float-overloads.h` is force-included before
   every C++ translation unit (and by `rpst-compat.h` for development tools). It contains exactly
   `using std::sin; cos; sqrt; fmod; log; log10; pow; round;`, each tied in the header comment to
   documented pinned call sites, plus one compile-time `static_assert` per name that an unqualified
   `float` call returns `float`. A toolchain that does not satisfy it (for example an Rtools GCC
   resolving differently) stops the build instead of silently using another evaluation chain.
   `abs` and every other `<cmath>` name are deliberately untouched; the approved `std::abs` raster
   policy and the Relative Percent arithmetic are unchanged.
3. **Gates.** `tools/fp-policy.R` is the structural check used by `tools/verify-vendor.R` (every
   compile rule, wrapper rules, `PKG_CXXFLAGS` free of the flag, force-include order, object dependency, header contents) and by
   `tools/test-fp-policy.R` (mutation tests plus a compile-time fail-closed probe).

## Fixture regeneration

All direct-PST fixtures were regenerated from the freshly built package library with the unchanged
generators (Ubuntu 24.04, GCC 13.3, glibc 2.39). The skeleton of every fixture (structure, integers,
counts, order, controlled failures) is unchanged; only finite float-derived values moved. Compared
with the previously committed values:

| Fixture | Values changed | Largest change |
| --- | --- | --- |
| `raster` | 0 | — |
| `od`, `network-construction` | 0 | — |
| `attractions` | 1 | 1 binary32 ULP |
| `angular-controls` | 112 of 34152 | 2 ULP |
| `core-network` | 27 of 1186 | 1 ULP |
| `reach-betweenness` | 117 of 2150 | 1 ULP |
| `segment-groups` | 64 of 1642 | 4 ULP |
| `axial-inputs` | 21 of 2414 | 6 ULP |
| `isovist` | 191 of 2780 | 4 ULP |

These are the intended consequence of the float-overload convention (the previous Linux fixtures
evaluated several `log`/`sin`/`sqrt` calls through the `double` chain). The earlier Linux/libc++
discrepancy evidence (the `core-network` and `angular-controls` one-ULP `log` normaliser differences and
the segment-group/axial 3–4 ULP Integration differences) is the evidence that motivated this policy.
Existing test tolerances are unchanged.

## Isovist-only portability allowance

Even with contraction and overloads controlled, supported system `sinf` implementations can differ
by one binary32 ULP. Isovist tests (`expect_isovist_polygon()` in `tests/testthat/helper-isovist.R`)
therefore allow each *finite* polygon coordinate, on either axis independently, to differ from the
direct reference by at most one binary32 ULP. Values that are not exactly binary32-representable get
no allowance. Everything else stays exactly compared: polygon dimensions and vertex count, vertex
order, area, visibility group structure and indices, the controlled-failure set, lifecycle and
ownership behaviour, and non-finite classes. Running the suite on Linux with a correctly rounded
`sinf` preloaded passes the allowance tests and fails the old exact comparison, which is the
intended scope of the allowance. No other suite has any new tolerance.

## Status

Verified on Linux (Ubuntu 24.04, GCC 13.3). The same policy was exercised on native macOS
(Apple clang, arm64) before adoption in the form of the three experiments recorded in the decision
log. **Windows/Rtools had not been validated when this was written**: the manual cross-platform workflow could not run
because of runner capacity, and the `static_assert` convention is expected to fail closed there if
the toolchain resolves differently. The full development suite and `R CMD check` have since passed on Windows x86-64
(`4119f2b` on GitHub Actions; later a local run on the tree of `96a1547`, see the [release checklist](../release-checklist.md)).
