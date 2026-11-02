at_native <- function(name, ...) .Call(get(paste0("C_rpst_", name), asNamespace("rPSTool")), ...)
at_rows <- function(x, width = 2L) matrix(as.double(unlist(x)), ncol = width, byrow = TRUE)
at_vector <- function(x) as.double(unlist(x))
at_graph <- function(x) {
  args <- x[intersect(names(x), c("x", "points", "points_per_polygon", "polygon_point_interval"))]
  args$x <- at_rows(args$x, 4L)
  args$points <- at_rows(args$points)
  if (!is.null(args$points_per_polygon)) args$points_per_polygon <- at_vector(args$points_per_polygon)
  do.call(axial_graph, args)
}
at_check <- function(actual, expected) {
  expected <- at_vector(expected)
  expect_identical(typeof(actual), "double")
  expect_identical(is.nan(actual), is.nan(expected))
  expect_identical(is.na(actual), is.na(expected))
  expect_identical(is.infinite(actual), is.infinite(expected))
  expect_identical(actual[!is.finite(expected)], expected[!is.finite(expected)])
  expect_equal(actual[is.finite(expected)], expected[is.finite(expected)], tolerance = 2e-6)
}
test_that("both attraction bindings match supported pinned native modes", {
  ref <- dget(test_path("fixtures", "attractions-direct-v3.3.2.R"))
  expect_identical(ref$pst_commit, unname(rPSTool:::.pst_engine_pin()[["pst_commit"]]))
  old <- Sys.getenv("RPST_NUM_THREADS", unset = NA_character_)
  on.exit(if (is.na(old)) Sys.unsetenv("RPST_NUM_THREADS") else Sys.setenv(RPST_NUM_THREADS=old))
  for (cap in c("1", "2")) {
    Sys.setenv(RPST_NUM_THREADS=cap)
    graphs <- list()
    on.exit(for (g in graphs) at_native("graph_release", g$ptr), add=TRUE)
    for (case in rpst_cases(ref$cases, every = 20L, by = list(rpst_case_signature), each = list(rpst_case_edges))) {
      name <- case$graph$name
      if (is.null(graphs[[name]])) graphs[[name]] <- at_graph(case$graph)
      g <- graphs[[name]]
      # Metadata is not the authority for native output lengths or ownership.
      g$n_lines <- g$n_points <- g$n_point_groups <- g$n_crossings <- 999L
      args <- case$args
      args$attraction_points <- at_rows(args$attraction_points)
      args$radius <- do.call(analysis_radius, args$radius)
      for (field in c("points_per_polygon", "attraction_values", "line_weights"))
        if (!is.null(args[[field]])) args[[field]] <- at_vector(args[[field]])
      # weights are named after the object they are passed as: hand do.call the symbols, not the values
      for (field in c("attraction_values", "line_weights"))
        if (!is.null(args[[field]])) { assign(field, args[[field]]); args[[field]] <- as.name(field) }
      out <- do.call(if (case$analysis == "reach") attraction_reach else attraction_distance,
                     c(list(graph=g), args))
      expect_identical(out$origin_id, seq_along(case$scores))
      at_check(out[[2L]], case$scores)
      expect_identical(names(out)[1L], "origin_id")
      if (case$analysis == "distance" && isTRUE(args$destination_indices))
        expect_identical(pick(out, "^di_"), as.integer(unlist(case$indices)))
      else expect_length(out, 2L)
    }
    for (g in graphs) at_native("graph_release", g$ptr)
  }
})

