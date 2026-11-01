# Optional geometry adapters. Matrices and native owners remain authoritative.
.pst_is_sf <- function(x) inherits(x, "sf") || inherits(x, "sfc")

.pst_require_sf <- function() {
  if (!requireNamespace("sf", quietly = TRUE))
    stop("The optional package 'sf' is required for sf geometry adapters.", call. = FALSE)
}

# NULL means no sf input; an NA crs is real, unknown sf metadata.
.pst_sf_crs <- function(..., reference = NULL) {
  inputs <- list(...)
  inputs <- inputs[vapply(inputs, .pst_is_sf, logical(1))]
  if (!length(inputs) && is.null(reference)) return(NULL)
  .pst_require_sf()
  crs <- lapply(inputs, sf::st_crs)
  if (!is.null(reference)) crs <- c(list(reference), crs)
  for (value in crs) {
    if (!is.na(value) && isTRUE(sf::st_is_longlat(value)))
      stop("Geographic longitude/latitude CRS is unsupported; transform explicitly to suitable planar coordinates with sf::st_transform().", call. = FALSE)
    if (!isTRUE(value == crs[[1L]]))
      stop("All sf inputs must have compatible CRS metadata (including missing CRS).", call. = FALSE)
  }
  crs[[1L]]
}

.pst_sf_geometry <- function(x, family, name) {
  .pst_require_sf()
  geometry <- sf::st_geometry(x)
  if (!length(geometry) && !inherits(geometry, paste0("sfc_", family)) &&
      !inherits(geometry, "sfc_GEOMETRY"))
    stop(name, " requires ", paste(family, collapse = " or "), " geometry.", call. = FALSE)
  for (part in geometry) {
    if (!inherits(part, "XY"))
      stop(name, " requires XY geometry; Z/M dimensions cannot be discarded.", call. = FALSE)
    if (!inherits(part, family))
      stop(name, " requires ", paste(family, collapse = " or "),
           " geometry; unsupported geometry families cannot be flattened.", call. = FALSE)
  }
  geometry
}

.pst_sf_points <- function(x, name) {
  if (!.pst_is_sf(x)) return(x)
  geometry <- .pst_sf_geometry(x, "POINT", name)
  out <- matrix(0, length(geometry), 2L)
  for (i in seq_along(geometry)) {
    part <- geometry[[i]]
    if (length(part) != 2L || any(!is.finite(part)))
      stop(name, " requires nonempty finite POINT features.", call. = FALSE)
    out[i, ] <- part
  }
  out
}

.pst_sf_lines <- function(x, name) {
  if (!.pst_is_sf(x)) return(x)
  geometry <- .pst_sf_geometry(x, "LINESTRING", name)
  out <- matrix(0, length(geometry), 4L)
  for (i in seq_along(geometry)) {
    part <- geometry[[i]]
    if (!is.matrix(part) || nrow(part) != 2L || ncol(part) != 2L ||
        any(!is.finite(part)))
      stop(name, " requires exactly two finite XY vertices per LINESTRING; polylines cannot be reduced to endpoints.", call. = FALSE)
    out[i, ] <- c(part[1L, ], part[2L, ])
  }
  out
}

# Every sf ring closes explicitly; PST closes implicitly. Remove exactly the
# structural final coordinate, keeping every other vertex and the winding.
.pst_sf_open_ring <- function(ring, name) {
  if (!is.matrix(ring) || ncol(ring) != 2L || nrow(ring) < 4L ||
      any(!is.finite(ring)) || !all(ring[1L, ] == ring[nrow(ring), ]))
    stop(name, " requires finite explicitly closed POLYGON rings with at least four coordinates; empty rings are unsupported.", call. = FALSE)
  ring[-nrow(ring), , drop = FALSE]
}

