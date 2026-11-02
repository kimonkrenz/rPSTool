# Direct Parquet persistence of analysis results (see docs/spatial-io/result-files.md).
#
# The analysis runs ONCE, natively. Its finished float32/count arrays are held by an rPSTool-owned, reference-counted
# result owner and exported zero-copy as an Arrow C stream, which the optional R `arrow` package imports and writes
# to Parquet. No R result vectors or data frames are built. The file is written to a unique temporary name in the
# destination directory and published only after it is complete: with `overwrite = FALSE` by a kernel-checked
# no-clobber step (POSIX link(2); Windows MoveFileExW without MOVEFILE_REPLACE_EXISTING), with `overwrite = TRUE` by a single
# rename (POSIX rename(2); Windows MoveFileExW with MOVEFILE_REPLACE_EXISTING). See src/pst-fs-core.h.

# A path as the native layer expects it: UTF-8 on Windows (converted to UTF-16 there), the native encoding elsewhere.
.pst_native_path <- function(x) if (.Platform$OS.type == "windows") enc2utf8(x) else enc2native(x)

.pst_result_arrow_minimum <- "25.0.0"
.pst_result_batch_rows <- 1048576  # also the Parquet row-group size
.pst_result_gc_rows <- 100000

# Strict runtime capability check, before anything is computed or created. Only entry points that exist in the
# declared minimum arrow version are required; `RecordBatchReader$import_from_c` is an arrow-version-specific R6
# class function that arrow does not document, so its presence is verified at run time.
.pst_result_capabilities <- function(arrow = TRUE, what = "output_file", codec = "zstd") {
  if (!isTRUE(.Call(C_rpst_output_supported)))
    stop("Writing a result file (", what, ") is not supported on this platform: the file-publication ",
         "primitives are not available.", call. = FALSE)
  if (!arrow) return(invisible(TRUE))
  if (!requireNamespace("arrow", quietly = TRUE))
    stop("Writing a result file requires the optional package 'arrow' (>= ", .pst_result_arrow_minimum,
         "); install it to use ", what, ".", call. = FALSE)
  version <- unname(getNamespaceVersion("arrow"))
  if (numeric_version(version) < numeric_version(.pst_result_arrow_minimum))
    stop("Writing a result file requires arrow >= ", .pst_result_arrow_minimum, " (found ", version, ").",
         call. = FALSE)
  exports <- getNamespaceExports("arrow")
  missing_exports <- setdiff(c("write_parquet", "RecordBatchReader", "codec_is_available"), exports)
  if (length(missing_exports))
    stop("The installed arrow lacks required exports: ", paste(missing_exports, collapse = ", "), ".", call. = FALSE)
  reader <- getExportedValue("arrow", "RecordBatchReader")
  if (!is.function(reader$import_from_c))
    stop("The installed arrow has no RecordBatchReader$import_from_c(), which is required to read the native result.",
         call. = FALSE)
  if (!isTRUE(getExportedValue("arrow", "codec_is_available")(codec)))
    stop("The installed arrow was built without ", codec, " support, which result files use.", call. = FALSE)
  invisible(TRUE)
}

.pst_flag <- function(x, name) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) stop(name, " must be TRUE or FALSE.", call. = FALSE)
  x
}

# Validate the destination and return its absolute path. Creates nothing.
.pst_check_output_file <- function(output_file, overwrite, arg = "output_file") {
  if (!is.character(output_file) || length(output_file) != 1L || is.na(output_file) || !nzchar(output_file))
    stop(arg, " must be one non-empty, non-missing path.", call. = FALSE)
  path <- path.expand(output_file)
  dir <- dirname(path)
  if (!dir.exists(dir)) stop("The directory of ", arg, " does not exist: ", dir, call. = FALSE)
  if (dir.exists(path)) stop(arg, " is a directory: ", path, call. = FALSE)
  target <- file.path(normalizePath(dir, winslash = "/", mustWork = TRUE), basename(path))
  # file.exists() is FALSE for a dangling symbolic link, which is nevertheless an existing directory entry
  if (!overwrite && (file.exists(target) || isTRUE(.Call(C_rpst_output_entry_exists, .pst_native_path(target)))))
    stop(arg, " already exists; use overwrite = TRUE to replace it: ", target, call. = FALSE)
  target
}

