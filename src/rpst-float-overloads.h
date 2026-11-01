// rPSTool deterministic floating-point evaluation policy: float-overload convention.
//
// Force-included (-include) before every C++ translation unit of the package,
// both the vendored pstalgo core and the rPSTool wrappers. Upstream bytes are not
// changed.
//
// Pinned PST calls the libm names below unqualified on `float` operands. In
// the global namespace, whether such a call resolves to a float overload or to
// the C `double` function depends on the standard library (libstdc++ with
// <math.h> in scope gives the double chain; libc++ and MSVC give the float
// chain) and on include order and compiler version per translation unit. That
// changes results by float ULPs between platforms. Bringing the std overload
// sets into the global namespace makes every such call resolve to the
// type-preserving overload on every supported toolchain. This header is
// deliberately limited to the eight names below, each tied to documented
// pinned (63df80a2cf3dd289be95ea3d91667c3490719b75) call sites. `abs` and any
// other <cmath> name are intentionally not touched.
//
// The static_asserts make the convention fail closed: a toolchain on which an
// unqualified call with a `float` argument does not return `float` stops the
// build instead of silently using a different evaluation chain.
#ifndef RPST_FLOAT_OVERLOADS_H
#define RPST_FLOAT_OVERLOADS_H
#ifdef __cplusplus
#include <cmath>
#include <type_traits>

// sin, cos: src/analyses/CalculateIsovists.cpp (segment-count scale factor);
//           include/pstalgo/maths.h (Vec2 from angle, T = float).
using std::sin;
using std::cos;
// sqrt: src/graph/AxialGraph.cpp, src/analyses/{Reach,AttractionReach,
//       CalculateIsovists}.cpp, src/Limits.cpp, src/utils/SphereTree.cpp.
using std::sqrt;
// fmod: include/pstalgo/maths.h (angle normalisation, T = float).
using std::fmod;
// log: include/pstalgo/maths.h log(T b, T v) = log(v) / log(b), used by
//      src/graph/AxialGraph.cpp and src/analyses/NetworkIntegration.cpp.
using std::log;
// log10: src/analyses/SegmentBetweenness.cpp and src/analyses/AngularChoice.cpp
//        (normalised scores).
using std::log10;
// pow: src/analyses/AttractionReach.cpp (weight function).
using std::pow;
// round: src/Limits.cpp and src/analyses/CreateBufferPolygons.cpp.
using std::round;

#define RPST_ASSERT_FLOAT_OVERLOAD(expr, name) \
	static_assert(std::is_same<decltype(expr), float>::value, \
		"rPSTool float-overload convention: unqualified " name "(float...) must return float")
RPST_ASSERT_FLOAT_OVERLOAD(sin(1.0f), "sin");
RPST_ASSERT_FLOAT_OVERLOAD(cos(1.0f), "cos");
RPST_ASSERT_FLOAT_OVERLOAD(sqrt(1.0f), "sqrt");
RPST_ASSERT_FLOAT_OVERLOAD(fmod(1.0f, 1.0f), "fmod");
RPST_ASSERT_FLOAT_OVERLOAD(log(1.0f), "log");
RPST_ASSERT_FLOAT_OVERLOAD(log10(1.0f), "log10");
RPST_ASSERT_FLOAT_OVERLOAD(pow(1.0f, 1.0f), "pow");
RPST_ASSERT_FLOAT_OVERLOAD(round(1.0f), "round");
#undef RPST_ASSERT_FLOAT_OVERLOAD
#endif
#endif
