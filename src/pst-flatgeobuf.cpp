// FlatGeobuf path input: read one local FlatGeobuf file (major version 3) and turn its
// exactly-two-vertex 2D LineString features into ONE transient contiguous std::vector<double2>
// (two endpoints per feature, in physical file order), then hand it to the SAME shared builder
// as the matrix, sf and GeoParquet routes (rpst::segment_graph_build). No PST algorithm lives here.
//
// Binary-format safety (docs/spatial-io/flatgeobuf-input.md §3): the file is untrusted. The
// header and every feature record are FlatBuffers; each is read into its own buffer (bounded as below) and
// passed through the pinned FlatBuffers `Verifier` BEFORE any generated accessor touches it. Verification is
// structural; the per-feature semantic checks (type, dimensions, vertex count, finiteness) follow it.
//
// Resource bounds (S2-B): header <= 64 MiB, one feature record <= 64 MiB, every size prefix <= the bytes
// remaining in the file, a non-zero declared feature count is bounded by the file size BEFORE any index-size
// arithmetic or reserve(), and all count/offset arithmetic is checked 64-bit.
//
// R/C++ safety: every R-facing check and every R allocation happens before a C++ owner (FILE*, buffers, the
// coordinate vector) exists, or after all of them have unwound; inside the owner scope there is no R API call and
// no Rf_error: failures are captured in a fixed char buffer and raised after unwinding. No C++ exception leaves
// .Call. The file is opened by path twice (inspect, then decode); nothing persists between the calls, and the
// decode call requires the re-read header bytes to equal the inspected ones byte for byte.
#define _FILE_OFFSET_BITS 64
#define R_NO_REMAP
#include <Rinternals.h>
#include <cctype>
#include <cmath>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <limits>
#include <string>
#include <vector>
#include <memory>
#include <sys/stat.h>
#include <sys/types.h>
#ifndef _WIN32
#include <fcntl.h>
#include <unistd.h>
#endif
#include "flatbuffers/flatbuffers.h"
#include "header_generated.h"
#include "feature_generated.h"
#include "pst-segment-build.h"
#include "pst-axial-build.h"
#include "pst-arrow-owner.h"

#ifdef _WIN32
// Defined in pst-output-file.cpp (which includes <windows.h>; kept out of this translation unit on purpose).
namespace rpst { namespace fs { std::FILE* open_temp_for_write(const char* utf8_path, std::string& error); } }
#endif

namespace {
using FlatGeobuf::GeometryType;

constexpr std::uint64_t kMaxHeaderBytes = 64ull << 20;   // 64 MiB (decision S2-B)
constexpr std::uint64_t kMaxRecordBytes = 64ull << 20;   // 64 MiB (decision S2-B)
constexpr std::uint64_t kMagicBytes = 8;
constexpr std::uint64_t kNodeBytes = 40;                 // PackedRTree node: four doubles + uint64 offset
// Smallest size-prefixed record rPSTool can ACCEPT: 4-byte prefix + the xy vector (4-byte length + four doubles).
constexpr std::uint64_t kMinAcceptedRecordBytes = 4 + 4 + 4 * 8;

bool host_is_little_endian()
{
    const std::uint16_t one = 1;
    unsigned char first;
    std::memcpy(&first, &one, 1);
    return first == 1;
}

bool fail(char* error, std::size_t size, const char* format, ...)
{
    va_list args;
    va_start(args, format);
    std::vsnprintf(error, size, format, args);
    va_end(args);
    return false;
}

// ---- 64-bit file access ----------------------------------------------------------------------------------
#ifdef _WIN32
bool utf8_to_wide(const char* s, std::wstring& out)
{
    out.clear();
    const auto* p = reinterpret_cast<const unsigned char*>(s);
    while (*p) {
        std::uint32_t cp;
        int extra;
        if (*p < 0x80) { cp = *p; extra = 0; }
        else if ((*p & 0xE0) == 0xC0) { cp = *p & 0x1F; extra = 1; }
        else if ((*p & 0xF0) == 0xE0) { cp = *p & 0x0F; extra = 2; }
        else if ((*p & 0xF8) == 0xF0) { cp = *p & 0x07; extra = 3; }
        else return false;
        ++p;
        for (int i = 0; i < extra; ++i, ++p) {
            if ((*p & 0xC0) != 0x80) return false;
            cp = (cp << 6) | (*p & 0x3F);
        }
        if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) return false;
        if (cp >= 0x10000) {
            cp -= 0x10000;
            out.push_back(static_cast<wchar_t>(0xD800 + (cp >> 10)));
            out.push_back(static_cast<wchar_t>(0xDC00 + (cp & 0x3FF)));
        } else {
            out.push_back(static_cast<wchar_t>(cp));
        }
    }
    return true;
}
#endif

struct File {
    std::FILE* f = nullptr;
    std::uint64_t size = 0;
    File() = default;
    File(const File&) = delete;
    File& operator=(const File&) = delete;
    ~File() { if (f) std::fclose(f); }

    // `path` is UTF-8 on Windows and in the native encoding elsewhere (chosen by the caller).
    bool open(const char* path, char* error, std::size_t error_size)
    {
#ifdef _WIN32
        std::wstring wide;
        if (!utf8_to_wide(path, wide)) return fail(error, error_size, "The path is not valid UTF-8.");
        f = _wfopen(wide.c_str(), L"rb");
#else
        f = std::fopen(path, "rb");
#endif
        if (!f) return fail(error, error_size, "Cannot open the FlatGeobuf file for reading.");
        // Regular-file test and size taken from the open descriptor (no path race).
#ifdef _WIN32
        struct __stat64 st;
        if (_fstat64(_fileno(f), &st) != 0) return fail(error, error_size, "Cannot stat the FlatGeobuf file.");
#else
        struct stat st;
        if (fstat(fileno(f), &st) != 0) return fail(error, error_size, "Cannot stat the FlatGeobuf file.");
#endif
        if ((st.st_mode & S_IFMT) != S_IFREG) return fail(error, error_size, "The path is not a regular file.");
        if (st.st_size < 0) return fail(error, error_size, "Invalid FlatGeobuf file size.");
        size = static_cast<std::uint64_t>(st.st_size);
        return true;
    }
    bool seek(std::uint64_t offset) const
    {
        if (offset > static_cast<std::uint64_t>(std::numeric_limits<std::int64_t>::max())) return false;
#ifdef _WIN32
        return _fseeki64(f, static_cast<__int64>(offset), SEEK_SET) == 0;
#else
        return fseeko(f, static_cast<off_t>(offset), SEEK_SET) == 0;
#endif
    }
    bool read(void* buffer, std::uint64_t n) const
    {
        return n == 0 || std::fread(buffer, 1, static_cast<std::size_t>(n), f) == static_cast<std::size_t>(n);
    }
};

std::uint32_t load_u32(const unsigned char* p)
{
    std::uint32_t v;
    std::memcpy(&v, p, 4);  // little-endian host asserted by the callers
    return v;
}

// Plain facts about a verified header (no owners).
struct HeaderFacts {
    std::uint64_t header_total = 0;  // 4 + size prefix value: bytes of the header buffer as read
    std::uint64_t data_start = 0;    // absolute offset of the first feature record
    std::uint64_t features = 0;      // declared count; 0 = unknown
    std::uint16_t index_node_size = 0;
    int geometry_type = 0;
    bool has_crs = false;
    // CRS strings as (offset, length) into the header buffer; present flags
    bool org_present = false, name_present = false, description_present = false, wkt_present = false,
         code_string_present = false;
    std::uint64_t org_off = 0, org_len = 0, name_off = 0, name_len = 0, description_off = 0, description_len = 0,
                  wkt_off = 0, wkt_len = 0, code_string_off = 0, code_string_len = 0;
    std::int32_t crs_code = 0;
};

