native_segment <- function(name, ...) {
  .Call(get(paste0("C_rpst_segment_graph_", name), envir = asNamespace("rPSTool")), ...)
}
segment_rows <- function() rbind(c(0, 0, 3, 0), c(3, 0, 3, 3))