.pst_sf_graph_points <- function(points, counts, name = "points") {
  if (!.pst_is_sf(points)) return(list(points = points, counts = counts))
  .pst_require_sf()
  if (!is.null(counts))
    stop("points_per_polygon must be NULL for sf points; POLYGON feature counts are derived from geometry.", call. = FALSE)
  geometry <- sf::st_geometry(points)
  if (!length(geometry) && inherits(geometry, "sfc_POLYGON"))
    stop(name, " requires at least one POLYGON feature; empty POLYGON features may represent empty groups.", call. = FALSE)
  if (!length(geometry) || all(vapply(geometry, inherits, logical(1), "POINT")))
    return(list(points = .pst_sf_points(points, name), counts = NULL))
  geometry <- .pst_sf_geometry(points, "POLYGON", name)
  # Every sf ring closes explicitly; PST closes implicitly. Only remove the
  # necessary final closure, keeping all other vertices and ring order intact.
  rings <- vector("list", length(geometry))
  counts <- numeric(length(geometry))
  for (i in seq_along(geometry)) {
    polygon <- geometry[[i]]
    pieces <- vector("list", max(0L, 2L * length(polygon) - 1L))
    for (j in seq_along(polygon)) {
      pieces[[2L * j - 1L]] <- .pst_sf_open_ring(polygon[[j]], name)
      if (j < length(polygon)) pieces[[2L * j]] <- matrix(NaN, 1L, 2L)
    }
    rings[[i]] <- if (length(pieces)) do.call(rbind, pieces) else matrix(numeric(), 0L, 2L)
    counts[[i]] <- nrow(rings[[i]])
  }
  list(points = if (length(rings)) do.call(rbind, rings) else matrix(numeric(), 0L, 2L),
       counts = counts)
}

.pst_sf_point_output <- function(coords, crs, id) {
  .pst_require_sf()
  if (any(!is.finite(coords)))
    stop("Native coordinates cannot be represented as finite sf POINT geometry.", call. = FALSE)
  geometry <- lapply(seq_len(nrow(coords)), function(i) sf::st_point(coords[i, ]))
  sf::st_sf(id, geometry = sf::st_sfc(geometry, crs = if (is.null(crs)) NA_integer_ else crs))
}

# Matrix analysis inputs remain usable without sf, even on a CRS-bearing graph.
.pst_sf_analysis_crs <- function(graph, x) {
  if (.pst_is_sf(x))
    .pst_sf_crs(x, reference = attr(graph, "crs", exact = TRUE))
  invisible(NULL)
}

# Each feature advances the native source exactly once. Negative sections keep
# the current source; separate sections never create an edge between parts.
.pst_sf_sections <- function(x, sections) {
  if (!.pst_is_sf(x)) return(list(coords = x, sections = sections))
  if (!is.null(sections))
    stop("sections must be NULL for sf coords; section lengths are derived from geometry.", call. = FALSE)
  geometry <- .pst_sf_geometry(x, c("LINESTRING", "MULTILINESTRING"), "coords")
  features <- vector("list", length(geometry))
  counts <- vector("list", length(geometry))
  for (i in seq_along(geometry)) {
    feature <- geometry[[i]]
    parts <- if (inherits(feature, "LINESTRING")) list(feature) else feature
    # A multipart feature without parts still advances its native source ID.
    if (!length(parts)) parts <- list(matrix(numeric(), 0L, 2L))
    sizes <- numeric(length(parts))
    for (j in seq_along(parts)) {
      part <- parts[[j]]
      if (!is.matrix(part) || !is.numeric(part) || ncol(part) != 2L ||
          any(!is.finite(part)))
        stop("coords requires finite XY coordinate matrices in every line part; Z/M cannot be discarded.", call. = FALSE)
      sizes[[j]] <- nrow(part)
    }
    earlier <- seq_len(length(parts) - 1L)
    sizes[earlier] <- -(sizes[earlier] + 1)
    counts[[i]] <- sizes
    features[[i]] <- do.call(rbind, parts)
  }
  list(coords = if (length(features)) do.call(rbind, features) else matrix(numeric(), 0L, 2L),
       sections = as.double(unlist(counts, use.names = FALSE)))
}

.pst_sf_line_output <- function(coords, crs, columns) {
  .pst_require_sf()
  if (any(!is.finite(coords)))
    stop("Native coordinates cannot be represented as finite sf LINESTRING geometry.", call. = FALSE)
  geometry <- lapply(seq_len(nrow(coords)), function(i)
    sf::st_linestring(matrix(coords[i, ], ncol = 2L, byrow = TRUE)))
  sf::st_sf(columns, geometry = sf::st_sfc(geometry, crs = if (is.null(crs)) NA_integer_ else crs))
}

# Isovist context groups. A group is an sf/sfc layer (features in order) or the
# existing matrix form. Obstacle/attraction polygons are single-ring POLYGONs:
# a hole cannot be represented as one PST polygon without changing visibility.
.pst_sf_isovist_group <- function(layer, polygon, name) {
  if (!.pst_is_sf(layer)) return(layer)
  if (!polygon) return(.pst_sf_points(layer, name))
  geometry <- .pst_sf_geometry(layer, "POLYGON", name)
  lapply(seq_along(geometry), function(i) {
    feature <- geometry[[i]]
    if (length(feature) != 1L)
      stop(name, " requires POLYGON features with exactly one ring; empty polygons and holes cannot be represented as one PST polygon.", call. = FALSE)
    .pst_sf_open_ring(feature[[1L]], name)
  })
}