# A unique temporary file in `dir`, created exclusively (never a pre-existing file or symlink).
.pst_result_temp_file <- function(dir) {
  for (attempt in seq_len(20L)) {
    candidate <- tempfile(pattern = ".rpst-", tmpdir = dir, fileext = ".partial")
    message <- .Call(C_rpst_output_create_exclusive, .pst_native_path(candidate))
    if (!nzchar(message)) return(candidate)
    if (!file.exists(candidate))
      stop("Cannot create a temporary file in ", dir, ": ", message, call. = FALSE)
  }
  stop("Cannot create a unique temporary file in ", dir, ".", call. = FALSE)
}

.pst_json_string <- function(x) {
  x <- gsub("\\", "\\\\", enc2utf8(x), fixed = TRUE)
  x <- gsub("\"", "\\\"", x, fixed = TRUE)
  x <- gsub("\n", "\\n", x, fixed = TRUE)
  x <- gsub("\r", "\\r", x, fixed = TRUE)
  x <- gsub("\t", "\\t", x, fixed = TRUE)
  paste0("\"", x, "\"")
}
# An explicit JSON array (rpst:schema 2); `items` is a list of values already convertible by .pst_json.
.pst_json_array <- function(items) structure(as.list(items), class = "pst_json_array")
.pst_json <- function(x) {
  if (is.null(x)) return("null")
  if (inherits(x, "pst_json_array"))
    return(paste0("[", paste0(vapply(unclass(x), .pst_json, ""), collapse = ","), "]"))
  if (is.list(x)) {
    if (!length(x)) return("{}")
    paste0("{", paste0(vapply(names(x), .pst_json_string, ""), ":", vapply(x, .pst_json, ""), collapse = ","), "}")
  } else if (is.logical(x)) tolower(as.character(x))
  else if (is.numeric(x)) sprintf("%.17g", x)
  else .pst_json_string(as.character(x))
}

# Compact, useful file metadata (Parquet key/value metadata via the Arrow schema).
.pst_result_metadata <- function(fn, parameters, graph_type, rows, graph,
                                 order = "native graph order (source feature order); no external feature identifiers",
                                 float_columns = TRUE, cols = NULL) {
  crs <- attr(graph, "crs", exact = TRUE)
  wkt <- if (is.list(crs) && is.character(crs$wkt) && length(crs$wkt) == 1L && !is.na(crs$wkt)) crs$wkt else ""
  status <- .pst_engine_pin()
  md <- c("rpst:schema" = "1",
    "rpst:version" = as.character(getNamespaceVersion("rPSTool")),
    "rpst:pst_version" = unname(status[["pst_version"]]),
    "rpst:pst_commit" = unname(status[["pst_commit"]]),
    "rpst:function" = fn,
    "rpst:parameters" = .pst_json(parameters),
    "rpst:graph_type" = graph_type,
    "rpst:graph_rows" = as.character(rows),
    "rpst:crs_wkt" = wkt,
    "rpst:id_base" = "1",
    "rpst:order" = order)
  # only tables that actually hold native single-precision columns say so (Segment Grouping has none: all int32)
  if (float_columns) md <- c(md, "rpst:float_columns" = "float32: PST native single precision, widened exactly to double by R")
  if (!is.null(cols))   # column manifest (docs/output-naming.md); the names are labels, this is the authoritative description
    md <- c(md, "rpst:naming" = "1", "rpst:columns" = .pst_json(.pst_nm_manifest(cols)))
  md
}

# Publish a completed temporary file: a kernel-checked no-clobber step with overwrite = FALSE, a single rename with overwrite = TRUE.
.pst_publish_temp <- function(temp, target, overwrite, arg = "output_file") {
  outcome <- .Call(C_rpst_output_publish, .pst_native_path(temp), .pst_native_path(target), overwrite)
  if (identical(outcome, "exists"))
    stop(arg, " was created by another process while the result was being written; it was not replaced: ",
         target, call. = FALSE)
  if (startsWith(outcome, "published, but")) {
    warning(arg, " was written, but ", sub("^published, but ", "", outcome), call. = FALSE)
  } else if (nzchar(outcome)) {
    stop("Cannot publish the result file: ", outcome, call. = FALSE)
  }
  invisible(TRUE)
}

