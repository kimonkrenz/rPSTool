// rPSTool owns only handles returned by the pinned exported PST C API.
#define R_NO_REMAP
#include <atomic>
#include <new>
#include <Rinternals.h>
#include <pstalgo/analyses/CreateGraph.h>
#include <pstalgo/analyses/NetworkIntegration.h>
#include <pstalgo/analyses/AngularIntegration.h>
#include <pstalgo/analyses/Reach.h>
#include <pstalgo/analyses/AttractionReach.h>
#include <pstalgo/analyses/AttractionDistance.h>
#include <pstalgo/analyses/ODBetweenness.h>
#include <pstalgo/analyses/SegmentBetweenness.h>
#include <pstalgo/analyses/AngularChoice.h>
#include <pstalgo/analyses/SegmentGrouping.h>
#include <pstalgo/analyses/SegmentGroupIntegration.h>
#include <pstalgo/graph/AxialGraph.h>
#include "pst-segment-build.h"
#include "pst-axial-build.h"
#include "pst-result-stream.h"
#include "pst-progress.h"
#include "pst-arrow-owner.h"
// AxialGraph's legacy maths header defines REAL as float. Restore R's REAL()
// accessor after the pinned declarations have been parsed.
#undef REAL
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <exception>
#include <limits>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

// The pinned header declares this descriptor constructor but the complete
// core supplies no definition. Supply only version/default field values here.
SPSTAGraphInfo::SPSTAGraphInfo()
    : m_Version(VERSION), m_LineCount(0), m_CrossingCount(0),
      m_PointCount(0), m_PointGroupCount(0)
{}

namespace {
// Private counters make finalisation observable without keeping pointers alive.
double created = 0;
double freed = 0;

SEXP graph_tag() { return Rf_install("rPST::HPSTAGraph/v1"); }

void graph_finalizer(SEXP pointer)
{
    auto handle = R_ExternalPtrAddr(pointer);
    if (!handle) return;
    R_ClearExternalPtr(pointer);
    PSTAFreeGraph(handle);
    ++freed;
}

HPSTAGraph graph_handle(SEXP pointer, bool require_live = true)
{
    if (TYPEOF(pointer) != EXTPTRSXP || R_ExternalPtrTag(pointer) != graph_tag())
        Rf_error("Invalid pst_graph native pointer; construct it with axial_graph().");
    auto handle = R_ExternalPtrAddr(pointer);
    if (require_live && !handle)
        Rf_error("The pst_graph native pointer is no longer live (released or deserialised); reconstruct it with axial_graph().");
    return handle;
}

struct CoordinateData
{
    const double* real;
    const int* integer;
    double at(R_xlen_t i) const
    {
        if (real) return real[i];
        const int value = integer[i];
        return value == NA_INTEGER ? NA_REAL : static_cast<double>(value);
    }
};

// No owning C++ temporaries or R allocations during optional-input validation.
struct AnalysisPoints {
    R_xlen_t count = 0;
    CoordinateData data{nullptr, nullptr};
};
AnalysisPoints analysis_points(SEXP x, HPSTAGraph handle, const char* name)
{
    if (x == R_NilValue) return {};
    if (!Rf_isMatrix(x) || (TYPEOF(x) != REALSXP && TYPEOF(x) != INTSXP))
        Rf_error("%s must be a numeric matrix with exactly two columns: x, y.", name);
    SEXP dims = Rf_getAttrib(x, R_DimSymbol);
    const int n = INTEGER(dims)[0];
    if (n <= 0 || INTEGER(dims)[1] != 2)
        Rf_error("%s must have at least one row and exactly two columns: x, y.", name);
    // R matrix rows and Reach's internal origin index are signed int. Both
    // descriptors use unsigned counts; the signed bound also fits those fields.
    if (static_cast<unsigned long long>(n) > std::numeric_limits<unsigned int>::max())
        Rf_error("Too many %s for the PST descriptor.", name);
    AnalysisPoints points{n, {TYPEOF(x) == REALSXP ? REAL(x) : nullptr,
                             TYPEOF(x) == INTSXP ? INTEGER(x) : nullptr}};
    // graph_handle has already checked exact axial tag and liveness. Inspect
    // only native geometry/origin for representation checks, never assignments.
    const auto& graph = *static_cast<const CAxialGraph*>(handle);
    float2 lower = graph.getLine(0).p1, upper = lower;
    const auto extend = [&](const float2& p) {
        lower.x = std::min(lower.x, p.x); lower.y = std::min(lower.y, p.y);
        upper.x = std::max(upper.x, p.x); upper.y = std::max(upper.y, p.y);
    };
    for (int i = 0; i < graph.getLineCount(); ++i) {
        extend(graph.getLine(i).p1); extend(graph.getLine(i).p2);
    }
    const auto graph_lower = lower, graph_upper = upper;
    for (R_xlen_t i = 0; i < points.count; ++i) {
        const double2 p(points.data.at(i), points.data.at(i + points.count));
        if (!std::isfinite(p.x) || !std::isfinite(p.y))
            Rf_error("%s coordinates must all be finite (no NA, NaN or Inf).", name);
        const auto local = p - graph.getWorldOrigin();
        if (!std::isfinite(local.x) || !std::isfinite(local.y) ||
            std::abs(local.x) > std::numeric_limits<float>::max() ||
            std::abs(local.y) > std::numeric_limits<float>::max())
            Rf_error("%s coordinates overflow PST's native local-coordinate representation.", name);
        // Origins/attractions are independent. PST compares each with network
        // geometry, not with other supplied points; validate that extent only.
        lower = graph_lower; upper = graph_upper;
        extend(graph.worldToLocal(p));
        if (!std::isfinite((upper - lower).getLengthSqr()))
            Rf_error("%s coordinate extent overflows PST's native distance representation.", name);
    }
    return points;
}
CoordinateData analysis_weights(SEXP x, R_xlen_t count, const char* name = "weights",
                                const char* item = "graph line or supplied attraction point")
{
    if (x == R_NilValue) return {nullptr, nullptr};
    if (TYPEOF(x) != REALSXP && TYPEOF(x) != INTSXP)
        Rf_error("%s must have numeric storage (integer or double).", name);
    if (XLENGTH(x) != count)
        Rf_error("%s must have exactly one value per %s.", name, item);
    const CoordinateData data{TYPEOF(x) == REALSXP ? REAL(x) : nullptr,
                              TYPEOF(x) == INTSXP ? INTEGER(x) : nullptr};
    for (R_xlen_t i = 0; i < count; ++i) {
        const double v = data.at(i);
        if (!std::isfinite(v)) Rf_error("%s must all be finite (no NA, NaN or Inf).", name);
        if (std::abs(v) > std::numeric_limits<float>::max() ||
            (v != 0 && static_cast<float>(v) == 0))
            Rf_error("%s overflow or underflow PST's native float representation.", name);
    }
    return data;
}
std::vector<double2> copy_analysis_points(const AnalysisPoints& points)
{
    std::vector<double2> coords(points.count);
    for (R_xlen_t i = 0; i < points.count; ++i)
        coords[i] = double2(points.data.at(i), points.data.at(i + points.count));
    return coords;
}
// Accept legacy native step arguments as well as the shared five-field list.
// No C++ allocation is live during validation (Rf_error is a non-local jump).
SPSTARadii analysis_radii(SEXP x, bool angular_engine = false)
{
    SPSTARadii radii;
    if (x == R_NilValue) return radii;
    const bool shared = TYPEOF(x) == VECSXP && Rf_inherits(x, "pst_radius");
    const char* fields[] = {"straight", "walking", "steps", "angular", "axmeter"};
    if (shared) {
        SEXP names = Rf_getAttrib(x, R_NamesSymbol);
        if (XLENGTH(x) != 5 || TYPEOF(names) != STRSXP || XLENGTH(names) != 5)
            Rf_error("radius must be created by analysis_radius().");
        for (int i = 0; i < 5; ++i)
            if (STRING_ELT(names, i) == NA_STRING ||
                std::strcmp(CHAR(STRING_ELT(names, i)), fields[i]) != 0)
                Rf_error("radius must be created by analysis_radius().");
    }
    for (int i = 0; i < 5; ++i) {
        if (!shared && i != 2) continue;
        SEXP field = shared ? VECTOR_ELT(x, i) : x;
        if (field == R_NilValue) continue;
        const char* step_error = "steps must be NULL or one non-negative whole number no greater than 2147483647.";
        if ((TYPEOF(field) != REALSXP && TYPEOF(field) != INTSXP) || XLENGTH(field) != 1) {
            if (i == 2) Rf_error("%s", step_error);
            Rf_error("radius %s must be NULL or one finite non-negative native float value.", fields[i]);
        }
        double v = TYPEOF(field) == REALSXP ? REAL(field)[0] :
            (INTEGER(field)[0] == NA_INTEGER ? NA_REAL : INTEGER(field)[0]);
        if (i == 2) {
            if (!std::isfinite(v) || v < 0 || v != std::floor(v) || v > std::numeric_limits<int>::max())
                Rf_error("%s", step_error);
            radii.SetSteps(static_cast<unsigned int>(v));
            continue;
        }
        if (!std::isfinite(v) || v < 0 || v > std::numeric_limits<float>::max())
            Rf_error("radius %s must be NULL or one finite non-negative native float value.", fields[i]);
        const float f = static_cast<float>(v);
        if ((v > 0 && f == 0) || (i == 0 && !std::isfinite(f * f)))
            Rf_error("radius %s overflows or underflows PST's native representation.", fields[i]);
        if (angular_engine && i == 4)
            Rf_error("axmeter radius is unsupported by the pinned angular engine.");
        switch (i) {
        case 0: radii.SetStraight(f); break;
        case 1: radii.SetWalking(f); break;
        case 3: radii.SetAngular(f); break;
        case 4: radii.SetAxmeter(f); break;
        }
    }
    return radii;
}
SPSTARadii shared_radii(SEXP radius, bool angular_engine = false)
{
    if (TYPEOF(radius) != VECSXP || !Rf_inherits(radius, "pst_radius"))
        Rf_error("radius must be created by analysis_radius().");
    return analysis_radii(radius, angular_engine);
}

int named_mode(SEXP x, const char* const* names, int count, const char* parameter)
{
    if (TYPEOF(x) == STRSXP && XLENGTH(x) == 1 && STRING_ELT(x, 0) != NA_STRING) {
        for (int i = 0; i < count; ++i)
            if (std::strcmp(CHAR(STRING_ELT(x, 0)), names[i]) == 0) return i;
    }
    Rf_error("Unsupported %s; use an exact supported name.", parameter);
    return 0;
}

}

namespace {
struct InputMatrix {
    R_xlen_t rows = 0;
    CoordinateData data{nullptr, nullptr};
    double2 point(R_xlen_t i) const { return double2(data.at(i), data.at(i + rows)); }
};
InputMatrix graph_input_matrix(SEXP x, int columns, const char* name, bool optional = false,
                               bool separators = false)
{
    if (optional && x == R_NilValue) return {};
    if (!Rf_isMatrix(x) || (TYPEOF(x) != REALSXP && TYPEOF(x) != INTSXP))
        Rf_error("%s must be a numeric matrix with %d columns.", name, columns);
    SEXP dims = Rf_getAttrib(x, R_DimSymbol);
    const int n = INTEGER(dims)[0];
    if (!optional && columns == 4 && (INTEGER(dims)[1] != 4 || n <= 0))
        Rf_error("Coordinates must have at least one row and exactly four columns: x1, y1, x2, y2.");
    if (INTEGER(dims)[1] != columns || (!optional && n <= 0))
        Rf_error("%s must have %srows and exactly %d columns.", name,
                 optional ? "zero or more " : "at least one ", columns);
    InputMatrix out{n, {TYPEOF(x) == REALSXP ? REAL(x) : nullptr,
                       TYPEOF(x) == INTSXP ? INTEGER(x) : nullptr}};
    for (R_xlen_t i = 0; i < n; ++i) {
        if (separators) {
            const auto pt = out.point(i);
            if (std::isnan(pt.x) && std::isnan(pt.y) && !R_IsNA(pt.x) && !R_IsNA(pt.y)) continue;
        }
        for (int j = 0; j < columns; ++j)
            if (!std::isfinite(out.data.at(i + n * static_cast<R_xlen_t>(j))))
                Rf_error("%s coordinates must all be finite (polygon ring separators may be NaN/NaN, never NA).", name);
    }
    return out;
}
// Polygon-partition and sampling-interval staging shared by the matrix and file routes. Raises R errors only,
// before any C++ owner exists; the outputs are views into protected R storage.
void stage_polygons(SEXP polygon_sizes, SEXP interval, R_xlen_t point_rows, CoordinateData& sizes,
                    R_xlen_t& polygon_count, float& spacing)
{
    const bool polygons = polygon_sizes != R_NilValue;
    if (polygons) {
        if (Rf_getAttrib(polygon_sizes, R_DimSymbol) != R_NilValue ||
            (TYPEOF(polygon_sizes) != INTSXP && TYPEOF(polygon_sizes) != REALSXP) ||
            XLENGTH(polygon_sizes) < 1 || XLENGTH(polygon_sizes) > std::numeric_limits<int>::max())
            Rf_error("points_per_polygon must be a non-empty numeric vector of non-negative whole counts.");
        polygon_count = XLENGTH(polygon_sizes);
        sizes = {TYPEOF(polygon_sizes) == REALSXP ? REAL(polygon_sizes) : nullptr,
                 TYPEOF(polygon_sizes) == INTSXP ? INTEGER(polygon_sizes) : nullptr};
        double sum = 0;
        for (R_xlen_t i = 0; i < polygon_count; ++i) {
            const double v = sizes.at(i);
            if (!std::isfinite(v) || v < 0 || v != std::floor(v) || v > point_rows)
                Rf_error("points_per_polygon must contain non-negative whole counts within the points row count.");
            sum += v;
        }
        if (sum != point_rows) Rf_error("points_per_polygon must sum to the number of points rows.");
        if ((TYPEOF(interval) != REALSXP && TYPEOF(interval) != INTSXP) || XLENGTH(interval) != 1)
            Rf_error("polygon_point_interval must be one positive finite native float value.");
        const double value = TYPEOF(interval) == REALSXP ? REAL(interval)[0] : INTEGER(interval)[0];
        if (!std::isfinite(value) || value <= 0 || value > std::numeric_limits<float>::max() ||
            static_cast<float>(value) == 0)
            Rf_error("polygon_point_interval must be one positive finite native float value without overflow/underflow.");
        spacing = static_cast<float>(value);
    } else if (interval != R_NilValue) {
        Rf_error("polygon_point_interval requires points_per_polygon.");
    }
}

// Shared axial construction core (matrix, indexed-matrix and file routes). Everything from the world-origin
// calculation to PSTACreateGraph is unchanged from the original in-line implementation; the inputs are already
// staged R views and one contiguous coordinate array. Calls no R API other than R_SetExternalPtrAddr and never
// throws: every failure is reported in `error` (empty on success).
bool axial_build_core(SEXP pointer, std::vector<double2>& coords, bool indexed, const InputMatrix& index_data,
                      R_xlen_t n, const InputMatrix& unlink_data, const InputMatrix& point_data,
                      bool polygons, const CoordinateData& sizes, R_xlen_t polygon_count, float spacing,
                      char* error, std::size_t error_size)
{
    error[0] = '\0';
    try {
        double2 lo = coords[0], hi = lo;
        const auto extend = [](const double2& p, double2& lower, double2& upper) {
            lower.x = std::min(lower.x, p.x); lower.y = std::min(lower.y, p.y);
            upper.x = std::max(upper.x, p.x); upper.y = std::max(upper.y, p.y);
        };
        for (const auto& pt : coords) extend(pt, lo, hi);
        // Exact pinned origin includes unused indexed coordinates.
        const double2 origin((lo.x+hi.x)/2, (lo.y+hi.y)/2);
        const auto local_ok = [&](const double2& pt) {
            const auto v = pt-origin;
            return std::isfinite(v.x) && std::isfinite(v.y) &&
                std::abs(v.x) <= std::numeric_limits<float>::max() &&
                std::abs(v.y) <= std::numeric_limits<float>::max();
        };
        bool representable = std::isfinite(origin.x) && std::isfinite(origin.y);
        if (indexed) {
            lo = hi = coords[static_cast<size_t>(index_data.data.at(0)-1)];
            for (R_xlen_t i = 0; i < n*2; ++i) {
                const auto& pt = coords[static_cast<size_t>(index_data.data.at(i)-1)];
                representable = representable && local_ok(pt);
                extend(pt, lo, hi);
            }
        } else for (const auto& pt : coords) representable = representable && local_ok(pt);
        const auto extent_ok = [&](const double2& lower, const double2& upper) {
            const auto low = static_cast<float2>(lower-origin);
            const auto high = static_cast<float2>(upper-origin);
            // SphereTree and nearest-line queries add bbox endpoints in float.
            return std::isfinite((high-low).getLengthSqr()) &&
                std::isfinite(low.x+high.x) && std::isfinite(low.y+high.y);
        };
        std::vector<double2> native_unlinks(static_cast<size_t>(unlink_data.rows));
        for (R_xlen_t i = 0; i < unlink_data.rows; ++i) {
            const auto pt = unlink_data.point(i);
            native_unlinks[i] = pt;
            auto lower = lo, upper = hi;
            extend(pt, lower, upper);
            representable = representable && local_ok(pt) && extent_ok(lower, upper);
        }
        std::vector<double2> native_points(static_cast<size_t>(point_data.rows));
        for (R_xlen_t i = 0; i < point_data.rows; ++i) {
            const auto pt = point_data.point(i);
            native_points[i] = pt;
            if (polygons && std::isnan(pt.x)) continue;
            representable = representable && local_ok(pt);
            extend(pt, lo, hi); // Points enter PST's network bounding box together.
        }
        representable = representable && extent_ok(lo, hi);
        // Safe upper bound only, not a replacement point-generation algorithm.
        // PST counts/generated-point indices and connectPointsToNetwork are int.
        // Bound all closed-ring perimeters/spacing plus vertices and groups;
        // this also prevents non-progressing double additions in PST's loop.
        double point_bound = 2.0*point_data.rows + 2.0*polygon_count;
        R_xlen_t offset = 0;
        std::vector<unsigned int> native_sizes(static_cast<size_t>(polygon_count));
        for (R_xlen_t g = 0; g < polygon_count; ++g) {
            const auto size = static_cast<R_xlen_t>(sizes.at(g));
            native_sizes[g] = static_cast<unsigned int>(size);
            R_xlen_t first = offset;
            for (R_xlen_t i = offset; i <= offset+size; ++i) {
                if (i != offset+size && !std::isnan(native_points[i].x)) continue;
                if (i > first) {
                    for (R_xlen_t j = first; j < i; ++j) {
                        const auto next = j+1 < i ? j+1 : first;
                        point_bound += (native_points[next]-native_points[j]).getLength()/spacing;
                    }
                }
                first = i+1;
            }
            offset += size;
        }
        if (!representable) {
            std::snprintf(error, error_size, "Coordinate extent overflows PST's native local-coordinate/distance representation.");
        } else if (polygons && (!std::isfinite(point_bound) || point_bound > std::numeric_limits<int>::max())) {
            std::snprintf(error, error_size, "Polygon sampling exceeds PST's native signed point-count bounds.");
        } else {
            std::vector<unsigned int> native_indices(indexed ? static_cast<size_t>(n)*2 : 0);
            for (R_xlen_t i = 0; indexed && i < n; ++i) {
                native_indices[2*i] = static_cast<unsigned int>(index_data.data.at(i)-1);
                native_indices[2*i+1] = static_cast<unsigned int>(index_data.data.at(i+n)-1);
            }
            SPSTACreateGraphDesc desc{};
            desc.m_LineCoords = coords.data();
            desc.m_LineCoordCount = static_cast<unsigned int>(coords.size());
            desc.m_LineCount = static_cast<unsigned int>(n);
            desc.m_Lines = indexed ? native_indices.data() : nullptr;
            desc.m_UnlinkCoords = native_unlinks.empty() ? nullptr : native_unlinks.data();
            desc.m_UnlinkCount = static_cast<unsigned int>(native_unlinks.size());
            desc.m_PointCoords = native_points.empty() ? nullptr : native_points.data();
            desc.m_PointCount = static_cast<unsigned int>(native_points.size());
            desc.m_PointsPerPolygon = polygons ? native_sizes.data() : nullptr;
            desc.m_PolygonCount = static_cast<unsigned int>(polygon_count);
            desc.m_PolygonPointInterval = spacing;
            const auto handle = PSTACreateGraph(&desc);
            if (!handle) std::snprintf(error, error_size, "PSTACreateGraph failed to create a native graph.");
            else { R_SetExternalPtrAddr(pointer, handle); ++created; }
        }
    } catch (const std::exception& e) {
        std::snprintf(error, error_size, "PST graph construction failed: %s", e.what());
    } catch (...) {
        std::snprintf(error, error_size, "PST graph construction failed with an unknown native exception.");
    }
    return error[0] == '\0';
}

SEXP create_axial_graph(SEXP x, SEXP indices, SEXP unlinks, SEXP points,
                        SEXP polygon_sizes, SEXP interval)
{
    const bool indexed = indices != R_NilValue;
    const bool polygons = polygon_sizes != R_NilValue;
    const auto lines = graph_input_matrix(x, indexed ? 2 : 4, "Coordinates");
    const auto unlink_data = graph_input_matrix(unlinks, 2, "unlinks", true);
    const auto point_data = graph_input_matrix(points, 2, "points", true, polygons);
    const auto index_data = indexed ? graph_input_matrix(indices, 2, "line_indices") : InputMatrix{};
    const R_xlen_t n = indexed ? index_data.rows : lines.rows;
    const R_xlen_t coord_count = indexed ? lines.rows : lines.rows * 2;
    if (static_cast<unsigned long long>(coord_count) > std::numeric_limits<unsigned int>::max())
        Rf_error("Too many coordinates for the PST graph descriptor.");
    if (indexed) {
        for (R_xlen_t i = 0; i < n * 2; ++i) {
            const double id = index_data.data.at(i);
            if (id < 1 || id > lines.rows || id != std::floor(id))
                Rf_error("line_indices must contain whole one-based coordinate indices within x.");
        }
    }
    CoordinateData sizes{nullptr, nullptr};
    R_xlen_t polygon_count = 0;
    float spacing = 0;
    stage_polygons(polygon_sizes, interval, point_data.rows, sizes, polygon_count, spacing);
    // All ALTREP storage is materialised above, before native buffers exist.
    SEXP pointer = PROTECT(R_MakeExternalPtr(nullptr, graph_tag(), R_NilValue));
    R_RegisterCFinalizerEx(pointer, graph_finalizer, TRUE);
    char error[512] = "";
    try {
        std::vector<double2> coords(static_cast<size_t>(coord_count));
        for (R_xlen_t i = 0; i < lines.rows; ++i) {
            if (indexed) coords[i] = lines.point(i);
            else {
                coords[2*i] = lines.point(i);
                coords[2*i+1] = double2(lines.data.at(i+2*lines.rows), lines.data.at(i+3*lines.rows));
            }
        }
        axial_build_core(pointer, coords, indexed, index_data, n, unlink_data, point_data,
                         polygons, sizes, polygon_count, spacing, error, sizeof(error));
    } catch (const std::exception& e) {
        std::snprintf(error, sizeof(error), "PST graph construction failed: %s", e.what());
    } catch (...) {
        std::snprintf(error, sizeof(error), "PST graph construction failed with an unknown native exception.");
    }
    if (error[0]) Rf_error("%s", error);
    UNPROTECT(1);
    return pointer;
}
} // namespace

