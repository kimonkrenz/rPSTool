#' Specify independent PST analysis radii
#'
#' Each non-NULL field sets a native limit; NULL leaves that field unrestricted.
#' Limits combine according to PST's traversal semantics. Straight and walking
#' use coordinate length units, angular uses degrees, and axmeter is PST's
#' accumulated length with topological weighting. No units are converted.
#' Angular analyses reject axmeter, which their pinned engine does not consume.
#' Native float narrowing is checked for overflow and underflow; straight also
#' requires a finite float square. Steps use signed native integer storage.
#'
#' A field may also be a vector of several values (a *multi-radius*). At most one field
#' may hold more than one value; the other fields are fixed restrictions that apply to every
#' calculation. The result is never a Cartesian product: `analysis_radius(walking = c(500, 1000),
#' angular = 180)` means two calculations, each limited to 180 degrees. The supplied order is
#' kept; `NA`, non-finite, invalid and duplicate values (duplicates also after narrowing to the native float)
#' are rejected, as are empty vectors such as `numeric(0)` (a field must be `NULL` or hold at least one value).
#' A radius of `0` is a valid value. Only [angular_choice()] and [angular_integration()]
#' accept a multi-radius; every other analysis rejects it before doing any work. Each radius is
#' expanded into an independent scalar configuration that passes the unchanged scalar
#' validation. See <https://github.com/kimonkrenz/rPSTool/blob/main/docs/compatibility/multi-radius.md>.
#'
#' @param straight,walking,angular,axmeter NULL, or finite nonnegative numeric value(s); one scalar or a vector (see Details).
#' @param steps NULL, or nonnegative whole number(s) at most 2147483647; one scalar or a vector.
#' @return A `pst_radius` list of five independent limits.
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

# Structure and multi-radius shape of a radius object; returns the name of the varying field ("" when none).
.pst_radius_shape <- function(radius, multi) {
  if (!inherits(radius, "pst_radius") || !is.list(radius) || !identical(names(radius), .pst_radius_fields))
    stop("radius must be created by analysis_radius().", call. = FALSE)
  lens <- vapply(radius, length, 1L)
  vary <- .pst_radius_fields[lens > 1L]
  if (!multi) {
    if (length(vary))
      stop("A radius with several values (", vary[[1L]], ") is supported only by angular_choice() and ",
           "angular_integration(); this analysis takes a single value per field.", call. = FALSE)
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
.pst_radius_plan <- function(radius, angular_engine = TRUE) {
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
