// Internal, test-only synthetic Arrow C stream producer. It lets the native Arrow C boundary
// (pst-geoparquet.cpp) be tested without R arrow, pyarrow, Python or libarrow: well-formed
// streams, deliberately malformed streams, and lifecycle counters. Not public API; reached
// only through internal .Call entries used by the test suite.
//
// Memory safety of the harness itself: no malformed case may rely on undefined behaviour of
// the producer. Overrides therefore only lie about fields the consumer must reject BEFORE
// dereferencing a buffer, and every produced buffer array is sized to cover its declared
// n_buffers / n_children. Fresh schema/array nodes stay under RAII holders until ownership
// has been transferred. The persistent stream state owns every string and byte it needs: it
// retains no pointer into R memory and no SEXP.
//
// R safety: the whole R-facing specification is validated into plain scalars/SEXP handles
// before any C++ owner exists; native construction then runs inside a try block whose
// failures are captured in a fixed buffer, and only after every owner has unwound is
// Rf_error called.
#define R_NO_REMAP
#include <Rinternals.h>
#include <algorithm>
#include <cerrno>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <limits>
#include <memory>
#include <string>
#include <vector>
#include "pst-arrow-owner.h"

namespace {
double c_schema_made = 0, c_schema_released = 0, c_array_made = 0, c_array_released = 0,
       c_stream_made = 0, c_stream_released = 0;

// ---- schema nodes ---------------------------------------------------------------------------

struct SchemaNode {
    std::string name, format;
    std::vector<ArrowSchema*> kids;  // owned child structs (may hold nullptr entries)
    ArrowSchema* dict = nullptr;
    ArrowSchema* unused_slot = nullptr;  // target of a legal non-NULL children pointer with n_children == 0
};
SchemaNode* node_of(ArrowSchema* s) { return static_cast<SchemaNode*>(s->private_data); }

void destroy_schema(ArrowSchema* s)
{
    if (!s) return;
    if (s->release) s->release(s);
    delete s;
}
void schema_release(ArrowSchema* s)
{
    auto* n = node_of(s);
    ++c_schema_released;
    for (auto* kid : n->kids) destroy_schema(kid);
    destroy_schema(n->dict);
    delete n;
    s->release = nullptr;
    s->private_data = nullptr;
    s->children = nullptr;
    s->dictionary = nullptr;
    s->n_children = 0;
}
void init_schema(ArrowSchema* s, const char* name, const char* format)
{
    std::memset(s, 0, sizeof *s);
    auto* n = new SchemaNode();
    try {
        n->name = name;
        n->format = format;
    } catch (...) {
        delete n;
        throw;
    }
    s->format = n->format.c_str();
    s->name = n->name.c_str();
    s->flags = 2;
    s->private_data = n;
    s->release = schema_release;
    ++c_schema_made;
}
struct SchemaHolder {
    ArrowSchema* s = new ArrowSchema();
    ~SchemaHolder() { destroy_schema(s); }
    ArrowSchema* take() { auto* r = s; s = nullptr; return r; }
    SchemaHolder() = default;
    SchemaHolder(const SchemaHolder&) = delete;
    SchemaHolder& operator=(const SchemaHolder&) = delete;
};
// Insert a holder's schema into `parent`; the holder keeps ownership until push_back succeeds.
void add_kid(ArrowSchema* parent, SchemaHolder& h)
{
    node_of(parent)->kids.push_back(h.s);
    h.take();
    parent->children = node_of(parent)->kids.data();
    parent->n_children = static_cast<std::int64_t>(node_of(parent)->kids.size());
}

// ---- array nodes ----------------------------------------------------------------------------

struct ArrayNode {
    std::vector<unsigned char> validity, offsets, data;
    std::vector<const void*> buffers;
    std::vector<ArrowArray*> kids;
    ArrowArray* dict = nullptr;
    ArrowArray* unused_slot = nullptr;
};
ArrayNode* node_of(ArrowArray* a) { return static_cast<ArrayNode*>(a->private_data); }

void destroy_array(ArrowArray* a)
{
    if (!a) return;
    if (a->release) a->release(a);
    delete a;
}
void array_release(ArrowArray* a)
{
    auto* n = node_of(a);
    ++c_array_released;
    for (auto* kid : n->kids) destroy_array(kid);
    destroy_array(n->dict);
    delete n;
    a->release = nullptr;
    a->private_data = nullptr;
    a->buffers = nullptr;
    a->children = nullptr;
    a->dictionary = nullptr;
    a->n_buffers = 0;
    a->n_children = 0;
}
void init_array(ArrowArray* a)
{
    std::memset(a, 0, sizeof *a);
    a->private_data = new ArrayNode();
    a->release = array_release;
    ++c_array_made;
}
struct ArrayHolder {
    ArrowArray* a = new ArrowArray();
    ~ArrayHolder() { destroy_array(a); }
    ArrowArray* take() { auto* r = a; a = nullptr; return r; }
    ArrayHolder() = default;
    ArrayHolder(const ArrayHolder&) = delete;
    ArrayHolder& operator=(const ArrayHolder&) = delete;
};

// ---- specification --------------------------------------------------------------------------

struct Batch { std::int64_t first, count, parent_offset, child_offset, tail; };

const char* const kNumeric[] = {
    "fail_get_schema", "fail_next_at", "top_n_children", "child_n_children_schema",
    "parent_length", "parent_offset", "child_length", "child_offset", "parent_n_buffers",
    "child_n_buffers", "parent_n_children", "child_n_children", "parent_null_count",
    "child_null_count", "offset_corrupt_mode", "offset_corrupt_row", "override_batch"};
enum Numeric { FAIL_GET_SCHEMA, FAIL_NEXT_AT, TOP_N_CHILDREN, CHILD_N_CHILDREN_SCHEMA,
               PARENT_LENGTH, PARENT_OFFSET, CHILD_LENGTH, CHILD_OFFSET, PARENT_N_BUFFERS,
               CHILD_N_BUFFERS, PARENT_N_CHILDREN, CHILD_N_CHILDREN, PARENT_NULL_COUNT,
               CHILD_NULL_COUNT, OFFSET_CORRUPT_MODE, OFFSET_CORRUPT_ROW, OVERRIDE_BATCH,
               NUMERIC_COUNT };
const char* const kFlags[] = {
    "missing_get_schema", "missing_get_next", "missing_get_last_error", "missing_release",
    "null_last_error", "released_top_schema", "released_child_schema", "top_dictionary",
    "child_dictionary_schema", "null_child_schema", "unused_children_schema",
    "parent_dictionary", "child_dictionary", "null_parent_buffers", "null_child_buffers",
    "null_offsets", "null_data", "null_child", "released_child_array",
    "unused_children_array", "force_parent_bitmap", "force_child_bitmap", "drop_bitmaps"};
enum Flag { MISSING_GET_SCHEMA, MISSING_GET_NEXT, MISSING_GET_LAST_ERROR, MISSING_RELEASE,
            NULL_LAST_ERROR, RELEASED_TOP_SCHEMA, RELEASED_CHILD_SCHEMA, TOP_DICTIONARY,
            CHILD_DICTIONARY_SCHEMA, NULL_CHILD_SCHEMA, UNUSED_CHILDREN_SCHEMA,
            PARENT_DICTIONARY, CHILD_DICTIONARY, NULL_PARENT_BUFFERS, NULL_CHILD_BUFFERS,
            NULL_OFFSETS, NULL_DATA, NULL_CHILD, RELEASED_CHILD_ARRAY,
            UNUSED_CHILDREN_ARRAY, FORCE_PARENT_BITMAP, FORCE_CHILD_BITMAP, DROP_BITMAPS,
            FLAG_COUNT };

// Per-control bounds. Large int64 ranges are kept ONLY for controls that deliberately exercise
// decoder overflow/addressability; every count, loop and allocation control is small.
struct Bound { double lo, hi; };
const Bound kNumericBounds[] = {
    {1, 255},            // fail_get_schema (narrowed to int)
    {1, 1e5},            // fail_next_at (also checked against the plan)
    {0, 8},              // top_n_children
    {0, 8},              // child_n_children_schema
    {-9.2e18, 9.2e18},   // parent_length    (overflow tests)
    {-9.2e18, 9.2e18},   // parent_offset    (overflow tests)
    {-9.2e18, 9.2e18},   // child_length     (overflow tests)
    {-9.2e18, 9.2e18},   // child_offset     (overflow tests)
    {0, 8},              // parent_n_buffers (sizes a buffer array)
    {0, 8},              // child_n_buffers  (sizes a buffer array)
    {0, 8},              // parent_n_children
    {0, 8},              // child_n_children
    {-9.2e18, 9.2e18},   // parent_null_count (stored, never sized)
    {-9.2e18, 9.2e18},   // child_null_count
    {0, 4},              // offset_corrupt_mode
    {1, 2e6},            // offset_corrupt_row (also checked against the pool)
    {0, 1e5}};           // override_batch (also checked against the plan)
static_assert(sizeof(kNumericBounds) / sizeof(kNumericBounds[0]) == NUMERIC_COUNT,
              "one bound per numeric control");
const double kMaxPool = 2e6;       // rows in the pool
const double kMaxBatches = 1e5;    // plan rows
const double kMaxSlice = 1e5;      // per-batch parent_offset / child_offset / tail
const double kMaxTotalRows = 1e7;  // rows the plan may request in total
const double kMaxPhysical = 4e6;   // physical entries one batch may materialise

// Staged, validated specification: plain scalars and non-owning pointers into R vectors (the
// .Call arguments, which stay alive and unmoved for the whole call) or into R_alloc storage.
// All R API access and materialisation happens while this is built, before any C++ owner
// exists; the C++ construction phase afterwards deep-copies and makes no R API call.
struct RawSpec {
    R_xlen_t n_rows = 0;
    const unsigned char** row_data = nullptr;  // R_alloc'd array of n_rows pointers
    R_xlen_t* row_size = nullptr;              // R_alloc'd array of n_rows lengths
    const double* plan = nullptr;              // column-major n_plan x 5, or null
    R_xlen_t n_plan = 0;
    const int* nulls_parent = nullptr;
    R_xlen_t n_nulls_parent = 0;
    const int* nulls_child = nullptr;
    R_xlen_t n_nulls_child = 0;
    const char* top_format = nullptr;
    const char* child_format = nullptr;
    const char* child_name = nullptr;
    bool large = false;
    bool numeric_set[NUMERIC_COUNT] = {};
    std::int64_t numeric[NUMERIC_COUNT] = {};
    bool flag[FLAG_COUNT] = {};
};

SEXP list_field(SEXP list, const char* name)
{
    SEXP names = Rf_getAttrib(list, R_NamesSymbol);
    if (TYPEOF(names) != STRSXP) return R_NilValue;
    for (R_xlen_t i = 0; i < XLENGTH(list); ++i)
        if (std::strcmp(CHAR(STRING_ELT(names, i)), name) == 0) return VECTOR_ELT(list, i);
    return R_NilValue;
}

double whole_in_range(double v, double lo, double hi, const char* what)
{
    if (!std::isfinite(v) || std::floor(v) != v || v < lo || v > hi)
        Rf_error("Test stream spec: %s must be a whole number in [%.0f, %.0f].", what, lo, hi);
    return v;
}

const char* optional_string(SEXP spec, const char* name)
{
    SEXP v = list_field(spec, name);
    if (v == R_NilValue) return nullptr;
    if (TYPEOF(v) != STRSXP || XLENGTH(v) != 1 || STRING_ELT(v, 0) == NA_STRING)
        Rf_error("Test stream spec: %s must be one non-missing string.", name);
    return CHAR(STRING_ELT(v, 0));
}

const int* optional_index_vector(SEXP spec, const char* name, R_xlen_t pool, R_xlen_t& length)
{
    SEXP v = list_field(spec, name);
    length = 0;
    if (v == R_NilValue) return nullptr;
    if (TYPEOF(v) != INTSXP)
        Rf_error("Test stream spec: %s must be an integer vector of 1-based pool rows.", name);
    const int* data = INTEGER(v);
    length = XLENGTH(v);
    if (length > pool) Rf_error("Test stream spec: %s lists more rows than the pool holds.", name);
    for (R_xlen_t i = 0; i < length; ++i)
        if (data[i] == NA_INTEGER || data[i] < 1 || data[i] > pool)
            Rf_error("Test stream spec: %s contains an invalid pool row index.", name);
    return data;
}

// Validates and stages the whole specification; may raise R errors, so it must run before any
// C++ owner exists.
void parse_spec(SEXP spec, RawSpec& raw)
{
    if (TYPEOF(spec) != VECSXP) Rf_error("Test stream spec must be a list.");
    SEXP rows = list_field(spec, "rows");
    if (TYPEOF(rows) != VECSXP) Rf_error("Test stream spec: rows must be a list of raw vectors.");
    const R_xlen_t pool = XLENGTH(rows);
    if (pool > kMaxPool) Rf_error("Test stream spec: too many rows.");
    raw.n_rows = pool;
    raw.row_data = reinterpret_cast<const unsigned char**>(R_alloc(static_cast<std::size_t>(pool) + 1, sizeof(void*)));
    raw.row_size = reinterpret_cast<R_xlen_t*>(R_alloc(static_cast<std::size_t>(pool) + 1, sizeof(R_xlen_t)));
    for (R_xlen_t i = 0; i < pool; ++i) {
        SEXP row = VECTOR_ELT(rows, i);
        if (TYPEOF(row) != RAWSXP) Rf_error("Test stream spec: every row must be a raw vector.");
        raw.row_size[i] = XLENGTH(row);
        raw.row_data[i] = XLENGTH(row) > 0 ? RAW(row) : nullptr;  // materialise now; never point into an empty vector
    }
    SEXP large = list_field(spec, "large");
    if (large != R_NilValue) {
        if (TYPEOF(large) != LGLSXP || XLENGTH(large) != 1 || LOGICAL(large)[0] == NA_LOGICAL)
            Rf_error("Test stream spec: large must be TRUE or FALSE.");
        raw.large = LOGICAL(large)[0] != 0;
    }
    raw.top_format = optional_string(spec, "top_format");
    raw.child_format = optional_string(spec, "child_format");
    raw.child_name = optional_string(spec, "child_name");
    raw.nulls_parent = optional_index_vector(spec, "nulls_parent", pool, raw.n_nulls_parent);
    raw.nulls_child = optional_index_vector(spec, "nulls_child", pool, raw.n_nulls_child);

    SEXP plan = list_field(spec, "plan");
    R_xlen_t n_plan = 1;  // the default plan is one batch over the whole pool
    if (plan != R_NilValue) {
        SEXP dim = Rf_getAttrib(plan, R_DimSymbol);
        if (TYPEOF(plan) != REALSXP || TYPEOF(dim) != INTSXP || XLENGTH(dim) != 2 || INTEGER(dim)[1] != 5)
            Rf_error("Test stream spec: plan must be a double matrix with columns first, count, parent_offset, child_offset, tail.");
        const R_xlen_t n = INTEGER(dim)[0];
        if (n > kMaxBatches) Rf_error("Test stream spec: too many batches.");
        const double* p = REAL(plan);
        double total = 0;  // checked accumulation of requested rows
        for (R_xlen_t i = 0; i < n; ++i) {
            const double first = whole_in_range(p[i], 0, static_cast<double>(pool), "plan first");
            const double count = whole_in_range(p[i + n], 0, static_cast<double>(pool), "plan count");
            const double po = whole_in_range(p[i + 2 * n], 0, kMaxSlice, "plan parent_offset");
            const double co = whole_in_range(p[i + 3 * n], 0, kMaxSlice, "plan child_offset");
            const double tail = whole_in_range(p[i + 4 * n], 0, kMaxSlice, "plan tail");
            if (first + count > static_cast<double>(pool))
                Rf_error("Test stream spec: plan requests more rows than were supplied.");
            if (po + co + count + tail > kMaxPhysical)
                Rf_error("Test stream spec: a plan batch materialises too many entries.");
            total += count;
            if (total > kMaxTotalRows) Rf_error("Test stream spec: plan accumulates too many rows.");
        }
        raw.plan = p;
        raw.n_plan = n;
        n_plan = n;
    }

    SEXP numeric = list_field(spec, "numeric");
    if (numeric != R_NilValue) {
        SEXP names = Rf_getAttrib(numeric, R_NamesSymbol);
        if (TYPEOF(numeric) != REALSXP || TYPEOF(names) != STRSXP || XLENGTH(names) != XLENGTH(numeric))
            Rf_error("Test stream spec: numeric must be a named double vector.");
        for (R_xlen_t i = 0; i < XLENGTH(numeric); ++i) {
            int which = -1;
            for (int k = 0; k < NUMERIC_COUNT; ++k)
                if (std::strcmp(CHAR(STRING_ELT(names, i)), kNumeric[k]) == 0) which = k;
            if (which < 0) Rf_error("Test stream spec: unknown numeric control '%s'.", CHAR(STRING_ELT(names, i)));
            if (raw.numeric_set[which]) Rf_error("Test stream spec: duplicate numeric control '%s'.", kNumeric[which]);
            raw.numeric[which] = static_cast<std::int64_t>(
                whole_in_range(REAL(numeric)[i], kNumericBounds[which].lo, kNumericBounds[which].hi, kNumeric[which]));
            raw.numeric_set[which] = true;
        }
    }
    // Batch and row controls are validated against the supplied plan and pool.
    if (raw.numeric_set[FAIL_NEXT_AT] && raw.numeric[FAIL_NEXT_AT] > n_plan)
        Rf_error("Test stream spec: fail_next_at exceeds the number of planned batches.");
    if (raw.numeric_set[OVERRIDE_BATCH] && raw.numeric[OVERRIDE_BATCH] > n_plan)
        Rf_error("Test stream spec: override_batch exceeds the number of planned batches.");
    if (raw.numeric_set[OFFSET_CORRUPT_ROW] && raw.numeric[OFFSET_CORRUPT_ROW] > pool)
        Rf_error("Test stream spec: offset_corrupt_row exceeds the number of pool rows.");

    SEXP flags = list_field(spec, "flags");
    if (flags != R_NilValue) {
        SEXP names = Rf_getAttrib(flags, R_NamesSymbol);
        if (TYPEOF(flags) != LGLSXP || TYPEOF(names) != STRSXP || XLENGTH(names) != XLENGTH(flags))
            Rf_error("Test stream spec: flags must be a named logical vector.");
        for (R_xlen_t i = 0; i < XLENGTH(flags); ++i) {
            int which = -1;
            for (int k = 0; k < FLAG_COUNT; ++k)
                if (std::strcmp(CHAR(STRING_ELT(names, i)), kFlags[k]) == 0) which = k;
            if (which < 0) Rf_error("Test stream spec: unknown flag '%s'.", CHAR(STRING_ELT(names, i)));
            if (LOGICAL(flags)[i] == NA_LOGICAL) Rf_error("Test stream spec: flags must not be NA.");
            raw.flag[which] = LOGICAL(flags)[i] != 0;
        }
    }
    // LARGE_BINARY-only malformed offsets must not be requested for ordinary BINARY.
    if (!raw.large && raw.numeric_set[OFFSET_CORRUPT_MODE] &&
        (raw.numeric[OFFSET_CORRUPT_MODE] == 3 || raw.numeric[OFFSET_CORRUPT_MODE] == 4))
        Rf_error("Test stream spec: offset_corrupt_mode 3 and 4 require large = TRUE.");
}

// Native, self-owned copy of the specification. Everything a stream callback needs later is
// stored here by value: no borrowed CHAR()/RAW()/REAL()/INTEGER() memory, no SEXP.
struct Spec {
    std::vector<std::vector<unsigned char>> pool;
    std::vector<Batch> plan;
    std::vector<char> null_parent, null_child;
    std::string top_format_owned, child_format_owned, child_name_owned;
    bool large = false;
    bool numeric_set[NUMERIC_COUNT] = {};
    std::int64_t numeric[NUMERIC_COUNT] = {};
    bool flag[FLAG_COUNT] = {};

