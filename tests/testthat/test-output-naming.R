# The output-column naming scheme (docs/output-naming.md), asserted through the real public functions (`rPSTool::`).
naming_segments <- function() rPSTool::segment_graph(cbind(0:4 * 3, 0, 1:5 * 3, 0))
naming_axial <- function() rPSTool::axial_graph(rbind(c(0, 0, 2, 0), c(1, -1, 1, 1), c(2, -1, 2, 1)),
                                                 points = rbind(c(0.5, 0.5), c(1.5, 0.5)))
cols <- function(x) setdiff(names(x), c("segment_id", "line_id", "origin_id", "group_id", "junction_id"))

test_that("radius components use full values in the canonical order", {
  nm <- rPSTool:::.pst_nm_radius
  expect_identical(nm(NULL), "rg")
  expect_identical(nm(analysis_radius()), "rg")
  expect_identical(nm(analysis_radius(walking = 3000)), "rw3000")
  expect_identical(nm(analysis_radius(walking = 0.5)), "rw0p5")
  expect_identical(nm(analysis_radius(walking = 1e4)), "rw10000")        # never abbreviated
  expect_identical(nm(3L), "rs3")
  expect_identical(nm(analysis_radius(axmeter = 1000, angular = 180, steps = 3, walking = 400, straight = 500)),
                   "rl500_rw400_rs3_ra180_ram1000")
  expect_identical(nm(analysis_radius(angular = 180, walking = 3000, steps = 3)), nm(analysis_radius(steps = 3, walking = 3000, angular = 180)))
  expect_identical(nm(analysis_radius(walking = 0)), "rw0")
})

test_that("Angular Integration and Angular Choice follow the documented examples", {
  g <- naming_segments(); r <- analysis_radius(walking = 3000)
  expect_identical(cols(rPSTool::angular_integration(g, radius = r)), c("ai_a_rw3000_t", "nc_a_rw3000", "td_a_rw3000"))
  expect_identical(cols(rPSTool::angular_integration(g, radius = r, normalization = "syntax")), c("ai_a_rw3000_a", "nc_a_rw3000", "td_a_rw3000"))
  expect_identical(cols(rPSTool::angular_integration(g, steps = 3))[1L], "ai_a_rs3_t")
  expect_identical(cols(rPSTool::angular_integration(g, radius = r, normalization = "hillier"))[1L], "ai_a_rw3000_h")
  expect_identical(cols(rPSTool::angular_integration(g, radius = r, weigh_by_length = TRUE, normalization = "syntax")),
                   c("ai_a_rw3000_wl_a", "nc_a_rw3000", "td_a_rw3000", "tw_a_rw3000_wl", "tdw_a_rw3000_wl"))
  # unweighted diagnostics are named by analysis, distance and radius alone: no placeholder weight code
  expect_identical(cols(rPSTool::angular_integration(g, radius = r, weight_outputs = TRUE))[4:5], c("tw_a_rw3000", "tdw_a_rw3000"))
  expect_identical(cols(rPSTool::angular_choice(g, radius = r)), c("ac_a_rw3000_n", "nc_a_rw3000", "td_a_rw3000"))
  expect_identical(cols(rPSTool::angular_choice(g, radius = r, normalization = "syntax"))[4L], "ac_a_rw3000_c")
  expect_identical(cols(rPSTool::angular_choice(g, radius = r, normalization = c("turner", "standard", "syntax")))[4:6],
                   c("ac_a_rw3000_t", "ac_a_rw3000_s", "ac_a_rw3000_c"))
  expect_identical(cols(rPSTool::angular_choice(g, radius = r, weigh_by_length = TRUE)),
                   c("ac_a_rw3000_wl_n", "nc_a_rw3000", "td_a_rw3000", "tdw_a_rw3000_wl"))
})

