#' Find the junctions between lines
#'
#' Returns the coordinates where lines cross or meet, optionally between two sets of lines, after removing unlinked
#' crossings. It is a stand-alone utility and does not create a graph.
#'
#' @details
#' PST works in single-precision local coordinates around the world centre of the first layer. With one layer, repeated
#' pairwise intersections are kept. With two layers (`y`), only the unique intersections between the layers are kept. A
#' shared endpoint of just two lines does not necessarily count as a junction in one-layer mode. Points are returned in
#' PST's sorted order. Each unlink removes the nearest junction without a tolerance; PST's unlink compaction can also
#' discard leading survivors, and rPSTool preserves that behaviour.
#'
#' An empty first layer is rejected, because PST returns without writing a result. A non-empty layer can validly give
#' zero junctions. An explicitly empty second layer selects two-layer mode and therefore gives no intersections.
#'
#' `sf` inputs are XY LINESTRINGs with exactly two finite vertices, or XY POINT coordinates with explicit indices; unlinks
#' are XY POINTs. Attributes are ignored. A known geographic CRS is rejected, `sf` inputs must have compatible CRS
#' (including unknown), and mixed matrices must already share one coordinate frame. Nothing is reprojected or converted.
#' The output CRS comes only from supplied `sf` metadata (unknown for matrix input). Inputs must be finite and within
#' PST's coordinate range.
#'
#' @param x A numeric matrix with columns `x1, y1, x2, y2` (column names do not determine the order), or `x, y` when
#'   `line_indices` is supplied, or the equivalent XY LINESTRING/POINT `sf`/`sfc` object.
#' @param line_indices Optional two-column matrix of whole, one-based endpoint indices into `x`. PST's world centre uses
#'   the coordinate prefix through the largest referenced index, including unused rows in that prefix.
#' @param y Optional second layer in the same formats as `x`.
#' @param line_indices_y Optional endpoint index matrix for `y`.
#' @param unlinks Optional matrix with columns `x, y`, or XY POINT `sf`/`sfc` object.
#' @param output `"native"` (default) returns a matrix; `"sf"` returns point geometry (requires 'sf').
#' @return A numeric matrix with columns `x` and `y`, in PST's order. With `output = "sf"`, XY POINT features with a
#'   one-based `junction_id`.
#' @seealso [create_segment_map()], [axial_graph()]
#' @export
#' @examples
#' x <- rbind(c(-1, 0, 1, 0), c(0, -1, 0, 1))
#' create_junctions(x)
create_junctions <- function(x, line_indices = NULL, y = NULL,
                                 line_indices_y = NULL, unlinks = NULL,
                                 output = c("native", "sf")) {
  output <- match.arg(output)
  if (output == "sf") .pst_require_sf()
  crs <- .pst_sf_crs(x, y, unlinks)
  x <- if (is.null(line_indices)) .pst_sf_lines(x, "x") else .pst_sf_points(x, "x")
  y <- if (is.null(line_indices_y)) .pst_sf_lines(y, "y") else .pst_sf_points(y, "y")
  unlinks <- .pst_sf_points(unlinks, "unlinks")
  if (is.matrix(x) && ((is.null(line_indices) && nrow(x) == 0L) ||
      (is.matrix(line_indices) && nrow(line_indices) == 0L)))
    stop("Empty first junction layer is unsupported: pinned PST succeeds without writing its result.", call. = FALSE)
  out <- .Call(C_rpst_create_junctions, x, line_indices, y, line_indices_y, unlinks, FALSE)
  colnames(out) <- c("x", "y")
  if (output == "sf")
    .pst_sf_point_output(out, crs, data.frame(junction_id = seq_len(nrow(out))))
  else out
}

