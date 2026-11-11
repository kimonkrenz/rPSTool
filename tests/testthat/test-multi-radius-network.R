# Multi-radius Network Reach and Segment Betweenness, with multiple Betweenness normalisations
# (docs/compatibility/multi-radius.md). Every multi column must equal the independently executed scalar call; PST runs once per radius;
# the file routes hold the same table as the in-memory result. Parquet checks need the optional arrow package and are skipped (not
# weakened) where it is missing; FlatGeobuf checks need sf and jsonlite.

nm_segments <- function() {
  set.seed(11)
  n <- 40
  x <- cumsum(runif(n, 1, 3)); y <- cumsum(rnorm(n))
  s <- cbind(x[-n], y[-n], x[-1], y[-1])
  unname(rbind(s, cbind(s[8:22, 1], s[8:22, 2], s[8:22, 1] + 1, s[8:22, 2] + 5)))
}
nm_graph <- function() axial_graph(nm_segments())
nm_axial_counts <- function(reset = FALSE) .Call(rPSTool:::C_rpst_axial_instrumentation, reset, NULL)[1:3]   # reach, betweenness, normalisers
nm_fail_after <- function(k) invisible(.Call(rPSTool:::C_rpst_axial_instrumentation, FALSE, as.double(k)))
nm_skip_fgb <- function() { skip_if_not_installed("sf"); skip_if_not_installed("jsonlite") }
nm_meta <- function(path) {
  raw <- .Call(rPSTool:::C_rpst_fgb_columns, enc2native(path))$metadata
  jsonlite::fromJSON(rawToChar(raw), simplifyVector = FALSE)
}
# the radius configuration of the i-th radius of a plan, as a scalar pst_radius
nm_config <- function(radius, i) rPSTool:::.pst_radius_plan(radius, FALSE)$configs[[i]]

# Every named column of the multi result equals, value and type, the same-named column of the scalar call with that radius.
nm_expect_columns_match_scalar <- function(multi, radius, scalar_fn) {
  plan <- rPSTool:::.pst_radius_plan(radius, FALSE)
  manifest <- attr(multi, "rpst_manifest")$columns
  seen <- character()
  for (i in seq_along(plan$configs)) {
    scalar <- scalar_fn(plan$configs[[i]])
    expect_null(attr(scalar, "rpst_manifest"))                          # a scalar call keeps the single-result schema
    for (nm in setdiff(names(scalar), c("line_id", "origin_id"))) {
      expect_true(nm %in% names(multi), info = nm)
      expect_identical(multi[[nm]], scalar[[nm]], info = nm)            # exact values and types
      expect_identical(manifest$radius[match(nm, manifest$name)], i)
      seen <- c(seen, nm)
    }
  }
  # nothing else is in the table, and no column is repeated
  expect_identical(setdiff(names(multi), c("line_id", "origin_id")), seen)
  expect_false(anyDuplicated(names(multi)) > 0)
}

# network_betweenness() names user weights after the R object they were passed as, so calls go through this wrapper, in which the
# weights are always the object `weights` (columns carry `wweights`).
nm_between <- function(g, radius, distance = "steps", normalization = "none", weights = NULL, attraction_points = NULL, ...)
  network_betweenness(g, radius, distance = distance, normalization = normalization, weights = weights,
                      attraction_points = attraction_points, ...)

nm_norm_sets <- list("none", "standard", "freeman", "syntax", c("none", "standard", "freeman", "syntax"),
                     c("syntax", "freeman", "none"), c("standard", "syntax"))

test_that("Network Reach: every radius column equals the scalar call, in the supplied order, for every radius field", {
  g <- nm_graph()
  radii <- list(analysis_radius(walking = c(8, 3, 20)), analysis_radius(steps = c(2, 1, 4), straight = 15),
                analysis_radius(straight = c(5, 12)), analysis_radius(angular = c(90, 45), walking = 30),
                analysis_radius(axmeter = c(10, 40)))
  origins <- rbind(c(1, 1), c(5, 2), c(12, 8))
  for (r in radii) {
    for (o in list(NULL, origins)) {
      multi <- network_reach(g, r, origins = o)
      expect_identical(names(multi)[[1L]], if (is.null(o)) "line_id" else "origin_id")
      expect_identical(nrow(multi), if (is.null(o)) 54L else 3L)
      expect_identical(vapply(multi, typeof, ""), c(setNames("integer", names(multi)[1L]),
        setNames(rep(c("integer", "double", "double"), length(rPSTool:::.pst_radius_plan(r, FALSE)$configs)),
                 names(multi)[-1L])))
      nm_expect_columns_match_scalar(multi, r, function(cfg) network_reach(g, cfg, origins = o))
    }
  }
  # radius-major, in the supplied order
  m <- network_reach(g, analysis_radius(walking = c(8, 3, 20)))
  expect_identical(names(m), c("line_id", "rc_rw8", "rln_rw8", "rca_rw8", "rc_rw3", "rln_rw3", "rca_rw3",
                               "rc_rw20", "rln_rw20", "rca_rw20"))
})