test_that("non-default angular parameters are suffixes; defaults, even when explicit, are omitted", {
  g <- naming_segments(); r <- analysis_radius(walking = 3000)
  one <- function(...) cols(rPSTool::angular_choice(g, radius = r, normalization = "syntax", ...))[4L]
  expect_identical(one(), "ac_a_rw3000_c")
  expect_identical(one(angle_threshold = 0, angle_precision = 1), "ac_a_rw3000_c")
  expect_identical(one(angle_threshold = 12), "ac_a_rw3000_c_at12")
  expect_identical(one(angle_precision = 3), "ac_a_rw3000_c_ap3")
  expect_identical(one(angle_precision = 3, angle_threshold = 12), "ac_a_rw3000_c_at12_ap3")
  expect_identical(one(angle_threshold = 12.5), "ac_a_rw3000_c_at12p5")
  expect_identical(cols(rPSTool::angular_choice(g, radius = r, angle_threshold = 12))[2:3], c("nc_a_rw3000_at12", "td_a_rw3000_at12"))
})

test_that("scalar and multi-radius calls name the same calculation identically", {
  g <- naming_segments()
  for (norm in c("none", "turner", "syntax")) {
    multi <- rPSTool::angular_choice(g, analysis_radius(walking = c(3, 8)), normalization = norm, weigh_by_length = TRUE)
    for (v in c(3, 8)) {
      one <- rPSTool::angular_choice(g, analysis_radius(walking = v), normalization = norm, weigh_by_length = TRUE)
      expect_true(all(cols(one) %in% names(multi)))
      for (nm in cols(one)) expect_identical(multi[[nm]], one[[nm]])
    }
  }
  multi <- rPSTool::angular_integration(g, radius = analysis_radius(steps = c(1, 2)), normalization = c("turner", "syntax", "hillier"))
  one <- rPSTool::angular_integration(g, steps = 2, normalization = "hillier")
  expect_identical(multi[["ai_a_rs2_h"]], one[["ai_a_rs2_h"]])
  expect_identical(anyDuplicated(names(multi)), 0L)
  expect_identical(names(rPSTool::angular_choice(g, analysis_radius(walking = c(8, 3))))[2L], "ac_a_rw8_n")   # requested order kept
})

test_that("axial analyses are named as documented", {
  a <- naming_axial()
  expect_identical(cols(rPSTool::network_integration(a, steps = 2)), c("ni_s_rs2", "nc_s_rs2", "td_s_rs2"))
  expect_identical(cols(rPSTool::network_integration(a)), c("ni_s_rg", "nc_s_rg", "td_s_rg"))
  expect_identical(names(rPSTool::network_integration(a, steps = 2, junctions = TRUE)$junctions)[4L], "nj_s_rs2")
  expect_identical(cols(rPSTool::network_reach(a, analysis_radius(straight = 500, walking = 400))), c("rc_rl500_rw400", "rln_rl500_rw400", "rca_rl500_rw400"))
  expect_identical(names(rPSTool::network_reach(a, origins = rbind(c(0.5, 0)), radius = analysis_radius(walking = 5)))[1L], "origin_id")
  r <- analysis_radius(walking = 800)
  expect_identical(cols(rPSTool::network_betweenness(a, r, distance = "walking", normalization = "freeman")),
                   c("nb_w_rw800_n", "nc_w_rw800", "td_w_rw800", "nb_w_rw800_f"))
  expect_identical(cols(rPSTool::network_betweenness(a, r, distance = "walking", normalization = "syntax"))[4L], "nb_w_rw800_y")
  expect_identical(cols(rPSTool::network_betweenness(a, r, distance = "steps", normalization = "standard"))[4L], "nb_s_rw800_s")
  expect_identical(cols(rPSTool::network_betweenness(a, r, attraction_points = rbind(c(0.5, 0.5)), distance = "walking"))[1L], "at_w_rw800_n")
  pts <- rbind(c(0.5, 0.5))
  expect_identical(cols(rPSTool::attraction_reach(a, pts, r, distance = "walking")), "ar_w_rw800")
  expect_identical(cols(rPSTool::attraction_reach(a, pts, distance = "none")), "ar_rg")
  expect_identical(cols(rPSTool::attraction_distance(a, pts, r, distance = "walking")), c("ad_w_rw800", "di_w_rw800"))
  expect_identical(cols(rPSTool::attraction_distance(a, pts, r, distance = "walking", destination_indices = FALSE)), "ad_w_rw800")
  expect_identical(cols(rPSTool::od_betweenness(a, rbind(c(0.2, 0)), r)), "od_w_rw800")
  s <- naming_segments(); gg <- rPSTool::segment_group_graph(s, seq_len(s$n_segments))
  expect_identical(cols(rPSTool::segment_group_integration(gg, analysis_radius(steps = 1))), c("gi_rs1", "nc_rs1", "td_rs1"))
})