// Read just the 8 magic bytes and the header size prefix and apply the size bounds.
bool read_header_size(const File& file, std::uint64_t& header_total, char* error, std::size_t error_size)
{
    if (file.size < kMagicBytes + 4) return fail(error, error_size, "The file is too small to be a FlatGeobuf file.");
    unsigned char head[12];
    if (!file.seek(0) || !file.read(head, sizeof head)) return fail(error, error_size, "Cannot read the FlatGeobuf signature.");
    static const unsigned char signature[7] = {0x66, 0x67, 0x62, 0x03, 0x66, 0x67, 0x62};  // "fgb\3fgb"; byte 8 = patch level
    if (std::memcmp(head, signature, 7) != 0)
        return fail(error, error_size, "The file does not carry the FlatGeobuf major-version-3 signature.");
    const std::uint64_t size = load_u32(head + 8);
    const std::uint64_t remaining = file.size - 12;
    if (size < 8) return fail(error, error_size, "The FlatGeobuf header size prefix is too small.");
    if (size > kMaxHeaderBytes)
        return fail(error, error_size, "The FlatGeobuf header size prefix (%llu bytes) exceeds the 64 MiB limit.",
                    static_cast<unsigned long long>(size));
    if (size > remaining)
        return fail(error, error_size, "The FlatGeobuf header size prefix exceeds the bytes remaining in the file.");
    header_total = 4 + size;
    return true;
}

// Checked size of the packed Hilbert R-tree index (PackedRTree::size): sum of the per-level node counts x 40.
bool index_bytes(std::uint64_t items, std::uint16_t node_size, std::uint64_t& bytes)
{
    if (node_size < 2 || items == 0) return false;
    const std::uint64_t max = std::numeric_limits<std::uint64_t>::max();
    std::uint64_t n = items, nodes = items;
    do {
        if (n > max - (node_size - 1u)) return false;
        n = (n + node_size - 1u) / node_size;
        if (nodes > max - n) return false;
        nodes += n;
    } while (n != 1);
    if (nodes > max / kNodeBytes) return false;
    bytes = nodes * kNodeBytes;
    return true;
}

// Read, verify and interpret the header. `buffer` receives the size-prefixed header bytes.
bool parse_header(const File& file, unsigned char* buffer, std::uint64_t header_total, HeaderFacts& facts,
                  char* error, std::size_t error_size)
{
    // The size prefix (offset 8) is part of the buffer the Verifier checks, which also requires it to equal the rest.
    if (!file.seek(kMagicBytes) || !file.read(buffer, header_total)) return fail(error, error_size, "Truncated FlatGeobuf header.");
    flatbuffers::Verifier verifier(buffer, static_cast<std::size_t>(header_total));
    if (!FlatGeobuf::VerifySizePrefixedHeaderBuffer(verifier))
        return fail(error, error_size, "The FlatGeobuf header failed FlatBuffers verification.");
    const FlatGeobuf::Header* h = FlatGeobuf::GetSizePrefixedHeader(buffer);

    const GeometryType type = h->geometry_type();
    if (type != GeometryType::Unknown && type != GeometryType::LineString)
        return fail(error, error_size, "The FlatGeobuf header declares geometry type %d; only LineString (2) or per-feature types (0) are supported.",
                    static_cast<int>(type));
    if (h->has_z() || h->has_m() || h->has_t() || h->has_tm())
        return fail(error, error_size, "The FlatGeobuf header declares Z, M or T dimensions; only XY geometry is supported.");
    facts.geometry_type = static_cast<int>(type);
    facts.features = h->features_count();
    facts.index_node_size = h->index_node_size();

    // Sizes: count bound against the file BEFORE any index arithmetic or reserve.
    const std::uint64_t after_header = 12 + (header_total - 4);
    const std::uint64_t room = file.size - after_header;
    if (facts.features > room / kMinAcceptedRecordBytes)
        return fail(error, error_size, "The FlatGeobuf header declares %llu features, more than the file can hold.",
                    static_cast<unsigned long long>(facts.features));
    std::uint64_t index = 0;
    if (facts.index_node_size > 0) {
        if (facts.index_node_size < 2) return fail(error, error_size, "The FlatGeobuf index node size %u is invalid.", static_cast<unsigned>(facts.index_node_size));
        if (facts.features == 0)
            return fail(error, error_size, "The FlatGeobuf header requests a spatial index but gives no feature count, so the index size is unknown.");
        if (!index_bytes(facts.features, facts.index_node_size, index))
            return fail(error, error_size, "The FlatGeobuf spatial index size overflows.");
    }
    if (index > room) return fail(error, error_size, "The FlatGeobuf spatial index extends beyond the end of the file.");
    facts.data_start = after_header + index;
    if (facts.features > (file.size - facts.data_start) / kMinAcceptedRecordBytes)
        return fail(error, error_size, "The FlatGeobuf header declares %llu features, more than the file can hold after its index.",
                    static_cast<unsigned long long>(facts.features));
    facts.header_total = header_total;

    if (const FlatGeobuf::Crs* crs = h->crs()) {
        facts.has_crs = true;
        facts.crs_code = crs->code();
        const unsigned char* base = buffer;
        auto locate = [&](const flatbuffers::String* s, bool& present, std::uint64_t& off, std::uint64_t& len) {
            present = s != nullptr;
            if (s) {
                off = static_cast<std::uint64_t>(reinterpret_cast<const unsigned char*>(s->data()) - base);
                len = s->size();
            }
        };
        locate(crs->org(), facts.org_present, facts.org_off, facts.org_len);
        locate(crs->name(), facts.name_present, facts.name_off, facts.name_len);
        locate(crs->description(), facts.description_present, facts.description_off, facts.description_len);
        locate(crs->wkt(), facts.wkt_present, facts.wkt_off, facts.wkt_len);
        locate(crs->code_string(), facts.code_string_present, facts.code_string_off, facts.code_string_len);
    }
    return true;
}

// Per-feature semantic checks on a VERIFIED record. Writes the four coordinates.
bool decode_feature(const unsigned char* record, int header_geometry_type, double out[4], char* reason, std::size_t reason_size)
{
    const FlatGeobuf::Feature* ft = FlatGeobuf::GetSizePrefixedFeature(record);
    const FlatGeobuf::Geometry* g = ft->geometry();
    if (!g) return fail(reason, reason_size, "null or empty geometry");
    if (g->parts() && g->parts()->size()) return fail(reason, reason_size, "multipart or collection geometry");
    const GeometryType t = g->type();
    if (header_geometry_type == 0) {
        if (t != GeometryType::LineString)
            return fail(reason, reason_size, "geometry type %d is not LineString", static_cast<int>(t));
    } else if (t != GeometryType::Unknown && t != GeometryType::LineString) {
        return fail(reason, reason_size, "geometry type %d contradicts the header", static_cast<int>(t));
    }
    if ((g->z() && g->z()->size()) || (g->m() && g->m()->size()) || (g->t() && g->t()->size()) || (g->tm() && g->tm()->size()))
        return fail(reason, reason_size, "Z, M or T values are present; only XY geometry is supported");
    if (g->ends() && g->ends()->size() > 1) return fail(reason, reason_size, "the geometry has more than one part");
    const auto* xy = g->xy();
    if (!xy || xy->size() == 0) return fail(reason, reason_size, "null or empty geometry");
    if (xy->size() != 4)
        return fail(reason, reason_size, "the LineString has %u vertices; exactly two are required (polylines are never split)", xy->size() / 2);
    for (int i = 0; i < 4; ++i) {
        out[i] = xy->Get(static_cast<flatbuffers::uoffset_t>(i));
        if (!std::isfinite(out[i])) return fail(reason, reason_size, "non-finite coordinate");
    }
    return true;
}

