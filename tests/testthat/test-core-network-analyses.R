# Oracles transcribed from pinned PST testreach.py, testsegmentbetweenness.py,
# testangularchoice.py and graphs.py at 63df80a2cf3dd289be95ea3d91667c3490719b75.
# Counts/lengths and Segment Betweenness use exact equality. Choice uses
# common.py's actual-denominator element predicate; Reach area requires exact
# zero when actual is zero (the distinct predicate in testreach.py).
core_chain <- function(n = 5, length = 3) cbind(0:(n-1)*length, 0, 1:n*length, 0)
core_square <- function() rbind(c(0,0,3,0), c(3,0,3,3), c(3,3,0,3), c(0,3,0,0))
core_relative <- function(actual, expected, reach = FALSE) {
  length(actual) == length(expected) && all(vapply(seq_along(actual), function(i) {
    if (!is.finite(actual[i]) || !is.finite(expected[i]))
      return(identical(actual[i], expected[i]))
    if (actual[i] == 0) return(if (reach) expected[i] == 0 else abs(expected[i]) <= 0.0001)
    abs((expected[i] - actual[i]) / actual[i]) <= 0.0001
  }, logical(1)))
}
core_native <- function(name, ...) .Call(get(paste0("C_rpst_", name), asNamespace("rPSTool")), ...)

test_that("Reach reproduces every pinned line-origin oracle", {
  g <- axial_graph(core_chain(3))
  cases <- list(
    list(analysis_radius(), c(3L,3L,3L), c(9,9,9), c(0,0,0)),
    list(analysis_radius(straight=0), c(1L,1L,1L), c(3,3,3), c(0,0,0)),
    list(analysis_radius(straight=1), c(1L,1L,1L), c(3,3,3), rep(pi,3)),
    list(analysis_radius(straight=3), c(2L,3L,2L), c(6,9,6), rep(9*pi,3)),
    list(analysis_radius(walking=0), c(1L,1L,1L), c(3,3,3), c(0,0,0)),
    list(analysis_radius(walking=1), c(1L,1L,1L), c(3,3,3), c(0,0,0)),
    list(analysis_radius(walking=3), c(2L,3L,2L), c(6,9,6), c(0,0,0)),
    list(analysis_radius(steps=0), c(1L,1L,1L), c(3,3,3), c(0,0,0)),
    list(analysis_radius(steps=1), c(2L,3L,2L), c(6,9,6), c(0,0,0)),
    list(analysis_radius(steps=2), c(3L,3L,3L), c(9,9,9), c(0,0,0)),
    list(analysis_radius(angular=1), c(3L,3L,3L), c(9,9,9), c(0,0,0)))
  for (case in cases) {
    out <- network_reach(g, case[[1]])
    expect_identical(out$reached_count, case[[2]])
    expect_identical(out$reached_length, case[[3]])
    expect_true(core_relative(out$reached_area, case[[4]], TRUE))
    native <- core_native("reach", g$ptr, case[[1]])
    expect_identical(unname(as.list(out[-1])), native)
  }
  g <- axial_graph(core_square())
  for (case in list(list(analysis_radius(),4L,12,9), list(analysis_radius(angular=80),1L,3,0),
                   list(analysis_radius(angular=100),3L,9,9), list(analysis_radius(angular=190),4L,12,9))) {
    out <- network_reach(g,case[[1]])
    expect_identical(out$reached_count,rep(case[[2]],4))
    expect_identical(out$reached_length,rep(case[[3]],4))
    expect_true(core_relative(out$reached_area,rep(case[[4]],4), TRUE))
  }
})

test_that("Segment Betweenness reproduces all pinned raw score oracles", {
  g <- axial_graph(core_chain(5,1))
  out <- network_betweenness(g,analysis_radius(steps=4))
  expect_identical(out$betweenness,c(0,3,4,3,0))
  for (bottom in c(-0.1,0)) {
    p <- rbind(c(-2,0),c(-1,0),c(0,0.1),c(0,bottom),c(1,0),c(2,0))
    x <- cbind(p[c(1,2,3,2,4,5),],p[c(2,3,5,4,5,6),])
    out <- network_betweenness(axial_graph(x),analysis_radius(angular=45),"angular")
    expect_identical(out$betweenness,if (bottom<0) c(0,1.5,1.5,1.5,1.5,0) else c(0,1,1,2,2,0))
  }
  for (distance in c("walking","steps","angular","axmeter")) {
    out <- network_betweenness(g,distance=distance)
    expect_identical(out$betweenness,c(0,3,4,3,0))
    expect_identical(out$node_count,rep(5L,5))
    raw <- core_native("betweenness",g$ptr,analysis_radius(),distance,"none")
    expect_identical(unname(as.list(out[-1])),raw[1:3])
  }
})

