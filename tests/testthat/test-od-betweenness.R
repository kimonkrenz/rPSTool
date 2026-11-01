od_native <- function(name, ...) .Call(get(paste0("C_rpst_", name), asNamespace("rPSTool")), ...)
od_rows <- function(x, width = 2L) matrix(as.double(unlist(x)), ncol = width, byrow = TRUE)
od_graph <- function(case) {
  args <- case[intersect(names(case),c("x","line_indices","unlinks","points",
                                     "points_per_polygon","polygon_point_interval"))]
  args$x <- od_rows(args$x,if (is.null(args$line_indices)) 4L else 2L)
  for (field in c("line_indices","unlinks","points"))
    if (!is.null(args[[field]])) args[[field]] <- od_rows(args[[field]])
  if (!is.null(args$points_per_polygon)) args$points_per_polygon <- as.double(unlist(args$points_per_polygon))
  do.call(axial_graph,args)
}
od_call <- function(g,args) {
  args$origins <- od_rows(args$origins)
  args$radius <- do.call(analysis_radius,args$radius)
  for (field in c("origin_weights","destination_weights"))
    if (!is.null(args[[field]])) args[[field]] <- as.double(unlist(args[[field]]))
  do.call(od_betweenness,c(list(graph=g),args))
}
od_compare <- function(actual,expected) {
  expected <- as.double(unlist(expected))
  expect_identical(typeof(actual),"double")
  expect_identical(is.na(actual),is.na(expected))
  expect_identical(is.nan(actual),is.nan(expected))
  expect_identical(is.infinite(actual),is.infinite(expected))
  expect_identical(actual[!is.finite(expected)],expected[!is.finite(expected)])
  expect_equal(actual[is.finite(expected)],expected[is.finite(expected)],tolerance=2e-6)
}
test_that("OD modes, costs, limits and weights match the pinned C API", {
  ref <- dget(test_path("fixtures","od-direct-v3.3.2.R"))
  expect_identical(ref$pst_commit,unname(rPSTool:::.pst_engine_pin()[["pst_commit"]]))
  old <- Sys.getenv("RPST_NUM_THREADS",unset=NA_character_)
  on.exit(if (is.na(old)) Sys.unsetenv("RPST_NUM_THREADS") else Sys.setenv(RPST_NUM_THREADS=old))
  graphs <- list()
  on.exit(for (g in graphs) od_native("graph_release",g$ptr),add=TRUE)
  Sys.setenv(RPST_NUM_THREADS="1")
  for (case in rpst_cases(od_supported_cases(ref$cases), every = 25L, by = list(rpst_case_signature), each = list(rpst_case_edges))) {
    name <- case$graph$name
    if (is.null(graphs[[name]])) graphs[[name]] <- od_graph(case$graph)
    g <- graphs[[name]]
    expect_identical(od_native("graph_info",g$ptr)[[3L]],as.integer(case$point_count))
    g$n_lines <- g$n_points <- g$n_point_groups <- g$n_crossings <- 999L
    out <- od_call(g,case$args)
    expect_identical(names(out),c("line_id","od_betweenness"))
    expect_identical(out$line_id,seq_along(case$scores))
    od_compare(out$od_betweenness,case$scores)
  }
  # A higher cap must not activate pinned PST's disabled multi-worker branch.
  Sys.setenv(RPST_NUM_THREADS="2")
  controls <- Filter(function(c) length(c$args$radius)==0L &&
                     is.null(c$args$origin_weights) && is.null(c$args$destination_weights),od_supported_cases(ref$cases))
  for (case in rpst_cases(controls, every = 8L, by = list(rpst_case_signature))) {
    out <- od_call(graphs[[case$graph$name]],case$args)
    expect_identical(out$od_betweenness,as.double(unlist(case$scores)))
  }
})

