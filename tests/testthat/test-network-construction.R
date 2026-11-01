construction_native <- function(name, ...) .Call(get(paste0("C_rpst_",name),asNamespace("rPSTool")),...)
construction_rows <- function(x, width=2L) matrix(as.double(unlist(x)),ncol=width,byrow=TRUE)
construction_args <- function(case) {
  args <- case$args
  for (field in intersect(names(args),c("x","y","coords","unlinks","line_indices","line_indices_y"))) {
    width <- if(field=="x" && is.null(args$line_indices) || field=="y" && is.null(args$line_indices_y)) 4L else 2L
    args[[field]] <- construction_rows(args[[field]],width)
  }
  if(!is.null(args$sections))args$sections <- as.double(unlist(args$sections))
  args
}
test_that("construction outputs match pristine direct PST structural fixtures", {
  ref <- dget(test_path("fixtures","network-construction-direct-v3.3.2.R"))
  expect_identical(ref$pst_commit,unname(rPSTool:::.pst_engine_pin()[["pst_commit"]]))
  for(case in ref$cases) {
    args <- construction_args(case)
    if(case$kind=="junctions") {
      actual <- do.call(create_junctions,args)
      expect_equal(unname(actual),construction_rows(case$native$points),tolerance=1e-7,info=case$name)
      expect_identical(typeof(actual),"double")
      expect_identical(colnames(actual),c("x","y"))
    } else {
      actual <- do.call(create_segment_map,args)
      expect_identical(names(actual),c("segments","source_id","unlinks"))
      expect_equal(unname(actual$segments),construction_rows(case$native$segments,4L),tolerance=1e-7,info=case$name)
      expect_identical(actual$source_id,as.integer(unlist(case$native$base_id))+1L)
      expect_equal(unname(actual$unlinks),construction_rows(case$native$unlinks),tolerance=1e-7,info=case$name)
      expect_identical(colnames(actual$segments),c("x1","y1","x2","y2"))
      expect_identical(colnames(actual$unlinks),c("x","y"))
      expect_identical(typeof(actual$segments),"double")
      expect_identical(typeof(actual$unlinks),"double")
    }
  }
  expect_identical(construction_native("construction_lifecycle")[[3L]],0)
})

test_that("incomplete empty junction layers are rejected but written empties remain valid", {
  before <- construction_native("construction_lifecycle")
  empty <- matrix(numeric(),ncol=4)
  expect_error(create_junctions(empty),"Empty first junction layer")
  expect_error(construction_native("create_junctions",empty,NULL,NULL,NULL,NULL,FALSE),"without writing")
  coords <- rbind(c(0,0),c(10,0))
  indices <- matrix(integer(),ncol=2)
  expect_error(create_junctions(coords,indices),"Empty first junction layer")
  expect_error(construction_native("create_junctions",coords,indices,NULL,NULL,NULL,FALSE),"Empty first junction layer")
  expect_identical(construction_native("construction_lifecycle"),before)
  one <- matrix(c(0,0,10,0),nrow=1)
  expect_identical(dim(create_junctions(one)),c(0L,2L))
  cross <- rbind(c(-10,0,10,0),c(0,-10,0,10))
  expect_identical(nrow(create_junctions(cross)),1L)
  expect_identical(dim(create_junctions(cross,y=empty)),c(0L,2L))
})

test_that("unsafe cycle collapse fails while native successful closed shapes remain exact", {
  square <- rbind(c(0,0),c(1,0),c(1,1),c(0,1),c(0,0))
  for(coords in list(square,rbind(c(0,0),c(1,0),c(2,0),c(0,0)),
                     rbind(c(0,0),c(10,0),c(10,10),c(0,10),c(0,.1)))) {
    snap <- if(nrow(coords)==5 && coords[nrow(coords),2]==.1) .2 else 0
    deviation <- if(snap>0)20 else if(nrow(coords)==4)0 else 1
    expect_error(create_segment_map(coords,nrow(coords),snap=snap,tail=0,deviation=deviation),"PSTACreateSegmentMap failed")
    expect_error(construction_native("create_segment_map",coords,nrow(coords),"axial_or_segment",snap,0,deviation,0,NULL,FALSE),"unsafe cyclic")
    expect_identical(construction_native("construction_lifecycle")[[3L]],0)
  }
  expected <- rbind(c(0,0,1,0),c(1,0,1,1),c(1,1,0,1),c(0,1,0,0))
  small <- create_segment_map(square,5,snap=0,tail=0,deviation=0)
  expect_identical(unname(small$segments),expected)
  large <- create_segment_map(square*10,5,snap=0,tail=0,deviation=1)
  expect_identical(unname(large$segments),expected*10)
  expect_identical(small$source_id,rep(1L,4))
})

