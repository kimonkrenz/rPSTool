// Transient IPSTAlgo results: copy while owned, then free on success or R unwind.
#define R_NO_REMAP
#include <Rinternals.h>
#include <pstalgo/analyses/CreateJunctions.h>
#include <pstalgo/analyses/CreateSegmentMap.h>
#include <cmath>
#include <cstdio>
#include <exception>
#include <limits>
#include <memory>
#include <stdexcept>
#include <vector>

namespace {
double created = 0, freed = 0;
SEXP result_tag() { return Rf_install("rPST::construction-result/v1"); }
void release(SEXP pointer) {
    auto* owner = static_cast<IPSTAlgo*>(R_ExternalPtrAddr(pointer));
    if (!owner) return;
    R_ClearExternalPtr(pointer);
    PSTAFree(owner);
    ++freed;
}
struct Numbers {
    const double* real = nullptr;
    const int* integer = nullptr;
    double at(R_xlen_t i) const {
        return real ? real[i] : (integer[i] == NA_INTEGER ? NA_REAL : integer[i]);
    }
};
Numbers numbers(SEXP x, const char* name) {
    if (TYPEOF(x) != REALSXP && TYPEOF(x) != INTSXP)
        Rf_error("%s must have integer or double storage.", name);
    return {TYPEOF(x) == REALSXP ? REAL(x) : nullptr,
            TYPEOF(x) == INTSXP ? INTEGER(x) : nullptr};
}
struct Matrix {
    R_xlen_t rows = 0;
    int cols = 2;
    Numbers values;
    double at(R_xlen_t i, int col) const { return values.at(i + rows * col); }
};
Matrix matrix(SEXP x, int cols, const char* name, bool optional = false) {
    if (optional && x == R_NilValue) return {};
    if (!Rf_isMatrix(x)) Rf_error("%s must be a numeric matrix with %d columns.", name, cols);
    SEXP dim = Rf_getAttrib(x, R_DimSymbol);
    if (TYPEOF(dim) != INTSXP || XLENGTH(dim) != 2 || INTEGER(dim)[0] < 0 ||
        INTEGER(dim)[1] != cols || XLENGTH(x) != static_cast<R_xlen_t>(INTEGER(dim)[0]) * cols)
        Rf_error("%s must be a numeric matrix with %d columns.", name, cols);
    Matrix out{INTEGER(dim)[0], cols, numbers(x, name)};
    for (R_xlen_t i = 0; i < XLENGTH(x); ++i)
        if (!std::isfinite(out.values.at(i))) Rf_error("%s must contain only finite values.", name);
    return out;
}
bool test_failure(SEXP x) {
    if (TYPEOF(x) != LGLSXP || XLENGTH(x) != 1 || LOGICAL(x)[0] == NA_LOGICAL)
        Rf_error("Invalid construction copy-failure test flag.");
    return LOGICAL(x)[0];
}
struct Layer {
    Matrix coords, indices;
    bool indexed = false;
    R_xlen_t count() const { return indexed ? indices.rows : coords.rows; }
};
Layer layer(SEXP x, SEXP index, const char* name, bool optional) {
    if (x == R_NilValue && optional) {
        if (index != R_NilValue) Rf_error("line_indices_y requires y.");
        return {};
    }
    Layer out{matrix(x, index == R_NilValue ? 4 : 2, name), {}, index != R_NilValue};
    if (out.indexed) {
        out.indices = matrix(index, 2, "line_indices");
        for (R_xlen_t i = 0; i < out.indices.rows * 2; ++i) {
            const double v = out.indices.values.at(i);
            if (v < 1 || v > out.coords.rows || v != std::floor(v))
                Rf_error("line_indices must contain whole one-based coordinate indices.");
        }
    }
    if (out.count() > std::numeric_limits<int>::max() / 2)
        Rf_error("Too many lines for PST's native endpoint indices.");
    return out;
}
struct Bounds {
    double lo[2], hi[2];
    void add(double x, double y) {
        lo[0] = std::min(lo[0], x); hi[0] = std::max(hi[0], x);
        lo[1] = std::min(lo[1], y); hi[1] = std::max(hi[1], y);
    }
};
Bounds bounds(const Matrix& x, R_xlen_t rows) {
    Bounds b{{x.at(0,0),x.at(0,1)},{x.at(0,0),x.at(0,1)}};
    for (R_xlen_t i = 0; i < rows; ++i) {
        b.add(x.at(i,0),x.at(i,1));
        if (x.cols == 4) b.add(x.at(i,2),x.at(i,3));
    }
    return b;
}
void representable(const Matrix& x, double ox, double oy, Bounds& extent) {
    for (R_xlen_t i = 0; i < x.rows; ++i) for (int col = 0; col < x.cols; col += 2) {
        const double px = x.at(i,col) - ox, py = x.at(i,col+1) - oy;
        if (!std::isfinite(px) || !std::isfinite(py) ||
            std::abs(px) > std::numeric_limits<float>::max() ||
            std::abs(py) > std::numeric_limits<float>::max())
            Rf_error("Coordinates overflow PST's local float representation.");
        extent.add(static_cast<float>(px),static_cast<float>(py));
    }
}
void representable_layer(const Layer& x, double ox, double oy, Bounds& extent) {
    if (!x.indexed) { representable(x.coords,ox,oy,extent); return; }
    for (R_xlen_t i=0;i<x.indices.rows*2;++i) {
        const R_xlen_t row=static_cast<R_xlen_t>(x.indices.values.at(i)-1);
        const double px=x.coords.at(row,0)-ox, py=x.coords.at(row,1)-oy;
        if (!std::isfinite(px) || !std::isfinite(py) ||
            std::abs(px)>std::numeric_limits<float>::max() ||
            std::abs(py)>std::numeric_limits<float>::max())
            Rf_error("Coordinates overflow PST's local float representation.");
        extent.add(static_cast<float>(px),static_cast<float>(py));
    }
}
void extent_ok(const Bounds& b, float expansion = 0) {
    const long double dx = static_cast<long double>(b.hi[0]) - b.lo[0] + 2.L * expansion;
    const long double dy = static_cast<long double>(b.hi[1]) - b.lo[1] + 2.L * expansion;
    if (dx*dx + dy*dy > std::numeric_limits<float>::max())
        Rf_error("Coordinate extent overflows PST's native distance representation.");
}
float threshold(SEXP x, const char* name, bool squared) {
    auto data = numbers(x, name);
    if (XLENGTH(x) != 1) Rf_error("%s must be one finite non-negative native float value.", name);
    const double v = data.at(0);
    if (!std::isfinite(v) || v < 0 || v > std::numeric_limits<float>::max() ||
        (v > 0 && static_cast<float>(v) == 0) ||
        (squared && static_cast<long double>(v)*v > std::numeric_limits<float>::max()))
        Rf_error("%s must be one finite non-negative native float value without overflow or underflow.", name);
    return static_cast<float>(v);
}
std::vector<double> copy_coords(const Matrix& x) {
    std::vector<double> out(static_cast<size_t>(x.rows) * x.cols);
    for (R_xlen_t i = 0; i < x.rows; ++i) for (int col = 0; col < x.cols; ++col)
        out[static_cast<size_t>(i) * x.cols + col] = x.at(i,col);
    return out;
}
std::vector<double2> copy_points(const Matrix& x) {
    std::vector<double2> out(static_cast<size_t>(x.rows)*(x.cols/2));
    for (R_xlen_t i=0;i<x.rows;++i) for(int col=0;col<x.cols;col+=2)
        out[static_cast<size_t>(i)*(x.cols/2)+col/2]=double2(x.at(i,col),x.at(i,col+1));
    return out;
}
std::vector<unsigned int> copy_indices(const Layer& x) {
    std::vector<unsigned int> out(static_cast<size_t>(x.indices.rows) * 2);
    for (R_xlen_t i = 0; i < x.indices.rows; ++i) for (int col = 0; col < 2; ++col)
        out[static_cast<size_t>(i)*2+col] = static_cast<unsigned int>(x.indices.at(i,col)-1);
    return out;
}
struct Output {
    SEXP pointer;
    SCreateJunctionsRes junction;
    SCreateSegmentMapRes segment;
    bool segment_map = false, fail_copy = false;
};
void cleanup(void* data, Rboolean) { release(static_cast<Output*>(data)->pointer); }
SEXP copy_result(void* data) {
    const auto& out = *static_cast<Output*>(data);
    if (!out.segment_map) {
        const int n = static_cast<int>(out.junction.m_PointCount);
        SEXP result = PROTECT(Rf_allocMatrix(REALSXP,n,2));
        if (out.fail_copy) Rf_error("Injected construction result-copy failure.");
        double* values = REAL(result);
        for (int i = 0; i < n; ++i) {
            values[i] = out.junction.m_PointCoords[2ull*i];
            values[static_cast<R_xlen_t>(i)+n] = out.junction.m_PointCoords[2ull*i+1];
        }
        UNPROTECT(1); return result;
    }
    const auto& res = out.segment;
    const int n = static_cast<int>(res.m_SegmentCount), nu = static_cast<int>(res.m_UnlinkCount);
    SEXP result = PROTECT(Rf_allocVector(VECSXP,3));
    SEXP lines = PROTECT(Rf_allocMatrix(REALSXP,n,4)); SET_VECTOR_ELT(result,0,lines);
    if (out.fail_copy) Rf_error("Injected construction result-copy failure.");
    SEXP ids = PROTECT(Rf_allocVector(INTSXP,n)); SET_VECTOR_ELT(result,1,ids);
    SEXP unlinks = PROTECT(Rf_allocMatrix(REALSXP,nu,2)); SET_VECTOR_ELT(result,2,unlinks);
    for (int i = 0; i < n; ++i) {
        const auto* s = res.m_Segments + 3ull*i;
        for (int col = 0; col < 4; ++col)
            REAL(lines)[i + static_cast<R_xlen_t>(n)*col] =
                res.m_SegmentCoords[2ull*s[col/2] + col%2];
        INTEGER(ids)[i] = static_cast<int>(s[2]+1);
    }
    for (int i = 0; i < nu; ++i) for (int col = 0; col < 2; ++col)
        REAL(unlinks)[i + static_cast<R_xlen_t>(nu)*col] = res.m_UnlinkCoords[2ull*i+col];
    UNPROTECT(4); return result;
}
SEXP finish(Output& out, const char* error) {
    if (*error) { release(out.pointer); UNPROTECT(1); Rf_error("%s",error); }
    // Native owning input buffers have unwound. The protected pointer owns the
    // result; cleanup releases it on normal return and on every R non-local jump.
    SEXP result = R_UnwindProtect(copy_result,&out,cleanup,&out,nullptr);
    UNPROTECT(1); return result;
}
}