test_that("only straight-only group Distance is rejected before PST computation", {
  g <- axial_graph(rbind(c(0,0,3,0),c(3,0,6,0)), points=rbind(c(1,1),c(5,1)),
                 points_per_polygon=c(1,1), polygon_point_interval=1)
  a <- rbind(c(0,0))
  for (radius in list(analysis_radius(),analysis_radius(straight=0),analysis_radius(straight=10))) {
    for (indices in c(TRUE,FALSE)) {
      expect_error(attraction_distance(g,a,radius,origin="point_groups",distance="straight",
                                          destination_indices=indices), "outputs unwritten")
      # Direct callers cannot bypass the rejection. NULL attractions would fail
      # their validation if the rejection were not performed first.
      expect_error(at_native("attraction_distance",g$ptr,radius,"point_groups","straight",
                             NULL,NULL,NULL,NULL,0,indices), "outputs unwritten")
    }
    expect_length(attraction_reach(g,a,radius,origin="point_groups",distance="straight")[[2L]],2L)
    expect_length(attraction_distance(g,a,radius,origin="points",distance="straight")[[2L]],2L)
  }
  for (distance in c("walking","steps","angular","weights")) {
    weights <- if (distance == "weights") c(1,2) else NULL
    out <- attraction_distance(g,a,origin="point_groups",distance=distance,line_weights=weights)
    expect_false(anyNA(out))
    expect_identical(pick(out, "^di_"),c(0L,0L))
    expect_equal(out[[2L]],attraction_distance(g,a,origin="point_groups",distance=distance,
                                                  destination_indices=FALSE,line_weights=weights)[[2L]])
  }
  expect_error(attraction_distance(g,a,distance="straight",radius=analysis_radius(steps=1)), "straight-only radius")
  expect_error(attraction_distance(g,a,radius=analysis_radius(axmeter=1)), "axmeter radius")
  at_native("graph_release",g$ptr)
})

test_that("attraction buffers and graphs retain exact ownership through lifetime events", {
  g <- axial_graph(rbind(c(0,0,3,0),c(3,0,6,0)),points=rbind(c(1,1),c(5,1)),
                 points_per_polygon=c(1,1),polygon_point_interval=1)
  a <- rbind(c(0,1),c(5,1))
  r <- attraction_reach(g,a,origin="point_groups")
  d <- attraction_distance(g,a,origin="point_groups",distance="walking")
  saved <- list(r,d)
  a[,] <- 99
  gc()
  expect_identical(attraction_reach(g,rbind(c(0,1),c(5,1)),origin="point_groups"),r)
  clone <- unserialize(serialize(g,NULL))
  expect_error(attraction_reach(clone,a), "no longer live")
  expect_error(attraction_distance(clone,a), "no longer live")
  at_native("graph_release",g$ptr);at_native("graph_release",g$ptr)
  expect_error(attraction_reach(g,a), "no longer live")
  expect_error(attraction_distance(g,a), "no longer live")
  rm(g,a);gc()
  expect_identical(list(r,d),saved)
  s <- segment_graph(rbind(c(0,0,1,0)))
  expect_error(attraction_reach(s,rbind(c(0,0))), "axial")
  expect_error(attraction_distance(s,rbind(c(0,0))), "axial")
  expect_error(at_native("attraction_reach",s$ptr,analysis_radius(),"lines","steps",rbind(c(0,0)),
                         NULL,NULL,NULL,"constant",0,"divide","mean"), "Invalid pst_graph")
  expect_error(at_native("attraction_distance",s$ptr,analysis_radius(),"lines","steps",rbind(c(0,0)),
                         NULL,NULL,NULL,0,TRUE), "Invalid pst_graph")
  at_native("segment_graph_release",s$ptr)
})