// Stream the feature records into `coords` (two endpoints each). Never throws.
bool decode_records(const File& file, const HeaderFacts& facts, std::vector<double2>& coords, bool axial, char* error, std::size_t error_size)
{
    try {
        const std::uint64_t room = file.size - facts.data_start;
        if (facts.features) coords.reserve(static_cast<std::size_t>(2 * facts.features));  // bounded by the file size above
        if (!file.seek(facts.data_start)) return fail(error, error_size, "Cannot seek to the FlatGeobuf features.");
        std::vector<unsigned char> record;
        std::uint64_t pos = 0, parsed = 0;
        while (pos < room) {
            if (facts.features && parsed == facts.features)
                return fail(error, error_size, "The file has bytes after the %llu declared features.", static_cast<unsigned long long>(facts.features));
            if (room - pos < 4) return fail(error, error_size, "Feature %llu: truncated size prefix.", static_cast<unsigned long long>(parsed + 1));
            unsigned char prefix[4];
            if (!file.read(prefix, 4)) return fail(error, error_size, "Feature %llu: cannot read the size prefix.", static_cast<unsigned long long>(parsed + 1));
            const std::uint64_t size = load_u32(prefix);
            if (size > kMaxRecordBytes)
                return fail(error, error_size, "Feature %llu: the size prefix (%llu bytes) exceeds the 64 MiB limit.",
                            static_cast<unsigned long long>(parsed + 1), static_cast<unsigned long long>(size));
            if (size > room - pos - 4)
                return fail(error, error_size, "Feature %llu: the size prefix exceeds the bytes remaining in the file.", static_cast<unsigned long long>(parsed + 1));
            record.resize(static_cast<std::size_t>(4 + size));
            std::memcpy(record.data(), prefix, 4);
            if (!file.read(record.data() + 4, size)) return fail(error, error_size, "Feature %llu: truncated record.", static_cast<unsigned long long>(parsed + 1));
            pos += 4 + size;
            flatbuffers::Verifier verifier(record.data(), record.size());
            if (!FlatGeobuf::VerifySizePrefixedFeatureBuffer(verifier))
                return fail(error, error_size, "Feature %llu: the record failed FlatBuffers verification.", static_cast<unsigned long long>(parsed + 1));
            double xy[4];
            char reason[200];
            if (!decode_feature(record.data(), facts.geometry_type, xy, reason, sizeof reason))
                return fail(error, error_size, "Feature %llu: %s.", static_cast<unsigned long long>(parsed + 1), reason);
            coords.push_back(double2(xy[0], xy[1]));
            coords.push_back(double2(xy[2], xy[3]));
            ++parsed;
        }
        if (facts.features && parsed != facts.features)
            return fail(error, error_size, "The file holds %llu features but declares %llu.", static_cast<unsigned long long>(parsed),
                        static_cast<unsigned long long>(facts.features));
        if (parsed == 0)
            return fail(error, error_size, axial ? "The FlatGeobuf file has no features; an axial graph needs at least one line."
                                                 : "The FlatGeobuf file has no features; a segment graph needs at least one segment.");
        return true;
    } catch (const std::exception& e) {
        return fail(error, error_size, "FlatGeobuf decoding failed: %s", e.what());
    } catch (...) {
        return fail(error, error_size, "FlatGeobuf decoding failed with an unknown native exception.");
    }
}

// R-facing argument staging (may raise R errors; call before any owner exists).
const char* path_argument(SEXP path)
{
    if (TYPEOF(path) != STRSXP || XLENGTH(path) != 1 || STRING_ELT(path, 0) == NA_STRING)
        Rf_error("path must be one non-missing string.");
#ifdef _WIN32
    const char* p = Rf_translateCharUTF8(STRING_ELT(path, 0));
#else
    const char* p = Rf_translateChar(STRING_ELT(path, 0));
#endif
    if (!p[0]) Rf_error("path must not be empty.");
    return p;
}

SEXP string_or_null(const unsigned char* base, bool present, std::uint64_t off, std::uint64_t len)
{
    if (!present) return R_NilValue;
    if (len > static_cast<std::uint64_t>(std::numeric_limits<int>::max())) Rf_error("A FlatGeobuf CRS string is too long.");
    return Rf_ScalarString(Rf_mkCharLenCE(reinterpret_cast<const char*>(base + off), static_cast<int>(len), CE_UTF8));
}

// ===================================================================================================================
// Spatial output: write a NEW FlatGeobuf holding the ORIGINAL source geometry and attributes plus the PST result
// columns (docs/spatial-io/spatial-output.md). One sequential pass over the source records; one reusable record buffer; one reusable
// FlatBufferBuilder; nothing is held per feature or per file. The result arrives as the rPSTool-owned Arrow C stream that
// the analysis already filled (zero-copy float32/int32 slices of native memory): feature i of the source is paired with
// result row i POSITIONALLY, in physical file order. The output is deliberately UNINDEXED (index_node_size = 0): a packed
// Hilbert R-tree would reorder the features and break that positional correspondence for any reader that streams the file.
// The source file is opened read-only and is never modified; the output is written to a temporary file the caller has
// created exclusively and publishes afterwards.
//
// Column semantics (the Chalmers PST QGIS add-or-replace rule, applied to the NEW file): a result column whose name
// equals a source column replaces that column IN PLACE (same index, new type/nullability); any other result column is
// appended; every unrelated source column is copied unchanged (all Column fields) and its values are copied byte for
// byte. Duplicate source names, a result name that differs from a source name only by ASCII case (GDAL looks fields up
// case-insensitively), duplicate result names and source columns of an unknown ColumnType are rejected.
//
// Geometry: the accepted source geometry (exactly the reader's contract: XY LineString of two vertices) is re-encoded
// from the decoded source tables (type, ends, xy) - not rebuilt from PST's native float graph - and the header CRS table,
// envelope, name, title, description and metadata are carried over unchanged. Nothing is repaired or transformed.
// The temporary file is opened through rpst::fs (pst-fs-core.h) on both POSIX and Windows.

constexpr std::uint64_t kMaxColumns = 65535;  // property entries index columns with a uint16

int column_width(FlatGeobuf::ColumnType t)
{
    switch (t) {
        case FlatGeobuf::ColumnType::Byte: case FlatGeobuf::ColumnType::UByte: case FlatGeobuf::ColumnType::Bool: return 1;
        case FlatGeobuf::ColumnType::Short: case FlatGeobuf::ColumnType::UShort: return 2;
        case FlatGeobuf::ColumnType::Int: case FlatGeobuf::ColumnType::UInt: case FlatGeobuf::ColumnType::Float: return 4;
        case FlatGeobuf::ColumnType::Long: case FlatGeobuf::ColumnType::ULong: case FlatGeobuf::ColumnType::Double: return 8;
        default: return -1;  // String, Json, DateTime, Binary: uint32 length + bytes
    }
}

std::string ascii_lower(const std::string& s)
{
    std::string r = s;
    for (auto& c : r) if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
    return r;
}

// One result column as the Arrow stream describes it (format "f" = float32, "i" = int32).
struct ResultColumnPlan {
    std::string name;
    bool is_float = true;
    bool nullable = false;
    int target = -1;          // output column index
};


// ---- header metadata (provenance) ---------------------------------------------------------------------------------------
// The FlatGeobuf header has ONE free-form metadata string. Policy (docs/spatial-io/spatial-output.md §4):
//   * the source has none                      -> write rPSTool's provenance object;
//   * the source is a flat JSON object of string values that already holds `rpst:*` keys (an earlier rPSTool analysis wrote
//     it)                                      -> keep every other pair byte for byte, drop the old `rpst:*` pairs and append
//                                                 the current ones, so the header never describes an earlier calculation;
//   * anything else (opaque text, other JSON)  -> preserved unchanged; no provenance is claimed (it cannot be extended safely).
struct MetaPair { std::size_t begin, end; bool rpst; };