extern "C" SEXP rpst_create_junctions(SEXP x, SEXP ix, SEXP y, SEXP iy, SEXP unlinks, SEXP fault) {
    const auto first = layer(x,ix,"x",false), second = layer(y,iy,"y",true);
    if (!first.count())
        Rf_error("Empty first junction layer is unsupported: pinned PST succeeds without writing its result.");
    const auto unlink = matrix(unlinks,2,"unlinks",true);
    const bool fail_copy = test_failure(fault);
    // Match PST's prefix bounding box for indexed layer 0, without compaction.
    R_xlen_t first_rows = first.coords.rows;
    if (first.indexed) {
        first_rows = 0;
        for (R_xlen_t i = 0; i < first.indices.rows*2; ++i)
            first_rows = std::max(first_rows,static_cast<R_xlen_t>(first.indices.values.at(i)));
    }
    auto world = bounds(first.coords,first_rows);
    const double ox = (world.lo[0]+world.hi[0])*.5, oy = (world.lo[1]+world.hi[1])*.5;
    if (!std::isfinite(ox) || !std::isfinite(oy)) Rf_error("PST's world center overflows double storage.");
    Bounds extent{{0,0},{0,0}};
    representable_layer(first,ox,oy,extent); representable_layer(second,ox,oy,extent); extent_ok(extent);
    for (R_xlen_t i = 0; i < unlink.rows; ++i) {
        const long double dx = std::max(std::abs(static_cast<long double>(unlink.at(i,0))-world.lo[0]),
                                        std::abs(static_cast<long double>(unlink.at(i,0))-world.hi[0]));
        const long double dy = std::max(std::abs(static_cast<long double>(unlink.at(i,1))-world.lo[1]),
                                        std::abs(static_cast<long double>(unlink.at(i,1))-world.hi[1]));
        if (dx*dx+dy*dy > std::numeric_limits<double>::max()) Rf_error("Unlink distance overflows native double storage.");
    }
    SEXP pointer = PROTECT(R_MakeExternalPtr(nullptr,result_tag(),R_NilValue));
    R_RegisterCFinalizerEx(pointer,release,TRUE);
    Output out; out.pointer=pointer; out.fail_copy=fail_copy;
    char error[512] = "";
    try {
        auto coords0=copy_points(first.coords), coords1=copy_points(second.coords), uc=copy_points(unlink);
        auto indices0=copy_indices(first), indices1=copy_indices(second);
        double2 empty_second(0,0);
        SCreateJunctionsDesc desc;
        desc.m_Coords0=coords0.data(); desc.m_Lines0=first.indexed ? indices0.data() : nullptr;
        desc.m_LineCount0=static_cast<unsigned int>(first.count());
        desc.m_Coords1=y==R_NilValue ? nullptr : (coords1.empty() ? &empty_second : coords1.data());
        desc.m_Lines1=second.indexed ? indices1.data() : nullptr; desc.m_LineCount1=static_cast<unsigned int>(second.count());
        desc.m_UnlinkCoords=uc.data(); desc.m_UnlinkCount=static_cast<unsigned int>(unlink.rows);
        desc.m_ProgressCallback=nullptr; desc.m_ProgressCallbackUser=nullptr;
        std::unique_ptr<IPSTAlgo> owner(PSTACreateJunctions(&desc,&out.junction));
        if (!owner) throw std::runtime_error("PSTACreateJunctions failed.");
        R_SetExternalPtrAddr(pointer,owner.release()); ++created;
        if (out.junction.m_PointCount > static_cast<unsigned int>(std::numeric_limits<int>::max()) ||
            (out.junction.m_PointCount && !out.junction.m_PointCoords))
            throw std::runtime_error("Invalid native junction output.");
    } catch (const std::exception& e) { std::snprintf(error,sizeof(error),"%s",e.what()); }
      catch (...) { std::snprintf(error,sizeof(error),"Unknown native junction creation exception."); }
    return finish(out,error);
}

