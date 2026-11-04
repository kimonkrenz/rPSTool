# Spatial output (see docs/spatial-io/spatial-output.md): a NEW GeoParquet or FlatGeobuf file holding the ORIGINAL
# source geometry and attributes plus the PST result columns, written by `spatial_output_file`. The analysis runs once; its
# native result arrays are paired with the source features POSITIONALLY (feature i <-> result row i, physical file order).
# No spatial join, no R sf object, no second calculation. The output format always equals the source format (an intentional
# requirement), the CRS and geometry are carried over unchanged, and the source file is only ever read.

# ---- source provenance recorded on file-built graphs ----------------------------------------------------------------
# Lightweight facts only (never geometry): enough to find the file again and to notice that it obviously changed. They do
# NOT prove content identity.
.pst_source_record <- function(path, format, rows) {
  info <- file.info(path)
  id <- .Call(C_rpst_file_identity, .pst_native_path(path))   # c(device, inode) as exact strings (NA when unavailable)
  list(path = path, format = format, rows = as.double(rows), size = as.double(info$size),
       mtime = as.numeric(info$mtime), device = id[[1L]], inode = id[[2L]])
}

# Attach the provenance to a freshly built path graph. `rows` is the graph's native row count.
.pst_attach_source <- function(graph, path, format) {
  rows <- if (!is.null(graph$n_segments)) graph$n_segments else graph$n_lines
  attr(graph, "source") <- .pst_source_record(path, format, rows)
  graph
}

# The recorded source, re-checked against the file system NOW. Errors if the graph was not built from a file path, or if the
# file's size, modification time or (where the platform provides it) device/inode differs from graph-construction time.
.pst_spatial_source <- function(graph, arg = "spatial_output_file") {
  src <- attr(graph, "source", exact = TRUE)
  if (is.null(src))
    stop(arg, " requires a graph built from a GeoParquet or FlatGeobuf file path: the original geometry and attributes ",
         "are re-read from that file. This graph was built from in-memory input (matrix or sf).", call. = FALSE)
  .pst_spatial_source_unchanged(src)
  src
}

.pst_spatial_source_unchanged <- function(src) {
  info <- file.info(src$path)
  id <- .Call(C_rpst_file_identity, .pst_native_path(src$path))
  same_id <- (is.na(src$device) && is.na(src$inode)) || (identical(id[[1L]], src$device) && identical(id[[2L]], src$inode))
  if (is.na(info$size) || !isTRUE(info$size == src$size) || !isTRUE(as.numeric(info$mtime) == src$mtime) || !same_id)
    stop("The source file changed after the graph was built (size, modification time or file identity differs): ", src$path,
         ". Spatial results are associated with the source network's feature order at graph construction, so the source ",
         "must not be modified or reordered until the spatial output is complete. Rebuild the graph from the current file.",
         call. = FALSE)
  invisible(TRUE)
}

# Refuse a destination that is the source network itself: the same path, a symbolic link to it, or a hard link to it.
# The (device, inode) identity (exact strings; POSIX st_dev/st_ino, Windows volume serial number and file ID) catches every
# spelling of the path, links and, on Windows, case and short-name aliases; the path comparison covers the rest. Neither check
# is a guarantee against every aliasing scheme (for example a bind mount on another path with a different device number) or
# against a race between the check and the publication.
.pst_check_spatial_destination <- function(target, src) {
  fold <- if (.Platform$OS.type == "windows") tolower else identity   # Windows paths are case-insensitive
  same_path <- identical(target, src$path) ||
    (file.exists(target) && identical(fold(normalizePath(target, winslash = "/", mustWork = FALSE)),
                                      fold(normalizePath(src$path, winslash = "/", mustWork = FALSE))))
  id <- .Call(C_rpst_file_identity, .pst_native_path(target))
  same_file <- !is.na(id[[1L]]) && !is.na(src$device) && identical(id[[1L]], src$device) && identical(id[[2L]], src$inode)
  if (same_path || same_file)
    stop("spatial_output_file is the source network itself (", src$path, "). Spatial output always creates a NEW file ",
         "and never modifies the source; choose a different destination (overwrite does not apply to the source).",
         call. = FALSE)
  invisible(TRUE)
}

# The destination's extension must match the (content-detected) source format, so a file never carries a misleading name:
# `.fgb` for FlatGeobuf, `.parquet` for GeoParquet (case-insensitive). Nothing is renamed or converted; the format is still
# identified from the SOURCE's bytes, never from an extension.
.pst_spatial_extensions <- c(flatgeobuf = "fgb", geoparquet = "parquet")
.pst_check_spatial_extension <- function(target, format) {
  expected <- .pst_spatial_extensions[[format]]
  found <- tolower(tools::file_ext(target))
  if (!identical(found, expected))
    stop("spatial_output_file must end in '.", expected, "' because the source network is ",
         c(flatgeobuf = "FlatGeobuf", geoparquet = "GeoParquet")[[format]], " and the output uses the same format (found ",
         if (nzchar(found)) paste0("'.", found, "'") else "no extension", "): ", basename(target),
         ". The destination is never renamed and the format is never changed.", call. = FALSE)
  invisible(TRUE)
}

