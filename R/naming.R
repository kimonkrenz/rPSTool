# Output-column naming (docs/output-naming.md). One central layer: every analysis builds its result column names, and the
# manifest describing them, here. Nothing is computed; the native result columns are only labelled.
#
#   <analysis>_<distance>_<radius>[_<weight>][_<normalisation>][_<parameters>]      (measures)
#   <diagnostic>_<distance>_<radius>[_<weight>][_<parameters>]                       (diagnostics)
#
# Components that do not apply to an analysis are omitted. Column names are labels, not a format to parse: the
# `rpst:columns` manifest is authoritative.

.pst_nm_radius_codes <- c(straight = "rl", walking = "rw", steps = "rs", angular = "ra", axmeter = "ram")

# One decimal value in a name: the shortest decimal that reads back to the same native float (`.pst_radius_value_text()`),
# 'p' for the decimal point and 'm' for a minus sign.
.pst_nm_num <- function(x, exact_integer = FALSE) {
  x <- as.double(x) + 0
  text <- .pst_radius_value_text(abs(x), exact_integer)
  if (x < 0) paste0("m", text) else text
}

# Every active radius restriction in the canonical order straight, walking, steps, angular, axmeter; "rg" when none.
# `radius` is a scalar pst_radius (or plain list of its fields), a steps number, or NULL.
.pst_nm_radius <- function(radius) {
  if (is.null(radius)) return("rg")
  if (!is.list(radius)) radius <- list(steps = radius)
  radius <- unclass(radius)
  parts <- character()
  for (field in .pst_radius_fields) {
    value <- .pst_nm_dbl(radius[[field]])   # an invalid value is left to the native validation, not named
    if (is.na(value)) next
    parts <- c(parts, paste0(.pst_nm_radius_codes[[field]], .pst_nm_num(value, field == "steps")))
  }
  if (length(parts)) paste(parts, collapse = "_") else "rg"
}

# Weight identifiers that would collide with a built-in weighting code: `wl` is length weighting.
.pst_nm_reserved_weights <- "l"

# Automatic normalisation of a user weight name: lower case; every run of characters outside [a-z0-9_] becomes one '_';
# leading and trailing underscores are removed. Only a name that is empty or has no letter or digit left is an error. The
# name is never truncated and the original is kept in the metadata. Names that normalise alike (`Jobs 2021`, `Jobs-2021`,
# `jobs_2021`) give the same column name, which the collision checks then treat as the same field.
.pst_nm_weight_id <- function(name, arg) {
  if (!is.character(name) || length(name) != 1L || is.na(name) || !nzchar(name))
    stop("The weight name inferred for ", arg, " is empty.", call. = FALSE)
  # In a non-UTF-8 session R shows a non-ASCII letter as "<U+00E9>"; it is a non-ASCII character in every locale.
  id <- gsub("<u\\+[0-9a-f]+>", " ", tolower(enc2utf8(name)), perl = TRUE)
  id <- gsub("[^a-z0-9_]+", "_", id, perl = TRUE)
  id <- gsub("^_+|_+$", "", id, perl = TRUE)
  if (!grepl("[a-z0-9]", id, perl = TRUE))
    stop("The weight name \"", name, "\" inferred for ", arg, " contains no letter or digit. Assign the weights to a ",
         "descriptively named R object.", call. = FALSE)
  if (id %in% .pst_nm_reserved_weights)
    stop("The weight name \"", name, "\" inferred for ", arg, " would give the weight code 'w", id, "', which is reserved for ",
         "length weighting. Choose a longer name.", call. = FALSE)
  id
}

