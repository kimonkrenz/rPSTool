// Internal interface of the rPSTool-owned ArrowArrayStream external pointer, shared by the
// GeoParquet decoder (pst-geoparquet.cpp) and the synthetic test producer
// (pst-arrow-test-stream.cpp). Not an installed or public header.
//
// Ownership: the external pointer owns one calloc'd ArrowArrayStream. Its finaliser calls
// the stream's release callback once if (and only if) the stream is still live, then frees
// the struct. The exact tag is centralised here so the two translation units cannot drift.
#ifndef RPST_ARROW_OWNER_H
#define RPST_ARROW_OWNER_H
#ifndef R_NO_REMAP
#error "Define R_NO_REMAP before including R headers in the translation unit."
#endif
#include <Rinternals.h>
#include "arrow-c-abi/arrow_c_abi.h"

namespace rpst {
// Exact tag of the stream external pointer.
SEXP arrow_stream_tag();

// Exact-tag validation: raises an R error for a wrong R type or tag. A correctly tagged
// but already freed pointer is an ordinary state and yields nullptr. May raise an R
// error, so call it before any C++ owner exists.
ArrowArrayStream* arrow_stream_lookup(SEXP pointer);

// Like arrow_stream_lookup() but additionally raises an R error for a freed pointer.
ArrowArrayStream* arrow_stream_require(SEXP pointer);

// Release the stream through its release callback exactly once (idempotent: a no-op
// when release is NULL).
void arrow_stream_release(ArrowArrayStream* stream);

// Largest byte index/offset the decoder treats as addressable. Defaults to PTRDIFF_MAX;
// a test hook may only lower it to simulate a smaller address space.
extern unsigned long long arrow_addressable_limit;
}  // namespace rpst
#endif
