// GeoParquet path input: consume one Arrow C stream (ArrowArrayStream) exported by the optional
// R `arrow` package, decode exactly-two-vertex 2D WKB LineStrings straight into one transient
// contiguous std::vector<double2>, and hand it to the SAME shared segment-graph builder the
// matrix route uses (rpst::segment_graph_build). No libarrow is linked and no PST algorithm
// lives here.
//
// Trust boundary: the producer is trusted for the real allocation size of every buffer and for
// buffer lifetime while the Arrow object is live. The C Data Interface exposes no buffer byte
// lengths, so none are invented. Every structural and logical field that IS exposed is
// validated before use, with checked arithmetic.
//
// R/C++ safety: every R-facing check (pointer tags, argument types, the column name) happens
// before any C++ owner exists. Once Arrow objects or the coordinate vector are live, no R API
// is called and no R error is raised: failures are captured into a fixed char buffer, all
// owners unwind, and only then is Rf_error called.
#define R_NO_REMAP
#include <Rinternals.h>
#include <algorithm>
#include <cmath>
#include <cstdarg>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <limits>
#include <vector>
#include <sys/types.h>
#include <sys/stat.h>
#include "pst-arrow-owner.h"
#include "pst-segment-build.h"
#include "pst-axial-build.h"

namespace rpst {
unsigned long long arrow_addressable_limit =
    static_cast<unsigned long long>(std::numeric_limits<std::ptrdiff_t>::max());

SEXP arrow_stream_tag() { return Rf_install("rPST::ArrowArrayStream/v1"); }

ArrowArrayStream* arrow_stream_lookup(SEXP pointer)
{
    if (TYPEOF(pointer) != EXTPTRSXP || R_ExternalPtrTag(pointer) != arrow_stream_tag())
        Rf_error("Invalid rPSTool Arrow stream native pointer.");
    return static_cast<ArrowArrayStream*>(R_ExternalPtrAddr(pointer));
}

ArrowArrayStream* arrow_stream_require(SEXP pointer)
{
    auto* stream = arrow_stream_lookup(pointer);
    if (!stream) Rf_error("The rPSTool Arrow stream native pointer has already been freed.");
    return stream;
}

void arrow_stream_release(ArrowArrayStream* stream)
{
    if (!stream || !stream->release) return;
    stream->release(stream);
    // A conforming producer already set release to NULL; make a non-conforming one safe too.
    stream->release = nullptr;
}
}  // namespace rpst

namespace {
// Finaliser and deterministic free: clear the pointer, release the stream once if it is
// still live, free the struct. Repeated calls are no-ops.
void stream_finalizer(SEXP pointer)
{
    auto* stream = static_cast<ArrowArrayStream*>(R_ExternalPtrAddr(pointer));
    if (!stream) return;
    R_ClearExternalPtr(pointer);
    rpst::arrow_stream_release(stream);
    std::free(stream);
}
}  // namespace

// ---- rPSTool-owned ArrowArrayStream external pointer ------------------------------------------

// Strict local regular-file test (stat), so FIFOs, devices and directories are rejected
// before anything opens them. Argument validation precedes any native work.
extern "C" SEXP rpst_path_is_regular_file(SEXP path)
{
    if (TYPEOF(path) != STRSXP || XLENGTH(path) != 1 || STRING_ELT(path, 0) == NA_STRING)
        Rf_error("path must be one non-missing string.");
    struct stat info;
    const bool ok = stat(Rf_translateChar(STRING_ELT(path, 0)), &info) == 0 &&
                    (info.st_mode & S_IFMT) == S_IFREG;
    return Rf_ScalarLogical(ok ? 1 : 0);
}

extern "C" SEXP rpst_arrow_stream_new()
{
    // Tag, pointer and finaliser exist before the calloc, so an allocation failure cannot
    // leak a native stream owner.
    SEXP pointer = PROTECT(R_MakeExternalPtr(nullptr, rpst::arrow_stream_tag(), R_NilValue));
    R_RegisterCFinalizerEx(pointer, stream_finalizer, TRUE);
    auto* stream = static_cast<ArrowArrayStream*>(std::calloc(1, sizeof(ArrowArrayStream)));
    if (!stream) {
        UNPROTECT(1);
        Rf_error("Unable to allocate the Arrow stream struct.");
    }
    R_SetExternalPtrAddr(pointer, stream);
    UNPROTECT(1);
    return pointer;
}

