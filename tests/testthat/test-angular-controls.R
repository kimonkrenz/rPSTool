angular_controls_native <- function(name, ...) .Call(get(paste0("C_rpst_",name),asNamespace("rPSTool")),...)
angular_controls_compare <- function(actual, expected) {
  expected <- as.double(unlist(expected))
  expect_identical(is.nan(actual),is.nan(expected))
  expect_identical(is.infinite(actual),is.infinite(expected))
  expect_identical(actual[!is.finite(expected)],expected[!is.finite(expected)])
  expect_equal(actual[is.finite(expected)],expected[is.finite(expected)],tolerance=3e-6)
}
test_that("angular controls and native normalizers match direct PST (a stratified selection of cases in CRAN mode)", {
  ref <- dget(test_path("fixtures","angular-controls-direct-v3.3.2.R"))
  expect_identical(ref$pst_commit,unname(rPSTool:::.pst_engine_pin()[["pst_commit"]]))
  old <- Sys.getenv("RPST_NUM_THREADS",unset=NA_character_)
  on.exit(if (is.na(old)) Sys.unsetenv("RPST_NUM_THREADS") else Sys.setenv(RPST_NUM_THREADS=old))
  graphs <- list()
  on.exit(for (g in graphs) angular_controls_native("segment_graph_release",g$ptr),add=TRUE)
  for (cap in c("1","2")) {
    Sys.setenv(RPST_NUM_THREADS=cap)
    cases <- if (cap=="1") ref$cases else Filter(function(x) length(x$radius)==0L,ref$cases)
    # CRAN mode: every graph x routine x weighting, every routine x weighting x radius class, every angle threshold, every
    # precision and every routine x weighting x threshold x precision combination is visited; the second pass (two worker
    # threads, radius-free cases) only needs every graph x routine. Full mode runs every case in both passes.
    cases <- if (cap == "1")
      rpst_cases(cases, every = 48L, by = list(function(x) paste(x$graph$name, x$routine, x$weighted),
                                               function(x) paste(x$routine, x$weighted, rpst_radius_class(x)),
                                               function(x) x$threshold, function(x) x$precision,
                                               function(x) paste(x$routine, x$weighted, x$threshold, x$precision)))
    else
      rpst_cases(cases, every = 64L, by = list(function(x) paste(x$graph$name, x$routine)))
    for (case in cases) {
      name <- case$graph$name
      if (is.null(graphs[[name]])) graphs[[name]] <- segment_graph(matrix(unlist(case$graph$x),ncol=4,byrow=TRUE))
      g <- graphs[[name]];g$n_segments <- 999L
      args <- list(graph=g,radius=do.call(analysis_radius,case$radius),weigh_by_length=case$weighted,
                   angle_threshold=case$threshold,angle_precision=case$precision)
      for (norm in names(case$normalized)) {
        args$normalization <- norm
        if (case$routine=="integration") {
          args$weight_outputs <- TRUE
          out <- do.call(angular_integration,args)
          expect_length(names(out),6L)   # segment_id, ai, nc, td, tw, tdw: each selected below by its real name
          angular_controls_compare(pick(out, "^ai_"),case$normalized[[norm]])
          angular_controls_compare(pick(out, "^tw_"),case$weights)
          angular_controls_compare(pick(out, "^tdw_"),case$depth_weights)
        } else {
          out <- do.call(angular_choice,args)
          angular_controls_compare(pick(out, re_ac_raw),case$scores)
          angular_controls_compare(pick(out, re_ac_norm),case$normalized[[norm]])
          if (case$weighted) angular_controls_compare(pick(out, "^tdw_"),case$depth_weights)
        }
        expect_identical(out$segment_id,seq_along(case$counts))
        expect_identical(pick(out, "^nc_"),as.integer(unlist(case$counts)))
        angular_controls_compare(pick(out, "^td_"),case$depths)
      }
    }
  }
})
test_that("angular defaults and exclusion of origin weight remain explicit", {
  g <- segment_graph(rbind(c(0,0,1,0),c(1,0,4,0),c(4,0,9,0)))
  old <- angular_controls_native("angular_integration",g$ptr,NULL)
  default <- angular_integration(g)
  expect_identical(unname(as.list(default[-1])),old)
  expect_identical(angular_integration(g,NULL,NULL,FALSE,"turner",0,1,FALSE),default)
  expect_identical(names(default),c("segment_id","ai_a_rg_t","nc_a_rg","td_a_rg"))
  weighted <- angular_integration(g,weigh_by_length=TRUE)
  expect_identical(pick(weighted, "^tw_"),c(8,6,4))
  expect_identical(pick(weighted, "^ai_"),c(8,6,4))
  expect_identical(pick(angular_integration(g,weight_outputs=TRUE), "^tw_"),rep(2,3))
  expect_identical(pick(angular_integration(g,steps=0,weigh_by_length=TRUE), "^tw_"),rep(0,3))
  square <- segment_graph(rbind(c(0,0,3,0),c(3,0,3,3),c(3,3,0,3),c(0,3,0,0)))
  expect_identical(pick(angular_integration(square,angle_threshold=90), "^td_"),rep(4,4))
  expect_identical(pick(angular_integration(square,angle_threshold=90.1), "^td_"),rep(0,4))
  expect_identical(pick(angular_integration(square,angle_precision=7), "^td_"),rep(4,4))
  angular_controls_native("segment_graph_release",g$ptr)
  angular_controls_native("segment_graph_release",square$ptr)
})
test_that("angular settings reject malformed native inputs and preserve lifetime", {
  g <- segment_graph(rbind(c(0,0,3,0),c(3,0,4,2)))
  calls <- list(
    function(t=0,p=1,w=FALSE,n="turner",o=FALSE) angular_controls_native("angular_integration_controls",g$ptr,NULL,w,n,t,p,o),
    function(t=0,p=1,w=FALSE,n="none",o=FALSE) angular_controls_native("angular_choice_controls",g$ptr,analysis_radius(),w,n,t,p))
  for (call in calls) {
    for (t in list(NULL,TRUE,"1",c(0,1),NA_real_,NA_integer_,NaN,Inf,1e40,1e-300)) expect_error(call(t=t),"angle_threshold")
    for (p in list(NULL,TRUE,"1",c(1,2),NA_real_,NA_integer_,NaN,Inf,0,-1,1.1,4294967296)) expect_error(call(p=p),"angle_precision")
    for (w in list(NA,1,NULL,c(TRUE,FALSE))) expect_error(call(w=w),"weigh_by_length")
    expect_error(call(n="invalid"),"normalization")
  }
  for (o in list(NA,1,NULL,c(TRUE,FALSE))) expect_error(calls[[1]](o=o),"weight_outputs")
  expect_error(angular_integration(g,steps=1,radius=analysis_radius()),"either")
  expect_error(angular_integration(g,radius=analysis_radius(axmeter=1)),"axmeter")
  graph_copy <- unserialize(serialize(g,NULL))
  expect_error(angular_integration(graph_copy,weigh_by_length=TRUE),"no longer live")
  expect_error(angular_choice(graph_copy,angle_precision=3),"no longer live")
  out <- angular_integration(g,weigh_by_length=TRUE,normalization="syntax",angle_precision=3)
  saved <- out
  expect_identical(angular_integration(g,weigh_by_length=TRUE,normalization="syntax",angle_precision=3),saved)
  angular_controls_native("segment_graph_release",g$ptr)
  angular_controls_native("segment_graph_release",g$ptr)
  expect_error(angular_integration(g),"no longer live")
  expect_error(angular_choice(g,angle_threshold=20),"no longer live")
  rm(g);gc();expect_identical(out,saved)
  axial <- axial_graph(rbind(c(0,0,1,0)))
  seg <- segment_graph(rbind(c(0,0,1,0)))
  group <- segment_group_graph(seg,1L)
  for (ptr in list(axial$ptr,group$ptr)) {
    expect_error(angular_controls_native("angular_integration_controls",ptr,NULL,FALSE,"turner",0,1,FALSE),"Invalid pst_segment_graph")
    expect_error(angular_controls_native("angular_choice_controls",ptr,analysis_radius(),FALSE,"none",0,1),"Invalid pst_segment_graph")
  }
  angular_controls_native("graph_release",axial$ptr)
  angular_controls_native("segment_group_graph_release",group$ptr)
  angular_controls_native("segment_graph_release",seg$ptr)
})