namespace rpst {
// Allocate and register the empty axial external pointer before any native owner exists.
SEXP axial_graph_new_pointer()
{
    SEXP pointer = PROTECT(R_MakeExternalPtr(nullptr, graph_tag(), R_NilValue));
    R_RegisterCFinalizerEx(pointer, graph_finalizer, TRUE);
    UNPROTECT(1);
    return pointer;
}

void axial_graph_require_empty(SEXP pointer)
{
    if (TYPEOF(pointer) != EXTPTRSXP || R_ExternalPtrTag(pointer) != graph_tag())
        Rf_error("Invalid pst_graph native pointer; construct it with axial_graph().");
    if (R_ExternalPtrAddr(pointer) != nullptr)
        Rf_error("The pst_graph native pointer is not empty.");
}

void stage_axial_auxiliary(SEXP unlinks, SEXP points, SEXP polygon_sizes, SEXP interval, AxialAuxiliary& out)
{
    const bool polygons = polygon_sizes != R_NilValue;
    const auto unlink_data = graph_input_matrix(unlinks, 2, "unlinks", true);
    const auto point_data = graph_input_matrix(points, 2, "points", true, polygons);
    CoordinateData sizes{nullptr, nullptr};
    R_xlen_t polygon_count = 0;
    float spacing = 0;
    stage_polygons(polygon_sizes, interval, point_data.rows, sizes, polygon_count, spacing);
    out.unlinks = {unlink_data.rows, unlink_data.data.real, unlink_data.data.integer};
    out.points = {point_data.rows, point_data.data.real, point_data.data.integer};
    out.polygon_sizes = {polygon_count, sizes.real, sizes.integer};
    out.polygons = polygons;
    out.spacing = spacing;
}

bool axial_graph_build(SEXP pointer, std::vector<double2>& coords, const AxialAuxiliary& aux, char* error,
                       std::size_t error_size)
{
    error[0] = '\0';
    if (coords.size() < 2 || coords.size() % 2 != 0) {
        std::snprintf(error, error_size, "Line coordinates must hold two endpoints per line.");
        return false;
    }
    // PST's descriptor counts coordinates in unsigned int and the engine consumes signed int line counts.
    if (coords.size() > std::numeric_limits<unsigned int>::max() ||
        coords.size() / 2 > static_cast<std::size_t>(std::numeric_limits<int>::max())) {
        std::snprintf(error, error_size, "Too many lines for the PST graph descriptor.");
        return false;
    }
    const InputMatrix unlink_data{aux.unlinks.length, {aux.unlinks.real, aux.unlinks.integer}};
    const InputMatrix point_data{aux.points.length, {aux.points.real, aux.points.integer}};
    const CoordinateData sizes{aux.polygon_sizes.real, aux.polygon_sizes.integer};
    return axial_build_core(pointer, coords, false, InputMatrix{}, static_cast<R_xlen_t>(coords.size() / 2),
                            unlink_data, point_data, aux.polygons, sizes, aux.polygon_sizes.length,
                            aux.spacing, error, error_size);
}
}  // namespace rpst

// Empty, tagged, finalised axial pointer that the file routes fill later (allocated before any file/Arrow object).
extern "C" SEXP rpst_axial_graph_new_pointer()
{
    return rpst::axial_graph_new_pointer();
}

extern "C" SEXP rpst_graph_create(SEXP x)
{
    return create_axial_graph(x, R_NilValue, R_NilValue, R_NilValue, R_NilValue, R_NilValue);
}
extern "C" SEXP rpst_graph_create_inputs(SEXP x, SEXP indices, SEXP unlinks,
                                         SEXP points, SEXP sizes, SEXP interval)
{
    return create_axial_graph(x, indices, unlinks, points, sizes, interval);
}

extern "C" SEXP rpst_graph_info(SEXP pointer)
{
    auto handle = graph_handle(pointer);
    SEXP info = PROTECT(Rf_allocVector(INTSXP, 4));
    SPSTAGraphInfo native_info{};
    native_info.m_Version = SPSTAGraphInfo::VERSION;
    if (!PSTAGetGraphInfo(handle, &native_info))
        Rf_error("PSTAGetGraphInfo failed for the native pst_graph.");
    INTEGER(info)[0] = static_cast<int>(native_info.m_LineCount);
    INTEGER(info)[1] = static_cast<int>(native_info.m_CrossingCount);
    INTEGER(info)[2] = static_cast<int>(native_info.m_PointCount);
    // PSTAGetGraphInfo hardcodes this field to zero. The native graph retains
    // real groups; use its exact getter, never editable R metadata.
    INTEGER(info)[3] = static_cast<int>(static_cast<const CAxialGraph*>(handle)->getPointGroupCount());
    UNPROTECT(1);
    return info;
}

// Private deterministic disposal hook, also exercising the actual GC finalizer.
extern "C" SEXP rpst_graph_release(SEXP pointer)
{
    graph_handle(pointer, false);
    graph_finalizer(pointer);
    return R_NilValue;
}

extern "C" SEXP rpst_graph_lifecycle()
{
    SEXP counts = PROTECT(Rf_allocVector(REALSXP, 3));
    REAL(counts)[0] = created;
    REAL(counts)[1] = freed;
    REAL(counts)[2] = created - freed;
    UNPROTECT(1);
    return counts;
}

// ---- shared file-backed (Arrow C stream) destination ------------------------------------------------------------
// Every file-capable analysis runs ONCE through its single compute/finishing code; only the destination of the
// finished native arrays differs: widened R vectors (in memory) or an rPSTool-owned, reference-counted ResultTable
// exported zero-copy as an Arrow C stream. Stream arguments are validated (R errors) before any C++ owner exists.
namespace {
struct ResultStreamArgs {
    ArrowArrayStream* stream = nullptr;
    const char** names = nullptr;          // R_alloc'd array of expected names (UTF-8)
    const char** metadata_keys = nullptr;
    const char** metadata_values = nullptr;
    R_xlen_t metadata_count = 0;
    std::size_t batch_rows = rpst::kResultBatchRows;
};

ResultStreamArgs result_stream_args(SEXP stream_pointer, SEXP names, SEXP metadata_names, SEXP metadata_values,
                                    SEXP batch_rows, R_xlen_t expected_names)
{
    ResultStreamArgs a;
    a.stream = rpst::arrow_stream_require(stream_pointer);
    if (a.stream->release) Rf_error("The Arrow stream is already live.");
    if (TYPEOF(names) != STRSXP || XLENGTH(names) != expected_names)
        Rf_error("The result needs exactly %d column names.", static_cast<int>(expected_names));
    a.names = reinterpret_cast<const char**>(R_alloc(static_cast<size_t>(expected_names), sizeof(const char*)));
    for (R_xlen_t i = 0; i < expected_names; ++i) {
        if (STRING_ELT(names, i) == NA_STRING || !CHAR(STRING_ELT(names, i))[0])
            Rf_error("Result column names must be non-missing, non-empty strings.");
        a.names[i] = Rf_translateCharUTF8(STRING_ELT(names, i));
    }
    if (TYPEOF(metadata_names) != STRSXP || TYPEOF(metadata_values) != STRSXP ||
        XLENGTH(metadata_names) != XLENGTH(metadata_values))
        Rf_error("Result metadata must be a named character vector.");
    a.metadata_count = XLENGTH(metadata_names);
    a.metadata_keys = reinterpret_cast<const char**>(R_alloc(static_cast<size_t>(a.metadata_count) + 1, sizeof(const char*)));
    a.metadata_values = reinterpret_cast<const char**>(R_alloc(static_cast<size_t>(a.metadata_count) + 1, sizeof(const char*)));
    for (R_xlen_t i = 0; i < a.metadata_count; ++i) {
        if (STRING_ELT(metadata_names, i) == NA_STRING || !CHAR(STRING_ELT(metadata_names, i))[0] ||
            STRING_ELT(metadata_values, i) == NA_STRING)
            Rf_error("Result metadata keys must be non-empty and no key or value may be missing.");
        a.metadata_keys[i] = Rf_translateCharUTF8(STRING_ELT(metadata_names, i));
        a.metadata_values[i] = Rf_translateCharUTF8(STRING_ELT(metadata_values, i));
    }
    if (TYPEOF(batch_rows) != REALSXP || XLENGTH(batch_rows) != 1 || !std::isfinite(REAL(batch_rows)[0]) ||
        REAL(batch_rows)[0] < 1 || REAL(batch_rows)[0] > 2147483647.0 || std::floor(REAL(batch_rows)[0]) != REAL(batch_rows)[0])
        Rf_error("The Arrow batch size must be a whole number between 1 and 2147483647.");
    a.batch_rows = static_cast<std::size_t>(REAL(batch_rows)[0]);
    return a;
}

void result_add_float(rpst::ResultTable& table, const char* name, std::vector<float>&& values)
{
    rpst::ResultColumn column;
    column.name = name;
    column.kind = rpst::ResultKind::Float32;
    column.f32 = std::move(values);
    table.columns.push_back(std::move(column));
}
void result_add_count(rpst::ResultTable& table, const char* name, std::vector<unsigned int>&& values)
{
    rpst::ResultColumn column;
    column.name = name;
    column.kind = rpst::ResultKind::Int32;
    column.u32 = std::move(values);
    table.columns.push_back(std::move(column));
}
void result_add_signed(rpst::ResultTable& table, const char* name, std::vector<int>&& values)
{
    rpst::ResultColumn column;
    column.name = name;
    column.kind = rpst::ResultKind::SignedInt32;
    column.i32 = std::move(values);
    table.columns.push_back(std::move(column));
}
// Mark the most recently added column nullable with its Arrow validity bits (bit i set = row i valid, LSB-first).
void result_mark_nullable(rpst::ResultTable& table, std::vector<std::uint8_t> validity)
{
    table.columns.back().nullable = true;
    table.columns.back().validity = std::move(validity);
}
// Validity bits from a per-row "written" predicate; a row PST did not write is null, every written value (NaN, Inf, -1, 0
// included) is valid.
template <class Written>
std::vector<std::uint8_t> result_validity(std::size_t rows, Written written)
{
    std::vector<std::uint8_t> bits((rows + 7) / 8, 0);
    for (std::size_t i = 0; i < rows; ++i)
        if (written(i)) bits[i >> 3] |= static_cast<std::uint8_t>(1u << (i & 7));
    return bits;
}
std::shared_ptr<rpst::ResultTable> result_new_table(const ResultStreamArgs& a, std::size_t rows)
{
    auto table = std::make_shared<rpst::ResultTable>();
    table->id_name = a.names[0];
    table->rows = rows;
    return table;
}
// The raw .Call arguments of the file route; null means "return R vectors". Parsed (and validated, with R errors)
// by result_stream_args only after the analysis arguments have been validated, because the expected column count
// can depend on them.
struct StreamRequest {
    SEXP stream, names, metadata_names, metadata_values, batch_rows;
};
ResultStreamArgs result_stream_args(const StreamRequest& r, R_xlen_t expected_names)
{
    return result_stream_args(r.stream, r.names, r.metadata_names, r.metadata_values, r.batch_rows, expected_names);
}
void result_finish_and_export(const ResultStreamArgs& a, std::shared_ptr<rpst::ResultTable> table, char* error, size_t size)
{
    for (R_xlen_t i = 0; i < a.metadata_count; ++i)
        table->metadata.emplace_back(a.metadata_keys[i], a.metadata_values[i]);
    rpst::export_result_stream(a.stream, std::move(table), a.batch_rows, rpst::StreamFaults{}, error, size);
}
} // namespace


namespace {
SEXP network_integration(SEXP pointer, SEXP steps, bool junctions, const StreamRequest* request = nullptr)
{
    // Reuse Task 003's tag/liveness validation. This is an axial HPSTAGraph;
    // it is never reinterpreted as a segment graph or another engine type.
    const HPSTAGraph handle = graph_handle(pointer);
    const auto radii = analysis_radii(steps);
    SPSTAGraphInfo info{};
    info.m_Version = SPSTAGraphInfo::VERSION;
    if (!PSTAGetGraphInfo(handle, &info))
        Rf_error("PSTAGetGraphInfo failed before PSTANetworkIntegration.");
    if (info.m_LineCount > static_cast<unsigned int>(std::numeric_limits<int>::max()))
        Rf_error("Too many lines for PSTANetworkIntegration.");
    const R_xlen_t n = info.m_LineCount;
    if (junctions && info.m_CrossingCount > static_cast<unsigned int>(std::numeric_limits<int>::max()))
        Rf_error("Too many junctions for PSTANetworkIntegration.");
    if (request && junctions)
        Rf_error("A result file cannot hold junction results; use junctions = FALSE with output_file.");
    const R_xlen_t junction_count = junctions ? info.m_CrossingCount : 0;
    ResultStreamArgs args;
    if (request) args = result_stream_args(*request, 4);

    // Allocate and cache all R output storage before C++ temporary buffers
    // exist. The .Call argument roots the owner for the entire synchronous call.
    // (The file route builds no R result vectors.)
    SEXP result = R_NilValue, junction_coords = R_NilValue, junction_scores = R_NilValue;
    double *integration_data = nullptr, *depth_data = nullptr, *coords_data = nullptr, *junction_data = nullptr;
    int* count_data = nullptr;
    int protected_count = 0;
    if (!request) {
        result = PROTECT(Rf_allocVector(VECSXP, junctions ? 5 : 3));
        SEXP integration = PROTECT(Rf_allocVector(REALSXP, n));
        SEXP node_count = PROTECT(Rf_allocVector(INTSXP, n));
        SEXP total_depth = PROTECT(Rf_allocVector(REALSXP, n));
        SET_VECTOR_ELT(result, 0, integration);
        SET_VECTOR_ELT(result, 1, node_count);
        SET_VECTOR_ELT(result, 2, total_depth);
        junction_coords = PROTECT(Rf_allocMatrix(REALSXP, static_cast<int>(junction_count), 2));
        junction_scores = PROTECT(Rf_allocVector(REALSXP, junction_count));
        protected_count = 6;
        if (junctions) {
            SET_VECTOR_ELT(result, 3, junction_coords);
            SET_VECTOR_ELT(result, 4, junction_scores);
        }
        coords_data = REAL(junction_coords);
        junction_data = REAL(junction_scores);
        integration_data = REAL(integration);
        count_data = INTEGER(node_count);
        depth_data = REAL(total_depth);
    }
    char error[512] = "";
    try {
        std::vector<float> scores(static_cast<size_t>(n));
        std::vector<unsigned int> counts(static_cast<size_t>(n));
        std::vector<float> depths(static_cast<size_t>(n));
        // PST accumulates junction scores; zero is the required fresh seed.
        std::vector<float> native_junction_scores(static_cast<size_t>(junction_count), 0);
        std::vector<double2> native_junction_coords(static_cast<size_t>(junction_count));
        SPSTANetworkIntegrationDesc desc{};
        desc.m_Version = SPSTANetworkIntegrationDesc::VERSION;
        desc.m_Graph = handle;
        // The constructor clears all radii, callbacks and optional outputs.
        desc.m_Radius = radii;
        desc.m_OutJunctionCount = static_cast<unsigned int>(junction_count);
        desc.m_OutJunctionCoords = junction_count ? native_junction_coords.data() : nullptr;
        desc.m_OutJunctionScores = junction_count ? native_junction_scores.data() : nullptr;
        desc.m_OutLineIntegration = scores.data();
        desc.m_OutLineNodeCount = counts.data();
        desc.m_OutLineTotalDepth = depths.data();
        rpst::progress_attach(desc.m_ProgressCallback, desc.m_ProgressCallbackUser);
        if (!PSTANetworkIntegration(&desc)) {
            std::snprintf(error, sizeof(error), "PSTANetworkIntegration failed for the native pst_graph.");
        } else if (request) {
            auto table = result_new_table(args, static_cast<size_t>(n));
            result_add_float(*table, args.names[1], std::move(scores));
            result_add_count(*table, args.names[2], std::move(counts));
            result_add_float(*table, args.names[3], std::move(depths));
            result_finish_and_export(args, std::move(table), error, sizeof error);
        } else {
            for (R_xlen_t i = 0; i < junction_count; ++i) {
                coords_data[i] = native_junction_coords[i].x;
                coords_data[i+junction_count] = native_junction_coords[i].y;
                junction_data[i] = native_junction_scores[i];
            }
            for (R_xlen_t i = 0; i < n; ++i) {
                integration_data[i] = scores[static_cast<size_t>(i)];
                count_data[i] = static_cast<int>(counts[static_cast<size_t>(i)]);
                depth_data[i] = depths[static_cast<size_t>(i)];
            }
        }
    } catch (const std::exception& e) {
        std::snprintf(error, sizeof(error), "PSTANetworkIntegration failed: %s", e.what());
    } catch (...) {
        std::snprintf(error, sizeof(error), "PSTANetworkIntegration failed with an unknown native exception.");
    }
    // Preserve PST scores, including -1, NaN and Inf for small neighbourhoods.
    // No R error jump or allocation can bypass a C++ buffer destructor.
    if (error[0]) Rf_error("%s", error);
    if (request) return Rf_ScalarReal(static_cast<double>(n));
    UNPROTECT(protected_count);
    return result;
}

} // namespace
extern "C" SEXP rpst_network_integration(SEXP pointer, SEXP steps)
{
    return network_integration(pointer, steps, false);
}
extern "C" SEXP rpst_network_integration_stream(SEXP pointer, SEXP steps, SEXP stream_pointer, SEXP names,
    SEXP metadata_names, SEXP metadata_values, SEXP batch_rows)
{
    const StreamRequest request{stream_pointer, names, metadata_names, metadata_values, batch_rows};
    return network_integration(pointer, steps, false, &request);
}
extern "C" SEXP rpst_network_integration_outputs(SEXP pointer, SEXP steps, SEXP junctions)
{
    if (TYPEOF(junctions) != LGLSXP || XLENGTH(junctions) != 1 || LOGICAL(junctions)[0] == NA_LOGICAL)
        Rf_error("junctions must be TRUE or FALSE.");
    return network_integration(pointer, steps, LOGICAL(junctions)[0]);
}

extern "C" SEXP rpst_graph_line_lengths(SEXP pointer)
{
    const auto handle = graph_handle(pointer);
    const int n = PSTAGetGraphLineLengths(handle, nullptr, 0);
    if (n < 0) Rf_error("PSTAGetGraphLineLengths failed to query the native count.");
    SEXP out = PROTECT(Rf_allocVector(REALSXP, n));
    double* data = REAL(out);
    char error[512] = "";
    try {
        std::vector<float> lengths(static_cast<size_t>(n));
        if (PSTAGetGraphLineLengths(handle, lengths.data(), n) != n)
            std::snprintf(error, sizeof(error), "PSTAGetGraphLineLengths failed.");
        else for (int i = 0; i < n; ++i) data[i] = lengths[i];
    } catch (const std::exception& e) {
        std::snprintf(error, sizeof(error), "PSTAGetGraphLineLengths failed: %s", e.what());
    } catch (...) { std::snprintf(error, sizeof(error), "PSTAGetGraphLineLengths failed with an unknown native exception."); }
    if (error[0]) Rf_error("%s", error);
    UNPROTECT(1);
    return out;
}
extern "C" SEXP rpst_graph_crossing_coords(SEXP pointer)
{
    const auto handle = graph_handle(pointer);
    const int n = PSTAGetGraphCrossingCoords(handle, nullptr, 0);
    if (n < 0) Rf_error("PSTAGetGraphCrossingCoords failed to query the native count.");
    SEXP out = PROTECT(Rf_allocMatrix(REALSXP, n, 2));
    double* data = REAL(out);
    char error[512] = "";
    try {
        std::vector<double2> coords(static_cast<size_t>(n));
        if (PSTAGetGraphCrossingCoords(handle, n ? coords.data() : nullptr, n) != n)
            std::snprintf(error, sizeof(error), "PSTAGetGraphCrossingCoords failed.");
        else for (int i = 0; i < n; ++i) { data[i] = coords[i].x; data[i+n] = coords[i].y; }
    } catch (const std::exception& e) {
        std::snprintf(error, sizeof(error), "PSTAGetGraphCrossingCoords failed: %s", e.what());
    } catch (...) { std::snprintf(error, sizeof(error), "PSTAGetGraphCrossingCoords failed with an unknown native exception."); }
    if (error[0]) Rf_error("%s", error);
    UNPROTECT(1);
    return out;
}

// Segment owners never contain axial handles. PST exposes no segment graph
// count getter in its C API: keep the verified constructor count in native
// owner storage, independent of editable R list fields.
namespace {
struct SegmentOwner {
    HPSTASegmentGraph handle = nullptr;
    unsigned int count = 0;
    unsigned int max_degree = 0;
    // Segments whose two endpoints coincide. PST's segment-group graph
    // construction does not terminate on them (rpst_segment_group_graph_create).
    unsigned int zero_length = 0;
};
double segment_created = 0;
double segment_freed = 0;
SEXP segment_graph_tag() { return Rf_install("rPST::HPSTASegmentGraph/v1"); }

void segment_graph_finalizer(SEXP pointer)
{
    auto* owner = static_cast<SegmentOwner*>(R_ExternalPtrAddr(pointer));
    if (!owner) return;
    R_ClearExternalPtr(pointer);
    if (owner->handle) {
        PSTAFreeSegmentGraph(owner->handle);
        ++segment_freed;
    }
    delete owner;
}

SegmentOwner* segment_graph_owner(SEXP pointer, bool require_live = true)
{
    if (TYPEOF(pointer) != EXTPTRSXP || R_ExternalPtrTag(pointer) != segment_graph_tag())
        Rf_error("Invalid pst_segment_graph native pointer; construct it with segment_graph().");
    auto* owner = static_cast<SegmentOwner*>(R_ExternalPtrAddr(pointer));
    if (require_live && (!owner || !owner->handle))
        Rf_error("The pst_segment_graph native pointer is no longer live (released or deserialised); reconstruct it with segment_graph().");
    return owner;
}
}

namespace rpst {
// Allocate and register the empty external pointer before any native owner exists.
// The caller must PROTECT the result immediately.
SEXP segment_graph_new_pointer()
{
    SEXP pointer = PROTECT(R_MakeExternalPtr(nullptr, segment_graph_tag(), R_NilValue));
    R_RegisterCFinalizerEx(pointer, segment_graph_finalizer, TRUE);
    UNPROTECT(1);
    return pointer;
}

// Exact-tag validator for an empty (not yet built) segment-graph pointer, as made by
// segment_graph_new_pointer(). May raise an R error; call before any C++ owner exists.
void segment_graph_require_empty(SEXP pointer)
{
    if (TYPEOF(pointer) != EXTPTRSXP || R_ExternalPtrTag(pointer) != segment_graph_tag())
        Rf_error("Invalid pst_segment_graph native pointer; construct it with segment_graph().");
    if (R_ExternalPtrAddr(pointer) != nullptr)
        Rf_error("The pst_segment_graph native pointer is not empty.");
}

// Shared segment-graph construction from one contiguous coordinate array holding
// two endpoints per segment: validation, origin/representability checks, the
// endpoint-degree guard, the PST descriptor and PSTACreateSegmentGraph. Used by the
// matrix route and by the GeoParquet stream route. Never calls the R API except
// R_SetExternalPtrAddr, and never throws: failures are returned in `error`.
bool segment_graph_build(SEXP pointer, std::vector<double2>& coords, char* error,
                         std::size_t error_size)
{
    error[0] = '\0';
    if (coords.size() < 2 || coords.size() % 2 != 0) {
        std::snprintf(error, error_size, "Segment coordinates must hold two endpoints per segment.");
        return false;
    }
    // Enforce the native bounds here, before any narrowing: PST's descriptor counts
    // coordinates in unsigned int and the engine consumes signed int line counts.
    if (coords.size() > std::numeric_limits<unsigned int>::max() ||
        coords.size() / 2 > static_cast<std::size_t>(std::numeric_limits<int>::max())) {
        std::snprintf(error, error_size, "Too many segments for the PST graph descriptor.");
        return false;
    }
    try {
        const std::size_t segments = coords.size() / 2;
        auto* owner = new SegmentOwner{};
        R_SetExternalPtrAddr(pointer, owner);
        owner->count = static_cast<unsigned int>(segments);
        double2 lo = coords.front();
        double2 hi = lo;
        for (const auto& p : coords) {
            lo.x = std::min(lo.x, p.x); lo.y = std::min(lo.y, p.y);
            hi.x = std::max(hi.x, p.x); hi.y = std::max(hi.y, p.y);
        }
        // PST centres doubles then uses float local coordinates and squared
        // float distances. Reject overflow; do not rescale, snap or filter.
        const double2 origin((lo.x + hi.x) / 2, (lo.y + hi.y) / 2);
        const double max_float = std::numeric_limits<float>::max();
        bool representable = std::isfinite(origin.x) && std::isfinite(origin.y);
        for (const auto& p : coords) {
            const double2 local = p - origin;
            representable = representable && std::isfinite(local.x) &&
                std::isfinite(local.y) && std::abs(local.x) <= max_float &&
                std::abs(local.y) <= max_float;
        }
        if (representable) {
            const auto lower = static_cast<float2>(lo - origin);
            const auto upper = static_cast<float2>(hi - origin);
            representable = std::isfinite((upper - lower).getLengthSqr());
        }
        for (size_t i = 0; representable && i < coords.size(); i += 2) {
            const auto center = (coords[i] + coords[i + 1]) * 0.5 - origin;
            const double length = (coords[i + 1] - coords[i]).getLength();
            representable = std::isfinite(center.x) && std::isfinite(center.y) &&
                std::isfinite(length) && length <= max_float;
        }
        if (!representable) {
            std::snprintf(error, error_size, "Coordinate extent overflows PST's native local-coordinate/distance representation.");
        } else {
            // Count endpoint incidences only to guard the angular engine's
            // 32-bit outgoing-path mask. Do not alter coordinates or topology.
            auto sorted = coords;
            std::sort(sorted.begin(), sorted.end(), [](const double2& a, const double2& b) {
                return a.x == b.x ? a.y < b.y : a.x < b.x;
            });
            for (size_t i = 0; i < coords.size(); i += 2)
                if (coords[i] == coords[i + 1]) ++owner->zero_length;
            unsigned int degree = 0;
            double2 previous = sorted.front();
            for (const auto& point : sorted) {
                degree = point == previous ? degree + 1 : 1;
                owner->max_degree = std::max(owner->max_degree, degree);
                previous = point;
            }
            SPSTACreateSegmentGraphDesc desc{};
            desc.m_Version = SPSTACreateSegmentGraphDesc::VERSION;
            desc.m_LineCoords = coords.data();
            desc.m_LineCoordCount = static_cast<unsigned int>(coords.size());
            desc.m_LineCount = static_cast<unsigned int>(segments);
            // Null indices mean sequential endpoint pairs; optional fields
            // and callbacks retain their pinned default null/zero values.
            auto handle = PSTACreateSegmentGraph(&desc);
            if (!handle)
                std::snprintf(error, error_size, "PSTACreateSegmentGraph failed to create a native graph.");
            else {
                owner->handle = handle;
                ++segment_created;
            }
        }
    } catch (const std::exception& e) {
        std::snprintf(error, error_size, "PST segment graph construction failed: %s", e.what());
    } catch (...) {
        std::snprintf(error, error_size, "PST segment graph construction failed with an unknown native exception.");
    }
    return error[0] == '\0';
}
}  // namespace rpst