extern "C" SEXP rpst_arrow_stream_is_live(SEXP pointer)
{
    const auto* stream = rpst::arrow_stream_lookup(pointer);
    return Rf_ScalarLogical(stream && stream->release ? 1 : 0);
}

// Idempotent: releases the live stream (if any) once; the struct stays allocated.
extern "C" SEXP rpst_arrow_stream_release(SEXP pointer)
{
    rpst::arrow_stream_release(rpst::arrow_stream_lookup(pointer));
    return R_NilValue;
}

// Idempotent deterministic cleanup: release if live, free the struct, clear the pointer.
extern "C" SEXP rpst_arrow_stream_free(SEXP pointer)
{
    rpst::arrow_stream_lookup(pointer);
    stream_finalizer(pointer);
    return R_NilValue;
}

// Test hook. Fail-closed: a finite, non-negative, whole number no larger than the real
// platform range; it can only lower the limit. NULL restores the platform limit.
extern "C" SEXP rpst_arrow_set_addressable_limit(SEXP limit)
{
    const auto platform = static_cast<unsigned long long>(std::numeric_limits<std::ptrdiff_t>::max());
    if (limit == R_NilValue) {
        rpst::arrow_addressable_limit = platform;
        return Rf_ScalarReal(static_cast<double>(platform));
    }
    if (TYPEOF(limit) != REALSXP || XLENGTH(limit) != 1)
        Rf_error("The address limit must be one double or NULL.");
    const double v = REAL(limit)[0];
    if (!std::isfinite(v) || v < 0 || std::floor(v) != v)
        Rf_error("The address limit must be finite, non-negative and whole.");
    if (v > static_cast<double>(platform))
        Rf_error("The address limit cannot exceed the platform's addressable range.");
    rpst::arrow_addressable_limit = v >= static_cast<double>(platform)
        ? platform : static_cast<unsigned long long>(v);
    return Rf_ScalarReal(static_cast<double>(rpst::arrow_addressable_limit));
}

// ---- decoder --------------------------------------------------------------------------------

