source(test_path("fixtures", "raster-direct-v3.3.2.R"), local = TRUE)
raster_symbol <- function(name) get(paste0("C_",name), envir=asNamespace("rPSTool"))
raster_counts <- function() .Call(raster_symbol("rpst_raster_lifecycle"))
raster_args <- function() list(x=matrix(c(0,0,2,2,0,2,2,0),2,4,byrow=TRUE),
                              values1=c(1,2),values2=c(3,4))

test_that("raster pixels and polygon geometry retain direct pinned PST results", {
  for (case in raster_direct_fixture) {
    r <- do.call(compare_line_results,case$args)
    for (repeat_use in 1:2) {
      actual <- raster_data(r)
      expected <- case$expected
      expect_equal(unname(actual$bbox),expected$bbox,tolerance=0,info=case$name)
      expect_equal(unname(actual$dimensions),expected$dimensions,tolerance=0,info=case$name)
      for (field in c("pitch","format","min","max","values"))
        expect_equal(actual[[field]],expected[[field]],tolerance=0,info=paste(case$name,field))
      polygons <- raster_to_polygons(r,case$ranges)
      expect_equal(polygons,case$polygons,tolerance=0,info=case$name)
    }
    raster_free(r)
    expect_equal(polygons,case$polygons,tolerance=0)
    expect_equal(actual$values,expected$values,tolerance=0)
  }
})

test_that("comparison owners, aliases, GC, serialization and copy errors are safe", {
  gc()
  before <- raster_counts()
  r <- do.call(compare_line_results,raster_args()); alias <- r
  expect_equal(raster_counts()-before,c(1,0,1,0,0,0))
  saved <- unserialize(serialize(r,NULL))
  expect_error(raster_data(saved),"dead or deserialised")
  expect_error(raster_to_polygons(saved,matrix(c(0,1),1,2)),"dead or deserialised")
  raster_free(saved);raster_free(saved)
  expect_error(.Call(raster_symbol("rpst_raster_polygons"),r$ptr,matrix(c(.1,1),1,2),TRUE),
               "Injected raster polygon-copy failure")
  expect_equal(raster_counts()-before,c(1,0,1,1,1,0))
  pixels <- raster_data(r)
  rings <- raster_to_polygons(r,matrix(c(.1,1),1,2))
  expect_true(length(rings[[1]])>0)
  raster_free(r);raster_free(alias)
  expect_equal(raster_counts()-before,c(1,1,0,2,2,0))
  expect_error(raster_data(alias),"dead or deserialised")
  expect_error(raster_to_polygons(alias,matrix(c(0,1),1,2)),"dead or deserialised")
  expect_equal(pixels$values,raster_direct_fixture[[1]]$expected$values,tolerance=0)
  expect_true(is.matrix(rings[[1]][[1]][[1]]))
  r <- do.call(compare_line_results,raster_args());rm(r);gc()
  expect_equal(raster_counts()-before,c(2,2,0,2,2,0))
})

test_that("native tags and malformed raster storage are rejected", {
  g <- axial_graph(matrix(c(0,0,2,2),1,4))
  expect_error(.Call(raster_symbol("rpst_raster_data"),g$ptr),"exact rPSTool comparison raster")
  expect_error(.Call(raster_symbol("rpst_raster_release"),g$ptr),"exact rPSTool comparison raster")
  expect_error(raster_data(g),"pst_raster")
  expect_error(compare_line_results("bad",1,2),"matrices")
  args <- raster_args()
  bad <- list(x=list(matrix(raw(8),2,4),matrix(numeric(),0,4),matrix(1,1,3),
                     matrix(Inf,2,4),matrix(NA_real_,2,4)),
              values1=list("bad",c(1),c(1,NA_real_),c(1,Inf),c(1,1e40),c(1,1e-100)),
              values2=list(c(1),c(1,NaN)),
              y=list(matrix(numeric(),0,4),matrix(1,1,4)),
              resolution=list(0,-1,NA_real_,Inf,1e-100,1e-38,1e-20),
              blur_radius=list(-1,NA_real_,Inf,1e40),
              m=list(NA_real_,Inf,1e40,1e-100))
  for (key in names(bad)) for (value in bad[[key]]) {
    changed <- args;changed[[key]] <- value
    expect_error(do.call(compare_line_results,changed),info=key)
  }
  expect_error(compare_line_results(args$x, args$values1, args$values2,
                                   blur_radius=1e10, resolution=1), "kernel bounds")
  expect_error(compare_line_results(matrix(c(0,0,2,0),1,4),1,2,blur_radius=0,resolution=1),
               "positive dimensions")
  expect_error(compare_line_results(matrix(c(0,0,1e300,1e300),1,4),1,2),"extent|pixel")
  expect_error(.Call(raster_symbol("rpst_compare_results"),args$x,args$values1,args$values2,
                     NULL,0,1,1,0),"mode")
  r <- do.call(compare_line_results,args)
  for (ranges in list(matrix(raw(2),1,2),matrix(1,1,3),matrix(c(NA,1),1,2),
                      matrix(c(1e40,1),1,2),matrix(c(1e-100,1),1,2)))
    expect_error(raster_to_polygons(r,ranges))
  expect_error(.Call(raster_symbol("rpst_raster_polygons"),r$ptr,matrix(c(0,1),1,2),NA),"flag")
  raster_free(r)
})

test_that("written nonfinite raster and boundary results remain native values", {
  args <- raster_args();args$values1 <- args$values2 <- c(0,0)
  r <- do.call(compare_line_results,args)
  d <- raster_data(r)
  expect_identical(d$min,0);expect_identical(d$max,0)
  expect_true(all(is.nan(d$values)))
  expect_identical(raster_to_polygons(r,matrix(c(-Inf,Inf),1,2)),list(list()))
  raster_free(r)
  r <- do.call(compare_line_results,raster_args())
  rings <- raster_to_polygons(r,matrix(c(-Inf,Inf),1,2))
  expect_true(any(!is.finite(unlist(rings))))
  raster_free(r)
})

test_that("blur uses the central worker cap without changing native results", {
  previous <- Sys.getenv("RPST_NUM_THREADS",unset=NA_character_)
  on.exit(if(is.na(previous)) Sys.unsetenv("RPST_NUM_THREADS") else Sys.setenv(RPST_NUM_THREADS=previous))
  outputs <- list()
  for (cap in c("1","2")) {
    Sys.setenv(RPST_NUM_THREADS=cap)
    r <- do.call(compare_line_results,raster_args())
    outputs[[cap]] <- raster_data(r);raster_free(r)
  }
  expect_identical(outputs[[1]],outputs[[2]])
  # Windows R's Sys.setenv(name="") removes the variable via _putenv, whereas POSIX keeps a present empty string
  # (see test-workers.R). Check that platform contract, then test the behaviour it implies: a present empty limit
  # is invalid, an absent one selects the default worker policy, which must not change native results.
  Sys.setenv(RPST_NUM_THREADS="")
  empty_is_present <- !is.na(Sys.getenv("RPST_NUM_THREADS",unset=NA_character_))
  expect_identical(empty_is_present,.Platform$OS.type != "windows")
  if (empty_is_present) {
    expect_error(do.call(compare_line_results,raster_args()),"comparison failed")
  } else {
    r <- do.call(compare_line_results,raster_args())
    expect_identical(raster_data(r),outputs[[1]]);raster_free(r)
  }
  for (cap in c("0","-1","1.5","4294967296")) {
    Sys.setenv(RPST_NUM_THREADS=cap)
    expect_error(do.call(compare_line_results,raster_args()),"comparison failed")
  }
})