    bool has(Numeric n) const { return numeric_set[n]; }
    std::int64_t get(Numeric n, std::int64_t fallback) const { return numeric_set[n] ? numeric[n] : fallback; }
};

struct StreamState {
    Spec spec;
    std::size_t next = 0;
    char* diagnostic = nullptr;  // owned; freed (and scribbled over) by release
};

void set_diagnostic(StreamState* state, const char* message)
{
    std::free(state->diagnostic);
    state->diagnostic = static_cast<char*>(std::malloc(std::strlen(message) + 1));
    if (state->diagnostic) std::memcpy(state->diagnostic, message, std::strlen(message) + 1);
}

// ---- schema construction --------------------------------------------------------------------

void build_schema(const Spec& sp, ArrowSchema* out)
{
    struct Guard {
        ArrowSchema* schema;
        bool committed = false;
        ~Guard() { if (!committed && schema->release) schema->release(schema); }
    } guard{out};
    init_schema(out, "", sp.top_format_owned.c_str());
    const std::int64_t kids = sp.get(TOP_N_CHILDREN, 1);
    for (std::int64_t i = 0; i < kids; ++i) {
        if (i == 0 && sp.flag[NULL_CHILD_SCHEMA]) {
            node_of(out)->kids.push_back(nullptr);
            out->children = node_of(out)->kids.data();
            out->n_children = static_cast<std::int64_t>(node_of(out)->kids.size());
            continue;
        }
        SchemaHolder holder;
        init_schema(holder.s, i == 0 ? sp.child_name_owned.c_str() : "extra",
                    i == 0 ? sp.child_format_owned.c_str() : "z");
        if (i == 0) {
            ArrowSchema* child = holder.s;
            if (sp.flag[CHILD_DICTIONARY_SCHEMA]) {
                SchemaHolder dict;
                init_schema(dict.s, "dictionary", "z");
                node_of(child)->dict = dict.take();
                child->dictionary = node_of(child)->dict;
            }
            for (std::int64_t c = 0; c < sp.get(CHILD_N_CHILDREN_SCHEMA, 0); ++c) {
                SchemaHolder sub;
                init_schema(sub.s, "sub", "z");
                add_kid(child, sub);
            }
            if (sp.flag[UNUSED_CHILDREN_SCHEMA] && child->n_children == 0)
                child->children = &node_of(child)->unused_slot;  // legal: n_children == 0
            if (sp.flag[RELEASED_CHILD_SCHEMA]) child->release(child);  // genuinely released once
        }
        add_kid(out, holder);
    }
    if (sp.flag[TOP_DICTIONARY]) {
        SchemaHolder dict;
        init_schema(dict.s, "dictionary", "z");
        node_of(out)->dict = dict.take();
        out->dictionary = node_of(out)->dict;
    }
    if (sp.flag[RELEASED_TOP_SCHEMA]) out->release(out);
    guard.committed = true;
}

// ---- array construction ---------------------------------------------------------------------

bool applies(const Spec& sp, std::size_t batch)
{
    const std::int64_t only = sp.get(OVERRIDE_BATCH, 0);
    return only == 0 || only == static_cast<std::int64_t>(batch) + 1;
}

// Build one record batch. Returns an empty string on success, otherwise a diagnostic.
std::string build_batch(const Spec& sp, std::size_t index, ArrowArray* out)
{
    struct Guard {
        ArrowArray* array;
        bool committed = false;
        ~Guard() { if (!committed && array->release) array->release(array); }
    } guard{out};
    const Batch& b = sp.plan[index];
    const bool over = applies(sp, index);
    const std::int64_t child_length = b.parent_offset + b.count + b.tail;
    const std::int64_t physical = b.child_offset + child_length;
    const auto pool_size = static_cast<std::int64_t>(sp.pool.size());

    // Pool row backing the child's physical position j (or -1 when outside the pool).
    auto pool_of_child = [&](std::int64_t j) -> std::int64_t {
        const std::int64_t pi = b.first - b.child_offset - b.parent_offset + j;
        return pi >= 0 && pi < pool_size ? pi : -1;
    };

    init_array(out);
    ArrayNode* parent = node_of(out);
    ArrayHolder child_holder;
    init_array(child_holder.a);
    ArrowArray* child = child_holder.a;
    ArrayNode* cn = node_of(child);

    // Child offsets and data.
    std::vector<std::int64_t> offsets(static_cast<std::size_t>(physical) + 1, 0);
    for (std::int64_t j = 0; j < physical; ++j) {
        const std::int64_t pi = pool_of_child(j);
        const std::size_t n = pi >= 0 ? sp.pool[static_cast<std::size_t>(pi)].size() : 0;
        if (pi >= 0 && n) {
            const auto& value = sp.pool[static_cast<std::size_t>(pi)];
            cn->data.insert(cn->data.end(), value.begin(), value.end());
        }
        offsets[static_cast<std::size_t>(j) + 1] = static_cast<std::int64_t>(cn->data.size());
    }
    if (!sp.large && static_cast<std::uint64_t>(cn->data.size()) > static_cast<std::uint64_t>(INT32_MAX))
        return "synthetic producer: BINARY data exceeds INT32_MAX";
    // Optional offset corruption at one pool row (only when that row is in this batch's selection).
    const std::int64_t mode = over ? sp.get(OFFSET_CORRUPT_MODE, 0) : 0;
    if (mode) {
        const std::int64_t j = sp.get(OFFSET_CORRUPT_ROW, 1) - 1 - b.first + b.child_offset + b.parent_offset;
        if (j >= b.child_offset + b.parent_offset && j < b.child_offset + b.parent_offset + b.count) {
            const auto k = static_cast<std::size_t>(j);
            if (mode == 1) offsets[k + 1] = offsets[k] - 1;           // decreasing
            else if (mode == 2) offsets[k] = -1;                      // negative start
            else if (mode == 3) offsets[k + 1] = INT64_C(1) << 62;    // huge end (LARGE_BINARY)
            else if (mode == 4) { offsets[k] = INT64_C(1) << 62; offsets[k + 1] = (INT64_C(1) << 62) + 41; }
        }
    }
    const std::size_t width = sp.large ? 8 : 4;
    cn->offsets.resize(offsets.size() * width);
    for (std::size_t i = 0; i < offsets.size(); ++i) {
        if (sp.large) {
            std::memcpy(cn->offsets.data() + i * 8, &offsets[i], 8);
        } else {
            const auto v = static_cast<std::int32_t>(offsets[i]);
            std::memcpy(cn->offsets.data() + i * 4, &v, 4);
        }
    }

    // Child validity.
    std::int64_t child_nulls = 0;
    bool child_needs_bitmap = sp.flag[FORCE_CHILD_BITMAP];
    for (std::int64_t j = 0; j < physical; ++j) {
        const std::int64_t pi = pool_of_child(j);
        if (pi >= 0 && sp.null_child[static_cast<std::size_t>(pi)]) {
            child_needs_bitmap = true;
            if (j >= b.child_offset) ++child_nulls;
        }
    }
    if (child_needs_bitmap) {
        cn->validity.assign((static_cast<std::size_t>(physical) + 7) / 8, 0);
        for (std::int64_t j = 0; j < physical; ++j) {
            const std::int64_t pi = pool_of_child(j);
            if (!(pi >= 0 && sp.null_child[static_cast<std::size_t>(pi)]))
                cn->validity[static_cast<std::size_t>(j) >> 3] |= static_cast<unsigned char>(1u << (j & 7));
        }
    }
    const bool child_empty = physical == 0;
    const bool child_bitmap = child_needs_bitmap && !sp.flag[DROP_BITMAPS] && !child_empty;
    cn->buffers.assign(static_cast<std::size_t>(std::max<std::int64_t>(3, over ? sp.get(CHILD_N_BUFFERS, 3) : 3)), nullptr);
    if (child_bitmap) cn->buffers[0] = cn->validity.data();
    if (!child_empty && !(over && sp.flag[NULL_OFFSETS])) cn->buffers[1] = cn->offsets.data();
    if (!cn->data.empty() && !(over && sp.flag[NULL_DATA])) cn->buffers[2] = cn->data.data();
    child->length = over ? sp.get(CHILD_LENGTH, child_length) : child_length;
    child->offset = over ? sp.get(CHILD_OFFSET, b.child_offset) : b.child_offset;
    child->null_count = over ? sp.get(CHILD_NULL_COUNT, child_nulls) : child_nulls;
    child->n_buffers = over ? sp.get(CHILD_N_BUFFERS, 3) : 3;
    child->buffers = cn->buffers.data();
    if (over && sp.flag[NULL_CHILD_BUFFERS]) child->buffers = nullptr;
    child->n_children = 0;
    if (over && sp.get(CHILD_N_CHILDREN, 0) > 0) {
        cn->kids.assign(static_cast<std::size_t>(std::min<std::int64_t>(sp.get(CHILD_N_CHILDREN, 0), 8)), nullptr);
        child->children = cn->kids.data();
        child->n_children = sp.get(CHILD_N_CHILDREN, 0);
    } else if (over && sp.flag[UNUSED_CHILDREN_ARRAY]) {
        child->children = &cn->unused_slot;  // legal: n_children == 0, non-NULL children pointer
    }
    if (over && sp.flag[CHILD_DICTIONARY]) {
        ArrayHolder dict;
        init_array(dict.a);
        cn->dict = dict.take();
        child->dictionary = cn->dict;
    }

    // Parent validity and fields.
    bool parent_needs_bitmap = sp.flag[FORCE_PARENT_BITMAP];
    std::int64_t parent_nulls = 0;
    const std::int64_t parent_bits = b.parent_offset + b.count;
    auto pool_of_parent = [&](std::int64_t q) -> std::int64_t {
        const std::int64_t pi = b.first - b.parent_offset + q;
        return pi >= 0 && pi < pool_size ? pi : -1;
    };
    for (std::int64_t q = 0; q < parent_bits; ++q) {
        const std::int64_t pi = pool_of_parent(q);
        if (pi >= 0 && sp.null_parent[static_cast<std::size_t>(pi)]) {
            parent_needs_bitmap = true;
            if (q >= b.parent_offset) ++parent_nulls;
        }
    }
    if (parent_needs_bitmap) {
        parent->validity.assign((static_cast<std::size_t>(parent_bits) + 7) / 8, 0);
        for (std::int64_t q = 0; q < parent_bits; ++q) {
            const std::int64_t pi = pool_of_parent(q);
            if (!(pi >= 0 && sp.null_parent[static_cast<std::size_t>(pi)]))
                parent->validity[static_cast<std::size_t>(q) >> 3] |= static_cast<unsigned char>(1u << (q & 7));
        }
    }
    const bool parent_bitmap = parent_needs_bitmap && !sp.flag[DROP_BITMAPS] && parent_bits > 0;
    parent->buffers.assign(static_cast<std::size_t>(std::max<std::int64_t>(1, over ? sp.get(PARENT_N_BUFFERS, 1) : 1)), nullptr);
    if (parent_bitmap) parent->buffers[0] = parent->validity.data();
    out->length = over ? sp.get(PARENT_LENGTH, b.count) : b.count;
    out->offset = over ? sp.get(PARENT_OFFSET, b.parent_offset) : b.parent_offset;
    out->null_count = over ? sp.get(PARENT_NULL_COUNT, parent_nulls) : parent_nulls;
    out->n_buffers = over ? sp.get(PARENT_N_BUFFERS, 1) : 1;
    out->buffers = parent->buffers.data();
    if (over && sp.flag[NULL_PARENT_BUFFERS]) out->buffers = nullptr;
    if (over && sp.flag[PARENT_DICTIONARY]) {
        ArrayHolder dict;
        init_array(dict.a);
        parent->dict = dict.take();
        out->dictionary = parent->dict;
    }

    // Attach the child (the holder owns it until the insertion succeeds).
    if (over && sp.flag[RELEASED_CHILD_ARRAY]) child->release(child);  // genuinely released once
    parent->kids.push_back(over && sp.flag[NULL_CHILD] ? nullptr : child);
    if (over && sp.flag[NULL_CHILD]) {
        // The child is not attached: the holder releases it.
    } else {
        child_holder.take();
    }
    // More declared children than real ones: pad with NULL slots so reads stay inside the array.
    const std::int64_t declared = over ? sp.get(PARENT_N_CHILDREN, 1) : 1;
    for (std::int64_t i = static_cast<std::int64_t>(parent->kids.size()); i < std::min<std::int64_t>(declared, 8); ++i)
        parent->kids.push_back(nullptr);
    out->children = parent->kids.data();
    out->n_children = declared;
    guard.committed = true;
    return "";
}

// ---- stream callbacks -----------------------------------------------------------------------

StreamState* state_of(ArrowArrayStream* s) { return static_cast<StreamState*>(s->private_data); }

int stream_get_schema(ArrowArrayStream* s, ArrowSchema* out)
{
    auto* state = state_of(s);
    try {
        if (state->spec.has(FAIL_GET_SCHEMA)) {
            set_diagnostic(state, "synthetic get_schema failure");
            const auto code = static_cast<int>(state->spec.numeric[FAIL_GET_SCHEMA]);
            return code != 0 ? code : 5;
        }
        build_schema(state->spec, out);
        return 0;
    } catch (const std::exception& e) {
        set_diagnostic(state, e.what());
    } catch (...) {
        set_diagnostic(state, "unknown producer exception");
    }
    return ENOMEM;
}

int stream_get_next(ArrowArrayStream* s, ArrowArray* out)
{
    auto* state = state_of(s);
    try {
        std::memset(out, 0, sizeof *out);
        if (state->next >= state->spec.plan.size()) return 0;  // end of stream: released array
        const std::size_t index = state->next++;
        if (state->spec.has(FAIL_NEXT_AT) &&
            state->spec.numeric[FAIL_NEXT_AT] == static_cast<std::int64_t>(index) + 1) {
            set_diagnostic(state, "synthetic get_next failure");
            return 5;
        }
        const std::string problem = build_batch(state->spec, index, out);
        if (!problem.empty()) {
            set_diagnostic(state, problem.c_str());
            return EINVAL;
        }
        return 0;
    } catch (const std::exception& e) {
        std::memset(out, 0, sizeof *out);
        set_diagnostic(state, e.what());
    } catch (...) {
        std::memset(out, 0, sizeof *out);
        set_diagnostic(state, "unknown producer exception");
    }
    return ENOMEM;
}

const char* stream_get_last_error(ArrowArrayStream* s)
{
    auto* state = state_of(s);
    return state->spec.flag[NULL_LAST_ERROR] ? nullptr : state->diagnostic;
}

void stream_release(ArrowArrayStream* s)
{
    auto* state = state_of(s);
    ++c_stream_released;
    if (state->diagnostic) {
        std::memset(state->diagnostic, 'X', std::strlen(state->diagnostic));  // catches use-after-release
        std::free(state->diagnostic);
    }
    delete state;
    s->release = nullptr;
    s->private_data = nullptr;
}

// A stream with no release callback owns nothing: its stubs must never be reached.
int stub_get_schema(ArrowArrayStream*, ArrowSchema*) { return EINVAL; }
int stub_get_next(ArrowArrayStream*, ArrowArray*) { return EINVAL; }
const char* stub_get_last_error(ArrowArrayStream*) { return nullptr; }

void export_stream(ArrowArrayStream* stream, const RawSpec& raw, char* error, std::size_t error_size)
{
    try {
        if (raw.flag[MISSING_RELEASE]) {
            stream->get_schema = stub_get_schema;
            stream->get_next = stub_get_next;
            stream->get_last_error = stub_get_last_error;
            stream->release = nullptr;
            stream->private_data = nullptr;
            return;
        }
        std::unique_ptr<StreamState> state(new StreamState());
        Spec& sp = state->spec;
        // Deep copy from the staged (non-owning) data: no R API call from here on.
        const auto pool = static_cast<std::size_t>(raw.n_rows);
        sp.pool.resize(pool);
        for (std::size_t i = 0; i < pool; ++i)
            if (raw.row_size[i] > 0)  // never form a pointer range for an empty value
                sp.pool[i].assign(raw.row_data[i], raw.row_data[i] + raw.row_size[i]);
        sp.null_parent.assign(pool, 0);
        sp.null_child.assign(pool, 0);
        for (R_xlen_t i = 0; i < raw.n_nulls_parent; ++i)
            sp.null_parent[static_cast<std::size_t>(raw.nulls_parent[i] - 1)] = 1;
        for (R_xlen_t i = 0; i < raw.n_nulls_child; ++i)
            sp.null_child[static_cast<std::size_t>(raw.nulls_child[i] - 1)] = 1;
        if (!raw.plan) {
            sp.plan.push_back(Batch{0, static_cast<std::int64_t>(pool), 0, 0, 0});
        } else {
            const R_xlen_t n = raw.n_plan;
            const double* p = raw.plan;
            for (R_xlen_t i = 0; i < n; ++i)
                sp.plan.push_back(Batch{static_cast<std::int64_t>(p[i]), static_cast<std::int64_t>(p[i + n]),
                                        static_cast<std::int64_t>(p[i + 2 * n]),
                                        static_cast<std::int64_t>(p[i + 3 * n]),
                                        static_cast<std::int64_t>(p[i + 4 * n])});
        }
        // The state owns the effective strings used later by the callbacks.
        sp.large = raw.large;
        sp.top_format_owned = raw.top_format ? raw.top_format : "+s";
        sp.child_format_owned = raw.child_format ? raw.child_format : (raw.large ? "Z" : "z");
        sp.child_name_owned = raw.child_name ? raw.child_name : "geometry";
        std::memcpy(sp.numeric_set, raw.numeric_set, sizeof sp.numeric_set);
        std::memcpy(sp.numeric, raw.numeric, sizeof sp.numeric);
        std::memcpy(sp.flag, raw.flag, sizeof sp.flag);

        stream->get_schema = raw.flag[MISSING_GET_SCHEMA] ? nullptr : stream_get_schema;
        stream->get_next = raw.flag[MISSING_GET_NEXT] ? nullptr : stream_get_next;
        stream->get_last_error = raw.flag[MISSING_GET_LAST_ERROR] ? nullptr : stream_get_last_error;
        stream->release = stream_release;
        stream->private_data = state.release();
        ++c_stream_made;
    } catch (const std::exception& e) {
        std::snprintf(error, error_size, "Test stream export failed: %s", e.what());
    } catch (...) {
        std::snprintf(error, error_size, "Test stream export failed with an unknown native exception.");
    }
}
}  // namespace

