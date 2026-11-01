// Private build probe: no graph or analysis API is introduced.
#define R_NO_REMAP
#include <Rinternals.h>
#include <pstalgo/test/CallbackTest.h>
#include <pstalgo/Limits.h>
#include <pstalgo/Raster.h>
#include <pstalgo/utils/SimpleAlignedAllocator.h>
#include <cstdint>
#include <stdexcept>

namespace {
struct CallbackState { int calls; bool cancel; };
int callback(const char*, float, void* user)
{
    auto* state = static_cast<CallbackState*>(user);
    ++state->calls;
    return state->cancel ? 1 : 0;
}
}

extern "C" SEXP rpst_native_smoke()
{
    CallbackState state{0, false};
    SCallbackTestDesc desc{};
    desc.m_Version = SCallbackTestDesc::VERSION;
    desc.m_ProgressCallback = callback;
    desc.m_ProgressCallbackUser = &state;
    desc.m_Progress = 0.5f;
    char status[] = "rPSTool build probe";
    desc.m_Status = status;
    desc.m_ReturnValue = 37;
    SEXP result = PROTECT(Rf_allocVector(INTSXP, 8));
    INTEGER(result)[0] = PSTACallbackTest(&desc);
    INTEGER(result)[1] = state.calls;
    state.cancel = true;
    INTEGER(result)[2] = PSTACallbackTest(&desc);
    desc.m_Version = 0;
    INTEGER(result)[3] = PSTACallbackTest(&desc);
    INTEGER(result)[4] = EPSTADistanceTypeFromDistanceType(_DIST_COUNT) ==
        EPSTADistanceType_Undefined;
    INTEGER(result)[5] = DistanceTypeFromEPSTADistanceType(
        EPSTADistanceType_Weights) == DIST_NONE;
    INTEGER(result)[6] = 0;
    try {
        psta::RasterFormatPixelSize(RasterFormat_Undefined);
    } catch (const std::runtime_error&) {
        INTEGER(result)[6] = 1;
    }
    // Exercise aligned allocation, block growth, writes, and destruction on
    // every platform, including the Rtools allocation/deallocation adapter.
    bool allocator_ok = true;
    for (int i = 0; i < 32; ++i) {
        CSimpleAlignedAllocator allocator(64, 4);
        void* first = allocator.Alloc(48);
        void* second = allocator.Alloc(32);
        if (!first || !second || first == second ||
            reinterpret_cast<std::uintptr_t>(first) % 16 != 0 ||
            reinterpret_cast<std::uintptr_t>(second) % 16 != 0) {
            allocator_ok = false;
            break;
        }
        std::memset(first, 0x5a, 48);
        std::memset(second, 0xa5, 32);
    }
    INTEGER(result)[7] = allocator_ok;
    UNPROTECT(1);
    return result;
}