extern "C" SEXP rpst_create_segment_map(SEXP coords, SEXP sections, SEXP type, SEXP snap,
    SEXP tail, SEXP deviation, SEXP extrude, SEXP unlinks, SEXP fault) {
    const auto points=matrix(coords,2,"coords"), unlink=matrix(unlinks,2,"unlinks",true);
    if (!points.rows) Rf_error("coords must contain at least one native edge.");
    auto lengths=numbers(sections,"sections");
    if (Rf_getAttrib(sections,R_DimSymbol)!=R_NilValue || XLENGTH(sections)<1 ||
        XLENGTH(sections)>std::numeric_limits<int>::max()) Rf_error("sections must be a non-empty numeric vector.");
    R_xlen_t total=0, edges=0, bases=0;
    for (R_xlen_t i=0;i<XLENGTH(sections);++i) {
        const double v=lengths.at(i);
        if (!std::isfinite(v) || v!=std::floor(v) || v<std::numeric_limits<int>::min() || v>std::numeric_limits<int>::max())
            Rf_error("sections must contain whole native signed integer lengths.");
        const double n=v<0 ? -1-v : v;
        if (n>points.rows-total) Rf_error("sections must partition exactly the coords rows.");
        total+=static_cast<R_xlen_t>(n); edges+=n>0 ? static_cast<R_xlen_t>(n)-1 : 0;
        if (v>=0) ++bases;
    }
    if (total!=points.rows) Rf_error("sections must partition exactly the coords rows.");
    if (edges<1 || edges>std::numeric_limits<int>::max()/2)
        Rf_error("sections must supply at least one edge within PST's native point-index bounds.");
    const bool center = TYPEOF(type)==STRSXP && XLENGTH(type)==1 && STRING_ELT(type,0)!=NA_STRING &&
        std::strcmp(CHAR(STRING_ELT(type,0)),"road_center_lines")==0;
    if (!center && !(TYPEOF(type)==STRSXP && XLENGTH(type)==1 && STRING_ELT(type,0)!=NA_STRING &&
        std::strcmp(CHAR(STRING_ELT(type,0)),"axial_or_segment")==0)) Rf_error("Unsupported network_type.");
    if (center && unlink.rows) Rf_error("unlinks are only supported for axial_or_segment networks.");
    if (unlink.rows>std::numeric_limits<int>::max()/2) Rf_error("Too many native unlink coordinates.");
    const float fsnap=threshold(snap,"snap",true), ftail=threshold(tail,"tail",false),
                fdeviation=threshold(deviation,"deviation",true), fextrude=threshold(extrude,"extrude",true);
    const bool fail_copy=test_failure(fault);
    const auto world=bounds(points,points.rows);
    const double ox=(world.lo[0]+world.hi[0])*.5, oy=(world.lo[1]+world.hi[1])*.5;
    if (!std::isfinite(ox) || !std::isfinite(oy)) Rf_error("PST's world center overflows double storage.");
    Bounds extent{{0,0},{0,0}};
    representable(points,ox,oy,extent); representable(unlink,ox,oy,extent); extent_ok(extent,std::max(fsnap,fextrude));
    SEXP pointer=PROTECT(R_MakeExternalPtr(nullptr,result_tag(),R_NilValue));
    R_RegisterCFinalizerEx(pointer,release,TRUE);
    Output out; out.pointer=pointer; out.segment_map=true; out.fail_copy=fail_copy;
    char error[512]="";
    try {
        auto pc=copy_coords(points),uc=copy_coords(unlink);
        std::vector<int> sec(XLENGTH(sections));
        for (R_xlen_t i=0;i<XLENGTH(sections);++i) sec[i]=static_cast<int>(lengths.at(i));
        SCreateSegmentMapDesc desc;
        desc.m_Snap=fsnap;desc.m_ExtrudeCut=fextrude;desc.m_MinTail=ftail;desc.m_Min3NodeColinearDeviation=fdeviation;
        desc.m_RoadNetworkType=center ? EPSTARoadNetworkType_RoadCenterLines : EPSTARoadNetworkType_AxialOrSegment;
        desc.m_PolyCoords=pc.data();desc.m_PolySections=sec.data();desc.m_PolyCoordCount=static_cast<unsigned int>(points.rows);
        desc.m_PolySectionCount=static_cast<unsigned int>(sec.size());desc.m_PolyCount=static_cast<unsigned int>(bases);
        desc.m_UnlinkCoords=uc.data();desc.m_UnlinkCount=static_cast<unsigned int>(unlink.rows);
        desc.m_ProgressCallback=nullptr;desc.m_ProgressCallbackUser=nullptr;
        std::unique_ptr<IPSTAlgo> owner(PSTACreateSegmentMap(&desc,&out.segment));
        if (!owner) throw std::runtime_error("PSTACreateSegmentMap failed (including unsafe cyclic detail reduction).");
        R_SetExternalPtrAddr(pointer,owner.release());++created;
        if (out.segment.m_SegmentCount>static_cast<unsigned int>(std::numeric_limits<int>::max()) ||
            out.segment.m_UnlinkCount>static_cast<unsigned int>(std::numeric_limits<int>::max()) ||
            (out.segment.m_SegmentCount && (!out.segment.m_Segments || !out.segment.m_SegmentCoords)) ||
            (out.segment.m_UnlinkCount && !out.segment.m_UnlinkCoords)) throw std::runtime_error("Invalid native segment-map output.");
        for (unsigned int i=0;i<out.segment.m_SegmentCount;++i)
            if (out.segment.m_Segments[3ull*i+2]>=static_cast<unsigned long long>(std::numeric_limits<int>::max()))
                throw std::runtime_error("Native source ID exceeds R integer storage.");
    } catch (const std::exception& e) {std::snprintf(error,sizeof(error),"%s",e.what());}
      catch (...) {std::snprintf(error,sizeof(error),"Unknown native segment-map construction exception.");}
    return finish(out,error);
}
extern "C" SEXP rpst_construction_lifecycle() {
    SEXP out=PROTECT(Rf_allocVector(REALSXP,3));
    REAL(out)[0]=created;REAL(out)[1]=freed;REAL(out)[2]=created-freed;
    UNPROTECT(1);return out;
}
