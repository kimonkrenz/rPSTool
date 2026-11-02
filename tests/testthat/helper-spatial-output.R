# Helpers for the spatial-output tests (docs/spatial-io/spatial-output.md). Sources are written with sf/GDAL (FlatGeobuf) and with R arrow
# (GeoParquet, hand-built 'geo' metadata) so the writers are always exercised against files produced by independent code.
so_ext <- c(flatgeobuf = "fgb", geoparquet = "parquet")
so_dir <- function() { d <- tempfile("rpst-so-"); dir.create(d); d }   # callers register unlink() with on.exit

# Irregular segments with exactly representable coordinates, a duplicate (row 5 = row 3), a reversed copy (row 8 is row 2
# reversed) and a zero-length segment (row 12).
so_segments <- function(n = 30) {
  i <- seq_len(n)
  x1 <- 100 + 10 * (i %% 7); y1 <- 200 + 10 * (i %/% 7)
  dx <- c(10, 0, -10, 7, 0, 10)[(i %% 6) + 1]; dy <- c(0, 10, 0, 3, -10, 10)[((i + 1) %% 6) + 1]
  m <- cbind(x1, y1, x1 + dx, y1 + dy)
  m[5, ] <- m[3, ]; m[8, ] <- m[2, c(3, 4, 1, 2)]; if (n >= 12) m[12, 3:4] <- m[12, 1:2]
  unname(m)
}
# Source attributes: identifiers that do NOT match row positions, strings with NA and non-ASCII text, a nullable integer,
# a large integer-valued double and a double with extreme values.
so_attributes <- function(n) {
  i <- seq_len(n)
  data.frame(osm_id = as.integer(rev(i) * 7L + 1000L), name = ifelse(i %% 5 == 0, NA, paste0("road-", i, if (n > 3) "é" else "")),
             lanes = ifelse(i %% 4 == 0, NA_integer_, as.integer(i %% 3)), big = 2^40 + i, w = i / 8, stringsAsFactors = FALSE)
}
so_sf <- function(m, attrs, epsg = 32630L) {
  geom <- sf::st_sfc(lapply(seq_len(nrow(m)), function(k) sf::st_linestring(matrix(m[k, ], 2, byrow = TRUE))), crs = epsg)
  sf::st_sf(attrs, geometry = geom)
}
so_write_fgb <- function(path, m, attrs = so_attributes(nrow(m)), index = FALSE, epsg = 32630L) {
  sf::st_write(so_sf(m, attrs, epsg), path, driver = "FlatGeobuf", quiet = TRUE,
               layer_options = paste0("SPATIAL_INDEX=", if (index) "YES" else "NO"))
  path
}
so_wkb <- function(m) lapply(seq_len(nrow(m)), function(k) wkb_line(m[k, 1], m[k, 2], m[k, 3], m[k, 4]))
so_geo_json <- function(primary = "geometry", crs = TRUE) {
  projjson <- paste(readLines(test_path("fixtures", "geoparquet", "utm30n.projjson"), warn = FALSE), collapse = "\n")
  paste0('{"version":"1.1.0","primary_column":"', primary, '","columns":{"', primary, '":{"encoding":"WKB",',
         '"geometry_types":["LineString"],"crs":', if (crs) projjson else "null", ',"bbox":[0,0,1,1]}}}')
}
# GeoParquet source. `extra` columns (named list of arrow-ready vectors) are appended; `chunk` sets the row-group size.
so_write_gpq <- function(path, m, attrs = so_attributes(nrow(m)), chunk = NULL, primary = "geometry", extra = list(), index = FALSE) {
  cols <- c(as.list(attrs), extra)
  cols[[primary]] <- arrow::Array$create(so_wkb(m), type = arrow::binary())
  tab <- do.call(arrow::arrow_table, cols)
  tab <- tab$ReplaceSchemaMetadata(list(geo = so_geo_json(primary), other_key = "kept"))
  arrow::write_parquet(tab, path, compression = "zstd", chunk_size = chunk %||% nrow(m))
  path
}
`%||%` <- function(a, b) if (is.null(a)) b else a
so_md5 <- function(path) unname(tools::md5sum(path))
so_leftovers <- function(dir) list.files(dir, pattern = "^\\.rpst-", all.files = TRUE)