test_that("syntax-normalised Choice uses total_depth_weight when length-weighted and total_depth otherwise (QGIS-equivalent)", {
  # The pinned PST for QGIS plugin passes total_depth_weight (weighted branch, angularchoiceanalysis.py l.128) or total_depth
  # (unweighted branch, l.177) to PSTAAngularChoiceSyntaxNormalize(scores, TD, ...), which computes log10(score + 1) / log10(2 + TD).
  # The direct-PST fixtures (angular-controls and multi-radius) already pin every case; this is a small independent secondary check.
  g <- segment_graph(rbind(c(0, 0, 1, 0), c(1, 0, 4, 0), c(4, 0, 9, 3), c(9, 3, 9, 8), c(4, 0, 4, -5)))
  for (radius in list(analysis_radius(), analysis_radius(walking = 7), analysis_radius(angular = 90))) {
    weighted <- angular_choice(g, radius = radius, weigh_by_length = TRUE, normalization = "syntax")
    unweighted <- angular_choice(g, radius = radius, weigh_by_length = FALSE, normalization = "syntax")
    expect_equal(pick(weighted, re_ac_norm), log10(pick(weighted, re_ac_raw) + 1) / log10(2 + pick(weighted, "^tdw_")), tolerance = 1e-6)
    expect_equal(pick(unweighted, re_ac_norm), log10(pick(unweighted, re_ac_raw) + 1) / log10(2 + pick(unweighted, "^td_")), tolerance = 1e-6)
    # unequal segment lengths make the two depth arrays differ, so the choice of array is observable
    expect_false(isTRUE(all.equal(pick(weighted, "^td_"), pick(weighted, "^tdw_"))))
    expect_false(isTRUE(all.equal(pick(weighted, re_ac_norm), log10(pick(weighted, re_ac_raw) + 1) / log10(2 + pick(weighted, "^td_")), tolerance = 1e-6)))
    # multi-normalisation / multi-radius paths use the same rule as the scalar call
    multi <- angular_choice(g, radius = radius, weigh_by_length = TRUE, normalization = c("syntax", "turner"))
    expect_identical(pick(multi, "^ac_.*_c$"), pick(weighted, re_ac_norm))
  }
  multi_radius <- angular_choice(g, radius = analysis_radius(walking = c(5, 8)), weigh_by_length = TRUE, normalization = "syntax")
  for (value in c(5, 8)) {
    scalar <- angular_choice(g, radius = analysis_radius(walking = value), weigh_by_length = TRUE, normalization = "syntax")
    expect_identical(multi_radius[[paste0("ac_a_rw", value, "_wl_c")]], pick(scalar, re_ac_norm))
  }
})

