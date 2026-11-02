
# Weight vectors used by the tests below; the object names become the weight names in the result columns.
wt_rep_1_3 <- rep(1,3)
wt_0 <- 0
wt_2 <- 2
wt_c_1_10_1 <- c(1,-10,1)
wt_c_2_0_1 <- c(2,0,1)
wt_c_2_3_4 <- c(2,3,4)
wt_c_5_0_4 <- c(5,0,4)
wt_1_3 <- 1:3
wt_c_1_2_3 <- c(1,2,3)
wt_c_1_1_1 <- c(1,-1,1)
wt_c_1l_1l_1l <- c(1L,-1L,1L)
wt_rep_1e_45_3 <- rep(1e-45,3)
wt_rep_m1e_45_3 <- rep(-1e-45,3)
wt_c_1_0_1 <- c(1,0,1)
wt_rep_1_999 <- rep(1,999)

origin_native <- function(name, ...) .Call(get(paste0("C_rpst_", name), asNamespace("rPSTool")), ...)
origin_chain <- function() cbind(0:2, 0, 1:3, 0)
origin_points <- function() rbind(c(0.5,0), c(2.5,0))
origin_near <- function(actual, expected) {
  expect_identical(is.na(actual), is.na(expected))
  expect_identical(is.nan(actual), is.nan(expected))
  expect_identical(is.infinite(actual), is.infinite(expected))
  finite <- is.finite(expected)
  expect_identical(actual[!finite], expected[!finite])
  expect_equal(actual[finite], expected[finite], tolerance = 1e-6)
}

test_that("optional modes match pinned exports and compact normalization oracles", {
  ref <- dget(test_path("fixtures", "reach-betweenness-direct-v3.3.2.R"))
  expect_identical(ref$pst_commit, unname(rPSTool:::.pst_engine_pin()[["pst_commit"]]))
  graphs <- lapply(ref$networks, function(rows) axial_graph(do.call(rbind, rows)))
  for (case in rpst_cases(ref$cases, every = 40L, by = list(rpst_case_signature), each = list(rpst_case_edges))) {
    g <- graphs[[case$network]]
    radius <- do.call(analysis_radius, case$radius)
    points <- if (is.null(case$points)) NULL else do.call(rbind, case$points)
    if (case$routine == "reach") {
      out <- network_reach(g, radius, points)
      expect_identical(out$origin_id, seq_len(nrow(points)))
      expect_identical(out$reached_count, as.integer(case$count))
      origin_near(out$reached_length, case$score)
      origin_near(out$reached_area, case$depth)
    } else {
      out <- network_betweenness(g, radius, case$distance, weights = case$weights,
                            attraction_points = points)
      expect_identical(out$line_id, seq_along(case$count))
      expect_identical(out$node_count, as.integer(case$count))
      origin_near(out$betweenness, case$score)
      origin_near(out$total_depth, case$depth)
      for (norm in names(case$normalizations)) {
        normalized <- network_betweenness(g, radius, case$distance, norm,
                                      case$weights, points)
        expect_identical(normalized[names(out)], out)
        origin_near(normalized$normalized, case$normalizations[[norm]])
        if (norm != "standard")
          expect_identical(is.na(normalized$normalized),
                           is.na(out$node_count) | is.nan(normalized$normalized))
      }
    }
  }
})

