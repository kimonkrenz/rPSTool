#' Specify the distance limits of an analysis
#'
#' Creates the `radius` argument used by the network analyses. A radius sets up to five independent
#' limits on how far an analysis travels from each origin. A limit left as `NULL` is unrestricted.
#'
#' @details
#' Each limit is expressed in its own units and nothing is converted:
#'
#' * `straight` and `walking`: coordinate length units (metres for the Barnsbury data).
#' * `angular`: degrees of accumulated turning.
#' * `steps`: the number of direction changes (topological steps) as a whole number.
#' * `axmeter`: PST's accumulated length with topological weighting.
#'
#' When several limits are set, PST applies all of them together, following its own traversal rules.
#' Angular analyses do not accept `axmeter`. Values must fit PST's single-precision storage: very large or
#' vanishingly small values are rejected, and a `straight` limit must also have a finite square.
#' `steps` must not exceed 2147483647.
#'
#' **Several radii in one call.** One field may hold a vector of values (a *multi-radius*), for example
#' `analysis_radius(walking = c(500, 1000))`. The other fields are then fixed limits that apply to every
#' calculation, so `analysis_radius(walking = c(500, 1000), angular = 180)` means two calculations, each
#' limited to 180 degrees; no Cartesian product is formed. The order you supply is kept. Missing,
#' non-finite, invalid and duplicate values (duplicates also after narrowing to single precision) and empty
#' vectors are rejected. A radius of `0` is valid. Only [network_reach()], [network_betweenness()],
#' [angular_choice()] and [angular_integration()] accept a multi-radius; every other analysis rejects it before doing any work. See
#' <https://github.com/kimonkrenz/rPSTool/blob/main/docs/compatibility/multi-radius.md>.
#'
#' Each analysis accepts a subset of the limits; see its help page. For example,
#' [network_integration()] accepts only `steps`, and [segment_group_integration()] only `walking` and `steps`.
#'
#' @param straight,walking,angular,axmeter `NULL`, or finite non-negative numbers. One value, or several
#'   for a multi-radius (see Details).
#' @param steps `NULL`, or non-negative whole numbers no greater than 2147483647. One value, or several
#'   for a multi-radius.
#' @return A `pst_radius` object: a list of the five limits.
#' @seealso [network_reach()], [network_betweenness()], [angular_choice()], [angular_integration()]
#' @export
#' @examples
#' analysis_radius(walking = 100, steps = 3)
#' analysis_radius(walking = c(100, 500, 1000), angular = 180)
#' analysis_radius(walking = 0)  # a radius of zero is valid
#' try(analysis_radius(walking = numeric(0)))  # an empty vector is rejected
analysis_radius <- function(straight = NULL, walking = NULL, steps = NULL,
                       angular = NULL, axmeter = NULL) {
  x <- structure(list(straight = straight, walking = walking, steps = steps,
                      angular = angular, axmeter = axmeter), class = "pst_radius")
  .pst_validate_radius(x, multi = TRUE)
  x
}

.pst_radius_fields <- c("straight", "walking", "steps", "angular", "axmeter")
.pst_radius_codes <- c(straight = "s", walking = "w", steps = "n", angular = "a", axmeter = "x")

# Analyses that accept a multi-radius. A function is added here (and calls .pst_radius_plan()) when its multi-radius
# support is complete; every other analysis keeps rejecting a vector before any native work.
.pst_multi_radius_functions <- c("network_reach", "network_betweenness", "angular_choice", "angular_integration")
.pst_multi_radius_list <- function(fns = .pst_multi_radius_functions) {
  fns <- paste0(fns, "()")
  if (length(fns) == 1L) fns else paste(paste(fns[-length(fns)], collapse = ", "), "and", fns[[length(fns)]])
}

# Reject, before any native work, a radius that sets a limit the analysis does not support (`fields`: the supported fields).
# A varying field is checked like a scalar one. Returns `radius` invisibly.
.pst_radius_require_fields <- function(radius, fields, fn) {
  if (!inherits(radius, "pst_radius")) return(invisible(radius))
  other <- setdiff(.pst_radius_fields, fields)
  used <- other[!vapply(unclass(radius)[other], is.null, NA)]
  if (length(used))
    stop(fn, "() does not support the ", paste(used, collapse = ", "), " radius limit(s); supported: ",
         paste(fields, collapse = ", "), ".", call. = FALSE)
  invisible(radius)
}

# Structure and multi-radius shape of a radius object; returns the name of the varying field ("" when none).
.pst_radius_shape <- function(radius, multi) {
  if (!inherits(radius, "pst_radius") || !is.list(radius) || !identical(names(radius), .pst_radius_fields))
    stop("radius must be created by analysis_radius().", call. = FALSE)
  lens <- vapply(radius, length, 1L)
  vary <- .pst_radius_fields[lens > 1L]
  if (!multi) {
    if (length(vary))
      stop("A radius with several values (", vary[[1L]], ") is supported only by ", .pst_multi_radius_list(),
           "; this analysis takes a single value per field.", call. = FALSE)
    return("")
  }
  if (length(vary) > 1L)
    stop("At most one analysis_radius() field may have several values (found: ", paste(vary, collapse = ", "),
         "); a Cartesian product of radii is not supported.", call. = FALSE)
  if (any(vapply(radius, function(v) !is.null(v) && length(v) == 0L, NA)))
    stop("An analysis_radius() field must be NULL or hold at least one value.", call. = FALSE)
  if (length(vary)) vary else ""
}

# Expand into independent scalar pst_radius configurations (in the supplied order). Pure restructuring; no validation.
.pst_radius_expand <- function(radius, vary) {
  if (!nzchar(vary)) return(list(radius))
  lapply(seq_along(radius[[vary]]), function(i) {
    x <- radius
    x[[vary]] <- radius[[vary]][[i]]
    x
  })
}