test_that("Segment Betweenness: every radius and normalisation column equals the scalar call", {
  g <- nm_graph()
  set.seed(3)
  weights <- c(0, runif(52, 0, 4), 0)                      # zero weights: PST skips those origins (NA diagnostics)
  attractions <- rbind(c(2, 1), c(6, 3), c(10, 7), c(13, 9))
  aweights <- c(1, 0, 2.5, 3)
  cases <- list(
    list(radius = analysis_radius(walking = c(8, 3, 20)), distance = "walking"),
    list(radius = analysis_radius(steps = c(2, 1, 4)), distance = "steps"),
    list(radius = analysis_radius(angular = c(120, 60), straight = 40), distance = "angular"),
    list(radius = analysis_radius(axmeter = c(15, 40)), distance = "axmeter"),
    list(radius = analysis_radius(walking = c(8, 30)), distance = "steps", weights = weights),
    list(radius = analysis_radius(steps = c(2, 3)), distance = "walking", attraction_points = attractions, weights = aweights),
    list(radius = analysis_radius(walking = c(0, 5)), distance = "steps", attraction_points = attractions))
  for (case in cases) {
    for (norms in nm_norm_sets) {
      multi <- nm_between(g, case$radius, case$distance, norms, case$weights, case$attraction_points)
      k <- length(rPSTool:::.pst_radius_plan(case$radius, FALSE)$configs)
      scalar_fn <- function(cfg) {
        parts <- lapply(setdiff(norms, "none"), function(n)
          nm_between(g, cfg, case$distance, n, case$weights, case$attraction_points))
        raw <- nm_between(g, cfg, case$distance, "none", case$weights, case$attraction_points)
        # the scalar call per normaliser repeats raw/diagnostics; assemble the columns the multi call must contain
        cols <- raw
        for (p in parts) cols <- cbind(cols, p[setdiff(names(p), names(cols))])
        cols
      }
      nm_expect_columns_match_scalar(multi, case$radius, scalar_fn)
      # raw, node count and total depth once per radius; one normalised column per requested normaliser other than "none"
      expect_identical(ncol(multi), 1L + k * (3L + length(setdiff(norms, "none"))))
      # the order of normalisations is the requested order, per radius
      per <- names(multi)[2:(1L + 3L + length(setdiff(norms, "none")))]
      codes <- c(standard = "s", freeman = "f", syntax = "y")[setdiff(norms, "none")]
      expect_identical(sub(".*_([sfy])$", "\\1", per[-(1:3)]), unname(codes))
    }
  }
})

test_that("scalar calls keep the scalar schema and value; a single-element vector is a scalar call", {
  g <- nm_graph()
  r <- analysis_radius(steps = 2)
  expect_null(attr(network_reach(g, r), "rpst_manifest"))
  expect_null(attr(network_betweenness(g, r), "rpst_manifest"))
  expect_null(attr(network_betweenness(g, r, normalization = c("standard")), "rpst_manifest"))
  expect_identical(names(network_betweenness(g, r, normalization = "freeman")),
                   c("line_id", "nb_s_rs2_n", "nc_s_rs2", "td_s_rs2", "nb_s_rs2_f"))
  expect_identical(names(network_reach(g, analysis_radius(walking = c(5)))), c("line_id", "rc_rw5", "rln_rw5", "rca_rw5"))
  # a multi call has a manifest (schema 2) and says which radius each column belongs to
  m <- network_betweenness(g, analysis_radius(steps = c(2, 3)), normalization = c("none", "freeman"))
  man <- attr(m, "rpst_manifest")
  expect_identical(man$columns$radius, rep(1:2, each = 4L))
  expect_identical(man$columns$role, rep(c("betweenness", "node_count", "total_depth", "normalized"), 2L))
  expect_identical(man$columns$normalization, rep(c(NA, NA, NA, "freeman"), 2L))
  expect_length(man$radii, 2L)
  # one-element normalisation vectors of every kind keep working; invalid ones fail as before
  for (n in c("none", "standard", "freeman", "syntax")) expect_s3_class(network_betweenness(g, r, normalization = n), "data.frame")
  expect_error(network_betweenness(g, r, normalization = "bogus"), "normalization must be one of")
})