test_that("malformed attraction inputs fail at the native boundary without damaging graphs", {
  g <- axial_graph(rbind(c(0,0,3,0),c(3,0,6,0)))
  a <- rbind(c(0,1))
  reach <- function(...) attraction_reach(g,...)
  distance <- function(...) attraction_distance(g,...)
  for (bad in list(NULL, c(0,1), matrix(logical(2),1), matrix(0,1,3),
                   rbind(c(NA,0)),rbind(c(NaN,0)),rbind(c(Inf,0)),rbind(c(1e30,0)))) {
    expect_error(reach(bad))
    expect_error(distance(bad))
  }
  for (bad in list(-1,NA,NaN,Inf,1.1,c(1,1),"1")) {
    expect_error(reach(a,points_per_polygon=bad,polygon_point_interval=1))
    expect_error(distance(a,points_per_polygon=bad,polygon_point_interval=1))
  }
  for (bad in list(NULL,0,-1,NA,Inf,1e-300,"1")) {
    expect_error(reach(a,points_per_polygon=1,polygon_point_interval=bad))
    expect_error(distance(a,points_per_polygon=1,polygon_point_interval=bad))
  }
  expect_error(reach(a,polygon_point_interval=1), "requires")
  expect_error(distance(a,polygon_point_interval=1), "requires")
  expect_error(reach(rbind(c(0,0),c(1,0)),points_per_polygon=2,polygon_point_interval=1e-12), "point-count")
  expect_error(distance(rbind(c(0,0),c(1,0)),points_per_polygon=2,polygon_point_interval=1e-12), "float loop")
  for (bad in list(NA,Inf,1e40,1e-300,c(1,2),"1")) {
    expect_error(reach(a,attraction_values=bad))
    expect_error(reach(a,decay_constant=bad))
  }
  for (bad in list(-1,NA,Inf,1e40,1e-300,"1"))
  { bad_weights <- rep(bad,2); expect_error(distance(a,distance="weights",line_weights=bad_weights)) }
  lw <- c(1,2)
  expect_error(distance(a,line_weights=lw), "requires")
  expect_error(distance(a,distance="weights"), "is required")
  for (bad in list(-1,Inf,NA,1e-300,"0")) expect_error(distance(a,point_edge_weight=bad))
  for (bad in list(NA,1,c(TRUE,FALSE),"yes")) expect_error(distance(a,destination_indices=bad))
  expect_error(at_native("attraction_reach",g$ptr,analysis_radius(),"lines","weights",a,
                         NULL,NULL,NULL,"constant",0,"divide","mean"), "Unsupported distance")
  expect_error(at_native("attraction_reach",g$ptr,analysis_radius(),"lines","steps",a,
                         NULL,NULL,NULL,"bad",0,"divide","mean"), "Unsupported decay")
  expect_error(at_native("attraction_distance",g$ptr,analysis_radius(),"lines","axmeter",a,
                         NULL,NULL,NULL,0,TRUE), "Unsupported distance")
  zero_cost <- c(0,0); negative_value <- -1
  expect_identical(pick(attraction_distance(g,a,distance="weights",line_weights=zero_cost), "^ad_"),c(0,0))
  expect_identical(pick(attraction_reach(g,a,attraction_values=negative_value), "^ar_"),c(0,0))
  at_native("graph_release",g$ptr)
})

test_that("finite straight line Reach protects shared scratch under concurrent attractions", {
  lines <- cbind(0:29,0,1:30,0)
  g <- axial_graph(lines)
  a <- cbind(rep(c(.5,29.5),30),1)
  old <- Sys.getenv("RPST_NUM_THREADS",unset=NA_character_)
  on.exit(if (is.na(old)) Sys.unsetenv("RPST_NUM_THREADS") else Sys.setenv(RPST_NUM_THREADS=old))
  Sys.setenv(RPST_NUM_THREADS="1")
  expected <- attraction_reach(g,a,analysis_radius(straight=2),distance="straight")
  Sys.setenv(RPST_NUM_THREADS="2")
  for (i in seq_len(20)) expect_identical(attraction_reach(g,a,analysis_radius(straight=2),distance="straight"),expected)
  Sys.setenv(RPST_NUM_THREADS="bad")
  expect_error(attraction_reach(g,a),"RPST_NUM_THREADS")
  expect_error(attraction_distance(g,a),"PSTAAttractionDistance failed")
  Sys.setenv(RPST_NUM_THREADS="1")
  expect_identical(attraction_reach(g,a,analysis_radius(straight=2),distance="straight"),expected)
  at_native("graph_release",g$ptr)
})
