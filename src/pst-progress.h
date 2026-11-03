// Console progress for the PST analyses (see R/progress.R). PST already reports progress through the
// FPSTAProgressCallback of every analysis descriptor, always on the thread that called the analysis (the R main
// thread): the parallel analyses poll their futures from it and the sequential ones report from their own loop.
// This file only installs a callback in the descriptor while an R-level operation has activated progress; when
// progress is off the descriptor keeps its pinned null callback and PST does no progress work.
#pragma once
#include <pstalgo/pstalgo.h>

namespace rpst {
// Install the progress callback in a descriptor and count one analysis (one PST call). No-op when progress is off.
void progress_attach(FPSTAProgressCallback& callback, void*& user_data);
}
