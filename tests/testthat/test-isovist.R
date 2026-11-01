
test_that("unaffected isovist geometry and visibility match direct pinned exports (a stratified selection of cases in CRAN mode)", {
  fixtures <- dget(test_path("fixtures","isovist-direct-v3.3.2.R"))
  # CRAN mode visits a deterministic subset that still contains every geometry kind, full-circle and partial view, distance and
  # case family of the fixture (a family differs only in numbers such as the view angle and resolution); full mode visits all 85 cases.
  family <- function(item) sub("(_-?[0-9.e]+)+$","",item$case$name)
  for(item in rpst_cases(fixtures$cases,every=8L,by=list(function(i) i$case$geometry,function(i) i$case$fov>=360,function(i) i$case$distance,
                                                          family,function(i) i$returncode))) {
    case <- item$case
    if(item$returncode!=0 || case$name %in% c("degenerate_partial_near_polygon","degenerate_two_point_near_polygon","degenerate_partial_straddling_points","degenerate_full_near_polygon")) next
    ctx <- do.call(isovist_context,isovist_input(case$geometry))
    before <- isovist_life()
    for(reuse in 1:2) {
      actual <- isovist_call(ctx,case); native <- item$native
      expected <- do.call(rbind,lapply(native$points,unlist));storage.mode(expected)<-"double"
      expect_isovist_polygon(actual$polygon,expected,info=case$name)
      expect_identical(actual$area,native$area,info=case$name)
      for(pair in list(c("visible_obstacles","obstacles"),c("visible_attraction_points","attraction_points"),c("visible_attraction_polygons","attraction_polygons"))) {
        visible <- actual[[pair[1]]];ref <- native[[pair[2]]]
        expect_identical(lengths(visible),as.integer(unlist(ref$groups)),info=case$name)
        expect_identical(as.integer(unlist(visible,use.names=FALSE)),as.integer(unlist(ref$indices))+1L,info=case$name)
        expect_equal(sum(lengths(visible)),ref$count,tolerance=0)
      }
      expect_equal(isovist_life()[6],0)
    }
    expect_equal(isovist_life()[4:5]-before[4:5],c(2,2))
    isovist_context_free(ctx)
    snapshot <- serialize(actual,NULL)
    invisible(gc())
    expect_identical(serialize(actual,NULL),snapshot)
  }
})

test_that("approved actual-state guards fail without leaking and context reuse remains valid", {
  fixtures <- dget(test_path("fixtures","isovist-direct-v3.3.2.R"))
  hazards <- Filter(function(x) x$returncode!=0 || x$case$name %in% c("degenerate_partial_near_polygon","degenerate_two_point_near_polygon","degenerate_partial_straddling_points","degenerate_full_near_polygon"),fixtures$cases)
  for(item in hazards) {
    ctx <- do.call(isovist_context,isovist_input(item$case$geometry));before<-isovist_life()
    expect_error(isovist_call(ctx,item$case),"no result was published")
    expect_identical(isovist_life()[4:6],before[4:6])
    good <- isovist(ctx,c(0,0),1,90)
    expect_true(nrow(good$polygon)>2)
    expect_equal(isovist_life()[6],0)
    isovist_context_free(ctx)
  }
  ctx<-isovist_context()
  expect_identical(isovist(ctx,c(0,0),.01,90)$area,0)
  expect_equal(nrow(isovist(ctx,c(0,0),.01,90)$polygon),1)
  isovist_context_free(ctx)
})

test_that("partial attraction-point guard preserves reuse, aliases and native ownership", {
  invisible(gc())
  before <- isovist_life()
  ctx <- do.call(isovist_context,isovist_input("straddling_points"))
  alias <- ctx
  expect_equal(isovist_life()[1:3]-before[1:3],c(1,0,1))
  saved <- isovist(ctx,c(0,0),1,90)
  snapshot <- serialize(saved,NULL)
  for (iteration in 1:3) {
    active <- isovist_life()
    expect_error(isovist(alias,c(0,0),.01,90),"no result was published")
    expect_identical(isovist_life(),active)
    expect_identical(isovist(ctx,c(0,0),1,90),saved)
    expect_equal(isovist_life()[4:6]-active[4:6],c(1,1,0))
  }
  expect_equal(nrow(isovist(ctx,c(0,0),1,360)$polygon),64)
  isovist_context_free(ctx)
  isovist_context_free(alias)
  expect_equal(isovist_life()[1:3]-before[1:3],c(1,1,0))
  expect_equal(isovist_life()[6],0)
  expect_error(isovist(alias,c(0,0),1,90),"dead")
  invisible(gc())
  expect_identical(serialize(saved,NULL),snapshot)
  # A singleton whose point queue stays empty remains a successful PST result.
  single <- do.call(isovist_context,isovist_input("near_point"))
  expect_equal(nrow(isovist(single,c(0,0),.01,90)$polygon),1)
  isovist_context_free(single)
  invisible(gc())
  active <- isovist_life()
  local({
    temporary <- do.call(isovist_context,isovist_input("straddling_points"))
    expect_error(isovist(temporary,c(0,0),.01,90),"no result was published")
    invisible(isovist(temporary,c(0,0),1,90))
  })
  invisible(gc())
  expect_equal(isovist_life()-active,c(1,1,0,1,1,0))
})