# Run `export(stream)` (the native analysis, which fills an rPSTool-owned Arrow C stream) and publish its Parquet file.
# Everything that can fail cheaply (path, overwrite flag, arrow capability) is checked before the analysis runs;
# nothing is created on disk until the analysis has succeeded; any failure afterwards removes the temporary file and
# leaves a pre-existing destination untouched.
.pst_write_result_file <- function(output_file, overwrite, export, columns, expected_rows,
                                   batch_rows = .pst_result_batch_rows,
                                   spatial_output_file = NULL, graph = NULL, metadata = NULL) {
  overwrite <- .pst_flag(overwrite, "overwrite")
  if (!is.null(spatial_output_file))   # a NEW spatial dataset instead of the attribute-only file (R/spatial-output.R)
    return(.pst_write_spatial_file(spatial_output_file, overwrite, graph, export, columns, expected_rows, metadata,
                                   batch_rows))
  target <- .pst_check_output_file(output_file, overwrite)
  .pst_result_capabilities()
  stream <- .Call(C_rpst_arrow_stream_new)
  on.exit(.Call(C_rpst_arrow_stream_free, stream), add = TRUE)
  native_rows <- export(stream, as.double(batch_rows))  # the single analysis; native errors stop here
  # Analyses whose row count is a native property (origins of a chosen kind) report it; the angular pair returns NULL.
  if (is.numeric(native_rows) && length(native_rows) == 1L) expected_rows <- native_rows
  temp <- .pst_result_temp_file(dirname(target))
  published <- FALSE
  on.exit(if (!published) unlink(temp), add = TRUE)
  reader <- getExportedValue("arrow", "RecordBatchReader")$import_from_c(stream)
  table <- reader$read_table()
  rows <- table$num_rows
  getExportedValue("arrow", "write_parquet")(table, temp, compression = "zstd",
                                             chunk_size = as.integer(batch_rows))
  rm(table, reader)
  # Large results: collect now so arrow drops its references and the native result is freed promptly (a full
  # collection costs ~0.1 s, so small results are simply left to the next ordinary collection).
  if (rows >= .pst_result_gc_rows) invisible(gc(verbose = FALSE))
  if (!identical(as.double(rows), as.double(expected_rows)))
    stop("The Parquet table has an unexpected number of rows; the file was not published.", call. = FALSE)
  if (!isTRUE(file.size(temp) > 0))
    stop("The temporary Parquet file is empty; the file was not published.", call. = FALSE)
  .pst_publish_temp(temp, target, overwrite)
  published <- TRUE
  structure(list(path = target, rows = as.integer(rows), columns = columns, format = "parquet"),
            class = "pst_result_file")
}