# The weight name of a supplied weight argument, inferred from the expression the caller wrote (captured with substitute()
# at the public function, before anything is evaluated): a plain object name (`population`) or a literal data-frame column
# (`data$population`, `data[["population"]]`). Anything else - an anonymous vector, a calculation, a do.call() value, a
# `...` element - cannot name the weights and is an error. Element names and values are never used. The name found is the
# user's own identifier; when the weights were forwarded through a wrapper function, it is the wrapper's variable name.
.pst_nm_infer_name <- function(expr) {
  if (is.symbol(expr)) {
    s <- as.character(expr)
    if (nzchar(s) && !grepl("^\\.\\.[0-9]+$", s) && s != "...") return(s)
  } else if (is.call(expr) && length(expr) == 3L) {
    key <- expr[[3L]]
    if (identical(expr[[1L]], quote(`$`)) && (is.symbol(key) || (is.character(key) && length(key) == 1L)))
      return(as.character(key))
    if (identical(expr[[1L]], quote(`[[`)) && is.character(key) && length(key) == 1L && !is.na(key) && nzchar(key))
      return(key)
  }
  stop("Cannot infer a weight name from this expression. Assign the weights to a named R object or use a data-frame column.",
       call. = FALSE)
}

# The weight component and its provenance for user-supplied numeric weights: absent weights have none; supplied weights are
# named by the expression the caller wrote. There is no fallback label.
.pst_nm_user_weight <- function(present, expr, arg, prefix = "w") {
  if (!present) return(list(code = "", name = NULL))
  name <- .pst_nm_infer_name(expr)
  list(code = paste0(prefix, .pst_nm_weight_id(name, arg)), name = name)
}

# Non-default parameter suffix. `spec` is a list, in canonical order, of list(code, value, default, kind); a parameter is
# written only when its value differs from the default (also when the default was passed explicitly). Numeric values use
# the exact-float encoding, modes their one-letter code.
# A user number as a double, or NA when it is not one finite number (the native validation then reports it, and the
# parameter is simply not written into a name).
.pst_nm_dbl <- function(x) {
  if (!is.numeric(x) || length(x) != 1L || is.factor(x) || !is.finite(x)) return(NA_real_)
  as.double(x)
}

.pst_nm_params <- function(spec) {
  out <- character()
  for (p in spec) {
    if (is.numeric(p$value) && is.na(p$value)) next
    if (identical(p$value, p$default)) next
    if (is.numeric(p$value) && is.numeric(p$default) && isTRUE(p$value == p$default)) next
    out <- c(out, paste0(p$code, if (is.numeric(p$value)) .pst_nm_num(p$value) else p$value))
  }
  paste(out, collapse = "_")
}

.pst_nm_join <- function(...) {
  parts <- c(...)
  paste(parts[!is.na(parts) & nzchar(parts)], collapse = "_")
}

# A column description: its name and the components it was built from (for the manifest).
.pst_nm_col <- function(code, role, distance = "", radius = "rg", weight = "", norm = "", params = "",
                        with_weight = TRUE, normalization = NULL, weight_name = NULL) {
  list(name = .pst_nm_join(code, distance, radius, if (with_weight) weight, norm, params),
       role = role, code = code, distance = distance, radius = radius, weight = if (with_weight) weight else "",
       normalization = if (nzchar(norm)) normalization else NULL, parameters = params,
       weight_name = weight_name)
}

.pst_nm_names <- function(cols) {
  names <- vapply(cols, function(col) col$name, "")
  if (anyDuplicated(tolower(names)))
    stop("Internal error: duplicate result column names: ", paste(unique(names[duplicated(tolower(names))]), collapse = ", "),
         call. = FALSE)
  names
}

# The manifest of the columns: a JSON array for the file metadata (`rpst:columns`).
.pst_nm_manifest <- function(cols) {
  .pst_json_array(lapply(cols, function(col) {
    col <- col[!vapply(col, function(x) is.null(x) || identical(x, ""), NA)]
    col
  }))
}

# ---- Angular analyses ---------------------------------------------------------------------------------------------

.pst_nm_angular_params <- function(threshold, precision)
  .pst_nm_params(list(list(code = "at", value = .pst_nm_dbl(threshold), default = 0),
                      list(code = "ap", value = .pst_nm_dbl(precision), default = 1)))

.pst_nm_choice_norm <- c(none = "n", standard = "s", turner = "t", syntax = "c")
.pst_nm_integration_norm <- c(turner = "t", syntax = "a", hillier = "h")

