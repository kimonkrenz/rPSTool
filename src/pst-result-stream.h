// Internal interface of the rPSTool result owner and Arrow C Stream producer. Not an installed or public
// header, and it deliberately includes no R header: nothing declared here may call the R API.
//
// A ResultTable owns the complete, finished native result arrays of one analysis (native float32 columns, native
// unsigned counts exposed as Arrow int32, optional per-column validity bitmaps, and an implicit one-based positional id
// column generated per batch). It is
// exported zero-copy as an Arrow C Stream whose batches are slices of those arrays. Ownership is shared: the
// stream, every batch array and every child array each hold a reference, so the buffers stay valid until the last
// Arrow consumer has released its object, in any order and from any thread. Release callbacks only drop references
// and free memory; they never call the R API.
#ifndef RPST_RESULT_STREAM_H
#define RPST_RESULT_STREAM_H
#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <utility>
#include <vector>
#include "arrow-c-abi/arrow_c_abi.h"

namespace rpst {
enum class ResultKind {
    Float32,  // native PST float, exported unchanged as Arrow float32
    Int32,    // native unsigned count/identifier, validated <= INT32_MAX and exported as Arrow int32
    SignedInt32  // native signed int (e.g. a destination index, -1 = none), exported unchanged as Arrow int32
};

struct ResultColumn {
    std::string name;
    ResultKind kind = ResultKind::Float32;
    std::vector<float> f32;         // used when kind == Float32
    std::vector<unsigned int> u32;  // used when kind == Int32
    std::vector<int> i32;           // used when kind == SignedInt32
    // Nullable columns (e.g. diagnostics PST did not write). `nullable` is fixed by the analysis and its parameters, not by
    // whether this run happens to contain a null: it sets the schema's nullable flag, which the Parquet writer needs.
    // `validity` is the full-column Arrow validity bitmap (bit i set = row i valid, LSB-first, (rows+7)/8 bytes); it is
    // empty exactly when the column is not nullable. The value arrays are never altered: a null row keeps whatever the
    // native slot held (not contractual). Valid NaN/Inf/-1/0 values keep their validity bit set.
    bool nullable = false;
    std::vector<std::uint8_t> validity;
};

struct ResultTable {
    ResultTable();
    ~ResultTable();
    ResultTable(const ResultTable&) = delete;
    ResultTable& operator=(const ResultTable&) = delete;
    std::string id_name;                 // implicit one-based positional id column (int32), always first
    std::size_t rows = 0;
    std::vector<ResultColumn> columns;   // in output order, after the id column
    std::vector<std::pair<std::string, std::string>> metadata;  // schema key/value metadata (UTF-8)
};

// Deterministic fault injection for tests only (all disabled by default).
struct StreamFaults {
    int schema_error = 0;      // non-zero: get_schema returns this errno-style code
    long fail_at_batch = -1;   // zero-based batch index at which get_next returns `batch_error`
    int batch_error = 0;
    long oom_at_batch = -1;    // zero-based batch index at which batch construction throws std::bad_alloc
    long oom_validity_at_batch = -1;  // zero-based batch index at which building a nullable child's bitmap throws std::bad_alloc
};

// Validate the table and fill `out` (which must not be live) with a stream over it. On failure nothing is exported,
// `out` is untouched and `error` is set. Calls no R API and never throws.
bool export_result_stream(ArrowArrayStream* out, std::shared_ptr<const ResultTable> table, std::size_t batch_rows,
                          const StreamFaults& faults, char* error, std::size_t error_size);

// Cumulative object counters (made / released), for lifecycle tests.
struct ResultCounters {
    unsigned long long tables_made, tables_freed, streams_made, streams_released, schemas_made, schemas_released,
        batches_made, batches_released, children_made, children_released;
};
ResultCounters result_counters();

// Default rows per Arrow batch (also the Parquet row-group size used by the R writer).
constexpr std::size_t kResultBatchRows = static_cast<std::size_t>(1) << 20;
}  // namespace rpst
#endif