// Allocate the empty, tagged, finalised segment-graph pointer that the GeoParquet route
// fills later (allocated before any Arrow object is live).
extern "C" SEXP rpst_segment_graph_new_pointer()
{
    return rpst::segment_graph_new_pointer();
}

extern "C" SEXP rpst_segment_graph_create(SEXP x)
{
    if (!Rf_isMatrix(x) || (TYPEOF(x) != REALSXP && TYPEOF(x) != INTSXP))
        Rf_error("Coordinates must be a numeric matrix with four columns: x1, y1, x2, y2.");
    SEXP dims = Rf_getAttrib(x, R_DimSymbol);
    const int n = INTEGER(dims)[0];
    if (INTEGER(dims)[1] != 4 || n <= 0)
        Rf_error("Coordinates must have at least one row and exactly four columns: x1, y1, x2, y2.");
    // PST's descriptor counts coordinates in unsigned int, but the engine
    // consumes signed int line counts and R uses an R_xlen_t element index.
    if (static_cast<unsigned long long>(n) * 2 >
        std::numeric_limits<unsigned int>::max())
        Rf_error("Too many segments for the PST graph descriptor.");
    const R_xlen_t rows = n;
    // Materialise ALTREP input once, before any C++ buffer owns memory.
    const CoordinateData data{TYPEOF(x) == REALSXP ? REAL(x) : nullptr,
                              TYPEOF(x) == INTSXP ? INTEGER(x) : nullptr};
    for (R_xlen_t i = 0; i < XLENGTH(x); ++i)
        if (!std::isfinite(data.at(i)))
            Rf_error("Coordinates must all be finite (no NA, NaN or Inf).");

    // Allocate/register the empty owner before native acquisition. No R
    // allocations or errors occur while C++ temporary buffers are alive.
    SEXP pointer = PROTECT(rpst::segment_graph_new_pointer());
    char error[512] = "";
    try {
        std::vector<double2> coords(static_cast<size_t>(n) * 2);
        for (R_xlen_t i = 0; i < rows; ++i) {
            coords[static_cast<size_t>(i) * 2] =
                double2(data.at(i), data.at(i + rows));
            coords[static_cast<size_t>(i) * 2 + 1] =
                double2(data.at(i + 2 * rows), data.at(i + 3 * rows));
        }
        rpst::segment_graph_build(pointer, coords, error, sizeof(error));
    } catch (const std::exception& e) {
        std::snprintf(error, sizeof(error), "PST segment graph construction failed: %s", e.what());
    } catch (...) {
        std::snprintf(error, sizeof(error), "PST segment graph construction failed with an unknown native exception.");
    }
    // All C++ temporaries have unwound before R's non-local error jump.
    if (error[0]) Rf_error("%s", error);
    UNPROTECT(1);
    return pointer;
}

extern "C" SEXP rpst_segment_graph_info(SEXP pointer)
{
    return Rf_ScalarInteger(static_cast<int>(segment_graph_owner(pointer)->count));
}
extern "C" SEXP rpst_segment_graph_release(SEXP pointer)
{
    segment_graph_owner(pointer, false);
    segment_graph_finalizer(pointer);
    return R_NilValue;
}
extern "C" SEXP rpst_segment_graph_lifecycle()
{
    SEXP counts = PROTECT(Rf_allocVector(REALSXP, 3));
    REAL(counts)[0] = segment_created;
    REAL(counts)[1] = segment_freed;
    REAL(counts)[2] = segment_created - segment_freed;
    UNPROTECT(1);
    return counts;
}

namespace {
struct AngularSettings { float threshold; unsigned int precision; };
AngularSettings angular_settings(SEXP threshold, SEXP precision)
{
    if ((TYPEOF(threshold) != REALSXP && TYPEOF(threshold) != INTSXP) || XLENGTH(threshold) != 1)
        Rf_error("angle_threshold must be one finite native-float number.");
    const double t = TYPEOF(threshold) == REALSXP ? REAL(threshold)[0] : INTEGER(threshold)[0];
    if (!std::isfinite(t) || (TYPEOF(threshold) == INTSXP && INTEGER(threshold)[0] == NA_INTEGER) ||
        std::abs(t) > std::numeric_limits<float>::max() || (t != 0 && static_cast<float>(t) == 0))
        Rf_error("angle_threshold must fit a finite native float without nonzero underflow.");
    if ((TYPEOF(precision) != REALSXP && TYPEOF(precision) != INTSXP) || XLENGTH(precision) != 1)
        Rf_error("angle_precision must be one positive whole number no greater than UINT_MAX.");
    const double v = TYPEOF(precision) == REALSXP ? REAL(precision)[0] : INTEGER(precision)[0];
    // Zero would divide by zero in the native discrete priority queue initializer.
    if (!std::isfinite(v) || v < 1 || v > std::numeric_limits<unsigned int>::max() || std::floor(v) != v)
        Rf_error("angle_precision must be one positive whole number no greater than UINT_MAX.");
    return {static_cast<float>(t), static_cast<unsigned int>(v)};
}
bool angular_weighted(SEXP weighted)
{
    if (TYPEOF(weighted) != LGLSXP || XLENGTH(weighted) != 1 || LOGICAL(weighted)[0] == NA_LOGICAL)
        Rf_error("weigh_by_length must be TRUE or FALSE.");
    return LOGICAL(weighted)[0];
}
// Complete native result of one Angular Integration run, exactly as PST wrote and the established normalisation
// finished it. Shared by the in-memory (R vectors) and the file-backed (Arrow) routes: the only difference
// between them is what happens to these arrays afterwards.
struct AngularIntegrationData {
    std::vector<float> scores, depths, weights, depth_weights;
    std::vector<unsigned int> counts;
};

// Test-only instrumentation (docs/compatibility/multi-radius.md section 2, docs/architecture.md): how often the expensive PST analysis and
// the cheap PST normalisers ran, and a countdown that makes the (k+1)-th PST analysis fail. It ships in the installed library on
// purpose: the package tests, including those run in CRAN mode, exercise the installed binary, and this is the only way to test
// "PST runs once per radius" and a failure in the middle of a radius sequence. It is not exported, is memory-safe (a failure is an
// ordinary C++ exception), validates its arguments, is one-shot (the countdown disarms itself) and is disabled (-1) by default.
// The members are atomic so that no data race is possible even though they are only touched from the R thread today.
struct AngularInstrumentation {
    std::atomic<unsigned long long> choice_runs{0}, choice_normalizations{0}, integration_runs{0}, integration_normalizations{0};
    std::atomic<int> fail_after_runs{-1};
};
AngularInstrumentation g_angular;
void angular_fault_point()
{
    const int remaining = g_angular.fail_after_runs.load();
    if (remaining < 0) return;
    if (remaining == 0) {
        g_angular.fail_after_runs.store(-1);
        throw std::runtime_error("injected native failure");
    }
    g_angular.fail_after_runs.store(remaining - 1);
}

// The ONE expensive step: a single PSTAAngularIntegration call. Fills counts, depths and (when requested) both weight
// arrays; `scores` is left empty for the caller. May throw; call it only inside a try block with no live R-API use.
void angular_integration_run(const SegmentOwner* owner, const SPSTARadii& radii, bool weighted,
                             AngularSettings settings, bool need_weights, AngularIntegrationData& d)
{
    const R_xlen_t n = owner->count;
    angular_fault_point();
    d.depths.assign(static_cast<size_t>(n), 0.0f);
    d.weights.assign(need_weights ? static_cast<size_t>(n) : 0, 0.0f);
    d.depth_weights.assign(need_weights ? static_cast<size_t>(n) : 0, 0.0f);
    d.counts.assign(static_cast<size_t>(n), 0u);
    SPSTAAngularIntegrationDesc desc{};
    desc.m_Graph = owner->handle;
    desc.m_Radius = radii;
    desc.m_WeighByLength = weighted;
    desc.m_AngleThreshold = settings.threshold;
    desc.m_AnglePrecision = settings.precision;
    desc.m_OutNodeCounts = d.counts.data();
    desc.m_OutTotalDepths = d.depths.data();
    desc.m_OutTotalWeights = need_weights ? d.weights.data() : nullptr;
    desc.m_OutTotalDepthWeights = need_weights ? d.depth_weights.data() : nullptr;
    ++g_angular.integration_runs;
    rpst::progress_attach(desc.m_ProgressCallback, desc.m_ProgressCallbackUser);
    if (!PSTAAngularIntegration(&desc)) throw std::runtime_error("PSTAAngularIntegration failed for the native pst_segment_graph.");
    for (R_xlen_t i = 0; i < n; ++i)
        if (d.counts[static_cast<size_t>(i)] > owner->count) throw std::runtime_error("PST returned an invalid angular node count.");
}

// One exported PST normaliser (0 turner, 1 syntax, 2 hillier) applied to the finished diagnostics of a run; the
// length-weighted variants consume the weight arrays, the others the counts and depths. `weighted` must match the run.
void angular_integration_normalize(int norm, bool weighted, const AngularIntegrationData& d, R_xlen_t n, std::vector<float>& out)
{
    out.assign(static_cast<size_t>(n), 0.0f);
    ++g_angular.integration_normalizations;
    if (weighted) {
        switch (norm) {
        case 0: PSTAAngularIntegrationNormalizeLengthWeight(d.weights.data(), d.depth_weights.data(), n, out.data()); break;
        case 1: PSTAAngularIntegrationSyntaxNormalizeLengthWeight(d.weights.data(), d.depth_weights.data(), n, out.data()); break;
        case 2: PSTAAngularIntegrationHillierNormalizeLengthWeight(d.weights.data(), d.depth_weights.data(), n, out.data()); break;
        }
    } else {
        switch (norm) {
        case 0: PSTAAngularIntegrationNormalize(d.counts.data(), d.depths.data(), n, out.data()); break;
        case 1: PSTAAngularIntegrationSyntaxNormalize(d.counts.data(), d.depths.data(), n, out.data()); break;
        case 2: PSTAAngularIntegrationHillierNormalize(d.counts.data(), d.depths.data(), n, out.data()); break;
        }
    }
}

// The authoritative computation + finishing for ONE radius and ONE normalisation (the scalar call).
void angular_integration_compute(const SegmentOwner* owner, const SPSTARadii& radii, bool weighted, int norm,
                                 AngularSettings settings, bool need_weights, AngularIntegrationData& d)
{
    angular_integration_run(owner, radii, weighted, settings, need_weights, d);
    angular_integration_normalize(norm, weighted, d, owner->count, d.scores);
}

SEXP angular_integration(SEXP pointer, SEXP steps, bool weighted, int norm,
                         AngularSettings settings, bool weight_outputs)
{
    const auto* owner = segment_graph_owner(pointer);
    if (owner->max_degree > 32)
        Rf_error("PSTAAngularIntegration supports at most 32 endpoint incidences at a shared coordinate (native outgoing-path mask).");
    const auto radii = analysis_radii(steps, true);
    const R_xlen_t n = owner->count;
    const bool need_weights = weighted || weight_outputs;
    SEXP result = PROTECT(Rf_allocVector(VECSXP, need_weights ? 5 : 3));
    double* out[4]{};
    for (int j : {0, 2, 3, 4}) {
        if (j >= 3 && !need_weights) continue;
        SEXP v = PROTECT(Rf_allocVector(REALSXP, n));
        SET_VECTOR_ELT(result, j, v);
        out[j == 0 ? 0 : j - 1] = REAL(v);
        UNPROTECT(1);
    }
    SEXP count = PROTECT(Rf_allocVector(INTSXP, n));
    SET_VECTOR_ELT(result, 1, count);
    int* counts_out = INTEGER(count);
    char error[512] = "";
    try {
        AngularIntegrationData d;
        angular_integration_compute(owner, radii, weighted, norm, settings, need_weights, d);
        for (R_xlen_t i = 0; i < n; ++i) {
            out[0][i] = d.scores[i]; counts_out[i] = static_cast<int>(d.counts[i]); out[1][i] = d.depths[i];
            if (need_weights) { out[2][i] = d.weights[i]; out[3][i] = d.depth_weights[i]; }
        }
    } catch (const std::exception& e) {
        std::snprintf(error, sizeof(error), "PSTAAngularIntegration failed: %s", e.what());
    } catch (...) {
        std::snprintf(error, sizeof(error), "PSTAAngularIntegration failed with an unknown native exception.");
    }
    if (error[0]) Rf_error("%s", error);
    UNPROTECT(2);
    return result;
}
} // namespace
extern "C" SEXP rpst_angular_integration(SEXP pointer, SEXP steps)
{
    return angular_integration(pointer, steps, false, 0, {0, 1}, false);
}
extern "C" SEXP rpst_angular_integration_controls(SEXP pointer, SEXP steps, SEXP weighted,
    SEXP normalization, SEXP threshold, SEXP precision, SEXP weight_outputs)
{
    segment_graph_owner(pointer);
    const auto settings = angular_settings(threshold, precision);
    const bool weigh_by_length = angular_weighted(weighted);
    if (TYPEOF(weight_outputs) != LGLSXP || XLENGTH(weight_outputs) != 1 || LOGICAL(weight_outputs)[0] == NA_LOGICAL)
        Rf_error("weight_outputs must be TRUE or FALSE.");
    const char* names[] = {"turner", "syntax", "hillier"};
    const int norm = named_mode(normalization, names, 3, "normalization");
    return angular_integration(pointer, steps, weigh_by_length, norm, settings, LOGICAL(weight_outputs)[0]);
}

namespace {
SEXP reach_points(SEXP pointer, SEXP radius, SEXP origins, const StreamRequest* request)
{
    const auto handle = graph_handle(pointer);
    const auto radii = shared_radii(radius);
    SPSTAGraphInfo info{};
    if (!PSTAGetGraphInfo(handle, &info)) Rf_error("PSTAGetGraphInfo failed before PSTAReach.");
    const auto points = analysis_points(origins, handle, "origins");
    const R_xlen_t n = origins == R_NilValue ? info.m_LineCount : points.count;
    ResultStreamArgs args;
    if (request) args = result_stream_args(*request, 4);
    SEXP result = R_NilValue;
    int* counts_out = nullptr;
    double *lengths_out = nullptr, *areas_out = nullptr;
    if (!request) {
        result = PROTECT(Rf_allocVector(VECSXP, 3));
        SEXP count = PROTECT(Rf_allocVector(INTSXP, n));
        SEXP length = PROTECT(Rf_allocVector(REALSXP, n));
        SEXP area = PROTECT(Rf_allocVector(REALSXP, n));
        SET_VECTOR_ELT(result, 0, count);
        SET_VECTOR_ELT(result, 1, length);
        SET_VECTOR_ELT(result, 2, area);
        counts_out = INTEGER(count);
        lengths_out = REAL(length);
        areas_out = REAL(area);
    }
    char error[512] = "";
    try {
        auto coords = copy_analysis_points(points);
        std::vector<unsigned int> counts(n);
        std::vector<float> lengths(n), areas(n);
        SPSTAReachDesc desc{};
        desc.m_Graph = handle;
        desc.m_Radius = radii;
        desc.m_OriginCoords = origins == R_NilValue ? nullptr : coords.data();
        desc.m_OriginCount = static_cast<unsigned int>(points.count);
        desc.m_OutReachedCount = counts.data();
        desc.m_OutReachedLength = lengths.data();
        desc.m_OutReachedArea = areas.data();
        rpst::progress_attach(desc.m_ProgressCallback, desc.m_ProgressCallbackUser);
        if (!PSTAReach(&desc)) throw std::runtime_error("PSTAReach returned false");
        if (request) {
            auto table = result_new_table(args, static_cast<size_t>(n));
            result_add_count(*table, args.names[1], std::move(counts));
            result_add_float(*table, args.names[2], std::move(lengths));
            result_add_float(*table, args.names[3], std::move(areas));
            result_finish_and_export(args, std::move(table), error, sizeof error);
        } else {
            for (R_xlen_t i = 0; i < n; ++i) {
                counts_out[i] = static_cast<int>(counts[i]);
                lengths_out[i] = lengths[i];
                areas_out[i] = areas[i];
            }
        }
    } catch (const std::exception& e) {
        std::snprintf(error, sizeof(error), "PSTAReach failed: %s", e.what());
    } catch (...) {
        std::snprintf(error, sizeof(error), "PSTAReach failed with an unknown native exception.");
    }
    if (error[0]) Rf_error("%s", error);
    if (request) return Rf_ScalarReal(static_cast<double>(n));
    UNPROTECT(4);
    return result;
}
} // namespace
extern "C" SEXP rpst_reach_points(SEXP pointer, SEXP radius, SEXP origins)
{
    return reach_points(pointer, radius, origins, nullptr);
}
extern "C" SEXP rpst_reach_points_stream(SEXP pointer, SEXP radius, SEXP origins, SEXP stream_pointer, SEXP names,
    SEXP metadata_names, SEXP metadata_values, SEXP batch_rows)
{
    const StreamRequest request{stream_pointer, names, metadata_names, metadata_values, batch_rows};
    return reach_points(pointer, radius, origins, &request);
}

extern "C" SEXP rpst_reach(SEXP pointer, SEXP radius)
{
    return rpst_reach_points(pointer, radius, R_NilValue);
}