.pst_sf_isovist_groups <- function(groups, polygon, name) {
  if (.pst_is_sf(groups))
    stop(name, " must be a list of groups; wrap an sf/sfc layer in list().", call. = FALSE)
  if (!is.list(groups)) return(groups)
  lapply(groups, .pst_sf_isovist_group, polygon = polygon, name = name)
}

# Native vertices plus exactly one structural closure, only when absent.
.pst_sf_polygon_output <- function(coords, crs) {
  .pst_require_sf()
  closed <- .pst_sf_output_ring(coords)
  if (identical(closed$problem, "vertices") || identical(closed$problem, "nonfinite"))
    stop("Native isovist polygon has fewer than three vertices or nonfinite coordinates; it cannot be represented as an sf POLYGON.", call. = FALSE)
  if (identical(closed$problem, "closure"))
    stop("Native isovist polygon cannot form a closed sf ring with at least four coordinates.", call. = FALSE)
  sf::st_sfc(sf::st_polygon(list(closed$ring)), crs = if (is.null(crs)) NA_integer_ else crs)
}

# Shared strictly representational ring closure for native outputs: all native
# coordinates in order plus one first-coordinate closure only if absent. Returns
# list(ring, problem) where problem is NULL, "vertices" (<3 rows), "nonfinite"
# or "closure" (an already-closed ring with <4 rows). Nothing is repaired.
.pst_sf_output_ring <- function(coords) {
  if (!is.matrix(coords) || ncol(coords) != 2L || !is.numeric(coords) || nrow(coords) < 3L)
    return(list(ring = NULL, problem = "vertices"))
  if (any(!is.finite(coords))) return(list(ring = NULL, problem = "nonfinite"))
  n <- nrow(coords)
  ring <- if (all(coords[1L, ] == coords[n, ])) coords else rbind(coords, coords[1L, ])
  if (nrow(ring) < 4L) return(list(ring = NULL, problem = "closure"))
  dimnames(ring) <- NULL
  list(ring = ring, problem = NULL)
}

# Native PST raster polygons (range -> polygon -> rings) to a list of
# sfc_POLYGON, one per range. Every ring is validated before anything is built,
# so an unrepresentable ring never yields a partial result.
.pst_sf_raster_polygons <- function(polygons, crs) {
  .pst_require_sf()
  sfc_crs <- if (is.null(crs)) NA_integer_ else crs
  reasons <- c(vertices = "fewer than three coordinates", nonfinite = "nonfinite coordinates",
               closure = "an already-closed ring with fewer than four coordinates")
  built <- vector("list", length(polygons))
  for (i in seq_along(polygons)) {
    built[[i]] <- vector("list", length(polygons[[i]]))
    for (j in seq_along(polygons[[i]])) {
      rings <- polygons[[i]][[j]]
      if (!length(rings))
        stop(sprintf("Native raster range %d polygon %d has no rings; it cannot be represented as an sf POLYGON. Use output = \"native\".", i, j), call. = FALSE)
      converted <- vector("list", length(rings))
      for (k in seq_along(rings)) {
        closed <- .pst_sf_output_ring(rings[[k]])
        if (!is.null(closed$problem))
          stop(sprintf("Native raster range %d polygon %d ring %d has %s and cannot be represented as an sf POLYGON ring without inventing geometry. Use output = \"native\".",
                       i, j, k, reasons[[closed$problem]]), call. = FALSE)
        converted[[k]] <- closed$ring
      }
      built[[i]][[j]] <- converted
    }
  }
  lapply(built, function(range) {
    if (!length(range)) {
      empty <- sf::st_sfc(list(), crs = sfc_crs)
      class(empty) <- c("sfc_POLYGON", "sfc")
      attr(empty, "classes") <- NULL
      return(empty)
    }
    sf::st_sfc(lapply(range, sf::st_polygon), crs = sfc_crs)
  })
}

# CRS of every sf/sfc layer nested in the three group families; matrix groups
# contribute no metadata. NULL when sf does not participate.
.pst_sf_isovist_crs <- function(families) {
  layers <- list()
  for (family in families)
    if (is.list(family) && !.pst_is_sf(family))
      layers <- c(layers, Filter(.pst_is_sf, family))
  if (length(layers)) do.call(.pst_sf_crs, unname(layers)) else NULL
}