test_that("full-circle polygon guard preserves queued controls and singleton results", {
  invisible(gc())
  before <- isovist_life()
  ctx <- do.call(isovist_context,isovist_input("near_polygon"))
  alias <- ctx
  saved <- isovist(ctx,c(0,0),.02,360,0,3)
  snapshot <- serialize(saved,NULL)
  for (iteration in 1:3) {
    active <- isovist_life()
    expect_error(isovist(alias,c(0,0),.01,360,0,3),"no result was published")
    expect_identical(isovist_life(),active)
    expect_identical(isovist(ctx,c(0,0),.02,360,0,3),saved)
    expect_equal(isovist_life()[4:6]-active[4:6],c(1,1,0))
  }
  isovist_context_free(ctx)
  isovist_context_free(alias)
  expect_equal(isovist_life()[1:3]-before[1:3],c(1,1,0))
  expect_equal(isovist_life()[6],0)
  expect_error(isovist(alias,c(0,0),.02,360,0,3),"dead")
  invisible(gc())
  expect_identical(serialize(saved,NULL),snapshot)
  for (kind in c("empty","inside_attraction")) {
    single <- do.call(isovist_context,isovist_input(kind))
    expect_equal(nrow(isovist(single,c(0,0),.01,360,0,3)$polygon),1)
    isovist_context_free(single)
  }
  invisible(gc())
  active <- isovist_life()
  local({
    temporary <- do.call(isovist_context,isovist_input("near_polygon"))
    expect_error(isovist(temporary,c(0,0),.01,360,0,3),"no result was published")
    invisible(isovist(temporary,c(0,0),.02,360,0,3))
  })
  invisible(gc())
  expect_equal(isovist_life()-active,c(1,1,0,1,1,0))
})

test_that("context tags, lifetime and R allocation unwinding protect dependent results", {
  ctx<-isovist_context();alias<-ctx
  before<-isovist_life()
  expect_error(.Call(rPSTool:::C_rpst_isovist_calculate,ctx$ptr,c(0,0),1,360,0,64,TRUE),"Injected isovist")
  expect_equal(isovist_life()[4:5]-before[4:5],c(1,1))
  expect_equal(isovist_life()[6],0)
  out<-isovist(ctx,c(0,0),1);saved<-serialize(out,NULL)
  dead<-unserialize(serialize(ctx,NULL))
  expect_error(isovist(dead,c(0,0),1),"dead or deserialised")
  isovist_context_free(dead)
  sg <- segment_graph(matrix(c(0,0,1,0),1,4))
  gg <- segment_group_graph(sg,1L)
  for(graph in list(gg,axial_graph(matrix(c(0,0,1,0),1,4)),segment_graph(matrix(c(0,0,1,0),1,4)))) {
    forged<-ctx;forged$ptr<-graph$ptr
    expect_error(isovist(forged,c(0,0),1),"exact rPSTool isovist")
    expect_error(isovist_context_free(forged),"exact rPSTool isovist")
  }
  expect_error(isovist(list(ptr=ctx$ptr),c(0,0),1),"Expected a pst_isovist_context")
  isovist_context_free(ctx);isovist_context_free(alias)
  expect_error(isovist(alias,c(0,0),1),"dead")
  expect_identical(serialize(out,NULL),saved)
  invisible(gc());before<-isovist_life()
  local({g<-isovist_context();isovist(g,c(0,0),1);invisible(NULL)})
  invisible(gc())
  expect_equal(isovist_life()[1:2]-before[1:2],c(1,1))
  expect_equal(isovist_life()[6],0)
  ctx<-isovist_context()
  gctorture(TRUE)
  result<-tryCatch(isovist(ctx,c(0,0),1),finally=gctorture(FALSE))
  expect_equal(nrow(result$polygon),64)
  isovist_context_free(ctx)
})

test_that("isovist input partitions and native bounds fail before calculation", {
  expect_error(isovist_context(obstacles=list(matrix(1,2,2))),"list of vertex matrices")
  expect_error(isovist_context(obstacles=list(list(matrix(numeric(),0,2)))),"need vertices")
  expect_error(isovist_context(attraction_points=list(matrix(Inf,1,2))),"finite")
  expect_error(isovist_context(attraction_points=rep(list(matrix(numeric(),0,2)),257)),"256")
  expect_error(isovist_context(attraction_points=list(matrix(c(-1e30,0,1e30,0),2,2,byrow=TRUE))),"extent")
  flat<-list(matrix(c(0,0),1,2),1L)
  expect_error(.Call(rPSTool:::C_rpst_isovist_context_create,list(matrix(numeric(),0,2),0L,integer()),list(flat[[1]],2L),list(matrix(numeric(),0,2),0L,integer())),"partition")
  ctx<-isovist_context()
  expect_error(isovist(ctx,c(NA,0),1),"origin")
  expect_error(isovist(ctx,c(0,0),Inf),"max_distance")
  expect_error(isovist(ctx,c(0,0),-1),"max_distance")
  expect_error(isovist(ctx,c(0,0),1,361),"field_of_view")
  expect_error(isovist(ctx,c(0,0),1,360,Inf),"direction")
  expect_error(isovist(ctx,c(0,0),1e30),"max_distance")
  expect_error(isovist(ctx,c(0,0),1,360,0,2),"at least 3")
  expect_error(isovist(ctx,c(0,0),1,360,0,4.5),"whole native")
  isovist_context_free(ctx)
})