# Validate `spatial_output_file` for one analysis call, before anything is computed. `eligible` is FALSE (with `reason`) for
# the modes of an analysis whose rows are not one-to-one with the source features.
.pst_spatial_request <- function(output_file, spatial_output_file, eligible = TRUE, reason = "") {
  if (is.null(spatial_output_file)) return(invisible(FALSE))
  if (!is.null(output_file))
    stop("output_file and spatial_output_file are mutually exclusive: output_file writes the results alone (attribute-only ",
         "Parquet), spatial_output_file writes a new spatial dataset with the original geometry and attributes.", call. = FALSE)
  if (!isTRUE(eligible))
    stop("spatial_output_file is not available for ", reason, ": its rows are not one-to-one with the source features. ",
         "Use output_file for such results.", call. = FALSE)
  invisible(TRUE)
}

# ---- checks that need only the source's schema, run BEFORE the analysis so a doomed write wastes no compute ---------------
# (The writers repeat the essential ones: the native FlatGeobuf writer remains the authority for its column plan.)
.pst_spatial_parquet_capabilities <- function() {
  need <- c("ParquetFileReader", "ReadableFile", "ParquetFileWriter", "ParquetWriterProperties", "FileOutputStream", "Table", "schema")
  missing_exports <- setdiff(need, getNamespaceExports("arrow"))
  if (length(missing_exports))
    stop("The installed arrow lacks exports required for spatial output: ", paste(missing_exports, collapse = ", "), ".", call. = FALSE)
  if (!requireNamespace("jsonlite", quietly = TRUE))
    stop("Writing a GeoParquet spatial output requires the package 'jsonlite' (already needed to read GeoParquet).", call. = FALSE)
  invisible(TRUE)
}
# Result columns that already exist in the source: with overwrite = FALSE this is an error naming them; with overwrite = TRUE
# they are replaced in the NEW file (the source is never modified).
.pst_spatial_existing_columns <- function(source_names, result_names, overwrite) {
  # a source column that differs from a result name only by letter case is ambiguous for case-insensitive readers: never
  # replaced or duplicated, with or without overwrite
  case_only <- source_names[tolower(source_names) %in% tolower(result_names) & !(source_names %in% result_names)]
  if (length(case_only))
    stop("The source column '", case_only[[1L]], "' differs from the result column '",
         result_names[match(tolower(case_only[[1L]]), tolower(result_names))],
         "' only by letter case; replacing or adding it would be ambiguous for case-insensitive readers. Rename the source ",
         "column; overwrite does not apply.", call. = FALSE)
  existing <- intersect(result_names, source_names)
  if (length(existing) && !isTRUE(overwrite))
    stop("Analysis output columns already exist in the source: ", paste(existing, collapse = ", "),
         ". Use overwrite = TRUE to replace them in the new output file; the source file is never modified.", call. = FALSE)
  invisible(existing)
}
.pst_spatial_preflight <- function(src, result_names, overwrite = FALSE) {
  if (anyDuplicated(tolower(result_names))) stop("Two result columns have the same name.", call. = FALSE)
  if (identical(src$format, "flatgeobuf")) {
    cols <- .Call(C_rpst_fgb_columns, .pst_native_path(src$path))
    low <- tolower(cols$name)
    if (anyDuplicated(low)) {
      d <- cols$name[low %in% low[duplicated(low)]]
      stop("The source has the columns '", d[[1L]], "' and '", d[[2L]], "', which are identical or differ only by letter case; ",
           "FlatGeobuf readers look fields up case-insensitively, so the output would be ambiguous.", call. = FALSE)
    }
    if (any(cols$type > 14L)) stop("A source column has an unknown FlatGeobuf column type; its values cannot be copied safely.", call. = FALSE)
    .pst_spatial_existing_columns(cols$name, result_names, overwrite)
    clash <- which(low %in% tolower(result_names) & !(cols$name %in% result_names))
    if (length(clash))
      stop("The result column '", result_names[match(low[clash[[1L]]], tolower(result_names))], "' differs from the source column '",
           cols$name[[clash[[1L]]]], "' only by letter case; FlatGeobuf readers look fields up case-insensitively, so replacing or ",
           "adding it would be ambiguous.", call. = FALSE)
    if (length(unique(c(cols$name, result_names))) > 65535L) stop("The output would have more than 65535 columns.", call. = FALSE)
  } else {
    source <- .pst_parquet_source_open(src$path)
    on.exit(source$file$close(), add = TRUE)   # the source is not held open beyond this check
    reader <- source$reader
    schema <- reader$GetSchema()
    if (!identical(as.double(reader$num_rows), src$rows))
      stop("The source has ", reader$num_rows, " rows but the graph was built from ", src$rows, "; it changed since the graph was built.", call. = FALSE)
    if (anyDuplicated(schema$names))
      stop("The source has duplicate column names (", paste(unique(schema$names[duplicated(schema$names)]), collapse = ", "),
           "); the output would be ambiguous.", call. = FALSE)
    geo <- tryCatch(jsonlite::fromJSON(schema$metadata$geo, simplifyVector = FALSE), error = function(e) NULL)
    primary <- geo$primary_column
    if (!is.character(primary) || length(primary) != 1L || !(primary %in% schema$names))
      stop("The source's GeoParquet metadata no longer names a geometry column.", call. = FALSE)
    if (primary %in% result_names)
      stop("A result column has the name of the geometry column ('", primary, "').", call. = FALSE)
    .pst_spatial_existing_columns(schema$names, result_names, overwrite)
  }
  invisible(TRUE)
}

