// Standalone check of the filesystem layer behind result-file publication (src/pst-fs-core.h), run on the real operating-system
// API without R. Build and run (the Windows commands are in tools/validation/windows/README.md):
//   Linux/macOS:  g++ -std=c++17 -I src tools/validation/windows/fs-harness.cpp -pthread -o fs-harness && ./fs-harness DIR
//   Windows:      g++ -std=c++17 -I src tools/validation/windows/fs-harness.cpp -o fs-harness.exe && fs-harness.exe DIR
// DIR must be an existing, empty, writable directory on the file system under test. Exit status 0 = all checks passed.
#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#include <thread>
#include <vector>
#include "pst-fs-core.h"

namespace fs = rpst::fs;
static int failures = 0, checks = 0, skipped = 0;
#define CHECK(cond) do { ++checks; if (!(cond)) { ++failures; std::cout << "FAIL line " << __LINE__ << ": " #cond "\n"; } } while (0)
#define CHECK_EQ(a, b) do { ++checks; const std::string x_ = (a), y_ = (b); if (x_ != y_) { ++failures; \
    std::cout << "FAIL line " << __LINE__ << ": " #a " = [" << x_ << "] expected [" << y_ << "]\n"; } } while (0)

static std::string join(const std::string& dir, const std::string& name) { return dir + "/" + name; }
static void write_file(const std::string& path, const std::string& text)
{
#ifdef _WIN32
    std::wstring w; fs::win_path(path.c_str(), w);
    std::ofstream out(w.c_str(), std::ios::binary);
#else
    std::ofstream out(path, std::ios::binary);
#endif
    out << text;
}
static std::string read_file(const std::string& path)
{
#ifdef _WIN32
    std::wstring w; fs::win_path(path.c_str(), w);
    std::ifstream in(w.c_str(), std::ios::binary);
#else
    std::ifstream in(path, std::ios::binary);
#endif
    return std::string((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
}
static bool remove_file(const std::string& path)
{
#ifdef _WIN32
    std::wstring w; fs::win_path(path.c_str(), w);
    return ::DeleteFileW(w.c_str()) != 0;
#else
    return ::unlink(path.c_str()) == 0;
#endif
}
static bool hard_link(const std::string& existing, const std::string& added)
{
#ifdef _WIN32
    std::wstring a, b; fs::win_path(existing.c_str(), a); fs::win_path(added.c_str(), b);
    return ::CreateHardLinkW(b.c_str(), a.c_str(), nullptr) != 0;
#else
    return ::link(existing.c_str(), added.c_str()) == 0;
#endif
}
#ifdef _WIN32
// Wine maps symbolic links to Unix symbolic links and does not reproduce the Windows reparse-point semantics that these checks
// are about, so they are skipped there (they must pass on real Windows).
static bool running_under_wine()
{
    HMODULE ntdll = ::GetModuleHandleW(L"ntdll.dll");
    return ntdll && ::GetProcAddress(ntdll, "wine_get_version") != nullptr;
}
#endif
static bool symlink_to(const std::string& target, const std::string& link)
{
#ifdef _WIN32
    if (running_under_wine()) return false;
    std::wstring a, b; fs::win_path(target.c_str(), a); fs::win_path(link.c_str(), b);
    // SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE (0x2) needs Developer Mode; without it the call fails (and the check is skipped).
    return ::CreateSymbolicLinkW(b.c_str(), a.c_str(), 0x2) != 0;
#else
    return ::symlink(target.c_str(), link.c_str()) == 0;
#endif
}

int main(int argc, char** argv)
{
    if (argc != 2) { std::cout << "usage: fs-harness DIR\n"; return 2; }
    const std::string dir = argv[1];
    // accents, Cyrillic, CJK and a supplementary-plane character, spelled as UTF-8 bytes
    const std::string uni = "r\xC3\xA9sum\xC3\xA9-\xD0\x96-\xE6\x97\xA5\xE6\x9C\xAC-\xF0\x9F\x98\x80";

    // ---- create_exclusive ---------------------------------------------------------------------------------------------------
    const std::string a = join(dir, "a.partial");
    CHECK_EQ(fs::create_exclusive(a.c_str()), "");
    CHECK(fs::entry_exists(a.c_str()));
    CHECK_EQ(read_file(a), "");
    CHECK(fs::create_exclusive(a.c_str()).find("exist") != std::string::npos);        // never reuses a file
    CHECK(fs::create_exclusive(join(dir, "no/such/dir/x").c_str()).find("No such file") != std::string::npos);
    const std::string u = join(dir, uni + ".partial");
    CHECK_EQ(fs::create_exclusive(u.c_str()), "");                                    // Unicode path
    CHECK(fs::entry_exists(u.c_str()));
    CHECK(fs::create_exclusive(u.c_str()).find("exist") != std::string::npos);
    CHECK(!fs::entry_exists(join(dir, "missing").c_str()));

    // ---- dangling symbolic link: exists, never followed ----------------------------------------------------------------------
    const std::string dangling = join(dir, "dangling");
    if (symlink_to(join(dir, "nowhere"), dangling)) {
        CHECK(fs::entry_exists(dangling.c_str()));                                    // file.exists() would say FALSE
        CHECK(fs::create_exclusive(dangling.c_str()).find("exist") != std::string::npos);
        write_file(join(dir, "d.tmp"), "D");
        CHECK_EQ(fs::publish(join(dir, "d.tmp").c_str(), dangling.c_str(), false), "exists");   // no-clobber also refuses a link
        CHECK(!fs::entry_exists(join(dir, "nowhere").c_str()));                        // the target was never created
        std::string dev, ino;
        CHECK(!fs::file_identity(dangling.c_str(), dev, ino));                         // a dangling link has no identity
        remove_file(join(dir, "d.tmp"));
        remove_file(dangling);
    } else { ++skipped; std::cout << "SKIP symbolic links are not available here\n"; }

    // ---- remove_entry: files and links, never a directory, never a link target ----------------------------------------------------
    {
        const std::string r1 = join(dir, "rm1.tmp"), r2 = join(dir, "rm2.tmp");
        write_file(r1, "R");
        CHECK_EQ(fs::remove_entry(r1.c_str()), "");
        CHECK(!fs::entry_exists(r1.c_str()));
        CHECK(!fs::remove_entry(r1.c_str()).empty());                                   // already gone
        write_file(r1, "R");
        if (hard_link(r1, r2)) {
            CHECK_EQ(fs::remove_entry(r2.c_str()), "");                                 // one name of two
            CHECK_EQ(read_file(r1), "R");
        }
        remove_file(r1);
        const std::string sub = join(dir, "rm-dir");
#ifdef _WIN32
        std::wstring ws; fs::win_path(sub.c_str(), ws); ::CreateDirectoryW(ws.c_str(), nullptr);
#else
        ::mkdir(sub.c_str(), 0777);
#endif
        CHECK(!fs::remove_entry(sub.c_str()).empty());                                  // a real directory is refused
        CHECK(fs::entry_exists(sub.c_str()));
        write_file(r1, "T");
        const std::string rl = join(dir, "rm-link");
        if (symlink_to(r1, rl)) {
            CHECK_EQ(fs::remove_entry(rl.c_str()), "");                                 // the link goes ...
            CHECK(!fs::entry_exists(rl.c_str()));
            CHECK_EQ(read_file(r1), "T");                                               // ... its target stays
        }
        if (symlink_to(join(dir, "rm-nowhere"), rl)) {
            CHECK_EQ(fs::remove_entry(rl.c_str()), "");                                 // a dangling link too
            CHECK(!fs::entry_exists(rl.c_str()));
        }
        remove_file(r1);
    }

    // ---- publish: no-clobber -------------------------------------------------------------------------------------------------
    const std::string b = join(dir, "b.out");
    write_file(a, "A"); write_file(b, "B");
    CHECK_EQ(fs::publish(a.c_str(), b.c_str(), false), "exists");
    CHECK_EQ(read_file(a), "A"); CHECK_EQ(read_file(b), "B");                          // nothing changed
    const std::string c = join(dir, "c.partial"), d = join(dir, "d.out");
    write_file(c, "C");
    CHECK_EQ(fs::publish(c.c_str(), d.c_str(), false), "");
    CHECK(!fs::entry_exists(c.c_str())); CHECK_EQ(read_file(d), "C");                  // the temporary name is gone
    CHECK(!fs::publish(join(dir, "gone").c_str(), join(dir, "e.out").c_str(), false).empty());   // missing source
    CHECK(!fs::entry_exists(join(dir, "e.out").c_str()));

    // ---- publish: replace ----------------------------------------------------------------------------------------------------
    CHECK_EQ(fs::publish(a.c_str(), b.c_str(), true), "");
    CHECK(!fs::entry_exists(a.c_str())); CHECK_EQ(read_file(b), "A");
    CHECK(!fs::publish(join(dir, "gone").c_str(), b.c_str(), true).empty());           // failure leaves the target intact
    CHECK_EQ(read_file(b), "A");
    const std::string fresh = join(dir, "fresh.partial"), nothing = join(dir, "nothing.out");
    write_file(fresh, "F");
    CHECK_EQ(fs::publish(fresh.c_str(), nothing.c_str(), true), "");                   // replace of a non-existing target publishes
    CHECK_EQ(read_file(nothing), "F");

    // Replacement while the old file is open for reading by someone else. Windows: refused (sharing violation) with the old file
    // intact, unless the reader allowed deletion; POSIX: succeeds, the reader keeps the old inode. Either way nothing is lost.
    {
        const std::string t = join(dir, "inuse.out"), p = join(dir, "inuse.partial");
        write_file(t, "OLD"); write_file(p, "NEW");
#ifdef _WIN32
        std::wstring wt; fs::win_path(t.c_str(), wt);
        HANDLE reader = ::CreateFileW(wt.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
        CHECK(reader != INVALID_HANDLE_VALUE);
        const std::string outcome = fs::publish(p.c_str(), t.c_str(), true);
        std::cout << "INFO replace while a reader without FILE_SHARE_DELETE holds the target: [" << outcome << "]\n";
        ::CloseHandle(reader);
        if (!outcome.empty()) {
            CHECK_EQ(read_file(t), "OLD"); CHECK_EQ(read_file(p), "NEW");              // failed safely: both files intact
            CHECK_EQ(fs::publish(p.c_str(), t.c_str(), true), "");                     // and succeeds once the reader is gone
        }
#else
        CHECK_EQ(fs::publish(p.c_str(), t.c_str(), true), "");
#endif
        CHECK_EQ(read_file(t), "NEW"); CHECK(!fs::entry_exists(p.c_str()));
    }

#ifdef _WIN32
    // The handle mode Apache Arrow uses for every local file it reads or maps (arrow/util/io_util.cc FileOpenReadable): GENERIC_READ,
    // FILE_SHARE_READ | FILE_SHARE_WRITE, no FILE_SHARE_DELETE. While one is open, replacing or deleting the file is refused, and so is R's
    // Sys.setFileTime() (platform.c winSetFileTime: GENERIC_WRITE with share mode 0, which fails silently, returning FALSE).
    {
        const std::string t = join(dir, "arrow-held.out"), p = join(dir, "arrow-held.partial");
        write_file(t, "OLD"); write_file(p, "NEW");
        std::wstring wt; fs::win_path(t.c_str(), wt);
        HANDLE h = ::CreateFileW(wt.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
        CHECK(h != INVALID_HANDLE_VALUE);
        CHECK(!fs::publish(p.c_str(), t.c_str(), true).empty());                           // replacement refused ...
        CHECK_EQ(read_file(t), "OLD");                                                     // ... the old file is intact
        CHECK(!fs::remove_entry(t.c_str()).empty());                                       // deletion refused
        HANDLE exclusive = ::CreateFileW(wt.c_str(), GENERIC_WRITE, 0, nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nullptr);
        CHECK(exclusive == INVALID_HANDLE_VALUE);                                          // what R's Sys.setFileTime() asks for
        if (exclusive != INVALID_HANDLE_VALUE) ::CloseHandle(exclusive);
        ::CloseHandle(h);
        CHECK_EQ(fs::publish(p.c_str(), t.c_str(), true), "");                             // after closing it works
        CHECK_EQ(read_file(t), "NEW");
    }
#endif

    // ---- publish with Unicode names ------------------------------------------------------------------------------------------
    const std::string up = join(dir, uni + ".out");
    write_file(u, "U");
    CHECK_EQ(fs::publish(u.c_str(), up.c_str(), false), "");
    CHECK_EQ(read_file(up), "U");
    write_file(u, "U2");
    CHECK_EQ(fs::publish(u.c_str(), up.c_str(), false), "exists");
    CHECK_EQ(fs::publish(u.c_str(), up.c_str(), true), "");
    CHECK_EQ(read_file(up), "U2");

    // ---- no-clobber race: many threads publish to one target; exactly one wins -------------------------------------------------
    {
        const std::string target = join(dir, "race.out");
        const int n = 16;
        std::vector<std::string> parts;
        for (int i = 0; i < n; ++i) { parts.push_back(join(dir, "race" + std::to_string(i) + ".partial")); write_file(parts.back(), std::to_string(i)); }
        std::vector<std::string> results(n);
        std::vector<std::thread> threads;
        for (int i = 0; i < n; ++i) threads.emplace_back([&, i] { results[i] = fs::publish(parts[i].c_str(), target.c_str(), false); });
        for (auto& t : threads) t.join();
        int won = 0, lost = 0;
        for (auto& r : results) { if (r.empty()) ++won; else if (r == "exists") ++lost; }
        CHECK(won == 1); CHECK(lost == n - 1);
        int left = 0; for (auto& p : parts) if (fs::entry_exists(p.c_str())) ++left;
        CHECK(left == n - 1);                                                           // the losers keep their temporary files
        for (auto& p : parts) remove_file(p);
    }

    // ---- file identity -------------------------------------------------------------------------------------------------------
    {
        const std::string s = join(dir, "source.fgb"), hl = join(dir, "hardlink.fgb"), other = join(dir, "other.fgb");
        write_file(s, "S"); write_file(other, "S");
        std::string d1, i1, d2, i2, d3, i3;
        CHECK(fs::file_identity(s.c_str(), d1, i1)); CHECK(!d1.empty() && !i1.empty());
        CHECK(fs::file_identity(s.c_str(), d2, i2)); CHECK(d1 == d2 && i1 == i2);        // stable
        CHECK(fs::file_identity(other.c_str(), d3, i3)); CHECK(!(d1 == d3 && i1 == i3)); // same content, different file
        if (hard_link(s, hl)) {
            CHECK(fs::file_identity(hl.c_str(), d3, i3)); CHECK(d1 == d3 && i1 == i3);   // a hard link is the same file
        } else { ++skipped; std::cout << "SKIP hard links are not available on this file system\n"; }
        const std::string sl = join(dir, "symlink.fgb");
        if (symlink_to(s, sl)) {
            CHECK(fs::file_identity(sl.c_str(), d3, i3)); CHECK(d1 == d3 && i1 == i3);   // links are followed
        } else { ++skipped; std::cout << "SKIP symbolic links are not available here\n"; }
#ifdef _WIN32
        std::string upper = s; std::transform(upper.begin(), upper.end(), upper.begin(), [](unsigned char ch) { return static_cast<char>(std::toupper(ch)); });
        std::string back = s; std::replace(back.begin(), back.end(), '/', '\\');
        CHECK(fs::file_identity(back.c_str(), d3, i3)); CHECK(d1 == d3 && i1 == i3);     // '\' versus '/'
        if (fs::file_identity(upper.c_str(), d3, i3)) { CHECK(d1 == d3 && i1 == i3); }   // case-insensitive alias (if the volume is)
#endif
        std::string dd, ii;
        CHECK(!fs::file_identity(join(dir, "missing").c_str(), dd, ii));
        const std::string ui = join(dir, uni + ".id"); write_file(ui, "x");
        CHECK(fs::file_identity(ui.c_str(), dd, ii));                                     // Unicode path
        std::cout << "INFO identity of source.fgb: device=" << d1 << " inode=" << i1 << "\n";
    }

#ifdef _WIN32
    // ---- open_for_write: refuses reparse points, writes through the stream ------------------------------------------------------
    {
        const std::string t = join(dir, "w.partial");
        CHECK_EQ(fs::create_exclusive(t.c_str()), "");
        std::string error;
        std::FILE* f = fs::open_for_write(t.c_str(), error);
        CHECK(f != nullptr);
        if (f) { CHECK(std::fwrite("hello", 1, 5, f) == 5); CHECK(std::fflush(f) == 0); CHECK(std::fclose(f) == 0); }
        CHECK_EQ(read_file(t), "hello");
        CHECK(fs::open_for_write(join(dir, "missing.partial").c_str(), error) == nullptr);
        const std::string sl = join(dir, "w.link");
        if (symlink_to(t, sl)) {
            CHECK(fs::open_for_write(sl.c_str(), error) == nullptr);                     // a symbolic link is never written through
            CHECK_EQ(read_file(t), "hello");
        }
        CHECK(fs::open_for_write(dir.c_str(), error) == nullptr);                         // a directory is refused
    }
    // ---- a path of more than MAX_PATH characters (extended-length prefix) ------------------------------------------------------
    {
        std::string deep = dir;
        for (int i = 0; i < 6 && deep.size() < 300; ++i) {
            deep += "/" + std::string(60, static_cast<char>('a' + i));
            std::wstring w; fs::win_path(deep.c_str(), w);
            if (!::CreateDirectoryW(w.c_str(), nullptr)) break;
        }
        const std::string lp = deep + "/long.partial", lo = deep + "/long.out";
        if (deep.size() > 270) {
            CHECK_EQ(fs::create_exclusive(lp.c_str()), "");
            CHECK_EQ(fs::publish(lp.c_str(), lo.c_str(), false), "");
            CHECK(fs::entry_exists(lo.c_str()));
        } else { ++skipped; std::cout << "SKIP could not build a long path\n"; }
    }
#endif

    std::cout << "fs-harness: " << checks << " checks, " << failures << " failed, " << skipped << " skipped\n";
    return failures ? 1 : 0;
}