# Columns of Angular Choice for ONE radius configuration, in the order of the native result: raw choice, node_count,
# total_depth, [total_depth_weight], then one column per requested normalisation other than "none".
.pst_nm_angular_choice <- function(radius, weighted, norms, threshold, precision) {
  r <- .pst_nm_radius(radius); w <- if (weighted) "wl" else ""; p <- .pst_nm_angular_params(threshold, precision)
  cols <- list(.pst_nm_col("ac", "choice", "a", r, w, "n", p, normalization = "none"),
               .pst_nm_col("nc", "node_count", "a", r, params = p, with_weight = FALSE),
               .pst_nm_col("td", "total_depth", "a", r, params = p, with_weight = FALSE))
  if (weighted) cols[[4L]] <- .pst_nm_col("tdw", "total_depth_weight", "a", r, w, params = p)
  for (n in setdiff(norms, "none"))
    cols[[length(cols) + 1L]] <- .pst_nm_col("ac", "normalized", "a", r, w, .pst_nm_choice_norm[[n]], p, normalization = n)
  cols
}

# Columns of Angular Integration for ONE radius configuration: one integration per requested normalisation, node_count,
# total_depth, [total_weight, total_depth_weight].
.pst_nm_angular_integration <- function(radius, weighted, weight_outputs, norms, threshold, precision) {
  r <- .pst_nm_radius(radius); p <- .pst_nm_angular_params(threshold, precision)
  w <- if (weighted) "wl" else ""   # unweighted totals carry no weight component (see docs/output-naming.md)
  cols <- lapply(norms, function(n)
    .pst_nm_col("ai", "integration", "a", r, if (weighted) "wl" else "", .pst_nm_integration_norm[[n]], p, normalization = n))
  cols <- c(cols, list(.pst_nm_col("nc", "node_count", "a", r, params = p, with_weight = FALSE),
                       .pst_nm_col("td", "total_depth", "a", r, params = p, with_weight = FALSE)))
  if (weighted || weight_outputs)
    cols <- c(cols, list(.pst_nm_col("tw", "total_weight", "a", r, w, params = p),
                         .pst_nm_col("tdw", "total_depth_weight", "a", r, w, params = p)))
  cols
}

# ---- Axial analyses -----------------------------------------------------------------------------------------------

.pst_nm_network_reach <- function(radius) {
  r <- .pst_nm_radius(radius)
  list(.pst_nm_col("rc", "reached_count", "", r), .pst_nm_col("rln", "reached_length", "", r),
       .pst_nm_col("rca", "reached_area", "", r))
}

.pst_nm_network_integration <- function(radius) {
  r <- .pst_nm_radius(radius)
  list(.pst_nm_col("ni", "integration", "s", r), .pst_nm_col("nc", "node_count", "s", r),
       .pst_nm_col("td", "total_depth", "s", r))
}
.pst_nm_junction <- function(radius) list(.pst_nm_col("nj", "junction_integration", "s", .pst_nm_radius(radius)))

.pst_nm_distance_codes <- c(straight = "l", walking = "w", steps = "s", angular = "a", axmeter = "am",
                            weights = "d", none = "")

.pst_nm_betweenness_norm <- c(none = "n", standard = "s", freeman = "f", syntax = "y")
.pst_nm_network_betweenness <- function(radius, distance, normalization, weight, attraction) {
  r <- .pst_nm_radius(radius); d <- .pst_nm_distance_codes[[distance]]; code <- if (attraction) "at" else "nb"
  # PST skips origins whose effective weight is not positive and then writes neither count nor depth, so for weighted and
  # attraction runs the diagnostics depend on the weights and carry them; attraction runs have their own codes (anc, atd)
  # because their origins are the lines that received attraction weight.
  nc <- if (attraction) "anc" else "nc"; td <- if (attraction) "atd" else "td"
  cols <- list(.pst_nm_col(code, "betweenness", d, r, weight$code, "n", normalization = "none", weight_name = weight$name),
               .pst_nm_col(nc, "node_count", d, r, weight$code, weight_name = weight$name),
               .pst_nm_col(td, "total_depth", d, r, weight$code, weight_name = weight$name))
  # `normalization` holds one or more names; the raw score above is always present, so "none" adds nothing
  for (n in setdiff(normalization, "none"))
    cols[[length(cols) + 1L]] <- .pst_nm_col(code, "normalized", d, r, weight$code, .pst_nm_betweenness_norm[[n]],
                                             normalization = n, weight_name = weight$name)
  cols
}

