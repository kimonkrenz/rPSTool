// Rtools has _aligned_malloc/_aligned_free, but not posix_memalign. Adapt only
// this translation unit; never mix aligned Windows allocation with std::free.
#ifndef _WIN32
#error This build adapter is only for Windows
#endif

#include <cstdlib>
#include <cerrno>
#include <malloc.h>
#include <pstalgo/utils/SimpleAlignedAllocator.h>
#include <pstalgo/Debug.h>

namespace {
int rpst_windows_posix_memalign(void** result, size_t alignment, size_t size)
{
    if (alignment < sizeof(void*) || (alignment & (alignment - 1)) != 0)
        return EINVAL;
    const int saved_errno = errno;
    void* memory = _aligned_malloc(size, alignment);
    errno = saved_errno; // posix_memalign reports errors through its return value.
    if (!memory) return ENOMEM;
    *result = memory;
    return 0;
}
}

// All headers consumed by the pristine source have already been included.
// These substitutions apply only to its two allocation/deallocation calls.
#define posix_memalign rpst_windows_posix_memalign
#define free _aligned_free
#include "../vendor/pstalgo/src/utils/SimpleAlignedAllocator.cpp"
#undef free
#undef posix_memalign