test_that("invalid requests are rejected before any calculation", {
  g <- nm_graph()
  nm_axial_counts(TRUE)
  expect_error(analysis_radius(walking = c(5, 5)), "duplicate")
  expect_error(analysis_radius(walking = c(1, 1 + 2^-40)), "identical native floats")
  expect_error(analysis_radius(walking = c(1, 2), steps = c(1, 2)), "At most one")
  expect_error(analysis_radius(walking = c(1, NA)), "NA")
  expect_error(analysis_radius(walking = numeric(0)), "at least one")
  expect_error(network_reach(g, analysis_radius(walking = c(5, 10)), origins = rbind(c(1, 1), c(NA, 2))), "finite|NA|origins")
  expect_error(network_reach(g, list(walking = c(5, 10))), "analysis_radius")
  expect_error(network_betweenness(g, analysis_radius(walking = c(5, 10)), distance = "bogus"), "distance must be one of")
  expect_error(network_betweenness(g, analysis_radius(walking = c(5, 10)), normalization = c("freeman", "bogus")), "one or more of")
  expect_error(network_betweenness(g, analysis_radius(walking = c(5, 10)), normalization = c("freeman", "freeman")), "duplicates")
  expect_error(network_betweenness(g, analysis_radius(walking = c(5, 10)), normalization = character()), "one or more of|must be one of")
  w3 <- 1:3
  expect_error(network_betweenness(g, analysis_radius(walking = c(5, 10)), weights = w3), "one value per")
  expect_error(network_betweenness(g, analysis_radius(walking = c(5, 10)), normalization = NA_character_), "one or more of|must be one of")
  # a wrong graph is still refused first
  expect_error(network_reach(segment_graph(nm_segments()), analysis_radius(walking = c(5, 10))), "axial")
  expect_error(network_betweenness(segment_graph(nm_segments()), analysis_radius(walking = c(5, 10))), "axial")
  expect_identical(nm_axial_counts(TRUE), c(0, 0, 0))   # no PST run happened for any of them
  # the unchanged analyses still refuse a vector
  expect_error(attraction_reach(g, rbind(c(0, 0)), analysis_radius(steps = c(1, 2))), "supported only by")
  # the error text names the analyses that accept one
  expect_error(attraction_distance(g, rbind(c(0, 0)), analysis_radius(steps = c(1, 2))),
               paste0("supported only by ", rPSTool:::.pst_multi_radius_list(), ";"), fixed = TRUE)
})

test_that("a radius a scalar call would reject is rejected when it is one of several", {
  g <- nm_graph()
  nm_axial_counts(TRUE)
  # the unchanged scalar rules apply to each configuration (here: the native float range of a fixed restriction)
  bad <- structure(list(straight = NULL, walking = c(5, 10), steps = NULL, angular = NULL, axmeter = 1e39), class = "pst_radius")
  expect_error(network_reach(g, bad), "finite non-negative")
  expect_error(network_betweenness(g, bad), "finite non-negative")
  # the same value is also refused as a scalar
  expect_error(network_reach(g, structure(list(straight = NULL, walking = 5, steps = NULL, angular = NULL, axmeter = 1e39),
                                          class = "pst_radius")), "finite non-negative")
  expect_identical(nm_axial_counts(TRUE), c(0, 0, 0))
})

test_that("PST runs once per radius and each normaliser is applied once per radius", {
  g <- nm_graph()
  nm_axial_counts(TRUE)
  network_betweenness(g, analysis_radius(walking = c(5, 10, 15, 20)), normalization = c("standard", "freeman", "syntax", "none"))
  expect_identical(nm_axial_counts(TRUE), c(0, 4, 12))                 # 4 runs; 3 normalisers x 4 radii
  network_betweenness(g, analysis_radius(walking = c(5, 10, 15, 20)), normalization = "none")
  expect_identical(nm_axial_counts(TRUE), c(0, 4, 0))
  network_reach(g, analysis_radius(steps = c(1, 2, 3)))
  expect_identical(nm_axial_counts(TRUE), c(3, 0, 0))
  network_betweenness(g, analysis_radius(walking = 5), normalization = "freeman")   # scalar: one run, one normaliser
  expect_identical(nm_axial_counts(TRUE), c(0, 1, 1))
})

test_that("a failure in a later radius reports the error, leaves the graph usable and changes nothing", {
  g <- nm_graph()
  before_reach <- network_reach(g, analysis_radius(steps = 2))
  before_between <- network_betweenness(g, analysis_radius(steps = 2))
  for (k in 0:2) {
    nm_axial_counts(TRUE); nm_fail_after(k)
    expect_error(network_betweenness(g, analysis_radius(walking = c(5, 10, 15)), normalization = c("freeman", "syntax")),
                 "injected native failure")
    nm_fail_after(-1)
    nm_fail_after(k)
    expect_error(network_reach(g, analysis_radius(steps = c(1, 2, 3))), "injected native failure")
    nm_fail_after(-1)
  }
  expect_identical(network_reach(g, analysis_radius(steps = 2)), before_reach)
  expect_identical(network_betweenness(g, analysis_radius(steps = 2)), before_between)
  expect_identical(nrow(network_betweenness(g, analysis_radius(steps = c(1, 2)))), 54L)
})

