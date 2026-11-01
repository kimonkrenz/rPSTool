# GeoParquet path input for segment_graph() (see
# docs/spatial-io/geoparquet-input.md). Optional packages: arrow (>= 25.0.0) reads the file and
# exports an Arrow C stream; jsonlite parses the GeoParquet `geo` metadata; sf interprets the
# CRS. All of that happens BEFORE any native pointer exists. The native decoder then consumes
# the stream and builds the graph through the shared segment-graph builder.

.pst_arrow_minimum <- "25.0.0"

# Packages and R-level capabilities this route needs. Raises a clear error before any native
# pointer is created. Only documented/exported arrow entry points are used (no arrow:::).
.pst_geoparquet_capabilities <- function(api = "segment_graph") {
  for (pkg in c("arrow", "jsonlite", "sf")) {
    if (!requireNamespace(pkg, quietly = TRUE))
      stop("Reading a GeoParquet path requires the optional package '", pkg,
           "'; install it to use ", api, "() with a file path.", call. = FALSE)
  }
  arrow_version <- unname(getNamespaceVersion("arrow"))
  if (numeric_version(arrow_version) < numeric_version(.pst_arrow_minimum))
    stop("Reading a GeoParquet path requires arrow >= ", .pst_arrow_minimum,
         " (found ", arrow_version, ").", call. = FALSE)
  exports <- getNamespaceExports("arrow")
  needed <- c("open_dataset", "Scanner", "as_record_batch_reader", "ParquetFileReader", "ReadableFile",
              "RecordBatchReader")
  missing_exports <- setdiff(needed, exports)
  if (length(missing_exports))
    stop("The installed arrow lacks required exports: ",
         paste(missing_exports, collapse = ", "), ".", call. = FALSE)
  if (!is.function(arrow::RecordBatchReader$public_methods$export_to_c))
    stop("The installed arrow RecordBatchReader has no export_to_c() method.", call. = FALSE)
  invisible(TRUE)
}

# The single place that depends on RecordBatchReader$export_to_c(). The reader is exported
# once into the rPSTool-owned stream and must never be consumed afterwards.
.pst_geoparquet_export_reader <- function(reader, stream) {
  if (!inherits(reader, "RecordBatchReader") || !is.function(reader$export_to_c))
    stop("The installed arrow did not return a RecordBatchReader with export_to_c().",
         call. = FALSE)
  reader$export_to_c(stream)
  invisible(NULL)
}

# Scanner compatibility is established by the public generic itself, with a clear rPSTool error.
.pst_geoparquet_open_reader <- function(scanner) {
  tryCatch(arrow::as_record_batch_reader(scanner),
           error = function(e)
             stop("The installed arrow could not convert a Scanner to a RecordBatchReader: ",
                  conditionMessage(e), call. = FALSE))
}

# Parse and validate the GeoParquet `geo` metadata. Returns the primary column name and the
# graph CRS (sf crs object, possibly the unknown crs). Does not trust geometry_types.
.pst_geoparquet_metadata <- function(json, schema_names) {
  if (!is.character(json) || length(json) != 1L || is.na(json))
    stop("The file has no GeoParquet 'geo' metadata; it is not a GeoParquet file.", call. = FALSE)
  geo <- tryCatch(jsonlite::fromJSON(json, simplifyVector = FALSE),
                  error = function(e) stop("The GeoParquet 'geo' metadata is not valid JSON: ",
                                           conditionMessage(e), call. = FALSE))
  if (!is.list(geo) || is.null(names(geo)))
    stop("The GeoParquet 'geo' metadata must be a JSON object.", call. = FALSE)
  version <- geo$version
  if (!is.character(version) || length(version) != 1L || is.na(version))
    stop("The GeoParquet 'geo' metadata has no 'version' string.", call. = FALSE)
  if (!grepl("^1\\.[01]\\.[0-9]+$", version))
    stop("Unsupported GeoParquet version '", version,
         "'; only GeoParquet 1.0 and 1.1 are supported.", call. = FALSE)
  primary <- geo$primary_column
  if (!is.character(primary) || length(primary) != 1L || is.na(primary) || !nzchar(primary))
    stop("The GeoParquet 'primary_column' must be one non-empty string.", call. = FALSE)
  columns <- geo$columns
  if (!is.list(columns) || is.null(names(columns)))
    stop("The GeoParquet 'columns' metadata must be a JSON object.", call. = FALSE)
  if (!(primary %in% names(columns)))
    stop("The GeoParquet primary column '", primary, "' is not described in 'columns'.",
         call. = FALSE)
  column <- columns[[primary]]
  if (!is.list(column))
    stop("The GeoParquet metadata of the primary column must be a JSON object.", call. = FALSE)
  if (!identical(column$encoding, "WKB"))
    stop("Unsupported GeoParquet geometry encoding; only \"WKB\" is supported.", call. = FALSE)
  if (!(primary %in% schema_names))
    stop("The GeoParquet primary column '", primary, "' is not a column of the file.",
         call. = FALSE)
  if ("edges" %in% names(column) && !identical(column$edges, "planar"))
    stop("Unsupported GeoParquet 'edges' value; PST requires planar edges (absent or \"planar\"); spherical edges are rejected.",
         call. = FALSE)

  # CRS: key absent => the GeoParquet default OGC:CRS84 (geographic, rejected); present and
  # null => deliberately unknown (allowed); object => interpreted through sf.
  if (!("crs" %in% names(column)))
    stop("The GeoParquet column has no 'crs' key, which means the default OGC:CRS84 (geographic longitude/latitude). Geographic CRS is unsupported: store projected coordinates with an explicit CRS (or an explicit null CRS), or transform them first.",
         call. = FALSE)
  crs_meta <- column$crs
  if (is.null(crs_meta)) {
    crs <- sf::st_crs(NA)
  } else {
    if (!is.list(crs_meta) || is.null(names(crs_meta)))
      stop("The GeoParquet 'crs' must be null or a PROJJSON object.", call. = FALSE)
    text <- jsonlite::toJSON(crs_meta, auto_unbox = TRUE, digits = NA, null = "null")
    crs <- tryCatch(suppressWarnings(sf::st_crs(as.character(text))),
                    error = function(e) NA)
    if (!inherits(crs, "crs") || is.na(crs))
      stop("The GeoParquet 'crs' could not be interpreted as PROJJSON by sf.", call. = FALSE)
    if (isTRUE(sf::st_is_longlat(crs)))
      stop("Geographic longitude/latitude CRS is unsupported; supply projected coordinates (no CRS transformation is performed).",
           call. = FALSE)
  }
  list(primary = primary, crs = crs)
}

