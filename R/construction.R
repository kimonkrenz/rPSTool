#' Create junction coordinates with pinned PST
#'
#' Explicit native construction utility, independent of any graph owner. PST
#' computes in local floats around the first layer's double world center.
#' One layer retains repeated pairwise intersections; two layers retain unique
#' inter-layer intersections. A shared endpoint of just two lines does not
#' necessarily qualify in one-layer mode. Points retain native sorted order.
#' Unlinks remove the nearest junction without a tolerance. Pinned PST's unlink
#' compaction can also discard leading survivors; rPSTool preserves that behaviour.
#'
#' An empty first line layer is rejected before PST: the pinned implementation
#' returns success without writing its result. A nonempty layer can validly
#' produce a zero-row native-written result. An explicitly empty second layer
#' selects two-layer mode and therefore produces no intersections.
#'
#' Optional sf/sfc inputs use exactly two finite XY vertices per LINESTRING
#' for packed layers, or XY POINT coordinate features with explicit indices.
#' Unlinks accept XY POINTs. Attributes are ignored. Known geographic CRS is
#' rejected; sf inputs must share compatible metadata, including unknown CRS.
#' Mixed matrices must already share the numerical frame. No reprojection or
#' unit conversion occurs. Output CRS comes only from supplied sf metadata
#' (matrix-only `output = "sf"` results have unknown CRS). Inputs must be
#' finite and fit PST's native coordinate and distance bounds.
#'
#' @param x Integer or double matrix with columns `x1,y1,x2,y2`, or `x,y`
#'   when `line_indices` is supplied, or the corresponding XY LINESTRING/POINT
#'   sf/sfc form. Column names do not determine order.
#' @param line_indices Optional numeric two-column matrix of whole one-based
#'   endpoint indices into `x`. PST's world center uses the coordinate prefix
#'   through the largest referenced index, including unused rows in that prefix.
#' @param y Optional second layer, in the same matrix or sf/sfc formats as `x`.
#' @param line_indices_y Optional endpoint index matrix for `y`.
#' @param unlinks Optional numeric matrix with columns `x,y`, or XY POINT sf/sfc.
#' @param output `"native"` (default) or `"sf"` (requires optional sf).
#' @return A double matrix with columns `x,y`. It owns its R storage; the
#'   transient native result owner is freed before returning. With `output="sf"`,
#'   returns XY POINT geometry with one-based `junction_id` in native order,
#'   derived solely from the copied native coordinates.
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

#' Construct segment endpoints and unlinks with pinned PST
#'
#' This explicit utility calls `PSTACreateSegmentMap`; it does not create a graph.
#' Coordinates are planar, in the units used by the native thresholds. PST finds
#' cuts, snaps, removes duplicate/zero segments, trims tails and reduces detail.
#' Axial/segment mode splits at cuts. Road-center mode emits cut coordinates as
#' unlinks (including native duplicates) and does not split at those cuts.
#' Input unlinks use PST's strict 100-unit cut-matching radius in axial mode.
#' Native output order, endpoint direction and source associations are preserved.
#' Thresholds must be finite nonnegative native floats, with squared values
#' representable where PST squares them; inputs must fit native coordinate,
#' distance and index bounds.
#'
#' A verified build-copy guard raises an R error whenever PST's detail reduction
#' would merge a chain of segments back onto its own starting point. This is
#' deliberately conservative. It includes closed rings with no junction, which
#' crash unmodified PST, and also a loop attached at a single junction of degree
#' three or more (for example a cul-de-sac loop whose detail-reduction threshold
#' is large relative to its vertex spacing), which unmodified PST completes as a degenerate
#' zero-length self-loop. rPSTool rejects both rather than publish a zero-length
#' segment. The guard can therefore reject inputs that unmodified PST would
#' process; it never alters a result. For every input rPSTool accepts, the output
#' is that of the unmodified PST computation. Zero deviation does not guarantee
#' that a cycle is accepted.
#' Native result arrays are copied before freeing their owner; inputs are not
#' retained and no native handle escapes. The output can be passed explicitly
#' to `segment_graph()` or `axial_graph()` as appropriate.
#'
#' Optional sf/sfc coords accept XY LINESTRING and MULTILINESTRING features.
#' Each feature is one native source object. Every vertex and part stays in
#' order; earlier multipart sections encode `-(n + 1)`, and the final section
#' encodes `n`. No connecting edge is added between parts. Empty features
#' advance the source ID with a zero section; singleton and empty parts are
#' retained. At least one actual edge remains required. Collections, other
#' families and Z/M are rejected. No geometry repair or attribute join occurs.
#' CRS rules match [create_junctions()]: projected units stay unchanged,
#' known geographic CRS is rejected, sf metadata must be compatible, unknown
#' CRS and mixed matrix frames remain the caller's responsibility.
#'
#' @param coords Integer or double coordinate matrix with columns `x,y`,
#'   or XY LINESTRING/MULTILINESTRING sf/sfc.
#' @param sections Numeric vector of signed whole section lengths partitioning
#'   the coordinate rows. A nonnegative value gives the point count and advances
#'   the native source ID. A negative value encodes `-(point_count + 1)` and
#'   continues the same source object into the next section. Empty/one-point
#'   sections are allowed alongside actual edges; at least one edge is required.
#'   Must be NULL (the default) for sf coords; derived from geometry. Matrix
#'   coords still require an explicit sections vector.
#' @param network_type Either `"axial_or_segment"` or `"road_center_lines"`.
#' @param snap Native endpoint snapping distance (default 1).
#' @param tail Native tail-length threshold (default 10). PST only removes a
#'   tail shorter than this threshold that reaches an intersection.
#' @param deviation Native collinear-deviation threshold (default 1), restricted
#'   to segments from the same native source object. Equality permits a merge.
#' @param extrude Native extension distance for intersection searches (default 0),
#'   independently controlled from `snap`.
#' @param unlinks Optional numeric `x,y` matrix or XY POINT sf/sfc, only in
#'   axial/segment mode when nonempty.
#' @param output `"native"` (default) or `"sf"` (requires optional sf).
#' @return A list with `segments` (double `x1,y1,x2,y2` matrix), `source_id`
#'   (one-based integer native source IDs), and `unlinks` (double `x,y` matrix).
#'   IDs may repeat or skip values; they associate outputs with native input
#'   objects and are not persistent external identifiers. With `output="sf"`,
#'   the same three-component list contains `segments` as two-vertex XY
#'   LINESTRING sf with a `source_id` column, the unchanged `source_id` vector,
#'   and `unlinks` as XY POINT sf without additional columns. Geometry comes
#'   solely from copied native output, with CRS only from supplied sf metadata
#'   (unknown for matrix-only calls). Empty outputs have zero features.
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