namespace {
struct Ctx {
    char* error;
    std::size_t size;
};

bool fail(Ctx& ctx, const char* format, ...)
{
    va_list args;
    va_start(args, format);
    std::vsnprintf(ctx.error, ctx.size, format, args);
    va_end(args);
    return false;
}

bool host_little_endian()
{
    const std::uint16_t one = 1;
    unsigned char first;
    std::memcpy(&first, &one, 1);
    return first == 1;
}

std::uint64_t byte_swap64(std::uint64_t v)
{
    std::uint64_t r = 0;
    for (int i = 0; i < 8; ++i) { r = (r << 8) | (v & 0xff); v >>= 8; }
    return r;
}
std::uint32_t byte_swap32(std::uint32_t v)
{
    return ((v & 0xffu) << 24) | ((v & 0xff00u) << 8) | ((v >> 8) & 0xff00u) | (v >> 24);
}

// Standard WKB LineString validation. `data` may be null only when `length` is zero, and
// nothing is dereferenced before the length check that covers it. On success the two
// endpoints are written; otherwise `reason` describes the first failure.
bool decode_wkb_linestring(const unsigned char* data, std::uint64_t length, double2& a,
                           double2& b, char* reason, std::size_t reason_size)
{
    if (length < 5) {
        std::snprintf(reason, reason_size, "truncated WKB (%llu bytes) before the geometry type",
                      static_cast<unsigned long long>(length));
        return false;
    }
    const unsigned char order = data[0];
    if (order != 0 && order != 1) {
        std::snprintf(reason, reason_size, "invalid WKB byte-order marker %u (expected 0 or 1)", order);
        return false;
    }
    const bool swap = (order == 1) != host_little_endian();
    std::uint32_t type;
    std::memcpy(&type, data + 1, 4);
    if (swap) type = byte_swap32(type);
    if (type != 2) {
        if ((type & 0xE0000000u) != 0)
            std::snprintf(reason, reason_size, "EWKB geometry flags (Z/M/SRID bits, type code 0x%08x) are unsupported; expected a plain 2D LineString (type 2)", type);
        else if (type == 1002 || type == 2002 || type == 3002)
            std::snprintf(reason, reason_size, "%s LineString (ISO type %u) is unsupported; expected a 2D LineString",
                          type == 1002 ? "Z" : type == 2002 ? "M" : "ZM", type);
        else
            std::snprintf(reason, reason_size, "unsupported WKB geometry type %u; expected a 2D LineString (type 2)", type);
        return false;
    }
    if (length < 9) {
        std::snprintf(reason, reason_size, "truncated WKB (%llu bytes) before the point count",
                      static_cast<unsigned long long>(length));
        return false;
    }
    std::uint32_t points;
    std::memcpy(&points, data + 5, 4);
    if (swap) points = byte_swap32(points);
    if (points == 0) {
        std::snprintf(reason, reason_size, "empty LineString (zero points)");
        return false;
    }
    if (points != 2) {
        std::snprintf(reason, reason_size, "LineString has %u points; exactly two are required (polylines are never split)", points);
        return false;
    }
    if (length < 41) {
        std::snprintf(reason, reason_size, "truncated WKB (%llu bytes; a two-point 2D LineString has 41)",
                      static_cast<unsigned long long>(length));
        return false;
    }
    if (length > 41) {
        std::snprintf(reason, reason_size, "overlong WKB (%llu bytes; a two-point 2D LineString has 41)",
                      static_cast<unsigned long long>(length));
        return false;
    }
    double v[4];
    for (int i = 0; i < 4; ++i) {
        std::uint64_t bits;
        std::memcpy(&bits, data + 9 + 8 * i, 8);
        if (swap) bits = byte_swap64(bits);
        std::memcpy(&v[i], &bits, 8);
        if (!std::isfinite(v[i])) {
            std::snprintf(reason, reason_size, "non-finite coordinate");
            return false;
        }
    }
    a = double2(v[0], v[1]);
    b = double2(v[2], v[3]);
    return true;
}

struct StreamGuard {
    ArrowArrayStream* stream;
    explicit StreamGuard(ArrowArrayStream* s) : stream(s) {}
    ~StreamGuard() { release(); }
    void release() { rpst::arrow_stream_release(stream); }
    StreamGuard(const StreamGuard&) = delete;
    StreamGuard& operator=(const StreamGuard&) = delete;
};
struct SchemaGuard {
    ArrowSchema schema;
    SchemaGuard() { std::memset(&schema, 0, sizeof schema); }
    ~SchemaGuard()
    {
        if (!schema.release) return;
        schema.release(&schema);
        schema.release = nullptr;
    }
    SchemaGuard(const SchemaGuard&) = delete;
    SchemaGuard& operator=(const SchemaGuard&) = delete;
};
struct ArrayGuard {
    ArrowArray array;
    ArrayGuard() { std::memset(&array, 0, sizeof array); }
    ~ArrayGuard()
    {
        if (!array.release) return;
        array.release(&array);
        array.release = nullptr;
    }
    ArrayGuard(const ArrayGuard&) = delete;
    ArrayGuard& operator=(const ArrayGuard&) = delete;
};

// Copy the producer's diagnostic into rPSTool storage immediately.
bool stream_failure(ArrowArrayStream* s, Ctx& ctx, const char* what, int code)
{
    char diagnostic[256] = "no description available";
    const char* text = s->get_last_error(s);
    if (text) std::snprintf(diagnostic, sizeof diagnostic, "%s", text);
    return fail(ctx, "Arrow stream %s failed (code %d): %s", what, code, diagnostic);
}

bool equals(const char* a, const char* b) { return a && std::strcmp(a, b) == 0; }

bool validate_schema(const ArrowSchema& top, const char* column, bool& large, Ctx& ctx)
{
    if (!top.release) return fail(ctx, "Malformed Arrow stream: the returned schema is already released.");
    if (!equals(top.format, "+s"))
        return fail(ctx, "Unexpected Arrow schema: the stream must carry a struct (format \"+s\"), found \"%s\".",
                    top.format ? top.format : "(null)");
    if (top.dictionary) return fail(ctx, "Unexpected Arrow schema: a dictionary-encoded top-level schema is unsupported.");
    if (top.n_children != 1)
        return fail(ctx, "Unexpected Arrow schema: exactly one (geometry) column is required, found %lld.",
                    static_cast<long long>(top.n_children));
    if (!top.children || !top.children[0])
        return fail(ctx, "Malformed Arrow schema: the geometry child schema is missing.");
    const ArrowSchema& child = *top.children[0];
    if (!child.release) return fail(ctx, "Malformed Arrow schema: the geometry child schema is already released.");
    if (!equals(child.name, column))
        return fail(ctx, "Unexpected Arrow schema: the column is named \"%s\", expected the GeoParquet primary column \"%s\".",
                    child.name ? child.name : "(null)", column);
    if (equals(child.format, "z")) large = false;
    else if (equals(child.format, "Z")) large = true;
    else
        return fail(ctx, "Unsupported Arrow type for the geometry column: format \"%s\"; WKB must be BINARY (\"z\") or LARGE_BINARY (\"Z\").",
                    child.format ? child.format : "(null)");
    if (child.dictionary) return fail(ctx, "Unexpected Arrow schema: a dictionary-encoded geometry column is unsupported.");
    if (child.n_children != 0)
        return fail(ctx, "Unexpected Arrow schema: the geometry column must not have children.");
    return true;
}

bool bit_is_set(const unsigned char* bitmap, std::int64_t index, bool& set, Ctx& ctx, const char* what)
{
    const auto byte = static_cast<unsigned long long>(index) >> 3;
    if (byte >= rpst::arrow_addressable_limit)
        return fail(ctx, "Malformed Arrow array: %s validity bitmap index %lld is not addressable.", what,
                    static_cast<long long>(index));
    set = ((bitmap[byte] >> (index & 7)) & 1) != 0;
    return true;
}

// Arrow's declared null_count against the declared length, and bitmap presence.
bool check_null_count(const ArrowArray& a, const char* what, Ctx& ctx)
{
    if (a.null_count < -1 || a.null_count > a.length)
        return fail(ctx, "Malformed Arrow %s array: null_count %lld is invalid for length %lld.", what,
                    static_cast<long long>(a.null_count), static_cast<long long>(a.length));
    if (a.length > 0 && !a.buffers[0] && a.null_count != 0)
        return fail(ctx, "Malformed Arrow %s array: null_count %lld requires a validity bitmap but none is present.",
                    what, static_cast<long long>(a.null_count));
    return true;
}

// Count bitmap nulls over [first, first + count) (all in the array's physical bit space).
bool count_nulls(const unsigned char* bitmap, std::int64_t first, std::int64_t count,
                 std::int64_t& nulls, Ctx& ctx, const char* what)
{
    nulls = 0;
    if (!bitmap) return true;
    for (std::int64_t i = 0; i < count; ++i) {
        bool set;
        if (!bit_is_set(bitmap, first + i, set, ctx, what)) return false;
        if (!set) ++nulls;
    }
    return true;
}

struct Decoder {
    Ctx& ctx;
    std::vector<double2>& out;
    unsigned long long expected;
    unsigned long long rows = 0;
    bool large = false;
    bool have_schema = false;

