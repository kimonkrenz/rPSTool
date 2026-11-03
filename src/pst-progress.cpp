// Single-line console progress for long analyses. Everything here runs on the R main thread: the PST callback is
// invoked by the thread that called the analysis, and the guard below ignores any other thread. The callback does
// arithmetic only until two seconds have passed since the operation began; afterwards it redraws only when the
// visible percentage or the active analysis changed. PST itself throttles the callback to about every 100 ms.
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <string>
#include <thread>
#include <vector>

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Print.h>
#include <R_ext/Utils.h>
#include <R_ext/Rdynload.h>

#include "pst-progress.h"

namespace {
constexpr int kBarCells = 20;
constexpr double kShowAfterSeconds = 2.0;

struct State {
    bool active = false;
    bool visible = false;
    bool dead = false;          // a console write failed: stay silent for the rest of the operation
    bool unicode = false;
    std::vector<std::string> labels;
    size_t label_cells = 0;     // padded label width (characters)
    int total = 0;
    int index = 0;              // 1-based number of the analysis being run
    int shown_pct = -1;
    int shown_index = 0;
    size_t last_cells = 0;      // display width of the line currently on screen
    double start = 0;
    std::thread::id owner;
    // pending draw
    std::string line;
    size_t line_cells = 0;
};
State g;
double g_fake_now = -1;         // test hook: seconds; < 0 means the real monotonic clock
double g_fake_step = 0;         // test hook: seconds the fake clock advances after each read

double now_seconds()
{
    if (g_fake_now >= 0) { const double t = g_fake_now; g_fake_now += g_fake_step; return t; }
    using clock = std::chrono::steady_clock;
    return std::chrono::duration<double>(clock::now().time_since_epoch()).count();
}

// UTF-8 code points, which is the display width of the label and of the block characters used.
size_t cells(const std::string& s)
{
    size_t n = 0;
    for (unsigned char c : s) if ((c & 0xC0) != 0x80) ++n;
    return n;
}

std::string truncate_cells(const std::string& s, size_t max_cells)
{
    if (cells(s) <= max_cells) return s;
    size_t n = 0, i = 0;
    for (; i < s.size(); ++i) {
        if ((static_cast<unsigned char>(s[i]) & 0xC0) != 0x80) { if (n == max_cells) break; ++n; }
    }
    return s.substr(0, i);
}

void build_line(int pct)
{
    const std::string& raw = g.labels[static_cast<size_t>(std::min(std::max(g.index, 1), g.total) - 1)];
    std::string label = truncate_cells(raw, g.label_cells);
    const size_t label_len = cells(label);
    std::string line = label;
    line.append(g.label_cells > label_len ? g.label_cells - label_len : 0, ' ');
    const int filled = pct * kBarCells / 100;
    line += "  ";
    if (g.unicode) {
        for (int i = 0; i < kBarCells; ++i) line += (i < filled ? "\xE2\x96\x88" : "\xE2\x96\x91");   // U+2588, U+2591
    } else {
        line += '[';
        line.append(static_cast<size_t>(filled), '#');
        line.append(static_cast<size_t>(kBarCells - filled), '-');
        line += ']';
    }
    char buf[48];
    std::snprintf(buf, sizeof buf, "  %3d%%", pct);
    line += buf;
    if (g.total > 1) {
        std::snprintf(buf, sizeof buf, "  Analysis %d/%d", std::min(std::max(g.index, 1), g.total), g.total);
        line += buf;
    }
    g.line = std::move(line);
    g.line_cells = cells(g.line);
}

void write_line(void*)
{
    // Pad with spaces so a shorter replacement leaves no trailing characters of the previous line.
    std::string out = "\r" + g.line;
    if (g.last_cells > g.line_cells) out.append(g.last_cells - g.line_cells, ' ');
    Rprintf("%s", out.c_str());
    R_FlushConsole();
}

void write_clear(void*)
{
    Rprintf("\r%s\r", std::string(g.last_cells, ' ').c_str());
    R_FlushConsole();
}

// Console writes go through R_ToplevelExec so that an R-level failure (for example a failing sink connection) can
// never longjmp across PST's C++ frames.
void draw(int pct)
{
    build_line(pct);
    if (!R_ToplevelExec(write_line, nullptr)) { g.dead = true; return; }
    g.last_cells = g.line_cells;
    g.shown_pct = pct;
    g.shown_index = g.index;
}

int progress_callback(const char* text, float progress, void*)
{
    if (text || !g.active || g.dead) return 0;
    if (std::this_thread::get_id() != g.owner) return 0;
    if (!g.visible) {
        if (now_seconds() - g.start < kShowAfterSeconds) return 0;
        g.visible = true;
    }
    int pct = static_cast<int>(progress * 100.0f);          // whole percent, floored: 100 only when PST reports 1
    pct = std::min(100, std::max(0, pct));
    if (pct == g.shown_pct && g.index == g.shown_index) return 0;
    draw(pct);
    return 0;
}

void analysis_started()
{
    ++g.index;
    g.shown_pct = -1;
    if (g.visible && !g.dead) draw(0);
}
}  // namespace