// Centrality shares allocation/conversion only. Each descriptor retains its
// exact graph family, and native validators run before any graph access.
namespace {
// Test-only instrumentation of the axial analyses (same contract as AngularInstrumentation): counts of PST Reach (multi route) and
// Segment Betweenness runs and of Betweenness normaliser calls, and a one-shot countdown that makes the (k+1)-th run fail.
struct AxialInstrumentation {
    std::atomic<unsigned long long> reach_runs{0}, betweenness_runs{0}, betweenness_normalizations{0}, integration_runs{0},
                                    attraction_reach_runs{0}, attraction_distance_runs{0}, od_runs{0};
    std::atomic<int> fail_after_runs{-1};
};
AxialInstrumentation g_axial;
void axial_fault_point()
{
    const int remaining = g_axial.fail_after_runs.load();
    if (remaining < 0) return;
    if (remaining == 0) {
        g_axial.fail_after_runs.store(-1);
        throw std::runtime_error("injected native failure");
    }
    g_axial.fail_after_runs.store(remaining - 1);
}
const char* const kBetweennessDistances[] = {"walking", "steps", "angular", "axmeter"};
const char* const kBetweennessNormalizations[] = {"none", "standard", "freeman", "syntax"};

// Validated, R-independent inputs of a Segment Betweenness call (everything except the radius).
struct BetweennessInput {
    HPSTAGraph handle{};
    int mode = 0;
    SPSTAGraphInfo info{};
    R_xlen_t n = 0;
    AnalysisPoints points;
    CoordinateData weight_data{nullptr, nullptr};
    bool has_weights = false, has_attractions = false;
};
BetweennessInput betweenness_input(SEXP pointer, SEXP distance, SEXP weights, SEXP attractions)
{
    BetweennessInput in;
    in.handle = graph_handle(pointer);
    in.mode = named_mode(distance, kBetweennessDistances, 4, "distance");
    if (!PSTAGetGraphInfo(in.handle, &in.info)) Rf_error("PSTAGetGraphInfo failed before PSTASegmentBetweenness.");
    // Angular traversal allocates two directed states per line in signed int.
    if (in.mode == 2 && in.info.m_LineCount > static_cast<unsigned int>(std::numeric_limits<int>::max() / 2))
        Rf_error("Too many lines for angular Segment Betweenness.");
    in.n = in.info.m_LineCount;
    in.points = analysis_points(attractions, in.handle, "attraction_points");
    const R_xlen_t weight_count = attractions == R_NilValue ? in.n : in.points.count;
    in.weight_data = analysis_weights(weights, weight_count);
    in.has_weights = weights != R_NilValue;
    in.has_attractions = attractions != R_NilValue;
    return in;
}

// Native inputs of the descriptor, built once per call (not per radius).
struct BetweennessBuffers {
    // Segment Betweenness's descriptor takes interleaved doubles, whereas Reach takes double2. Preserve each exact
    // exported storage type.
    std::vector<double> coords;
    std::vector<float> native_weights;
};
BetweennessBuffers betweenness_buffers(const BetweennessInput& in)
{
    BetweennessBuffers b;
    b.coords.resize(static_cast<size_t>(in.points.count) * 2);
    for (R_xlen_t i = 0; i < in.points.count; ++i) {
        b.coords[static_cast<size_t>(i) * 2] = in.points.data.at(i);
        b.coords[static_cast<size_t>(i) * 2 + 1] = in.points.data.at(i + in.points.count);
    }
    const R_xlen_t weight_count = in.has_attractions ? in.points.count : in.n;
    b.native_weights.resize(in.has_weights ? static_cast<size_t>(weight_count) : 0);
    for (size_t i = 0; i < b.native_weights.size(); ++i)
        b.native_weights[i] = static_cast<float>(in.weight_data.at(i));
    return b;
}

// Pinned PST skips nonpositive weighted origins without writing either diagnostic. UINT_MAX cannot be a count under our
// signed graph bounds; negative infinity cannot be a depth (all native distances are >= 0).
constexpr unsigned int kBetweennessMissingCount = std::numeric_limits<unsigned int>::max();
const float kBetweennessMissingDepth = -std::numeric_limits<float>::infinity();

// The finished arrays of one PSTASegmentBetweenness run.
struct BetweennessRun {
    std::vector<float> scores, depths;
    std::vector<unsigned int> counts;
    bool written(std::size_t i) const { return counts[i] != kBetweennessMissingCount; }
};
void betweenness_run(const BetweennessInput& in, BetweennessBuffers& b, const SPSTARadii& radii, BetweennessRun& run)
{
    const R_xlen_t n = in.n;
    axial_fault_point();
    ++g_axial.betweenness_runs;
    run.scores.assign(static_cast<size_t>(n), 0.0f);
    run.depths.assign(static_cast<size_t>(n), kBetweennessMissingDepth);
    run.counts.assign(static_cast<size_t>(n), kBetweennessMissingCount);
    static const EPSTADistanceType native_distances[] = {EPSTADistanceType_Walking, EPSTADistanceType_Steps,
        EPSTADistanceType_Angular, EPSTADistanceType_Axmeter};
    SPSTASegmentBetweennessDesc desc{};
    desc.m_Graph = in.handle;
    desc.m_Radius = radii;
    desc.m_DistanceType = native_distances[in.mode];
    desc.m_Weights = in.has_weights ? b.native_weights.data() : nullptr;
    desc.m_AttractionPoints = in.has_attractions ? b.coords.data() : nullptr;
    desc.m_AttractionPointCount = static_cast<unsigned int>(in.points.count);
    desc.m_OutBetweenness = run.scores.data();
    desc.m_OutNodeCount = run.counts.data();
    desc.m_OutTotalDepth = run.depths.data();
    rpst::progress_attach(desc.m_ProgressCallback, desc.m_ProgressCallbackUser);
    if (!PSTASegmentBetweenness(&desc)) throw std::runtime_error("PSTASegmentBetweenness returned false");
    for (R_xlen_t i = 0; i < n; ++i) {
        const bool count_written = run.counts[i] != kBetweennessMissingCount;
        const bool depth_written = run.depths[i] != kBetweennessMissingDepth;
        if (count_written != depth_written)
            throw std::runtime_error("PST count/depth write masks are inconsistent");
        if (count_written && run.counts[i] > in.info.m_LineCount)
            throw std::runtime_error("PST returned an invalid node count");
        if (!count_written && !in.has_weights && !in.has_attractions)
            throw std::runtime_error("PST left unweighted diagnostics unwritten");
    }
}
// One exported PST normaliser (norm 1 standard, 2 freeman, 3 syntax) applied to a finished run; `normalized` has one entry
// per line (zero where PST wrote no diagnostics and the mode needs them).
void betweenness_normalize(int norm, const BetweennessInput& in, BetweennessRun& run, std::vector<float>& normalized)
{
    const R_xlen_t n = in.n;
    if (norm != 0) ++g_axial.betweenness_normalizations;
    normalized.assign(static_cast<size_t>(n), 0.0f);
    if (norm == 1) {
        PSTAStandardNormalize(run.scores.data(), n, normalized.data());
    } else if (norm == 2 || norm == 3) {
        // Never pass sentinels to normalization. Compact written rows, call the genuine export, and scatter in
        // original line order.
        std::vector<float> defined_scores, defined_depths;
        std::vector<unsigned int> defined_counts;
        for (R_xlen_t i = 0; i < n; ++i) {
            if (!run.written(static_cast<size_t>(i))) continue;
            defined_scores.push_back(run.scores[i]);
            defined_counts.push_back(run.counts[i]);
            defined_depths.push_back(run.depths[i]);
        }
        std::vector<float> defined_normalized(defined_scores.size());
        const auto defined_count = static_cast<unsigned int>(defined_scores.size());
        if (defined_count) {
            if (norm == 2)
                PSTABetweennessNormalize(defined_scores.data(), defined_counts.data(),
                                        defined_count, defined_normalized.data());
            else
                PSTABetweennessSyntaxNormalize(defined_scores.data(), defined_depths.data(),
                                              defined_count, defined_normalized.data());
        }
        size_t j = 0;
        for (R_xlen_t i = 0; i < n; ++i)
            if (run.written(static_cast<size_t>(i))) normalized[i] = defined_normalized[j++];
    }
}

SEXP betweenness_weighted(SEXP pointer, SEXP radius, SEXP distance, SEXP normalization, SEXP weights,
                          SEXP attractions, const StreamRequest* request)
{
    // Same validation order as ever: graph, radius, distance, normalisation, then the graph size, points and weights.
    graph_handle(pointer);
    const auto radii = shared_radii(radius);
    named_mode(distance, kBetweennessDistances, 4, "distance");
    const auto norm = named_mode(normalization, kBetweennessNormalizations, 4, "normalization");
    const auto in = betweenness_input(pointer, distance, weights, attractions);
    const R_xlen_t n = in.n;
    // The file route builds no R result vectors: columns are betweenness, node_count, total_depth (+ normalized).
    ResultStreamArgs args;
    if (request) args = result_stream_args(*request, norm == 0 ? 4 : 5);
    SEXP result = R_NilValue;
    double* out[3] = {nullptr, nullptr, nullptr};
    int* counts_out = nullptr;
    int protected_count = 0;
    if (!request) {
        result = PROTECT(Rf_allocVector(VECSXP, 4));
        for (int j : {0, 2, 3}) {
            SEXP v = PROTECT(Rf_allocVector(REALSXP, n));
            SET_VECTOR_ELT(result, j, v);
            out[j == 0 ? 0 : j - 1] = REAL(v);
            UNPROTECT(1);
        }
        SEXP count = PROTECT(Rf_allocVector(INTSXP, n));
        SET_VECTOR_ELT(result, 1, count);
        counts_out = INTEGER(count);
        protected_count = 2;
    }
    char error[512] = "";
    try {
        auto buffers = betweenness_buffers(in);
        BetweennessRun run;
        betweenness_run(in, buffers, radii, run);
        std::vector<float> normalized;
        betweenness_normalize(norm, in, run, normalized);
        if (request) {
            // Nullability follows the analysis and its parameters, not the data: node_count and total_depth are always
            // nullable (PST skips nonpositive weighted origins without writing them) and `normalized` only for the
            // Freeman/syntax modes; the raw score and the standard normalisation are never null. Native values are
            // moved as they are; a null row keeps whatever its native slot held (the UINT_MAX / -Inf sentinels of the
            // diagnostics, a zero in `normalized`), which no consumer reads.
            auto table = result_new_table(args, static_cast<size_t>(n));
            auto bits = result_validity(static_cast<size_t>(n), [&](std::size_t i) { return run.written(i); });
            result_add_float(*table, args.names[1], std::move(run.scores));
            result_add_count(*table, args.names[2], std::move(run.counts));
            result_mark_nullable(*table, bits);
            result_add_float(*table, args.names[3], std::move(run.depths));
            result_mark_nullable(*table, bits);
            if (norm != 0) {
                result_add_float(*table, args.names[4], std::move(normalized));
                if (norm == 2 || norm == 3) result_mark_nullable(*table, std::move(bits));
            }
            result_finish_and_export(args, std::move(table), error, sizeof error);
        } else {
            for (R_xlen_t i = 0; i < n; ++i) {
                const bool written = run.written(static_cast<size_t>(i));
                out[0][i] = run.scores[i];
                counts_out[i] = written ? static_cast<int>(run.counts[i]) : NA_INTEGER;
                out[1][i] = written ? run.depths[i] : NA_REAL;
                out[2][i] = (norm == 2 || norm == 3) && !written ? NA_REAL : normalized[i];
            }
        }
    } catch (const std::exception& e) {
        std::snprintf(error, sizeof(error), "PSTASegmentBetweenness failed: %s", e.what());
    } catch (...) {
        std::snprintf(error, sizeof(error), "PSTASegmentBetweenness failed with an unknown native exception.");
    }
    if (error[0]) Rf_error("%s", error);
    if (request) return Rf_ScalarReal(static_cast<double>(n));
    UNPROTECT(protected_count);
    return result;
}
} // namespace

extern "C" SEXP rpst_betweenness_weighted(SEXP pointer, SEXP radius, SEXP distance,
                                         SEXP normalization, SEXP weights, SEXP attractions)
{
    return betweenness_weighted(pointer, radius, distance, normalization, weights, attractions, nullptr);
}
extern "C" SEXP rpst_betweenness_weighted_stream(SEXP pointer, SEXP radius, SEXP distance, SEXP normalization,
    SEXP weights, SEXP attractions, SEXP stream_pointer, SEXP names, SEXP metadata_names, SEXP metadata_values,
    SEXP batch_rows)
{
    const StreamRequest request{stream_pointer, names, metadata_names, metadata_values, batch_rows};
    return betweenness_weighted(pointer, radius, distance, normalization, weights, attractions, &request);
}

extern "C" SEXP rpst_betweenness(SEXP pointer, SEXP radius, SEXP distance, SEXP normalization)
{
    return rpst_betweenness_weighted(pointer, radius, distance, normalization, R_NilValue, R_NilValue);
}

namespace {
// Complete native result of one Angular Choice run (see AngularIntegrationData). `depth_weights` is written by
// PST only when weighted and `normalized` only when a normalisation was requested; both stay zero otherwise.
struct AngularChoiceData {
    std::vector<float> scores, depths, depth_weights, normalized;
    std::vector<unsigned int> counts;
};

// The ONE expensive step: a single PSTAAngularChoice call (raw choice, counts, depths, and depth weights when weighted).
// `normalized` is left untouched. May throw; call it only inside a try block with no live R-API use.
void angular_choice_run(const SegmentOwner* owner, const SPSTARadii& radii, bool weigh_by_length,
                        AngularSettings settings, AngularChoiceData& d)
{
    const R_xlen_t n = owner->count;
    angular_fault_point();
    d.scores.assign(static_cast<size_t>(n), 0.0f);
    d.depths.assign(static_cast<size_t>(n), 0.0f);
    d.depth_weights.assign(weigh_by_length ? static_cast<size_t>(n) : 0, 0.0f);
    d.counts.assign(static_cast<size_t>(n), 0u);
    SPSTAAngularChoiceDesc desc{};
    desc.m_Graph = owner->handle;
    desc.m_Radius = radii;
    desc.m_WeighByLength = weigh_by_length;
    desc.m_AngleThreshold = settings.threshold;
    desc.m_AnglePrecision = settings.precision;
    desc.m_OutChoice = d.scores.data();
    desc.m_OutNodeCount = d.counts.data();
    desc.m_OutTotalDepth = d.depths.data();
    desc.m_OutTotalDepthWeight = weigh_by_length ? d.depth_weights.data() : nullptr;
    ++g_angular.choice_runs;
    rpst::progress_attach(desc.m_ProgressCallback, desc.m_ProgressCallbackUser);
    if (!PSTAAngularChoice(&desc)) throw std::runtime_error("PSTAAngularChoice returned false");
}

// One exported PST normaliser (1 standard, 2 turner, 3 syntax; 0 "none" writes nothing) applied to a finished run.
// Syntax normalisation reads the total depth of the run: the length-weighted total depth (depth x segment weight) for a
// length-weighted run, as the pinned PST for QGIS plugin does (angularchoiceanalysis.py, weighted branch), and the plain
// total depth otherwise. `weighted` must match the run.
void angular_choice_normalize(int norm, const AngularChoiceData& d, bool weighted, R_xlen_t n, std::vector<float>& out)
{
    out.assign(static_cast<size_t>(n), 0.0f);
    if (norm != 0) ++g_angular.choice_normalizations;
    switch (norm) {
    case 1: PSTAStandardNormalize(d.scores.data(), n, out.data()); break;
    case 2: PSTAAngularChoiceNormalize(d.scores.data(), d.counts.data(), n, out.data()); break;
    case 3: PSTAAngularChoiceSyntaxNormalize(d.scores.data(), weighted ? d.depth_weights.data() : d.depths.data(), n, out.data()); break;
    }
}

// The scalar call: one radius, at most one normalisation.
void angular_choice_compute(const SegmentOwner* owner, const SPSTARadii& radii, bool weigh_by_length, int norm,
                            AngularSettings settings, AngularChoiceData& d)
{
    angular_choice_run(owner, radii, weigh_by_length, settings, d);
    if (!weigh_by_length) d.depth_weights.assign(static_cast<size_t>(owner->count), 0.0f);  // unweighted: stays zero, never exposed
    angular_choice_normalize(norm, d, weigh_by_length, owner->count, d.normalized);
}

const char* const kAngularChoiceNormalizations[] = {"none", "standard", "turner", "syntax"};

SEXP angular_choice(SEXP pointer, SEXP radius, SEXP weighted, SEXP normalization, AngularSettings settings)
{
    const auto* owner = segment_graph_owner(pointer);
    if (owner->max_degree > 32)
        Rf_error("PSTAAngularChoice supports at most 32 endpoint incidences at a shared coordinate (native outgoing-path mask).");
    const auto radii = shared_radii(radius, true);
    if (TYPEOF(weighted) != LGLSXP || XLENGTH(weighted) != 1 || LOGICAL(weighted)[0] == NA_LOGICAL)
        Rf_error("weigh_by_length must be TRUE or FALSE.");
    const bool weigh_by_length = LOGICAL(weighted)[0];
    const auto norm = named_mode(normalization, kAngularChoiceNormalizations, 4, "normalization");
    const R_xlen_t n = owner->count;
    SEXP result = PROTECT(Rf_allocVector(VECSXP, 5));
    double* out[4];
    for (int j : {0, 2, 3, 4}) {
        SEXP v = PROTECT(Rf_allocVector(REALSXP, n));
        SET_VECTOR_ELT(result, j, v);
        out[j == 0 ? 0 : j - 1] = REAL(v);
        UNPROTECT(1);
    }
    SEXP count = PROTECT(Rf_allocVector(INTSXP, n));
    SET_VECTOR_ELT(result, 1, count);
    int* counts_out = INTEGER(count);
    char error[512] = "";
    try {
        AngularChoiceData d;
        angular_choice_compute(owner, radii, weigh_by_length, norm, settings, d);
        for (R_xlen_t i = 0; i < n; ++i) {
            out[0][i] = d.scores[i]; counts_out[i] = static_cast<int>(d.counts[i]);
            out[1][i] = d.depths[i]; out[2][i] = d.depth_weights[i]; out[3][i] = d.normalized[i];
        }
    } catch (const std::exception& e) {
        std::snprintf(error, sizeof(error), "PSTAAngularChoice failed: %s", e.what());
    } catch (...) {
        std::snprintf(error, sizeof(error), "PSTAAngularChoice failed with an unknown native exception.");
    }
    if (error[0]) Rf_error("%s", error);
    UNPROTECT(2);
    return result;
}
} // namespace
extern "C" SEXP rpst_angular_choice(SEXP pointer, SEXP radius, SEXP weighted, SEXP normalization)
{
    return angular_choice(pointer, radius, weighted, normalization, {0, 1});
}
extern "C" SEXP rpst_angular_choice_controls(SEXP pointer, SEXP radius, SEXP weighted,
    SEXP normalization, SEXP threshold, SEXP precision)
{
    segment_graph_owner(pointer);
    const auto settings = angular_settings(threshold, precision);
    return angular_choice(pointer, radius, weighted, normalization, settings);
}

// ---- file-backed (Arrow C stream) route for the angular pair ----------------------------------------------------
// The analysis runs exactly once through the SAME compute/finishing functions as the in-memory route above; only
// the destination of the finished native arrays differs (an rPSTool-owned, reference-counted ResultTable exported
// zero-copy as an Arrow C stream instead of widened R vectors). Argument validation (which may raise R errors)
// precedes every C++ owner and R errors from native failures are raised only after all owners have unwound.
extern "C" SEXP rpst_angular_integration_stream(SEXP pointer, SEXP steps, SEXP weighted, SEXP normalization,
    SEXP threshold, SEXP precision, SEXP weight_outputs, SEXP stream_pointer, SEXP names, SEXP metadata_names,
    SEXP metadata_values, SEXP batch_rows)
{
    // Same validation, in the same order, as rpst_angular_integration_controls + angular_integration.
    segment_graph_owner(pointer);
    const auto settings = angular_settings(threshold, precision);
    const bool weigh_by_length = angular_weighted(weighted);
    if (TYPEOF(weight_outputs) != LGLSXP || XLENGTH(weight_outputs) != 1 || LOGICAL(weight_outputs)[0] == NA_LOGICAL)
        Rf_error("weight_outputs must be TRUE or FALSE.");
    const char* norm_names[] = {"turner", "syntax", "hillier"};
    const int norm = named_mode(normalization, norm_names, 3, "normalization");
    const auto* owner = segment_graph_owner(pointer);
    if (owner->max_degree > 32)
        Rf_error("PSTAAngularIntegration supports at most 32 endpoint incidences at a shared coordinate (native outgoing-path mask).");
    const auto radii = analysis_radii(steps, true);
    const bool need_weights = weigh_by_length || LOGICAL(weight_outputs)[0];
    const auto args = result_stream_args(stream_pointer, names, metadata_names, metadata_values, batch_rows,
                                         need_weights ? 6 : 4);
    char error[512] = "";
    {
        try {
            AngularIntegrationData d;
            angular_integration_compute(owner, radii, weigh_by_length, norm, settings, need_weights, d);
            auto table = std::make_shared<rpst::ResultTable>();
            table->id_name = args.names[0];
            table->rows = owner->count;
            result_add_float(*table, args.names[1], std::move(d.scores));
            result_add_count(*table, args.names[2], std::move(d.counts));
            result_add_float(*table, args.names[3], std::move(d.depths));
            if (need_weights) {
                result_add_float(*table, args.names[4], std::move(d.weights));
                result_add_float(*table, args.names[5], std::move(d.depth_weights));
            }
            result_finish_and_export(args, std::move(table), error, sizeof error);
        } catch (const std::exception& e) {
            std::snprintf(error, sizeof(error), "PSTAAngularIntegration failed: %s", e.what());
        } catch (...) {
            std::snprintf(error, sizeof(error), "PSTAAngularIntegration failed with an unknown native exception.");
        }
    }
    if (error[0]) Rf_error("%s", error);
    return R_NilValue;
}

extern "C" SEXP rpst_angular_choice_stream(SEXP pointer, SEXP radius, SEXP weighted, SEXP normalization,
    SEXP threshold, SEXP precision, SEXP stream_pointer, SEXP names, SEXP metadata_names, SEXP metadata_values,
    SEXP batch_rows)
{
    // Same validation, in the same order, as rpst_angular_choice_controls + angular_choice.
    segment_graph_owner(pointer);
    const auto settings = angular_settings(threshold, precision);
    const auto* owner = segment_graph_owner(pointer);
    if (owner->max_degree > 32)
        Rf_error("PSTAAngularChoice supports at most 32 endpoint incidences at a shared coordinate (native outgoing-path mask).");
    const auto radii = shared_radii(radius, true);
    if (TYPEOF(weighted) != LGLSXP || XLENGTH(weighted) != 1 || LOGICAL(weighted)[0] == NA_LOGICAL)
        Rf_error("weigh_by_length must be TRUE or FALSE.");
    const bool weigh_by_length = LOGICAL(weighted)[0];
    const auto norm = named_mode(normalization, kAngularChoiceNormalizations, 4, "normalization");
    const auto args = result_stream_args(stream_pointer, names, metadata_names, metadata_values, batch_rows,
                                         4 + (weigh_by_length ? 1 : 0) + (norm != 0 ? 1 : 0));
    char error[512] = "";
    {
        try {
            AngularChoiceData d;
            angular_choice_compute(owner, radii, weigh_by_length, norm, settings, d);
            auto table = std::make_shared<rpst::ResultTable>();
            table->id_name = args.names[0];
            table->rows = owner->count;
            result_add_float(*table, args.names[1], std::move(d.scores));
            result_add_count(*table, args.names[2], std::move(d.counts));
            result_add_float(*table, args.names[3], std::move(d.depths));
            int next = 4;
            if (weigh_by_length) result_add_float(*table, args.names[next++], std::move(d.depth_weights));
            if (norm != 0) result_add_float(*table, args.names[next++], std::move(d.normalized));
            result_finish_and_export(args, std::move(table), error, sizeof error);
        } catch (const std::exception& e) {
            std::snprintf(error, sizeof(error), "PSTAAngularChoice failed: %s", e.what());
        } catch (...) {
            std::snprintf(error, sizeof(error), "PSTAAngularChoice failed with an unknown native exception.");
        }
    }
    if (error[0]) Rf_error("%s", error);
    return R_NilValue;
}

// ---- Multi-radius / multi-normalisation (docs/compatibility/multi-radius.md) ---------------------------------------------------
// R expands analysis_radius() into independent SCALAR configurations; every one is parsed by the unchanged scalar boundary
// (shared_radii) BEFORE the first PST call. For each radius the expensive PST analysis then runs exactly once and each
// requested exported normaliser is applied to that run's finished arrays. Only one radius' scratch is alive at a time;
// the finished columns go either into preallocated R vectors or into one rPSTool-owned ResultTable (one Arrow stream).
namespace {
// Validate the list of scalar radius configurations. Everything is R_alloc'd (reclaimed by R), so the Rf_error calls leave no
// C++ owner behind. SPSTARadii is trivially destructible.
SPSTARadii* multi_radii(SEXP list, R_xlen_t& count, bool angular_engine = true)
{
    if (TYPEOF(list) != VECSXP || XLENGTH(list) < 1) Rf_error("radius configurations must be a non-empty list of analysis_radius().");
    count = XLENGTH(list);
    auto* radii = reinterpret_cast<SPSTARadii*>(R_alloc(static_cast<size_t>(count), sizeof(SPSTARadii)));
    for (R_xlen_t i = 0; i < count; ++i) new (&radii[i]) SPSTARadii(shared_radii(VECTOR_ELT(list, i), angular_engine));
    return radii;
}
// Normalisation names (each a distinct member of `names`), as indices into `names`. R_alloc'd.
int* multi_norms(SEXP x, const char* const* names, int count, R_xlen_t& n, int first_allowed)
{
    if (TYPEOF(x) != STRSXP) Rf_error("normalization must be a character vector.");
    n = XLENGTH(x);
    auto* out = reinterpret_cast<int*>(R_alloc(static_cast<size_t>(n) + 1, sizeof(int)));
    for (R_xlen_t i = 0; i < n; ++i) {
        SEXP one = PROTECT(Rf_ScalarString(STRING_ELT(x, i)));
        out[i] = named_mode(one, names, count, "normalization");
        UNPROTECT(1);
        if (out[i] < first_allowed) Rf_error("normalization contains an entry that does not select a normaliser.");
        for (R_xlen_t j = 0; j < i; ++j)
            if (out[j] == out[i]) Rf_error("normalization must not contain duplicates.");
    }
    return out;
}

// Where the finished columns of a radius go. add_float/add_count take ownership of (or copy out of) the vector.
struct RColumnSink {
    SEXP list; R_xlen_t next = 0;
    void add_float(std::vector<float>&& v) {
        double* o = REAL(VECTOR_ELT(list, next++));
        for (size_t i = 0; i < v.size(); ++i) o[i] = v[i];
    }
    void add_count(std::vector<unsigned int>&& v) {
        int* o = INTEGER(VECTOR_ELT(list, next++));
        for (size_t i = 0; i < v.size(); ++i) o[i] = static_cast<int>(v[i]);
    }
};
struct TableColumnSink {
    rpst::ResultTable& table; const char* const* names; R_xlen_t next = 1;
    void add_float(std::vector<float>&& v) { result_add_float(table, names[next++], std::move(v)); }
    void add_count(std::vector<unsigned int>&& v) { result_add_count(table, names[next++], std::move(v)); }
};

// Per radius: choice, node_count, total_depth, [total_depth_weight], then one array per normalisation.
template <class Sink>
void angular_choice_multi_compute(const SegmentOwner* owner, const SPSTARadii* radii, R_xlen_t k, bool weighted,
                                  AngularSettings settings, const int* norms, R_xlen_t nnorms, Sink& sink)
{
    for (R_xlen_t r = 0; r < k; ++r) {
        AngularChoiceData d;
        angular_choice_run(owner, radii[r], weighted, settings, d);
        std::vector<std::vector<float>> normalized(static_cast<size_t>(nnorms));
        for (R_xlen_t j = 0; j < nnorms; ++j) angular_choice_normalize(norms[j], d, weighted, owner->count, normalized[static_cast<size_t>(j)]);
        sink.add_float(std::move(d.scores));
        sink.add_count(std::move(d.counts));
        sink.add_float(std::move(d.depths));
        if (weighted) sink.add_float(std::move(d.depth_weights));
        for (auto& v : normalized) sink.add_float(std::move(v));
    }
}
// Per radius: one array per normalisation, node_count, total_depth, [total_weight, total_depth_weight].
template <class Sink>
void angular_integration_multi_compute(const SegmentOwner* owner, const SPSTARadii* radii, R_xlen_t k, bool weighted,
                                       bool need_weights, AngularSettings settings, const int* norms, R_xlen_t nnorms,
                                       Sink& sink)
{
    for (R_xlen_t r = 0; r < k; ++r) {
        AngularIntegrationData d;
        angular_integration_run(owner, radii[r], weighted, settings, need_weights, d);
        for (R_xlen_t j = 0; j < nnorms; ++j) {
            std::vector<float> scores;
            angular_integration_normalize(norms[j], weighted, d, owner->count, scores);
            sink.add_float(std::move(scores));
        }
        sink.add_count(std::move(d.counts));
        sink.add_float(std::move(d.depths));
        if (need_weights) { sink.add_float(std::move(d.weights)); sink.add_float(std::move(d.depth_weights)); }
    }
}

struct MultiArgs {
    const SegmentOwner* owner; SPSTARadii* radii; R_xlen_t k; bool weighted; AngularSettings settings;
    int* norms; R_xlen_t nnorms; bool need_weights; R_xlen_t per_radius;
};
MultiArgs multi_args(bool choice, SEXP pointer, SEXP radii, SEXP weighted, SEXP norms, SEXP threshold, SEXP precision,
                     SEXP weight_outputs)
{
    MultiArgs a{};
    a.owner = segment_graph_owner(pointer);
    a.settings = angular_settings(threshold, precision);
    a.weighted = angular_weighted(weighted);
    if (a.owner->max_degree > 32)
        Rf_error(choice ? "PSTAAngularChoice supports at most 32 endpoint incidences at a shared coordinate (native outgoing-path mask)."
                        : "PSTAAngularIntegration supports at most 32 endpoint incidences at a shared coordinate (native outgoing-path mask).");
    if (choice) {
        a.norms = multi_norms(norms, kAngularChoiceNormalizations, 4, a.nnorms, 1);
        a.per_radius = 3 + (a.weighted ? 1 : 0) + a.nnorms;
    } else {
        if (TYPEOF(weight_outputs) != LGLSXP || XLENGTH(weight_outputs) != 1 || LOGICAL(weight_outputs)[0] == NA_LOGICAL)
            Rf_error("weight_outputs must be TRUE or FALSE.");
        static const char* const names[] = {"turner", "syntax", "hillier"};
        a.norms = multi_norms(norms, names, 3, a.nnorms, 0);
        if (a.nnorms < 1) Rf_error("normalization must name at least one normaliser.");
        a.need_weights = a.weighted || LOGICAL(weight_outputs)[0];
        a.per_radius = a.nnorms + 2 + (a.need_weights ? 2 : 0);
    }
    a.radii = multi_radii(radii, a.k);
    return a;
}
SEXP multi_result_list(const MultiArgs& a, R_xlen_t total, bool choice)
{
    SEXP result = PROTECT(Rf_allocVector(VECSXP, total));
    for (R_xlen_t r = 0; r < a.k; ++r) {
        for (R_xlen_t c = 0; c < a.per_radius; ++c) {
            // integer columns: choice -> position 1 ; integration -> position nnorms
            const bool is_count = choice ? (c == 1) : (c == a.nnorms);
            SEXP v = PROTECT(Rf_allocVector(is_count ? INTSXP : REALSXP, a.owner->count));
            SET_VECTOR_ELT(result, r * a.per_radius + c, v);
            UNPROTECT(1);
        }
    }
    UNPROTECT(1);
    return result;
}
} // namespace