bool scan_json_string(const std::string& s, std::size_t& i, std::size_t& start, std::size_t& stop)
{
    if (i >= s.size() || s[i] != '"') return false;
    ++i;
    start = i;
    while (i < s.size()) {
        const unsigned char c = static_cast<unsigned char>(s[i]);
        if (c == '"') { stop = i; ++i; return true; }
        if (c == '\\') {
            if (i + 1 >= s.size()) return false;
            const char e = s[i + 1];
            if (e == 'u') {
                if (i + 6 > s.size()) return false;
                for (std::size_t k = 2; k < 6; ++k) if (!std::isxdigit(static_cast<unsigned char>(s[i + k]))) return false;
                i += 6;
            } else if (e == '"' || e == '\\' || e == '/' || e == 'b' || e == 'f' || e == 'n' || e == 'r' || e == 't') {
                i += 2;
            } else {
                return false;
            }
        } else {
            ++i;
        }
    }
    return false;
}

void skip_json_space(const std::string& s, std::size_t& i)
{
    while (i < s.size() && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r')) ++i;
}

// Strict scan of `{"k":"v",...}` (string values only). On success `pairs` holds the byte span of each `"k":"v"`.
bool scan_flat_string_object(const std::string& s, std::vector<MetaPair>& pairs)
{
    std::size_t i = 0;
    skip_json_space(s, i);
    if (i >= s.size() || s[i] != '{') return false;
    ++i;
    skip_json_space(s, i);
    if (i < s.size() && s[i] == '}') { ++i; skip_json_space(s, i); return i == s.size(); }
    for (;;) {
        skip_json_space(s, i);
        const std::size_t begin = i;
        std::size_t ks, ke, vs, ve;
        if (!scan_json_string(s, i, ks, ke)) return false;
        skip_json_space(s, i);
        if (i >= s.size() || s[i] != ':') return false;
        ++i;
        skip_json_space(s, i);
        if (!scan_json_string(s, i, vs, ve)) return false;
        pairs.push_back({begin, i, s.compare(ks, 5, "rpst:") == 0 && ke - ks >= 5});
        skip_json_space(s, i);
        if (i >= s.size()) return false;
        if (s[i] == ',') { ++i; continue; }
        if (s[i] == '}') { ++i; break; }
        return false;
    }
    skip_json_space(s, i);
    return i == s.size();
}

std::string json_escaped(const std::string& x)
{
    std::string r;
    r.reserve(x.size() + 2);
    r += '"';
    for (const unsigned char c : x) {
        switch (c) {
            case '"': r += "\\\""; break;
            case '\\': r += "\\\\"; break;
            case '\n': r += "\\n"; break;
            case '\r': r += "\\r"; break;
            case '\t': r += "\\t"; break;
            default:
                if (c < 0x20) { char u[8]; std::snprintf(u, sizeof u, "\\u%04x", c); r += u; }
                else r += static_cast<char>(c);
        }
    }
    r += '"';
    return r;
}

std::string merge_header_metadata(const std::string& source, const std::vector<std::pair<std::string, std::string>>& provenance)
{
    std::string fresh;
    for (const auto& kv : provenance) {
        if (!fresh.empty()) fresh += ',';
        fresh += json_escaped(kv.first) + ":" + json_escaped(kv.second);
    }
    if (source.empty()) return "{" + fresh + "}";
    std::vector<MetaPair> pairs;
    if (!scan_flat_string_object(source, pairs)) return source;                       // opaque: preserved faithfully
    bool owned = false;
    for (const MetaPair& p : pairs) owned = owned || p.rpst;
    if (!owned) return source;                                                         // not rPSTool's: never extended
    std::string out = "{";
    bool first = true;
    for (const MetaPair& p : pairs) {
        if (p.rpst) continue;
        if (!first) out += ',';
        out.append(source, p.begin, p.end - p.begin);                                  // unrelated pairs, byte for byte
        first = false;
    }
    if (!first) out += ',';
    out += fresh + "}";
    return out;
}

struct WriteOutcome {
    std::uint64_t rows = 0;
};

// Pull-through reader of the result stream: validates the schema once and then serves rows in order.
class ResultCursor {
public:
    ResultCursor(ArrowArrayStream* stream) : stream_(stream) {}
    ~ResultCursor() { release_batch(); if (have_schema_ && schema_.release) schema_.release(&schema_); rpst::arrow_stream_release(stream_); }
    ResultCursor(const ResultCursor&) = delete;
    ResultCursor& operator=(const ResultCursor&) = delete;

    // Validates "+s": the first child is the positional id (int32), then the expected result columns in order.
    bool open(const std::vector<std::string>& names, std::vector<ResultColumnPlan>& plan, char* error, std::size_t error_size)
    {
        if (!stream_ || !stream_->release || !stream_->get_schema || !stream_->get_next || !stream_->get_last_error)
            return fail(error, error_size, "The result stream has not been exported or is malformed.");
        if (stream_->get_schema(stream_, &schema_) != 0) return fail(error, error_size, "The result stream could not describe its schema.");
        have_schema_ = true;
        if (!schema_.format || std::strcmp(schema_.format, "+s") != 0 || schema_.n_children != static_cast<std::int64_t>(names.size()) + 1)
            return fail(error, error_size, "The result stream does not carry the expected struct of %llu result columns.",
                        static_cast<unsigned long long>(names.size()));
        if (!schema_.children) return fail(error, error_size, "The result stream's schema has no children.");
        const ArrowSchema* id = schema_.children[0];
        if (!id || !id->format || std::strcmp(id->format, "i") != 0)
            return fail(error, error_size, "The result stream's positional id column is not int32.");
        for (std::size_t k = 0; k < names.size(); ++k) {
            const ArrowSchema* c = schema_.children[k + 1];
            if (!c || !c->name || names[k] != c->name)
                return fail(error, error_size, "Result column %llu does not match the requested name.", static_cast<unsigned long long>(k + 1));
            if (!c->format || (std::strcmp(c->format, "f") != 0 && std::strcmp(c->format, "i") != 0))
                return fail(error, error_size, "Result column '%s' has an unsupported Arrow type '%s'.", c->name, c->format ? c->format : "");
            ResultColumnPlan p;
            p.name = names[k];
            p.is_float = std::strcmp(c->format, "f") == 0;
            p.nullable = (c->flags & 2) != 0;  // ARROW_FLAG_NULLABLE
            plan.push_back(p);
        }
        columns_ = names.size();
        return true;
    }

    // Advance to result row `row` (strictly sequential); returns false at the end or on a stream error.
    bool next_row(char* error, std::size_t error_size, bool& end)
    {
        end = false;
        while (position_ >= length_) {
            release_batch();
            if (stream_->get_next(stream_, &batch_) != 0) return fail(error, error_size, "The result stream failed while producing a batch.");
            if (!batch_.release) { end = true; return true; }
            have_batch_ = true;
            if (batch_.length < 0 || batch_.offset != 0 || !batch_.children || batch_.n_children != static_cast<std::int64_t>(columns_) + 1)
                return fail(error, error_size, "The result stream produced a malformed batch.");
            for (std::size_t k = 0; k <= columns_; ++k) {
                const ArrowArray* c = batch_.children[k];
                if (!c || c->length < batch_.length || c->offset < 0 || c->n_buffers < 2 || !c->buffers || (batch_.length > 0 && !c->buffers[1]))
                    return fail(error, error_size, "The result stream produced a malformed column array.");
            }
            length_ = static_cast<std::uint64_t>(batch_.length);
            position_ = 0;
        }
        return true;
    }
    // Value access for the current row (after next_row() returned !end).
    bool valid(std::size_t k) const
    {
        const ArrowArray* c = batch_.children[k + 1];
        if (c->null_count == 0 || !c->buffers[0]) return true;
        const std::uint64_t bit = static_cast<std::uint64_t>(c->offset) + position_;
        return (static_cast<const unsigned char*>(c->buffers[0])[bit >> 3] >> (bit & 7)) & 1u;
    }
    void value(std::size_t k, unsigned char out[4]) const
    {
        const ArrowArray* c = batch_.children[k + 1];
        std::memcpy(out, static_cast<const unsigned char*>(c->buffers[1]) + 4 * (static_cast<std::uint64_t>(c->offset) + position_), 4);
    }
    void advance() { ++position_; }

private:
    void release_batch() { if (have_batch_ && batch_.release) batch_.release(&batch_); have_batch_ = false; length_ = 0; position_ = 0; }
    ArrowArrayStream* stream_;
    ArrowSchema schema_{};
    ArrowArray batch_{};
    bool have_schema_ = false, have_batch_ = false;
    std::size_t columns_ = 0;
    std::uint64_t length_ = 0, position_ = 0;
};

struct OutputFile {
    std::FILE* f = nullptr;
    ~OutputFile() { if (f) std::fclose(f); }
    // The temporary file already exists (created exclusively by the caller); a symlink there is never followed.
    bool open(const char* path, char* error, std::size_t error_size)
    {
#ifdef _WIN32
        std::string message;
        f = rpst::fs::open_temp_for_write(path, message);
        if (!f) return fail(error, error_size, "Cannot open the temporary output file for writing (%s).", message.c_str());
        std::setvbuf(f, nullptr, _IOFBF, 1u << 20);   // large sequential writes; a failure only leaves the default buffer
        return true;
#else
        const int fd = ::open(path, O_WRONLY | O_NOFOLLOW | O_CLOEXEC);
        if (fd < 0) return fail(error, error_size, "Cannot open the temporary output file for writing.");
        f = ::fdopen(fd, "wb");
        if (!f) { ::close(fd); return fail(error, error_size, "Cannot open the temporary output file for writing."); }
        std::setvbuf(f, nullptr, _IOFBF, 1u << 20);   // large sequential writes; a failure only leaves the default buffer
        return true;
#endif
    }
    bool write(const void* data, std::size_t n) { return n == 0 || std::fwrite(data, 1, n, f) == n; }
    bool finish() { const bool ok = std::fflush(f) == 0 && !std::ferror(f); const bool closed = std::fclose(f) == 0; f = nullptr; return ok && closed; }
};

bool write_spatial(const char* source_path, const char* temp_path, ArrowArrayStream* stream,
                   const std::vector<std::string>& result_names, std::uint64_t expected_rows,
                   const std::vector<std::pair<std::string, std::string>>& provenance, WriteOutcome& outcome, char* error, std::size_t error_size)
{
    try {
        File file;
        if (!file.open(source_path, error, error_size)) return false;
        std::uint64_t header_total = 0;
        if (!read_header_size(file, header_total, error, error_size)) return false;
        std::vector<unsigned char> hbuf(static_cast<std::size_t>(header_total));
        HeaderFacts facts;
        if (!parse_header(file, hbuf.data(), header_total, facts, error, error_size)) return false;
        const FlatGeobuf::Header* h = FlatGeobuf::GetSizePrefixedHeader(hbuf.data());

        ResultCursor cursor(stream);
        std::vector<ResultColumnPlan> plan;
        if (!cursor.open(result_names, plan, error, error_size)) return false;

        // ---- column plan: source columns (replaced in place) + appended result columns ------------------------------
        struct OutColumn { std::string name; FlatGeobuf::ColumnType type; const FlatGeobuf::Column* source; int result; };
        std::vector<OutColumn> out;
        std::vector<FlatGeobuf::ColumnType> source_types;
        if (h->columns()) {
            for (const FlatGeobuf::Column* c : *h->columns()) {
                if (!c->name()) return fail(error, error_size, "A source column has no name.");
                if (static_cast<int>(c->type()) > static_cast<int>(FlatGeobuf::ColumnType::Binary))
                    return fail(error, error_size, "Source column '%s' has an unknown FlatGeobuf column type (%d); its values cannot be copied safely.",
                                c->name()->c_str(), static_cast<int>(c->type()));
                out.push_back({c->name()->str(), c->type(), c, -1});
                source_types.push_back(c->type());
            }
        }
        const std::size_t source_columns = out.size();
        for (std::size_t i = 0; i < source_columns; ++i)
            for (std::size_t j = i + 1; j < source_columns; ++j)
                if (ascii_lower(out[i].name) == ascii_lower(out[j].name))
                    return fail(error, error_size, "The source has the columns '%s' and '%s', which are identical or differ only by letter case; FlatGeobuf readers look fields up case-insensitively, so the output would be ambiguous.",
                                out[i].name.c_str(), out[j].name.c_str());
        for (std::size_t a = 0; a < plan.size(); ++a)
            for (std::size_t b = a + 1; b < plan.size(); ++b)
                if (ascii_lower(plan[a].name) == ascii_lower(plan[b].name))
                    return fail(error, error_size, "Two result columns have the same name ('%s').", plan[a].name.c_str());
        for (std::size_t a = 0; a < plan.size(); ++a) {
            int target = -1;
            for (std::size_t i = 0; i < source_columns; ++i) {
                if (out[i].name == plan[a].name) { target = static_cast<int>(i); break; }
                if (ascii_lower(out[i].name) == ascii_lower(plan[a].name))
                    return fail(error, error_size, "The result column '%s' differs from the source column '%s' only by letter case; FlatGeobuf readers look fields up case-insensitively, so replacing or adding it would be ambiguous.",
                                plan[a].name.c_str(), out[i].name.c_str());
            }
            const FlatGeobuf::ColumnType type = plan[a].is_float ? FlatGeobuf::ColumnType::Float : FlatGeobuf::ColumnType::Int;
            if (target >= 0) { out[static_cast<std::size_t>(target)].type = type; out[static_cast<std::size_t>(target)].source = nullptr; out[static_cast<std::size_t>(target)].result = static_cast<int>(a); }
            else { target = static_cast<int>(out.size()); out.push_back({plan[a].name, type, nullptr, static_cast<int>(a)}); }
            plan[a].target = target;
        }
        if (out.size() > kMaxColumns) return fail(error, error_size, "The output would have %llu columns; FlatGeobuf supports at most 65535.", static_cast<unsigned long long>(out.size()));
        std::vector<int> replaced(source_columns, 0);   // source column index -> replaced by a result column
        for (const auto& p : plan) if (static_cast<std::size_t>(p.target) < source_columns) replaced[static_cast<std::size_t>(p.target)] = 1;

        // ---- output header --------------------------------------------------------------------------------------------
        OutputFile output;
        if (!output.open(temp_path, error, error_size)) return false;
        {
            flatbuffers::FlatBufferBuilder b(1u << 14);
            std::vector<flatbuffers::Offset<FlatGeobuf::Column>> cols;
            cols.reserve(out.size());
            for (const OutColumn& c : out) {
                const auto name = b.CreateString(c.name);
                if (c.source) {
                    const FlatGeobuf::Column* s = c.source;
                    const auto title = s->title() ? b.CreateString(s->title()->str()) : flatbuffers::Offset<flatbuffers::String>();
                    const auto desc = s->description() ? b.CreateString(s->description()->str()) : flatbuffers::Offset<flatbuffers::String>();
                    const auto meta = s->metadata() ? b.CreateString(s->metadata()->str()) : flatbuffers::Offset<flatbuffers::String>();
                    cols.push_back(FlatGeobuf::CreateColumn(b, name, s->type(), title, desc, s->width(), s->precision(), s->scale(),
                                                            s->nullable(), s->unique(), s->primary_key(), meta));
                } else {
                    cols.push_back(FlatGeobuf::CreateColumn(b, name, c.type, 0, 0, -1, -1, -1, plan[static_cast<std::size_t>(c.result)].nullable));
                }
            }
            flatbuffers::Offset<FlatGeobuf::Crs> crs;
            if (const FlatGeobuf::Crs* c = h->crs()) {
                auto str = [&](const flatbuffers::String* x) { return x ? b.CreateString(x->str()) : flatbuffers::Offset<flatbuffers::String>(); };
                const auto org = str(c->org()), nm = str(c->name()), ds = str(c->description()), wkt = str(c->wkt()), cs = str(c->code_string());
                crs = FlatGeobuf::CreateCrs(b, org, c->code(), nm, ds, wkt, cs);
            }
            std::vector<double> envelope;
            if (h->envelope()) envelope.assign(h->envelope()->begin(), h->envelope()->end());
            const std::string source_meta = h->metadata() ? h->metadata()->str() : std::string();
            const std::string meta = merge_header_metadata(source_meta, provenance);   // see the policy above
            const auto header = FlatGeobuf::CreateHeaderDirect(
                b, h->name() ? h->name()->c_str() : nullptr, envelope.empty() ? nullptr : &envelope, h->geometry_type(),
                false, false, false, false, &cols, expected_rows, 0, crs, h->title() ? h->title()->c_str() : nullptr,
                h->description() ? h->description()->c_str() : nullptr, meta.empty() ? nullptr : meta.c_str());
            FlatGeobuf::FinishSizePrefixedHeaderBuffer(b, header);
            static const unsigned char magic_prefix[7] = {0x66, 0x67, 0x62, 0x03, 0x66, 0x67, 0x62};
            unsigned char magic[8];
            std::memcpy(magic, magic_prefix, 7);
            // Copy the source's own patch-level byte (the eighth magic byte) so the file declares what it was derived from.
            unsigned char head[8];
            if (!file.seek(0) || !file.read(head, 8)) return fail(error, error_size, "Cannot re-read the source signature.");
            magic[7] = head[7];
            if (b.GetSize() > kMaxHeaderBytes + 4) return fail(error, error_size, "The output header would exceed the 64 MiB limit.");
            if (!output.write(magic, 8) || !output.write(b.GetBufferPointer(), b.GetSize()))
                return fail(error, error_size, "Writing the output header failed (is the disk full?).");
        }

        // ---- records ------------------------------------------------------------------------------------------------------
        if (!file.seek(facts.data_start)) return fail(error, error_size, "Cannot seek to the FlatGeobuf features.");
        const std::uint64_t room = file.size - facts.data_start;
        std::vector<unsigned char> record, props;
        flatbuffers::FlatBufferBuilder fb(1u << 10);
        std::uint64_t pos = 0, rows = 0;
        while (pos < room) {
            const unsigned long long number = static_cast<unsigned long long>(rows + 1);
            if (room - pos < 4) return fail(error, error_size, "Feature %llu: truncated size prefix.", number);
            unsigned char prefix[4];
            if (!file.read(prefix, 4)) return fail(error, error_size, "Feature %llu: cannot read the size prefix.", number);
            const std::uint64_t size = load_u32(prefix);
            if (size > kMaxRecordBytes) return fail(error, error_size, "Feature %llu: the size prefix exceeds the 64 MiB limit.", number);
            if (size > room - pos - 4) return fail(error, error_size, "Feature %llu: the size prefix exceeds the bytes remaining in the file.", number);
            record.resize(static_cast<std::size_t>(4 + size));
            std::memcpy(record.data(), prefix, 4);
            if (!file.read(record.data() + 4, size)) return fail(error, error_size, "Feature %llu: truncated record.", number);
            pos += 4 + size;
            if (rows >= expected_rows) return fail(error, error_size, "The source has more features than the %llu analysis result rows; it changed since the graph was built.", static_cast<unsigned long long>(expected_rows));
            flatbuffers::Verifier verifier(record.data(), record.size());
            if (!FlatGeobuf::VerifySizePrefixedFeatureBuffer(verifier)) return fail(error, error_size, "Feature %llu: the record failed FlatBuffers verification.", number);
            double xy[4];
            char reason[200];
            if (!decode_feature(record.data(), facts.geometry_type, xy, reason, sizeof reason))
                return fail(error, error_size, "Feature %llu: %s (the source changed since the graph was built).", number, reason);
            const FlatGeobuf::Feature* ft = FlatGeobuf::GetSizePrefixedFeature(record.data());
            if (ft->columns() && ft->columns()->size())
                return fail(error, error_size, "Feature %llu carries its own column schema, which is unsupported.", number);

            // properties: copy every entry of a column that is not replaced; then append the result entries
            props.clear();
            if (const auto* p = ft->properties()) {
                const unsigned char* d = p->data();
                const std::size_t length = p->size();
                std::size_t o = 0;
                while (o < length) {
                    if (length - o < 2) return fail(error, error_size, "Feature %llu: a truncated property entry.", number);
                    std::uint16_t ci;
                    std::memcpy(&ci, d + o, 2);
                    if (ci >= source_columns) return fail(error, error_size, "Feature %llu: a property refers to column %u, but the header has %llu.", number, static_cast<unsigned>(ci), static_cast<unsigned long long>(source_columns));
                    const std::size_t start = o;
                    o += 2;
                    std::size_t value_bytes;
                    const int w = column_width(source_types[ci]);
                    if (w > 0) value_bytes = static_cast<std::size_t>(w);
                    else {
                        if (length - o < 4) return fail(error, error_size, "Feature %llu: a truncated property length.", number);
                        const std::uint64_t counted = 4 + static_cast<std::uint64_t>(load_u32(d + o));   // 64-bit: no wrap on 32-bit hosts
                        if (counted > length - o) return fail(error, error_size, "Feature %llu: a property value extends beyond the property buffer.", number);
                        value_bytes = static_cast<std::size_t>(counted);
                    }
                    if (value_bytes > length - o) return fail(error, error_size, "Feature %llu: a property value extends beyond the property buffer.", number);
                    o += value_bytes;
                    if (!replaced[ci]) props.insert(props.end(), d + start, d + o);
                }
            }
            bool end = false;
            if (!cursor.next_row(error, error_size, end)) return false;
            if (end) return fail(error, error_size, "The analysis produced fewer result rows (%llu) than the source has features.", static_cast<unsigned long long>(rows));
            for (std::size_t k = 0; k < plan.size(); ++k) {
                if (!cursor.valid(k)) continue;  // a null result is an omitted property
                const std::uint16_t idx = static_cast<std::uint16_t>(plan[k].target);
                unsigned char v[4];
                cursor.value(k, v);
                const std::size_t at = props.size();
                props.resize(at + 6);
                std::memcpy(props.data() + at, &idx, 2);
                std::memcpy(props.data() + at + 2, v, 4);
            }
            cursor.advance();

            // geometry: the decoded source tables, re-encoded unchanged
            fb.Clear();
            flatbuffers::Offset<FlatGeobuf::Geometry> geometry;
            {
                const FlatGeobuf::Geometry* g = ft->geometry();  // non-null: decode_feature accepted it
                const auto ends = g->ends() ? fb.CreateVector(g->ends()->data(), g->ends()->size()) : flatbuffers::Offset<flatbuffers::Vector<std::uint32_t>>();
                const auto coords = fb.CreateVector(g->xy()->data(), g->xy()->size());
                geometry = FlatGeobuf::CreateGeometry(fb, ends, coords, 0, 0, 0, 0, g->type(), 0);
            }
            const auto properties = props.empty() ? flatbuffers::Offset<flatbuffers::Vector<std::uint8_t>>() : fb.CreateVector(props.data(), props.size());
            FlatGeobuf::FinishSizePrefixedFeatureBuffer(fb, FlatGeobuf::CreateFeature(fb, geometry, properties, 0));
            if (fb.GetSize() > kMaxRecordBytes + 4) return fail(error, error_size, "Feature %llu: the output record would exceed the 64 MiB limit.", number);
            if (!output.write(fb.GetBufferPointer(), fb.GetSize())) return fail(error, error_size, "Writing feature %llu failed (is the disk full?).", number);
            ++rows;
        }
        if (rows != expected_rows)
            return fail(error, error_size, "The source has %llu features but the analysis produced %llu result rows; it changed since the graph was built.",
                        static_cast<unsigned long long>(rows), static_cast<unsigned long long>(expected_rows));
        bool end = false;
        if (!cursor.next_row(error, error_size, end)) return false;
        if (!end) return fail(error, error_size, "The analysis produced more result rows than the source has features.");
        if (!output.finish()) return fail(error, error_size, "Finishing the output file failed (is the disk full?).");
        outcome.rows = rows;
        return true;
    } catch (const std::exception& e) {
        return fail(error, error_size, "Writing the FlatGeobuf output failed: %s", e.what());
    } catch (...) {
        return fail(error, error_size, "Writing the FlatGeobuf output failed with an unknown native exception.");
    }
}
}  // namespace