test_that("length-weighted syntax Choice is identical in memory, in Parquet and in spatial output files (scalar and multi-radius)", {
  skip_if_not_installed("sf"); skip_if_not_installed("arrow", "25.0.0"); skip_if_not_installed("jsonlite")
  dir <- so_dir(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  m <- so_segments(30)
  for (format in c("flatgeobuf", "geoparquet")) {
    src <- so_make_source(format, file.path(dir, paste0("net.", so_ext[[format]])), m)
    g <- segment_graph(src)
    for (weighted in c(TRUE, FALSE)) {
      mem <- angular_choice(g, radius = analysis_radius(walking = 30), weigh_by_length = weighted, normalization = "syntax")
      depth <- if (weighted) pick(mem, "^tdw_") else pick(mem, "^td_")
      expect_equal(pick(mem, re_ac_norm), log10(pick(mem, re_ac_raw) + 1) / log10(2 + depth), tolerance = 1e-6)
      # the two depth arrays must differ for weighting to be observable on this network
      expect_false(isTRUE(all.equal(pick(mem, "^td_"), pick(mem, "^tdw_"))))
      pq <- file.path(dir, "r.parquet")
      angular_choice(g, radius = analysis_radius(walking = 30), weigh_by_length = weighted, normalization = "syntax",
                         output_file = pq, overwrite = TRUE)
      expect_identical(pick(rs_read(pq), re_ac_norm), pick(mem, re_ac_norm))
      sp <- file.path(dir, paste0("o.", so_ext[[format]]))
      angular_choice(g, radius = analysis_radius(walking = 30), weigh_by_length = weighted, normalization = "syntax",
                         spatial_output_file = sp, overwrite = TRUE)
      expect_identical(pick(so_read(sp, format)$attrs, re_ac_norm), pick(mem, re_ac_norm))
      multi <- angular_choice(g, radius = analysis_radius(walking = c(30, 12)), weigh_by_length = weighted, normalization = "syntax")
      expect_identical(multi[[paste0("ac_a_rw30_", if (weighted) "wl_", "c")]], pick(mem, re_ac_norm))
      mpq <- file.path(dir, "m.parquet")
      angular_choice(g, radius = analysis_radius(walking = c(30, 12)), weigh_by_length = weighted, normalization = "syntax",
                         output_file = mpq, overwrite = TRUE)
      expect_identical(as.data.frame(rs_read_parquet(mpq))[[paste0("ac_a_rw30_", if (weighted) "wl_", "c")]], pick(mem, re_ac_norm))
    }
  }
})