test_that("empty diagnostics: all-zero weights give NA diagnostics and NA Freeman and syntax values for every radius", {
  g <- nm_graph()
  r <- analysis_radius(steps = c(1, 2))
  zero <- rep(0, 54)
  multi <- nm_between(g, r, "steps", c("standard", "freeman", "syntax"), zero)
  nm_expect_columns_match_scalar(multi, r, function(cfg) {
    raw <- nm_between(g, cfg, "steps", "none", zero)
    for (n in c("standard", "freeman", "syntax")) raw <- cbind(raw, nm_between(g, cfg, "steps", n, zero)[-(1:4)])
    raw
  })
  man <- attr(multi, "rpst_manifest")$columns
  for (nm in man$name[man$role %in% c("node_count", "total_depth")]) expect_true(all(is.na(multi[[nm]])), info = nm)
  for (nm in man$name[!is.na(man$normalization) & man$normalization %in% c("freeman", "syntax")]) expect_true(all(is.na(multi[[nm]])), info = nm)
  for (nm in man$name[!is.na(man$normalization) & man$normalization == "standard"]) expect_false(anyNA(multi[[nm]]), info = nm)
})

test_that("weights are named in every radius' columns", {
  g <- nm_graph()
  population <- seq_len(54)
  m <- network_betweenness(g, analysis_radius(steps = c(1, 2)), weights = population, normalization = c("none", "syntax"))
  expect_identical(names(m), c("line_id", "nb_s_rs1_wpopulation_n", "nc_s_rs1_wpopulation", "td_s_rs1_wpopulation",
                               "nb_s_rs1_wpopulation_y", "nb_s_rs2_wpopulation_n", "nc_s_rs2_wpopulation",
                               "td_s_rs2_wpopulation", "nb_s_rs2_wpopulation_y"))
  expect_error(network_betweenness(g, analysis_radius(steps = c(1, 2)), weights = population * 2), "named|assign")
})

# ---- file output ------------------------------------------------------------------------------------------------------------

nm_w30 <- rep(c(0, 1, 2), 10)
nm_fgb_graph <- function(dir, n = 30) {
  src <- so_write_fgb(file.path(dir, "net.fgb"), so_segments(n))
  list(src = src, g = axial_graph(src))
}

test_that("FlatGeobuf spatial output of multi-radius Network Reach and Betweenness equals the in-memory result", {
  nm_skip_fgb()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE))
  s <- nm_fgb_graph(dir); g <- s$g
  attrs <- names(so_attributes(30))
  cases <- list(
    reach = list(call = function(...) network_reach(g, analysis_radius(steps = c(1, 2, 3)), ...), fn = "network_reach",
                 vary = "steps", expect_cols = 9L),
    between = list(call = function(...) network_betweenness(g, analysis_radius(walking = c(30, 10, 60), steps = 6),
                                                          normalization = c("freeman", "none", "standard", "syntax"), ...),
                   fn = "network_betweenness", vary = "walking", expect_cols = 18L),
    weighted = list(call = function(...) network_betweenness(g, analysis_radius(steps = c(2, 3)), weights = nm_w30,
                                                           normalization = c("freeman", "syntax"), ...),
                    fn = "network_betweenness", vary = "steps", expect_cols = 10L))
  for (nm in names(cases)) {
    case <- cases[[nm]]
    frame <- case$call()
    out <- file.path(dir, paste0(nm, ".fgb"))
    res <- case$call(spatial_output_file = out)
    expect_s3_class(res, "pst_result_file")
    expect_identical(so_leftovers(dir), character())
    back <- so_read(out, "flatgeobuf")
    result_names <- setdiff(names(frame), "line_id")
    expect_identical(back$names, c(attrs, result_names))
    expect_identical(ncol(frame) - 1L, case$expect_cols)
    for (col in result_names) {
      expect_identical(is.na(back$attrs[[col]]), is.na(frame[[col]]), info = col)          # nulls are the NA rows
      expect_equal(as.numeric(back$attrs[[col]]), as.numeric(frame[[col]]), tolerance = 0, info = col)
    }
    expect_identical(back$wkb, so_wkb_of(s$src))
    meta <- nm_meta(out)
    expect_identical(meta[["rpst:schema"]], "2")
    expect_identical(meta[["rpst:function"]], case$fn)
    expect_identical(meta[["rpst:graph_type"]], "axial")
    expect_identical(meta[["rpst:graph_rows"]], "30")
    expect_identical(meta[["rpst:radius_varying"]], case$vary)
    cols <- jsonlite::fromJSON(meta[["rpst:columns"]], simplifyVector = FALSE)
    expect_identical(vapply(cols, function(x) x$name, ""), result_names)
    expect_equal(vapply(cols, function(x) x$radius, 1), attr(frame, "rpst_manifest")$columns$radius)
    expect_identical(meta[["rpst:radius_configurations"]] |> jsonlite::fromJSON(simplifyVector = FALSE) |> length(),
                     length(attr(frame, "rpst_manifest")$radii))
  }
  # the metadata records fixed restrictions and normalisations
  m <- nm_meta(file.path(dir, "between.fgb"))
  expect_identical(jsonlite::fromJSON(m[["rpst:radius_fixed"]], simplifyVector = FALSE), list(steps = 6L))
  expect_identical(unlist(jsonlite::fromJSON(m[["rpst:normalizations"]], simplifyVector = FALSE)),
                   c("freeman", "none", "standard", "syntax"))
  expect_identical(jsonlite::fromJSON(m[["rpst:parameters"]], simplifyVector = FALSE)$distance, "steps")
  # scalar calls keep the scalar file schema
  out <- file.path(dir, "scalar.fgb")
  network_reach(g, analysis_radius(steps = 2), spatial_output_file = out)
  expect_identical(nm_meta(out)[["rpst:schema"]], "1")
  out <- file.path(dir, "scalar-b.fgb")
  network_betweenness(g, analysis_radius(steps = 2), normalization = "syntax", spatial_output_file = out)
  expect_identical(nm_meta(out)[["rpst:schema"]], "1")
})