// Inspect the header of one FlatGeobuf file: apply the header-level policy and return the raw verified header
// bytes (for revalidation at decode time) together with the facts R needs to interpret the CRS.
extern "C" SEXP rpst_fgb_inspect(SEXP path_argument_sexp)
{
    const char* path = path_argument(path_argument_sexp);
    if (!host_is_little_endian()) Rf_error("FlatGeobuf input is not supported on big-endian hosts.");
    char error[512] = "";
    std::uint64_t header_total = 0;
    {
        File file;
        if (file.open(path, error, sizeof error)) read_header_size(file, header_total, error, sizeof error);
    }
    if (error[0]) Rf_error("%s", error);

    SEXP header = PROTECT(Rf_allocVector(RAWSXP, static_cast<R_xlen_t>(header_total)));
    unsigned char* buffer = RAW(header);
    HeaderFacts facts;
    {
        File file;
        std::uint64_t again = 0;
        if (file.open(path, error, sizeof error) && read_header_size(file, again, error, sizeof error)) {
            if (again != header_total) fail(error, sizeof error, "The FlatGeobuf file changed while it was being inspected.");
            else parse_header(file, buffer, header_total, facts, error, sizeof error);
        }
    }
    if (error[0]) Rf_error("%s", error);

    SEXP result = PROTECT(Rf_allocVector(VECSXP, 5));
    SEXP names = PROTECT(Rf_allocVector(STRSXP, 5));
    const char* labels[] = {"header", "features_count", "index_node_size", "geometry_type", "crs"};
    for (int i = 0; i < 5; ++i) SET_STRING_ELT(names, i, Rf_mkChar(labels[i]));
    Rf_setAttrib(result, R_NamesSymbol, names);
    SET_VECTOR_ELT(result, 0, header);
    SET_VECTOR_ELT(result, 1, Rf_ScalarReal(static_cast<double>(facts.features)));
    SET_VECTOR_ELT(result, 2, Rf_ScalarInteger(static_cast<int>(facts.index_node_size)));
    SET_VECTOR_ELT(result, 3, Rf_ScalarInteger(facts.geometry_type));
    if (facts.has_crs) {
        SEXP crs = PROTECT(Rf_allocVector(VECSXP, 6));
        SEXP crs_names = PROTECT(Rf_allocVector(STRSXP, 6));
        const char* crs_labels[] = {"org", "code", "name", "description", "wkt", "code_string"};
        for (int i = 0; i < 6; ++i) SET_STRING_ELT(crs_names, i, Rf_mkChar(crs_labels[i]));
        Rf_setAttrib(crs, R_NamesSymbol, crs_names);
        SET_VECTOR_ELT(crs, 0, string_or_null(buffer, facts.org_present, facts.org_off, facts.org_len));
        SET_VECTOR_ELT(crs, 1, Rf_ScalarInteger(facts.crs_code));
        SET_VECTOR_ELT(crs, 2, string_or_null(buffer, facts.name_present, facts.name_off, facts.name_len));
        SET_VECTOR_ELT(crs, 3, string_or_null(buffer, facts.description_present, facts.description_off, facts.description_len));
        SET_VECTOR_ELT(crs, 4, string_or_null(buffer, facts.wkt_present, facts.wkt_off, facts.wkt_len));
        SET_VECTOR_ELT(crs, 5, string_or_null(buffer, facts.code_string_present, facts.code_string_off, facts.code_string_len));
        SET_VECTOR_ELT(result, 4, crs);
        UNPROTECT(2);
    }
    UNPROTECT(3);
    return result;
}