# ---- the two format writers ------------------------------------------------------------------------------------------
# FlatGeobuf: one native pass (src/pst-flatgeobuf.cpp) that consumes the analysis' result stream directly.
.pst_spatial_write_flatgeobuf <- function(src, stream, temp, result_names, metadata, rows) {
  source_names <- .Call(C_rpst_fgb_columns, .pst_native_path(src$path))$name
  written <- .Call(C_rpst_fgb_write_spatial, stream, .pst_native_path(src$path), .pst_native_path(temp), result_names,
                   as.double(rows), names(metadata), unname(metadata))
  columns <- .Call(C_rpst_fgb_columns, .pst_native_path(temp))$name
  list(rows = written, columns = columns, geometry_column = NULL,
       replaced = intersect(result_names, source_names), appended = setdiff(result_names, source_names))
}

# GeoParquet: row group by row group through R arrow's incremental ParquetFileWriter. The source row groups are decoded one at a
# time (peak = one source row group); the result columns are zero-copy slices of the table imported from the native stream; the
# geometry column and the 'geo' metadata pass through unchanged, so CRS, bbox and covering stay valid.
# zstd, as for output_file.
.pst_spatial_parquet_codec <- "zstd"
.pst_spatial_gc_groups <- 4L   # collect garbage every this many source row groups
.pst_spatial_write_geoparquet <- function(src, stream, temp, result_names, metadata, rows) {
  arrow <- function(name) getExportedValue("arrow", name)
  source <- .pst_parquet_source_open(src$path)
  on.exit(try(source$file$close(), silent = TRUE), add = TRUE)   # closed on every exit, before the caller publishes
  reader <- source$reader
  if (!identical(as.double(reader$num_rows), as.double(rows)))
    stop("The source has ", reader$num_rows, " rows but the analysis produced ", rows,
         " result rows; it changed since the graph was built.", call. = FALSE)
  schema <- reader$GetSchema()
  source_names <- schema$names
  if (anyDuplicated(source_names))
    stop("The source has duplicate column names (", paste(unique(source_names[duplicated(source_names)]), collapse = ", "),
         "); the output would be ambiguous.", call. = FALSE)
  geo <- tryCatch(jsonlite::fromJSON(schema$metadata$geo, simplifyVector = FALSE), error = function(e) NULL)
  geometry_column <- geo$primary_column
  if (!is.character(geometry_column) || length(geometry_column) != 1L || !(geometry_column %in% source_names))
    stop("The source's GeoParquet metadata no longer names a geometry column.", call. = FALSE)
  if (geometry_column %in% result_names)
    stop("A result column has the name of the geometry column ('", geometry_column, "').", call. = FALSE)
  if (anyDuplicated(result_names)) stop("Two result columns have the same name.", call. = FALSE)

  result <- arrow("RecordBatchReader")$import_from_c(stream)$read_table()   # zero-copy over the native result
  result_fields <- result$schema$fields[-1L]                                   # drop the positional id column
  if (!identical(vapply(result_fields, function(f) f$name, ""), result_names))
    stop("The result stream's columns do not match the requested result names.", call. = FALSE)
  fields <- schema$fields
  for (k in seq_along(result_names)) {
    at <- match(result_names[[k]], source_names)
    if (is.na(at)) fields <- c(fields, list(result_fields[[k]])) else fields[[at]] <- result_fields[[k]]
  }
  out_schema <- do.call(arrow("schema"), fields)
  md <- schema$metadata
  md[names(metadata)] <- as.list(unname(metadata))                              # rpst:* keys; 'geo' and the rest untouched
  out_schema <- out_schema$WithMetadata(md)
  out_names <- names(out_schema)

  sink <- arrow("FileOutputStream")$create(temp)
  on.exit(try(sink$close(), silent = TRUE), add = TRUE)   # also on an interrupt or an early error (closing twice is harmless)
  writer <- arrow("ParquetFileWriter")$create(
    out_schema, sink, properties = arrow("ParquetWriterProperties")$create(out_names, compression = .pst_spatial_parquet_codec))
  offset <- 0
  groups_written <- 0L
  tryCatch({
    for (g in seq_len(reader$num_row_groups) - 1L) {
      part <- reader$ReadRowGroup(g)
      m <- part$num_rows
      if (m == 0) next
      columns <- lapply(out_names, function(nm) {
        k <- match(nm, result_names)
        if (is.na(k)) part$GetColumnByName(nm) else result$column(k)$Slice(offset, m)   # k-th result column (id is column 0)
      })
      names(columns) <- out_names
      writer$WriteTable(do.call(arrow("Table")$create, c(columns, list(schema = out_schema))), chunk_size = m)
      offset <- offset + m
      # Arrow row groups and tables are small R objects over large C++ buffers, so R's collector does not run in step with the
      # Arrow pool: collect every few row groups so that dead ones cannot pile up.
      rm(part, columns)
      groups_written <- groups_written + 1L
      if (groups_written %% .pst_spatial_gc_groups == 0L) invisible(gc(verbose = FALSE))
    }
    writer$Close()
    sink$close()
  }, error = function(e) { try(sink$close(), silent = TRUE); stop(e) })
  rm(result, reader)
  source$file$close()
  if (!identical(as.double(offset), as.double(rows)))
    stop("The spatial output has an unexpected number of rows; the file was not published.", call. = FALSE)
  list(rows = offset, columns = setdiff(out_names, geometry_column), geometry_column = geometry_column,
       replaced = intersect(result_names, source_names), appended = setdiff(result_names, source_names))
}

