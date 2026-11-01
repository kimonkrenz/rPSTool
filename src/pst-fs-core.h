// Filesystem primitives for publishing result files, without any R dependency (so that they can be exercised by a
// standalone harness on the real Win32 API; see tools/validation/windows/). Paths are UTF-8 on Windows and in the native
// encoding elsewhere. Every function returns an empty string on success or a short error description.
//
//   create_exclusive  create an EMPTY file that must not exist; a symbolic link (also a dangling one) at the path is never
//                     followed and counts as existing.
//   publish           move the completed temporary file `from` to `to`, both in the same directory.
//                       overwrite = false  never replaces anything; the kernel checks and renames in one step
//                                          (POSIX link(2) + unlink(2); Windows MoveFileExW without
//                                          MOVEFILE_REPLACE_EXISTING). Result "exists" when `to` exists.
//                       overwrite = true   replaces `to` by a single rename (POSIX rename(2); Windows MoveFileExW with
//                                          MOVEFILE_REPLACE_EXISTING). On any failure the old `to` is untouched.
//   entry_exists      does a directory entry exist at the path (a dangling symbolic link counts)?
//   remove_entry      remove one directory entry that is a file or a symbolic link, without following the link and without
//                     touching its target (R's unlink() cannot remove a symbolic link on Windows: it sends a junction-only
//                     FSCTL_DELETE_REPARSE_POINT); a real directory is refused.
//   file_identity     exact (device, inode) identity of the file the path resolves to (links followed), as strings.
//   open_for_write    Windows: open the existing temporary file for writing as a FILE*, refusing reparse points.
#pragma once
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <fcntl.h>
#include <io.h>
#else
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

namespace rpst {
namespace fs {

inline std::string message_from_errno(int code)
{
    char buffer[200];
    std::snprintf(buffer, sizeof buffer, "%s", std::strerror(code));
    return buffer;
}

#ifdef _WIN32

// UTF-8 to UTF-16 (strict: invalid UTF-8 is an error). Returns false for invalid input.
inline bool utf8_to_wide(const char* s, std::wstring& out)
{
    out.clear();
    if (!s || !*s) return true;
    const int n = ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s, -1, nullptr, 0);
    if (n <= 0) return false;
    out.resize(static_cast<std::size_t>(n));
    if (::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s, -1, &out[0], n) <= 0) return false;
    out.resize(static_cast<std::size_t>(n) - 1);   // drop the terminating NUL
    return true;
}

// The UTF-16 path to hand to the Win32 API: '/' becomes '\', and a long absolute path gets the extended-length prefix
// (which switches off Win32's own normalisation, so the separators must already be backslashes).
inline bool win_path(const char* utf8, std::wstring& out)
{
    if (!utf8_to_wide(utf8, out) || out.empty()) return false;
    for (wchar_t& c : out) if (c == L'/') c = L'\\';
    const bool extended = out.compare(0, 4, L"\\\\?\\") == 0 || out.compare(0, 4, L"\\\\.\\") == 0;
    if (!extended && out.size() >= 240) {
        if (out.size() > 2 && out[1] == L':' && out[2] == L'\\') out.insert(0, L"\\\\?\\");
        else if (out.compare(0, 2, L"\\\\") == 0) out.replace(0, 2, L"\\\\?\\UNC\\");
    }
    return true;
}

// Win32 error code -> the wording the POSIX implementation (and the tests) use for the same condition.
inline std::string message_from_win32(DWORD code)
{
    switch (code) {
    case ERROR_FILE_EXISTS: case ERROR_ALREADY_EXISTS: return "File exists";
    case ERROR_FILE_NOT_FOUND: case ERROR_PATH_NOT_FOUND: case ERROR_INVALID_NAME: return "No such file or directory";
    case ERROR_ACCESS_DENIED: return "Permission denied";
    case ERROR_DISK_FULL: case ERROR_HANDLE_DISK_FULL: return "No space left on device";
    case ERROR_SHARING_VIOLATION: case ERROR_LOCK_VIOLATION: return "The file is in use by another process";
    default: break;
    }
    char buffer[300];
    std::snprintf(buffer, sizeof buffer, "Windows error %lu", static_cast<unsigned long>(code));
    return buffer;
}