test_that("attraction and OD parameters appear only when they differ from the defaults", {
  a <- naming_axial(); pts <- rbind(c(0.5, 0.5)); r <- analysis_radius(walking = 800)
  nm <- function(...) cols(rPSTool::attraction_reach(a, pts, r, distance = "walking", ...))
  expect_identical(nm(decay = "constant", decay_constant = 0, distribution = "divide", collection = "mean"), "ar_w_rw800")
  expect_identical(nm(decay = "power"), "ar_w_rw800_dcp")                       # decay_constant NULL = the default 1
  expect_identical(nm(decay = "power", decay_constant = 1), "ar_w_rw800_dcp")
  expect_identical(nm(decay = "power", decay_constant = 2), "ar_w_rw800_dcp_dk2")
  expect_identical(nm(decay_constant = 1.5), "ar_w_rw800_dk1p5")
  expect_identical(nm(collection = "sum", distribution = "copy"), "ar_w_rw800_dsc_cls")
  expect_identical(cols(rPSTool::attraction_distance(a, pts, r, distance = "walking", point_edge_weight = 2))[1L], "ad_w_rw800_pe2")
  expect_identical(cols(rPSTool::od_betweenness(a, rbind(c(0.2, 0)), r, destination_mode = "closest")), "od_w_rw800_dmc")
  expect_identical(cols(rPSTool::attraction_reach(a, pts, r, origin = "points", distance = "walking")), "ar_w_rw800_orp")
})

# Weight names are inferred from the expression passed to the weight argument, so these tests build real calls.
nm_call <- function(expr, ..., env = parent.frame()) {
  a <- naming_axial(); r <- analysis_radius(walking = 800); p <- rbind(c(0.5, 0.5), c(1.5, 0.5))
  e <- new.env(parent = env); e$a <- a; e$r <- r; e$p <- p
  for (n in names(list(...))) assign(n, list(...)[[n]], envir = e)
  eval(expr, e)
}
bet_name <- function(weights_expr, ..., env = parent.frame()) {
  call <- substitute(rPSTool::network_betweenness(a, r, distance = "walking", attraction_points = p, weights = W), list(W = weights_expr))
  cols(nm_call(call, ..., env = env))[1L]
}

test_that("weights are named after the R object or data-frame column passed", {
  population <- c(1, 2)
  expect_identical(bet_name(quote(population)), "at_w_rw800_wpopulation_n")
  d <- data.frame(population = c(1, 2), jobs = c(3, 4))
  expect_identical(bet_name(quote(d$population), d = d), "at_w_rw800_wpopulation_n")
  expect_identical(bet_name(quote(d[["jobs"]]), d = d), "at_w_rw800_wjobs_n")
  expect_identical(bet_name(quote(d$"jobs"), d = d), "at_w_rw800_wjobs_n")
  # a name assigned first is the only way to use a calculated or anonymous vector
  population_thousands <- d$population / 1000
  expect_identical(bet_name(quote(population_thousands)), "at_w_rw800_wpopulation_thousands_n")
  # weights given positionally are named too
  a <- naming_axial(); r <- analysis_radius(walking = 800); p <- rbind(c(0.5, 0.5), c(1.5, 0.5)); jobs <- c(1, 2)
  expect_identical(cols(rPSTool::network_betweenness(a, r, "walking", "none", jobs, p))[1L], "at_w_rw800_wjobs_n")
})