extern "C" SEXP rpst_angular_choice_multi(SEXP pointer, SEXP radii, SEXP weighted, SEXP norms, SEXP threshold, SEXP precision)
{
    const MultiArgs a = multi_args(true, pointer, radii, weighted, norms, threshold, precision, R_NilValue);
    if (a.per_radius > std::numeric_limits<int>::max() / (a.k ? a.k : 1)) Rf_error("Too many result columns.");
    SEXP result = PROTECT(multi_result_list(a, a.k * a.per_radius, true));
    char error[512] = "";
    {
        try {
            RColumnSink sink{result};
            angular_choice_multi_compute(a.owner, a.radii, a.k, a.weighted, a.settings, a.norms, a.nnorms, sink);
        } catch (const std::exception& e) {
            std::snprintf(error, sizeof(error), "PSTAAngularChoice failed: %s", e.what());
        } catch (...) {
            std::snprintf(error, sizeof(error), "PSTAAngularChoice failed with an unknown native exception.");
        }
    }
    if (error[0]) Rf_error("%s", error);
    UNPROTECT(1);
    return result;
}
extern "C" SEXP rpst_angular_integration_multi(SEXP pointer, SEXP radii, SEXP weighted, SEXP norms, SEXP threshold,
    SEXP precision, SEXP weight_outputs)
{
    const MultiArgs a = multi_args(false, pointer, radii, weighted, norms, threshold, precision, weight_outputs);
    if (a.per_radius > std::numeric_limits<int>::max() / (a.k ? a.k : 1)) Rf_error("Too many result columns.");
    SEXP result = PROTECT(multi_result_list(a, a.k * a.per_radius, false));
    char error[512] = "";
    {
        try {
            RColumnSink sink{result};
            angular_integration_multi_compute(a.owner, a.radii, a.k, a.weighted, a.need_weights, a.settings, a.norms,
                                              a.nnorms, sink);
        } catch (const std::exception& e) {
            std::snprintf(error, sizeof(error), "PSTAAngularIntegration failed: %s", e.what());
        } catch (...) {
            std::snprintf(error, sizeof(error), "PSTAAngularIntegration failed with an unknown native exception.");
        }
    }
    if (error[0]) Rf_error("%s", error);
    UNPROTECT(1);
    return result;
}
extern "C" SEXP rpst_angular_choice_multi_stream(SEXP pointer, SEXP radii, SEXP weighted, SEXP norms, SEXP threshold,
    SEXP precision, SEXP stream_pointer, SEXP names, SEXP metadata_names, SEXP metadata_values, SEXP batch_rows)
{
    const MultiArgs a = multi_args(true, pointer, radii, weighted, norms, threshold, precision, R_NilValue);
    if (a.per_radius > std::numeric_limits<int>::max() / (a.k ? a.k : 1) - 1) Rf_error("Too many result columns.");
    const auto args = result_stream_args(stream_pointer, names, metadata_names, metadata_values, batch_rows,
                                         1 + a.k * a.per_radius);
    char error[512] = "";
    {
        try {
            auto table = result_new_table(args, a.owner->count);
            TableColumnSink sink{*table, args.names};
            angular_choice_multi_compute(a.owner, a.radii, a.k, a.weighted, a.settings, a.norms, a.nnorms, sink);
            result_finish_and_export(args, std::move(table), error, sizeof error);
        } catch (const std::exception& e) {
            std::snprintf(error, sizeof(error), "PSTAAngularChoice failed: %s", e.what());
        } catch (...) {
            std::snprintf(error, sizeof(error), "PSTAAngularChoice failed with an unknown native exception.");
        }
    }
    if (error[0]) Rf_error("%s", error);
    return R_NilValue;
}
extern "C" SEXP rpst_angular_integration_multi_stream(SEXP pointer, SEXP radii, SEXP weighted, SEXP norms, SEXP threshold,
    SEXP precision, SEXP weight_outputs, SEXP stream_pointer, SEXP names, SEXP metadata_names, SEXP metadata_values,
    SEXP batch_rows)
{
    const MultiArgs a = multi_args(false, pointer, radii, weighted, norms, threshold, precision, weight_outputs);
    if (a.per_radius > std::numeric_limits<int>::max() / (a.k ? a.k : 1) - 1) Rf_error("Too many result columns.");
    const auto args = result_stream_args(stream_pointer, names, metadata_names, metadata_values, batch_rows,
                                         1 + a.k * a.per_radius);
    char error[512] = "";
    {
        try {
            auto table = result_new_table(args, a.owner->count);
            TableColumnSink sink{*table, args.names};
            angular_integration_multi_compute(a.owner, a.radii, a.k, a.weighted, a.need_weights, a.settings, a.norms,
                                              a.nnorms, sink);
            result_finish_and_export(args, std::move(table), error, sizeof error);
        } catch (const std::exception& e) {
            std::snprintf(error, sizeof(error), "PSTAAngularIntegration failed: %s", e.what());
        } catch (...) {
            std::snprintf(error, sizeof(error), "PSTAAngularIntegration failed with an unknown native exception.");
        }
    }
    if (error[0]) Rf_error("%s", error);
    return R_NilValue;
}

// ---- Multi-radius Network Reach and Segment Betweenness (axial graphs) ---------------------------------------------------
// Same contract as the angular layer above: every radius configuration is parsed before the first PST call, PST runs once
// per radius, and each requested exported normaliser is applied to that run. Only one radius' scratch is alive at a time;
// the finished columns of ALL radii are retained, either in preallocated R vectors or in one ResultTable (one Arrow
// stream), so the result storage grows with the number of radii.
namespace {
// Column sink of the in-memory route: preallocated R vectors; a null validity bit becomes NA.
struct NullableRSink {
    SEXP list; R_xlen_t next = 0;
    void add_float(std::vector<float>&& v, const std::vector<std::uint8_t>* valid) {
        double* o = REAL(VECTOR_ELT(list, next++));
        for (size_t i = 0; i < v.size(); ++i)
            o[i] = (valid && !((*valid)[i >> 3] & (1u << (i & 7)))) ? NA_REAL : static_cast<double>(v[i]);
    }
    void add_count(std::vector<unsigned int>&& v, const std::vector<std::uint8_t>* valid) {
        int* o = INTEGER(VECTOR_ELT(list, next++));
        for (size_t i = 0; i < v.size(); ++i)
            o[i] = (valid && !((*valid)[i >> 3] & (1u << (i & 7)))) ? NA_INTEGER : static_cast<int>(v[i]);
    }
    void add_signed(std::vector<int>&& v) {   // native signed values (such as -1 = none) are written unchanged, never null
        int* o = INTEGER(VECTOR_ELT(list, next++));
        for (size_t i = 0; i < v.size(); ++i) o[i] = v[i];
    }
};
// Column sink of the file route: moves the native arrays into the result owner, marking nullable columns.
struct NullableTableSink {
    rpst::ResultTable& table; const char* const* names; R_xlen_t next = 1;
    void add_float(std::vector<float>&& v, const std::vector<std::uint8_t>* valid) {
        result_add_float(table, names[next++], std::move(v));
        if (valid) result_mark_nullable(table, *valid);
    }
    void add_count(std::vector<unsigned int>&& v, const std::vector<std::uint8_t>* valid) {
        result_add_count(table, names[next++], std::move(v));
        if (valid) result_mark_nullable(table, *valid);
    }
    void add_signed(std::vector<int>&& v) { result_add_signed(table, names[next++], std::move(v)); }
};
// Result vectors of the in-memory route: `count_position` is the column of each radius that holds integers.
SEXP multi_plain_list(R_xlen_t k, R_xlen_t per_radius, R_xlen_t rows, R_xlen_t count_position)
{
    if (per_radius > std::numeric_limits<int>::max() / (k ? k : 1)) Rf_error("Too many result columns.");
    SEXP result = PROTECT(Rf_allocVector(VECSXP, k * per_radius));
    for (R_xlen_t r = 0; r < k; ++r)
        for (R_xlen_t c = 0; c < per_radius; ++c) {
            SEXP v = PROTECT(Rf_allocVector(c == count_position ? INTSXP : REALSXP, rows));
            SET_VECTOR_ELT(result, r * per_radius + c, v);
            UNPROTECT(1);
        }
    UNPROTECT(1);
    return result;
}

struct BetweennessMulti {
    BetweennessInput in; SPSTARadii* radii; R_xlen_t k; int* norms; R_xlen_t nnorms; R_xlen_t per_radius;
};
// Per radius: betweenness, node_count, total_depth, then one array per requested normaliser. Freeman and syntax values are
// null where PST wrote no diagnostics, exactly as in a scalar call.
template <class Sink>
void betweenness_multi_compute(const BetweennessMulti& a, BetweennessBuffers& buffers, Sink& sink)
{
    for (R_xlen_t r = 0; r < a.k; ++r) {
        BetweennessRun run;
        betweenness_run(a.in, buffers, a.radii[r], run);
        std::vector<std::vector<float>> normalized(static_cast<size_t>(a.nnorms));
        for (R_xlen_t j = 0; j < a.nnorms; ++j) betweenness_normalize(a.norms[j], a.in, run, normalized[static_cast<size_t>(j)]);
        const auto bits = result_validity(static_cast<size_t>(a.in.n), [&](std::size_t i) { return run.written(i); });
        sink.add_float(std::move(run.scores), nullptr);
        sink.add_count(std::move(run.counts), &bits);
        sink.add_float(std::move(run.depths), &bits);
        for (R_xlen_t j = 0; j < a.nnorms; ++j)
            sink.add_float(std::move(normalized[static_cast<size_t>(j)]), (a.norms[j] == 2 || a.norms[j] == 3) ? &bits : nullptr);
    }
}
// `norms` lists the requested normalisers other than "none" (R drops "none": the raw score is always returned).
BetweennessMulti betweenness_multi_args(SEXP pointer, SEXP radii, SEXP distance, SEXP norms, SEXP weights, SEXP attractions)
{
    BetweennessMulti a{};
    graph_handle(pointer);
    a.radii = multi_radii(radii, a.k, false);
    named_mode(distance, kBetweennessDistances, 4, "distance");
    a.norms = multi_norms(norms, kBetweennessNormalizations, 4, a.nnorms, 1);
    a.in = betweenness_input(pointer, distance, weights, attractions);
    a.per_radius = 3 + a.nnorms;
    return a;
}
} // namespace

extern "C" SEXP rpst_betweenness_multi(SEXP pointer, SEXP radii, SEXP distance, SEXP norms, SEXP weights, SEXP attractions)
{
    auto a = betweenness_multi_args(pointer, radii, distance, norms, weights, attractions);
    SEXP result = PROTECT(multi_plain_list(a.k, a.per_radius, a.in.n, 1));
    char error[512] = "";
    try {
        auto buffers = betweenness_buffers(a.in);
        NullableRSink sink{result};
        betweenness_multi_compute(a, buffers, sink);
    } catch (const std::exception& e) {
        std::snprintf(error, sizeof(error), "PSTASegmentBetweenness failed: %s", e.what());
    } catch (...) {
        std::snprintf(error, sizeof(error), "PSTASegmentBetweenness failed with an unknown native exception.");
    }
    if (error[0]) Rf_error("%s", error);
    UNPROTECT(1);
    return result;
}
extern "C" SEXP rpst_betweenness_multi_stream(SEXP pointer, SEXP radii, SEXP distance, SEXP norms, SEXP weights,
    SEXP attractions, SEXP stream_pointer, SEXP names, SEXP metadata_names, SEXP metadata_values, SEXP batch_rows)
{
    auto a = betweenness_multi_args(pointer, radii, distance, norms, weights, attractions);
    if (a.per_radius > std::numeric_limits<int>::max() / (a.k ? a.k : 1) - 1) Rf_error("Too many result columns.");
    const auto args = result_stream_args(stream_pointer, names, metadata_names, metadata_values, batch_rows,
                                         1 + a.k * a.per_radius);
    char error[512] = "";
    try {
        auto buffers = betweenness_buffers(a.in);
        auto table = result_new_table(args, static_cast<size_t>(a.in.n));
        NullableTableSink sink{*table, args.names};
        betweenness_multi_compute(a, buffers, sink);
        result_finish_and_export(args, std::move(table), error, sizeof error);
    } catch (const std::exception& e) {
        std::snprintf(error, sizeof(error), "PSTASegmentBetweenness failed: %s", e.what());
    } catch (...) {
        std::snprintf(error, sizeof(error), "PSTASegmentBetweenness failed with an unknown native exception.");
    }
    if (error[0]) Rf_error("%s", error);
    return Rf_ScalarReal(static_cast<double>(a.in.n));
}

namespace {
struct ReachMulti {
    HPSTAGraph handle{}; SPSTARadii* radii = nullptr; R_xlen_t k = 0; AnalysisPoints points; R_xlen_t n = 0; bool has_origins = false;
};
ReachMulti reach_multi_args(SEXP pointer, SEXP radii, SEXP origins)
{
    ReachMulti a;
    a.handle = graph_handle(pointer);
    a.radii = multi_radii(radii, a.k, false);
    SPSTAGraphInfo info{};
    if (!PSTAGetGraphInfo(a.handle, &info)) Rf_error("PSTAGetGraphInfo failed before PSTAReach.");
    a.points = analysis_points(origins, a.handle, "origins");
    a.has_origins = origins != R_NilValue;
    a.n = a.has_origins ? a.points.count : info.m_LineCount;
    return a;
}
// Per radius: reached_count, reached_length, reached_area.
template <class Sink>
void reach_multi_compute(const ReachMulti& a, Sink& sink)
{
    auto coords = copy_analysis_points(a.points);
    for (R_xlen_t r = 0; r < a.k; ++r) {
        axial_fault_point();
        ++g_axial.reach_runs;
        std::vector<unsigned int> counts(static_cast<size_t>(a.n));
        std::vector<float> lengths(static_cast<size_t>(a.n)), areas(static_cast<size_t>(a.n));
        SPSTAReachDesc desc{};
        desc.m_Graph = a.handle;
        desc.m_Radius = a.radii[r];
        desc.m_OriginCoords = a.has_origins ? coords.data() : nullptr;
        desc.m_OriginCount = static_cast<unsigned int>(a.points.count);
        desc.m_OutReachedCount = counts.data();
        desc.m_OutReachedLength = lengths.data();
        desc.m_OutReachedArea = areas.data();
        rpst::progress_attach(desc.m_ProgressCallback, desc.m_ProgressCallbackUser);
        if (!PSTAReach(&desc)) throw std::runtime_error("PSTAReach returned false");
        sink.add_count(std::move(counts), nullptr);
        sink.add_float(std::move(lengths), nullptr);
        sink.add_float(std::move(areas), nullptr);
    }
}
} // namespace

// ---- Multi-radius Network Integration (axial graphs) ---------------------------------------------------------------------------
// Same contract as above. Junction positions do not depend on the radius: they are taken from the first run and every later run
// is checked to have produced identical coordinates; only the junction scores are per radius. Junction results exist only on the
// in-memory route (a result file cannot hold them, as for a scalar call).
namespace {
struct IntegrationMulti {
    HPSTAGraph handle{}; SPSTARadii* radii = nullptr; R_xlen_t k = 0; R_xlen_t n = 0; R_xlen_t junction_count = 0;
};
IntegrationMulti integration_multi_args(SEXP pointer, SEXP radii, bool junctions)
{
    IntegrationMulti a;
    a.handle = graph_handle(pointer);
    a.radii = multi_radii(radii, a.k, false);
    SPSTAGraphInfo info{};
    info.m_Version = SPSTAGraphInfo::VERSION;
    if (!PSTAGetGraphInfo(a.handle, &info)) Rf_error("PSTAGetGraphInfo failed before PSTANetworkIntegration.");
    if (info.m_LineCount > static_cast<unsigned int>(std::numeric_limits<int>::max()))
        Rf_error("Too many lines for PSTANetworkIntegration.");
    a.n = info.m_LineCount;
    if (junctions && info.m_CrossingCount > static_cast<unsigned int>(std::numeric_limits<int>::max()))
        Rf_error("Too many junctions for PSTANetworkIntegration.");
    a.junction_count = junctions ? info.m_CrossingCount : 0;
    return a;
}
// Per radius: integration, node_count, total_depth. `on_junctions(r, coords, scores)` receives each radius' junction results.
template <class Sink, class JunctionFn>
void integration_multi_compute(const IntegrationMulti& a, Sink& sink, JunctionFn on_junctions)
{
    std::vector<double2> first_coords;
    for (R_xlen_t r = 0; r < a.k; ++r) {
        axial_fault_point();
        ++g_axial.integration_runs;
        std::vector<float> scores(static_cast<size_t>(a.n)), depths(static_cast<size_t>(a.n));
        std::vector<unsigned int> counts(static_cast<size_t>(a.n));
        std::vector<float> junction_scores(static_cast<size_t>(a.junction_count), 0);   // PST accumulates; zero is the fresh seed
        std::vector<double2> junction_coords(static_cast<size_t>(a.junction_count));
        SPSTANetworkIntegrationDesc desc{};
        desc.m_Version = SPSTANetworkIntegrationDesc::VERSION;
        desc.m_Graph = a.handle;
        desc.m_Radius = a.radii[r];
        desc.m_OutJunctionCount = static_cast<unsigned int>(a.junction_count);
        desc.m_OutJunctionCoords = a.junction_count ? junction_coords.data() : nullptr;
        desc.m_OutJunctionScores = a.junction_count ? junction_scores.data() : nullptr;
        desc.m_OutLineIntegration = scores.data();
        desc.m_OutLineNodeCount = counts.data();
        desc.m_OutLineTotalDepth = depths.data();
        rpst::progress_attach(desc.m_ProgressCallback, desc.m_ProgressCallbackUser);
        if (!PSTANetworkIntegration(&desc)) throw std::runtime_error("PSTANetworkIntegration failed for the native pst_graph.");
        if (a.junction_count) {
            if (r == 0) first_coords = junction_coords;
            else if (std::memcmp(first_coords.data(), junction_coords.data(), first_coords.size() * sizeof(double2)) != 0)
                throw std::runtime_error("PST returned different junction coordinates for different radii");
            on_junctions(r, first_coords, junction_scores);
        }
        sink.add_float(std::move(scores), nullptr);
        sink.add_count(std::move(counts), nullptr);
        sink.add_float(std::move(depths), nullptr);
    }
}
} // namespace

// Returns list(line columns (3 per radius, radius-major), junction coordinate matrix or NULL, list of per-radius junction scores or NULL).
extern "C" SEXP rpst_network_integration_multi(SEXP pointer, SEXP radii, SEXP junctions_arg)
{
    if (TYPEOF(junctions_arg) != LGLSXP || XLENGTH(junctions_arg) != 1 || LOGICAL(junctions_arg)[0] == NA_LOGICAL)
        Rf_error("junctions must be TRUE or FALSE.");
    const bool junctions = LOGICAL(junctions_arg)[0] == TRUE;
    const auto a = integration_multi_args(pointer, radii, junctions);
    SEXP out = PROTECT(Rf_allocVector(VECSXP, 3));
    SEXP lines = PROTECT(multi_plain_list(a.k, 3, a.n, 1));
    SET_VECTOR_ELT(out, 0, lines);
    UNPROTECT(1);
    double* coords_data = nullptr;
    SEXP score_list = R_NilValue;
    if (junctions) {
        SEXP coords = PROTECT(Rf_allocMatrix(REALSXP, static_cast<int>(a.junction_count), 2));
        SET_VECTOR_ELT(out, 1, coords);
        UNPROTECT(1);
        coords_data = REAL(coords);
        score_list = PROTECT(Rf_allocVector(VECSXP, a.k));
        SET_VECTOR_ELT(out, 2, score_list);
        UNPROTECT(1);
        for (R_xlen_t r = 0; r < a.k; ++r) {
            SEXP v = PROTECT(Rf_allocVector(REALSXP, a.junction_count));
            SET_VECTOR_ELT(score_list, r, v);
            UNPROTECT(1);
        }
    }
    char error[512] = "";
    try {
        NullableRSink sink{lines};
        integration_multi_compute(a, sink, [&](R_xlen_t r, const std::vector<double2>& coords, const std::vector<float>& scores) {
            double* o = REAL(VECTOR_ELT(score_list, r));
            for (R_xlen_t i = 0; i < a.junction_count; ++i) {
                if (r == 0) {
                    coords_data[i] = coords[static_cast<size_t>(i)].x;
                    coords_data[i + a.junction_count] = coords[static_cast<size_t>(i)].y;
                }
                o[i] = scores[static_cast<size_t>(i)];
            }
        });
    } catch (const std::exception& e) {
        std::snprintf(error, sizeof(error), "PSTANetworkIntegration failed: %s", e.what());
    } catch (...) {
        std::snprintf(error, sizeof(error), "PSTANetworkIntegration failed with an unknown native exception.");
    }
    if (error[0]) Rf_error("%s", error);
    UNPROTECT(1);
    return out;
}
extern "C" SEXP rpst_network_integration_multi_stream(SEXP pointer, SEXP radii, SEXP stream_pointer, SEXP names,
    SEXP metadata_names, SEXP metadata_values, SEXP batch_rows)
{
    const auto a = integration_multi_args(pointer, radii, false);
    if (3 > std::numeric_limits<int>::max() / (a.k ? a.k : 1) - 1) Rf_error("Too many result columns.");
    const auto args = result_stream_args(stream_pointer, names, metadata_names, metadata_values, batch_rows, 1 + a.k * 3);
    char error[512] = "";
    try {
        auto table = result_new_table(args, static_cast<size_t>(a.n));
        NullableTableSink sink{*table, args.names};
        integration_multi_compute(a, sink, [](R_xlen_t, const std::vector<double2>&, const std::vector<float>&) {});
        result_finish_and_export(args, std::move(table), error, sizeof error);
    } catch (const std::exception& e) {
        std::snprintf(error, sizeof(error), "PSTANetworkIntegration failed: %s", e.what());
    } catch (...) {
        std::snprintf(error, sizeof(error), "PSTANetworkIntegration failed with an unknown native exception.");
    }
    if (error[0]) Rf_error("%s", error);
    return Rf_ScalarReal(static_cast<double>(a.n));
}