test_that("zero and negative weights retain raw semantics and missing diagnostics", {
  g <- axial_graph(origin_chain())
  for (distance in c("walking", "steps", "angular", "axmeter")) {
    for (weights in list(c(1,0,1), c(1,-1,1))) {
      raw <- network_betweenness(g, distance = distance, weights = weights)
      expect_identical(raw$betweenness, if (weights[2] == 0) c(0.75,1,0.75) else rep(0.5,3))
      expect_identical(raw$node_count, c(3L,NA_integer_,3L))
      expect_true(is.na(raw$total_depth[2]) && !is.nan(raw$total_depth[2]))
      for (i in 1:3) expect_identical(network_betweenness(g, distance = distance, weights = weights), raw)
      for (norm in c("standard", "freeman", "syntax")) {
        out <- network_betweenness(g, distance = distance, normalization = norm, weights = weights)
        expect_identical(out[names(raw)], raw)
        expect_identical(is.na(out$normalized), if (norm == "standard") rep(FALSE,3) else c(FALSE,TRUE,FALSE))
      }
    }
    unit <- network_betweenness(g, distance = distance, weights = wt_rep_1_3)
    plain <- network_betweenness(g, distance = distance)
    # Three unit lines add PST's endpoint (1) and self (0.25) contributions.
    expect_identical(unit$betweenness, plain$betweenness + 1.25)
    expect_identical(unit$node_count, plain$node_count)
    expect_identical(unit$total_depth, plain$total_depth)
    sparse <- network_betweenness(g, distance = distance, attraction_points = matrix(c(0.5,0),1))
    expect_identical(sparse$node_count, c(3L,NA_integer_,NA_integer_))
    expect_identical(is.na(sparse$total_depth), c(FALSE,TRUE,TRUE))
    zero <- network_betweenness(g, distance = distance, weights = wt_0,
                           attraction_points = matrix(c(0.5,0),1))
    expect_identical(zero$betweenness, rep(0,3))
    expect_identical(zero$node_count, rep(NA_integer_,3))
    expect_identical(zero$total_depth, rep(NA_real_,3))
    expect_identical(network_betweenness(g, distance = distance, weights = wt_0,
      attraction_points = matrix(c(0.5,0),1), normalization = "standard")$normalized, rep(1,3))
    for (norm in c("freeman", "syntax"))
      expect_identical(network_betweenness(g, distance = distance, weights = wt_0,
        attraction_points = matrix(c(0.5,0),1), normalization = norm)$normalized, rep(NA_real_,3))
  }
  single <- axial_graph(matrix(c(0,0,1,0),1))
  expect_identical(network_betweenness(single, weights = wt_2)$betweenness, 1)
  signed <- network_betweenness(g, weights = wt_c_1_10_1, normalization = "syntax")
  # A written normalizer NaN is distinct from rPSTool's missing skipped row.
  expect_identical(is.nan(signed$normalized), c(TRUE,FALSE,TRUE))
  expect_true(is.na(signed$normalized[2]) && !is.nan(signed$normalized[2]))
})

test_that("PST accumulates attractions and preserves paired row permutation", {
  g <- axial_graph(origin_chain())
  p <- rbind(c(0.25,0),c(0.75,0),c(2.5,0))
  for (distance in c("walking", "steps", "angular", "axmeter")) {
    implicit <- network_betweenness(g, distance = distance, attraction_points = p)
    expect_identical(implicit, network_betweenness(g, distance = distance, weights = wt_rep_1_3, attraction_points = p))
    expect_identical(implicit, network_betweenness(g, distance = distance, weights = wt_c_2_0_1))
    unequal <- network_betweenness(g, distance = distance, weights = wt_c_2_3_4, attraction_points = p)
    expect_identical(unequal, network_betweenness(g, distance = distance, weights = wt_c_5_0_4))
    order <- c(3L,1L,2L)
    wt_reordered <- c(2,3,4)[order]
    expect_identical(unequal, network_betweenness(g, distance = distance,
      weights = wt_reordered, attraction_points = p[order,]))
    away <- origin_points(); away[,2] <- c(2,-2)
    expect_identical(network_betweenness(g, distance = distance, attraction_points = away),
                     network_betweenness(g, distance = distance, attraction_points = origin_points()))
  }
})

test_that("point Reach retains strict boundary, circle area and input row order", {
  g <- axial_graph(origin_chain())
  p <- rbind(c(-0.4999,0),c(-0.5,0),c(-0.5001,0))
  out <- network_reach(g, analysis_radius(straight = 1), p)
  expect_identical(out$origin_id, 1:3)
  expect_identical(out$reached_count, c(1L,0L,0L))
  expect_identical(out$reached_length, c(1,0,0))
  expect_equal(out$reached_area, rep(pi,3), tolerance = 1e-6)
  expect_identical(network_reach(g, analysis_radius(straight=0), matrix(c(0.5,0),1))$reached_count, 0L)
  expect_identical(network_reach(g, analysis_radius(straight=0))$reached_count, rep(1L,3))
  expect_identical(network_reach(g, analysis_radius(straight=1))$reached_count, c(2L,3L,2L))
  p <- rbind(c(2.5,0), c(0.5,0), c(0.5,2))
  for (radius in list(analysis_radius(), analysis_radius(walking=1), analysis_radius(steps=1),
                     analysis_radius(angular=0), analysis_radius(axmeter=2), analysis_radius(straight=1,steps=1))) {
    out <- network_reach(g, radius, p)
    order <- c(3L,1L,2L)
    permuted <- network_reach(g, radius, p[order,])
    expect_identical(permuted$origin_id, 1:3)
    for (name in names(out)[-1]) expect_identical(permuted[[name]], out[[name]][order])
  }
  expect_identical(network_reach(g, analysis_radius(walking=0), matrix(c(0.5,2),1))$reached_count, 0L)
})