# float32 narrowing exactly as the native boundary performs it (C cast), used only to detect values that would collide.
.pst_as_float <- function(x) readBin(writeBin(as.double(x), raw(), size = 4L), "numeric", n = length(x), size = 4L)

# Validate a radius object. Scalars: unchanged rules. With `multi`, vectors are expanded and EVERY configuration is validated
# by the scalar path (R rules + the native boundary) before anything is computed.
.pst_validate_radius <- function(radius, angular_engine = FALSE, multi = FALSE) {
  vary <- .pst_radius_shape(radius, multi)
  if (nzchar(vary)) {
    values <- radius[[vary]]
    if (!(typeof(values) %in% c("integer", "double")) || is.factor(values) || anyNA(values))
      stop("radius ", vary, " must be NULL or finite non-negative numeric values (no NA).", call. = FALSE)
    # every configuration first passes the scalar rules (range, whole steps, native float narrowing, underflow), so a value
    # outside the native range is reported as such; only valid values are then compared for duplicates
    for (config in .pst_radius_expand(radius, vary)) .pst_validate_radius(config, angular_engine)
    if (anyDuplicated(values) || (vary != "steps" && anyDuplicated(.pst_as_float(values))))
      stop("radius ", vary, " must not contain duplicate values (values that become identical native floats count as duplicates).",
           call. = FALSE)
    return(invisible(radius))
  }
  for (name in .pst_radius_fields) {
    value <- radius[[name]]
    if (is.null(value)) next
    if (name == "steps") {
      .pst_validate_steps(value)
    } else if (!(typeof(value) %in% c("integer", "double")) || is.factor(value) ||
               length(value) != 1L || !is.finite(value) || value < 0 ||
               value > 3.4028234663852886e38) {
      stop("radius ", name, " must be NULL or one finite non-negative native float value.",
           call. = FALSE)
    }
  }
  if (angular_engine && !is.null(radius$axmeter))
    stop("axmeter radius is unsupported by the pinned angular engine.", call. = FALSE)
  .Call(C_rpst_radius_validate, radius)
  invisible(radius)
}

# The radius plan of an angular call: validated scalar configurations in order, the varying field, and the fixed restrictions.
# `fields`/`fn`, when given, first reject limits the analysis does not support (before any validation or native work).
.pst_radius_plan <- function(radius, angular_engine = TRUE, fields = NULL, fn = NULL) {
  if (!is.null(fields)) .pst_radius_require_fields(radius, fields, fn)
  vary <- .pst_radius_shape(radius, TRUE)
  .pst_validate_radius(radius, angular_engine, multi = TRUE)
  configs <- .pst_radius_expand(radius, vary)
  fixed <- unclass(radius)[setdiff(.pst_radius_fields, vary)]
  list(configs = configs, varying = vary, fixed = fixed[!vapply(fixed, is.null, NA)], values = if (nzchar(vary)) radius[[vary]])
}

# Tag text of one value: the shortest %.1g..%.9g decimal that reads back to the same NATIVE float (distinct requested values
# are distinct floats, enforced at validation, so tags are unique), written in plain fixed notation with '.' as 'p'
# ('500' -> '500', '0.5' -> '0p5', '1e20' -> '100000000000000000000'). Steps are exact integers; negative zero is zero.
.pst_radius_value_text <- function(x, steps = FALSE) {
  x <- as.double(x) + 0
  if (steps) return(sprintf("%.0f", x))
  target <- .pst_as_float(x)
  for (digits in 1:9) {
    text <- sprintf("%.*g", digits, x)
    if (identical(.pst_as_float(as.numeric(text)), target)) break
  }
  gsub(".", "p", format(as.numeric(text), scientific = FALSE, digits = 15, trim = TRUE), fixed = TRUE)
}
.pst_radius_tag <- function(plan, i) {
  if (!nzchar(plan$varying)) return("")
  paste0("_", .pst_radius_codes[[plan$varying]], .pst_radius_value_text(plan$values[[i]], plan$varying == "steps"))
}
.pst_validate_steps <- function(steps) {
  if (!is.null(steps) &&
      (!(typeof(steps) %in% c("integer", "double")) || is.factor(steps) || length(steps) != 1L ||
       !is.finite(steps) || steps < 0 || steps != floor(steps) || steps > 2147483647))
    stop("steps must be NULL or one non-negative whole number no greater than 2147483647.",
         call. = FALSE)
}
.pst_resolve_radius <- function(steps, radius, angular_engine = FALSE, multi = FALSE) {
  .pst_validate_steps(steps)
  if (is.null(radius)) return(steps)
  if (!is.null(steps)) stop("Supply either steps or radius, not both.", call. = FALSE)
  .pst_validate_radius(radius, angular_engine, multi)
  radius
}
.pst_analysis_graph <- function(graph, segment = FALSE) {
  cls <- if (segment) "pst_segment_graph" else "pst_graph"
  type <- if (segment) "segment" else "axial"
  if (!inherits(graph, cls) || !is.list(graph) ||
      !identical(graph$type, type) || is.null(graph$ptr))
    stop(if (segment) "graph must be a live pst_segment_graph created by segment_graph()."
         else "graph must be a live axial pst_graph created by axial_graph().", call. = FALSE)
  graph$ptr
}
.pst_mode <- function(value, choices, parameter) {
  if (!is.character(value) || length(value) != 1L || is.na(value) || !(value %in% choices))
    stop(parameter, " must be one of: ", paste(choices, collapse = ", "), ".", call. = FALSE)
  value
}