test_that("multi-radius file output keeps the collision, overwrite and failure guarantees", {
  nm_skip_fgb()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE))
  s <- nm_fgb_graph(dir); g <- s$g
  r <- analysis_radius(steps = c(1, 2, 3))
  out <- file.path(dir, "out.fgb")
  network_betweenness(g, r, normalization = c("freeman", "syntax"), spatial_output_file = out)
  md5 <- so_md5(out)
  expect_error(network_betweenness(g, r, spatial_output_file = out), "already exists")
  expect_identical(so_md5(out), md5)                                   # never replaced without overwrite
  # a failure on a later radius publishes nothing and leaves a pre-existing file untouched
  for (fn in list(function(o) network_betweenness(g, r, normalization = "freeman", spatial_output_file = o, overwrite = TRUE),
                  function(o) network_reach(g, r, spatial_output_file = o, overwrite = TRUE))) {
    nm_fail_after(1)
    expect_error(fn(out), "injected native failure")
    nm_fail_after(-1)
    expect_identical(so_md5(out), md5)
    fresh <- file.path(dir, "fresh.fgb")
    nm_fail_after(2)
    expect_error(fn(fresh), "injected native failure")
    nm_fail_after(-1)
    expect_false(file.exists(fresh))
    expect_identical(so_leftovers(dir), character())
  }
  expect_s3_class(network_betweenness(g, r, normalization = "syntax", spatial_output_file = out, overwrite = TRUE), "pst_result_file")
  expect_false(identical(so_md5(out), md5))
  expect_identical(nrow(network_betweenness(g, analysis_radius(steps = 2))), 30L)   # the graph is still usable
  # requests that fail validation create nothing
  nm_axial_counts(TRUE)
  expect_error(network_betweenness(g, r, normalization = "bogus", spatial_output_file = file.path(dir, "x.fgb")), "one or more of|must be one of")
  expect_error(network_betweenness(g, r, spatial_output_file = file.path(dir, "x.parquet")), "must end in")
  expect_error(network_reach(g, r, output_file = file.path(dir, "o.parquet"), spatial_output_file = file.path(dir, "x.fgb")), "mutually exclusive")
  expect_identical(nm_axial_counts(TRUE), c(0, 0, 0))
  expect_identical(sort(list.files(dir)), sort(c("net.fgb", "out.fgb")))
})

test_that("Network Reach with origins keeps its spatial-output restriction for a multi-radius call", {
  nm_skip_fgb()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE))
  g <- nm_fgb_graph(dir)$g
  expect_error(network_reach(g, analysis_radius(steps = c(1, 2)), origins = rbind(c(105, 205)),
                             spatial_output_file = file.path(dir, "o.fgb")), "not one-to-one")
  expect_identical(list.files(dir), "net.fgb")
})

skip_nm_parquet <- function() {
  skip_if_not_installed("sf"); skip_if_not_installed("jsonlite"); skip_if_not_installed("arrow", "25.0.0")
}