#' Prepare a street network as segments
#'
#' Turns a street-centre-line network into the segments (and, for axial maps, unlinks) used by the analyses. PST finds
#' where lines cut each other, snaps nearby endpoints, removes duplicate and zero-length segments, trims short tails
#' and reduces detail. Use it to prepare a drawn network before calling [segment_graph()] or [axial_graph()]. It does not create a graph.
#'
#' @details
#' **Network type.** In `"axial_or_segment"` mode lines are split at cuts. In `"road_center_lines"` mode the cut
#' coordinates are returned as unlinks (including PST's duplicates) and lines are not split at those cuts. Supplied
#' `unlinks` apply only in axial or segment mode and are matched to cuts within a strict radius of 100 coordinate units.
#' Output order, endpoint direction and source associations are preserved.
#'
#' **Thresholds.** `snap`, `tail`, `deviation` and `extrude` must be finite, non-negative single-precision values (squared
#' values must also fit, where PST squares them). Coordinates are planar and in the units of those thresholds.
#'
#' **Input.** `coords` is a coordinate matrix described by `sections`, or an `sf`/`sfc` object of XY LINESTRING or
#' MULTILINESTRING features. Each feature is one source object. Every vertex and part is kept in order and no connecting edge
#' is added between parts. Empty features advance the source identifier, and at least one actual edge is required.
#' Collections, other geometry types and Z/M are rejected, and no repair or attribute join occurs. CRS rules match
#' [create_junctions()].
#'
#' @section Limitations:
#' A safeguard rejects with an error any input where PST's detail reduction would merge a chain of segments back onto its
#' own starting point. This includes closed rings with no junction, which crash unmodified PST, and loops attached at a single
#' junction of degree three or more (for example a cul-de-sac loop whose `deviation` is large relative to its vertex
#' spacing), which unmodified PST completes as a degenerate zero-length self-loop. The safeguard can therefore reject inputs
#' that unmodified PST would process, but it never changes a result: for every accepted input the output is that of the
#' unmodified PST computation. Consequently an input containing a cycle is not guaranteed to be accepted; a smaller
#' `deviation` threshold, or breaking the cycle, may avoid the error.
#'
#' @param coords A numeric matrix with columns `x, y`, or an XY LINESTRING/MULTILINESTRING `sf`/`sfc` object.
#' @param sections For matrix `coords`, a numeric vector of signed whole section lengths partitioning the coordinate rows.
#'   A non-negative value gives the number of points and advances the source identifier; a negative value encodes
#'   `-(point_count + 1)` and continues the same source object in the next section. One-point and empty sections are allowed
#'   alongside actual edges. Must be `NULL` (the default) for `sf` coords, where it is derived from the geometry.
#' @param network_type `"axial_or_segment"` or `"road_center_lines"`.
#' @param snap Endpoint snapping distance (default 1).
#' @param tail Tail-length threshold (default 10): PST removes only a tail shorter than this that reaches an intersection.
#' @param deviation Collinear-deviation threshold (default 1), applied to segments from the same source object. Equality
#'   permits a merge.
#' @param extrude Extension distance for intersection searches (default 0), controlled independently of `snap`.
#' @param unlinks Optional matrix with columns `x, y`, or XY POINT `sf`/`sfc` object, used only in axial or segment mode.
#' @param output `"native"` (default) or `"sf"` (requires 'sf').
#' @return A list with
#'   * `segments`: a numeric matrix of `x1, y1, x2, y2`,
#'   * `source_id`: one-based integer identifiers of the input object each segment came from, which can repeat or skip
#'     values and are not persistent external identifiers, and
#'   * `unlinks`: a numeric matrix of `x, y`.
#'
#'   With `output = "sf"`, `segments` is a two-vertex LINESTRING `sf` object with a `source_id` column, and `unlinks` is
#'   a POINT `sf` object; the CRS comes only from supplied `sf` metadata (unknown for matrix input), and empty outputs
#'   have zero features.
#' @seealso [segment_graph()], [axial_graph()], [create_junctions()]
#' @export
#' @examples
#' m <- create_segment_map(rbind(c(0, 0), c(10, 0), c(20, 0)), 3,
#'   snap = 0, tail = 0)
#' m$segments
create_segment_map <- function(coords, sections = NULL,
    network_type = c("axial_or_segment", "road_center_lines"), snap = 1,
    tail = 10, deviation = 1, extrude = 0, unlinks = NULL,
    output = c("native", "sf")) {
  network_type <- match.arg(network_type)
  output <- match.arg(output)
  if (output == "sf") .pst_require_sf()
  crs <- .pst_sf_crs(coords, unlinks)
  input <- .pst_sf_sections(coords, sections)
  coords <- input$coords
  sections <- input$sections
  unlinks <- .pst_sf_points(unlinks, "unlinks")
  out <- .Call(C_rpst_create_segment_map, coords, sections, network_type,
               snap, tail, deviation, extrude, unlinks, FALSE)
  names(out) <- c("segments", "source_id", "unlinks")
  colnames(out$segments) <- c("x1", "y1", "x2", "y2")
  colnames(out$unlinks) <- c("x", "y")
  if (output == "sf") {
    out$segments <- .pst_sf_line_output(out$segments, crs, data.frame(source_id = out$source_id))
    out$unlinks <- .pst_sf_point_output(out$unlinks, crs, data.frame(row.names = seq_len(nrow(out$unlinks))))
  }
  out
}
