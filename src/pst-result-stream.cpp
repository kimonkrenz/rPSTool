// rPSTool result owner and Arrow C Stream producer, plus the registered test harness (a synthetic result
// producer and a scripted Arrow consumer) that exercises the release protocol independently of any PST analysis.
// No PST algorithm lives here and the exporter never calls the R API (only the test .Call entry points do, and only
// outside any live C++ owner).
#define R_NO_REMAP
#include <Rinternals.h>
#include <algorithm>
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <exception>
#include <limits>
#include <new>
#include "pst-result-stream.h"

namespace rpst {
namespace {
std::atomic<unsigned long long> c_tables_made{0}, c_tables_freed{0}, c_streams_made{0}, c_streams_released{0},
    c_schemas_made{0}, c_schemas_released{0}, c_batches_made{0}, c_batches_released{0}, c_children_made{0},
    c_children_released{0};

constexpr int kEINVAL = 22, kENOMEM = 12;
// ARROW_FLAG_NULLABLE from the Arrow C Data Interface (the vendored header deliberately omits the flag constants).
constexpr std::int64_t kArrowFlagNullable = 2;

// ---- schema ---------------------------------------------------------------------------------
struct SchemaStrings {
    std::vector<std::string> names;
    std::vector<const char*> formats;
    std::vector<std::int64_t> flags;  // 0, or kArrowFlagNullable for a nullable column (the id column is never nullable)
    std::string metadata;  // Arrow C schema metadata encoding, empty = none
};
using SchemaStringsPtr = std::shared_ptr<const SchemaStrings>;

void put_i32(std::string& out, std::int32_t v) { out.append(reinterpret_cast<const char*>(&v), sizeof v); }

std::string encode_metadata(const std::vector<std::pair<std::string, std::string>>& metadata)
{
    if (metadata.empty()) return std::string();
    std::string out;
    put_i32(out, static_cast<std::int32_t>(metadata.size()));
    for (const auto& kv : metadata) {
        put_i32(out, static_cast<std::int32_t>(kv.first.size()));
        out += kv.first;
        put_i32(out, static_cast<std::int32_t>(kv.second.size()));
        out += kv.second;
    }
    return out;
}

void release_child_schema(ArrowSchema* schema)
{
    if (!schema->release) return;
    delete static_cast<SchemaStringsPtr*>(schema->private_data);
    schema->release = nullptr;
    ++c_children_released;
}

struct SchemaRoot {
    SchemaStringsPtr strings;
    std::vector<ArrowSchema> children;
    std::vector<ArrowSchema*> child_ptrs;
};

void release_root_schema(ArrowSchema* schema)
{
    if (!schema->release) return;
    auto* root = static_cast<SchemaRoot*>(schema->private_data);
    // Children a consumer has not moved away are released with the parent.
    for (auto& child : root->children)
        if (child.release) child.release(&child);
    delete root;
    schema->release = nullptr;
    ++c_schemas_released;
}

// ---- batches --------------------------------------------------------------------------------
struct BatchState {
    std::shared_ptr<const ResultTable> table;  // keeps the native arrays alive
    std::unique_ptr<std::int32_t[]> ids;       // the batch's one-based positional ids
};
using BatchStatePtr = std::shared_ptr<BatchState>;

struct ChildPriv {
    BatchStatePtr state;
    const void* buffers[2] = {nullptr, nullptr};
    std::vector<std::uint8_t> bitmap;  // this batch's validity bits (bit 0 = first row of the batch); empty if none are null
};

void release_child_array(ArrowArray* array)
{
    if (!array->release) return;
    delete static_cast<ChildPriv*>(array->private_data);
    array->release = nullptr;
    ++c_children_released;
}

struct RootPriv {
    BatchStatePtr state;
    std::vector<ArrowArray> children;
    std::vector<ArrowArray*> child_ptrs;
    const void* buffers[1] = {nullptr};
};

void release_root_array(ArrowArray* array)
{
    if (!array->release) return;
    auto* root = static_cast<RootPriv*>(array->private_data);
    for (auto& child : root->children)
        if (child.release) child.release(&child);
    delete root;
    array->release = nullptr;
    ++c_batches_released;
}

// ---- stream ---------------------------------------------------------------------------------
struct StreamPriv {
    std::shared_ptr<const ResultTable> table;
    std::size_t batch_rows = 0;
    std::size_t position = 0;
    long batch_index = 0;
    StreamFaults faults;
    std::string last_error;
};

SchemaStringsPtr schema_strings(const ResultTable& table)
{
    auto strings = std::make_shared<SchemaStrings>();
    strings->names.push_back(table.id_name);
    strings->formats.push_back("i");
    strings->flags.push_back(0);
    for (const auto& column : table.columns) {
        strings->names.push_back(column.name);
        strings->formats.push_back(column.kind == ResultKind::Float32 ? "f" : "i");  // Int32 and SignedInt32 are both "i"
        strings->flags.push_back(column.nullable ? kArrowFlagNullable : 0);
    }
    strings->metadata = encode_metadata(table.metadata);
    return strings;
}

int stream_get_schema(ArrowArrayStream* stream, ArrowSchema* out)
{
    auto* priv = static_cast<StreamPriv*>(stream->private_data);
    std::memset(out, 0, sizeof *out);
    if (!priv) return kEINVAL;
    if (priv->faults.schema_error) {
        priv->last_error = "injected get_schema failure";
        return priv->faults.schema_error;
    }
    SchemaRoot* root = nullptr;
    try {
        auto strings = schema_strings(*priv->table);
        root = new SchemaRoot{strings, {}, {}};
        const std::size_t n = strings->names.size();
        root->children.resize(n);
        root->child_ptrs.resize(n);
        for (std::size_t i = 0; i < n; ++i) {
            std::memset(&root->children[i], 0, sizeof(ArrowSchema));
            root->children[i].format = strings->formats[i];
            root->children[i].name = strings->names[i].c_str();
            root->children[i].flags = strings->flags[i];  // nullable only for columns that can hold unwritten (null) values
            root->children[i].private_data = new SchemaStringsPtr(strings);
            root->children[i].release = release_child_schema;
            root->child_ptrs[i] = &root->children[i];
            ++c_children_made;
        }
        out->format = "+s";
        out->name = "";
        out->metadata = strings->metadata.empty() ? nullptr : strings->metadata.data();
        out->flags = 0;
        out->n_children = static_cast<std::int64_t>(n);
        out->children = root->child_ptrs.data();
        out->private_data = root;
        out->release = release_root_schema;
        ++c_schemas_made;
        return 0;
    } catch (const std::bad_alloc&) {
        priv->last_error = "out of memory while building the Arrow schema";
    } catch (...) {
        priv->last_error = "unexpected failure while building the Arrow schema";
    }
    if (root) {  // children created so far
        for (auto& child : root->children)
            if (child.release) child.release(&child);
        delete root;
    }
    std::memset(out, 0, sizeof *out);
    return kENOMEM;
}

int stream_get_next(ArrowArrayStream* stream, ArrowArray* out)
{
    auto* priv = static_cast<StreamPriv*>(stream->private_data);
    std::memset(out, 0, sizeof *out);  // release == NULL: end of stream unless a batch is built below
    if (!priv) return kEINVAL;
    const ResultTable& table = *priv->table;
    if (priv->position >= table.rows) return 0;
    const long index = priv->batch_index;
    if (priv->faults.fail_at_batch == index) {
        priv->last_error = "injected get_next failure";
        return priv->faults.batch_error ? priv->faults.batch_error : kEINVAL;
    }
    RootPriv* root = nullptr;
    try {
        if (priv->faults.oom_at_batch == index) throw std::bad_alloc();
        const std::size_t offset = priv->position;
        const std::size_t length = std::min(priv->batch_rows, table.rows - offset);
        auto state = std::make_shared<BatchState>();
        state->table = priv->table;
        state->ids.reset(new std::int32_t[length]);
        for (std::size_t i = 0; i < length; ++i) state->ids[i] = static_cast<std::int32_t>(offset + i + 1);
        root = new RootPriv();
        root->state = state;
        const std::size_t n = table.columns.size() + 1;
        root->children.resize(n);
        root->child_ptrs.resize(n);
        for (std::size_t j = 0; j < n; ++j) {
            std::memset(&root->children[j], 0, sizeof(ArrowArray));
            root->child_ptrs[j] = &root->children[j];
        }
        for (std::size_t j = 0; j < n; ++j) {
            std::unique_ptr<ChildPriv> cp(new ChildPriv());  // owned until child.private_data takes it (no leak on a throw)
            cp->state = state;
            std::int64_t null_count = 0;
            if (j == 0) {
                cp->buffers[1] = state->ids.get();
            } else {
                const ResultColumn& column = table.columns[j - 1];
                cp->buffers[1] = column.kind == ResultKind::Float32
                                     ? static_cast<const void*>(column.f32.data() + offset)
                                     : column.kind == ResultKind::SignedInt32
                                           ? static_cast<const void*>(column.i32.data() + offset)
                                           : static_cast<const void*>(column.u32.data() + offset);
                if (column.nullable) {
                    // The batch's own bitmap, rebuilt from the full-column bits so that array.offset stays 0 and every
                    // batch start (byte-aligned or not) is handled identically. Exact null count from the same bits.
                    if (priv->faults.oom_validity_at_batch == index) throw std::bad_alloc();
                    cp->bitmap.assign((length + 7) / 8, 0);
                    for (std::size_t i = 0; i < length; ++i) {
                        const std::size_t row = offset + i;
                        if ((column.validity[row >> 3] >> (row & 7)) & 1u) cp->bitmap[i >> 3] |= static_cast<std::uint8_t>(1u << (i & 7));
                        else ++null_count;
                    }
                    if (null_count) cp->buffers[0] = cp->bitmap.data();  // no nulls: the bitmap may be absent (null_count == 0)
                }
            }
            ArrowArray& child = root->children[j];
            child.length = static_cast<std::int64_t>(length);
            child.null_count = null_count;
            child.offset = 0;
            child.n_buffers = 2;
            child.n_children = 0;
            child.buffers = cp->buffers;
            child.private_data = cp.release();
            child.release = release_child_array;
            ++c_children_made;
        }
        out->length = static_cast<std::int64_t>(length);
        out->null_count = 0;
        out->offset = 0;
        out->n_buffers = 1;
        out->n_children = static_cast<std::int64_t>(n);
        out->buffers = root->buffers;
        out->children = root->child_ptrs.data();
        out->private_data = root;
        out->release = release_root_array;
        ++c_batches_made;
        priv->position += length;
        ++priv->batch_index;
        return 0;
    } catch (const std::bad_alloc&) {
        priv->last_error = "out of memory while building an Arrow batch";
    } catch (...) {
        priv->last_error = "unexpected failure while building an Arrow batch";
    }
    if (root) {
        for (auto& child : root->children)
            if (child.release) child.release(&child);
        delete root;
    }
    std::memset(out, 0, sizeof *out);
    return kENOMEM;
}

const char* stream_get_last_error(ArrowArrayStream* stream)
{
    auto* priv = static_cast<StreamPriv*>(stream->private_data);
    return priv && !priv->last_error.empty() ? priv->last_error.c_str() : nullptr;
}

void stream_release(ArrowArrayStream* stream)
{
    if (!stream->release) return;
    delete static_cast<StreamPriv*>(stream->private_data);
    stream->private_data = nullptr;
    stream->release = nullptr;
    ++c_streams_released;
}
}  // namespace

ResultTable::ResultTable() { ++c_tables_made; }
ResultTable::~ResultTable() { ++c_tables_freed; }

ResultCounters result_counters()
{
    return {c_tables_made, c_tables_freed, c_streams_made, c_streams_released, c_schemas_made, c_schemas_released,
            c_batches_made, c_batches_released, c_children_made, c_children_released};
}

bool export_result_stream(ArrowArrayStream* out, std::shared_ptr<const ResultTable> table, std::size_t batch_rows,
                          const StreamFaults& faults, char* error, std::size_t error_size)
{
    error[0] = '\0';
    try {
        if (!table) { std::snprintf(error, error_size, "No result table to export."); return false; }
        if (out->release) { std::snprintf(error, error_size, "The Arrow stream is already live."); return false; }
        if (batch_rows < 1) { std::snprintf(error, error_size, "The Arrow batch size must be at least one row."); return false; }
        const std::size_t max_rows = static_cast<std::size_t>(std::numeric_limits<std::int32_t>::max());
        if (table->rows > max_rows) {
            std::snprintf(error, error_size, "Too many result rows for an Arrow int32 identifier column.");
            return false;
        }
        if (table->id_name.empty()) { std::snprintf(error, error_size, "The result identifier column needs a name."); return false; }
        std::vector<std::string> seen{table->id_name};
        for (const auto& column : table->columns) {
            if (column.name.empty()) { std::snprintf(error, error_size, "Result column names must be non-empty."); return false; }
            for (const auto& previous : seen)
                if (previous == column.name) { std::snprintf(error, error_size, "Duplicate result column name '%s'.", column.name.c_str()); return false; }
            seen.push_back(column.name);
            const std::size_t length = column.kind == ResultKind::Float32 ? column.f32.size()
                                     : column.kind == ResultKind::SignedInt32 ? column.i32.size() : column.u32.size();
            if (length != table->rows) {
                std::snprintf(error, error_size, "Result column '%s' has %zu values for %zu rows.", column.name.c_str(), length, table->rows);
                return false;
            }
            if (column.nullable ? column.validity.size() != (table->rows + 7) / 8 : !column.validity.empty()) {
                std::snprintf(error, error_size, "Result column '%s' has a validity mask inconsistent with its row count.", column.name.c_str());
                return false;
            }
            if (column.kind == ResultKind::Int32) {
                // Native unsigned values are never reinterpreted: anything above INT32_MAX is rejected. Rows marked
                // null (unwritten native slots, e.g. a UINT_MAX sentinel) are not values and are skipped.
                for (std::size_t i = 0; i < column.u32.size(); ++i)
                    if (column.u32[i] > static_cast<unsigned int>(std::numeric_limits<std::int32_t>::max()) &&
                        (!column.nullable || ((column.validity[i >> 3] >> (i & 7)) & 1u))) {
                        std::snprintf(error, error_size, "Result column '%s' holds a value above the Arrow int32 range.", column.name.c_str());
                        return false;
                    }
            }
        }
        for (const auto& kv : table->metadata)
            if (kv.first.empty()) { std::snprintf(error, error_size, "Result metadata keys must be non-empty."); return false; }
        auto* priv = new StreamPriv();
        priv->table = std::move(table);
        priv->batch_rows = batch_rows;
        priv->faults = faults;
        out->get_schema = stream_get_schema;
        out->get_next = stream_get_next;
        out->get_last_error = stream_get_last_error;
        out->release = stream_release;
        out->private_data = priv;
        ++c_streams_made;
        return true;
    } catch (const std::bad_alloc&) {
        std::snprintf(error, error_size, "Out of memory while preparing the Arrow result stream.");
    } catch (const std::exception& e) {
        std::snprintf(error, error_size, "Preparing the Arrow result stream failed: %s", e.what());
    } catch (...) {
        std::snprintf(error, error_size, "Preparing the Arrow result stream failed with an unknown exception.");
    }
    return false;
}
}  // namespace rpst