    bool batch(const ArrowArray& parent)
    {
        if (parent.length < 0 || parent.offset < 0)
            return fail(ctx, "Malformed Arrow batch: negative length or offset.");
        if (parent.n_buffers != 1)
            return fail(ctx, "Malformed Arrow batch: a struct array must have exactly one (validity) buffer, found %lld.",
                        static_cast<long long>(parent.n_buffers));
        if (!parent.buffers) return fail(ctx, "Malformed Arrow batch: the buffer array is missing.");
        if (parent.dictionary) return fail(ctx, "Malformed Arrow batch: dictionary arrays are unsupported.");
        if (parent.n_children != 1)
            return fail(ctx, "Malformed Arrow batch: exactly one geometry child array is required, found %lld.",
                        static_cast<long long>(parent.n_children));
        if (!parent.children || !parent.children[0])
            return fail(ctx, "Malformed Arrow batch: the geometry child array is missing.");
        const ArrowArray& child = *parent.children[0];
        if (!child.release) return fail(ctx, "Malformed Arrow batch: the geometry child array is already released.");
        if (child.length < 0 || child.offset < 0)
            return fail(ctx, "Malformed Arrow geometry array: negative length or offset.");
        if (child.n_children != 0) return fail(ctx, "Malformed Arrow geometry array: it must not have children.");
        if (child.dictionary) return fail(ctx, "Malformed Arrow geometry array: dictionary arrays are unsupported.");
        if (child.n_buffers != 3)
            return fail(ctx, "Malformed Arrow geometry array: binary arrays have exactly three buffers, found %lld.",
                        static_cast<long long>(child.n_buffers));
        if (!child.buffers) return fail(ctx, "Malformed Arrow geometry array: the buffer array is missing.");
        if (!check_null_count(parent, "batch", ctx) || !check_null_count(child, "geometry", ctx)) return false;

        // Composition of offsets (Arrow slicing): the child's logical index for parent row i
        // is parent.offset + i, and its physical index is child.offset + parent.offset + i.
        const std::int64_t max = std::numeric_limits<std::int64_t>::max();
        if (parent.offset > max - parent.length)
            return fail(ctx, "Malformed Arrow batch: offset + length overflows.");
        const std::int64_t parent_end = parent.offset + parent.length;
        if (child.length < parent_end)
            return fail(ctx, "Malformed Arrow batch: the geometry child (length %lld) does not cover the parent's logical range (offset %lld + length %lld).",
                        static_cast<long long>(child.length), static_cast<long long>(parent.offset),
                        static_cast<long long>(parent.length));
        if (child.offset > max - parent_end)
            return fail(ctx, "Malformed Arrow batch: the combined parent and child offset overflows.");
        const std::int64_t physical_begin = child.offset + parent.offset;
        const std::int64_t physical_end = child.offset + parent_end;

        if (static_cast<unsigned long long>(parent.length) > expected - rows)
            return fail(ctx, "The stream produced more rows than the file reports (%llu).", expected);
        if (parent.length == 0) return true;

        const auto* parent_bitmap = static_cast<const unsigned char*>(parent.buffers[0]);
        const auto* child_bitmap = static_cast<const unsigned char*>(child.buffers[0]);
        const void* offsets = child.buffers[1];
        const auto* data = static_cast<const unsigned char*>(child.buffers[2]);
        if (!offsets) return fail(ctx, "Malformed Arrow geometry array: the offsets buffer is missing.");

        // Declared null counts against the observed bitmaps.
        std::int64_t observed;
        if (!count_nulls(parent_bitmap, parent.offset, parent.length, observed, ctx, "batch")) return false;
        if (parent.null_count >= 0 && observed != parent.null_count)
            return fail(ctx, "Malformed Arrow batch: null_count %lld contradicts the validity bitmap (%lld nulls).",
                        static_cast<long long>(parent.null_count), static_cast<long long>(observed));
        if (!count_nulls(child_bitmap, physical_begin, parent.length, observed, ctx, "geometry")) return false;
        if (child.null_count >= 0) {
            const bool whole = parent.offset == 0 && parent.length == child.length;
            if ((whole && observed != child.null_count) || (!whole && observed > child.null_count))
                return fail(ctx, "Malformed Arrow geometry array: null_count %lld contradicts the validity bitmap (%lld nulls in the inspected range).",
                            static_cast<long long>(child.null_count), static_cast<long long>(observed));
        }

        // Every offset index k and k + 1 (the largest is physical_end) must be addressable as a
        // whole element: its last byte, (physical_end + 1) * width - 1, must lie within the limit.
        const unsigned long long width = large ? 8 : 4;
        if (static_cast<unsigned long long>(physical_end) + 1 > rpst::arrow_addressable_limit / width)
            return fail(ctx, "Malformed Arrow geometry array: the offsets buffer index %lld is not addressable.",
                        static_cast<long long>(physical_end));
        const auto* offset_bytes = static_cast<const unsigned char*>(offsets);

        for (std::int64_t i = 0; i < parent.length; ++i) {
            const unsigned long long row = rows + static_cast<unsigned long long>(i) + 1;  // one-based
            bool valid;
            if (parent_bitmap) {
                if (!bit_is_set(parent_bitmap, parent.offset + i, valid, ctx, "batch")) return false;
                if (!valid) return fail(ctx, "Row %llu: null feature record.", row);
            }
            const std::int64_t k = physical_begin + i;
            if (child_bitmap) {
                if (!bit_is_set(child_bitmap, k, valid, ctx, "geometry")) return false;
                if (!valid) return fail(ctx, "Row %llu: null geometry.", row);
            }
            std::int64_t start, end;
            if (large) {
                std::memcpy(&start, offset_bytes + static_cast<std::size_t>(k) * 8, 8);
                std::memcpy(&end, offset_bytes + static_cast<std::size_t>(k + 1) * 8, 8);
            } else {
                std::int32_t s32, e32;
                std::memcpy(&s32, offset_bytes + static_cast<std::size_t>(k) * 4, 4);
                std::memcpy(&e32, offset_bytes + static_cast<std::size_t>(k + 1) * 4, 4);
                start = s32;
                end = e32;
            }
            if (start < 0 || end < start)
                return fail(ctx, "Row %llu: malformed Arrow offsets (start %lld, end %lld).", row,
                            static_cast<long long>(start), static_cast<long long>(end));
            if (static_cast<unsigned long long>(end) > rpst::arrow_addressable_limit)
                return fail(ctx, "Row %llu: the WKB value end offset %lld is not addressable.", row,
                            static_cast<long long>(end));
            const auto length = static_cast<std::uint64_t>(end - start);
            if (length > 0 && !data)
                return fail(ctx, "Row %llu: malformed Arrow geometry array: a %llu-byte value but a NULL data buffer.",
                            row, static_cast<unsigned long long>(length));
            char reason[256];
            double2 a, b;
            if (!decode_wkb_linestring(length ? data + static_cast<std::size_t>(start) : nullptr, length,
                                       a, b, reason, sizeof reason))
                return fail(ctx, "Row %llu: %s.", row, reason);
            out.push_back(a);
            out.push_back(b);
        }
        rows += static_cast<unsigned long long>(parent.length);
        return true;
    }
};

// Decode the whole stream into `out` (two endpoints per row) and release the stream before
// returning. Never throws and never calls the R API; failures are reported in `error`.
bool decode_stream(ArrowArrayStream* stream, const char* column, unsigned long long expected,
                   std::vector<double2>& out, char* error, std::size_t error_size, bool axial = false)
{
    Ctx ctx{error, error_size};
    error[0] = '\0';
    try {
        StreamGuard guard(stream);
        if (!stream->release) return fail(ctx, "The Arrow stream has not been exported or is already released.");
        if (!stream->get_schema || !stream->get_next || !stream->get_last_error)
            return fail(ctx, "Malformed Arrow stream: a required callback (get_schema, get_next or get_last_error) is missing.");
        if (expected > std::numeric_limits<unsigned int>::max() / 2)
            return fail(ctx, axial ? "Too many lines for the PST graph descriptor." : "Too many segments for the PST graph descriptor.");
        out.reserve(static_cast<std::size_t>(expected) * 2);

        Decoder decoder{ctx, out, expected};
        {
            SchemaGuard schema;
            const int code = stream->get_schema(stream, &schema.schema);
            if (code != 0) return stream_failure(stream, ctx, "get_schema", code);
            if (!validate_schema(schema.schema, column, decoder.large, ctx)) return false;
        }
        for (;;) {
            ArrayGuard batch;
            const int code = stream->get_next(stream, &batch.array);
            if (code != 0) return stream_failure(stream, ctx, "get_next", code);
            if (!batch.array.release) break;  // end of stream
            if (!decoder.batch(batch.array)) return false;
        }
        guard.release();
        if (decoder.rows != expected)
            return fail(ctx, "The stream produced %llu rows but the file reports %llu.", decoder.rows, expected);
        return true;
    } catch (const std::exception& e) {
        fail(ctx, "GeoParquet decoding failed: %s", e.what());
    } catch (...) {
        fail(ctx, "GeoParquet decoding failed with an unknown native exception.");
    }
    return false;
}

// R-facing argument checks; these may raise R errors and so must run before any C++ owner.
struct Request {
    ArrowArrayStream* stream;
    char column[1024];
    unsigned long long rows;
};

void read_request(Request& request, SEXP stream, SEXP column, SEXP rows, bool allow_zero)
{
    request.stream = rpst::arrow_stream_require(stream);
    if (TYPEOF(column) != STRSXP || XLENGTH(column) != 1 || STRING_ELT(column, 0) == NA_STRING)
        Rf_error("The geometry column name must be one non-missing string.");
    const char* name = Rf_translateCharUTF8(STRING_ELT(column, 0));
    if (!name[0] || std::strlen(name) >= sizeof request.column)
        Rf_error("The geometry column name must be non-empty and shorter than %d bytes.",
                 static_cast<int>(sizeof request.column));
    std::memcpy(request.column, name, std::strlen(name) + 1);
    if (TYPEOF(rows) != REALSXP || XLENGTH(rows) != 1)
        Rf_error("The expected row count must be one double.");
    const double n = REAL(rows)[0];
    if (!std::isfinite(n) || n < (allow_zero ? 0 : 1) || std::floor(n) != n || n > 9007199254740992.0)
        Rf_error("The expected row count must be a whole number of at least %d.", allow_zero ? 0 : 1);
    request.rows = static_cast<unsigned long long>(n);
}
}  // namespace