test_that("anonymous vectors and calculated expressions are rejected before any computation", {
  a <- naming_axial(); r <- analysis_radius(walking = 800); d <- data.frame(population = c(1, 2, 3))
  msg <- "Cannot infer a weight name from this expression. Assign the weights to a named R object or use a data-frame column."
  expect_error(rPSTool::network_betweenness(a, r, weights = c(1, 2, 3)), msg, fixed = TRUE)
  expect_error(rPSTool::network_betweenness(a, r, weights = d$population / 1000), msg, fixed = TRUE)
  expect_error(rPSTool::network_betweenness(a, r, weights = rep(1, 3)), msg, fixed = TRUE)
  expect_error(rPSTool::network_betweenness(a, r, weights = 1:3), msg, fixed = TRUE)
  expect_error(rPSTool::network_betweenness(a, r, weights = d[["population"]] * 2), msg, fixed = TRUE)
  col <- "population"
  expect_error(rPSTool::network_betweenness(a, r, weights = d[[col]]), msg, fixed = TRUE)    # a computed key is not a literal column
  expect_error(rPSTool::network_betweenness(a, r, weights = d[, "population"]), msg, fixed = TRUE)
  w <- c(1, 2, 3)
  expect_error(do.call(rPSTool::network_betweenness, list(a, r, weights = w)), msg, fixed = TRUE)   # values, not expressions
  expect_error((function(...) rPSTool::network_betweenness(a, r, ...))(weights = c(1, 2, 3)), msg, fixed = TRUE)
  expect_error(rPSTool::network_betweenness(a, r, weights = w, normalization = "bogus"), "normalization")   # other errors are unchanged
})

test_that("a wrapper function names the weights after its own variable; this is documented behaviour", {
  a <- naming_axial(); r <- analysis_radius(walking = 800); pts <- rbind(c(0.5, 0.5), c(1.5, 0.5))
  wrapper <- function(w) cols(rPSTool::network_betweenness(a, r, distance = "walking", attraction_points = pts, weights = w))[1L]
  population <- c(1, 2)
  expect_identical(wrapper(population), "at_w_rw800_ww_n")          # the wrapper's formal, not the caller's object
  forward <- function(...) cols(rPSTool::network_betweenness(a, r, distance = "walking", attraction_points = pts, ...))[1L]
  expect_identical(forward(weights = population), "at_w_rw800_wpopulation_n")   # `...` keeps the caller's expression
})

test_that("weight names are normalised automatically", {
  for (n in c("Jobs 2021", "Jobs-2021", "Jobs/2021", "Jobs  2021", "JOBS 2021", " jobs_2021 ", "Jobs (2021)", "jobs_2021"))
    expect_identical(bet_name(as.name(n), env = list2env(stats::setNames(list(c(1, 2)), n))), "at_w_rw800_wjobs_2021_n", info = n)
  expect_identical(bet_name(quote(Population), Population = c(1, 2)), "at_w_rw800_wpopulation_n")
  expect_identical(bet_name(as.name("Population (%)"), `Population (%)` = c(1, 2)), "at_w_rw800_wpopulation_n")
  expect_identical(bet_name(quote(wjobs_2021), wjobs_2021 = c(1, 2)), "at_w_rw800_wwjobs_2021_n")   # the prefix is always added
  # Non-ASCII letters are not in [a-z0-9_]. enc2native() gives the string as this session represents it (the
  # accented letter in a UTF-8 session, R's "<U+00E9>" escape in a non-UTF-8 one), which is what a user's symbol
  # would be; it avoids R's own as.name()/environment warning about an unrepresentable character.
  accented <- enc2native(paste0("caf", intToUtf8(233L), " x"))
  expect_identical(bet_name(as.name(accented), env = list2env(stats::setNames(list(c(1, 2)), accented))), "at_w_rw800_wcaf_x_n")
  expect_identical(bet_name(quote(a.b.c), a.b.c = c(1, 2)), "at_w_rw800_wa_b_c_n")
  # only a name with no letter or digit left is an error, and `l` would read as length weighting
  for (n in c("!!", "---", "(%)", "_"))
    expect_error(bet_name(as.name(n), env = list2env(stats::setNames(list(c(1, 2)), n))), "no letter or digit", info = n)
  expect_error(bet_name(quote(l), l = c(1, 2)), "reserved")
  expect_error(bet_name(as.name(" L! "), ` L! ` = c(1, 2)), "reserved")
})