// Decode the file into the pre-allocated empty graph pointer through the shared segment or axial builder
// (`aux` non-null selects the axial builder). `header` is the raw header from rpst_fgb_inspect(); the re-read
// header must equal it exactly. The caller has already validated the pointer and staged `aux`.
SEXP decode_and_build(SEXP graph, SEXP path_argument_sexp, SEXP header, const rpst::AxialAuxiliary* aux)
{
    const bool axial = aux != nullptr;
    const char* path = path_argument(path_argument_sexp);
    if (TYPEOF(header) != RAWSXP || XLENGTH(header) < 12 || static_cast<std::uint64_t>(XLENGTH(header)) > kMaxHeaderBytes + 4)
        Rf_error("header must be the raw header returned by the inspection step.");
    if (!host_is_little_endian()) Rf_error("FlatGeobuf input is not supported on big-endian hosts.");
    const unsigned char* inspected = RAW(header);
    const std::uint64_t inspected_size = static_cast<std::uint64_t>(XLENGTH(header));
    char error[512] = "";
    {
        std::vector<double2> coords;
        {
            File file;
            std::uint64_t header_total = 0;
            if (file.open(path, error, sizeof error) && read_header_size(file, header_total, error, sizeof error)) {
                if (header_total != inspected_size) {
                    fail(error, sizeof error, "The FlatGeobuf header changed between inspection and decoding.");
                } else {
                    try {
                        std::vector<unsigned char> buffer(static_cast<std::size_t>(header_total));
                        HeaderFacts facts;
                        if (parse_header(file, buffer.data(), header_total, facts, error, sizeof error)) {
                            if (std::memcmp(buffer.data(), inspected, static_cast<std::size_t>(header_total)) != 0)
                                fail(error, sizeof error, "The FlatGeobuf header changed between inspection and decoding.");
                            else if (decode_records(file, facts, coords, axial, error, sizeof error)) {
                                if (axial) rpst::axial_graph_build(graph, coords, *aux, error, sizeof error);
                                else rpst::segment_graph_build(graph, coords, error, sizeof error);
                            }
                        }
                    } catch (const std::exception& e) {
                        fail(error, sizeof error, "FlatGeobuf decoding failed: %s", e.what());
                    } catch (...) {
                        fail(error, sizeof error, "FlatGeobuf decoding failed with an unknown native exception.");
                    }
                }
            }
        }  // the file is closed before the coordinate vector is released
    }
    // All C++ owners have unwound before R's non-local error jump.
    if (error[0]) Rf_error("%s", error);
    return graph;
}