test_that("attribute-only Parquet output of multi-radius Network Reach and Betweenness equals the in-memory result", {
  skip_nm_parquet()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE))
  g <- nm_graph()
  origins <- rbind(c(1, 1), c(5, 2), c(12, 8))
  cases <- list(
    list(fn = network_reach, args = list(radius = analysis_radius(walking = c(8, 3, 20))), id = "line_id", rows = 54L, name = "reach"),
    list(fn = network_reach, args = list(radius = analysis_radius(steps = c(1, 2)), origins = origins), id = "origin_id", rows = 3L,
         name = "reach-origins"),
    list(fn = nm_between, args = list(radius = analysis_radius(steps = c(2, 1)), distance = "walking",
                                               normalization = c("syntax", "none", "freeman", "standard"),
                                               weights = c(0, rep(1.5, 53))), id = "line_id", rows = 54L, name = "between"))
  for (case in cases) {
    frame <- do.call(case$fn, c(list(g), case$args))
    path <- file.path(dir, paste0(case$name, ".parquet"))
    res <- do.call(case$fn, c(list(g), case$args, list(output_file = path)))
    expect_s3_class(res, "pst_result_file")
    expect_identical(res$columns, names(frame))
    expect_identical(res$rows, case$rows)
    t <- rs_read_parquet(path, as_data_frame = FALSE)
    expect_identical(names(t), names(frame))
    d <- as.data.frame(t)
    expect_identical(d[[case$id]], frame[[case$id]])
    for (nm in setdiff(names(frame), case$id)) {
      expect_identical(is.na(d[[nm]]), is.na(frame[[nm]]), info = nm)
      expect_identical(as.numeric(d[[nm]]), as.numeric(frame[[nm]]), info = nm)
    }
    meta <- t$schema$metadata
    expect_identical(meta[["rpst:schema"]], "2")
    expect_identical(meta[["rpst:graph_type"]], "axial")
    expect_identical(meta[["rpst:graph_rows"]], "54")
    cols <- jsonlite::fromJSON(meta[["rpst:columns"]], simplifyVector = FALSE)
    expect_identical(vapply(cols, function(x) x$name, ""), setdiff(names(frame), case$id))
    # no clobbering, no leftovers, failure leaves nothing
    expect_error(do.call(case$fn, c(list(g), case$args, list(output_file = path))), "already exists")
    nm_fail_after(1)
    fresh <- file.path(dir, paste0("fresh-", case$name, ".parquet"))
    expect_error(do.call(case$fn, c(list(g), case$args, list(output_file = fresh))), "injected native failure")
    nm_fail_after(-1)
    expect_false(file.exists(fresh))
    expect_identical(so_leftovers(dir), character())
  }
})

# ---- review additions: weight_name in the manifest, one radius with several normalisations, GeoParquet ----------------------------

test_that("the schema-2 manifest keeps weight_name for weighted and attraction Network Betweenness, as the scalar manifest does", {
  nm_skip_fgb()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE))
  g <- nm_fgb_graph(dir)$g
  attractions <- rbind(c(105, 205), c(112, 207), c(120, 215))
  wts <- rep(c(0, 1, 2), 10)
  names_of <- function(path) vapply(jsonlite::fromJSON(nm_meta(path)[["rpst:columns"]], simplifyVector = FALSE), function(x) x$name, "")
  weight_of <- function(path) vapply(jsonlite::fromJSON(nm_meta(path)[["rpst:columns"]], simplifyVector = FALSE),
                                     function(x) if (is.null(x$weight_name)) NA_character_ else x$weight_name, "")
  for (case in list(list(weights = wts, attraction_points = NULL, name = "weights"),
                    list(weights = c(1, 0, 2), attraction_points = attractions, name = "weights"),
                    list(weights = NULL, attraction_points = NULL, name = NA_character_))) {
    multi <- file.path(dir, "m.fgb"); scalar <- file.path(dir, "s.fgb")
    nm_between(g, analysis_radius(steps = c(2, 3)), "steps", c("none", "freeman", "syntax"), case$weights, case$attraction_points,
               spatial_output_file = multi, overwrite = TRUE)
    nm_between(g, analysis_radius(steps = 2), "steps", "freeman", case$weights, case$attraction_points,
               spatial_output_file = scalar, overwrite = TRUE)
    expect_identical(nm_meta(multi)[["rpst:schema"]], "2")
    expect_identical(nm_meta(scalar)[["rpst:schema"]], "1")
    # every column of both manifests carries the weight name (or none), and the multi manifest repeats it for every radius
    expect_true(all(weight_of(scalar) == case$name) || (is.na(case$name) && all(is.na(weight_of(scalar)))))
    expect_true(all(weight_of(multi) == case$name) || (is.na(case$name) && all(is.na(weight_of(multi)))))
    expect_length(weight_of(multi), 2L * 5L)   # two radii x (raw, node count, total depth, freeman, syntax)
    # the scalar columns of radius 2 are the first four multi columns, with the same names and weight names
    expect_identical(names_of(multi)[1:4], names_of(scalar))
    expect_identical(weight_of(multi)[1:4], weight_of(scalar))
    # the parameters record it too
    expect_identical(jsonlite::fromJSON(nm_meta(multi)[["rpst:parameters"]], simplifyVector = FALSE)$weight_name,
                     jsonlite::fromJSON(nm_meta(scalar)[["rpst:parameters"]], simplifyVector = FALSE)$weight_name)
  }
  # an angular manifest (no weights) is unchanged: no weight_name entry
  src <- so_write_fgb(file.path(dir, "seg.fgb"), so_segments(30))
  out <- file.path(dir, "ang.fgb")
  angular_choice(segment_graph(src), analysis_radius(walking = c(25, 10)), spatial_output_file = out)
  expect_true(all(is.na(weight_of(out))))
})