// =============================================================================================
// Registered test harness. Not a user API: a synthetic result producer and a scripted Arrow consumer, so the
// ownership and release protocol is tested independently of PST. Argument validation precedes every C++ owner and
// R errors are raised only after owners have unwound.
// =============================================================================================
#include "pst-arrow-owner.h"

namespace {
bool names_ok(SEXP x, R_xlen_t n)
{
    if (TYPEOF(x) != STRSXP || XLENGTH(x) != n) return false;
    for (R_xlen_t i = 0; i < n; ++i)
        if (STRING_ELT(x, i) == NA_STRING) return false;
    return true;
}
}  // namespace

// Build a synthetic table from R data and export it into an rPSTool-owned, not-yet-live stream.
//   columns: list; kind 0 = float32 supplied as a raw vector of 4*rows bytes (any bit pattern), kind 1 = integer vector
//   faults: integer(4 or 5) = schema_error, fail_at_batch, batch_error, oom_at_batch [, oom_validity_at_batch] (-1 disables a batch fault)
//   columns may carry attr(, "valid"): a logical vector of length rows (no NA); its presence makes the column nullable
extern "C" SEXP rpst_result_test_export(SEXP stream_pointer, SEXP id_name, SEXP names, SEXP kinds, SEXP columns,
                                        SEXP metadata_names, SEXP metadata_values, SEXP rows_, SEXP batch_rows_,
                                        SEXP faults_)
{
    ArrowArrayStream* stream = rpst::arrow_stream_require(stream_pointer);
    if (TYPEOF(names) != STRSXP) Rf_error("Malformed synthetic result specification.");
    const R_xlen_t ncol = XLENGTH(names);
    if (!names_ok(id_name, 1) || !names_ok(names, ncol) || TYPEOF(kinds) != INTSXP ||
        XLENGTH(kinds) != ncol || TYPEOF(columns) != VECSXP || XLENGTH(columns) != ncol ||
        TYPEOF(rows_) != REALSXP || XLENGTH(rows_) != 1 || TYPEOF(batch_rows_) != REALSXP ||
        XLENGTH(batch_rows_) != 1 || TYPEOF(faults_) != INTSXP || (XLENGTH(faults_) != 4 && XLENGTH(faults_) != 5) ||
        TYPEOF(metadata_names) != STRSXP || TYPEOF(metadata_values) != STRSXP ||
        XLENGTH(metadata_names) != XLENGTH(metadata_values))
        Rf_error("Malformed synthetic result specification.");
    if (!(REAL(rows_)[0] >= 0) || REAL(rows_)[0] > 4294967295.0 || !(REAL(batch_rows_)[0] >= 1))
        Rf_error("Malformed synthetic result sizes.");
    const std::size_t rows = static_cast<std::size_t>(REAL(rows_)[0]);
    SEXP* valids = reinterpret_cast<SEXP*>(R_alloc(static_cast<size_t>(ncol) + 1, sizeof(SEXP)));
    for (R_xlen_t j = 0; j < ncol; ++j) {
        SEXP column = VECTOR_ELT(columns, j);
        if (INTEGER(kinds)[j] == 0) {
            if (TYPEOF(column) != RAWSXP || static_cast<std::size_t>(XLENGTH(column)) != rows * 4)
                Rf_error("A float32 synthetic column must be a raw vector of 4 * rows bytes.");
        } else if (INTEGER(kinds)[j] == 1 || INTEGER(kinds)[j] == 2) {
            if (TYPEOF(column) != INTSXP || static_cast<std::size_t>(XLENGTH(column)) != rows)
                Rf_error("An int32 synthetic column must be an integer vector of length rows.");
        } else {
            Rf_error("Unknown synthetic column kind.");
        }
        // Optional validity: attr(column, "valid") is a logical vector of length rows without NA; its presence makes the
        // column nullable (all TRUE = nullable but no nulls).
        SEXP valid = Rf_getAttrib(column, Rf_install("valid"));
        valids[j] = valid;  // kept alive by `columns`; read later without any R call that could allocate
        if (valid != R_NilValue) {
            if (TYPEOF(valid) != LGLSXP || static_cast<std::size_t>(XLENGTH(valid)) != rows)
                Rf_error("A synthetic validity mask must be a logical vector of length rows.");
            for (std::size_t i = 0; i < rows; ++i)
                if (LOGICAL(valid)[i] == NA_LOGICAL) Rf_error("A synthetic validity mask must not contain NA.");
        }
    }
    // Every string conversion that can raise an R error (Rf_translateCharUTF8 may signal on an untranslatable
    // string) happens here, before any C++ owner exists. The pointers are R_alloc'd (reclaimed by R on return) and
    // the translated text is copied into the table only inside the scope below.
    const char* id_utf8 = Rf_translateCharUTF8(STRING_ELT(id_name, 0));
    const char** name_utf8 = reinterpret_cast<const char**>(R_alloc(static_cast<size_t>(ncol) + 1, sizeof(const char*)));
    for (R_xlen_t j = 0; j < ncol; ++j) name_utf8[j] = Rf_translateCharUTF8(STRING_ELT(names, j));
    const R_xlen_t nmeta = XLENGTH(metadata_names);
    const char** meta_key_utf8 = reinterpret_cast<const char**>(R_alloc(static_cast<size_t>(nmeta) + 1, sizeof(const char*)));
    const char** meta_value_utf8 = reinterpret_cast<const char**>(R_alloc(static_cast<size_t>(nmeta) + 1, sizeof(const char*)));
    for (R_xlen_t i = 0; i < nmeta; ++i) {
        meta_key_utf8[i] = Rf_translateCharUTF8(STRING_ELT(metadata_names, i));
        meta_value_utf8[i] = Rf_translateCharUTF8(STRING_ELT(metadata_values, i));
    }
    char error[512] = "";
    {
        auto table = std::make_shared<rpst::ResultTable>();
        try {
            table->id_name = id_utf8;
            table->rows = rows;
            for (R_xlen_t j = 0; j < ncol; ++j) {
                rpst::ResultColumn column;
                column.name = name_utf8[j];
                SEXP data = VECTOR_ELT(columns, j);
                if (INTEGER(kinds)[j] == 0) {
                    column.kind = rpst::ResultKind::Float32;
                    column.f32.resize(rows);
                    if (rows) std::memcpy(column.f32.data(), RAW(data), rows * 4);
                } else if (INTEGER(kinds)[j] == 2) {
                    column.kind = rpst::ResultKind::SignedInt32;
                    column.i32.assign(INTEGER(data), INTEGER(data) + rows);
                } else {
                    column.kind = rpst::ResultKind::Int32;
                    column.u32.resize(rows);
                    for (std::size_t i = 0; i < rows; ++i) column.u32[i] = static_cast<unsigned int>(INTEGER(data)[i]);
                }
                SEXP valid = valids[j];
                if (valid != R_NilValue) {
                    column.nullable = true;
                    column.validity.assign((rows + 7) / 8, 0);
                    for (std::size_t i = 0; i < rows; ++i)
                        if (LOGICAL(valid)[i]) column.validity[i >> 3] |= static_cast<std::uint8_t>(1u << (i & 7));
                }
                table->columns.push_back(std::move(column));
            }
            for (R_xlen_t i = 0; i < nmeta; ++i)
                table->metadata.emplace_back(meta_key_utf8[i], meta_value_utf8[i]);
            rpst::StreamFaults faults;
            faults.schema_error = INTEGER(faults_)[0];
            faults.fail_at_batch = INTEGER(faults_)[1];
            faults.batch_error = INTEGER(faults_)[2];
            faults.oom_at_batch = INTEGER(faults_)[3];
            if (XLENGTH(faults_) == 5) faults.oom_validity_at_batch = INTEGER(faults_)[4];
            rpst::export_result_stream(stream, table, static_cast<std::size_t>(REAL(batch_rows_)[0]), faults, error, sizeof error);
        } catch (const std::exception& e) {
            std::snprintf(error, sizeof error, "Synthetic result construction failed: %s", e.what());
        } catch (...) {
            std::snprintf(error, sizeof error, "Synthetic result construction failed with an unknown exception.");
        }
    }
    if (error[0]) Rf_error("%s", error);
    return R_NilValue;
}