// Fill an rPSTool-owned, not-yet-live stream with a synthetic producer.
extern "C" SEXP rpst_arrow_test_export(SEXP stream_pointer, SEXP spec)
{
    ArrowArrayStream* stream = rpst::arrow_stream_require(stream_pointer);
    if (stream->release) Rf_error("The Arrow stream is already live.");
    RawSpec raw;
    parse_spec(spec, raw);
    char error[512] = "";
    export_stream(stream, raw, error, sizeof error);
    if (error[0]) Rf_error("%s", error);
    return R_NilValue;
}

extern "C" SEXP rpst_arrow_test_counters()
{
    SEXP out = PROTECT(Rf_allocVector(REALSXP, 6));
    SEXP names = PROTECT(Rf_allocVector(STRSXP, 6));
    const char* labels[] = {"schemas_made", "schemas_released", "arrays_made", "arrays_released",
                            "streams_made", "streams_released"};
    const double values[] = {c_schema_made, c_schema_released, c_array_made, c_array_released,
                             c_stream_made, c_stream_released};
    for (int i = 0; i < 6; ++i) {
        REAL(out)[i] = values[i];
        SET_STRING_ELT(names, i, Rf_mkChar(labels[i]));
    }
    Rf_setAttrib(out, R_NamesSymbol, names);
    UNPROTECT(2);
    return out;
}