test_that("Angular Choice reproduces pinned radius and weighting oracles", {
  g <- segment_graph(core_chain())
  out <- angular_choice(g)
  expect_true(core_relative(out$choice,c(0,6,8,6,0)))
  expect_identical(out$node_count,rep(5L,5))
  expect_true(core_relative(out$total_depth,rep(0,5)))
  weighted <- angular_choice(g,weigh_by_length=TRUE)
  expect_true(core_relative(weighted$choice,c(36,90,108,90,36)))
  expect_true(core_relative(weighted$total_depth_weight,rep(0,5)))
  for (field in c("straight","walking","steps")) {
    for (limit in c(0,1,if (field=="steps") 2 else 3)) {
      radius <- do.call(analysis_radius,setNames(list(limit),field))
      expected <- if (limit==0 || (field!="steps" && limit==1)) rep(1L,5) else
        if (field=="steps" && limit==2) c(3L,4L,5L,4L,3L) else c(2L,3L,3L,3L,2L)
      expect_identical(angular_choice(g,radius)$node_count,expected)
    }
  }
  expect_identical(angular_choice(g,analysis_radius(angular=1))$node_count,rep(5L,5))
  g <- segment_graph(core_square())
  out <- angular_choice(g)
  expect_true(core_relative(out$choice,rep(1,4)))
  expect_true(core_relative(out$total_depth,rep(4,4)))
  for (angle in c(80,100)) {
    out <- angular_choice(g,analysis_radius(angular=angle))
    expect_identical(out$node_count,rep(if(angle==80) 1L else 3L,4))
    expect_true(core_relative(out$total_depth,rep(if(angle==80) 0 else 2,4)))
  }
  weighted <- angular_choice(g,weigh_by_length=TRUE)
  expect_true(core_relative(weighted$choice,rep(36,4)))
  expect_true(core_relative(weighted$total_depth_weight,rep(12,4)))
  raw <- core_native("angular_choice",g$ptr,analysis_radius(),TRUE,"none")
  expect_identical(unname(as.list(weighted[-1])),raw[1:4])
})

test_that("exported normalization preserves raw results", {
  g <- axial_graph(core_chain(5,1))
  expect_identical(network_betweenness(g,normalization="standard")$normalized,c(0,0.75,1,0.75,0))
  expect_true(core_relative(network_betweenness(g,normalization="freeman")$normalized,c(0,0.5,2/3,0.5,0)))
  # Expected only: normalization equations are never used in implementation.
  raw <- network_betweenness(g)
  expected <- log10(raw$betweenness+1)/log10(raw$total_depth+2)
  expect_true(core_relative(network_betweenness(g,normalization="syntax")$normalized,expected))
  s <- segment_graph(core_chain())
  expect_identical(angular_choice(s,normalization="standard")$normalized,c(0,0.75,1,0.75,0))
  expect_true(core_relative(angular_choice(s,normalization="turner")$normalized,c(0,0.5,2/3,0.5,0)))
  for (weighted in c(FALSE,TRUE)) {
    raw <- angular_choice(s,weigh_by_length=weighted)
    expected <- log10(raw$choice+1)/log10(raw$total_depth+2)
    normalized <- angular_choice(s,weigh_by_length=weighted,normalization="syntax")
    expect_true(core_relative(normalized$normalized,expected))
    expect_identical(normalized[names(raw)],raw)
  }
})

test_that("shared radii are additive and legacy steps remain identical", {
  a <- axial_graph(core_chain())
  s <- segment_graph(core_chain())
  for (steps in c(0,1,2,2147483647)) {
    expect_identical(network_integration(a,steps),network_integration(a,radius=analysis_radius(steps=steps)))
    expect_identical(angular_integration(s,steps),angular_integration(s,radius=analysis_radius(steps=steps)))
  }
  expect_error(network_integration(a,steps=1,radius=analysis_radius()),"either steps or radius")
  expect_error(angular_integration(s,steps=1,radius=analysis_radius()),"either steps or radius")
  for (field in c("straight","walking","angular")) {
    r <- do.call(analysis_radius,setNames(list(if(field=="angular") 1 else 3),field))
    expect_identical(angular_integration(s,radius=r)$node_count,angular_choice(s,r)$node_count)
  }
  r <- analysis_radius(straight=3,walking=6,steps=2,angular=1,axmeter=100)
  expect_identical(network_reach(a,r)$reached_count,c(2L,3L,3L,3L,2L))
})

