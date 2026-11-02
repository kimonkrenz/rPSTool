# The output-column naming scheme (docs/output-naming.md). These tests call the real public functions (`rPSTool::`), not the
# legacy-name adapter that the numerical regression tests use.
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

test_that("custom weights require a name; names are normalised strictly", {
  a <- naming_axial(); r <- analysis_radius(walking = 800); w <- c(1, 2)
  p <- rbind(c(0.5, 0.5), c(1.5, 0.5))
  bet <- function(...) cols(rPSTool::network_betweenness(a, r, distance = "walking", attraction_points = p, weights = w, ...))
  # the exact required message, raised before any computation
  expect_error(bet(), "Custom weights require weight_name. Supply a descriptive identifier, for example weight_name = \"population\".",
               fixed = TRUE)
  expect_identical(bet(weight_name = "population")[1L], "at_w_rw800_wpopulation_n")
  expect_identical(bet(weight_name = "Population")[1L], "at_w_rw800_wpopulation_n")
  expect_identical(bet(weight_name = "Jobs 2021")[1L], "at_w_rw800_wjobs_2021_n")
  expect_identical(bet(weight_name = "jobs_2021")[1L], "at_w_rw800_wjobs_2021_n")
  expect_identical(bet(weight_name = "wjobs_2021")[1L], "at_w_rw800_wwjobs_2021_n")   # the prefix is always added
  # only a-z, 0-9 and '_' survive: anything else is an error, never silently altered or truncated
  for (bad in c("Jobs-2021", "Jobs/2021", "Population (%)", "caf\u00e9", "a.b", "", "!!", NA_character_))
    expect_error(bet(weight_name = bad), "weight_name", info = bad)
  expect_error(bet(weight_name = c("a", "b")), "one non-empty string")
  expect_error(bet(weight_name = 1), "one non-empty string")
  expect_error(bet(weight_name = "l"), "reserved")
  expect_error(rPSTool::network_betweenness(a, r, distance = "walking", weight_name = "x"), "supplied without weights")
  # the same rules and the same pre-computation timing for all four custom-weight APIs
  pts <- rbind(c(0.5, 0.5)); o <- rbind(c(0.2, 0))
  expect_error(rPSTool::attraction_reach(a, pts, r, distance = "walking", attraction_values = 1), "Custom weights require weight_name")
  expect_error(rPSTool::attraction_reach(a, pts, r, distance = "walking", attraction_values = 1, weight_name = "Cap-1"), "weight_name")
  expect_error(rPSTool::attraction_distance(a, pts, distance = "weights", line_weights = rep(1, 3)), "Custom weights require weight_name")
  expect_error(rPSTool::od_betweenness(a, o, r, origin_weights = 1), "Custom weights require origin_weight_name")
  expect_error(rPSTool::od_betweenness(a, o, r, destination_weights = rep(1, 2)), "Custom weights require destination_weight_name")
  # origin and destination names are validated independently
  expect_error(rPSTool::od_betweenness(a, o, r, origin_weights = 1, origin_weight_name = "pop",
                                       destination_weights = rep(1, 2), destination_weight_name = "jobs/2021"), "destination_weight_name")
  expect_error(rPSTool::od_betweenness(a, o, r, origin_weights = 1, origin_weight_name = "pop-1",
                                       destination_weights = rep(1, 2), destination_weight_name = "jobs"), "origin_weight_name")
  expect_error(rPSTool::od_betweenness(a, o, r, origin_weight_name = "pop"), "supplied without origin_weights")
  expect_identical(cols(rPSTool::od_betweenness(a, o, r, origin_weights = 1, origin_weight_name = "Pop 1",
                                                destination_weights = rep(1, 2), destination_weight_name = "jobs")),
                   "od_w_rw800_wopop_1_wdjobs")
  expect_identical(cols(rPSTool::od_betweenness(a, o, r, destination_weights = rep(1, 2), destination_weight_name = "jobs")), "od_w_rw800_wdjobs")
  expect_identical(cols(rPSTool::attraction_distance(a, pts, distance = "weights", line_weights = rep(1, 3), weight_name = "cost"))[1L],
                   "ad_d_rg_wcost")
  expect_identical(cols(rPSTool::attraction_reach(a, pts, r, distance = "walking", attraction_values = 1, weight_name = "capacity")),
                   "ar_w_rw800_wcapacity")
})

test_that("the original weight name is recorded in the metadata manifest, not truncated", {
  a <- naming_axial(); r <- analysis_radius(walking = 800)
  res <- rPSTool::network_betweenness(a, r, distance = "walking", weights = c(1, 2, 3), weight_name = "Jobs 2021")
  man <- attr(res, "rpst_manifest")$columns
  expect_true(all(man$weight_name %in% "Jobs 2021"))
  expect_true(all(grepl("_wjobs_2021", man$name[man$weight_name %in% "Jobs 2021"])))
})

test_that("unweighted analyses carry no weight component; weighted diagnostics are tagged", {
  a <- naming_axial(); r <- analysis_radius(walking = 800)
  expect_identical(cols(rPSTool::network_betweenness(a, r, distance = "walking")), c("nb_w_rw800_n", "nc_w_rw800", "td_w_rw800"))
  expect_identical(cols(rPSTool::network_betweenness(a, r, distance = "walking", weights = c(1, 2, 3), weight_name = "pop")),
                   c("nb_w_rw800_wpop_n", "nc_w_rw800_wpop", "td_w_rw800_wpop"))
  expect_identical(cols(rPSTool::network_betweenness(a, r, distance = "walking", attraction_points = rbind(c(0.5, 0.5)))),
                   c("at_w_rw800_n", "anc_w_rw800", "atd_w_rw800"))
})

test_that("weights do not change the numerical results, only the names", {
  a <- naming_axial(); r <- analysis_radius(walking = 800); p <- rbind(c(0.5, 0.5), c(1.5, 0.5))
  x <- rPSTool::network_betweenness(a, r, distance = "walking", attraction_points = p, weights = c(1, 2), weight_name = "w")
  y <- rPSTool::network_betweenness(a, r, distance = "walking", attraction_points = p, weights = c(1, 2), weight_name = "other")
  expect_identical(unname(as.list(x)), unname(as.list(y)))
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