test_that("all four custom-weight APIs infer names, and origin and destination are independent", {
  a <- naming_axial(); r <- analysis_radius(walking = 800); pts <- rbind(c(0.5, 0.5)); o <- rbind(c(0.2, 0))
  capacity <- 1; travel_cost <- rep(1, 3); population <- 1; jobs <- rep(1, 2)
  expect_identical(cols(rPSTool::attraction_reach(a, pts, r, distance = "walking", attraction_values = capacity)), "ar_w_rw800_wcapacity")
  expect_identical(cols(rPSTool::attraction_distance(a, pts, distance = "weights", line_weights = travel_cost))[1L], "ad_d_rg_wtravel_cost")
  expect_identical(cols(rPSTool::od_betweenness(a, o, r, origin_weights = population, destination_weights = jobs)), "od_w_rw800_wopopulation_wdjobs")
  expect_identical(cols(rPSTool::od_betweenness(a, o, r, origin_weights = population)), "od_w_rw800_wopopulation")
  expect_identical(cols(rPSTool::od_betweenness(a, o, r, destination_weights = jobs)), "od_w_rw800_wdjobs")
  # one anonymous vector is enough to fail, and the message is the same
  msg <- "Cannot infer a weight name"
  expect_error(rPSTool::od_betweenness(a, o, r, origin_weights = population, destination_weights = rep(1, 2)), msg)
  expect_error(rPSTool::od_betweenness(a, o, r, origin_weights = 1, destination_weights = jobs), msg)
  expect_error(rPSTool::attraction_reach(a, pts, r, distance = "walking", attraction_values = 1), msg)
  expect_error(rPSTool::attraction_distance(a, pts, distance = "weights", line_weights = rep(1, 3)), msg)
  # a name that normalises to nothing is rejected for its own argument only
  `!!` <- 1
  expect_error(rPSTool::od_betweenness(a, o, r, origin_weights = `!!`, destination_weights = jobs), "origin_weights")
  expect_error(rPSTool::od_betweenness(a, o, r, origin_weights = population, destination_weights = `!!`), "destination_weights")
  # there are no naming arguments: weight names are inferred from the call
  expect_error(rPSTool::network_betweenness(a, r, weights = population, weight_name = "x"), "unused argument")
  expect_error(rPSTool::od_betweenness(a, o, r, origin_weights = population, origin_weight_name = "x"), "unused argument")
})

test_that("the original inferred name is recorded in the metadata manifest, not truncated", {
  cols_ <- rPSTool:::.pst_nm_network_betweenness(analysis_radius(walking = 800), "walking", "none",
                                                 list(code = "wjobs_2021", name = "Jobs 2021"), FALSE)
  expect_true(all(vapply(cols_, function(x) identical(x$weight_name, "Jobs 2021"), NA)))
  expect_true(all(grepl("_wjobs_2021", vapply(cols_, function(x) x$name, ""))))
  json <- rPSTool:::.pst_json(rPSTool:::.pst_nm_manifest(cols_))
  expect_match(json, "Jobs 2021", fixed = TRUE)
  g <- naming_axial(); population <- c(1, 2, 3)
  res <- rPSTool::network_betweenness(g, analysis_radius(walking = 800), distance = "walking", weights = population)
  expect_identical(cols(res), c("nb_w_rw800_wpopulation_n", "nc_w_rw800_wpopulation", "td_w_rw800_wpopulation"))
})

test_that("unweighted analyses carry no weight component; weighted diagnostics are tagged", {
  a <- naming_axial(); r <- analysis_radius(walking = 800); pop <- c(1, 2, 3)
  expect_identical(cols(rPSTool::network_betweenness(a, r, distance = "walking")), c("nb_w_rw800_n", "nc_w_rw800", "td_w_rw800"))
  expect_identical(cols(rPSTool::network_betweenness(a, r, distance = "walking", weights = pop)),
                   c("nb_w_rw800_wpop_n", "nc_w_rw800_wpop", "td_w_rw800_wpop"))
  expect_identical(cols(rPSTool::network_betweenness(a, r, distance = "walking", attraction_points = rbind(c(0.5, 0.5)))),
                   c("at_w_rw800_n", "anc_w_rw800", "atd_w_rw800"))
  expect_identical(cols(rPSTool::network_betweenness(a, r, distance = "walking", weights = NULL)), c("nb_w_rw800_n", "nc_w_rw800", "td_w_rw800"))
})