# Returns the new graph for one GeoParquet file. `target` is "segment" (segment_graph) or "axial"
# (pst_graph; `aux` then carries the in-memory unlinks/points/polygon inputs and the reconciled-CRS finisher).
# `path` has already been validated and identified as GeoParquet by .pst_path_graph().
# A Parquet file opened for reading with an OWNED, explicitly closable handle. ParquetFileReader$create(<path>) memory-maps the file
# and keeps it open until R's garbage collector happens to finalise the reader; Arrow opens local files without
# FILE_SHARE_DELETE (arrow/util/io_util.cc), so on Windows an unfinalised reader makes the file impossible to replace, delete or
# re-time (R's Sys.setFileTime() requests exclusive access). Callers close `$file` as soon as they are done with `$reader`
# (before publishing anything); the data read from a non-mapped file does not refer to the file.
.pst_parquet_source_open <- function(path) {
  file <- getExportedValue("arrow", "ReadableFile")$create(path)
  reader <- tryCatch(getExportedValue("arrow", "ParquetFileReader")$create(file, mmap = FALSE),
                     error = function(e) { try(file$close(), silent = TRUE); stop(e) })
  list(file = file, reader = reader)
}

.pst_geoparquet_graph <- function(path, target = "segment", aux = NULL) {
  axial <- identical(target, "axial")
  .pst_geoparquet_capabilities(if (axial) "axial_graph" else "segment_graph")
  source <- .pst_parquet_source_open(path)
  info <- tryCatch(list(rows = source$reader$num_rows, schema = source$reader$GetSchema()), finally = source$file$close())
  rows <- info$rows
  schema <- info$schema
  meta <- .pst_geoparquet_metadata(schema$metadata$geo, schema$names)
  rm(source, info, schema)
  if (!is.numeric(rows) || length(rows) != 1L || !is.finite(rows) || rows < 1)
    stop("The GeoParquet file has no rows; ",
         if (axial) "an axial graph needs at least one line." else "a segment graph needs at least one segment.",
         call. = FALSE)
  # Axial only: reconcile the file CRS with sf unlinks/points and stage them as matrices (R errors only).
  if (axial) aux <- .pst_axial_auxiliary(aux, meta$crs)

  # Geometry-only, single-threaded scan (row order is the graph order).
  dataset <- arrow::open_dataset(path, format = "parquet")
  scanner <- arrow::Scanner$create(dataset, projection = meta$primary, use_threads = FALSE)
  reader <- .pst_geoparquet_open_reader(scanner)

  # Ownership sequence: empty graph pointer, zeroed stream pointer, deterministic cleanup,
  # then export. The reader is dropped immediately and never consumed again.
  graph_ptr <- if (axial) .Call(C_rpst_axial_graph_new_pointer) else .Call(C_rpst_segment_graph_new_pointer)
  stream <- .Call(C_rpst_arrow_stream_new)
  on.exit(.Call(C_rpst_arrow_stream_free, stream), add = TRUE)
  .pst_geoparquet_export_reader(reader, stream)
  rm(reader, scanner, dataset)
  invisible(gc(verbose = FALSE))

  if (axial) {
    .Call(C_rpst_geoparquet_axial_graph, graph_ptr, stream, meta$primary, as.double(rows),
          aux$unlinks, aux$points, aux$points_per_polygon, aux$polygon_point_interval)
    .pst_axial_graph_object(graph_ptr, aux$crs)
  } else {
    .Call(C_rpst_geoparquet_segment_graph, graph_ptr, stream, meta$primary, as.double(rows))
    .pst_segment_graph_object(graph_ptr, meta$crs)
  }
}