test_that("point and weight validation fails closed in the native boundary", {
  g <- axial_graph(origin_chain())
  valid <- matrix(c(0.5,0),1)
  point_calls <- list(
    function(x) network_reach(g, origins=x),
    function(x) network_betweenness(g, attraction_points=x),
    function(x) origin_native("reach_points",g$ptr,analysis_radius(),x),
    function(x) origin_native("betweenness_weighted",g$ptr,analysis_radius(),"steps","none",NULL,x))
  invalid <- list(1, list(x=1,y=2), data.frame(x=1,y=2), matrix("x",1,2),
    matrix(TRUE,1,2), matrix(1+1i,1,2), array(1,c(1,2,1)), matrix(0,0,2),
    matrix(0,1,1), matrix(0,1,3), matrix(0,1,4))
  for (bad in invalid) for (fn in point_calls) expect_error(fn(bad), "numeric matrix|at least one row")
  for (value in c(NA_real_,NaN,Inf,-Inf)) {
    bad <- valid; bad[1,2] <- value
    for (fn in point_calls) expect_error(fn(bad), "finite")
  }
  bad <- matrix(NA_integer_,1,2)
  for (fn in point_calls) expect_error(fn(bad), "finite")
  for (value in c(1e20,-1e20,1e40,-1e40,.Machine$double.xmax)) {
    bad <- valid; bad[1,1] <- value
    for (fn in point_calls) expect_error(fn(bad), "overflow")
  }
  for (points in list(NULL,valid)) {
    n <- if (is.null(points)) 3L else 1L
    weight_calls <- list(
      function(w) network_betweenness(g,weights=w,attraction_points=points),
      function(w) origin_native("betweenness_weighted",g$ptr,analysis_radius(),"steps","none",w,points))
    for (bad in list("1",TRUE,list(1),1+1i))
      for (fn in weight_calls) expect_error(fn(bad), "numeric storage")
    for (bad in list(numeric(),rep(1,n+1),rep(1,n-1)))
      for (fn in weight_calls) expect_error(fn(bad), "exactly one value")
    for (value in c(NA_real_,NaN,Inf,-Inf))
      for (fn in weight_calls) expect_error(fn(rep(value,n)), "finite")
    for (value in c(1e40,-1e40,1e-100,-1e-100))
      for (fn in weight_calls) expect_error(fn(rep(value,n)), "overflow or underflow")
    for (fn in weight_calls) expect_error(fn(rep(NA_integer_,n)), "finite")
  }
  # Valid integer and ALTREP-backed inputs are materialized before C++ buffers.
  p <- matrix(0:3,2,2)
  expect_identical(network_reach(g,origins=p),network_reach(g,origins=p*1.0))
  named <- p; colnames(named) <- c("y", "x")
  expect_identical(network_reach(g,origins=named),network_reach(g,origins=p))
  expect_identical(network_betweenness(g,attraction_points=named),network_betweenness(g,attraction_points=p))
  expect_identical(network_betweenness(g,weights=wt_1_3),network_betweenness(g,weights=wt_c_1_2_3))
  expect_identical(network_betweenness(g,weights=wt_c_1_1_1),network_betweenness(g,weights=wt_c_1l_1l_1l))
  # A representable subnormal weight is allowed; only narrowing to zero fails.
  expect_no_error(network_betweenness(g,weights=wt_rep_1e_45_3))
  expect_no_error(network_betweenness(g,weights=wt_rep_m1e_45_3))
  # Points are independent: their mutual distance need not fit native float
  # squared storage when each point/network extent does fit.
  distant <- rbind(c(1e19,0),c(-1e19,0))
  expect_identical(network_reach(g,analysis_radius(straight=1),distant)$reached_count,c(0L,0L))
  expect_no_error(network_betweenness(g,attraction_points=distant))
  offset <- 1e14
  shifted <- axial_graph(origin_chain()+offset)
  expect_identical(network_reach(shifted,origins=origin_points()+offset),network_reach(g,origins=origin_points()))
  expect_identical(network_betweenness(shifted,attraction_points=origin_points()+offset),network_betweenness(g,attraction_points=origin_points()))
})