extern "C" SEXP rpst_reach_multi(SEXP pointer, SEXP radii, SEXP origins)
{
    const auto a = reach_multi_args(pointer, radii, origins);
    SEXP result = PROTECT(multi_plain_list(a.k, 3, a.n, 0));
    char error[512] = "";
    try {
        NullableRSink sink{result};
        reach_multi_compute(a, sink);
    } catch (const std::exception& e) {
        std::snprintf(error, sizeof(error), "PSTAReach failed: %s", e.what());
    } catch (...) {
        std::snprintf(error, sizeof(error), "PSTAReach failed with an unknown native exception.");
    }
    if (error[0]) Rf_error("%s", error);
    UNPROTECT(1);
    return result;
}
extern "C" SEXP rpst_reach_multi_stream(SEXP pointer, SEXP radii, SEXP origins, SEXP stream_pointer, SEXP names,
    SEXP metadata_names, SEXP metadata_values, SEXP batch_rows)
{
    const auto a = reach_multi_args(pointer, radii, origins);
    if (3 > std::numeric_limits<int>::max() / (a.k ? a.k : 1) - 1) Rf_error("Too many result columns.");
    const auto args = result_stream_args(stream_pointer, names, metadata_names, metadata_values, batch_rows, 1 + a.k * 3);
    char error[512] = "";
    try {
        auto table = result_new_table(args, static_cast<size_t>(a.n));
        NullableTableSink sink{*table, args.names};
        reach_multi_compute(a, sink);
        result_finish_and_export(args, std::move(table), error, sizeof error);
    } catch (const std::exception& e) {
        std::snprintf(error, sizeof(error), "PSTAReach failed: %s", e.what());
    } catch (...) {
        std::snprintf(error, sizeof(error), "PSTAReach failed with an unknown native exception.");
    }
    if (error[0]) Rf_error("%s", error);
    return Rf_ScalarReal(static_cast<double>(a.n));
}
// Test-only: PST runs / normaliser calls since the last reset (choice runs, choice normalisers, integration runs,
// integration normalisers), and a countdown that makes the PST analysis after `after` further runs fail (-1 disarms).
// Arguments are validated before anything changes: `reset` is TRUE or FALSE, `fail_after` is NULL (leave unchanged) or one whole
// number from -1 to INT_MAX.
extern "C" SEXP rpst_angular_instrumentation(SEXP reset, SEXP fail_after)
{
    if (TYPEOF(reset) != LGLSXP || XLENGTH(reset) != 1 || LOGICAL(reset)[0] == NA_LOGICAL)
        Rf_error("reset must be TRUE or FALSE.");
    int arm = 0;
    bool set_fault = false;
    if (fail_after != R_NilValue) {
        if (TYPEOF(fail_after) != REALSXP || XLENGTH(fail_after) != 1)
            Rf_error("fail_after must be NULL or one whole number from -1 to 2147483647.");
        const double k = REAL(fail_after)[0];
        if (!std::isfinite(k) || k < -1 || k > std::numeric_limits<int>::max() || std::floor(k) != k)
            Rf_error("fail_after must be NULL or one whole number from -1 to 2147483647.");
        arm = static_cast<int>(k);
        set_fault = true;
    }
    SEXP out = PROTECT(Rf_allocVector(REALSXP, 4));
    REAL(out)[0] = static_cast<double>(g_angular.choice_runs.load());
    REAL(out)[1] = static_cast<double>(g_angular.choice_normalizations.load());
    REAL(out)[2] = static_cast<double>(g_angular.integration_runs.load());
    REAL(out)[3] = static_cast<double>(g_angular.integration_normalizations.load());
    if (LOGICAL(reset)[0] == TRUE) {
        g_angular.choice_runs = 0; g_angular.choice_normalizations = 0;
        g_angular.integration_runs = 0; g_angular.integration_normalizations = 0;
    }
    if (set_fault) g_angular.fail_after_runs.store(arm);
    UNPROTECT(1);
    return out;
}

// Test-only counterpart of rpst_angular_instrumentation for the axial analyses: returns c(reach runs, betweenness runs, betweenness
// normaliser calls, multi-radius network integration runs, then multi-radius attraction reach, attraction distance and OD betweenness runs) and optionally resets them and arms the one-shot failure countdown (-1 disarms). Arguments are validated first.
extern "C" SEXP rpst_axial_instrumentation(SEXP reset, SEXP fail_after)
{
    if (TYPEOF(reset) != LGLSXP || XLENGTH(reset) != 1 || LOGICAL(reset)[0] == NA_LOGICAL)
        Rf_error("reset must be TRUE or FALSE.");
    int arm = 0;
    bool set_fault = false;
    if (fail_after != R_NilValue) {
        if (TYPEOF(fail_after) != REALSXP || XLENGTH(fail_after) != 1)
            Rf_error("fail_after must be NULL or one whole number from -1 to 2147483647.");
        const double k = REAL(fail_after)[0];
        if (!std::isfinite(k) || k < -1 || k > std::numeric_limits<int>::max() || std::floor(k) != k)
            Rf_error("fail_after must be NULL or one whole number from -1 to 2147483647.");
        arm = static_cast<int>(k);
        set_fault = true;
    }
    SEXP out = PROTECT(Rf_allocVector(REALSXP, 7));
    REAL(out)[0] = static_cast<double>(g_axial.reach_runs.load());
    REAL(out)[1] = static_cast<double>(g_axial.betweenness_runs.load());
    REAL(out)[2] = static_cast<double>(g_axial.betweenness_normalizations.load());
    REAL(out)[3] = static_cast<double>(g_axial.integration_runs.load());
    REAL(out)[4] = static_cast<double>(g_axial.attraction_reach_runs.load());
    REAL(out)[5] = static_cast<double>(g_axial.attraction_distance_runs.load());
    REAL(out)[6] = static_cast<double>(g_axial.od_runs.load());
    if (LOGICAL(reset)[0] == TRUE) {
        g_axial.reach_runs = 0; g_axial.betweenness_runs = 0; g_axial.betweenness_normalizations = 0;
        g_axial.integration_runs = 0; g_axial.attraction_reach_runs = 0; g_axial.attraction_distance_runs = 0;
        g_axial.od_runs = 0;
    }
    if (set_fault) g_axial.fail_after_runs.store(arm);
    UNPROTECT(1);
    return out;
}

extern "C" SEXP rpst_radius_validate(SEXP radius)
{
    shared_radii(radius);
    return R_NilValue;
}

// Segment grouping consumes only the segment owner, never an axial handle.
namespace {
struct GroupingArgs {
    float threshold = 0;
    bool split_at_junctions = false;
};
// Argument validation shared by the in-memory and the file route (same checks, same order, same messages). May raise R errors,
// so it runs before any C++ owner exists.
GroupingArgs grouping_args(SEXP angle, SEXP split)
{
    if ((TYPEOF(angle) != REALSXP && TYPEOF(angle) != INTSXP) || XLENGTH(angle) != 1)
        Rf_error("angle_threshold must be one finite non-negative native float value in degrees.");
    const double threshold = TYPEOF(angle) == REALSXP ? REAL(angle)[0] :
        (INTEGER(angle)[0] == NA_INTEGER ? NA_REAL : INTEGER(angle)[0]);
    if (!std::isfinite(threshold) || threshold < 0 ||
        threshold > std::numeric_limits<float>::max() ||
        (threshold > 0 && static_cast<float>(threshold) == 0))
        Rf_error("angle_threshold must be one finite non-negative native float value in degrees.");
    if (TYPEOF(split) != LGLSXP || XLENGTH(split) != 1 || LOGICAL(split)[0] == NA_LOGICAL)
        Rf_error("split_at_junctions must be TRUE or FALSE.");
    GroupingArgs a;
    a.threshold = static_cast<float>(threshold);
    a.split_at_junctions = LOGICAL(split)[0];
    return a;
}
// The native result of the ONE PSTASegmentGrouping call: zero-based group and colour indices per segment (unchanged from PST)
// and the two counts. Both routes consume exactly this.
struct GroupingData {
    std::vector<unsigned int> ids, colors;
    unsigned int groups = 0, color_count = 0;
};
// The PST call plus the existing range validation. Throws; never calls the R API.
void segment_grouping_compute(const SegmentOwner* owner, const GroupingArgs& a, GroupingData& d)
{
    const R_xlen_t n = owner->count;
    d.ids.assign(static_cast<std::size_t>(n), 0u);
    d.colors.assign(static_cast<std::size_t>(n), 0u);
    SPSTASegmentGroupingDesc desc{};
    desc.m_SegmentGraph = owner->handle;
    desc.m_AngleThresholdDegrees = a.threshold;
    desc.m_SplitGroupsAtJunctions = a.split_at_junctions;
    desc.m_LineCount = owner->count;
    desc.m_OutGroupIdPerLine = d.ids.data();
    desc.m_OutColorPerLine = d.colors.data();
    if (!PSTASegmentGrouping(&desc)) throw std::runtime_error("PSTASegmentGrouping returned false");
    if (!desc.m_OutGroupCount || desc.m_OutGroupCount > owner->count ||
        !desc.m_OutColorCount || desc.m_OutColorCount > desc.m_OutGroupCount)
        throw std::runtime_error("PST returned invalid group/color counts");
    for (R_xlen_t i = 0; i < n; ++i)
        if (d.ids[static_cast<std::size_t>(i)] >= desc.m_OutGroupCount || d.colors[static_cast<std::size_t>(i)] >= desc.m_OutColorCount)
            throw std::runtime_error("PST returned invalid group/color indices");
    d.groups = desc.m_OutGroupCount;
    d.color_count = desc.m_OutColorCount;
}
}  // namespace

extern "C" SEXP rpst_segment_grouping(SEXP pointer, SEXP angle, SEXP split)
{
    const auto* owner = segment_graph_owner(pointer);
    const GroupingArgs args = grouping_args(angle, split);
    const R_xlen_t n = owner->count;
    SEXP result = PROTECT(Rf_allocVector(VECSXP, 4));
    SEXP ids = PROTECT(Rf_allocVector(INTSXP, n));
    SEXP colors = PROTECT(Rf_allocVector(INTSXP, n));
    SEXP group_count = PROTECT(Rf_ScalarInteger(0));
    SEXP color_count = PROTECT(Rf_ScalarInteger(0));
    SET_VECTOR_ELT(result, 0, ids); SET_VECTOR_ELT(result, 1, colors);
    SET_VECTOR_ELT(result, 2, group_count); SET_VECTOR_ELT(result, 3, color_count);
    int* ids_out = INTEGER(ids); int* colors_out = INTEGER(colors);
    int* groups_out = INTEGER(group_count); int* color_count_out = INTEGER(color_count);
    char error[512] = "";
    try {
        GroupingData d;
        segment_grouping_compute(owner, args, d);
        for (R_xlen_t i = 0; i < n; ++i) {
            ids_out[i] = static_cast<int>(d.ids[static_cast<std::size_t>(i)] + 1);
            colors_out[i] = static_cast<int>(d.colors[static_cast<std::size_t>(i)] + 1);
        }
        *groups_out = static_cast<int>(d.groups);
        *color_count_out = static_cast<int>(d.color_count);
    } catch (const std::exception& e) {
        std::snprintf(error, sizeof(error), "PSTASegmentGrouping failed: %s", e.what());
    } catch (...) {
        std::snprintf(error, sizeof(error), "PSTASegmentGrouping failed with an unknown native exception.");
    }
    if (error[0]) Rf_error("%s", error);
    UNPROTECT(5);
    return result;
}

// File route: the SAME single PST call, exported as an rPSTool-owned Arrow stream instead of R vectors. The native
// zero-based buffers are moved into the result table and shifted to the public one-based convention IN PLACE (no second
// buffer); the two scalars, known only after PST has run, become schema metadata `rpst:n_groups` / `rpst:n_colors`.
extern "C" SEXP rpst_segment_grouping_stream(SEXP pointer, SEXP angle, SEXP split, SEXP stream_pointer, SEXP names,
                                             SEXP metadata_names, SEXP metadata_values, SEXP batch_rows)
{
    const auto* owner = segment_graph_owner(pointer);
    const GroupingArgs grouping = grouping_args(angle, split);
    const auto args = result_stream_args(stream_pointer, names, metadata_names, metadata_values, batch_rows, 3);
    char error[512] = "";
    {
        try {
            GroupingData d;
            segment_grouping_compute(owner, grouping, d);
            // validated: every index < groups/colors <= segment count <= INT_MAX, so +1 cannot leave int32 range
            for (auto& v : d.ids) ++v;
            for (auto& v : d.colors) ++v;
            auto table = std::make_shared<rpst::ResultTable>();
            table->id_name = args.names[0];
            table->rows = owner->count;
            result_add_count(*table, args.names[1], std::move(d.ids));
            result_add_count(*table, args.names[2], std::move(d.colors));
            table->metadata.emplace_back("rpst:n_groups", std::to_string(d.groups));
            table->metadata.emplace_back("rpst:n_colors", std::to_string(d.color_count));
            result_finish_and_export(args, std::move(table), error, sizeof error);
        } catch (const std::exception& e) {
            std::snprintf(error, sizeof(error), "PSTASegmentGrouping failed: %s", e.what());
        } catch (...) {
            std::snprintf(error, sizeof(error), "PSTASegmentGrouping failed with an unknown native exception.");
        }
    }
    if (error[0]) Rf_error("%s", error);
    return R_NilValue;
}

namespace {
struct GroupOwner {
    HPSTASegmentGroupGraph handle = nullptr;
    unsigned int count = 0;
};
double group_created = 0, group_freed = 0;
SEXP group_graph_tag() { return Rf_install("rPST::HPSTASegmentGroupGraph/v1"); }
void group_graph_finalizer(SEXP pointer)
{
    auto* owner = static_cast<GroupOwner*>(R_ExternalPtrAddr(pointer));
    if (!owner) return;
    R_ClearExternalPtr(pointer);
    if (owner->handle) {
        PSTAFreeSegmentGroupGraph(owner->handle);
        ++group_freed;
    }
    delete owner;
}
GroupOwner* group_graph_owner(SEXP pointer, bool require_live = true)
{
    if (TYPEOF(pointer) != EXTPTRSXP || R_ExternalPtrTag(pointer) != group_graph_tag())
        Rf_error("Invalid pst_segment_group_graph native pointer; construct it with segment_group_graph().");
    auto* owner = static_cast<GroupOwner*>(R_ExternalPtrAddr(pointer));
    if (require_live && (!owner || !owner->handle))
        Rf_error("The pst_segment_group_graph native pointer is no longer live (released or deserialised); reconstruct it with segment_group_graph().");
    return owner;
}
// No score sentinel: counts and step depths alone establish actual writes.
// UINT_MAX exceeds all possible counts because groups <= segments <= INT_MAX.
// -Inf cannot be a native total depth: PST sums unsigned, non-negative steps.
// Shared by the in-memory and the file route (and the synthetic-buffer test hook): the paired write masks must agree and
// written counts must be possible. Throws; no output is produced here.
void validate_group_outputs(const unsigned int* counts, const float* depths, R_xlen_t n, unsigned int group_count)
{
    for (R_xlen_t i = 0; i < n; ++i) {
        const bool count_written = counts[i] != std::numeric_limits<unsigned int>::max();
        const bool depth_written = depths[i] != -std::numeric_limits<float>::infinity();
        if (count_written != depth_written)
            throw std::runtime_error("PST count/depth write masks are inconsistent");
        if (count_written && counts[i] > group_count)
            throw std::runtime_error("PST returned an invalid group node count");
    }
}
void copy_group_outputs(const float* scores, const unsigned int* counts,
                        const float* depths, R_xlen_t n, unsigned int group_count,
                        double* score_out, int* count_out, double* depth_out)
{
    validate_group_outputs(counts, depths, n, group_count);
    for (R_xlen_t i = 0; i < n; ++i) {
        const bool count_written = counts[i] != std::numeric_limits<unsigned int>::max();
        score_out[i] = count_written ? scores[i] : NA_REAL;
        count_out[i] = count_written ? static_cast<int>(counts[i]) : NA_INTEGER;
        depth_out[i] = count_written ? depths[i] : NA_REAL;
    }
}
// File route: the same validation, then the native arrays are moved into a table whose three data columns carry one
// validity mask (nullable by function, never by data): a row is valid exactly when PST wrote its count and depth. The
// score is never consulted for missingness, and written NaN/Inf/-1/0 stay valid.
std::shared_ptr<rpst::ResultTable> group_result_table(const ResultStreamArgs& a, std::vector<float>&& scores,
                                                      std::vector<unsigned int>&& counts, std::vector<float>&& depths,
                                                      unsigned int group_count)
{
    const R_xlen_t n = static_cast<R_xlen_t>(counts.size());
    validate_group_outputs(counts.data(), depths.data(), n, group_count);
    auto bits = result_validity(counts.size(), [&](std::size_t i) {
        return counts[i] != std::numeric_limits<unsigned int>::max();
    });
    auto table = result_new_table(a, counts.size());
    result_add_float(*table, a.names[1], std::move(scores));
    result_mark_nullable(*table, bits);
    result_add_count(*table, a.names[2], std::move(counts));
    result_mark_nullable(*table, bits);
    result_add_float(*table, a.names[3], std::move(depths));
    result_mark_nullable(*table, std::move(bits));
    return table;
}
}

extern "C" SEXP rpst_segment_group_graph_create(SEXP pointer, SEXP ids)
{
    const auto* segment = segment_graph_owner(pointer);
    // PST's CSegmentGroupGraph::Create loops forever when a zero-length segment
    // is listed twice in its intersection (SegmentGroupGraph.cpp:203-254; only
    // ASSERTs guard it). Refuse before the native call.
    if (segment->zero_length > 0)
        Rf_error("segment_group_graph() cannot be built from a segment graph that contains zero-length segments (%u found: both endpoints identical); "
                 "PST's group-graph construction does not terminate on them. Remove them before building the segment graph.",
                 segment->zero_length);
    if ((TYPEOF(ids) != INTSXP && TYPEOF(ids) != REALSXP) ||
        XLENGTH(ids) != segment->count)
        Rf_error("group_id must be a numeric vector with one ID per native segment.");
    if (Rf_getAttrib(ids, R_DimSymbol) != R_NilValue)
        Rf_error("group_id must be a vector, not a matrix or array.");
    const CoordinateData data{TYPEOF(ids) == REALSXP ? REAL(ids) : nullptr,
                              TYPEOF(ids) == INTSXP ? INTEGER(ids) : nullptr};
    unsigned int group_count = 0;
    for (R_xlen_t i = 0; i < XLENGTH(ids); ++i) {
        const double id = data.at(i);
        if (!std::isfinite(id) || id < 1 || id != std::floor(id) || id > segment->count)
            Rf_error("group_id must contain whole IDs in 1..n_segments.");
        group_count = std::max(group_count, static_cast<unsigned int>(id));
    }
    SEXP result = PROTECT(R_MakeExternalPtr(nullptr, group_graph_tag(), R_NilValue));
    R_RegisterCFinalizerEx(result, group_graph_finalizer, TRUE);
    char error[512] = "";
    try {
        std::vector<unsigned int> native_ids(segment->count);
        for (R_xlen_t i = 0; i < XLENGTH(ids); ++i) {
            native_ids[i] = static_cast<unsigned int>(data.at(i)) - 1;
        }
        auto* owner = new GroupOwner{};
        R_SetExternalPtrAddr(result, owner);
        owner->count = group_count;
        SPSTACreateSegmentGroupGraphDesc desc{};
        desc.m_SegmentGraph = segment->handle;
        desc.m_GroupIndexPerSegment = native_ids.data();
        desc.m_SegmentCount = segment->count;
        desc.m_GroupCount = group_count;
        owner->handle = PSTACreateSegmentGroupGraph(&desc);
        if (!owner->handle) throw std::runtime_error("PSTACreateSegmentGroupGraph returned null");
        ++group_created;
    } catch (const std::exception& e) {
        std::snprintf(error, sizeof(error), "PST segment group graph construction failed: %s", e.what());
    } catch (...) {
        std::snprintf(error, sizeof(error), "PST segment group graph construction failed with an unknown native exception.");
    }
    if (error[0]) Rf_error("%s", error);
    UNPROTECT(1);
    return result;
}
extern "C" SEXP rpst_segment_group_graph_info(SEXP pointer)
{
    return Rf_ScalarInteger(static_cast<int>(group_graph_owner(pointer)->count));
}
extern "C" SEXP rpst_segment_group_graph_release(SEXP pointer)
{
    group_graph_owner(pointer, false);
    group_graph_finalizer(pointer);
    return R_NilValue;
}
extern "C" SEXP rpst_segment_group_graph_lifecycle()
{
    SEXP result = PROTECT(Rf_allocVector(REALSXP, 3));
    REAL(result)[0] = group_created; REAL(result)[1] = group_freed;
    REAL(result)[2] = group_created - group_freed;
    UNPROTECT(1);
    return result;
}
namespace {
SEXP segment_group_integration(SEXP pointer, SEXP radius, const StreamRequest* request)
{
    const auto* owner = group_graph_owner(pointer);
    const auto radii = shared_radii(radius);
    // The pinned implementation reads only Walking()/Steps(). Do not silently
    // accept other limits as though they restricted this engine.
    if (radii.m_Mask & ~(EPSTADistanceTypeMask_Walking | EPSTADistanceTypeMask_Steps))
        Rf_error("Segment Group Integration supports only walking and steps radius limits.");
    const R_xlen_t n = owner->count;
    ResultStreamArgs args;
    if (request) args = result_stream_args(*request, 4);
    SEXP result = R_NilValue;
    double *scores_out = nullptr, *depths_out = nullptr;
    int* counts_out = nullptr;
    int protected_count = 0;
    if (!request) {
        result = PROTECT(Rf_allocVector(VECSXP, 3));
        SEXP scores = PROTECT(Rf_allocVector(REALSXP, n));
        SEXP counts = PROTECT(Rf_allocVector(INTSXP, n));
        SEXP depths = PROTECT(Rf_allocVector(REALSXP, n));
        SET_VECTOR_ELT(result, 0, scores); SET_VECTOR_ELT(result, 1, counts);
        SET_VECTOR_ELT(result, 2, depths);
        scores_out = REAL(scores); counts_out = INTEGER(counts);
        depths_out = REAL(depths);
        protected_count = 4;
    }
    char error[512] = "";
    try {
        // Validate explicit caps even on no-node graphs that return before PST
        // reaches its worker creation. No R APIs are called by worker threads.
        rpst_worker_count();
        std::vector<float> native_scores(n);
        std::vector<unsigned int> native_counts(n, std::numeric_limits<unsigned int>::max());
        std::vector<float> native_depths(n, -std::numeric_limits<float>::infinity());
        SPSTASegmentGroupIntegrationDesc desc{};
        desc.m_Graph = owner->handle; desc.m_Radius = radii;
        desc.m_OutIntegration = native_scores.data();
        desc.m_OutNodeCount = native_counts.data();
        desc.m_OutTotalDepth = native_depths.data();
        rpst::progress_attach(desc.m_ProgressCallback, desc.m_ProgressCallbackUser);
        if (!PSTASegmentGroupIntegration(&desc))
            throw std::runtime_error("PSTASegmentGroupIntegration returned false");
        if (request) {
            auto table = group_result_table(args, std::move(native_scores), std::move(native_counts),
                                            std::move(native_depths), owner->count);
            result_finish_and_export(args, std::move(table), error, sizeof error);
        } else {
            copy_group_outputs(native_scores.data(), native_counts.data(), native_depths.data(),
                               n, owner->count, scores_out, counts_out, depths_out);
        }
    } catch (const std::exception& e) {
        std::snprintf(error, sizeof(error), "PSTASegmentGroupIntegration failed: %s", e.what());
    } catch (...) {
        std::snprintf(error, sizeof(error), "PSTASegmentGroupIntegration failed with an unknown native exception.");
    }
    if (error[0]) Rf_error("%s", error);
    if (request) return Rf_ScalarReal(static_cast<double>(n));
    UNPROTECT(protected_count);
    return result;
}
} // namespace
extern "C" SEXP rpst_segment_group_integration(SEXP pointer, SEXP radius)
{
    return segment_group_integration(pointer, radius, nullptr);
}
extern "C" SEXP rpst_segment_group_integration_stream(SEXP pointer, SEXP radius, SEXP stream_pointer, SEXP names,
    SEXP metadata_names, SEXP metadata_values, SEXP batch_rows)
{
    const StreamRequest request{stream_pointer, names, metadata_names, metadata_values, batch_rows};
    return segment_group_integration(pointer, radius, &request);
}