# The analysis runs once; its result is paired with the source and written to a temporary file that is published by a single rename
# only when complete (the same primitives as output_file). Nothing is created before the analysis succeeds.
.pst_write_spatial_file <- function(spatial_output_file, overwrite, graph, export, columns, expected_rows, metadata,
                                    batch_rows = .pst_result_batch_rows) {
  src <- .pst_spatial_source(graph)
  target <- .pst_check_output_file(spatial_output_file, overwrite, "spatial_output_file")
  .pst_check_spatial_extension(target, src$format)
  .pst_check_spatial_destination(target, src)
  .pst_result_capabilities(arrow = identical(src$format, "geoparquet"), what = "spatial_output_file",
                           codec = .pst_spatial_parquet_codec)
  if (identical(src$format, "geoparquet")) .pst_spatial_parquet_capabilities()
  result_names <- columns[-1L]   # the first column is the implicit positional id; the source keeps its own identifiers
  .pst_spatial_preflight(src, result_names, overwrite)
  stream <- .Call(C_rpst_arrow_stream_new)
  on.exit(.Call(C_rpst_arrow_stream_free, stream), add = TRUE)
  native_rows <- export(stream, as.double(batch_rows))   # the single analysis
  if (is.numeric(native_rows) && length(native_rows) == 1L) expected_rows <- native_rows
  if (!identical(as.double(expected_rows), src$rows))
    stop("The analysis has ", expected_rows, " result rows but the source network has ", src$rows,
         " features: this analysis' rows are not one-to-one with the source features.", call. = FALSE)
  .pst_spatial_source_unchanged(src)   # the source must still be what the graph was built from
  temp <- .pst_result_temp_file(dirname(target))
  published <- FALSE
  on.exit(if (!published) unlink(temp), add = TRUE)
  written <- switch(src$format,
                    flatgeobuf = .pst_spatial_write_flatgeobuf(src, stream, temp, result_names, metadata, expected_rows),
                    geoparquet = .pst_spatial_write_geoparquet(src, stream, temp, result_names, metadata, expected_rows))
  if (!identical(as.double(written$rows), src$rows) || !isTRUE(file.size(temp) > 0))
    stop("The spatial output is incomplete; the file was not published.", call. = FALSE)
  .pst_spatial_source_unchanged(src)   # and was not modified while the output was written
  .pst_publish_temp(temp, target, overwrite, "spatial_output_file")
  published <- TRUE
  structure(list(path = target, rows = as.integer(written$rows), columns = written$columns, format = src$format,
                 spatial = TRUE, source = src$path, geometry_column = written$geometry_column,
                 replaced = written$replaced, appended = written$appended),
            class = "pst_result_file")
}
