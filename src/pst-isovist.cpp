// Reusable context; dependent result buffers are copied and freed before return.
#define R_NO_REMAP
#include <Rinternals.h>
#include <cstdint>
#include <pstalgo/analyses/CalculateIsovists.h>
#include <cmath>
#include <cstdio>
#include <exception>
#include <limits>
#include <memory>
#include <stdexcept>
#include <vector>

namespace {
double contexts_created=0, contexts_freed=0, results_created=0, results_freed=0;
SEXP context_tag() { return Rf_install("rPST::isovist-context/v1"); }
SEXP result_tag() { return Rf_install("rPST::isovist-result/v1"); }
struct Context {
    void* handle=nullptr;
    double origin[2]={0,0}, lo[2]={0,0}, hi[2]={0,0};
    uint64_t polygon_vertices=0;
    std::vector<uint32_t> groups[3];
    ~Context() { if(handle) { PSTAFree(static_cast<IPSTAlgo*>(handle)); ++contexts_freed; } }
};
void release_context(SEXP x) {
    auto* owner=static_cast<Context*>(R_ExternalPtrAddr(x));
    R_ClearExternalPtr(x); delete owner;
}
void release_result(SEXP x) {
    auto* owner=static_cast<IPSTAlgo*>(R_ExternalPtrAddr(x));
    if(!owner) return;
    R_ClearExternalPtr(x); PSTAFree(owner); ++results_freed;
}
Context* context(SEXP x) {
    if(TYPEOF(x)!=EXTPTRSXP || R_ExternalPtrTag(x)!=context_tag())
        Rf_error("Expected an exact rPSTool isovist context pointer.");
    auto* p=static_cast<Context*>(R_ExternalPtrAddr(x));
    if(!p || !p->handle) Rf_error("Isovist context is dead or deserialised; reconstruct it from inputs.");
    return p;
}
struct Numbers {
    const double* real=nullptr; const int* integer=nullptr;
    double at(R_xlen_t i) const { return real ? real[i] : (integer[i]==NA_INTEGER ? NA_REAL : integer[i]); }
};
Numbers numbers(SEXP x) {
    if(TYPEOF(x)!=REALSXP && TYPEOF(x)!=INTSXP) Rf_error("Isovist inputs require integer or double storage.");
    return {TYPEOF(x)==REALSXP ? REAL(x):nullptr,TYPEOF(x)==INTSXP ? INTEGER(x):nullptr};
}
struct Geometry {
    Numbers coords, groups, vertices;
    R_xlen_t rows=0, ng=0, np=0;
    bool polygon=false;
};
Geometry geometry(SEXP x, bool polygon) {
    if(TYPEOF(x)!=VECSXP || XLENGTH(x)!=(polygon ? 3:2)) Rf_error("Invalid native isovist geometry descriptor.");
    SEXP xy=VECTOR_ELT(x,0), groups=VECTOR_ELT(x,1);
    if(!Rf_isMatrix(xy)) Rf_error("Isovist coordinates must be two-column matrices.");
    SEXP dim=Rf_getAttrib(xy,R_DimSymbol);
    if(TYPEOF(dim)!=INTSXP || XLENGTH(dim)!=2 || INTEGER(dim)[0]<0 || INTEGER(dim)[1]!=2 ||
       XLENGTH(xy)!=2*static_cast<R_xlen_t>(INTEGER(dim)[0])) Rf_error("Invalid isovist coordinate dimensions.");
    Geometry g; g.rows=INTEGER(dim)[0]; g.coords=numbers(xy); g.groups=numbers(groups);
    g.ng=XLENGTH(groups); g.polygon=polygon;
    if(g.ng>256) Rf_error("Isovist visibility supports at most 256 combined groups.");
    double objects=0;
    for(R_xlen_t i=0;i<g.ng;++i) {
        double n=g.groups.at(i);
        if(!std::isfinite(n) || n<0 || n>16777216 || n!=std::floor(n))
            Rf_error("Isovist group counts must be whole values from 0 to 2^24.");
        objects+=n;
    }
    if(objects>std::numeric_limits<int>::max()) Rf_error("Too many isovist objects for native indexing.");
    if(polygon) {
        SEXP vertices=VECTOR_ELT(x,2); g.vertices=numbers(vertices);g.np=XLENGTH(vertices);
        if(g.np!=objects) Rf_error("Polygon counts do not match the group partition.");
        double ncoords=0;
        for(R_xlen_t i=0;i<g.np;++i) {
            double n=g.vertices.at(i);
            if(!std::isfinite(n) || n<1 || n>g.rows || n!=std::floor(n))
                Rf_error("Polygon vertex counts must be positive whole coordinate counts.");
            ncoords+=n;
        }
        if(ncoords!=g.rows) Rf_error("Polygon vertex counts do not partition coordinate rows.");
    } else if(objects!=g.rows) Rf_error("Point group counts do not partition coordinate rows.");
    for(R_xlen_t i=0;i<2*g.rows;++i)
        if(!std::isfinite(g.coords.at(i))) Rf_error("Isovist coordinates must be finite.");
    return g;
}
struct Buffers {
    std::vector<double> coords; std::vector<uint32_t> groups,vertices;
    explicit Buffers(const Geometry& g) {
        coords.resize(static_cast<size_t>(g.rows)*2);
        for(R_xlen_t i=0;i<g.rows;++i) for(int col=0;col<2;++col)
            coords[static_cast<size_t>(i)*2+col]=g.coords.at(i+col*g.rows);
        for(R_xlen_t i=0;i<g.ng;++i) groups.push_back(static_cast<uint32_t>(g.groups.at(i)));
        for(R_xlen_t i=0;i<g.np;++i) vertices.push_back(static_cast<uint32_t>(g.vertices.at(i)));
    }
    SCreateIsovistContextDesc::SPolygons polygons() {
        return {static_cast<uint32_t>(groups.size()),groups.data(),vertices.data(),coords.data()};
    }
    SCreateIsovistContextDesc::SPoints points() {
        return {static_cast<uint32_t>(groups.size()),groups.data(),coords.data()};
    }
};
void extent(double lx,double ly,double hx,double hy) {
    const long double dx=static_cast<long double>(hx)-lx,dy=static_cast<long double>(hy)-ly;
    if(dx*dx+dy*dy>std::numeric_limits<float>::max())
        Rf_error("Isovist extent overflows native float distances.");
}
float scalar(SEXP x,const char* name,double minimum,double maximum) {
    Numbers n=numbers(x);
    if(XLENGTH(x)!=1) Rf_error("%s must be a single native float value.",name);
    double v=n.at(0);
    if(!std::isfinite(v) || v<minimum || v>maximum || (v!=0 && static_cast<float>(v)==0))
        Rf_error("%s is outside its finite native float bounds.",name);
    return static_cast<float>(v);
}
struct Output { SEXP pointer; SCalculateIsovistDesc desc; bool fail_copy=false; };
void cleanup(void* p,Rboolean) { release_result(static_cast<Output*>(p)->pointer); }
SEXP copy_result(void* p) {
    auto& o=*static_cast<Output*>(p);auto& d=o.desc;
    SEXP result=PROTECT(Rf_allocVector(VECSXP,5));
    const int n=static_cast<int>(d.m_OutPointCount);
    SEXP xy=PROTECT(Rf_allocMatrix(REALSXP,n,2));SET_VECTOR_ELT(result,0,xy);
    if(o.fail_copy) Rf_error("Injected isovist result-copy failure.");
    for(int i=0;i<n;++i) {
        REAL(xy)[i]=d.m_OutPoints[2ull*i];REAL(xy)[static_cast<R_xlen_t>(i)+n]=d.m_OutPoints[2ull*i+1];
    }
    SET_VECTOR_ELT(result,1,Rf_ScalarReal(d.m_OutArea));
    SCalculateIsovistDesc::SVisibleObjects* vis[]={&d.m_OutVisibleObstacles,&d.m_OutVisibleAttractionPoints,&d.m_OutVisibleAttractionPolygons};
    for(int k=0;k<3;++k) {
        const auto& v=*vis[k];
        SEXP groups=PROTECT(Rf_allocVector(VECSXP,v.GroupCount));SET_VECTOR_ELT(result,k+2,groups);
        size_t at=0;
        for(uint32_t g=0;g<v.GroupCount;++g) {
            SEXP ids=PROTECT(Rf_allocVector(INTSXP,v.CountPerGroup[g]));SET_VECTOR_ELT(groups,g,ids);
            for(uint32_t i=0;i<v.CountPerGroup[g];++i) INTEGER(ids)[i]=static_cast<int>(v.Indices[at++])+1;
            UNPROTECT(1);
        }
        UNPROTECT(1);
    }
    UNPROTECT(2);return result;
}
}
extern "C" SEXP rpst_isovist_context_create(SEXP obstacles,SEXP points,SEXP polygons) {
    Geometry geometry_sets[]={geometry(obstacles,true),geometry(points,false),geometry(polygons,true)};
    if(geometry_sets[0].ng+geometry_sets[1].ng+geometry_sets[2].ng>256)
        Rf_error("Isovist visibility supports at most 256 combined groups.");
    if(geometry_sets[0].rows+geometry_sets[2].rows>std::numeric_limits<int>::max()/2)
        Rf_error("Too many polygon vertices for native edge indexing.");
    double lo[2]={0,0},hi[2]={0,0};bool first=true;
    for(const auto& g:geometry_sets) for(R_xlen_t i=0;i<g.rows;++i) {
        for(int c=0;c<2;++c) {
            double v=g.coords.at(i+c*g.rows);
            lo[c]=first ? v:std::min(lo[c],v);hi[c]=first ? v:std::max(hi[c],v);
        }
        first=false;
    }
    double origin[2]={0,0};
    if(!first) for(int c=0;c<2;++c) {
        origin[c]=std::trunc((lo[c]+hi[c])*.5);
        if(!std::isfinite(origin[c])) Rf_error("Isovist world center overflows double coordinates.");
        lo[c]=static_cast<float>(lo[c]-origin[c]);hi[c]=static_cast<float>(hi[c]-origin[c]);
        if(!std::isfinite(lo[c]) || !std::isfinite(hi[c])) Rf_error("Isovist coordinates overflow native local floats.");
    }
    extent(lo[0],lo[1],hi[0],hi[1]);
    SEXP pointer=PROTECT(R_MakeExternalPtr(nullptr,context_tag(),R_NilValue));
    R_RegisterCFinalizerEx(pointer,release_context,TRUE);
    char error[256]={0};
    try {
        Buffers a(geometry_sets[0]),b(geometry_sets[1]),c(geometry_sets[2]);
        auto owner=std::make_unique<Context>();
        SCreateIsovistContextDesc d;
        d.ObstaclePolygons=a.polygons();d.AttractionPoints=b.points();d.AttractionPolygons=c.polygons();
        d.m_ProgressCallback=nullptr;d.m_ProgressCallbackUser=nullptr;
        for(int i=0;i<3;++i) {
            owner->groups[i]=(i==0 ? a.groups : i==1 ? b.groups:c.groups);
        }
        for(int i=0;i<2;++i) {owner->origin[i]=origin[i];owner->lo[i]=lo[i];owner->hi[i]=hi[i];}
        owner->polygon_vertices=static_cast<uint64_t>(geometry_sets[0].rows)+geometry_sets[2].rows;
        owner->handle=PSTACreateIsovistContext(&d);
        if(!owner->handle) throw std::runtime_error("PST isovist context creation failed.");
        ++contexts_created;R_SetExternalPtrAddr(pointer,owner.release());
    } catch(const std::exception& e) {std::snprintf(error,sizeof(error),"%s",e.what());}
      catch(...) {std::snprintf(error,sizeof(error),"Unknown isovist context failure.");}
    if(error[0]) {UNPROTECT(1);Rf_error("%s",error);}
    UNPROTECT(1);return pointer;
}
extern "C" SEXP rpst_isovist_context_release(SEXP x) {
    if(TYPEOF(x)!=EXTPTRSXP || R_ExternalPtrTag(x)!=context_tag()) Rf_error("Expected an exact rPSTool isovist context pointer.");
    release_context(x);return R_NilValue;
}
extern "C" SEXP rpst_isovist_calculate(SEXP x,SEXP origin,SEXP distance,SEXP fov,SEXP direction,SEXP resolution,SEXP fault) {
    Context* owner=context(x);
    Numbers coords=numbers(origin);
    if(XLENGTH(origin)!=2) Rf_error("Isovist origin must contain two finite coordinates.");
    double world[2]={coords.at(0),coords.at(1)},local[2];
    for(int c=0;c<2;++c) {
        local[c]=static_cast<float>(world[c]-owner->origin[c]);
        if(!std::isfinite(world[c]) || !std::isfinite(local[c])) Rf_error("Isovist origin overflows native coordinates.");
    }
    float radius=scalar(distance,"max_distance",0,std::sqrt(std::numeric_limits<float>::max()));
    float view=scalar(fov,"field_of_view",0,360);
    float angle=scalar(direction,"direction",-std::numeric_limits<float>::max(),std::numeric_limits<float>::max());
    Numbers res=numbers(resolution);
    if(XLENGTH(resolution)!=1 || !std::isfinite(res.at(0)) || res.at(0)<3 || res.at(0)>std::numeric_limits<int>::max()/2 || res.at(0)!=std::floor(res.at(0)))
        Rf_error("perimeter_segments must be a whole native count of at least 3.");
    uint32_t segments=static_cast<uint32_t>(res.at(0));
    const double arc_segments=std::ceil((view*segments)/360.0f);
    if(arc_segments+owner->polygon_vertices>std::numeric_limits<int>::max()/2)
        Rf_error("Too many calculated isovist edges for native vertex indexing.");
    const float half_angle=3.1415926535897932384626433832795f/segments;
    const float outer=radius*std::sqrt(3.1415926535897932384626433832795f/(segments*std::sin(half_angle)*std::cos(half_angle)));
    if(!std::isfinite(outer)) Rf_error("Isovist clipping radius overflows native floats.");
    extent(std::min(owner->lo[0],local[0]-outer),std::min(owner->lo[1],local[1]-outer),
           std::max(owner->hi[0],local[0]+outer),std::max(owner->hi[1],local[1]+outer));
    if(TYPEOF(fault)!=LGLSXP || XLENGTH(fault)!=1 || LOGICAL(fault)[0]==NA_LOGICAL) Rf_error("Invalid isovist copy-failure flag.");
    SEXP pointer=PROTECT(R_MakeExternalPtr(nullptr,result_tag(),x));
    R_RegisterCFinalizerEx(pointer,release_result,TRUE);
    Output out;out.pointer=pointer;out.fail_copy=LOGICAL(fault)[0];
    auto& d=out.desc;
    d.m_IsovistContext=owner->handle;d.m_OriginX=world[0];d.m_OriginY=world[1];
    d.m_MaxViewDistance=radius;d.m_FieldOfViewDegrees=view;d.m_DirectionDegrees=angle;d.m_PerimeterSegmentCount=segments;
    d.m_OutPointCount=0;d.m_OutPoints=nullptr;d.m_OutIsovistHandle=nullptr;d.m_OutArea=0;
    d.m_OutVisibleObstacles={};d.m_OutVisibleAttractionPoints={};d.m_OutVisibleAttractionPolygons={};
    d.m_ProgressCallback=nullptr;d.m_ProgressCallbackUser=nullptr;
    char error[256]={0};
    try {
        PSTACalculateIsovist(&d);
        if(!d.m_OutIsovistHandle) throw std::runtime_error("PST isovist calculation failed: no result was published.");
        R_SetExternalPtrAddr(pointer,d.m_OutIsovistHandle);++results_created;
        if(d.m_OutPointCount>std::numeric_limits<int>::max() || (d.m_OutPointCount && !d.m_OutPoints))
            throw std::runtime_error("Invalid native isovist point output.");
        SCalculateIsovistDesc::SVisibleObjects* vis[]={&d.m_OutVisibleObstacles,&d.m_OutVisibleAttractionPoints,&d.m_OutVisibleAttractionPolygons};
        for(int k=0;k<3;++k) {
            const auto& v=*vis[k];
            if(v.GroupCount!=owner->groups[k].size() || (v.GroupCount && !v.CountPerGroup) || (v.ObjectCount && !v.Indices))
                throw std::runtime_error("Invalid native isovist visibility output.");
            size_t total=0;
            for(uint32_t g=0;g<v.GroupCount;++g) {
                if(v.CountPerGroup[g]>owner->groups[k][g] || total+v.CountPerGroup[g]>v.ObjectCount)
                    throw std::runtime_error("Invalid native isovist visibility partition.");
                for(uint32_t i=0;i<v.CountPerGroup[g];++i)
                    if(v.Indices[total+i]>=owner->groups[k][g]) throw std::runtime_error("Invalid native isovist visibility index.");
                total+=v.CountPerGroup[g];
            }
            if(total!=v.ObjectCount) throw std::runtime_error("Invalid native isovist visibility total.");
        }
    } catch(const std::exception& e) {std::snprintf(error,sizeof(error),"%s",e.what());}
      catch(...) {std::snprintf(error,sizeof(error),"Unknown isovist calculation failure.");}
    if(error[0]) {release_result(pointer);UNPROTECT(1);Rf_error("%s",error);}
    SEXP result=R_UnwindProtect(copy_result,&out,cleanup,&out,nullptr);
    UNPROTECT(1);return result;
}
extern "C" SEXP rpst_isovist_lifecycle() {
    SEXP out=PROTECT(Rf_allocVector(REALSXP,6));
    double values[]={contexts_created,contexts_freed,contexts_created-contexts_freed,results_created,results_freed,results_created-results_freed};
    for(int i=0;i<6;++i) REAL(out)[i]=values[i];
    UNPROTECT(1);return out;
}
