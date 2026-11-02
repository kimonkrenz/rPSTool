# Result columns are named by what they hold (docs/output-naming.md): `<analysis>_<distance>_<radius>[_<weight>][_<norm>][_<params>]`.
# `pick()` returns the one column of a result whose real name matches `pattern`, and fails if there is not exactly one, so a
# test states which column it means (for example "^nc_" for the node count, "^ac_.*_n$" for raw Angular Choice) without
# depending on its position.
pick <- function(x, pattern) {
  hit <- grep(pattern, names(x))
  if (length(hit) != 1L)
    stop("expected exactly one column matching '", pattern, "' in: ", paste(names(x), collapse = ", "), call. = FALSE)
  x[[hit]]
}

# The columns whose meaning depends on the normalisation suffix (docs/output-naming.md): raw and normalised Angular Choice
# (`ac_a_rw25_n`, `ac_a_rw25_c`, with optional `_at<v>`/`_ap<v>` parameters after the normalisation) and raw and normalised
# Network/Attraction Betweenness (`nb_w_rw800_n`, `nb_w_rw800_f`).
re_ac_raw  <- "^ac_.*_n(_at[0-9mp]+)?(_ap[0-9mp]+)?$"
re_ac_norm <- "^ac_.*_[tsc](_at[0-9mp]+)?(_ap[0-9mp]+)?$"
re_nb_raw  <- "^(nb|at)_.*_n$"
re_nb_norm <- "^(nb|at)_.*_[sfy]$"

# TRUE when the columns of `x` match one regular expression per column, in order.
columns_match <- function(x, patterns) {
  nms <- names(x)
  length(nms) == length(patterns) && all(mapply(grepl, patterns, nms))
}

# Assert the column layout of a result: one regular expression per column, in order.
expect_columns <- function(x, patterns) {
  testthat::expect_true(columns_match(x, patterns), info = paste("columns:", paste(names(x), collapse = ", ")))
}

# Column values without names, for comparing results whose column names legitimately
# differ (for example because one call names a weight and the other does not).
unnamed <- function(x) unname(as.list(x))

# One column of a multi-radius / multi-normalisation result, located through the
# result's own manifest (role, 1-based radius index, optional normalisation).
# Fails loudly if the column does not exist, so an absent column can never make a
# comparison vacuously pass (NULL is identical to NULL).
mcol <- function(x, role, radius = 1L, normalization = NA_character_) {
  m <- attr(x, "rpst_manifest")$columns
  testthat::expect_false(is.null(m), info = "result carries no rpst_manifest")
  want_norm <- if (is.na(normalization)) is.na(m$normalization) else (!is.na(m$normalization) & m$normalization %in% normalization)
  hit <- which(m$role == role & m$radius == radius & want_norm)
  if (length(hit) != 1L) stop("expected exactly one '", role, "' column for radius ", radius, ", found ", length(hit), call. = FALSE)
  x[[m$name[[hit]]]]
}