.pst_nm_origin_codes <- c(lines = "l", junctions = "j", points = "p", point_groups = "g")

.pst_nm_attraction_reach <- function(radius, origin, distance, weight, decay, decay_constant, distribution, collection,
                                     polygon_point_interval) {
  r <- .pst_nm_radius(radius); d <- .pst_nm_distance_codes[[distance]]
  default_constant <- if (identical(decay, "constant")) 0 else 1
  decay_codes <- c(constant = "c", power = "p", curve = "v", divide = "d")
  p <- .pst_nm_params(list(
    list(code = "or", value = unname(.pst_nm_origin_codes[[origin]]), default = "l"),
    list(code = "dc", value = unname(decay_codes[[decay]]), default = "c"),
    list(code = "dk", value = .pst_nm_dbl(decay_constant), default = default_constant),
    list(code = "ds", value = if (identical(distribution, "copy")) "c" else "d", default = "d"),
    list(code = "cl", value = unname(c(mean = "m", sum = "s", min = "n", max = "x")[[collection]]), default = "m"),
    list(code = "pi", value = if (is.null(polygon_point_interval)) NULL else .pst_nm_dbl(polygon_point_interval), default = NULL)))
  list(.pst_nm_col("ar", "attraction_reach", d, r, weight$code, params = p, weight_name = weight$name))
}

.pst_nm_attraction_distance <- function(radius, origin, distance, weight, point_edge_weight, polygon_point_interval,
                                        destination_indices) {
  r <- .pst_nm_radius(radius); d <- .pst_nm_distance_codes[[distance]]
  p <- .pst_nm_params(list(
    list(code = "or", value = unname(.pst_nm_origin_codes[[origin]]), default = "l"),
    list(code = "pe", value = .pst_nm_dbl(point_edge_weight), default = 0),
    list(code = "pi", value = if (is.null(polygon_point_interval)) NULL else .pst_nm_dbl(polygon_point_interval), default = NULL)))
  cols <- list(.pst_nm_col("ad", "attraction_distance", d, r, weight$code, params = p, weight_name = weight$name))
  if (destination_indices) cols[[2L]] <- .pst_nm_col("di", "destination_index", d, r, weight$code, params = p, weight_name = weight$name)
  cols
}

.pst_nm_od_betweenness <- function(radius, distance, destination_mode, origin_weight, destination_weight) {
  r <- .pst_nm_radius(radius); d <- .pst_nm_distance_codes[[distance]]
  p <- .pst_nm_params(list(list(code = "dm", value = if (identical(destination_mode, "closest")) "c" else "a", default = "a")))
  list(.pst_nm_col("od", "od_betweenness", d, r, .pst_nm_join(origin_weight$code, destination_weight$code), params = p,
                   weight_name = if (is.null(origin_weight$name) && is.null(destination_weight$name)) NULL else
                     paste(c(if (!is.null(origin_weight$name)) paste0("origin: ", origin_weight$name),
                             if (!is.null(destination_weight$name)) paste0("destination: ", destination_weight$name)),
                           collapse = "; ")))
}

.pst_nm_segment_group_integration <- function(radius) {
  r <- .pst_nm_radius(radius)
  list(.pst_nm_col("gi", "integration", "", r), .pst_nm_col("nc", "node_count", "", r), .pst_nm_col("td", "total_depth", "", r))
}