test_that("a single radius with several Betweenness normalisations equals independent scalar calls", {
  g <- nm_graph()
  set.seed(5)
  wts <- c(0, runif(52, 0, 3), 0)
  attractions <- rbind(c(2, 1), c(6, 3), c(10, 7))
  aw <- c(1, 0, 3)
  cases <- list(
    list(radius = analysis_radius(walking = 12), distance = "walking"),
    list(radius = analysis_radius(steps = 3, straight = 40), distance = "steps"),
    list(radius = analysis_radius(angular = 100), distance = "angular"),
    list(radius = analysis_radius(axmeter = 20), distance = "axmeter", weights = wts),
    list(radius = analysis_radius(), distance = "steps", attraction_points = attractions, weights = aw),
    list(radius = analysis_radius(walking = 0), distance = "walking"))
  sets <- list(c("standard", "freeman"), c("syntax", "none", "standard"), c("freeman", "syntax", "standard", "none"),
               c("none", "syntax"))
  for (case in cases) for (norms in sets) {
    multi <- nm_between(g, case$radius, case$distance, norms, case$weights, case$attraction_points)
    man <- attr(multi, "rpst_manifest")
    expect_false(is.null(man), info = paste(norms, collapse = ","))     # several normalisations: schema 2 even with one radius
    expect_length(man$radii, 1L)
    extra <- setdiff(norms, "none")
    expect_identical(ncol(multi), 1L + 3L + length(extra))
    scalar_raw <- nm_between(g, case$radius, case$distance, "none", case$weights, case$attraction_points)
    expect_identical(multi[names(scalar_raw)], scalar_raw)                # raw, node count, total depth, once
    for (n in extra) {
      one <- nm_between(g, case$radius, case$distance, n, case$weights, case$attraction_points)
      nrm <- setdiff(names(one), names(scalar_raw))
      expect_length(nrm, 1L)
      expect_true(nrm %in% names(multi))
      expect_identical(multi[[nrm]], one[[nrm]], info = paste(n, collapse = ","))
    }
    # the order of the normalised columns is the requested order, after the three shared columns
    codes <- c(standard = "s", freeman = "f", syntax = "y")[extra]
    expect_identical(sub(".*_([sfy])$", "\\1", names(multi)[-(1:4)]), unname(codes))
  }
})

skip_nm_geoparquet <- function() {
  skip_if_not_installed("sf"); skip_if_not_installed("jsonlite"); skip_if_not_installed("arrow", "25.0.0")
}
nm_pq_meta <- function(path) rs_read_parquet(path, as_data_frame = FALSE)$schema$metadata
nm_same_values <- function(actual, expected, info = NULL) {
  expect_identical(is.na(actual), is.na(expected), info = info)
  expect_identical(is.nan(actual), is.nan(expected), info = info)
  expect_identical(as.numeric(actual), as.numeric(expected), info = info)
}