namespace rpst {
void progress_attach(FPSTAProgressCallback& callback, void*& user_data)
{
    if (!g.active || g.dead) return;
    callback = &progress_callback;
    user_data = nullptr;
    analysis_started();
}
}  // namespace rpst

extern "C" {
// rpst_progress_begin(labels, unicode, width): TRUE when this call started progress for the operation, FALSE when
// progress is already active (a nested operation) or the labels are unusable.
SEXP rpst_progress_begin(SEXP labels, SEXP unicode, SEXP width)
{
    if (g.active) return Rf_ScalarLogical(FALSE);
    if (TYPEOF(labels) != STRSXP || XLENGTH(labels) < 1 || XLENGTH(labels) > 100000) return Rf_ScalarLogical(FALSE);
    State fresh;
    fresh.unicode = Rf_asLogical(unicode) == TRUE;
    const int total = static_cast<int>(XLENGTH(labels));
    size_t widest = 1;
    for (int i = 0; i < total; ++i) {
        std::string label = Rf_translateCharUTF8(STRING_ELT(labels, i));
        widest = std::max(widest, cells(label));
        fresh.labels.push_back(std::move(label));
    }
    fresh.total = total;
    // Fixed part of the line: two spaces, the bar, two spaces, "100%" and, for several analyses, "  Analysis k/n".
    const int console_width = Rf_asInteger(width) == NA_INTEGER ? 80 : Rf_asInteger(width);
    size_t fixed = 2 + (fresh.unicode ? kBarCells : kBarCells + 2) + 6;
    if (total > 1) fixed += 2 + 9 + 2 * std::to_string(total).size() + 1;
    const size_t room = console_width > static_cast<int>(fixed) + 12 ? static_cast<size_t>(console_width) - fixed - 1 : 12;
    fresh.label_cells = std::min(widest, room);
    fresh.start = now_seconds();
    fresh.owner = std::this_thread::get_id();
    fresh.active = true;
    g = std::move(fresh);
    return Rf_ScalarLogical(TRUE);
}

// Ends the operation: erases the line if it was shown and resets all state. Always safe to call.
SEXP rpst_progress_end(void)
{
    if (g.active && g.visible && !g.dead && g.last_cells > 0) R_ToplevelExec(write_clear, nullptr);
    g = State();
    g_fake_now = -1;
    g_fake_step = 0;
    return R_NilValue;
}

SEXP rpst_progress_active(void) { return Rf_ScalarLogical(g.active); }

// Test hook (no PST involved): op 0 = set the fake clock to `value` seconds (negative restores the real one),
// 1 = a new analysis starts, 2 = PST reports progress `value` (0..1), 3 = the fake clock advances `value` seconds per read.
SEXP rpst_progress_test(SEXP op, SEXP value)
{
    const int o = Rf_asInteger(op);
    const double v = Rf_asReal(value);
    if (o == 0) g_fake_now = v;
    else if (o == 1) { FPSTAProgressCallback cb = nullptr; void* user = nullptr; rpst::progress_attach(cb, user); }
    else if (o == 2) progress_callback(nullptr, static_cast<float>(v), nullptr);
    else if (o == 3) g_fake_step = v;
    return R_NilValue;
}
}
