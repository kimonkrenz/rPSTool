# FlatGeobuf path input for segment_graph() (see docs/spatial-io/flatgeobuf-input.md). The header is
# inspected natively (verified FlatBuffers), the CRS is interpreted here through sf BEFORE any native graph pointer
# exists, and the native decoder then re-reads and revalidates the header and streams the features into the shared
# segment-graph builder. No other package is needed beyond sf.

# GDAL's representation of an UNKNOWN CRS (written, for example, when an sf layer with an NA CRS is saved): a Crs
# table with no authority, code 0 and exactly this engineering CRS. Only this exact form maps to sf::st_crs(NA).
.pst_flatgeobuf_unknown_crs_name <- "Undefined Cartesian SRS with unknown unit"
.pst_flatgeobuf_unknown_crs_wkt <- paste0(
  'ENGCRS["Undefined Cartesian SRS with unknown unit",EDATUM["Unknown engineering datum"],CS[Cartesian,2],',
  'AXIS["x",unspecified,ORDER[1],LENGTHUNIT["unknown",0]],AXIS["y",unspecified,ORDER[2],LENGTHUNIT["unknown",0]]]')

.pst_flatgeobuf_empty <- function(x) is.null(x) || identical(x, "")

.pst_flatgeobuf_is_unknown_crs <- function(crs) {
  .pst_flatgeobuf_empty(crs$org) &&
    (is.null(crs$code) || identical(as.integer(crs$code), 0L)) &&
    identical(crs$name, .pst_flatgeobuf_unknown_crs_name) &&
    identical(crs$wkt, .pst_flatgeobuf_unknown_crs_wkt) &&
    .pst_flatgeobuf_empty(crs$description) &&
    .pst_flatgeobuf_empty(crs$code_string)
}

# Graph CRS from the header's Crs table (NULL = no table). Unknown (absent, or exactly GDAL's unknown form) ->
# sf::st_crs(NA); otherwise interpreted through sf like GDAL does (EPSG code first, then WKT); geographic and
# uninterpretable CRS are rejected.
.pst_flatgeobuf_crs <- function(crs) {
  if (is.null(crs) || .pst_flatgeobuf_is_unknown_crs(crs)) return(sf::st_crs(NA))
  candidates <- character()
  code <- if (is.null(crs$code)) 0L else as.integer(crs$code)
  org <- if (.pst_flatgeobuf_empty(crs$org)) "EPSG" else crs$org
  if (!is.na(code) && code != 0L) candidates <- c(candidates, paste0(org, ":", code))
  if (!.pst_flatgeobuf_empty(crs$wkt)) candidates <- c(candidates, crs$wkt)
  value <- NA
  for (candidate in candidates) {
    parsed <- tryCatch(suppressWarnings(sf::st_crs(candidate)), error = function(e) NA)
    if (inherits(parsed, "crs") && !is.na(parsed)) { value <- parsed; break }
  }
  if (!inherits(value, "crs") || is.na(value))
    stop("The FlatGeobuf CRS could not be interpreted by sf (org/code/WKT); no CRS is guessed.", call. = FALSE)
  if (isTRUE(sf::st_is_longlat(value)))
    stop("Geographic longitude/latitude CRS is unsupported; supply projected coordinates (no CRS transformation is performed).",
         call. = FALSE)
  value
}

# `path` has already been validated and identified as FlatGeobuf by .pst_path_graph(). `target` is "segment"
# (segment_graph) or "axial" (axial_graph, with `aux` as for GeoParquet).
.pst_flatgeobuf_graph <- function(path, target = "segment", aux = NULL) {
  axial <- identical(target, "axial")
  if (!requireNamespace("sf", quietly = TRUE))
    stop("Reading a FlatGeobuf path requires the optional package 'sf' to interpret the CRS; ",
         "install it to use ", if (axial) "axial_graph" else "segment_graph", "() with a file path.", call. = FALSE)
  info <- .Call(C_rpst_fgb_inspect, path)          # header policy + verified raw header (no owners survive)
  crs <- .pst_flatgeobuf_crs(info$crs)             # R-side CRS decision before any native pointer exists
  if (axial) aux <- .pst_axial_auxiliary(aux, crs) # reconcile with sf unlinks/points; stage matrices (R errors only)
  if (axial) {
    graph_ptr <- .Call(C_rpst_axial_graph_new_pointer)
    .Call(C_rpst_fgb_axial_graph, graph_ptr, path, info$header,
          aux$unlinks, aux$points, aux$points_per_polygon, aux$polygon_point_interval)
    .pst_axial_graph_object(graph_ptr, aux$crs)
  } else {
    graph_ptr <- .Call(C_rpst_segment_graph_new_pointer)
    .Call(C_rpst_fgb_segment_graph, graph_ptr, path, info$header)  # revalidates the header, decodes, builds
    .pst_segment_graph_object(graph_ptr, crs)
  }
}
