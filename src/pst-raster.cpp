// Comparison owns the raster; inspection and polygon results are copied to R.
#define R_NO_REMAP
#include <Rinternals.h>
#include <pstalgo/analyses/CreateBufferPolygons.h>
#include <pstalgo/analyses/RasterToPolygons.h>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <exception>
#include <limits>
#include <memory>
#include <stdexcept>
#include <vector>

namespace {
double comparisons_created=0, comparisons_freed=0, polygons_created=0, polygons_freed=0;
SEXP raster_tag() { return Rf_install("rPST::comparison-raster/v1"); }
SEXP polygon_tag() { return Rf_install("rPST::raster-polygons/v1"); }
struct Raster {
    IPSTAlgo* handle=nullptr;
    void* raster=nullptr;
    float minimum=0,maximum=0;
    ~Raster() { if(handle) { PSTAFree(handle); ++comparisons_freed; } }
};
void release_raster(SEXP x) {
    auto* p=static_cast<Raster*>(R_ExternalPtrAddr(x));
    R_ClearExternalPtr(x); delete p;
}
void release_polygons(SEXP x) {
    auto* p=static_cast<IPSTAlgo*>(R_ExternalPtrAddr(x));
    if(!p) return;
    R_ClearExternalPtr(x); PSTAFree(p); ++polygons_freed;
}
Raster* raster(SEXP x) {
    if(TYPEOF(x)!=EXTPTRSXP || R_ExternalPtrTag(x)!=raster_tag())
        Rf_error("Expected an exact rPSTool comparison raster pointer.");
    auto* p=static_cast<Raster*>(R_ExternalPtrAddr(x));
    if(!p || !p->handle || !p->raster)
        Rf_error("Raster is dead or deserialised; recreate the comparison.");
    return p;
}
struct Numbers {
    const double* real=nullptr; const int* integer=nullptr;
    double at(R_xlen_t i) const { return real ? real[i] : integer[i]==NA_INTEGER ? NA_REAL : integer[i]; }
};
Numbers numbers(SEXP x) {
    if(TYPEOF(x)!=REALSXP && TYPEOF(x)!=INTSXP) Rf_error("Raster inputs require integer or double storage.");
    return {TYPEOF(x)==REALSXP ? REAL(x):nullptr,TYPEOF(x)==INTSXP ? INTEGER(x):nullptr};
}
int rows(SEXP x,int columns) {
    if(!Rf_isMatrix(x)) Rf_error("Raster coordinates/ranges must be numeric matrices.");
    SEXP dim=Rf_getAttrib(x,R_DimSymbol);
    if(TYPEOF(dim)!=INTSXP || XLENGTH(dim)!=2 || INTEGER(dim)[0]<0 ||
       INTEGER(dim)[1]!=columns || XLENGTH(x)!=static_cast<R_xlen_t>(INTEGER(dim)[0])*columns)
        Rf_error("Invalid raster matrix dimensions; expected %d columns.",columns);
    numbers(x); return INTEGER(dim)[0];
}
bool native_float(double v) {
    return std::isfinite(v) && std::abs(v)<=std::numeric_limits<float>::max() &&
        (v==0 || static_cast<float>(v)!=0);
}
float scalar(SEXP x,const char* name,bool nonnegative,bool positive) {
    Numbers n=numbers(x);
    if(XLENGTH(x)!=1 || !native_float(n.at(0)) ||
       (nonnegative && n.at(0)<0) || (positive && n.at(0)<=0))
        Rf_error("%s is outside its finite native float bounds.",name);
    return static_cast<float>(n.at(0));
}
struct Lines {
    Numbers xy,values; int count=0;
};
Lines lines(SEXP x,SEXP values,bool optional) {
    Lines l;
    if(optional && x==R_NilValue) { l.values=numbers(values); return l; }
    l.count=rows(x,4);l.xy=numbers(x);l.values=numbers(values);
    if(l.count==0 || l.count>std::numeric_limits<int>::max()/2)
        Rf_error("Raster line layers require a positive count within native coordinate bounds.");
    if(XLENGTH(values)!=l.count) Rf_error("Raster values must match line rows.");
    for(R_xlen_t i=0;i<4*static_cast<R_xlen_t>(l.count);++i)
        if(!std::isfinite(l.xy.at(i))) Rf_error("Raster coordinates must be finite.");
    return l;
}
void values(const Lines& l,int count) {
    for(int i=0;i<count;++i)
        if(!native_float(l.values.at(i))) Rf_error("Raster values exceed finite native float bounds.");
}
void validate_extent(const Lines& a,const Lines& b,float blur,float res) {
    double lo[2]={a.xy.at(0),a.xy.at(a.count)},hi[2]={lo[0],lo[1]};
    for(const auto& l:{a,b}) for(int i=0;i<l.count;++i) for(int endpoint=0;endpoint<2;++endpoint)
        for(int c=0;c<2;++c) {
            double v=l.xy.at(i+static_cast<R_xlen_t>(2*endpoint+c)*l.count);
            lo[c]=std::min(lo[c],v);hi[c]=std::max(hi[c],v);
        }
    const float inv=1.f/res,inflate=blur*3.f,sigma=blur*inv;
    if(!std::isfinite(inv) || !std::isfinite(inflate) || !std::isfinite(sigma) ||
       static_cast<double>(std::ceil(sigma*3.f))>std::numeric_limits<int>::max()-1)
        Rf_error("Raster resolution or blur overflows native kernel bounds.");
    double dims[2],origin[2];
    for(int c=0;c<2;++c) {
        lo[c]=std::floor((lo[c]-inflate)*inv)*res;
        hi[c]=std::ceil((hi[c]+inflate)*inv)*res;
        dims[c]=std::round(inv*(hi[c]-lo[c]));origin[c]=lo[c]+.5*res;
        if(!std::isfinite(lo[c]) || !std::isfinite(hi[c]) || !std::isfinite(origin[c]) ||
           !std::isfinite(dims[c]) || dims[c]<1 || dims[c]>std::numeric_limits<int>::max())
            Rf_error("Raster extent must produce positive dimensions within native bounds.");
    }
    if(dims[0]*dims[1]>std::numeric_limits<uint32_t>::max()/sizeof(float))
        Rf_error("Raster byte count overflows PST's unsigned allocation/index arithmetic.");
    for(const auto& l:{a,b}) for(int i=0;i<l.count;++i) {
        float p[4];
        for(int j=0;j<4;++j) {
            const float local=static_cast<float>(l.xy.at(i+static_cast<R_xlen_t>(j)*l.count)-origin[j%2]);
            p[j]=local*inv;
            if(!std::isfinite(local) || !std::isfinite(p[j]) || std::abs(p[j])>static_cast<float>(std::numeric_limits<int>::max()/2))
                Rf_error("Raster coordinates overflow native pixel indexing.");
        }
        const float dx=p[2]-p[0],dy=p[3]-p[1],squared=dx*dx+dy*dy;
        if(!std::isfinite(squared) || static_cast<double>(std::ceil(std::sqrt(squared)*2.f))>std::numeric_limits<int>::max())
            Rf_error("Raster line sampling overflows native counts.");
    }
}
struct Buffers {
    std::vector<double> coords; std::vector<float> scores;
    Buffers(const Lines& l,int count) {
        coords.resize(static_cast<size_t>(l.count)*4);
        for(int i=0;i<l.count;++i) for(int j=0;j<4;++j)
            coords[static_cast<size_t>(i)*4+j]=l.xy.at(i+static_cast<R_xlen_t>(j)*l.count);
        scores.resize(count);for(int i=0;i<count;++i) scores[i]=static_cast<float>(l.values.at(i));
    }
};
SRasterData data(Raster* owner) {
    SRasterData d;
    if(PSTAGetRasterData(owner->raster,&d)!=PSTA_RESULT_OK)
        throw std::runtime_error("PST raster inspection failed.");
    const uint64_t bytes=static_cast<uint64_t>(d.Pitch)*d.Height;
    const unsigned pixel=d.Format==RasterFormat_Float ? sizeof(float) : d.Format==RasterFormat_Byte ? 1:0;
    if(!pixel || !d.Width || !d.Height || !d.Bits || d.Width>std::numeric_limits<int>::max() ||
       d.Height>std::numeric_limits<int>::max() || d.Pitch<static_cast<uint64_t>(d.Width)*pixel ||
       bytes>std::numeric_limits<uint32_t>::max())
        throw std::runtime_error("Invalid native raster storage.");
    return d;
}
bool flag(SEXP x) {
    if(TYPEOF(x)!=LGLSXP || XLENGTH(x)!=1 || LOGICAL(x)[0]==NA_LOGICAL)
        Rf_error("Invalid raster copy-failure flag.");
    return LOGICAL(x)[0];
}
struct PolygonOutput {
    SEXP pointer; SRasterToPolygonsDesc desc; bool fail_copy=false;
};
void cleanup(void* p,Rboolean) { release_polygons(static_cast<PolygonOutput*>(p)->pointer); }
SEXP copy_polygons(void* p) {
    auto& o=*static_cast<PolygonOutput*>(p);auto& d=o.desc;
    SEXP result=PROTECT(Rf_allocVector(VECSXP,d.RangeCount));
    if(o.fail_copy) Rf_error("Injected raster polygon-copy failure.");
    size_t at=0,xy=0;
    for(uint32_t r=0;r<d.RangeCount;++r) {
        SEXP group=PROTECT(Rf_allocVector(VECSXP,d.OutPolygonCountPerRange[r]));SET_VECTOR_ELT(result,r,group);
        for(uint32_t i=0;i<d.OutPolygonCountPerRange[r];++i) {
            uint32_t nr=d.OutPolygonData[at++];
            SEXP poly=PROTECT(Rf_allocVector(VECSXP,nr));SET_VECTOR_ELT(group,i,poly);
            for(uint32_t k=0;k<nr;++k) {
                uint32_t n=d.OutPolygonData[at++];
                SEXP ring=PROTECT(Rf_allocMatrix(REALSXP,static_cast<int>(n),2));SET_VECTOR_ELT(poly,k,ring);
                for(uint32_t j=0;j<n;++j) {
                    REAL(ring)[j]=d.OutPolygonCoords[2*(xy+j)];
                    REAL(ring)[static_cast<R_xlen_t>(j)+n]=d.OutPolygonCoords[2*(xy+j)+1];
                }
                xy+=n;UNPROTECT(1);
            }
            UNPROTECT(1);
        }
        UNPROTECT(1);
    }
    UNPROTECT(1);return result;
}
}
extern "C" SEXP rpst_compare_results(SEXP x,SEXP v1,SEXP v2,SEXP y,SEXP mode,SEXP blur,SEXP resolution,SEXP m) {
    Lines a=lines(x,v1,false),b=lines(y,v2,true);
    if(y==R_NilValue && XLENGTH(v2)!=a.count) Rf_error("Raster values2 must match the first line layer.");
    values(a,a.count);values(b,y==R_NilValue ? a.count:b.count);
    if(TYPEOF(mode)!=INTSXP || XLENGTH(mode)!=1 || (INTEGER(mode)[0]!=0 && INTEGER(mode)[0]!=1))
        Rf_error("Invalid raster comparison mode.");
    const float sigma=scalar(blur,"blur_radius",true,false),res=scalar(resolution,"resolution",true,true),
        minimum=scalar(m,"m",false,false);
    validate_extent(a,b,sigma,res);
    SEXP pointer=PROTECT(R_MakeExternalPtr(nullptr,raster_tag(),R_NilValue));
    R_RegisterCFinalizerEx(pointer,release_raster,TRUE);
    char error[256]={0};
    try {
        Buffers before(a,a.count),after(b,y==R_NilValue ? a.count:b.count);
        auto owner=std::make_unique<Raster>();
        SCompareResultsDesc d;
        d.LineCount1=a.count;d.LineCoords1=before.coords.data();d.Values1=before.scores.data();
        d.LineCount2=b.count;d.LineCoords2=b.count ? after.coords.data():nullptr;d.Values2=after.scores.data();
        d.Mode=static_cast<SCompareResultsDesc::EMode>(INTEGER(mode)[0]);d.M=minimum;
        d.BlurRadius=sigma;d.Resolution=res;d.OutRaster=nullptr;d.OutMin=0;d.OutMax=0;
        d.m_ProgressCallback=nullptr;d.m_ProgressCallbackUser=nullptr;
        owner->handle=static_cast<IPSTAlgo*>(PSTACompareResults(&d));
        if(!owner->handle) throw std::runtime_error("PST raster comparison failed.");
        ++comparisons_created;owner->raster=d.OutRaster;owner->minimum=d.OutMin;owner->maximum=d.OutMax;
        if(!owner->raster) throw std::runtime_error("PST comparison published no raster.");
        data(owner.get());R_SetExternalPtrAddr(pointer,owner.release());
    } catch(const std::exception& e) {std::snprintf(error,sizeof(error),"%s",e.what());}
      catch(...) {std::snprintf(error,sizeof(error),"Unknown raster comparison failure.");}
    if(error[0]) {UNPROTECT(1);Rf_error("%s",error);}
    UNPROTECT(1);return pointer;
}
extern "C" SEXP rpst_raster_release(SEXP x) {
    if(TYPEOF(x)!=EXTPTRSXP || R_ExternalPtrTag(x)!=raster_tag()) Rf_error("Expected an exact rPSTool comparison raster pointer.");
    release_raster(x);return R_NilValue;
}
extern "C" SEXP rpst_raster_data(SEXP x) {
    Raster* owner=raster(x);SRasterData d;bool inspected=false;char error[256]={0};
    try {d=data(owner);inspected=true;}
    catch(const std::exception& e) {std::snprintf(error,sizeof(error),"%s",e.what());}
    catch(...) {std::snprintf(error,sizeof(error),"Unknown raster inspection failure.");}
    // d is read only after a successful inspection, even if an exception carried an empty message.
    if(!inspected) Rf_error("%s",error[0] ? error : "PST raster inspection failed.");
    SEXP result=PROTECT(Rf_allocVector(VECSXP,7));
    SEXP bbox=PROTECT(Rf_allocVector(REALSXP,4));SET_VECTOR_ELT(result,0,bbox);
    double bb[]={d.BBMinX,d.BBMinY,d.BBMaxX,d.BBMaxY};for(int i=0;i<4;++i) REAL(bbox)[i]=bb[i];
    SEXP dims=PROTECT(Rf_allocVector(INTSXP,2));SET_VECTOR_ELT(result,1,dims);
    INTEGER(dims)[0]=d.Width;INTEGER(dims)[1]=d.Height;
    SET_VECTOR_ELT(result,2,Rf_ScalarReal(d.Pitch));SET_VECTOR_ELT(result,3,Rf_mkString(d.Format==RasterFormat_Float ? "float":"byte"));
    SET_VECTOR_ELT(result,4,Rf_ScalarReal(owner->minimum));SET_VECTOR_ELT(result,5,Rf_ScalarReal(owner->maximum));
    SEXP pixels=PROTECT(Rf_allocMatrix(d.Format==RasterFormat_Float ? REALSXP:INTSXP,d.Height,d.Width));
    SET_VECTOR_ELT(result,6,pixels);
    for(uint32_t row=0;row<d.Height;++row) {
        const auto* bytes=static_cast<const unsigned char*>(d.Bits)+static_cast<size_t>(row)*d.Pitch;
        for(uint32_t col=0;col<d.Width;++col) {
            R_xlen_t at=row+static_cast<R_xlen_t>(col)*d.Height;
            if(d.Format==RasterFormat_Float) {
                float v;std::memcpy(&v,bytes+static_cast<size_t>(col)*sizeof(float),sizeof(v));REAL(pixels)[at]=v;
            } else INTEGER(pixels)[at]=bytes[col];
        }
    }
    UNPROTECT(4);return result;
}
extern "C" SEXP rpst_raster_polygons(SEXP x,SEXP ranges,SEXP fault) {
    Raster* owner=raster(x);int nr=rows(ranges,2);Numbers limits=numbers(ranges);bool fail=flag(fault);
    for(R_xlen_t i=0;i<2*static_cast<R_xlen_t>(nr);++i) {
        double v=limits.at(i);
        if(std::isnan(v) || (std::isfinite(v) && !native_float(v))) Rf_error("Raster ranges must be native float limits, optionally infinite.");
    }
    SEXP pointer=PROTECT(R_MakeExternalPtr(nullptr,polygon_tag(),x));
    R_RegisterCFinalizerEx(pointer,release_polygons,TRUE);
    PolygonOutput out;out.pointer=pointer;out.fail_copy=fail;char error[256]={0};
    try {
        SRasterData storage=data(owner);
        std::vector<SRasterToPolygonsDesc::SRange> native_ranges(nr);
        for(int i=0;i<nr;++i) native_ranges[i]={static_cast<float>(limits.at(i)),static_cast<float>(limits.at(i+nr))};
        auto& d=out.desc;d.Raster=owner->raster;d.RangeCount=nr;d.Ranges=native_ranges.data();
        d.OutPolygonCountPerRange=nullptr;d.OutPolygonData=nullptr;d.OutPolygonCoords=nullptr;
        d.m_ProgressCallback=nullptr;d.m_ProgressCallbackUser=nullptr;
        IPSTAlgo* handle=static_cast<IPSTAlgo*>(PSTARasterToPolygons(&d));
        if(!handle) throw std::runtime_error("PST raster polygon conversion failed.");
        R_SetExternalPtrAddr(pointer,handle);++polygons_created;
        if(nr && !d.OutPolygonCountPerRange) throw std::runtime_error("Invalid native polygon counts.");
        const uint64_t bound=4ull*storage.Width*storage.Height;
        uint64_t total=0,coords=0;size_t at=0;
        for(int r=0;r<nr;++r) {
            uint32_t count=d.OutPolygonCountPerRange[r];
            if(count>std::numeric_limits<int>::max() || count>bound || (count && !d.OutPolygonData))
                throw std::runtime_error("Invalid native polygon partition.");
            for(uint32_t i=0;i<count;++i) {
                uint32_t rings=d.OutPolygonData[at++];
                if(rings>std::numeric_limits<int>::max() || (total+=rings)>bound)
                    throw std::runtime_error("Invalid native ring partition.");
                for(uint32_t j=0;j<rings;++j) {
                    uint32_t n=d.OutPolygonData[at++];
                    if(n>std::numeric_limits<int>::max() || (coords+=n)>bound || (n && !d.OutPolygonCoords))
                        throw std::runtime_error("Invalid native ring coordinates.");
                }
            }
            // Each range runs an independent native grid traversal.
            total=coords=0;
        }
    } catch(const std::exception& e) {std::snprintf(error,sizeof(error),"%s",e.what());}
      catch(...) {std::snprintf(error,sizeof(error),"Unknown raster polygon failure.");}
    if(error[0]) {release_polygons(pointer);UNPROTECT(1);Rf_error("%s",error);}
    SEXP result=R_UnwindProtect(copy_polygons,&out,cleanup,&out,nullptr);
    UNPROTECT(1);return result;
}
extern "C" SEXP rpst_raster_lifecycle() {
    SEXP out=PROTECT(Rf_allocVector(REALSXP,6));
    double v[]={comparisons_created,comparisons_freed,comparisons_created-comparisons_freed,
        polygons_created,polygons_freed,polygons_created-polygons_freed};
    for(int i=0;i<6;++i) REAL(out)[i]=v[i];
    UNPROTECT(1);return out;
}