test_that("GeoParquet spatial output of multi-radius Network Reach and Betweenness: exact values, nulls, metadata, publication and failure", {
  skip_nm_geoparquet()
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE))
  m <- so_segments(30)
  attrs <- so_attributes(30)
  attrs$nb_s_rs2_wweights_n <- seq_len(30)                 # a source column that a result column replaces
  src <- so_write_gpq(file.path(dir, "net.parquet"), m, attrs, chunk = 7L)
  g <- axial_graph(src)
  original <- as.data.frame(rs_read_parquet(src, as_data_frame = FALSE))
  src_md <- nm_pq_meta(src)
  weights <- rep(c(0, 1, 2), 10)                           # zero weights: PST writes no diagnostics for those origins
  r <- analysis_radius(steps = c(2, 3), straight = 80)
  norms <- c("freeman", "none", "syntax", "standard")
  frame <- nm_between(g, r, "steps", norms, weights)
  expect_true(anyNA(frame[[grep("^nc_", names(frame))[[1L]]]]))   # the table really contains nulls
  out <- file.path(dir, "between.parquet")
  # a source column named like a result column needs overwrite = TRUE, and nothing is created without it
  expect_error(nm_between(g, r, "steps", norms, weights, spatial_output_file = out), "already exist in the source: nb_s_rs2_wweights_n")
  expect_false(file.exists(out))
  res <- nm_between(g, r, "steps", norms, weights, spatial_output_file = out, overwrite = TRUE)
  expect_s3_class(res, "pst_result_file")
  expect_true(res$spatial)
  expect_identical(res$replaced, "nb_s_rs2_wweights_n")
  result_names <- setdiff(names(frame), "line_id")
  expect_identical(res$appended, setdiff(result_names, "nb_s_rs2_wweights_n"))
  expect_identical(so_leftovers(dir), character())
  back <- so_read(out, "geoparquet")
  source_names <- setdiff(names(rs_read_parquet(src, as_data_frame = FALSE)), "geometry")
  expect_identical(back$names, c(source_names, setdiff(result_names, "nb_s_rs2_wweights_n")))
  for (nm in result_names) nm_same_values(as.numeric(back$attrs[[nm]]), frame[[nm]], info = nm)   # exact values and the same nulls
  expect_identical(back$wkb, unclass(original$geometry))                                            # geometry byte for byte
  for (nm in setdiff(names(so_attributes(30)), character())) expect_identical(back$attrs[[nm]], original[[nm]])
  out_md <- nm_pq_meta(out)
  expect_identical(out_md[["geo"]], src_md[["geo"]])
  expect_identical(out_md[["other_key"]], "kept")
  expect_identical(out_md[["rpst:schema"]], "2")
  expect_identical(out_md[["rpst:function"]], "network_betweenness")
  expect_identical(out_md[["rpst:graph_type"]], "axial")
  expect_identical(out_md[["rpst:graph_rows"]], "30")
  expect_identical(out_md[["rpst:radius_varying"]], "steps")
  expect_identical(jsonlite::fromJSON(out_md[["rpst:radius_fixed"]], simplifyVector = FALSE), list(straight = 80L))
  expect_identical(unlist(jsonlite::fromJSON(out_md[["rpst:normalizations"]], simplifyVector = FALSE)), norms)
  cols <- jsonlite::fromJSON(out_md[["rpst:columns"]], simplifyVector = FALSE)
  expect_identical(vapply(cols, function(x) x$name, ""), result_names)
  expect_true(all(vapply(cols, function(x) identical(x$weight_name, "weights"), NA)))
  expect_identical(rs_pq(out)$num_row_groups, rs_pq(src)$num_row_groups)
  # Network Reach, same route (source without a colliding column)
  src2 <- so_write_gpq(file.path(dir, "net2.parquet"), m, so_attributes(30), chunk = 11L)
  g2 <- axial_graph(src2)
  rr <- analysis_radius(walking = c(25, 10, 60))
  freach <- network_reach(g2, rr)
  out2 <- file.path(dir, "reach.parquet")
  network_reach(g2, rr, spatial_output_file = out2)
  back2 <- so_read(out2, "geoparquet")
  for (nm in setdiff(names(freach), "line_id")) nm_same_values(as.numeric(back2$attrs[[nm]]), freach[[nm]], info = nm)
  expect_identical(nm_pq_meta(out2)[["rpst:function"]], "network_reach")
  expect_identical(nm_pq_meta(out2)[["rpst:schema"]], "2")
  # publication and failure behaviour
  md5 <- so_md5(out)
  expect_error(nm_between(g, r, "steps", norms, weights, spatial_output_file = out), "already exists")
  expect_identical(so_md5(out), md5)
  nm_fail_after(1)                                           # the second radius fails after the first completed
  expect_error(nm_between(g, r, "steps", norms, weights, spatial_output_file = out, overwrite = TRUE), "injected native failure")
  nm_fail_after(-1)
  expect_identical(so_md5(out), md5)                         # the existing file is untouched
  fresh <- file.path(dir, "fresh.parquet")
  nm_fail_after(2)
  expect_error(network_reach(g2, rr, spatial_output_file = fresh), "injected native failure")
  nm_fail_after(-1)
  expect_false(file.exists(fresh))
  expect_identical(so_leftovers(dir), character())
  expect_s3_class(nm_between(g, r, "steps", "syntax", weights, spatial_output_file = out, overwrite = TRUE), "pst_result_file")
  expect_false(identical(so_md5(out), md5))                  # replaced atomically on request
  expect_identical(nrow(network_reach(g2, analysis_radius(steps = 2))), 30L)   # the graph is still usable
})