extern "C" SEXP rpst_fgb_segment_graph(SEXP graph, SEXP path_argument_sexp, SEXP header)
{
    rpst::segment_graph_require_empty(graph);
    return decode_and_build(graph, path_argument_sexp, header, nullptr);
}

// Axial variant: the optional unlinks/points/polygon inputs are validated and viewed BEFORE any C++ owner exists.
extern "C" SEXP rpst_fgb_axial_graph(SEXP graph, SEXP path_argument_sexp, SEXP header, SEXP unlinks, SEXP points,
                                     SEXP polygon_sizes, SEXP interval)
{
    rpst::axial_graph_require_empty(graph);
    rpst::AxialAuxiliary aux;
    rpst::stage_axial_auxiliary(unlinks, points, polygon_sizes, interval, aux);
    return decode_and_build(graph, path_argument_sexp, header, &aux);
}

// Spatial output (docs/spatial-io/spatial-output.md). Argument staging (the only part that can raise R errors) happens before any C++
// owner exists; the writer reports failures through a fixed buffer; the R error is raised after everything has unwound.
//   stream    rPST::ArrowArrayStream/v1 pointer already filled by the analysis (released by the writer once it has taken
//             it over; on an earlier failure the caller's rpst_arrow_stream_free() releases it - exactly once either way)
//   source    path of the original FlatGeobuf (opened read-only)
//   temp      path of the exclusively created temporary output
//   names     result column names in stream order (without the positional id column)
//   rows      expected row count (the native graph size)
//   prov_names/prov_values  the provenance pairs for the header metadata string (merged by merge_header_metadata())
extern "C" SEXP rpst_fgb_write_spatial(SEXP stream_, SEXP source_, SEXP temp_, SEXP names_, SEXP rows_, SEXP prov_names_, SEXP prov_values_)
{
    ArrowArrayStream* stream = rpst::arrow_stream_require(stream_);
    const char* source = path_argument(source_);
    const char* temp = path_argument(temp_);
    if (TYPEOF(names_) != STRSXP || XLENGTH(names_) < 1) Rf_error("names must be a non-empty character vector.");
    if (TYPEOF(rows_) != REALSXP || XLENGTH(rows_) != 1 || !R_FINITE(REAL(rows_)[0]) || REAL(rows_)[0] < 1 || REAL(rows_)[0] != std::floor(REAL(rows_)[0]) || REAL(rows_)[0] > 9007199254740992.0)
        Rf_error("rows must be one positive whole number.");
    if (TYPEOF(prov_names_) != STRSXP || TYPEOF(prov_values_) != STRSXP || XLENGTH(prov_names_) != XLENGTH(prov_values_) || XLENGTH(prov_names_) < 1)
        Rf_error("The provenance names and values must be character vectors of the same non-zero length.");
    for (R_xlen_t i = 0; i < XLENGTH(prov_names_); ++i)
        if (STRING_ELT(prov_names_, i) == NA_STRING || STRING_ELT(prov_values_, i) == NA_STRING) Rf_error("Provenance entries must not be missing.");
    if (!host_is_little_endian()) Rf_error("FlatGeobuf output is not supported on big-endian hosts.");
    for (R_xlen_t i = 0; i < XLENGTH(names_); ++i)
        if (STRING_ELT(names_, i) == NA_STRING || !CHAR(STRING_ELT(names_, i))[0]) Rf_error("Result column names must be non-empty and non-missing.");
    // Translation may raise an R error, so it happens here, before any C++ owner exists.
    const R_xlen_t n_names = XLENGTH(names_);
    const char** name_ptrs = reinterpret_cast<const char**>(R_alloc(static_cast<std::size_t>(n_names), sizeof(const char*)));
    for (R_xlen_t i = 0; i < n_names; ++i) name_ptrs[i] = Rf_translateCharUTF8(STRING_ELT(names_, i));
    const R_xlen_t n_prov = XLENGTH(prov_names_);
    const char** prov_name_ptrs = reinterpret_cast<const char**>(R_alloc(static_cast<std::size_t>(n_prov), sizeof(const char*)));
    const char** prov_value_ptrs = reinterpret_cast<const char**>(R_alloc(static_cast<std::size_t>(n_prov), sizeof(const char*)));
    for (R_xlen_t i = 0; i < n_prov; ++i) {
        prov_name_ptrs[i] = Rf_translateCharUTF8(STRING_ELT(prov_names_, i));
        prov_value_ptrs[i] = Rf_translateCharUTF8(STRING_ELT(prov_values_, i));
    }
    char error[512] = "";
    WriteOutcome outcome;
    {
        std::vector<std::string> names;
        std::vector<std::pair<std::string, std::string>> provenance;
        try {
            for (R_xlen_t i = 0; i < n_names; ++i) names.emplace_back(name_ptrs[i]);
            for (R_xlen_t i = 0; i < n_prov; ++i) provenance.emplace_back(prov_name_ptrs[i], prov_value_ptrs[i]);
        } catch (...) { fail(error, sizeof error, "Out of memory staging the result names."); }
        if (!error[0]) write_spatial(source, temp, stream, names, static_cast<std::uint64_t>(REAL(rows_)[0]), provenance, outcome, error, sizeof error);
    }  // every C++ owner (file, buffers, cursor, stream release) has unwound
    if (error[0]) Rf_error("%s", error);
    return Rf_ScalarReal(static_cast<double>(outcome.rows));
}