// Private synthetic-buffer hook tests the same production conversion, including
// corrupt paired masks. It never injects faults into PST or changes live graphs.
namespace {
SEXP segment_group_output_test(SEXP scores, SEXP counts, SEXP depths, const StreamRequest* request)
{
    if (TYPEOF(scores) != REALSXP || TYPEOF(counts) != INTSXP || TYPEOF(depths) != REALSXP ||
        XLENGTH(scores) != XLENGTH(counts) || XLENGTH(scores) != XLENGTH(depths) ||
        XLENGTH(scores) < 1 || XLENGTH(scores) > std::numeric_limits<int>::max())
        Rf_error("Synthetic group outputs require equal nonempty double/integer/double vectors.");
    const R_xlen_t n = XLENGTH(scores);
    const double* s = REAL(scores); const int* c = INTEGER(counts); const double* d = REAL(depths);
    for (R_xlen_t i = 0; i < n; ++i) {
        if (c[i] != NA_INTEGER && c[i] < 0) Rf_error("Synthetic counts must be non-negative or NA (unwritten).");
        if ((std::isfinite(s[i]) && std::abs(s[i]) > std::numeric_limits<float>::max()) ||
            (std::isfinite(d[i]) && std::abs(d[i]) > std::numeric_limits<float>::max()))
            Rf_error("Synthetic outputs exceed native float range.");
    }
    ResultStreamArgs args;
    if (request) args = result_stream_args(*request, 4);
    SEXP result = R_NilValue;
    double *so = nullptr, *dout = nullptr; int* co = nullptr;
    if (!request) {
        result = PROTECT(Rf_allocVector(VECSXP, 3));
        SEXP out_s = PROTECT(Rf_allocVector(REALSXP, n));
        SEXP out_c = PROTECT(Rf_allocVector(INTSXP, n));
        SEXP out_d = PROTECT(Rf_allocVector(REALSXP, n));
        SET_VECTOR_ELT(result, 0, out_s); SET_VECTOR_ELT(result, 1, out_c); SET_VECTOR_ELT(result, 2, out_d);
        so = REAL(out_s); co = INTEGER(out_c); dout = REAL(out_d);
    }
    char error[512] = "";
    try {
        std::vector<float> ns(n), nd(n); std::vector<unsigned int> nc(n);
        for (R_xlen_t i = 0; i < n; ++i) {
            ns[i] = static_cast<float>(s[i]); nd[i] = static_cast<float>(d[i]);
            nc[i] = c[i] == NA_INTEGER ? std::numeric_limits<unsigned int>::max() : static_cast<unsigned int>(c[i]);
        }
        if (request) {
            auto table = group_result_table(args, std::move(ns), std::move(nc), std::move(nd), static_cast<unsigned int>(n));
            result_finish_and_export(args, std::move(table), error, sizeof error);
        } else {
            copy_group_outputs(ns.data(), nc.data(), nd.data(), n, static_cast<unsigned int>(n), so, co, dout);
        }
    } catch (const std::exception& e) {
        std::snprintf(error, sizeof(error), "Group output conversion failed: %s", e.what());
    } catch (...) {
        std::snprintf(error, sizeof(error), "Group output conversion failed with an unknown native exception.");
    }
    if (error[0]) Rf_error("%s", error);
    if (request) return R_NilValue;
    UNPROTECT(4);
    return result;
}
} // namespace
extern "C" SEXP rpst_segment_group_output_test(SEXP scores, SEXP counts, SEXP depths)
{
    return segment_group_output_test(scores, counts, depths, nullptr);
}
// Private: drives the production file-route conversion (mask validation + nullable table) from synthetic buffers.
extern "C" SEXP rpst_segment_group_output_test_stream(SEXP scores, SEXP counts, SEXP depths, SEXP stream_pointer,
    SEXP names, SEXP metadata_names, SEXP metadata_values, SEXP batch_rows)
{
    const StreamRequest request{stream_pointer, names, metadata_names, metadata_values, batch_rows};
    return segment_group_output_test(scores, counts, depths, &request);
}

// Private structural inspection for constructor/lifetime regressions only.
// No graph geometry is retained in public R owners; these are fresh copies.
extern "C" SEXP rpst_graph_point_state(SEXP pointer)
{
    const auto& graph = *static_cast<const CAxialGraph*>(graph_handle(pointer));
    const int n = graph.getPointCount();
    const int groups = static_cast<int>(graph.getPointGroupCount());
    SEXP out = PROTECT(Rf_allocVector(VECSXP, 2));
    SEXP points = PROTECT(Rf_allocMatrix(REALSXP, n, 5));
    SEXP sizes = PROTECT(Rf_allocVector(INTSXP, groups));
    SET_VECTOR_ELT(out, 0, points); SET_VECTOR_ELT(out, 1, sizes);
    double* data = REAL(points);
    for (int i = 0; i < n; ++i) {
        const auto& p = graph.getPoint(i);
        const auto world = graph.localToWorld(p.coords);
        data[i] = world.x; data[i+n] = world.y;
        data[i+2*static_cast<R_xlen_t>(n)] = p.iLine+1;
        data[i+3*static_cast<R_xlen_t>(n)] = p.distFromLine;
        data[i+4*static_cast<R_xlen_t>(n)] = p.linePos;
    }
    for (int i = 0; i < groups; ++i) INTEGER(sizes)[i] = static_cast<int>(graph.getPointGroupSize(i));
    UNPROTECT(3);
    return out;
}

namespace {
float attraction_scalar(SEXP x, const char* name, bool positive = false, bool nonnegative = false)
{
    if ((TYPEOF(x) != REALSXP && TYPEOF(x) != INTSXP) || XLENGTH(x) != 1)
        Rf_error("%s must be one finite native float value.", name);
    CoordinateData data{TYPEOF(x) == REALSXP ? REAL(x) : nullptr,
                        TYPEOF(x) == INTSXP ? INTEGER(x) : nullptr};
    const double v = data.at(0);
    if (!std::isfinite(v) || std::abs(v) > std::numeric_limits<float>::max() ||
        (v != 0 && static_cast<float>(v) == 0) || (positive && v <= 0) || (nonnegative && v < 0))
        Rf_error("%s must be a representable finite%s native float value.", name,
                 positive ? " positive" : nonnegative ? " non-negative" : "");
    return static_cast<float>(v);
}
struct AttractionInput {
    InputMatrix points;
    CoordinateData sizes{nullptr, nullptr};
    R_xlen_t groups = 0;
    float spacing = 0;
};
AttractionInput attraction_input(SEXP x, SEXP sizes, SEXP interval, HPSTAGraph handle,
                                 const char* name = "attraction_points")
{
    const bool polygons = sizes != R_NilValue;
    if (x==R_NilValue) Rf_error("%s must be a numeric matrix with two columns (zero rows are allowed).", name);
    AttractionInput out{graph_input_matrix(x, 2, name, true, polygons)};
    if (polygons) {
        if ((TYPEOF(sizes) != REALSXP && TYPEOF(sizes) != INTSXP) ||
            Rf_getAttrib(sizes, R_DimSymbol) != R_NilValue || XLENGTH(sizes) < 1 ||
            XLENGTH(sizes) > std::numeric_limits<int>::max())
            Rf_error("points_per_polygon must be a non-empty numeric vector of non-negative whole counts.");
        out.groups = XLENGTH(sizes);
        out.sizes = {TYPEOF(sizes) == REALSXP ? REAL(sizes) : nullptr,
                     TYPEOF(sizes) == INTSXP ? INTEGER(sizes) : nullptr};
        double sum = 0;
        for (R_xlen_t i = 0; i < out.groups; ++i) {
            const double v = out.sizes.at(i);
            if (!std::isfinite(v) || v < 0 || v != std::floor(v) || v > out.points.rows)
                Rf_error("points_per_polygon must contain non-negative whole counts within the attraction row count.");
            sum += v;
        }
        if (sum != out.points.rows) Rf_error("points_per_polygon must sum to the number of attraction rows.");
        out.spacing = attraction_scalar(interval, "polygon_point_interval", true);
    } else if (interval != R_NilValue) Rf_error("polygon_point_interval requires points_per_polygon.");
    const auto& graph = *static_cast<const CAxialGraph*>(handle);
    // Both native analyses compare attractions with graph points as well as
    // lines. Bound the full native/input extent, including local bbox sums.
    float2 lo = graph.getLine(0).p1, hi = lo;
    const auto extend = [&](const float2& p) {
        lo.x = std::min(lo.x,p.x); lo.y = std::min(lo.y,p.y);
        hi.x = std::max(hi.x,p.x); hi.y = std::max(hi.y,p.y);
    };
    for (int i=0; i<graph.getLineCount(); ++i) { extend(graph.getLine(i).p1); extend(graph.getLine(i).p2); }
    for (int i=0; i<graph.getPointCount(); ++i) extend(graph.getPoint(i).coords);
    for (R_xlen_t i=0; i<out.points.rows; ++i) {
        const auto p = out.points.point(i);
        if (std::isnan(p.x)) continue;
        const auto local = p-graph.getWorldOrigin();
        if (!std::isfinite(local.x) || !std::isfinite(local.y) ||
            std::abs(local.x)>std::numeric_limits<float>::max() || std::abs(local.y)>std::numeric_limits<float>::max())
            Rf_error("%s coordinates overflow PST's native local-coordinate representation.", name);
        extend(graph.worldToLocal(p));
    }
    if (!std::isfinite((hi-lo).getLengthSqr()) || !std::isfinite(lo.x+hi.x) || !std::isfinite(lo.y+hi.y))
        Rf_error("%s coordinate extent overflows PST's native distance representation.", name);
    return out;
}
// Bounds only: PST still generates all samples and computes every score/minimum.
// Reach samples world doubles; Distance samples local floats. Check both paths.
void attraction_sampling_bounds(const AttractionInput& in, const std::vector<double2>& points,
                                 const CAxialGraph& graph, bool local_sampling)
{
    if (!in.groups) return;
    double bound = 2.0*points.size()+2.0*in.groups;
    R_xlen_t offset = 0;
    for (R_xlen_t g=0; g<in.groups; ++g) {
        const auto end = offset+static_cast<R_xlen_t>(in.sizes.at(g));
        R_xlen_t first = offset;
        for (R_xlen_t i=offset; i<=end; ++i) {
            if (i!=end && !std::isnan(points[i].x)) continue;
            for (R_xlen_t j=first; j<i; ++j) {
                const auto k = j+1<i ? j+1 : first;
                double length = (points[k]-points[j]).getLength();
                if (local_sampling) {
                    const float f = (graph.worldToLocal(points[k])-graph.worldToLocal(points[j])).getLength();
                    if (f>0 && f+in.spacing==f)
                        throw std::runtime_error("Polygon sampling interval cannot advance PST's native float loop.");
                    length = std::max(length,static_cast<double>(f));
                }
                bound += length/in.spacing;
            }
            first=i+1;
        }
        offset=end;
    }
    if (!std::isfinite(bound) || bound>std::numeric_limits<int>::max())
        throw std::runtime_error("Polygon sampling exceeds PST's native signed point-count bounds.");
}
unsigned int attraction_origin(HPSTAGraph h, SEXP origin, unsigned char& mode)
{
    const char* names[] = {"points","junctions","lines","point_groups"};
    mode = static_cast<unsigned char>(named_mode(origin,names,4,"origin"));
    const auto& graph = *static_cast<const CAxialGraph*>(h);
    const auto n = mode==0 ? graph.getPointCount() : mode==1 ? graph.getCrossingCount() :
                   mode==2 ? graph.getLineCount() : graph.getPointGroupCount();
    if (static_cast<unsigned long long>(n)>static_cast<unsigned long long>(std::numeric_limits<int>::max()))
        Rf_error("Origin count exceeds PST's signed index bounds.");
    return static_cast<unsigned int>(n);
}
std::vector<unsigned int> attraction_sizes(const AttractionInput& in)
{
    std::vector<unsigned int> sizes(in.groups);
    for (R_xlen_t i=0; i<in.groups; ++i) sizes[i]=static_cast<unsigned int>(in.sizes.at(i));
    return sizes;
}
std::vector<double2> attraction_points_copy(const AttractionInput& in)
{
    std::vector<double2> points(in.points.rows);
    for (R_xlen_t i=0; i<in.points.rows; ++i) points[i]=in.points.point(i);
    return points;
}
}
namespace {
SEXP attraction_reach(SEXP pointer, SEXP radius, SEXP origin, SEXP distance,
    SEXP points, SEXP sizes, SEXP interval, SEXP values, SEXP decay, SEXP constant,
    SEXP distribution, SEXP collection, const StreamRequest* request)
{
    const auto h=graph_handle(pointer);
    const auto radii=shared_radii(radius);
    unsigned char origin_mode;
    const auto n=attraction_origin(h,origin,origin_mode);
    const char* distances[]={"straight","walking","steps","angular","axmeter","none"};
    int d=named_mode(distance,distances,6,"distance");
    if (d==5) d=EPSTADistanceType_Undefined;
    const char* decays[]={"constant","power","curve","divide"};
    const auto w=named_mode(decay,decays,4,"decay");
    const auto c=attraction_scalar(constant,"decay_constant");
    const char* distributions[]={"copy","divide"};
    const auto dist=named_mode(distribution,distributions,2,"distribution");
    const char* collections[]={"mean","sum","min","max"};
    const auto coll=named_mode(collection,collections,4,"collection");
    const auto in=attraction_input(points,sizes,interval,h);
    const auto weights=analysis_weights(values,in.groups ? in.groups : in.points.rows);
    ResultStreamArgs args;
    if (request) args=result_stream_args(*request,2);
    SEXP out=R_NilValue;
    double* output=nullptr;
    if (!request) { out=PROTECT(Rf_allocVector(REALSXP,n)); output=REAL(out); }
    char error[512]="";
    try {
        auto coords=attraction_points_copy(in);
        attraction_sampling_bounds(in,coords,*static_cast<const CAxialGraph*>(h),false);
        auto counts=attraction_sizes(in);
        std::vector<float> native_values(values==R_NilValue ? 0 : (in.groups ? in.groups : in.points.rows));
        for (size_t i=0; i<native_values.size(); ++i) native_values[i]=static_cast<float>(weights.at(i));
        std::vector<float> scores(n);
        SPSTAAttractionReachDesc desc{};
        desc.m_Graph=h; desc.m_OriginType=origin_mode; desc.m_DistanceType=static_cast<unsigned char>(d);
        desc.m_Radius=radii; desc.m_WeightFunc=static_cast<unsigned char>(w); desc.m_WeightFuncConstant=c;
        desc.m_AttractionPoints=coords.data(); desc.m_AttractionPointCount=static_cast<unsigned int>(coords.size());
        desc.m_PointsPerAttractionPolygon=counts.empty() ? nullptr : counts.data();
        desc.m_AttractionPolygonCount=static_cast<unsigned int>(counts.size()); desc.m_AttractionPolygonPointInterval=in.spacing;
        desc.m_AttractionValues=native_values.empty() ? nullptr : native_values.data();
        desc.m_AttractionDistributionFunc=static_cast<unsigned char>(dist); desc.m_AttractionCollectionFunc=static_cast<unsigned char>(coll);
        desc.m_OutScores=scores.data(); desc.m_OutputCount=n;
        rpst::progress_attach(desc.m_ProgressCallback, desc.m_ProgressCallbackUser);
        if (!PSTAAttractionReach(&desc)) throw std::runtime_error("PSTAAttractionReach failed.");
        if (request) {
            auto table=result_new_table(args,n);
            result_add_float(*table,args.names[1],std::move(scores));
            result_finish_and_export(args,std::move(table),error,sizeof error);
        } else for (unsigned int i=0; i<n; ++i) output[i]=scores[i];
    } catch (const std::exception& e) { std::snprintf(error,sizeof(error),"%s",e.what()); }
      catch (...) { std::snprintf(error,sizeof(error),"Unknown native Attraction Reach exception."); }
    if (error[0]) Rf_error("%s",error);
    if (request) return Rf_ScalarReal(static_cast<double>(n));
    UNPROTECT(1); return out;
}
} // namespace
extern "C" SEXP rpst_attraction_reach(SEXP pointer, SEXP radius, SEXP origin, SEXP distance,
    SEXP points, SEXP sizes, SEXP interval, SEXP values, SEXP decay, SEXP constant,
    SEXP distribution, SEXP collection)
{
    return attraction_reach(pointer,radius,origin,distance,points,sizes,interval,values,decay,constant,distribution,
                            collection,nullptr);
}
extern "C" SEXP rpst_attraction_reach_stream(SEXP pointer, SEXP radius, SEXP origin, SEXP distance,
    SEXP points, SEXP sizes, SEXP interval, SEXP values, SEXP decay, SEXP constant,
    SEXP distribution, SEXP collection, SEXP stream_pointer, SEXP names, SEXP metadata_names,
    SEXP metadata_values, SEXP batch_rows)
{
    const StreamRequest request{stream_pointer,names,metadata_names,metadata_values,batch_rows};
    return attraction_reach(pointer,radius,origin,distance,points,sizes,interval,values,decay,constant,distribution,
                            collection,&request);
}
namespace {
// The radius/distance/origin rules of Attraction Distance (R_alloc/Rf_error only, so it can run before any native owner exists).
void attraction_distance_check_radius(int d, const SPSTARadii& radii, unsigned char origin_mode)
{
    const bool straight_only=d==EPSTADistanceType_Straight && !(radii.m_Mask & ~EPSTADistanceTypeMask_Straight);
    if (straight_only && origin_mode==EPSTAOriginType_PointGroups)
        Rf_error("Pinned PST leaves straight-only Attraction Distance point-group outputs unwritten; this combination is unsupported.");
    if (d==EPSTADistanceType_Straight && !straight_only)
        Rf_error("Pinned PST supports straight Attraction Distance only with no radius or a straight-only radius.");
    if (!straight_only && (radii.m_Mask & EPSTADistanceTypeMask_Axmeter))
        Rf_error("axmeter radius is unsupported by the pinned Attraction Distance network builder.");
}
SEXP attraction_distance(SEXP pointer, SEXP radius, SEXP origin, SEXP distance,
    SEXP points, SEXP sizes, SEXP interval, SEXP weights, SEXP point_cost, SEXP indices,
    const StreamRequest* request)
{
    const auto h=graph_handle(pointer);
    const auto radii=shared_radii(radius);
    unsigned char origin_mode;
    const auto n=attraction_origin(h,origin,origin_mode);
    const char* distances[]={"straight","walking","steps","angular","weights"};
    int d=named_mode(distance,distances,5,"distance");
    if (d==4) d=EPSTADistanceType_Weights;
    attraction_distance_check_radius(d,radii,origin_mode);
    const auto in=attraction_input(points,sizes,interval,h);
    const auto line_count=static_cast<const CAxialGraph*>(h)->getLineCount();
    if (d==EPSTADistanceType_Weights && weights==R_NilValue)
        Rf_error("line_weights is required for distance = weights.");
    const auto line_weights=analysis_weights(weights,line_count);
    if (d!=EPSTADistanceType_Weights && weights!=R_NilValue)
        Rf_error("line_weights requires distance = weights.");
    for (int i=0; weights!=R_NilValue && i<line_count; ++i)
        if (line_weights.at(i)<0) Rf_error("line_weights must be non-negative for PST's shortest-path traversal.");
    const auto cost=attraction_scalar(point_cost,"point_edge_weight",false,true);
    if (TYPEOF(indices)!=LGLSXP || XLENGTH(indices)!=1 || LOGICAL(indices)[0]==NA_LOGICAL)
        Rf_error("destination_indices must be TRUE or FALSE.");
    const bool want_indices=LOGICAL(indices)[0];
    ResultStreamArgs args;
    if (request) args=result_stream_args(*request,want_indices ? 3 : 2);
    SEXP out=R_NilValue;
    double* output=nullptr; int* index_output=nullptr;
    if (!request) {
        out=PROTECT(Rf_allocVector(VECSXP,2));
        SEXP distances_out=PROTECT(Rf_allocVector(REALSXP,n));
        SEXP indices_out=PROTECT(Rf_allocVector(INTSXP,want_indices ? n : 0));
        SET_VECTOR_ELT(out,0,distances_out); SET_VECTOR_ELT(out,1,indices_out);
        output=REAL(distances_out); index_output=INTEGER(indices_out);
    }
    char error[512]="";
    try {
        auto coords=attraction_points_copy(in);
        attraction_sampling_bounds(in,coords,*static_cast<const CAxialGraph*>(h),true);
        auto counts=attraction_sizes(in);
        std::vector<float> native_weights(weights==R_NilValue ? 0 : line_count);
        for (size_t i=0; i<native_weights.size(); ++i) native_weights[i]=static_cast<float>(line_weights.at(i));
        std::vector<float> results(n);
        // Negative initialization avoids PST's premature public-index lookup
        // in polygon/group mode; every supported path then writes native values.
        std::vector<int> destinations(want_indices ? n : 0,-1);
        SPSTAAttractionDistanceDesc desc{};
        desc.m_Graph=h; desc.m_OriginType=origin_mode; desc.m_DistanceType=static_cast<unsigned char>(d); desc.m_Radius=radii;
        desc.m_AttractionPoints=coords.data(); desc.m_AttractionPointCount=static_cast<unsigned int>(coords.size());
        desc.m_PointsPerAttractionPolygon=counts.empty() ? nullptr : counts.data();
        desc.m_AttractionPolygonCount=static_cast<unsigned int>(counts.size()); desc.m_AttractionPolygonPointInterval=in.spacing;
        desc.m_LineWeights=native_weights.empty() ? nullptr : native_weights.data(); desc.m_LineWeightCount=static_cast<unsigned int>(native_weights.size());
        desc.m_WeightPerMeterForPointEdges=cost; desc.m_OutMinDistance=results.data();
        desc.m_OutDestinationIndices=want_indices ? destinations.data() : nullptr; desc.m_OutputCount=n;
        rpst::progress_attach(desc.m_ProgressCallback, desc.m_ProgressCallbackUser);
        if (!PSTAAttractionDistance(&desc)) throw std::runtime_error("PSTAAttractionDistance failed.");
        if (request) {
            auto table=result_new_table(args,n);
            result_add_float(*table,args.names[1],std::move(results));
            if (want_indices) result_add_signed(*table,args.names[2],std::move(destinations));  // native zero-based, -1 = none
            result_finish_and_export(args,std::move(table),error,sizeof error);
        } else for (unsigned int i=0; i<n; ++i) { output[i]=results[i]; if (want_indices) index_output[i]=destinations[i]; }
    } catch (const std::exception& e) { std::snprintf(error,sizeof(error),"%s",e.what()); }
      catch (...) { std::snprintf(error,sizeof(error),"Unknown native Attraction Distance exception."); }
    if (error[0]) Rf_error("%s",error);
    if (request) return Rf_ScalarReal(static_cast<double>(n));
    UNPROTECT(3); return out;
}
} // namespace
extern "C" SEXP rpst_attraction_distance(SEXP pointer, SEXP radius, SEXP origin, SEXP distance,
    SEXP points, SEXP sizes, SEXP interval, SEXP weights, SEXP point_cost, SEXP indices)
{
    return attraction_distance(pointer,radius,origin,distance,points,sizes,interval,weights,point_cost,indices,nullptr);
}
extern "C" SEXP rpst_attraction_distance_stream(SEXP pointer, SEXP radius, SEXP origin, SEXP distance,
    SEXP points, SEXP sizes, SEXP interval, SEXP weights, SEXP point_cost, SEXP indices,
    SEXP stream_pointer, SEXP names, SEXP metadata_names, SEXP metadata_values, SEXP batch_rows)
{
    const StreamRequest request{stream_pointer,names,metadata_names,metadata_values,batch_rows};
    return attraction_distance(pointer,radius,origin,distance,points,sizes,interval,weights,point_cost,indices,&request);
}