# Read a spatial output back with an independent reader. FlatGeobuf: GDAL via sf. GeoParquet: R arrow.
so_read <- function(path, format) {
  if (format == "flatgeobuf") {
    x <- sf::st_read(path, quiet = TRUE)
    list(attrs = sf::st_drop_geometry(x), wkb = sf::st_as_binary(sf::st_geometry(x)), crs = sf::st_crs(x),
         names = names(sf::st_drop_geometry(x)))
  } else {
    t <- rs_read_parquet(path, as_data_frame = FALSE)
    d <- as.data.frame(t)
    list(attrs = d[setdiff(names(d), "geometry")], wkb = unclass(d$geometry), table = t,
         names = setdiff(names(d), "geometry"))
  }
}
# The geometry (WKB) of a source file, read independently of the package: GDAL via sf for FlatGeobuf, arrow for GeoParquet
# (GDAL builds do not all include the Parquet driver).
so_wkb_of <- function(path) {
  if (grepl("\\.parquet$", path)) so_read(path, "geoparquet")$wkb
  else sf::st_as_binary(sf::st_geometry(sf::st_read(path, quiet = TRUE)))
}
so_make_source <- function(format, path, m, ...) if (format == "flatgeobuf") so_write_fgb(path, m, ...) else so_write_gpq(path, m, ...)
so_graph <- function(format, path, kind) {
  if (kind == "segment") segment_graph(path) else axial_graph(path)
}

# Run R code in a fresh Rscript subprocess, optionally under an RLIMIT_FSIZE (`limit_blocks` x 512 bytes, POSIX `ulimit -f`,
# with SIGXFSZ ignored so an over-limit write fails with EFBIG instead of killing the process). stdout and stderr go to files,
# so a non-zero exit status is RETURNED (never raised as an R warning) and the complete output is available for diagnostics.
so_subprocess <- function(lines, limit_blocks = NULL) {
  script <- tempfile(fileext = ".R"); out <- tempfile(); err <- tempfile()
  on.exit(unlink(c(script, out, err)), add = TRUE)
  writeLines(c(sprintf(".libPaths(c(%s))", paste(sprintf("'%s'", .libPaths()), collapse = ",")), lines), script)
  command <- paste0(if (!is.null(limit_blocks)) sprintf("trap '' 25; ulimit -f %d; ", as.integer(limit_blocks)),
                    "exec ", shQuote(file.path(R.home("bin"), "Rscript")), " --vanilla ", shQuote(script))
  status <- system2("sh", c("-c", shQuote(command)), stdout = out, stderr = err)
  list(status = status, stdout = readLines(out, warn = FALSE), stderr = readLines(err, warn = FALSE))
}
so_describe <- function(run) paste0("status=", run$status, "\nstdout:\n", paste(run$stdout, collapse = "\n"),
                                    "\nstderr:\n", paste(run$stderr, collapse = "\n"))

# A network large enough that its spatial output cannot fit in the file-size limit used by the full-disk test, with
# incompressible attributes so that GeoParquet's compression cannot make it small.
so_big_segments <- function(n) {
  i <- seq_len(n); x <- (i %% 200) * 10; y <- (i %/% 200) * 10
  unname(cbind(x, y, x + 10, y + ((i %% 3) - 1) * 2))
}
so_noise_attributes <- function(n) {
  set.seed(7)
  d <- data.frame(osm_id = seq_len(n)); for (k in 1:8) d[[paste0("noise", k)]] <- runif(n)
  d
}
