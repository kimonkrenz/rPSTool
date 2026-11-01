// Build-only standard declarations missing from the pinned upstream headers.
// Force-included in C++ compilation; upstream bytes and algorithms stay intact.
#ifdef __cplusplus
#include "rpst-float-overloads.h"
unsigned int rpst_worker_count();
#include <algorithm>
#include <cmath>
#include <limits>
#include <cstring>
// libstdc++ 15 no longer pulls <stdint.h> in through <memory>; the pinned CalculateIsovists.h uses uint32_t without
// including it. This header is force-included (-include) in every C++ unit, so the declaration is supplied here, outside the
// pristine vendor tree (docs/build-and-platforms.md, section on GCC 15).
#include <cstdint>
// Pinned CreateSegmentMap.cpp uses the unqualified C99 spelling.
using std::isnan;

// PST's type-name macro returns a string literal as char*, which is invalid
// ISO C++. Its only consumer formats a read-only diagnostic. Override the
// macro at the build boundary rather than changing the vendored header.
#include <pstalgo/pstalgo.h>
#undef PSTA_DECL_STRUCT_NAME
#define PSTA_DECL_STRUCT_NAME(T) inline static const char* TypeName() { return #T; }
#endif
