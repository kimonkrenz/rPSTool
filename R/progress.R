# Console progress for long analyses (single option: options(rPSTool.progress = TRUE/FALSE)).
#
# PST reports the progress of each analysis it runs through the callback of the analysis descriptor. While an
# operation has activated progress, the native layer installs that callback (src/pst-progress.cpp); otherwise the
# callback stays null and PST does no progress work. Nothing is shown until two seconds after the operation began.
#
#   NULL (default)  progress in interactive sessions only, and not while output is being captured (sink())
#   TRUE            progress wherever the console can show it
#   FALSE           never
#
# The option is read once per top-level operation. The line shows the first result variable of the running analysis,
# as named by the central naming layer (R/naming.R), PST's own percentage for that analysis, and "Analysis k/n" when
# the operation runs several analyses (one per radius).

.pst_progress_wanted <- function() {
  opt <- getOption("rPSTool.progress")
  if (identical(opt, FALSE)) return(FALSE)
  if (identical(opt, TRUE)) return(TRUE)
  interactive() && sink.number() == 0L && !isTRUE(getOption("knitr.in.progress"))
}

# Unicode block characters only in a UTF-8 session; otherwise the ASCII bar.
.pst_progress_unicode <- function() isTRUE(l10n_info()[["UTF-8"]])

# Activate progress for the calling function's operation and end it when that function exits (also on error or
# interrupt). `labels` is the result variable of each analysis, in running order; it is only evaluated when progress
# is on. A nested call (an operation already showing progress) leaves the outer one in charge.
.pst_progress_scope <- function(labels, frame = parent.frame()) {
  if (!.pst_progress_wanted()) return(invisible(FALSE))
  started <- .Call(C_rpst_progress_begin, as.character(labels), .pst_progress_unicode(), getOption("width", 80L))
  if (!isTRUE(started)) return(invisible(FALSE))
  do.call(base::on.exit, list(quote(.Call(C_rpst_progress_end)), TRUE), envir = frame)
  invisible(TRUE)
}