namespace {
SEXP od_betweenness(SEXP pointer, SEXP origins, SEXP radius, SEXP distance,
                    SEXP mode, SEXP origin_weights, SEXP destination_weights, const StreamRequest* request)
{
    const auto handle = graph_handle(pointer);
    const auto radii = shared_radii(radius);
    const char* distances[] = {"walking", "angular"};
    const int distance_mode = named_mode(distance, distances, 2, "distance");
    const char* destinations[] = {"all", "closest"};
    const int destination_mode = named_mode(mode, destinations, 2, "destination_mode");
    // Reuse bounds covering supplied world origins against native graph points
    // and lines, including float bbox sums and origin/destination distance squares.
    const auto input = attraction_input(origins, R_NilValue, R_NilValue, handle, "origins");
    const auto& graph = *static_cast<const CAxialGraph*>(handle);
    const int n = graph.getLineCount(), points = graph.getPointCount();
    const auto ow = analysis_weights(origin_weights, input.points.rows, "origin_weights", "origin row");
    const auto dw = analysis_weights(destination_weights, points, "destination_weights", "native graph point");
    ResultStreamArgs args;
    if (request) args = result_stream_args(*request, 2);
    SEXP out = R_NilValue;
    double* output = nullptr;
    if (!request) { out = PROTECT(Rf_allocVector(REALSXP, n)); output = REAL(out); }
    char error[512] = "";
    try {
        auto coords = attraction_points_copy(input);
        std::vector<float> native_origins(origin_weights == R_NilValue ? 0 : input.points.rows);
        std::vector<float> native_destinations(destination_weights == R_NilValue ? 0 : points);
        for (size_t i = 0; i < native_origins.size(); ++i) native_origins[i] = static_cast<float>(ow.at(i));
        for (size_t i = 0; i < native_destinations.size(); ++i) native_destinations[i] = static_cast<float>(dw.at(i));
        std::vector<float> scores(n);
        SPSTAODBetweenness desc{};
        desc.m_Graph = handle;
        desc.m_OriginPoints = coords.empty() ? nullptr : coords.data();
        desc.m_OriginCount = static_cast<unsigned int>(coords.size());
        desc.m_OriginWeights = native_origins.empty() ? nullptr : native_origins.data();
        desc.m_DestinationWeights = native_destinations.empty() ? nullptr : native_destinations.data();
        desc.m_DestinationCount = static_cast<unsigned int>(points);
        desc.m_DestinationMode = static_cast<unsigned char>(destination_mode);
        desc.m_DistanceType = distance_mode == 0 ? EPSTADistanceType_Walking : EPSTADistanceType_Angular;
        desc.m_Radius = radii;
        desc.m_OutScores = scores.data();
        desc.m_OutputCount = static_cast<unsigned int>(n);
        rpst::progress_attach(desc.m_ProgressCallback, desc.m_ProgressCallbackUser);
        if (!PSTAODBetweenness(&desc)) throw std::runtime_error("PSTAODBetweenness failed.");
        if (request) {
            auto table = result_new_table(args, static_cast<size_t>(n));
            result_add_float(*table, args.names[1], std::move(scores));
            result_finish_and_export(args, std::move(table), error, sizeof error);
        } else for (int i = 0; i < n; ++i) output[i] = scores[i];
    } catch (const std::exception& e) {
        std::snprintf(error, sizeof(error), "%s", e.what());
    } catch (...) {
        std::snprintf(error, sizeof(error), "Unknown native OD Betweenness exception.");
    }
    if (error[0]) Rf_error("%s", error);
    if (request) return Rf_ScalarReal(static_cast<double>(n));
    UNPROTECT(1);
    return out;
}
} // namespace
extern "C" SEXP rpst_od_betweenness(SEXP pointer, SEXP origins, SEXP radius, SEXP distance,
                                    SEXP mode, SEXP origin_weights, SEXP destination_weights)
{
    return od_betweenness(pointer, origins, radius, distance, mode, origin_weights, destination_weights, nullptr);
}
extern "C" SEXP rpst_od_betweenness_stream(SEXP pointer, SEXP origins, SEXP radius, SEXP distance,
    SEXP mode, SEXP origin_weights, SEXP destination_weights, SEXP stream_pointer, SEXP names,
    SEXP metadata_names, SEXP metadata_values, SEXP batch_rows)
{
    const StreamRequest request{stream_pointer, names, metadata_names, metadata_values, batch_rows};
    return od_betweenness(pointer, origins, radius, distance, mode, origin_weights, destination_weights, &request);
}

// ---- Multi-radius Attraction Reach, Attraction Distance and OD Betweenness (axial graphs) -------------------------------------------
// Same contract as the multi-radius Network Reach / Betweenness layer: every radius configuration is parsed (and, for Attraction
// Distance, checked against the distance rules) before the first PST call; PST then runs once per radius with the scalar
// descriptor, exactly as a scalar call would fill it. The finished columns of all radii are retained, in preallocated R vectors
// or in one ResultTable, so result storage grows with the number of radii. The attraction/origin inputs are copied per run
// because PST receives them through non-const pointers.
namespace {
struct AttractionReachMulti {
    HPSTAGraph h{}; SPSTARadii* radii = nullptr; R_xlen_t k = 0; unsigned char origin_mode = 0; unsigned int n = 0;
    int d = 0, w = 0, dist = 0, coll = 0; float c = 0;
    AttractionInput in; CoordinateData weights{nullptr, nullptr}; bool has_values = false;
};
AttractionReachMulti attraction_reach_multi_args(SEXP pointer, SEXP radii, SEXP origin, SEXP distance, SEXP points, SEXP sizes,
    SEXP interval, SEXP values, SEXP decay, SEXP constant, SEXP distribution, SEXP collection)
{
    AttractionReachMulti a;
    a.h = graph_handle(pointer);
    a.radii = multi_radii(radii, a.k, false);
    a.n = attraction_origin(a.h, origin, a.origin_mode);
    const char* distances[] = {"straight", "walking", "steps", "angular", "axmeter", "none"};
    a.d = named_mode(distance, distances, 6, "distance");
    if (a.d == 5) a.d = EPSTADistanceType_Undefined;
    const char* decays[] = {"constant", "power", "curve", "divide"};
    a.w = named_mode(decay, decays, 4, "decay");
    a.c = attraction_scalar(constant, "decay_constant");
    const char* distributions[] = {"copy", "divide"};
    a.dist = named_mode(distribution, distributions, 2, "distribution");
    const char* collections[] = {"mean", "sum", "min", "max"};
    a.coll = named_mode(collection, collections, 4, "collection");
    a.in = attraction_input(points, sizes, interval, a.h);
    a.weights = analysis_weights(values, a.in.groups ? a.in.groups : a.in.points.rows);
    a.has_values = values != R_NilValue;
    return a;
}
// One score column per radius.
template <class Sink>
void attraction_reach_multi_compute(const AttractionReachMulti& a, Sink& sink)
{
    const auto& graph = *static_cast<const CAxialGraph*>(a.h);
    for (R_xlen_t r = 0; r < a.k; ++r) {
        axial_fault_point();
        ++g_axial.attraction_reach_runs;
        auto coords = attraction_points_copy(a.in);
        attraction_sampling_bounds(a.in, coords, graph, false);
        auto counts = attraction_sizes(a.in);
        std::vector<float> native_values(a.has_values ? (a.in.groups ? a.in.groups : a.in.points.rows) : 0);
        for (size_t i = 0; i < native_values.size(); ++i) native_values[i] = static_cast<float>(a.weights.at(i));
        std::vector<float> scores(a.n);
        SPSTAAttractionReachDesc desc{};
        desc.m_Graph = a.h; desc.m_OriginType = a.origin_mode; desc.m_DistanceType = static_cast<unsigned char>(a.d);
        desc.m_Radius = a.radii[r]; desc.m_WeightFunc = static_cast<unsigned char>(a.w); desc.m_WeightFuncConstant = a.c;
        desc.m_AttractionPoints = coords.data(); desc.m_AttractionPointCount = static_cast<unsigned int>(coords.size());
        desc.m_PointsPerAttractionPolygon = counts.empty() ? nullptr : counts.data();
        desc.m_AttractionPolygonCount = static_cast<unsigned int>(counts.size());
        desc.m_AttractionPolygonPointInterval = a.in.spacing;
        desc.m_AttractionValues = native_values.empty() ? nullptr : native_values.data();
        desc.m_AttractionDistributionFunc = static_cast<unsigned char>(a.dist);
        desc.m_AttractionCollectionFunc = static_cast<unsigned char>(a.coll);
        desc.m_OutScores = scores.data(); desc.m_OutputCount = a.n;
        rpst::progress_attach(desc.m_ProgressCallback, desc.m_ProgressCallbackUser);
        if (!PSTAAttractionReach(&desc)) throw std::runtime_error("PSTAAttractionReach failed.");
        sink.add_float(std::move(scores), nullptr);
    }
}

struct AttractionDistanceMulti {
    HPSTAGraph h{}; SPSTARadii* radii = nullptr; R_xlen_t k = 0; unsigned char origin_mode = 0; unsigned int n = 0; int d = 0;
    AttractionInput in; int line_count = 0; CoordinateData line_weights{nullptr, nullptr}; bool has_weights = false;
    float cost = 0; bool want_indices = false;
};
AttractionDistanceMulti attraction_distance_multi_args(SEXP pointer, SEXP radii, SEXP origin, SEXP distance, SEXP points,
    SEXP sizes, SEXP interval, SEXP weights, SEXP point_cost, SEXP indices)
{
    AttractionDistanceMulti a;
    a.h = graph_handle(pointer);
    a.radii = multi_radii(radii, a.k, false);
    a.n = attraction_origin(a.h, origin, a.origin_mode);
    const char* distances[] = {"straight", "walking", "steps", "angular", "weights"};
    a.d = named_mode(distance, distances, 5, "distance");
    if (a.d == 4) a.d = EPSTADistanceType_Weights;
    for (R_xlen_t r = 0; r < a.k; ++r) attraction_distance_check_radius(a.d, a.radii[r], a.origin_mode);   // every radius, before any run
    a.in = attraction_input(points, sizes, interval, a.h);
    a.line_count = static_cast<const CAxialGraph*>(a.h)->getLineCount();
    if (a.d == EPSTADistanceType_Weights && weights == R_NilValue)
        Rf_error("line_weights is required for distance = weights.");
    a.line_weights = analysis_weights(weights, a.line_count);
    if (a.d != EPSTADistanceType_Weights && weights != R_NilValue)
        Rf_error("line_weights requires distance = weights.");
    a.has_weights = weights != R_NilValue;
    for (int i = 0; a.has_weights && i < a.line_count; ++i)
        if (a.line_weights.at(i) < 0) Rf_error("line_weights must be non-negative for PST's shortest-path traversal.");
    a.cost = attraction_scalar(point_cost, "point_edge_weight", false, true);
    if (TYPEOF(indices) != LGLSXP || XLENGTH(indices) != 1 || LOGICAL(indices)[0] == NA_LOGICAL)
        Rf_error("destination_indices must be TRUE or FALSE.");
    a.want_indices = LOGICAL(indices)[0];
    return a;
}
// Per radius: distance, then (when requested) the native zero-based destination index, -1 = none.
template <class Sink>
void attraction_distance_multi_compute(const AttractionDistanceMulti& a, Sink& sink)
{
    const auto& graph = *static_cast<const CAxialGraph*>(a.h);
    for (R_xlen_t r = 0; r < a.k; ++r) {
        axial_fault_point();
        ++g_axial.attraction_distance_runs;
        auto coords = attraction_points_copy(a.in);
        attraction_sampling_bounds(a.in, coords, graph, true);
        auto counts = attraction_sizes(a.in);
        std::vector<float> native_weights(a.has_weights ? a.line_count : 0);
        for (size_t i = 0; i < native_weights.size(); ++i) native_weights[i] = static_cast<float>(a.line_weights.at(i));
        std::vector<float> results(a.n);
        std::vector<int> destinations(a.want_indices ? a.n : 0, -1);   // negative initialisation, as in the scalar call
        SPSTAAttractionDistanceDesc desc{};
        desc.m_Graph = a.h; desc.m_OriginType = a.origin_mode; desc.m_DistanceType = static_cast<unsigned char>(a.d);
        desc.m_Radius = a.radii[r];
        desc.m_AttractionPoints = coords.data(); desc.m_AttractionPointCount = static_cast<unsigned int>(coords.size());
        desc.m_PointsPerAttractionPolygon = counts.empty() ? nullptr : counts.data();
        desc.m_AttractionPolygonCount = static_cast<unsigned int>(counts.size());
        desc.m_AttractionPolygonPointInterval = a.in.spacing;
        desc.m_LineWeights = native_weights.empty() ? nullptr : native_weights.data();
        desc.m_LineWeightCount = static_cast<unsigned int>(native_weights.size());
        desc.m_WeightPerMeterForPointEdges = a.cost; desc.m_OutMinDistance = results.data();
        desc.m_OutDestinationIndices = a.want_indices ? destinations.data() : nullptr; desc.m_OutputCount = a.n;
        rpst::progress_attach(desc.m_ProgressCallback, desc.m_ProgressCallbackUser);
        if (!PSTAAttractionDistance(&desc)) throw std::runtime_error("PSTAAttractionDistance failed.");
        sink.add_float(std::move(results), nullptr);
        if (a.want_indices) sink.add_signed(std::move(destinations));
    }
}

struct ODBetweennessMulti {
    HPSTAGraph h{}; SPSTARadii* radii = nullptr; R_xlen_t k = 0; int distance_mode = 0, destination_mode = 0;
    AttractionInput in; int n = 0, points = 0; CoordinateData ow{nullptr, nullptr}, dw{nullptr, nullptr};
    bool has_ow = false, has_dw = false;
};
ODBetweennessMulti od_multi_args(SEXP pointer, SEXP origins, SEXP radii, SEXP distance, SEXP mode, SEXP origin_weights,
                                 SEXP destination_weights)
{
    ODBetweennessMulti a;
    a.h = graph_handle(pointer);
    a.radii = multi_radii(radii, a.k, false);
    const char* distances[] = {"walking", "angular"};
    a.distance_mode = named_mode(distance, distances, 2, "distance");
    const char* destinations[] = {"all", "closest"};
    a.destination_mode = named_mode(mode, destinations, 2, "destination_mode");
    a.in = attraction_input(origins, R_NilValue, R_NilValue, a.h, "origins");
    const auto& graph = *static_cast<const CAxialGraph*>(a.h);
    a.n = graph.getLineCount(); a.points = graph.getPointCount();
    a.ow = analysis_weights(origin_weights, a.in.points.rows, "origin_weights", "origin row");
    a.dw = analysis_weights(destination_weights, a.points, "destination_weights", "native graph point");
    a.has_ow = origin_weights != R_NilValue; a.has_dw = destination_weights != R_NilValue;
    return a;
}
template <class Sink>
void od_multi_compute(const ODBetweennessMulti& a, Sink& sink)
{
    for (R_xlen_t r = 0; r < a.k; ++r) {
        axial_fault_point();
        ++g_axial.od_runs;
        auto coords = attraction_points_copy(a.in);
        std::vector<float> native_origins(a.has_ow ? a.in.points.rows : 0);
        std::vector<float> native_destinations(a.has_dw ? a.points : 0);
        for (size_t i = 0; i < native_origins.size(); ++i) native_origins[i] = static_cast<float>(a.ow.at(i));
        for (size_t i = 0; i < native_destinations.size(); ++i) native_destinations[i] = static_cast<float>(a.dw.at(i));
        std::vector<float> scores(a.n);
        SPSTAODBetweenness desc{};
        desc.m_Graph = a.h;
        desc.m_OriginPoints = coords.empty() ? nullptr : coords.data();
        desc.m_OriginCount = static_cast<unsigned int>(coords.size());
        desc.m_OriginWeights = native_origins.empty() ? nullptr : native_origins.data();
        desc.m_DestinationWeights = native_destinations.empty() ? nullptr : native_destinations.data();
        desc.m_DestinationCount = static_cast<unsigned int>(a.points);
        desc.m_DestinationMode = static_cast<unsigned char>(a.destination_mode);
        desc.m_DistanceType = a.distance_mode == 0 ? EPSTADistanceType_Walking : EPSTADistanceType_Angular;
        desc.m_Radius = a.radii[r];
        desc.m_OutScores = scores.data();
        desc.m_OutputCount = static_cast<unsigned int>(a.n);
        rpst::progress_attach(desc.m_ProgressCallback, desc.m_ProgressCallbackUser);
        if (!PSTAODBetweenness(&desc)) throw std::runtime_error("PSTAODBetweenness failed.");
        sink.add_float(std::move(scores), nullptr);
    }
}

// Shared in-memory / file drivers. `Compute` fills the sink; the messages of the scalar functions are kept (no prefix).
template <class Args, class Compute>
SEXP attraction_multi_frame(const Args& a, R_xlen_t rows, R_xlen_t per_radius, R_xlen_t count_position, Compute compute,
                            const char* unknown)
{
    SEXP result = PROTECT(multi_plain_list(a.k, per_radius, rows, count_position));
    char error[512] = "";
    try {
        NullableRSink sink{result};
        compute(sink);
    } catch (const std::exception& e) { std::snprintf(error, sizeof(error), "%s", e.what()); }
      catch (...) { std::snprintf(error, sizeof(error), "%s", unknown); }
    if (error[0]) Rf_error("%s", error);
    UNPROTECT(1);
    return result;
}
template <class Args, class Compute>
SEXP attraction_multi_stream(const Args& a, R_xlen_t rows, R_xlen_t per_radius, const StreamRequest& request, Compute compute,
                             const char* unknown)
{
    if (per_radius > std::numeric_limits<int>::max() / (a.k ? a.k : 1) - 1) Rf_error("Too many result columns.");
    const auto args = result_stream_args(request, 1 + a.k * per_radius);
    char error[512] = "";
    try {
        auto table = result_new_table(args, static_cast<size_t>(rows));
        NullableTableSink sink{*table, args.names};
        compute(sink);
        result_finish_and_export(args, std::move(table), error, sizeof error);
    } catch (const std::exception& e) { std::snprintf(error, sizeof(error), "%s", e.what()); }
      catch (...) { std::snprintf(error, sizeof(error), "%s", unknown); }
    if (error[0]) Rf_error("%s", error);
    return Rf_ScalarReal(static_cast<double>(rows));
}
} // namespace

extern "C" SEXP rpst_attraction_reach_multi(SEXP pointer, SEXP radii, SEXP origin, SEXP distance, SEXP points, SEXP sizes,
    SEXP interval, SEXP values, SEXP decay, SEXP constant, SEXP distribution, SEXP collection)
{
    const auto a = attraction_reach_multi_args(pointer, radii, origin, distance, points, sizes, interval, values, decay, constant,
                                               distribution, collection);
    return attraction_multi_frame(a, a.n, 1, -1, [&](NullableRSink& s) { attraction_reach_multi_compute(a, s); },
                                  "Unknown native Attraction Reach exception.");
}
extern "C" SEXP rpst_attraction_reach_multi_stream(SEXP pointer, SEXP radii, SEXP origin, SEXP distance, SEXP points, SEXP sizes,
    SEXP interval, SEXP values, SEXP decay, SEXP constant, SEXP distribution, SEXP collection, SEXP stream_pointer, SEXP names,
    SEXP metadata_names, SEXP metadata_values, SEXP batch_rows)
{
    const auto a = attraction_reach_multi_args(pointer, radii, origin, distance, points, sizes, interval, values, decay, constant,
                                               distribution, collection);
    const StreamRequest request{stream_pointer, names, metadata_names, metadata_values, batch_rows};
    return attraction_multi_stream(a, a.n, 1, request, [&](NullableTableSink& s) { attraction_reach_multi_compute(a, s); },
                                   "Unknown native Attraction Reach exception.");
}

extern "C" SEXP rpst_attraction_distance_multi(SEXP pointer, SEXP radii, SEXP origin, SEXP distance, SEXP points, SEXP sizes,
    SEXP interval, SEXP weights, SEXP point_cost, SEXP indices)
{
    const auto a = attraction_distance_multi_args(pointer, radii, origin, distance, points, sizes, interval, weights, point_cost,
                                                  indices);
    return attraction_multi_frame(a, a.n, a.want_indices ? 2 : 1, a.want_indices ? 1 : -1,
                                  [&](NullableRSink& s) { attraction_distance_multi_compute(a, s); },
                                  "Unknown native Attraction Distance exception.");
}
extern "C" SEXP rpst_attraction_distance_multi_stream(SEXP pointer, SEXP radii, SEXP origin, SEXP distance, SEXP points,
    SEXP sizes, SEXP interval, SEXP weights, SEXP point_cost, SEXP indices, SEXP stream_pointer, SEXP names,
    SEXP metadata_names, SEXP metadata_values, SEXP batch_rows)
{
    const auto a = attraction_distance_multi_args(pointer, radii, origin, distance, points, sizes, interval, weights, point_cost,
                                                  indices);
    const StreamRequest request{stream_pointer, names, metadata_names, metadata_values, batch_rows};
    return attraction_multi_stream(a, a.n, a.want_indices ? 2 : 1, request,
                                   [&](NullableTableSink& s) { attraction_distance_multi_compute(a, s); },
                                   "Unknown native Attraction Distance exception.");
}

extern "C" SEXP rpst_od_betweenness_multi(SEXP pointer, SEXP origins, SEXP radii, SEXP distance, SEXP mode,
    SEXP origin_weights, SEXP destination_weights)
{
    const auto a = od_multi_args(pointer, origins, radii, distance, mode, origin_weights, destination_weights);
    return attraction_multi_frame(a, a.n, 1, -1, [&](NullableRSink& s) { od_multi_compute(a, s); },
                                  "Unknown native OD Betweenness exception.");
}
extern "C" SEXP rpst_od_betweenness_multi_stream(SEXP pointer, SEXP origins, SEXP radii, SEXP distance, SEXP mode,
    SEXP origin_weights, SEXP destination_weights, SEXP stream_pointer, SEXP names, SEXP metadata_names,
    SEXP metadata_values, SEXP batch_rows)
{
    const auto a = od_multi_args(pointer, origins, radii, distance, mode, origin_weights, destination_weights);
    const StreamRequest request{stream_pointer, names, metadata_names, metadata_values, batch_rows};
    return attraction_multi_stream(a, a.n, 1, request, [&](NullableTableSink& s) { od_multi_compute(a, s); },
                                   "Unknown native OD Betweenness exception.");
}