extern "C" SEXP rpst_result_counters()
{
    const auto c = rpst::result_counters();
    const char* labels[] = {"tables_made", "tables_freed", "streams_made", "streams_released", "schemas_made",
                            "schemas_released", "batches_made", "batches_released", "children_made", "children_released"};
    const double values[] = {static_cast<double>(c.tables_made), static_cast<double>(c.tables_freed),
                             static_cast<double>(c.streams_made), static_cast<double>(c.streams_released),
                             static_cast<double>(c.schemas_made), static_cast<double>(c.schemas_released),
                             static_cast<double>(c.batches_made), static_cast<double>(c.batches_released),
                             static_cast<double>(c.children_made), static_cast<double>(c.children_released)};
    SEXP out = PROTECT(Rf_allocVector(REALSXP, 10));
    SEXP names = PROTECT(Rf_allocVector(STRSXP, 10));
    for (int i = 0; i < 10; ++i) {
        REAL(out)[i] = values[i];
        SET_STRING_ELT(names, i, Rf_mkChar(labels[i]));
    }
    Rf_setAttrib(out, R_NamesSymbol, names);
    UNPROTECT(2);
    return out;
}

// Scripted consumer. `ops` is an integer matrix with two columns (op, argument). Each op yields one double:
//   1 get_schema into schema slot arg (value: return code)         2 release schema slot arg
//   3 get_next into batch slot arg (value: return code; 100 = end of stream)  4 release batch slot arg
//   5 release the stream                                            6 checksum of batch slot arg (all buffers)
//   7 move child `arg % 100` of batch slot `arg / 100` into child slot (arg % 100) (parent keeps a released stub)
//   8 release child slot arg                                         9 checksum of child slot arg
//  10 get_last_error length (0 when NULL)                           11 batch slot arg length (rows)
//  12 null_count*2 + (bitmap present) of child `arg % 100` of batch slot `arg / 100`    13 same for child slot arg
//  14 validity checksum of child slot arg                           15 same for child `arg % 100` of batch slot `arg / 100`
// Everything still live at the end is released in a fixed order after the script, mirroring a careful consumer.
extern "C" SEXP rpst_result_test_drive(SEXP stream_pointer, SEXP ops_)
{
    ArrowArrayStream* stream = rpst::arrow_stream_require(stream_pointer);
    if (TYPEOF(ops_) != INTSXP || !Rf_isMatrix(ops_) || INTEGER(Rf_getAttrib(ops_, R_DimSymbol))[1] != 2)
        Rf_error("ops must be an integer matrix with two columns.");
    const R_xlen_t n = INTEGER(Rf_getAttrib(ops_, R_DimSymbol))[0];
    SEXP result = PROTECT(Rf_allocVector(REALSXP, n));
    double* out = REAL(result);
    char error[256] = "";
    {
        ArrowSchema schemas[8];
        ArrowArray batches[8];
        ArrowArray children[8];
        std::memset(schemas, 0, sizeof schemas);
        std::memset(batches, 0, sizeof batches);
        std::memset(children, 0, sizeof children);
        const auto checksum = [](const ArrowArray& a) {
            double sum = static_cast<double>(a.length);
            for (std::int64_t c = 0; c < a.n_children; ++c) {
                const ArrowArray* child = a.children[c];
                if (!child || !child->release) continue;
                const unsigned char* bytes = static_cast<const unsigned char*>(child->buffers[1]);
                for (std::int64_t i = 0; i < child->length * 4; ++i) sum += bytes[i] * static_cast<double>((i % 7) + 1);
            }
            return sum;
        };
        const auto child_sum = [](const ArrowArray& child) {
            double sum = static_cast<double>(child.length);
            const unsigned char* bytes = static_cast<const unsigned char*>(child.buffers[1]);
            for (std::int64_t i = 0; i < child.length * 4; ++i) sum += bytes[i] * static_cast<double>((i % 7) + 1);
            return sum;
        };
        // Validity checksum: sum over rows i of (valid(i) ? i + 1 : 0), reading the bitmap at array.offset like a consumer
        // (an absent bitmap means every row is valid).
        const auto valid_sum = [](const ArrowArray& child) {
            double sum = 0;
            for (std::int64_t i = 0; i < child.length; ++i) {
                const std::int64_t row = child.offset + i;
                const unsigned char* bits = static_cast<const unsigned char*>(child.buffers[0]);
                if (!bits || ((bits[row >> 3] >> (row & 7)) & 1)) sum += static_cast<double>(i + 1);
            }
            return sum;
        };
        for (R_xlen_t k = 0; k < n && !error[0]; ++k) {
            const int op = INTEGER(ops_)[k], arg = INTEGER(ops_)[k + n];
            if (arg < 0 || arg > 799) { std::snprintf(error, sizeof error, "Bad op argument."); break; }
            const int slot = (op == 7 || op == 12 || op == 15) ? arg / 100 : arg;
            if (slot > 7) { std::snprintf(error, sizeof error, "Bad op slot."); break; }
            out[k] = 0;
            switch (op) {
            case 1: if (schemas[slot].release) schemas[slot].release(&schemas[slot]);
                    out[k] = stream->get_schema ? stream->get_schema(stream, &schemas[slot]) : -1; break;
            case 2: if (schemas[slot].release) schemas[slot].release(&schemas[slot]); break;
            case 3:
                if (batches[slot].release) batches[slot].release(&batches[slot]);
                out[k] = stream->get_next ? stream->get_next(stream, &batches[slot]) : -1;
                if (out[k] == 0 && !batches[slot].release) out[k] = 100;
                break;
            case 4: if (batches[slot].release) batches[slot].release(&batches[slot]); break;
            case 5: if (stream->release) stream->release(stream); break;
            case 6: out[k] = batches[slot].release ? checksum(batches[slot]) : -1; break;
            case 7: {
                const int child_index = arg % 100;
                if (!batches[slot].release || child_index >= batches[slot].n_children) { out[k] = -1; break; }
                ArrowArray* source = batches[slot].children[child_index];
                if (!source->release) { out[k] = -1; break; }
                if (children[child_index].release) children[child_index].release(&children[child_index]);
                children[child_index] = *source;  // move: the source must now be treated as released
                source->release = nullptr;
                break;
            }
            case 12: {  // null count (x2) and bitmap presence of child `arg % 100` of batch `slot`; -1 if unavailable
                const int child_index = arg % 100;
                if (!batches[slot].release || child_index >= batches[slot].n_children) { out[k] = -1; break; }
                const ArrowArray* source = batches[slot].children[child_index];
                out[k] = source->release ? static_cast<double>(source->null_count) * 2 + (source->buffers[0] ? 1 : 0) : -1;
                break;
            }
            case 13:  // a moved child: null count (x2) + bitmap presence; -1 once released
                out[k] = children[slot].release ? static_cast<double>(children[slot].null_count) * 2 + (children[slot].buffers[0] ? 1 : 0) : -1;
                break;
            case 14: out[k] = children[slot].release ? valid_sum(children[slot]) : -1; break;
            case 15: {  // validity checksum of child `arg % 100` of batch `slot`
                const int child_index = arg % 100;
                if (!batches[slot].release || child_index >= batches[slot].n_children) { out[k] = -1; break; }
                const ArrowArray* source = batches[slot].children[child_index];
                out[k] = source->release ? valid_sum(*source) : -1;
                break;
            }
            case 8: if (children[slot].release) children[slot].release(&children[slot]); break;
            case 9: out[k] = children[slot].release ? child_sum(children[slot]) : -1; break;
            case 10: { const char* e = stream->get_last_error ? stream->get_last_error(stream) : nullptr;
                       out[k] = e ? static_cast<double>(std::strlen(e)) : 0; break; }
            case 11: out[k] = batches[slot].release ? static_cast<double>(batches[slot].length) : -1; break;
            default: std::snprintf(error, sizeof error, "Unknown op."); break;
            }
        }
        for (auto& c : children) if (c.release) c.release(&c);
        for (auto& b : batches) if (b.release) b.release(&b);
        for (auto& s : schemas) if (s.release) s.release(&s);
    }
    if (error[0]) Rf_error("%s", error);
    UNPROTECT(1);
    return result;
}