test_that("transient native owners release on success and R result-copy long jumps", {
  x <- rbind(c(-10,0,10,0),c(0,-10,0,10))
  coords <- rbind(c(0,0),c(10,0),c(20,0))
  before <- construction_native("construction_lifecycle")
  for(i in 1:8) {
    j <- create_junctions(x)
    m <- create_segment_map(coords,3,snap=0,tail=0)
    expect_error(construction_native("create_junctions",x,NULL,NULL,NULL,NULL,TRUE),"result-copy failure")
    expect_error(construction_native("create_segment_map",coords,3,"axial_or_segment",0,0,1,0,NULL,TRUE),"result-copy failure")
    gc()
  }
  after <- construction_native("construction_lifecycle")
  expect_identical(after-before,c(32,32,0))
  saved <- list(j,m);rm(x,coords,j,m);gc()
  expect_identical(saved,unserialize(serialize(saved,NULL)))
  g <- segment_graph(saved[[2L]]$segments)
  expect_identical(construction_native("segment_graph_info",g$ptr),1L)
  construction_native("segment_graph_release",g$ptr)
  gc()
  expect_identical(unname(saved[[1L]]),matrix(c(0,0),nrow=1))
  expect_identical(construction_native("construction_lifecycle")[[3L]],0)
})

test_that("construction validates storage, section encoding and native representation", {
  xy <- rbind(c(0,0),c(10,0));line <- matrix(c(0,0,10,0),nrow=1)
  expect_error(create_junctions(data.frame(line)),"matrix")
  expect_error(create_junctions(matrix("a",1,4)),"storage")
  for(v in c(NA_real_,NaN,Inf)) {
    bad <- line;bad[1]<-v;expect_error(create_junctions(bad),"finite")
    bad <- xy;bad[1]<-v;expect_error(create_segment_map(bad,2),"finite")
  }
  for(index in list(matrix(0,1,2),matrix(1.1,1,2),matrix(3,1,2),matrix(NA_real_,1,2)))
    expect_error(create_junctions(xy,index),"indices|finite")
  expect_error(create_junctions(line,line_indices_y=matrix(1,1,2)),"requires y")
  for(section in list(numeric(),c(1,0),1.5,3,-4,NA_real_,Inf,2^31))
    expect_error(create_segment_map(xy,section),"sections")
  expect_error(create_segment_map(xy,matrix(2)),"vector")
  expect_error(create_segment_map(xy,2,network_type="road_center_lines",unlinks=xy),"unlinks")
  for(name in c("snap","tail","deviation","extrude"))for(v in list(-1,NA_real_,Inf,numeric(),1e-320,1e40)) {
    args <- list(coords=xy,sections=2);args[[name]]<-v
    expect_error(do.call(create_segment_map,args),name)
  }
  expect_error(create_junctions(matrix(c(-1e300,0,1e300,0),1)),"float|center")
  expect_error(create_segment_map(rbind(c(0,0),c(1e30,0)),2),"distance")
  expect_error(create_junctions(line,unlinks=matrix(c(1e300,1e300),1)),"distance")
  integers <- xy;storage.mode(integers)<-"integer"
  expect_identical(create_segment_map(integers,2L,snap=0,tail=0),create_segment_map(xy,2,snap=0,tail=0))
  expect_identical(nrow(create_segment_map(rbind(c(0,0),c(0,0)),2)$segments),0L)
  expect_identical(construction_native("construction_lifecycle")[[3L]],0)
})