#' Result column names
#'
#' Every analysis names its result columns with one compact scheme, so that a column identifies the analysis, distance,
#' radius, weighting, normalisation and any non-default analytical parameter, and so that successive results can be
#' accumulated in one table or spatial dataset.
#'
#' @details
#' Measures are named `<analysis>_<distance>_<radius>[_<weight>][_<normalisation>][_<parameters>]` and diagnostics
#' `<diagnostic>_<distance>_<radius>[_<weight>][_<parameters>]`, in lower case with underscores. Components that do not
#' apply are omitted. A scalar call and a multi-radius call name the same calculation identically.
#'
#' * **Analysis:** `ni` Network Integration (`nj` its junction score), `nb` Network Betweenness, `at` Attraction
#'   Betweenness (`network_betweenness()` with `attraction_points`), `ai` Angular Integration, `ac` Angular Choice (PST's
#'   Angular Betweenness), `ar` Attraction Reach, `ad` Attraction Distance, `od` Origin-Destination Betweenness, `gi`
#'   segment-group integration.
#' * **Distance:** `a` angular, `w` walking, `s` steps, `l` straight line, `am` axmeter, `d` custom per-line cost.
#'   Omitted where the analysis has none (Network Reach, segment groups, `distance = "none"`).
#' * **Radius:** `rl`, `rw`, `rs`, `ra`, `ram` followed by the full value (`rw3000`, `rs3`, `rw0p5`; `p` is the decimal
#'   point and thousands are never abbreviated), every active restriction in the order straight, walking, steps,
#'   angular, axmeter; `rg` when unrestricted.
#' * **Weight:** none when unweighted (including the unit-weight totals of an unweighted Angular Integration), `wl`
#'   length weighting, `w<name>` custom weights, named after the R object or data-frame column you pass (`weights = population`
#'   gives `wpopulation`; anonymous vectors and calculations are errors), and `wo<name>` and `wd<name>` origin and destination
#'   weights of [od_betweenness()], each named independently.
#' * **Normalisation:** `t` Turner, `a` NAIN, `c` NACH, `h` Hillier, `s` standard, `f` Freeman, `y` Network Betweenness
#'   `syntax`, `n` raw.
#' * **Diagnostics:** `nc` node count, `td` total depth, `tw` total weight, `tdw` total depth weight, `rc` reached
#'   count, `rln` reached length, `rca` reached area, `di` destination index; `anc` and `atd` are the node count and total
#'   depth of Attraction Betweenness. The diagnostics of weighted runs carry the weight component,
#'   because PST skips origins without positive weight.
#' * **Parameters:** written only when different from the default, in a fixed order: `at<v>` `angle_threshold`, `ap<v>`
#'   `angle_precision`, `or<x>` `origin`, `dc<x>` `decay`, `dk<v>` `decay_constant`, `ds<x>` `distribution`, `cl<x>`
#'   `collection`, `pe<v>` `point_edge_weight`, `pi<v>` `polygon_point_interval`, `dm<x>` `destination_mode`.
#'
#' For example, `ai_a_rw3000_t` is Angular Integration with angular distance, a 3000 walking radius and Turner
#' normalisation, and `ac_a_rw3000_c_at12` is Angular Choice with NACH normalisation and `angle_threshold = 12`.
#'
#' @section Naming custom weights:
#' Custom weights are named in the result columns (`..._wpopulation_...`) after the R expression you supply, so no extra
#' argument is needed: an object name (`weights = population`) or a literal data-frame column (`weights = data$population`
#' or `weights = data[["population"]]`). An anonymous vector (`c(1, 2, 3)`) or a calculation (`data$population / 1000`) has
#' no name and is an error raised before any computation: assign it to a named object first. The name is lower-cased, every
#' run of characters outside `a-z`, `0-9` and `_` becomes one `_`, and leading and trailing underscores are dropped
#' (`Jobs-2021` gives `jobs_2021`); a name with no letter or digit left is an error. The original name is kept in the result
#' metadata. Names are read from the call, never from values or element names; weights forwarded through a wrapper function
#' are named by the wrapper's variable, and `do.call()` with values cannot be named (pass named objects instead). The name
#' is a label only: it does not check that the same name always means the same values. [network_betweenness()],
#' [attraction_reach()], [attraction_distance()] and [od_betweenness()] follow these rules for their weight arguments.
#'
#' The names are labels: the `rpst:columns` manifest in result-file metadata, and the `rpst_manifest` attribute of
#' multi-radius data frames, describe each column authoritatively. The full tables and examples are in
#' `docs/output-naming.md` in the repository.
#'
#' @name result_column_names
#' @aliases result_column_names
#' @seealso [angular_integration()], [angular_choice()], [network_betweenness()], [pst_result_file]
NULL