test_that("the five upstream OD regressions and untouched graph analyses remain valid", {
  g <- axial_graph(cbind(0:2,0,1:3,0),points=rbind(c(1.5,.5),c(3.5,0)))
  origin <- rbind(c(-.5,0))
  baseline <- network_integration(g)
  expect_equal(od_betweenness(g,origin,destination_mode="closest")$od_betweenness,c(1,1,0))
  expect_equal(od_betweenness(g,origin)$od_betweenness,c(1,1,.5))
  expect_equal(od_betweenness(g,origin,analysis_radius(walking=3.9))$od_betweenness,c(1,1,0))
  expect_equal(od_betweenness(g,origin,analysis_radius(walking=4.1))$od_betweenness,c(1,1,.5))
  expect_equal(od_betweenness(g,origin,origin_weights=10)$od_betweenness,c(10,10,5))
  expect_equal(od_betweenness(g,origin,origin_weights=10,destination_weights=c(4,1))$od_betweenness,c(10,10,2))
  expect_identical(network_integration(g),baseline)
  expect_identical(od_betweenness(g,origin,origin_weights=-10)$od_betweenness,c(0,0,0))
  expect_identical(od_betweenness(g,origin,destination_weights=c(0,-1))$od_betweenness,c(0,0,0))
  od_native("graph_release",g$ptr)
})

test_that("OD weights target native sampled points and preserve pinned radius quirks", {
  g <- axial_graph(rbind(c(0,0,3,0),c(3,0,6,0)),points=rbind(c(1,1),c(2,1)),
                 points_per_polygon=2,polygon_point_interval=.5)
  expect_gt(g$n_points,g$n_point_groups)
  expect_error(od_betweenness(g,rbind(c(0,0)),destination_weights=1),"native graph point")
  expect_length(od_betweenness(g,rbind(c(0,0)),destination_weights=rep(1,g$n_points))$od_betweenness,2L)
  od_native("graph_release",g$ptr)
  g <- axial_graph(rbind(c(0,0,10,0)),points=rbind(c(1,0),c(9,2)))
  args <- list(graph=g,origins=rbind(c(1,0)),radius=analysis_radius(walking=0),destination_weights=c(0,1))
  expect_identical(do.call(od_betweenness,args)$od_betweenness,0)
  args$distance <- "angular"
  expect_identical(do.call(od_betweenness,args)$od_betweenness,1)
  args$radius <- analysis_radius(axmeter=0)   # natively ignored by PST; rejected by rPSTool (see the axmeter regression test)
  expect_error(do.call(od_betweenness,args),"axmeter radius is not supported")
  od_native("graph_release",g$ptr)
})

test_that("OD input/output lifetimes, native graph kinds and liveness are enforced", {
  g <- axial_graph(cbind(0:2,0,1:3,0),points=rbind(c(1.5,.5),c(3.5,0)))
  origins <- rbind(c(-.5,0),c(2.5,1))
  ow <- c(2,3); dw <- c(4,1)
  out <- od_betweenness(g,origins,origin_weights=ow,destination_weights=dw)
  saved <- out
  origins[,] <- 99;ow[] <- -1;dw[] <- 0
  gc()
  expect_identical(od_betweenness(g,rbind(c(-.5,0),c(2.5,1)),origin_weights=c(2,3),
                                     destination_weights=c(4,1)),saved)
  clone <- unserialize(serialize(g,NULL))
  expect_error(od_betweenness(clone,origins),"no longer live")
  od_native("graph_release",g$ptr);od_native("graph_release",g$ptr)
  expect_error(od_betweenness(g,origins),"no longer live")
  rm(g,origins,ow,dw);gc()
  expect_identical(out,saved)
  seg <- segment_graph(rbind(c(0,0,1,0)))
  group <- segment_group_graph(seg,1L)
  for (pointer in list(seg$ptr,group$ptr)) {
    expect_error(od_native("od_betweenness",pointer,rbind(c(0,0)),analysis_radius(),"walking","all",NULL,NULL),"Invalid pst_graph")
    fake <- structure(list(ptr=pointer,type="axial"),class="pst_graph")
    expect_error(od_betweenness(fake,rbind(c(0,0))),"Invalid pst_graph")
  }
  expect_error(od_betweenness(seg,rbind(c(0,0))),"axial")
  od_native("segment_group_graph_release",group$ptr)
  od_native("segment_graph_release",seg$ptr)
})