test_that("weights do not change the numerical results, only the names", {
  a <- naming_axial(); r <- analysis_radius(walking = 800); p <- rbind(c(0.5, 0.5), c(1.5, 0.5))
  w <- c(1, 2); other <- c(1, 2)
  x <- rPSTool::network_betweenness(a, r, distance = "walking", attraction_points = p, weights = w)
  y <- rPSTool::network_betweenness(a, r, distance = "walking", attraction_points = p, weights = other)
  expect_identical(unname(as.list(x)), unname(as.list(y)))
  expect_false(identical(names(x), names(y)))
})

test_that("positional identifiers keep their names and result names are unique", {
  g <- naming_segments()
  res <- rPSTool::angular_integration(g, radius = analysis_radius(walking = c(1, 5, 9)), normalization = c("turner", "syntax", "hillier"),
                                      weigh_by_length = TRUE, weight_outputs = TRUE)
  expect_identical(names(res)[1L], "segment_id")
  expect_identical(anyDuplicated(tolower(names(res))), 0L)
  man <- attr(res, "rpst_manifest")$columns
  expect_identical(man$name, setdiff(names(res), "segment_id"))
})

test_that("the file route and the data frame use the same names, and the metadata manifest describes them", {
  skip_if_not_installed("sf"); skip_if_not_installed("jsonlite")
  dir <- tempfile("rpst-nm-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE))
  m <- cbind(0:19 * 3, 0, 1:20 * 3, 0)
  src <- file.path(dir, "net.fgb")
  sf::st_write(so_sf(m, data.frame(id = 1:20), epsg = 32630L), src, driver = "FlatGeobuf", quiet = TRUE,
               layer_options = "SPATIAL_INDEX=NO")
  g <- rPSTool::segment_graph(src)
  r <- analysis_radius(walking = 30)
  memory <- rPSTool::angular_choice(g, r, normalization = "syntax", angle_threshold = 5)
  out <- file.path(dir, "out.fgb")
  res <- rPSTool::angular_choice(g, r, normalization = "syntax", angle_threshold = 5, spatial_output_file = out)
  expect_identical(res$appended, cols(memory))
  back <- sf::st_read(out, quiet = TRUE)
  expect_identical(setdiff(names(back), c("id", "geometry")), cols(memory))
  for (nm in cols(memory)) expect_equal(as.numeric(back[[nm]]), as.numeric(memory[[nm]]), tolerance = 0)
  md <- jsonlite::fromJSON(rawToChar(.Call(rPSTool:::C_rpst_fgb_columns, enc2native(out))$metadata), simplifyVector = FALSE)
  manifest <- jsonlite::fromJSON(md[["rpst:columns"]], simplifyVector = FALSE)
  expect_identical(vapply(manifest, function(x) x$name, ""), cols(memory))
  expect_identical(manifest[[4L]]$normalization, "syntax")
  expect_identical(manifest[[4L]]$parameters, "at5")
})

test_that("every result column's manifest entry serialises, including OD Betweenness with both weights", {
  a <- naming_axial(); o <- rbind(c(0.2, 0)); r <- analysis_radius(walking = 800)
  cols <- rPSTool:::.pst_nm_od_betweenness(r, "walking", "all", list(code = "wopop_1", name = "Pop 1"), list(code = "wdjobs", name = "jobs"))
  json <- rPSTool:::.pst_json(rPSTool:::.pst_nm_manifest(cols))
  expect_match(json, "origin: Pop 1; destination: jobs", fixed = TRUE)
  parsed <- jsonlite::fromJSON(json, simplifyVector = FALSE)
  expect_identical(parsed[[1L]]$name, "od_w_rw800_wopop_1_wdjobs")
  for (w in list(list(NULL, NULL), list("a", NULL), list(NULL, "b")))
    expect_no_error(rPSTool:::.pst_json(rPSTool:::.pst_nm_manifest(rPSTool:::.pst_nm_od_betweenness(r, "walking", "closest",
      list(code = if (!is.null(w[[1]])) "woa" else "", name = w[[1]]), list(code = if (!is.null(w[[2]])) "wdb" else "", name = w[[2]])))))
})
