// Internal interface of the axial-graph constructor shared by the matrix route (pst-graph.cpp) and the
// file routes (pst-flatgeobuf.cpp, pst-geoparquet.cpp). Not an installed or public header.
#ifndef RPST_AXIAL_BUILD_H
#define RPST_AXIAL_BUILD_H
#ifndef R_NO_REMAP
#error "Define R_NO_REMAP before including R headers in the translation unit."
#endif
#include <Rinternals.h>
#include <cstddef>
#include <vector>
#include <pstalgo/Vec2.h>

namespace rpst {
// Views into R-owned numeric storage that the caller keeps alive (the .Call arguments protect it).
// `real` or `integer` is set (never both); a matrix view is column-major with two columns.
struct AxialView {
    R_xlen_t length = 0;  // matrix rows, or vector length
    const double* real = nullptr;
    const int* integer = nullptr;
};

// Optional axial inputs after R-level staging: unlinks, points and polygon partitions. Holds no owners.
struct AxialAuxiliary {
    AxialView unlinks;        // zero rows when absent
    AxialView points;         // zero rows when absent
    AxialView polygon_sizes;  // empty unless `polygons`
    bool polygons = false;
    float spacing = 0;
};

// Allocate and register the empty axial external pointer (tag and finaliser as for every axial graph).
// May raise an R error, so call it before any C++ owner exists. The caller must PROTECT the result.
SEXP axial_graph_new_pointer();

// Require an exact-tag axial pointer whose address is still NULL. Raises an R error otherwise.
void axial_graph_require_empty(SEXP pointer);

// Validate (storage, shape, finiteness, polygon partition, interval) and view the optional unlinks, points,
// polygon sizes and interval exactly as the matrix constructor does. Raises R errors only, so call it before
// any C++ owner exists.
void stage_axial_auxiliary(SEXP unlinks, SEXP points, SEXP polygon_sizes, SEXP interval, AxialAuxiliary& out);

// Build an axial PST graph into `pointer` from one contiguous array holding two endpoints per line (x1,y1 then
// x2,y2 of each row, in row order) plus the staged auxiliary inputs. Performs the established origin/extent/
// float-representability/polygon-bound checks and the PSTACreateGraph call. Calls no R API other than
// R_SetExternalPtrAddr and reports every failure in `error` (empty on success), never by throwing.
bool axial_graph_build(SEXP pointer, std::vector<double2>& coords, const AxialAuxiliary& aux, char* error,
                       std::size_t error_size);
}  // namespace rpst
#endif