// Decode a stream and build the segment graph into the pre-allocated empty graph pointer.
// The Arrow stream is released by the decoder BEFORE the PST graph is constructed. Any
// failure leaves the graph pointer empty (decode) or not live (build): nothing is published.
namespace {
// Shared body of the segment and axial entry points (`aux` non-null selects the axial builder). The caller has
// validated the graph pointer and staged `aux` before any C++ owner exists.
SEXP decode_and_build(SEXP graph, SEXP stream, SEXP column, SEXP rows, const rpst::AxialAuxiliary* aux)
{
    const bool axial = aux != nullptr;
    Request request;
    read_request(request, stream, column, rows, false);
    if (request.rows > std::numeric_limits<unsigned int>::max() / 2)
        Rf_error(axial ? "Too many lines for the PST graph descriptor." : "Too many segments for the PST graph descriptor.");
    char error[512] = "";
    {
        std::vector<double2> coords;
        if (decode_stream(request.stream, request.column, request.rows, coords, error, sizeof error, axial)) {
            if (axial) rpst::axial_graph_build(graph, coords, *aux, error, sizeof error);
            else rpst::segment_graph_build(graph, coords, error, sizeof error);
        }
    }
    // All C++ owners have unwound before R's non-local error jump.
    if (error[0]) Rf_error("%s", error);
    return graph;
}
}  // namespace