test_that("OD native validation fails safely and zero-sized sets remain genuine", {
  g <- axial_graph(cbind(0:2,0,1:3,0),points=rbind(c(1.5,.5),c(3.5,0)))
  origin <- rbind(c(-.5,0))
  call <- function(origins=origin,radius=analysis_radius(),distance="walking",mode="all",ow=NULL,dw=NULL)
    od_native("od_betweenness",g$ptr,origins,radius,distance,mode,ow,dw)
  for (bad in list(NULL,c(0,0),matrix(TRUE,1,2),matrix(0,1,3),rbind(c(NA,0)),
                   rbind(c(NaN,NaN)),rbind(c(Inf,0)),rbind(c(1e30,0)),rbind(c(1e300,0))))
    expect_error(call(origins=bad),"origins")
  for (bad in list("straight","steps","axmeter","weights",NA_character_,1,c("walking","angular")))
    expect_error(call(distance=bad),"distance")
  for (bad in list("ALL","first",NA_character_,0,c("all","closest"))) expect_error(call(mode=bad),"destination_mode")
  for (bad in list(logical(1),character(1),NA,Inf,NaN,1e40,1e-300,c(1,2))) expect_error(call(ow=bad),"origin_weights")
  for (bad in list(logical(2),c("1","2"),c(NA,1),c(Inf,1),c(1e40,1),c(1e-300,1),1))
    expect_error(call(dw=bad),"destination_weights")
  expect_error(call(radius=list()),"analysis_radius")
  malformed <- analysis_radius();malformed$steps <- -1
  expect_error(call(radius=malformed),"steps")
  expect_identical(call(origins=matrix(numeric(),0,2),ow=numeric()),c(0,0,0))
  old <- Sys.getenv("RPST_NUM_THREADS",unset=NA_character_)
  on.exit(if (is.na(old)) Sys.unsetenv("RPST_NUM_THREADS") else Sys.setenv(RPST_NUM_THREADS=old))
  Sys.setenv(RPST_NUM_THREADS="invalid")
  expect_error(call(),"PSTAODBetweenness failed")
  expect_error(call(origins=matrix(numeric(),0,2)),"PSTAODBetweenness failed")
  Sys.setenv(RPST_NUM_THREADS="1")
  expect_identical(call(),c(1,1,.5))
  od_native("graph_release",g$ptr)
  no_dest <- axial_graph(rbind(c(0,0,3,0)))
  expect_identical(od_betweenness(no_dest,rbind(c(0,1)))$od_betweenness,0)
  expect_identical(od_betweenness(no_dest,rbind(c(0,1)),destination_weights=numeric())$od_betweenness,0)
  od_native("graph_release",no_dest$ptr)
})

test_that("axmeter radius is rejected before OD Betweenness calculation; supported radius limits are unchanged", {
  g <- axial_graph(rbind(c(0,0,10,0),c(10,0,10,10)),points=rbind(c(1,0),c(9,9)))
  o <- rbind(c(1,0))
  expect_error(od_betweenness(g,o,radius=analysis_radius(axmeter=0)),"axmeter radius is not supported")
  expect_error(od_betweenness(g,o,radius=analysis_radius(axmeter=5,walking=100)),"axmeter radius is not supported")
  expect_error(od_betweenness(g,o,radius=analysis_radius(axmeter=5),distance="angular"),"axmeter radius is not supported")
  # rejection is raised before the calculation and before any output writer is reached
  expect_error(od_betweenness(g,o,radius=analysis_radius(axmeter=1),destination_weights=c(1,2,3)),"axmeter radius is not supported")
  f <- tempfile(fileext=".parquet"); on.exit(unlink(f),add=TRUE)
  expect_error(od_betweenness(g,o,radius=analysis_radius(axmeter=1),output_file=f),"axmeter radius is not supported")
  expect_false(file.exists(f))
})

test_that("supported OD radius limits still work and are not affected by the axmeter rejection", {
  g <- axial_graph(rbind(c(0,0,10,0),c(10,0,10,10)),points=rbind(c(1,0),c(9,9)))
  o <- rbind(c(1,0))
  for (r in list(analysis_radius(),analysis_radius(walking=50),analysis_radius(steps=1),analysis_radius(straight=50),analysis_radius(angular=90)))
    expect_length(od_betweenness(g,o,radius=r)$od_betweenness,2L)
  # analysis_radius() itself still accepts axmeter for analyses that honour it
  expect_no_error(analysis_radius(axmeter=3))
  expect_no_error(network_reach(g,analysis_radius(axmeter=3)))
})