test_that("all new entry points enforce graph tags and liveness before access", {
  a <- axial_graph(core_chain());s <- segment_graph(core_chain())
  fake_a <- structure(list(ptr=s$ptr,type="axial"),class="pst_graph")
  fake_s <- structure(list(ptr=a$ptr,type="segment"),class="pst_segment_graph")
  for (fn in list(network_reach,network_betweenness)) {
    expect_error(fn(s),"live axial pst_graph")
    expect_error(fn(fake_a),"Invalid pst_graph native pointer")
    expect_error(fn(unserialize(serialize(a,NULL))),"no longer live")
  }
  expect_error(angular_choice(a),"live pst_segment_graph")
  expect_error(angular_choice(fake_s),"Invalid pst_segment_graph native pointer")
  expect_error(angular_choice(unserialize(serialize(s,NULL))),"no longer live")
  for (ptr in list(s$ptr,NULL,1,new("externalptr"))) {
    expect_error(core_native("reach",ptr,analysis_radius()),"Invalid pst_graph native pointer")
    expect_error(core_native("betweenness",ptr,analysis_radius(),"steps","none"),"Invalid pst_graph native pointer")
  }
  for (ptr in list(a$ptr,NULL,1,new("externalptr")))
    expect_error(core_native("angular_choice",ptr,analysis_radius(),FALSE,"none"),"Invalid pst_segment_graph native pointer")
  core_native("graph_release",a$ptr);core_native("segment_graph_release",s$ptr)
  expect_error(network_reach(a),"no longer live")
  expect_error(network_betweenness(a),"no longer live")
  expect_error(angular_choice(s),"no longer live")
  star <- cbind(0,0,seq_len(33),1)
  g <- segment_graph(star)
  expect_error(angular_choice(g),"at most 32 endpoint incidences")
  expect_error(core_native("angular_choice",g$ptr,analysis_radius(),FALSE,"none"),"at most 32 endpoint incidences")
  expect_identical(angular_choice(segment_graph(star[1:32,]))$node_count,rep(32L,32))
})

test_that("invalid radii and modes fail in R and native conversion", {
  a <- axial_graph(core_chain());s <- segment_graph(core_chain())
  for (radius in list(NULL,1,list(),structure(list(steps=1),class="pst_radius"))) {
    expect_error(network_reach(a,radius),"analysis_radius")
    expect_error(network_betweenness(a,radius),"analysis_radius")
    expect_error(angular_choice(s,radius),"analysis_radius")
    expect_error(core_native("reach",a$ptr,radius),"analysis_radius")
    expect_error(core_native("betweenness",a$ptr,radius,"steps","none"),"analysis_radius")
    expect_error(core_native("angular_choice",s$ptr,radius,FALSE,"none"),"analysis_radius")
  }
  for (field in names(analysis_radius())) {
    for (v in list(TRUE,"1",numeric(),c(1,2),NA_integer_,NA_real_,NaN,Inf,-Inf,-1,1+1i,1e40)) {
      bad <- analysis_radius();bad[field] <- list(v)
      expect_error(network_reach(a,bad))
      expect_error(core_native("reach",a$ptr,bad))
      expect_error(core_native("betweenness",a$ptr,bad,"steps","none"))
      expect_error(core_native("angular_choice",s$ptr,bad,FALSE,"none"))
    }
  }
  for (value in c(0.5,2147483648)) {
    bad <- analysis_radius();bad$steps <- value
    expect_error(network_reach(a,bad),"steps must be NULL")
    expect_error(core_native("reach",a$ptr,bad),"steps must be NULL")
  }
  large <- tiny <- analysis_radius();large$straight <- 1e20;tiny$walking <- 1e-100
  expect_error(analysis_radius(straight=1e20),"overflows or underflows")
  expect_error(analysis_radius(walking=1e-100),"overflows or underflows")
  for (r in list(large,tiny)) {
    expect_error(network_reach(a,r),"overflows or underflows")
    expect_error(core_native("reach",a$ptr,r),"overflows or underflows")
  }
  for (fn in list(angular_choice,angular_integration))
    expect_error(fn(s,radius=analysis_radius(axmeter=0)),"axmeter radius is unsupported")
  expect_error(core_native("angular_choice",s$ptr,analysis_radius(axmeter=0),FALSE,"none"),"axmeter radius is unsupported")
  expect_error(core_native("angular_integration",s$ptr,analysis_radius(axmeter=0)),"axmeter radius is unsupported")
  for (mode in list("straight","weights",0L,NA_character_,"ang",c("steps","angular"))) {
    expect_error(network_betweenness(a,distance=mode),"distance must be")
    expect_error(core_native("betweenness",a$ptr,analysis_radius(),mode,"none"),"Unsupported distance")
  }
  for (mode in list("bogus",0L,NA_character_,"turn",character())) {
    expect_error(network_betweenness(a,normalization=mode),"normalization must be")
    expect_error(angular_choice(s,normalization=mode),"normalization must be")
    expect_error(core_native("betweenness",a$ptr,analysis_radius(),"steps",mode),"Unsupported normalization")
    expect_error(core_native("angular_choice",s$ptr,analysis_radius(),FALSE,mode),"Unsupported normalization")
  }
  for (w in list(1L,NA,logical(),c(TRUE,FALSE),"TRUE")) {
    expect_error(angular_choice(s,weigh_by_length=w),"TRUE or FALSE")
    expect_error(core_native("angular_choice",s$ptr,analysis_radius(),w,"none"),"TRUE or FALSE")
  }
})