inline std::string create_exclusive(const char* path)
{
    std::wstring w;
    if (!win_path(path, w)) return "The path is not valid";
    // CREATE_NEW fails if anything with that name exists. FILE_FLAG_OPEN_REPARSE_POINT: a (dangling) symbolic link is never followed.
    HANDLE h = ::CreateFileW(w.c_str(), GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
                             CREATE_NEW, FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (h == INVALID_HANDLE_VALUE) return message_from_win32(::GetLastError());
    if (!::CloseHandle(h)) {
        const DWORD code = ::GetLastError();
        ::DeleteFileW(w.c_str());
        return message_from_win32(code);
    }
    return "";
}

inline std::string publish(const char* from, const char* to, bool overwrite)
{
    std::wstring wf, wt;
    if (!win_path(from, wf) || !win_path(to, wt)) return "The path is not valid";
    // No MOVEFILE_COPY_ALLOWED: a rename within one volume only, never a copy-and-delete. Without MOVEFILE_REPLACE_EXISTING an
    // existing destination makes the call fail (the check and the rename are one operation in the file system).
    const DWORD flags = overwrite ? MOVEFILE_REPLACE_EXISTING : 0;
    for (int attempt = 0;; ++attempt) {
        if (::MoveFileExW(wf.c_str(), wt.c_str(), flags)) return "";
        const DWORD code = ::GetLastError();
        // Virus scanners and indexers briefly hold files open; retrying a failed rename is always safe.
        if ((code == ERROR_SHARING_VIOLATION || code == ERROR_LOCK_VIOLATION) && attempt < 10) { ::Sleep(50); continue; }
        if (!overwrite && (code == ERROR_ALREADY_EXISTS || code == ERROR_FILE_EXISTS)) return "exists";
        return message_from_win32(code);
    }
}

inline std::string remove_entry(const char* path)
{
    std::wstring w;
    if (!win_path(path, w)) return "The path is not valid";
    const DWORD attributes = ::GetFileAttributesW(w.c_str());   // does not follow reparse points
    if (attributes == INVALID_FILE_ATTRIBUTES) return message_from_win32(::GetLastError());
    BOOL ok;
    if (attributes & FILE_ATTRIBUTE_DIRECTORY) {
        // only a directory symbolic link or junction (a reparse point) is a link; RemoveDirectoryW then removes the link itself
        if (!(attributes & FILE_ATTRIBUTE_REPARSE_POINT)) return "The entry is a directory";
        ok = ::RemoveDirectoryW(w.c_str());
    } else {
        ok = ::DeleteFileW(w.c_str());   // for a file symbolic link this deletes the link, not its target
    }
    return ok ? "" : message_from_win32(::GetLastError());
}

inline bool entry_exists(const char* path)
{
    std::wstring w;
    if (!win_path(path, w)) return false;
    // GetFileAttributesW does not follow reparse points: a dangling symbolic link still has attributes.
    return ::GetFileAttributesW(w.c_str()) != INVALID_FILE_ATTRIBUTES;
}

// Identity of the file the path resolves to. FILE_ID_INFO (Windows 8 / Server 2012 and later) carries a 64-bit volume serial
// number and a 128-bit file ID; older systems and file systems that cannot provide it fall back to the 32-bit volume serial
// number and the 64-bit file index of BY_HANDLE_FILE_INFORMATION. Hard links to one file, and every spelling of one path
// (case, short names, '/' versus '\'), give the same identity; a symbolic link gives that of its target.
inline bool file_identity(const char* path, std::string& device, std::string& inode)
{
    std::wstring w;
    if (!win_path(path, w)) return false;
    HANDLE h = ::CreateFileW(w.c_str(), 0, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
                             FILE_FLAG_BACKUP_SEMANTICS, nullptr);
    if (h == INVALID_HANDLE_VALUE) return false;
    struct IdInfo { std::uint64_t volume; unsigned char id[16]; } info;
    typedef BOOL(WINAPI * GetEx)(HANDLE, int, LPVOID, DWORD);
    GetEx get_ex = nullptr;
    if (HMODULE k = ::GetModuleHandleW(L"kernel32.dll"))
        get_ex = reinterpret_cast<GetEx>(reinterpret_cast<void*>(::GetProcAddress(k, "GetFileInformationByHandleEx")));
    char buffer[64];
    bool ok = false;
    const int kFileIdInfo = 18;
    if (get_ex && get_ex(h, kFileIdInfo, &info, sizeof info)) {
        std::snprintf(buffer, sizeof buffer, "%016llx", static_cast<unsigned long long>(info.volume));
        device = buffer;
        inode.clear();
        for (int i = 15; i >= 0; --i) { std::snprintf(buffer, sizeof buffer, "%02x", info.id[i]); inode += buffer; }
        ok = true;
    } else {
        BY_HANDLE_FILE_INFORMATION bh;
        if (::GetFileInformationByHandle(h, &bh)) {
            std::snprintf(buffer, sizeof buffer, "%08lx", static_cast<unsigned long>(bh.dwVolumeSerialNumber));
            device = buffer;
            std::snprintf(buffer, sizeof buffer, "%08lx%08lx", static_cast<unsigned long>(bh.nFileIndexHigh),
                          static_cast<unsigned long>(bh.nFileIndexLow));
            inode = buffer;
            ok = true;
        }
    }
    ::CloseHandle(h);
    return ok;
}

// Open the existing temporary file `path` for writing ("wb" semantics, nothing truncated: the file is empty). A reparse point
// (symbolic link, junction) is refused. The handle is owned by the returned FILE*.
inline std::FILE* open_for_write(const char* path, std::string& error)
{
    std::wstring w;
    if (!win_path(path, w)) { error = "The path is not valid"; return nullptr; }
    HANDLE h = ::CreateFileW(w.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
                             FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (h == INVALID_HANDLE_VALUE) { error = message_from_win32(::GetLastError()); return nullptr; }
    BY_HANDLE_FILE_INFORMATION bh;
    if (!::GetFileInformationByHandle(h, &bh) || (bh.dwFileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY))) {
        ::CloseHandle(h);
        error = "The temporary output file is not a regular file";
        return nullptr;
    }
    const int fd = ::_open_osfhandle(reinterpret_cast<intptr_t>(h), _O_WRONLY | _O_BINARY);
    if (fd < 0) { ::CloseHandle(h); error = "Cannot attach the temporary output file to a stream"; return nullptr; }
    std::FILE* f = ::_fdopen(fd, "wb");
    if (!f) { ::_close(fd); error = "Cannot open the temporary output file for writing"; return nullptr; }
    return f;
}

#else  // POSIX

inline std::string create_exclusive(const char* path)
{
    const int fd = ::open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0666);
    if (fd < 0) return message_from_errno(errno);
    if (::close(fd) != 0) {
        const std::string m = message_from_errno(errno);
        ::unlink(path);
        return m;
    }
    return "";
}