// Column names, types and nullable flags of a FlatGeobuf header (verified), for the R descriptor and tests. The header
// is read into an R raw vector first, so no C++ owner is alive while R allocates.
extern "C" SEXP rpst_fgb_columns(SEXP path_argument_sexp)
{
    const char* path = path_argument(path_argument_sexp);
    if (!host_is_little_endian()) Rf_error("FlatGeobuf input is not supported on big-endian hosts.");
    char error[512] = "";
    std::uint64_t header_total = 0;
    { File file; if (file.open(path, error, sizeof error)) read_header_size(file, header_total, error, sizeof error); }
    if (error[0]) Rf_error("%s", error);
    SEXP header = PROTECT(Rf_allocVector(RAWSXP, static_cast<R_xlen_t>(header_total)));
    {
        File file; std::uint64_t again = 0; HeaderFacts facts;
        if (file.open(path, error, sizeof error) && read_header_size(file, again, error, sizeof error)) {
            if (again != header_total) fail(error, sizeof error, "The FlatGeobuf file changed while it was being inspected.");
            else parse_header(file, RAW(header), header_total, facts, error, sizeof error);
        }
    }
    if (error[0]) Rf_error("%s", error);
    const FlatGeobuf::Header* h = FlatGeobuf::GetSizePrefixedHeader(RAW(header));
    const R_xlen_t n = h->columns() ? static_cast<R_xlen_t>(h->columns()->size()) : 0;
    SEXP names = PROTECT(Rf_allocVector(STRSXP, n));
    SEXP types = PROTECT(Rf_allocVector(INTSXP, n));
    SEXP nullable = PROTECT(Rf_allocVector(LGLSXP, n));
    for (R_xlen_t i = 0; i < n; ++i) {
        const FlatGeobuf::Column* c = h->columns()->Get(static_cast<flatbuffers::uoffset_t>(i));
        SET_STRING_ELT(names, i, Rf_mkCharLenCE(c->name()->data(), static_cast<int>(c->name()->size()), CE_UTF8));
        INTEGER(types)[i] = static_cast<int>(c->type());
        LOGICAL(nullable)[i] = c->nullable();
    }
    // the header metadata string as raw bytes (it may hold anything), or NULL when absent
    SEXP metadata = R_NilValue;
    if (h->metadata()) {
        metadata = PROTECT(Rf_allocVector(RAWSXP, static_cast<R_xlen_t>(h->metadata()->size())));
        if (h->metadata()->size()) std::memcpy(RAW(metadata), h->metadata()->data(), h->metadata()->size());
    } else {
        metadata = PROTECT(R_NilValue);
    }
    SEXP result = PROTECT(Rf_allocVector(VECSXP, 4));
    SET_VECTOR_ELT(result, 0, names); SET_VECTOR_ELT(result, 1, types); SET_VECTOR_ELT(result, 2, nullable); SET_VECTOR_ELT(result, 3, metadata);
    SEXP labels = PROTECT(Rf_allocVector(STRSXP, 4));
    SET_STRING_ELT(labels, 0, Rf_mkChar("name")); SET_STRING_ELT(labels, 1, Rf_mkChar("type")); SET_STRING_ELT(labels, 2, Rf_mkChar("nullable")); SET_STRING_ELT(labels, 3, Rf_mkChar("metadata"));
    Rf_setAttrib(result, R_NamesSymbol, labels);
    UNPROTECT(7);
    return result;
}
