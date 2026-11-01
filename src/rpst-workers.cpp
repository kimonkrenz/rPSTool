// One policy for every exposed PST worker engine. Called on the caller thread
// while constructing PST workers; no R API, callbacks, or global mutable state.
#include <algorithm>
#include <cctype>
#include <cstddef>
#include <cstdlib>
#include <limits>
#include <stdexcept>
#include <thread>

// R's own convention (parallel:::.check_ncores): the check cap is active for any non-empty
// _R_CHECK_LIMIT_CORES_ value other than "false", compared case-insensitively ("true", "TRUE", "warn", ...).
static bool check_cap_active()
{
    const char* v = std::getenv("_R_CHECK_LIMIT_CORES_");
    if (!v || !*v) return false;
    static const char off[] = "false";
    size_t i = 0;
    for (; off[i] && v[i]; ++i)
        if (std::tolower(static_cast<unsigned char>(v[i])) != off[i]) return true;
    return !(off[i] == '\0' && v[i] == '\0');
}

unsigned int rpst_worker_count()
{
    const unsigned int hardware = std::max(std::thread::hardware_concurrency(), 1u);
    unsigned int limit = hardware;
    const char* explicit_limit = std::getenv("RPST_NUM_THREADS");
    if (explicit_limit) {
        unsigned int value = 0;
        if (!*explicit_limit) throw std::runtime_error("RPST_NUM_THREADS must be a positive integer cap.");
        for (const char* p = explicit_limit; *p; ++p) {
            if (*p < '0' || *p > '9' ||
                value > (std::numeric_limits<unsigned int>::max() - (*p - '0')) / 10)
                throw std::runtime_error("RPST_NUM_THREADS must be a positive integer cap within unsigned integer range.");
            value = value * 10 + (*p - '0');
        }
        if (!value) throw std::runtime_error("RPST_NUM_THREADS must be a positive integer cap.");
        limit = std::min(value, hardware);
    }
    // The check cap is a ceiling: a stricter explicit cap still applies, a larger one cannot lift it.
    if (check_cap_active()) limit = std::min(limit, 2u);
    return limit;
}

// Private observation hook for native/R policy tests. No public worker API.
#define R_NO_REMAP
#include <Rinternals.h>
#include <cstdio>
extern "C" SEXP rpst_workers()
{
    unsigned int count = 0;
    char error[256] = "";
    try { count = rpst_worker_count(); }
    catch (const std::exception& e) { std::snprintf(error, sizeof(error), "%s", e.what()); }
    if (error[0]) Rf_error("%s", error);
    return Rf_ScalarReal(count);
}