inline std::string publish(const char* from, const char* to, bool overwrite)
{
    if (overwrite) {
        if (::rename(from, to) != 0) return message_from_errno(errno);
        return "";
    }
    if (::link(from, to) != 0) {
        if (errno == EEXIST) return "exists";
        return "no-clobber publication failed (" + message_from_errno(errno) + "); this filesystem may not support hard links";
    }
    if (::unlink(from) != 0)   // The target is published and complete; only the temporary name remains for the caller.
        return "published, but the temporary file could not be removed (" + message_from_errno(errno) + ")";
    return "";
}

inline std::string remove_entry(const char* path)
{
    struct stat st;
    if (::lstat(path, &st) != 0) return message_from_errno(errno);
    if (S_ISDIR(st.st_mode)) return "The entry is a directory";
    if (::unlink(path) != 0) return message_from_errno(errno);
    return "";
}

inline bool entry_exists(const char* path)
{
    struct stat st;
    return ::lstat(path, &st) == 0;
}

inline bool file_identity(const char* path, std::string& device, std::string& inode)
{
    struct stat st;
    if (::stat(path, &st) != 0) return false;
    device = std::to_string(static_cast<unsigned long long>(st.st_dev));
    inode = std::to_string(static_cast<unsigned long long>(st.st_ino));
    return true;
}

#endif

}  // namespace fs
}  // namespace rpst
