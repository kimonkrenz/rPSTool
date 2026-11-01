// Internal interface of the segment-graph constructor shared by the matrix route
// (pst-graph.cpp) and the GeoParquet Arrow-stream route (pst-geoparquet.cpp).
// Not an installed or public header.
#ifndef RPST_SEGMENT_BUILD_H
#define RPST_SEGMENT_BUILD_H
#ifndef R_NO_REMAP
#error "Define R_NO_REMAP before including R headers in the translation unit."
#endif
#include <Rinternals.h>
#include <cstddef>
#include <vector>
#include <pstalgo/Vec2.h>

namespace rpst {
// Allocate and register the empty segment-graph external pointer (tag and finaliser
// as for every segment graph). May raise an R error on allocation failure, so call it
// before any C++ owner exists. The caller must PROTECT the result immediately.
SEXP segment_graph_new_pointer();

// Require an exact-tag segment-graph external pointer whose address is still NULL
// (i.e. not yet built). Raises an R error otherwise; call before any C++ owner exists.
void segment_graph_require_empty(SEXP pointer);

// Build a PST segment graph into `pointer` from one contiguous array holding two
// endpoints per segment (x1,y1 then x2,y2 of each row, in row order). Performs the
// established extent/origin, float-representability and endpoint-degree checks and the
// PSTACreateSegmentGraph call. Calls no R API other than R_SetExternalPtrAddr and
// reports every failure in `error` (empty on success), never by throwing.
bool segment_graph_build(SEXP pointer, std::vector<double2>& coords, char* error,
                         std::size_t error_size);
}  // namespace rpst
#endif