test_that("new results retain row order, graph reuse and independent lifetime", {
  x <- rbind(c(0,0,3,0),c(3,0,3,3),c(3,3,6,3),c(6,3,9,3))
  order <- c(4L,2L,1L,3L)
  for (case in list(list(axial_graph,network_reach,"line_id","graph"),
                   list(axial_graph,network_betweenness,"line_id","graph"),
                   list(segment_graph,angular_choice,"segment_id","segment_graph"))) {
    gc(); before <- core_native(paste0(case[[4]],"_lifecycle"))
    g <- case[[1]](x);ptr <- g$ptr
    out <- case[[2]](g)
    g$n_lines <- g$n_segments <- 999L
    for (i in 1:3) expect_identical(case[[2]](g),out)
    expect_identical(g$ptr,ptr)
    perm <- case[[2]](case[[1]](x[order,]))
    expect_identical(perm[[case[[3]]]],seq_len(4))
    for (col in setdiff(names(out),case[[3]]))
      expect_true(core_relative(perm[[col]],out[[col]][order]))
    rm(g,ptr);gc()
    expect_identical(out[[case[[3]]]],seq_len(4))
    # The temporary reordered graph is also finalized; no analysis owns handles.
    delta <- core_native(paste0(case[[4]],"_lifecycle"))-before
    expect_identical(delta,c(2,2,0))
  }
})

test_that("all radius fields and centrality modes match direct official-wrapper oracle", {
  ref <- dget(test_path("fixtures","core-network-direct-v3.3.2.R"))
  expect_identical(ref$pst_commit,unname(rPSTool:::.pst_engine_pin()[["pst_commit"]]))
  rows <- do.call(rbind,ref$rows)
  a <- axial_graph(rows);s <- segment_graph(rows)
  for (case in ref$cases) {
    radius <- do.call(analysis_radius,case$radius)
    out <- switch(case$routine,
      reach=network_reach(a,radius),
      integration=legacy_ni_run(a,radius=radius),
      betweenness=network_betweenness(a,radius,case$distance),
      angular_choice=angular_choice(s,radius,case$weighted),
      angular_integration=angular_integration(s,radius=radius))
    count <- if (case$routine=="reach") out$reached_count else out$node_count
    score <- out[[if (case$routine=="reach") "reached_length" else
      if (case$routine=="betweenness") "betweenness" else
        if (case$routine=="angular_choice") "choice" else "integration"]]
    depth <- if (case$routine=="reach") out$reached_area else out$total_depth
    expect_identical(count,as.integer(case$count),info=case$routine)
    expect_true(core_relative(score,case$score),info=paste(case$routine,case$distance))
    expect_true(core_relative(depth,case$depth),info=paste(case$routine,case$distance))
    if (case$routine=="angular_choice" && case$weighted)
      expect_true(core_relative(out$total_depth_weight,case$extra))
    for (norm in names(case$normalizations)) {
      normalized <- if (case$routine=="betweenness")
        network_betweenness(a,radius,case$distance,norm) else
        angular_choice(s,radius,case$weighted,norm)
      expect_true(core_relative(normalized$normalized,case$normalizations[[norm]]))
      expect_identical(normalized[names(out)],out)
    }
  }
})

test_that("small neighbourhood normalization and native float narrowing are preserved", {
  a <- axial_graph(matrix(c(0,0,3,0),nrow=1))
  s <- segment_graph(matrix(c(0,0,3,0),nrow=1))
  expect_identical(network_betweenness(a,normalization="standard")$normalized,1)
  expect_identical(network_betweenness(a,normalization="freeman")$normalized,0)
  expect_identical(network_betweenness(a,normalization="syntax")$normalized,0)
  expect_identical(angular_choice(s,normalization="standard")$normalized,1)
  expect_identical(angular_choice(s,normalization="turner")$normalized,0)
  expect_identical(angular_choice(s,normalization="syntax")$normalized,0)
  # Float rounds this limit to exactly three. Widening the output is lossless.
  a <- axial_graph(core_chain(3))
  expect_identical(network_reach(a,analysis_radius(walking=3-1e-8)),network_reach(a,analysis_radius(walking=3)))
  expect_identical(network_reach(a,analysis_radius(steps=1L)),network_reach(a,analysis_radius(steps=1)))
})
