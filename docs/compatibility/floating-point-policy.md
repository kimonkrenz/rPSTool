# Deterministic floating-point evaluation policy

rPSTool compiles pinned PST v3.3.2 (`63df80a2cf3dd289be95ea3d91667c3490719b75`) unchanged. This document records the build-layer policy that removes two known toolchain-dependent evaluation
differences (FMA contraction and unqualified libm overload resolution) from PST's unchanged float
arithmetic. System libm implementations remain outside its control; the one residual found
(`sinf`, below) is documented and given an explicit isovist-only allowance. It changes no PST algorithm, normalisation or vendored byte. Direct-PST fixtures are produced by pinned PST v3.3.2 under this policy.

## Causes of last-bit differences

Three causes separate otherwise identical PST builds on different platforms:

| Cause | Mechanism | Affected |
| --- | --- | --- |
| FMA contraction | Apple clang on arm64 contracts `a*b+c` by default; GCC on x86-64 does not | Raster blur (`Blur.cpp`) |
| Unqualified libm overload resolution | `sin(float)` etc. resolve to the `double` function under libstdc++ (depending on include order and GCC version) and to the `float` overload under libc++/MSVC | Isovist, Network Integration (`log`), `log10` normalisers, segment-group/axial/attraction/angular scores |
| System `sinf` rounding | `sinf` is not correctly rounded at some angles in some libm implementations (observed with glibc 2.39; other libms were not surveyed) | Isovist polygon coordinates only (at most 1 binary32 ULP) |

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
   `abs` and every other `<cmath>` name are deliberately untouched.
3. **Gates.** `tools/fp-policy.R` is the structural check used by `tools/verify-vendor.R` (every
   compile rule, wrapper rules, `PKG_CXXFLAGS` free of the flag, force-include order, object dependency, header contents) and by
   `tools/test-fp-policy.R` (mutation tests plus a compile-time fail-closed probe).

## Reference fixtures

Direct-PST fixtures are serialised in hexadecimal floating point and regenerated with the unchanged generators from the built package
(see [`tools/reference/README.md`](../../tools/reference/README.md)). Fixtures were generated on Ubuntu 24.04 (GCC 13.3, glibc 2.39).

## Isovist-only portability allowance

Even with contraction and overloads controlled, supported system `sinf` implementations can differ
by one binary32 ULP. Isovist tests (`expect_isovist_polygon()` in `tests/testthat/helper-isovist.R`)
therefore allow each *finite* polygon coordinate, on either axis independently, to differ from the
direct reference by at most one binary32 ULP. Values that are not exactly binary32-representable get
no allowance. Everything else stays exactly compared: polygon dimensions and vertex count, vertex
order, area, visibility group structure and indices, the controlled-failure set, lifecycle and
ownership behaviour, and non-finite classes. No other analysis has a floating-point tolerance.

## Platform status

See [KNOWN_LIMITATIONS.md](../../KNOWN_LIMITATIONS.md). On a toolchain whose unqualified `float` calls resolve differently, the `static_assert` convention stops the build.