extern "C" SEXP rpst_geoparquet_segment_graph(SEXP graph, SEXP stream, SEXP column, SEXP rows)
{
    rpst::segment_graph_require_empty(graph);
    return decode_and_build(graph, stream, column, rows, nullptr);
}

extern "C" SEXP rpst_geoparquet_axial_graph(SEXP graph, SEXP stream, SEXP column, SEXP rows, SEXP unlinks,
                                            SEXP points, SEXP polygon_sizes, SEXP interval)
{
    rpst::axial_graph_require_empty(graph);
    rpst::AxialAuxiliary aux;
    rpst::stage_axial_auxiliary(unlinks, points, polygon_sizes, interval, aux);
    return decode_and_build(graph, stream, column, rows, &aux);
}

// Test/diagnostic entry: decode a stream to an n x 4 numeric matrix (x1, y1, x2, y2) with no
// graph. The result is allocated before native work; it is filled only on success.
extern "C" SEXP rpst_arrow_decode_matrix(SEXP stream, SEXP column, SEXP rows)
{
    Request request;
    read_request(request, stream, column, rows, true);
    if (request.rows > static_cast<unsigned long long>(std::numeric_limits<int>::max()))
        Rf_error("Too many rows for a matrix.");
    const auto n = static_cast<R_xlen_t>(request.rows);
    SEXP result = PROTECT(Rf_allocMatrix(REALSXP, static_cast<int>(n), 4));
    double* data = REAL(result);
    char error[512] = "";
    {
        std::vector<double2> coords;
        if (decode_stream(request.stream, request.column, request.rows, coords, error, sizeof error)) {
            for (R_xlen_t i = 0; i < n; ++i) {
                data[i] = coords[static_cast<std::size_t>(i) * 2].x;
                data[i + n] = coords[static_cast<std::size_t>(i) * 2].y;
                data[i + 2 * n] = coords[static_cast<std::size_t>(i) * 2 + 1].x;
                data[i + 3 * n] = coords[static_cast<std::size_t>(i) * 2 + 1].y;
            }
        }
    }
    if (error[0]) Rf_error("%s", error);
    UNPROTECT(1);
    return result;
}