#' Writing analysis results to files
#'
#' The analysis functions can write their results to a file instead of returning a data frame, by setting `output_file`
#' (a Parquet table) or `spatial_output_file` (a new spatial dataset). They then return, invisibly, a descriptor of the
#' file. Use this for results too large to hold comfortably in R or to hand over to other software.
#'
#' @details
#' **`output_file`.** Writes the same columns, in the same order and graph order, as the data frame the function would return.
#' PST's single-precision values are stored as float32, which reads back in R as exactly the doubles the data frame holds;
#' counts and the one-based positional identifier are int32. The file's metadata (`rpst:*` keys) records the rPSTool and PST
#' versions and commit, the function and its parameters, the graph type and size, the CRS and the identifier convention. It
#' needs the suggested package 'arrow' (>= 25.0.0).
#'
#' **`spatial_output_file`.** Writes a new spatial dataset containing the geometry and attributes of the file the graph was built
#' from, plus the result columns, matched to the source features by position (no spatial join). The format is always that of the
#' source (GeoParquet to GeoParquet, FlatGeobuf to FlatGeobuf), and the CRS and geometry are carried over unchanged. A result
#' column named like a source column replaces it; other result columns are appended. The destination must end in `.parquet`
#' (GeoParquet source) or `.fgb` (FlatGeobuf source), in any letter case. It is mutually exclusive with `output_file`, needs a
#' graph built from a file path, and some analyses restrict it to one result per network line (see each function). The source file
#' must not be modified or reordered after the graph is built. See
#' <https://github.com/kimonkrenz/rPSTool/blob/main/docs/spatial-io/spatial-output.md>.
#'
#' **`overwrite`.** With `overwrite = FALSE` (default) an existing destination is never replaced; with `TRUE` it is replaced. Files
#' are written under a temporary name and published only when complete, so replacement is a single rename and the old file is
#' untouched if anything fails. No guarantee of durability after a crash is made. With `spatial_output_file`, `overwrite = TRUE` additionally allows result columns that already exist in the source to be replaced in the new file; with `FALSE` such a collision is an error raised before the analysis. `overwrite` never modifies the source.
#'
#' **Descriptor.** The descriptor is a list with the absolute `path`, the number of `rows`, the `columns` in file order and the
#' `format` (`"parquet"`). For `spatial_output_file` it additionally has `spatial = TRUE`, the `source` network path, the
#' `geometry_column` (GeoParquet), and the result columns that `replaced` a source column or were `appended`. `columns` then
#' lists the non-geometry columns of the new dataset and `format` is `"flatgeobuf"` or `"geoparquet"`. The results themselves are
#' not held in R. Details of the file layout: <https://github.com/kimonkrenz/rPSTool/blob/main/docs/spatial-io/result-files.md>.
#'
#' @section Limitations:
#' On Windows, replacing an existing file fails, leaving the old file intact, while another process holds the destination open
#' without allowing it to be deleted. Result-file writing uses the Win32 API on Windows and POSIX calls elsewhere.
#'
#' @name pst_result_file
#' @rdname pst_result_file
#' @aliases pst_result_file
#' @param x A `pst_result_file`.
#' @param ... Unused.
#' @return `x`, invisibly. The `print()` method shows one line with the path, row count, columns and format.
#' @export
#' @examples
#' # Result files need the suggested package 'arrow' (>= 25.0.0).
#' if (requireNamespace("arrow", quietly = TRUE) &&
#'     utils::packageVersion("arrow") >= "25.0.0") {
#'   g <- segment_graph(cbind(0:4 * 3, 0, 1:5 * 3, 0))
#'   f <- angular_choice(g, output_file = tempfile(fileext = ".parquet"))
#'   f
#'   unlink(f$path)
#' }
print.pst_result_file <- function(x, ...) {
  cat(sprintf("<pst_result_file> %s: %d rows, columns %s (%s)\n", x$path, x$rows,
              paste(x$columns, collapse = ", "), x$format))
  invisible(x)
}

.pst_radius_parameters <- function(radius_or_steps) {
  if (inherits(radius_or_steps, "pst_radius")) unclass(radius_or_steps) else list(steps = radius_or_steps)
}

# File route of the axial-graph analyses: the metadata and the single shared writer. `call` runs
# the analysis' own native stream entry point as call(stream, column_names, metadata_names, metadata_values,
# batch_rows); the row count comes back from that native call.
.pst_axial_result_file <- function(output_file, overwrite, fn, parameters, graph, ptr, columns, order, call,
                                   graph_type = "axial", rows = NULL, spatial_output_file = NULL, cols = NULL) {
  # Native size of the graph, never editable R metadata: lines for an axial graph (default), or the caller's native count.
  if (is.null(rows)) rows <- .Call(C_rpst_graph_info, ptr)[[1L]]
  metadata <- .pst_result_metadata(fn, parameters, graph_type, rows, graph, order, cols = cols)
  invisible(.pst_write_result_file(
    output_file, overwrite, columns = columns, expected_rows = NA_real_,
    export = function(stream, batch_rows) call(stream, columns, names(metadata), unname(metadata), batch_rows),
    spatial_output_file = spatial_output_file, graph = graph, metadata = metadata))
}
.pst_count_or_null <- function(x) if (is.null(x)) NULL else length(x)
