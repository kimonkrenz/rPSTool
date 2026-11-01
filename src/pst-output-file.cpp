// R entry points for publishing a result file safely (see docs/spatial-io/result-files.md). Only the operations R cannot do
// safely itself live here: exclusive creation of the temporary file, a no-clobber / replacing publication, and file identity.
// The platform-specific work (POSIX and Win32) is in pst-fs-core.h, which has no R dependency.
#define R_NO_REMAP
#include <Rinternals.h>
#include <string>
#include "pst-fs-core.h"

#ifdef _WIN32
namespace rpst { namespace fs {
// Used by the FlatGeobuf writer (pst-flatgeobuf.cpp) to open the exclusively created temporary file for writing.
std::FILE* open_temp_for_write(const char* utf8_path, std::string& error) { return open_for_write(utf8_path, error); }
}}
#endif

namespace {
// Argument validation only; may raise an R error. No C++ owner exists in these functions. Paths are UTF-8 on Windows (converted
// to UTF-16 for the Win32 API) and in the native encoding elsewhere.
const char* path_arg(SEXP x, const char* what)
{
    if (TYPEOF(x) != STRSXP || XLENGTH(x) != 1 || STRING_ELT(x, 0) == NA_STRING || !CHAR(STRING_ELT(x, 0))[0])
        Rf_error("%s must be one non-empty, non-missing string.", what);
#ifdef _WIN32
    return Rf_translateCharUTF8(STRING_ELT(x, 0));
#else
    return Rf_translateChar(STRING_ELT(x, 0));
#endif
}
}  // namespace

// Are the publication primitives available on this platform? (POSIX and Windows.)
extern "C" SEXP rpst_output_supported()
{
    return Rf_ScalarLogical(1);
}

// Create `path` exclusively (it must not exist; a symbolic link at `path` is never followed). Returns "" on success or
// a short error description. The file is created empty (POSIX: the usual 0666 & ~umask mode).
extern "C" SEXP rpst_output_create_exclusive(SEXP path_)
{
    const char* path = path_arg(path_, "path");
    std::string message;
    try { message = rpst::fs::create_exclusive(path); } catch (...) { message = "out of memory"; }
    return Rf_mkString(message.c_str());
}

// Publish the completed temporary file `from` as `to`, both in the same directory (see pst-fs-core.h for the exact
// guarantees per platform). Returns "" on success, "exists" if the target exists (overwrite = FALSE), otherwise a short error
// description.
extern "C" SEXP rpst_output_publish(SEXP from_, SEXP to_, SEXP overwrite_)
{
    const char* from = path_arg(from_, "from");
    const char* to = path_arg(to_, "to");
    if (TYPEOF(overwrite_) != LGLSXP || XLENGTH(overwrite_) != 1 || LOGICAL(overwrite_)[0] == NA_LOGICAL)
        Rf_error("overwrite must be TRUE or FALSE.");
    const bool overwrite = LOGICAL(overwrite_)[0];
    std::string message;
    try { message = rpst::fs::publish(from, to, overwrite); } catch (...) { message = "out of memory"; }
    return Rf_mkString(message.c_str());
}

// Does a directory entry exist at `path`? A dangling symbolic link counts (unlike file.exists()).
extern "C" SEXP rpst_output_entry_exists(SEXP path_)
{
    const char* path = path_arg(path_, "path");
    bool exists = false;
    try { exists = rpst::fs::entry_exists(path); } catch (...) { exists = false; }
    return Rf_ScalarLogical(exists);
}

// Remove one directory entry that is a file or a symbolic link (never a directory), without following a link. Returns "" or
// a short error description. Used by tests to remove the links they create (R's unlink() cannot do it on Windows).
extern "C" SEXP rpst_output_remove_entry(SEXP path_)
{
    const char* path = path_arg(path_, "path");
    std::string message;
    try { message = rpst::fs::remove_entry(path); } catch (...) { message = "out of memory"; }
    return Rf_mkString(message.c_str());
}

// (device, inode) of the file `path` resolves to (symbolic links followed) as two strings, or c(NA, NA) when it does not
// exist or cannot be examined. Strings, because the identifiers can exceed 2^53 (and are 128 bits on ReFS); they compare
// exactly. POSIX: decimal st_dev / st_ino. Windows: hexadecimal volume serial number and file ID (see pst-fs-core.h). Used to
// refuse a spatial-output destination that is the source network itself (the same path, any spelling of it, a symbolic link
// or a hard link). Identity is a check at one moment, not a proof of content identity.
extern "C" SEXP rpst_file_identity(SEXP path_)
{
    const char* path = path_arg(path_, "path");
    std::string device, inode;
    bool ok = false;
    try { ok = rpst::fs::file_identity(path, device, inode); } catch (...) { ok = false; }
    SEXP result = PROTECT(Rf_allocVector(STRSXP, 2));
    if (ok) {
        SET_STRING_ELT(result, 0, Rf_mkChar(device.c_str()));
        SET_STRING_ELT(result, 1, Rf_mkChar(inode.c_str()));
    } else {
        SET_STRING_ELT(result, 0, NA_STRING);
        SET_STRING_ELT(result, 1, NA_STRING);
    }
    UNPROTECT(1);
    return result;
}