test_that("optional modes retain exact graph-family tags, liveness and native counts", {
  a <- axial_graph(origin_chain()); s <- segment_graph(origin_chain())
  p <- origin_points()
  calls <- list(function(g) network_reach(g,origins=p),
                function(g) network_betweenness(g,weights=wt_c_1_0_1),
                function(g) network_betweenness(g,attraction_points=p))
  fake <- structure(list(ptr=s$ptr,type="axial",n_lines=3L),class="pst_graph")
  for (fn in calls) {
    expect_error(fn(s),"live axial pst_graph")
    expect_error(fn(fake),"Invalid pst_graph native pointer")
    expect_error(fn(unserialize(serialize(a,NULL))),"no longer live")
  }
  for (ptr in list(s$ptr,NULL,1,new("externalptr"))) {
    expect_error(origin_native("reach_points",ptr,analysis_radius(),p),"Invalid pst_graph native pointer")
    expect_error(origin_native("betweenness_weighted",ptr,analysis_radius(),"steps","none",c(1,0,1),p),"Invalid pst_graph native pointer")
  }
  raw <- network_betweenness(a,weights=wt_c_1_0_1)
  a$n_lines <- 999L; a$n_crossings <- -1L; a$pst_version <- "forged"
  expect_identical(network_betweenness(a,weights=wt_c_1_0_1),raw)
  expect_error(network_betweenness(a,weights=wt_rep_1_999),"exactly one value")
  origin_native("graph_release",a$ptr)
  for (fn in calls) expect_error(fn(a),"no longer live")
  origin_native("graph_release",a$ptr) # repeated release is safe
})

test_that("optional results and graphs have independent lifetime and reusable storage", {
  gc(); before <- origin_native("graph_lifecycle")
  lines <- origin_chain(); points <- origin_points(); weights <- c(1,0,1)
  g <- axial_graph(lines); ptr <- g$ptr
  reach <- network_reach(g,origins=points)
  weighted <- network_betweenness(g,weights=weights,normalization="syntax")
  attraction <- network_betweenness(g,attraction_points=points,normalization="freeman")
  for (i in 1:5) {
    expect_identical(network_reach(g,origins=points),reach)
    expect_identical(network_betweenness(g,weights=weights,normalization="syntax"),weighted)
    expect_identical(network_betweenness(g,attraction_points=points,normalization="freeman"),attraction)
    gc()
  }
  expect_identical(g$ptr,ptr)
  saved <- serialize(list(reach,weighted,attraction),NULL)
  rm(g,ptr,lines,points,weights); gc()
  expect_identical(serialize(list(reach,weighted,attraction),NULL),saved)
  expect_identical(origin_native("graph_lifecycle")-before,c(1,1,0))
  # NULL modes are identical to the old native entry points, including bytes.
  g <- axial_graph(origin_chain())
  expect_identical(serialize(network_reach(g),NULL),serialize(network_reach(g,origins=NULL),NULL))
  expect_identical(unname(as.list(network_reach(g)[-1])),origin_native("reach",g$ptr,analysis_radius()))
  for (distance in c("walking","steps","angular","axmeter"))
    for (norm in c("none","standard","freeman","syntax")) {
      old <- origin_native("betweenness",g$ptr,analysis_radius(),distance,norm)
      out <- network_betweenness(g,analysis_radius(),distance,norm)
      expect_identical(unname(as.list(out[-1])),old[seq_len(ncol(out)-1)])
      expect_identical(serialize(out,NULL),serialize(network_betweenness(g,analysis_radius(),distance,norm,NULL,NULL),NULL))
    }
})
